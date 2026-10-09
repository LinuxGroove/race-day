extends Node
## What the player has done (autoload: Progress): Time Trial bests and
## ghosts, the championship and the career in progress, and Racing School
## medals. Kept in user://progress.cfg, ghosts in user://ghosts/.

const PATH := "user://progress.cfg"
const GHOSTS := "user://ghosts/"
## The player's id in single-player weekends (peer 1, seat 0).
const PLAYER_ID := 4

var _cfg := ConfigFile.new()
## Tests set this so they don't touch the player's save.
var save_path := PATH


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(save_path)


func save() -> void:
	_cfg.save(save_path)


# --- Time Trial ---------------------------------------------------------

func best_time(layout: String) -> float:
	return float(_cfg.get_value("time_trial", layout, 0.0))


## Records a valid lap. Returns true (and keeps its ghost) when it's a new best.
func record_time_trial(layout: String, lap: float, ghost: GhostLap, _assists := 0) -> bool:
	var best := best_time(layout)
	if best > 0.0 and lap >= best:
		return false
	_cfg.set_value("time_trial", layout, lap)
	save()
	if ghost:
		save_ghost(layout, ghost)
	return true


func save_ghost(layout: String, ghost: GhostLap) -> void:
	DirAccess.make_dir_recursive_absolute(GHOSTS)
	var f := FileAccess.open_compressed(GHOSTS + layout + ".ghost", FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f:
		f.store_var(ghost.to_dict())


func load_ghost(layout: String) -> GhostLap:
	var path := GHOSTS + layout + ".ghost"
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return null
	var d = f.get_var()
	return GhostLap.from_dict(d) if d is Dictionary else null


## Medals won in Time Trial: {layout: medal index}.
func time_trial_medals() -> Dictionary:
	var out := {}
	if not _cfg.has_section("time_trial"):
		return out
	for layout in _cfg.get_section_keys("time_trial"):
		var t := Circuits.track(layout) if not Circuits.info(layout).is_empty() else null
		if t:
			out[layout] = LapReference.medal_for(t, best_time(layout))
	return out


# --- Championship -------------------------------------------------------

## The championship in progress, or {}: {"calendar", "round", "laps",
## "difficulty", "qualifying", "team", "standings" {id: points},
## "names" {id: [name, code, team]}, "results" [[id, ...] per round]}.
func championship() -> Dictionary:
	return _cfg.get_value("championship", "state", {})


func start_championship(calendar: Array, laps: int, difficulty: float, qualifying: String) -> void:
	_cfg.set_value("championship", "state", {
		"calendar": calendar, "round": 0, "laps": laps, "difficulty": difficulty,
		"qualifying": qualifying, "team": Session.player_team(), "standings": {}, "team_points": {},
		"names": {}, "results": [], "seed": randi(),
	})
	save()


func end_championship() -> void:
	_cfg.set_value("championship", "state", {})
	save()


## The race config for the championship's next round.
func championship_config() -> Dictionary:
	var c := championship()
	return _season_config(c, "championship", int(c.get("team", Session.player_team())), {})


func record_championship_round(config: Dictionary, results: Array) -> void:
	var c := championship()
	if c.is_empty():
		return
	_score_round(c, results)
	_cfg.set_value("championship", "state", c)
	if int(c.round) >= c.calendar.size():
		var best := int(_cfg.get_value("championship", "best", 0))
		var pos := standing_of(c, PLAYER_ID)
		if best == 0 or pos < best:
			_cfg.set_value("championship", "best", pos)
	save()


func _season_config(c: Dictionary, mode: String, team: int, upgrades: Dictionary) -> Dictionary:
	var round := int(c.round)
	var layout: String = c.calendar[clampi(round, 0, c.calendar.size() - 1)]
	var people := [{"id": PLAYER_ID, "name": Session.player_name(), "team": team, "number": int(LGSettings.get_value("player", "number")), "peer": 1, "seat": 0}]
	var settings := {
		"circuit": layout, "laps": int(c.laps), "difficulty": float(c.difficulty),
		"qualifying": str(c.qualifying), "grid": GameConfig.GRID_SIZE, "weather": "random",
		"damage": 1, "tyre_wear": 1.0,
	}
	var config := Session.make_config(people, settings, mode, int(c.get("seed", 1)) + round * 7)
	config["round"] = round + 1
	config["rounds"] = c.calendar.size()
	config["upgrades"] = upgrades
	config["title"] = "Round %d: %s" % [round + 1, Circuits.info(layout).get("name", layout)]
	return config


func _score_round(c: Dictionary, results: Array) -> void:
	var st: Dictionary = c.standings
	var tp: Dictionary = c.team_points
	var names: Dictionary = c.names
	var order := []
	for r in results:
		var id := int(r.id)
		st[id] = int(st.get(id, 0)) + int(r.points)
		tp[int(r.team)] = int(tp.get(int(r.team), 0)) + int(r.points)
		names[id] = [str(r.name), str(r.code), int(r.team)]
		order.append(id)
	c.results.append(order)
	c.round = int(c.round) + 1


## Standings rows, leader first: [[id, points, name, code, team], ...].
func standings(c: Dictionary) -> Array:
	var rows := []
	for id in c.get("standings", {}):
		var n: Array = c.names.get(id, ["?", "???", 0])
		rows.append([int(id), int(c.standings[id]), n[0], n[1], n[2]])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]) if int(a[1]) != int(b[1]) else int(a[0]) < int(b[0]))
	return rows


