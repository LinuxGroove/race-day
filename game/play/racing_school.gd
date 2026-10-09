class_name RacingSchool
extends RefCounted
## The Racing School: short tests at the Proving Ground and on real circuits,
## each with bronze, silver and gold. A test is a stretch of road (or a lap)
## driven from a rolling start; the times to beat come from the AI driving
## the same stretch in the same car, so they fit every circuit.
##
## Kinds of test:
##   segment   drive from `from` to `to` without going off
##   lap       one clean lap from a flying start
##   overtake  pass the car ahead before the end of the stretch
##   pit       make a stop in your box and rejoin

## Medal thresholds over the AI's time: [gold, silver, bronze].
const SEGMENT_MEDALS := [1.02, 1.06, 1.12]
const LAP_MEDALS := [1.025, 1.06, 1.12]
const PIT_MEDALS := [1.06, 1.15, 1.3]
## Overtake margins in metres ahead at the end: [gold, silver, bronze].
const PASS_MEDALS := [70.0, 30.0, 0.0]

const NO_HELP := {"braking_line": "off", "braking_help": false, "steering_help": false}
const ALL_HELP := {"braking_line": "full", "braking_help": false, "steering_help": false, "abs": true, "tc": true, "gears": "auto"}

const TESTS := [
	{"id": "brake", "name": "Braking for a hairpin", "kind": "segment", "circuit": "proving",
		"where": "slowest", "lead": 380.0, "after": 120.0, "assists": ALL_HELP,
		"brief": "Brake where the line turns red, turn in, and accelerate out. Stay on the road."},
	{"id": "esses", "name": "The racing line", "kind": "segment", "circuit": "proving",
		"where": "esses", "lead": 220.0, "after": 140.0, "assists": ALL_HELP,
		"brief": "Follow the line through the corners: wide on the way in, clip the inside, wide on the way out."},
	{"id": "fast", "name": "A fast corner", "kind": "segment", "circuit": "proving",
		"where": "fastest", "lead": 300.0, "after": 160.0, "assists": ALL_HELP,
		"brief": "A quick corner needs only a lift or a dab of brake. Keep your speed up and stay smooth."},
	{"id": "no_help", "name": "A lap with no help", "kind": "lap", "circuit": "proving",
		"assists": NO_HELP,
		"brief": "One clean lap with no braking line and no help. Find your own braking points."},
	{"id": "pass", "name": "Make a pass", "kind": "overtake", "circuit": "proving",
		"where": "slowest", "lead": 600.0, "after": 300.0, "assists": ALL_HELP,
		"brief": "Catch the car ahead and get past before the end. Use its slipstream, then brake later."},
	{"id": "pit", "name": "A pit stop", "kind": "pit", "circuit": "greenfield",
		"assists": {"pit": false, "braking_line": "corners"},
		"brief": "Take the pit entry, press Limiter before the white line, stop in your box, and rejoin."},
	{"id": "wet", "name": "A wet lap", "kind": "lap", "circuit": "proving", "wet": 0.8,
		"assists": {"braking_line": "corners"},
		"brief": "The road is wet. Brake earlier, be gentle with the throttle, and bring it home."},
	{"id": "real", "name": "A lap of Greenfield Park", "kind": "lap", "circuit": "greenfield",
		"assists": NO_HELP,
		"brief": "A real circuit with no help. Bronze is a clean lap; gold is quick."},
]

static var _refs := {}

var scene: RaceScene
var test: Dictionary
var entry: Race.Entry
var rival: Race.Entry
## The stretch, as distances along the lap, and its length.
var from_s := 0.0
var length := 0.0
var elapsed := 0.0
var reference := 0.0
var done := false
var result := {}

var _start_total := 0.0
var _start_damage := 0.0
var _off := false
var _lap_started := false


static func find(id: String) -> Dictionary:
	for t in TESTS:
		if str(t.id) == id:
			return t
	return {}


## The circuit a test runs on: its own, or the Proving Ground if that circuit
## isn't built yet.
static func circuit_for(t: Dictionary) -> String:
	var c := str(t.get("circuit", "proving"))
	return c if not Circuits.info(c).is_empty() else "proving"


## Whether a test can run (a pit stop needs a pit lane).
static func available(t: Dictionary) -> bool:
	if str(t.kind) == "pit":
		return not Circuits.track(circuit_for(t)).pit.is_empty()
	return true


