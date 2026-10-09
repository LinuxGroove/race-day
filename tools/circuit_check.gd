extends SceneTree
## Checks every circuit layout headless: how it builds, its shape, its pit
## lane and an AI lap round it, and optionally a short race.
##
##   godot --headless --path . -s tools/circuit_check.gd
##   CIRCUIT=greenfield_gp godot --headless --path . -s tools/circuit_check.gd
##   CIRCUIT=greenfield_gp,monte_gp RACE=1 godot --headless --path . -s tools/circuit_check.gd
##
## CIRCUIT picks layouts (comma separated; default every one but the Proving
## Ground, or "all"), RACE=1 adds a 2-lap 20-car race, RACE=only skips the
## solo lap, LAPS sets the race's laps, SEED its random seed, PIT=0 skips
## the pit stop on the solo run. It prints one block per layout and a table
## at the end, and exits 1 if any layout has a problem.

## Steeper than this (rise over run) is too steep, except where a layout
## says otherwise in its info ("max_slope").
const MAX_SLOPE := 0.10
## Track edges closer than this to another part of the track (metres).
const MIN_GAP := 6.0
## Pit entry and exit stretches bending tighter than this (metres).
const PIT_MIN_RADIUS := 500.0
## The upper road of a crossover clears the lower by at least this.
const CROSSOVER_CLEARANCE := 8.0


## Catches the build's errors and warnings.
class Catch extends Logger:
	var errors: Array = []
	var warnings: Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text := rationale if rationale != "" else code
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(text)
		else:
			errors.append(text)

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func clear() -> void:
		errors.clear()
		warnings.clear()


var _catch := Catch.new()
var _rows: Array = []
var _failed := 0


func _init() -> void:
	OS.add_logger(_catch)
	var want := OS.get_environment("CIRCUIT")
	var ids: Array = []
	for id in Circuits.ids():
		if want == "" and id == "proving":
			continue
		if want == "" or want == "all" or id in want.split(","):
			ids.append(id)
	var race_opt := OS.get_environment("RACE")
	for id in ids:
		_check(id, race_opt)
	print("")
	print("%-18s %-22s %-14s %6s %4s %3s %9s %7s %6s %s" % ["id", "circuit", "layout", "km", "crn", "drs", "lap", "wide", "race", "problems"])
	for r in _rows:
		print("%-18s %-22s %-14s %6.2f %4d %3d %9s %7.1f %6s %s" % [r.id, r.name, r.layout, r.km, r.corners, r.drs, _time(r.lap), r.wide, r.race, r.problems])
	print("Layouts: %d, with problems: %d" % [_rows.size(), _failed])
	quit(1 if _failed > 0 else 0)


func _check(id: String, race_opt: String) -> void:
	var info := Circuits.info(id)
	print("\n== %s: %s, %s ==" % [id, info.get("name", "?"), info.get("layout", "?")])
	var problems: Array = []
	_catch.clear()
	var plan := Circuits.plan(id)
	var t := Track.build(plan, id, "%s %s" % [info.get("name", id), info.get("layout", "")])
	for e in _catch.errors:
		problems.append("build error: " + str(e))
		print("  ERROR ", e)
	for w in _catch.warnings:
		print("  warning ", w)
	var row := {"id": id, "name": info.get("name", ""), "layout": info.get("layout", ""), "km": t.length / 1000.0, "corners": t.corners.size(), "drs": t.drs.size(), "lap": 0.0, "wide": 0.0, "race": "-", "problems": ""}
	print("  length %.0f m, %d corners, %d DRS zones, sectors at %.0f and %.0f m" % [t.length, t.corners.size(), t.drs.size(), t.sectors[0], t.sectors[1]])
	var solved := Track.solve_pieces(plan)
	var autos: Array = []
	for k in plan.pieces.size():
		if float(plan.pieces[k].length) < 0.0:
			autos.append("piece %d %.0f m" % [k, float(solved[k].length)])
	if not autos.is_empty():
		print("  AUTO straights: ", ", ".join(autos))
	var climb := 0.0
	for p in plan.pieces:
		climb += float(p.get("climb", 0.0))
	if absf(climb) > 0.5:
		print("  climbs add up to %.1f m (spread along the lap)" % climb)
	_shape(t, info, problems)
	_pit(t, problems)
	if race_opt != "only":
		_solo(t, row, problems, OS.get_environment("PIT") != "0")
	if race_opt != "":
		_race(t, row, problems)
	row.problems = "; ".join(problems)
	if not problems.is_empty():
		_failed += 1
		print("  PROBLEMS: ", row.problems)
	_rows.append(row)