func standing_of(c: Dictionary, id: int) -> int:
	var rows := standings(c)
	for i in rows.size():
		if int(rows[i][0]) == id:
			return i + 1
	return 0


# --- Career -------------------------------------------------------------

## The career: {"season", "team", "upgrades" {engine, aero, brakes},
## "dev" (development points toward the next upgrade), "offers" [team],
## "season_state" (a championship dict), "history" [[season, team, place]]}.
func career() -> Dictionary:
	return _cfg.get_value("career", "state", {})


func start_career(laps: int, difficulty: float) -> void:
	var c := {
		"season": 1, "team": Teams.team_index("tankco"),
		"upgrades": {"engine": 0, "aero": 0, "brakes": 0}, "dev": 0, "offers": [],
		"laps": laps, "difficulty": difficulty, "history": [],
	}
	c["season_state"] = _new_season(c)
	_cfg.set_value("career", "state", c)
	save()


func _new_season(c: Dictionary) -> Dictionary:
	var cal := Array(Circuits.calendar())
	if cal.is_empty():
		cal = Array(Circuits.ids())
	return {
		"calendar": cal, "round": 0, "laps": int(c.laps),
		"difficulty": float(c.difficulty), "qualifying": "one_lap", "standings": {},
		"team_points": {}, "names": {}, "results": [], "seed": randi(),
	}


func career_config() -> Dictionary:
	var c := career()
	return _season_config(c.season_state, "career", int(c.team), c.upgrades)


func record_career_round(config: Dictionary, results: Array) -> void:
	var c := career()
	if c.is_empty():
		return
	var s: Dictionary = c.season_state
	_score_round(s, results)
	# The team develops the car: more with points, never past level 5.
	var mine := {}
	for r in results:
		if int(r.id) == PLAYER_ID:
			mine = r
	c.dev = int(c.dev) + 1 + int(mine.get("points", 0)) / 6
	var parts := ["engine", "aero", "brakes"]
	while int(c.dev) >= 3:
		c.dev = int(c.dev) - 3
		var low: String = parts[0]
		for p in parts:
			if int(c.upgrades[p]) < int(c.upgrades[low]):
				low = p
		c.upgrades[low] = mini(5, int(c.upgrades[low]) + 1)
	if int(s.round) >= s.calendar.size():
		c.offers = _offers(c, s)
	c.season_state = s
	_cfg.set_value("career", "state", c)
	save()


## Teams that want the player after a season: better teams call when the
## player beat their team-mate and scored well.
func _offers(c: Dictionary, s: Dictionary) -> Array:
	var place := standing_of(s, PLAYER_ID)
	var mate := 99
	for r in standings(s):
		if int(r[4]) == int(c.team) and int(r[0]) != PLAYER_ID:
			mate = standing_of(s, int(r[0]))
	var out := []
	var reach := 0
	if place < mate:
		reach += 2
	if place <= 10:
		reach += 2
	if place <= 5:
		reach += 3
	if place <= 2:
		reach += 3
	# Teams are listed quickest first; the reach counts up from the back.
	for k in range(1, reach + 1):
		var t := Teams.TEAMS.size() - 1 - k
		if t >= 0 and t != int(c.team) and t < int(c.team):
			out.append(t)
	out.reverse()
	return out.slice(0, 3)


## Starts the next season, with a new team if the player took an offer.
func next_career_season(team := -1) -> void:
	var c := career()
	var s: Dictionary = c.season_state
	c.history.append([int(c.season), int(c.team), standing_of(s, PLAYER_ID)])
	if team >= 0 and team != int(c.team):
		c.team = team
		c.upgrades = {"engine": 0, "aero": 0, "brakes": 0}
	c.season = int(c.season) + 1
	c.offers = []
	c.season_state = _new_season(c)
	_cfg.set_value("career", "state", c)
	save()


func end_career() -> void:
	_cfg.set_value("career", "state", {})
	save()


# --- Racing School ------------------------------------------------------

func school_medal(test: String) -> int:
	return int(_cfg.get_value("school", test, -1))


## Keeps the best medal (0 gold, 1 silver, 2 bronze). Returns true if better.
func record_school(test: String, medal: int) -> bool:
	var had := school_medal(test)
	if medal < 0 or (had >= 0 and had <= medal):
		return false
	_cfg.set_value("school", test, medal)
	save()
	return true