## Starts a test from the menus.
static func start(id: String) -> void:
	var t := find(id)
	if t.is_empty():
		return
	Session.start_solo()
	var people := [Session.local_people()[0]]
	var circuit := circuit_for(t)
	var config := Session.make_config(people, {"circuit": circuit, "grid": 1, "weather": "dry"}, "school")
	config.drivers = Grid.build(people, 1, 100.0)
	config.forecast = []
	config.wet = float(t.get("wet", 0.0))
	config.qualifying = "none"
	config.school = id
	config.title = str(t.name)
	Session.launch(config)


func _init(p_scene: RaceScene, id: String) -> void:
	scene = p_scene
	test = RacingSchool.find(id)


## Puts the car (and any rival) in place once the session's race exists.
func begin(p_entry: Race.Entry) -> void:
	entry = p_entry
	done = false
	result = {}
	elapsed = 0.0
	_off = false
	_lap_started = false
	var race := scene.race
	var track := race.track
	match str(test.kind):
		"segment", "overtake":
			var span := RacingSchool.stretch(track, test)
			from_s = span[0]
			length = span[1]
			RacingSchool.place(entry, track, from_s, 0.92)
			if str(test.kind) == "overtake":
				rival = race.add_car(-1, "Rival", entry.team, 1, 0.8, {"code": "RIV", "consistency": 1.0, "spec_team": LapReference.TEAM})
				rival.bot = true
				RacingSchool.place(rival, track, track.wrap_s(from_s + 35.0), 0.92)
				rival.s_total = entry.s_total + 35.0
		"pit":
			from_s = RacingSchool.on_straight(track, track.wrap_s(float(track.pit.entry) - 650.0))
			length = track.delta_s(from_s, float(track.pit.entry)) + track.delta_s(float(track.pit.entry), float(track.pit.exit)) + 150.0
			RacingSchool.place(entry, track, from_s, 0.92)
			entry.ai = null
		"lap":
			# The race's flying start: the lap begins at the line.
			length = track.length
	_start_total = entry.s_total
	_start_damage = entry.sim.damage
	reference = RacingSchool.reference_time(track, test)


## Places a car on the racing line at `s`, rolling at a share of the line's speed.
static func place(e: Race.Entry, track: Track, s: float, share: float) -> void:
	var lat := track.value_at(track.line_off, s)
	e.sim.place_moving(s, lat, track.value_at(track.line_speed, s) * share)
	e.s_total = s
	e.lap = 1
	e.lap_valid = true
	e.checkpoints.clear()


## The stretch of road a segment test covers: [start s, length].
static func stretch(track: Track, t: Dictionary) -> Array:
	var cs := track.corners
	if cs.is_empty():
		return [0.0, minf(800.0, track.length * 0.5)]
	var first := 0
	var last := 0
	match str(t.get("where", "slowest")):
		"slowest":
			for k in cs.size():
				if float(cs[k].peak) > float(cs[first].peak):
					first = k
			last = first
		"fastest":
			# The quickest real corner: the widest one that still needs a lift.
			var best := -1
			for k in cs.size():
				var r := float(cs[k].radius)
				if r < 260.0 and r > 70.0 and (best < 0 or r > float(cs[best].radius)):
					best = k
			first = maxi(best, 0)
			last = first
		"esses":
			# The run of corners packed closest together.
			var most := 0
			for k in cs.size():
				var n := 0
				for j in range(1, 4):
					var c2: Dictionary = cs[(k + j) % cs.size()]
					if track.delta_s(float(cs[k].start), float(c2.start)) > 0.0 and track.delta_s(float(cs[k].start), float(c2.start)) < 420.0:
						n = j
				if n > most:
					most = n
					first = k
			last = (first + maxi(most, 1)) % cs.size()
	var lead := float(t.get("lead", 300.0))
	var after := float(t.get("after", 140.0))
	var s0 := RacingSchool.on_straight(track, track.wrap_s(float(cs[first].start) - lead))
	var span := fposmod(float(cs[last].end) + after - s0, track.length)
	return [s0, span]


## A rolling start mustn't drop a car into the middle of a corner: a spot in
## one moves on to just past its exit.
static func on_straight(track: Track, s: float) -> float:
	for c in track.corners:
		var into := track.delta_s(float(c.start) - 40.0, s)
		if into >= 0.0 and track.delta_s(s, float(c.end)) >= 0.0:
			return track.wrap_s(float(c.end) + 80.0)
	return s