## Heights, slopes, banking, parts of the track too close together or
## crossing, and the run-off left between them.
func _shape(t: Track, info: Dictionary, problems: Array) -> void:
	var lo := INF
	var hi := -INF
	var steep := 0.0
	var steep_s := 0.0
	var max_bank := 0.0
	for i in t.n:
		var y := t.pos[i].y
		lo = minf(lo, y)
		hi = maxf(hi, y)
		# Slope over 20 m, as a driver feels it.
		var k := maxi(1, int(round(10.0 / t.step)))
		var dy := t.pos[(i + k) % t.n].y - t.pos[posmod(i - k, t.n)].y
		var sl := absf(dy) / (2.0 * k * t.step)
		if sl > steep:
			steep = sl
			steep_s = i * t.step
		max_bank = maxf(max_bank, rad_to_deg(atan(absf(t.bank[i]))))
	print("  heights %.0f to %.0f m, steepest %.1f%% at %.0f m, banking up to %.1f deg" % [lo, hi, steep * 100.0, steep_s, max_bank])
	if steep > float(info.get("max_slope", MAX_SLOPE)) + 0.005:
		problems.append("slope %.1f%% at %.0f m" % [steep * 100.0, steep_s])
	# Other parts of the track nearby: crossings and near misses.
	var close_gap := INF
	var close_at := Vector2.ZERO
	var crossings := {}
	for i in t.n:
		var p := Vector2(t.pos[i].x, t.pos[i].z)
		for j in t.samples_near(p, t.half[i] + 40.0):
			if j <= i:
				continue
			var d := p.distance_to(Vector2(t.pos[j].x, t.pos[j].z))
			var ds := absf(t.delta_s(i * t.step, j * t.step))
			if ds < d * 1.5 + 40.0:
				continue
			var dy := absf(t.pos[i].y - t.pos[j].y)
			var gap := d - t.half[i] - t.half[j] - Track.KERB_WIDTH * 2.0
			if gap < 0.0 and d < (t.half[i] + t.half[j]) * 0.7:
				var key := "%d" % int(i * t.step / 100.0)
				if not crossings.has(key) or dy < float(crossings[key].dy):
					crossings[key] = {"s": i * t.step, "s2": j * t.step, "dy": dy}
			elif dy < 4.5 and gap < close_gap:
				close_gap = gap
				close_at = Vector2(i * t.step, j * t.step)
	var seen := {}
	for c in crossings.values():
		var k2 := "%d" % int(float(c.s2) / 100.0)
		if seen.has(k2):
			continue
		seen["%d" % int(float(c.s) / 100.0)] = true
		var deliberate: bool = t.feature_at(float(c.s)) in ["over", "under"] and t.feature_at(float(c.s2)) in ["over", "under"]
		print("  crossing at %.0f m and %.0f m, %.1f m apart in height%s" % [c.s, c.s2, c.dy, " (the crossover)" if deliberate else ""])
		if not deliberate:
			problems.append("the track crosses itself at %.0f m" % c.s)
		elif float(c.dy) < CROSSOVER_CLEARANCE:
			problems.append("crossover clears only %.1f m" % c.dy)
	if close_gap < INF:
		print("  closest other part of the track: %.1f m between edges (at %.0f m and %.0f m)" % [close_gap, close_at.x, close_at.y])
		if close_gap < MIN_GAP:
			problems.append("track %.1f m from itself at %.0f m" % [close_gap, close_at.x])
	# Corners whose outside run-off was squeezed by another part of the track.
	var squeezed: Array = []
	for c in t.corners:
		var outside := 1 if int(c.dir) > 0 else 0
		var w := INF
		var s := float(c.start)
		while t.delta_s(s, float(c.end)) > 0.0:
			w = minf(w, t.runoff_width(s, outside))
			s += t.step
		if w < 6.0 and t.plan.corner_outside.width > 6.0 and not (t.in_pit_range(float(c.apex))):
			squeezed.append("T%d %.0f m" % [c.number, w])
	if not squeezed.is_empty():
		print("  run-off squeezed on the outside of: ", ", ".join(squeezed))


