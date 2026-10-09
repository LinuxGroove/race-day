class_name Grid
extends RefCounted
## Who drives in a session: the people (each in their team's car, taking an
## AI driver's seat) and the AI drivers filling the rest of the grid, with
## their pace for the difficulty.
##
## A driver: {"id", "name", "code", "nat", "team", "number", "bot", "peer",
## "seat", "pace", "aggression", "consistency", "skill"}. People keep their
## actor ids (peer * 4 + seat); AI drivers get negative ids.


## `people`: [{"id", "name", "team", "number", "peer", "seat"}], `size` the
## grid's size, `difficulty` 0 to 110. Returns drivers in grid order (an
## estimate of pace with a little shuffle, as if qualifying had happened).
static func build(people: Array, size: int, difficulty: float, seed := 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var seats := {}
	for t in Teams.TEAMS.size():
		seats[t] = []
	for i in Teams.DRIVERS.size():
		var d: Dictionary = Teams.DRIVERS[i]
		seats[int(d.team)].append(i)
	var out := []
	# People first: each takes the slower seat in their team, then the other,
	# then a seat in the next team with room.
	for p in people:
		var team := clampi(int(p.get("team", 9)), 0, Teams.TEAMS.size() - 1)
		var tries := 0
		while seats[team].is_empty() and tries < Teams.TEAMS.size():
			team = (team + Teams.TEAMS.size() - 1) % Teams.TEAMS.size()
			tries += 1
		if seats[team].is_empty():
			break
		var list: Array = seats[team]
		list.sort_custom(func(a, b): return float(Teams.DRIVERS[a].skill) > float(Teams.DRIVERS[b].skill))
		list.pop_back()
		var name := str(p.get("name", "Player"))
		out.append({
			"id": int(p.id), "name": name, "code": code_for(name), "nat": str(p.get("nat", "")),
			"team": team, "number": int(p.get("number", 21)), "bot": false,
			"peer": int(p.get("peer", 1)), "seat": int(p.get("seat", 0)),
			"pace": -1.0, "aggression": 0.5, "consistency": 1.0, "skill": 1.0,
		})
	# AI drivers in the seats left, fastest first, as many as fit.
	var ai := []
	for t in seats:
		for i in seats[t]:
			ai.append(i)
	ai.sort_custom(func(a, b): return _strength(a) > _strength(b))
	var room := maxi(0, size - out.size())
	# A short grid keeps a spread of teams: drop from the middle and back.
	while ai.size() > room:
		ai.remove_at(ai.size() - 1 - (ai.size() % 3))
	for i in ai:
		var d: Dictionary = Teams.DRIVERS[i]
		var traits: Array = d.traits
		out.append({
			"id": -(i + 1), "name": str(d.name), "code": str(d.code), "nat": str(d.nat),
			"team": int(d.team), "number": int(Teams.NUMBERS[i]), "bot": true,
			"peer": 0, "seat": 0,
			"pace": Teams.ai_pace(float(d.skill), difficulty),
			"aggression": 0.65 if "defend" in traits else 0.5,
			"consistency": clampf(0.78 + (float(d.skill) - 0.85) * 1.2, 0.75, 0.96),
			"skill": float(d.skill),
		})
	# Grid order: the quickest cars at the front, with some shuffle; people
	# start where a car like theirs would.
	var keyed := []
	for d in out:
		var k := _team_speed(int(d.team)) + (float(d.skill) - 0.9) * 0.4 + rng.randf_range(-0.012, 0.012)
		keyed.append([k, d])
	keyed.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var ordered := []
	for k in keyed:
		ordered.append(k[1])
	return ordered


static func _strength(i: int) -> float:
	var d: Dictionary = Teams.DRIVERS[i]
	return _team_speed(int(d.team)) + (float(d.skill) - 0.9) * 0.4


## A team's car, as one number (higher is quicker).
static func _team_speed(team: int) -> float:
	var t := Teams.team(team)
	return (float(t.engine) - 1.0) * 0.6 + (float(t.aero) - 1.0) * 0.6


## A three-letter code from a name ("Sam Carter" -> "CAR", "Ken" -> "KEN").
static func code_for(name: String) -> String:
	var parts := name.strip_edges().split(" ", false)
	var base := parts[parts.size() - 1] if parts.size() > 0 else "YOU"
	var letters := ""
	for ch in base.to_upper():
		if ch >= "A" and ch <= "Z":
			letters += ch
	while letters.length() < 3:
		letters += "X"
	return letters.left(3)


## An AI lap time estimate for qualifying and Time Trial medals: `ref` is a
## lap by the reference car at pace 1.0.
static func estimate_lap(ref: float, driver: Dictionary, rng: RandomNumberGenerator, wet := 0.0) -> float:
	var pace := float(driver.pace)
	var t := ref / maxf(pace, 0.5)
	# The team's car against the reference car (Solaris, a midfield car).
	t *= 1.0 - (_team_speed(int(driver.team)) - _team_speed(5)) * 0.9
	var idx := -int(driver.id) - 1
	if idx >= 0 and idx < Teams.DRIVERS.size() and "quali" in Teams.DRIVERS[idx].traits:
		t *= 0.998
	t *= 1.0 + rng.randf_range(-0.003, 0.004) + wet * rng.randf_range(0.0, 0.01)
	return t