## The AI's time for a test in the Time Trial car, worked out once.
static func reference_time(track: Track, t: Dictionary) -> float:
	var key := "%s:%s" % [track.id, t.id]
	if _refs.has(key):
		return _refs[key]
	var race := Race.new(track, Race.Kind.PRACTICE, 99, 5)
	race.wetness = float(t.get("wet", 0.0))
	var e: Race.Entry = race.add_car(1, "Ref", LapReference.TEAM, 0, 1.0, {"consistency": 1.0})
	race.start()
	var time := 0.0
	match str(t.kind):
		"lap":
			while race.clock < track.length / 15.0 + 200.0:
				race.step(Race.DT)
				if e.lap >= 2:
					time = e.last_lap
					break
		"segment", "overtake", "pit":
			var s0 := 0.0
			var span := 0.0
			if str(t.kind) == "pit":
				s0 = on_straight(track, track.wrap_s(float(track.pit.entry) - 650.0))
				span = track.delta_s(s0, float(track.pit.entry)) + track.delta_s(float(track.pit.entry), float(track.pit.exit)) + 150.0
				e.ai.pit_request = true
			else:
				var st := stretch(track, t)
				s0 = st[0]
				span = st[1]
			place(e, track, s0, 0.92)
			var start := e.s_total
			race.time = 0.0
			while race.time < span / 8.0 + 60.0:
				race.step(Race.DT)
				if e.s_total - start >= span:
					time = race.time
					break
	if time <= 0.0:
		time = track.length / 50.0
	_refs[key] = time
	return time


## Medal times (or margins for a pass): [gold, silver, bronze].
func targets() -> Array:
	match str(test.kind):
		"overtake":
			return PASS_MEDALS
		"lap":
			return [reference * LAP_MEDALS[0], reference * LAP_MEDALS[1], reference * LAP_MEDALS[2]]
		"pit":
			return [reference * PIT_MEDALS[0], reference * PIT_MEDALS[1], reference * PIT_MEDALS[2]]
	return [reference * SEGMENT_MEDALS[0], reference * SEGMENT_MEDALS[1], reference * SEGMENT_MEDALS[2]]


## Follows the test each tick. Sets `done` and `result` when it ends.
func tick(dt: float) -> void:
	if done or entry == null:
		return
	var sim := entry.sim
	match str(test.kind):
		"lap":
			if entry.lap >= 1:
				_lap_started = true
				elapsed = scene.race.time - entry.lap_start
			if _lap_started and not entry.lap_valid:
				_finish(false, "Off the track: that lap doesn't count.")
			return
	elapsed += dt
	# The pit test is about the stop: the pit road leaves the track.
	if sim.wheels_out >= 4 and not sim.spot.in_pit and str(test.kind) != "pit":
		_off = true
		_finish(false, "Off the track. Keep two wheels on the road.")
		return
	if str(test.kind) == "overtake" and sim.damage - _start_damage > 0.08:
		_finish(false, "Too much contact. Pass cleanly.")
		return
	if str(test.kind) == "pit" and entry.penalty > 0.0:
		_finish(false, "Too fast in the pit lane. Press Limiter before the white line.")
		return
	if elapsed > maxf(reference * 2.5, 30.0):
		_finish(false, "Out of time.")
		return
	if entry.s_total - _start_total >= length:
		match str(test.kind):
			"overtake":
				var margin := entry.s_total - rival.s_total
				if margin <= 0.0:
					_finish(false, "Still behind. Get alongside before the braking zone.")
				else:
					_finish(true, "", margin)
			"pit":
				if entry.stops < 1:
					_finish(false, "You missed your box.")
				else:
					_finish(true)
			_:
				_finish(true)


## A lap test's lap is done (from the race's lap event).
func on_lap(ev: Dictionary) -> void:
	if done or str(test.kind) != "lap" or int(ev.id) != entry.id:
		return
	elapsed = float(ev.time)
	if bool(ev.valid):
		_finish(true)
	else:
		_finish(false, "Off the track: that lap doesn't count.")


func _finish(passed: bool, why := "", margin := 0.0) -> void:
	done = true
	var medal := -1
	var tg := targets()
	if passed:
		if str(test.kind) == "overtake":
			medal = 0 if margin >= float(tg[0]) else (1 if margin >= float(tg[1]) else 2)
		else:
			for i in 3:
				if elapsed <= float(tg[i]):
					medal = i
					break
			if medal < 0:
				why = "Too slow for bronze. Try again!"
	var better := Progress.record_school(str(test.id), medal) if medal >= 0 else false
	result = {"passed": medal >= 0, "medal": medal, "time": elapsed, "margin": margin, "why": why,
		"targets": tg, "kind": str(test.kind), "better": better}