## The pit lane: where it leaves and rejoins, and how much the track bends
## where cars cross over to it and back.
func _pit(t: Track, problems: Array) -> void:
	if t.pit.is_empty():
		print("  no pit lane")
		return
	var entry := float(t.pit.entry)
	var exit := float(t.pit.exit)
	var r_in := _tightest(t, entry - 120.0, float(t.pit.wall_in))
	var r_app := _tightest(t, entry - AiDriver.PIT_COMMIT, entry - 120.0)
	var r_out := _tightest(t, float(t.pit.wall_out), exit + 80.0)
	var r_rejoin := _tightest(t, exit + 80.0, exit + AiDriver.PIT_REJOIN)
	var r_grid := _tightest(t, -10.0 - 24.0 * 8.0, 30.0)
	print("  pit lane on the %s from %.0f to %.0f m: tightest radius approaching %s, into the lane %s, out %s, rejoining %s; grid %s" % [
		"left" if int(t.pit.side) > 0 else "right", entry, exit, _r(r_app), _r(r_in), _r(r_out), _r(r_rejoin), _r(r_grid)])
	if r_in < PIT_MIN_RADIUS:
		problems.append("pit entry bends (radius %.0f m)" % r_in)
	if r_out < PIT_MIN_RADIUS:
		problems.append("pit exit bends (radius %.0f m)" % r_out)
	if r_grid < 1000.0:
		problems.append("the grid bends (radius %.0f m)" % r_grid)


func _tightest(t: Track, from: float, to: float) -> float:
	var k := 0.0
	var s := from
	while s <= to:
		k = maxf(k, absf(t.value_at(t.curv, s)))
		s += t.step
	return 1.0 / maxf(k, 0.00001)


func _r(r: float) -> String:
	return "straight" if r > 5000.0 else "%.0f m" % r


## One AI car on its own at pace 1.0: two timed laps, where it runs wide,
## then (with a pit lane) a pit stop.
func _solo(t: Track, row: Dictionary, problems: Array, pit: bool) -> void:
	var race := Race.new(t, Race.Kind.PRACTICE, 99, 3)
	var e: Race.Entry = race.add_car(1, "Solo", 5, 0, 1.0, {})
	race.start()
	var wide := {}
	var worst := 0.0
	var invalid := 0
	var laps: Array = []
	var pit_stopped := false
	var pit_out := false
	var top := 0.0
	var spins := 0
	var spinning := false
	while race.clock < 600.0:
		race.step(Race.DT)
		for ev in race.drain_events():
			match str(ev.type):
				"lap":
					laps.append(float(ev.time))
				"lap_invalid":
					invalid += 1
				"pit_stop":
					pit_stopped = true
				"pit_done":
					pit_out = true
		top = maxf(top, e.sim.speed)
		var rel := absf(wrapf(e.sim.yaw - t.heading_at(e.sim.spot.s), -PI, PI))
		if rel > 1.2 and not spinning:
			spins += 1
		spinning = rel > 1.2
		if e.lap >= 1 and e.lap <= 2 and not e.sim.spot.in_pit:
			var over := absf(e.sim.spot.lat) - e.sim.spot.half
			if over > 0.5:
				var key := int(e.sim.spot.s / 50.0)
				if not wide.has(key) or over > float(wide[key]):
					wide[key] = over
				worst = maxf(worst, over)
		if laps.size() >= 2 and (not pit or t.pit.is_empty()):
			break
		if laps.size() == 2 and e.ai.pit_phase == AiDriver.PitPhase.NONE and not e.ai.pit_request and not pit_stopped:
			e.ai.pit_request = true
		# The lap into the pits and the lap out of them.
		if laps.size() >= 4:
			break
	if laps.size() < 2:
		problems.append("the AI didn't finish two laps (%d)" % laps.size())
		print("  AI solo: only %d laps in %.0f s, stuck at %.0f m" % [laps.size(), race.clock, e.sim.spot.s])
		return
	row.lap = minf(laps[0], laps[1])
	row.wide = worst
	print("  AI solo laps %s and %s, top speed %.0f km/h, %d invalid, %d spins" % [_time(laps[0]), _time(laps[1]), top * 3.6, invalid, spins])
	if spins > 0:
		problems.append("the AI spun %d times" % spins)
	if not wide.is_empty():
		var spots: Array = []
		var keys: Array = wide.keys()
		keys.sort()
		for k in keys:
			var s := (int(k) + 0.5) * 50.0
			var c := t.next_corner(s)
			spots.append("%.0f m%s %.1f m" % [s, (" (T%d)" % int(c.number)) if not c.is_empty() else "", wide[k]])
		print("  runs wide: ", ", ".join(spots))
		if worst > 1.5:
			problems.append("the AI runs %.1f m wide" % worst)
	if pit:
		if t.pit.is_empty():
			pass
		elif pit_stopped and pit_out and laps.size() >= 4:
			var lost := float(laps[2]) + float(laps[3]) - 2.0 * float(row.lap)
			print("  pit stop: in lap %s, out lap %s, %.1f s lost" % [_time(laps[2]), _time(laps[3]), lost])
		else:
			problems.append("the AI's pit stop failed (stopped %s, out %s)" % [pit_stopped, pit_out])
			print("  pit stop failed: stopped %s, out %s, at %.0f m lat %.1f" % [pit_stopped, pit_out, e.sim.spot.s, e.sim.spot.lat])


## A 2-lap race with the full field.
func _race(t: Track, row: Dictionary, problems: Array) -> void:
	var laps := int(OS.get_environment("LAPS")) if OS.get_environment("LAPS") != "" else 2
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	var race := Race.new(t, Race.Kind.RACE, laps, seed)
	for k in Teams.DRIVERS.size():
		var d: Dictionary = Teams.DRIVERS[k]
		var pace := clampf(0.86 + float(d.skill) * 0.14, 0.9, 1.0)
		race.add_car(k + 1, str(d.name), int(d.team), k, pace, {"code": d.code, "nat": d.nat})
	race.start()
	var contacts := 0
	var hard := 0
	var retired: Array = []
	var penalties := 0
	while not race.is_over() and race.clock < 200.0 + laps * 200.0:
		race.step(Race.DT)
		for ev in race.drain_events():
			match str(ev.type):
				"contact":
					contacts += 1
					if float(ev.speed) > 7.0:
						hard += 1
				"retired":
					var e: Race.Entry = race.entry(int(ev.id))
					var c := t.next_corner(e.sim.spot.s)
					retired.append("%s (lap %d, %.0f m%s, %.0f s)" % [e.code, e.lap, e.sim.spot.s, (" T%d" % int(c.number)) if not c.is_empty() else "", race.time])
				"penalty":
					penalties += 1
	var finished := 0
	for e in race.entries:
		if e.finished and not e.retired:
			finished += 1
	var res := race.results()
	var winner: Dictionary = res[0] if not res.is_empty() else {}
	print("  race (%d laps): %d of %d finished%s, %d contacts (%d hard), %d penalties, winner %s in %s, over %s" % [
		laps, finished, race.entries.size(), "" if race.is_over() else " (NOT OVER)", contacts, hard, penalties,
		winner.get("code", "?"), _time(float(winner.get("time", 0.0))), "yes" if race.is_over() else "no"])
	if not retired.is_empty():
		print("  retired: ", ", ".join(retired))
	row.race = "%d/%d" % [finished, race.entries.size()]
	if finished < race.entries.size() - 2 or not race.is_over():
		problems.append("only %d finished the race" % finished)


static func _time(t: float) -> String:
	if t <= 0.0:
		return "-"
	return "%d:%06.3f" % [int(t / 60.0), fmod(t, 60.0)]
