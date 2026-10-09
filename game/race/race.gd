class_name Race
extends RefCounted
## One session on track: a race, a qualifying lap, a Time Trial run or a
## Racing School test. No nodes: Session.gd's game scene calls step() on the
## physics tick, and tests run whole races headless the same way.
##
## It owns the cars' physics, the AI, the start lights, laps and sectors,
## positions and gaps, slipstream and DRS, pit stops, track limits, flags,
## the virtual safety car, retirements and the final classification. The
## view and the HUD read it and drain `events`.

enum Kind { RACE, QUALIFYING, TIME_TRIAL, PRACTICE, SCHOOL }
enum Phase { GRID, LIGHTS, RACING, FINISHED }

## One car in the session.
class Entry:
	var id := 0
	var name := ""
	var code := ""
	var nat := ""
	var team := 0
	var number := 0
	var sim: CarSim
	var input := CarInput.new()
	## The AI driving this car, or null for a person.
	var ai: AiDriver
	## A person on another device: their own device runs the physics and
	## sends the state; this race only places the car.
	var remote := false
	## The device and seat driving this car (multiplayer).
	var peer := 0
	var seat := 0
	var bot := true
	var lap := 0
	var lap_start := 0.0
	var last_lap := 0.0
	var best_lap := 0.0
	var lap_valid := true
	var sector_start := 0.0
	var sectors := [0.0, 0.0, 0.0]
	var best_sectors := [0.0, 0.0, 0.0]
	var last_sectors := [0.0, 0.0, 0.0]
	var sector := 0
	var s_total := 0.0
	var position := 0
	var gap := 0.0
	var interval := 0.0
	var laps_down := 0
	var finished := false
	var finish_time := 0.0
	var retired := false
	var retire_t := 0.0
	var penalty := 0.0
	var warnings := 0
	var stops := 0
	var compounds := []
	var next_compound := Tyres.HARD
	var in_pit_lane := false
	var pit_stop_t := 0.0
	var speeding := false
	var drs_ok := false
	var blue := false
	var grid_pos := Vector2.ZERO
	var grid_slot := 0
	var last_corner := -1
	var checkpoints := {}
	var start_position := 0
	var overtakes := 0
	var points := 0
	var stalled_t := 0.0
	## A retired car moved off the track: out of the way of everyone.
	var cleared := false

const DT := 1.0 / 120.0
const LIGHT_INTERVAL := 1.0
const CHECKPOINT := 50.0
const MAX_WARNINGS := 3
const LIMITS_PENALTY := 5.0
const SPEEDING_PENALTY := 5.0
const BASE_STOP := 2.4
const WING_CHANGE := 6.0
## The AI drivers think every this many physics ticks.
const AI_EVERY := 3
## Positions and gaps update every this many ticks.
const ORDER_EVERY := 6
## Seconds before the marshals clear a stopped, retired car.
const RECOVERY_TIME := 4.0
## After the leader finishes, others get this long to cross the line.
const FINISH_GRACE := 120.0

var track: Track
var kind := Kind.RACE
var laps := 5
var phase := Phase.GRID
var time := 0.0
var clock := 0.0
var lights := 0
var _lights_t := 0.0
var _lights_hold := 1.0
var entries: Array = []
## Entries in running order.
var order: Array = []
## 0 dry to 1 soaked.
## How wet the road is (0 dry to 1 soaked) and how hard it's raining now.
var wetness := 0.0
var rain := 0.0
## The weather through the session: [[time in seconds, rain 0 to 1], ...],
## from lights out (or the start of a non-race session).
var forecast: Array = []
var _wet_step := -1
var damage := 2
var tyre_wear := 1.0
var vsc := false
var vsc_t := 0.0
var drs_enabled := true
var mandatory_compounds := false
var fastest := {"id": 0, "time": 0.0, "lap": 0}
var leader_finished_t := -1.0
## The only rules a client runs are its own car's physics: the host owns
## laps, flags and results (see apply_status).
var authority := true
## Keeps the cars on the grid until every device is ready (multiplayer).
var hold_start := false
## [{type, ...}] for the HUD and sound; drained by the view each frame.
var events: Array = []
var rng := RandomNumberGenerator.new()
## Flags by sector for yellow flags.
var yellow := [false, false, false]
## Cached speed profiles per team and weather.
var _speeds := {}
var _drs_said := false
var _tick := 0
## Distance along the lap from each car to each other car (n x n).
var _gaps := PackedFloat32Array()


func _init(p_track: Track = null, p_kind := Kind.RACE, p_laps := 5, seed := 1) -> void:
	track = p_track
	kind = p_kind
	laps = p_laps
	rng.seed = seed


## Adds a car. `slot` is its grid slot (0 is pole).
func add_car(id: int, name: String, team: int, slot: int, ai_pace := -1.0, opts := {}) -> Entry:
	var e := Entry.new()
	e.id = id
	e.name = name
	e.code = str(opts.get("code", name.left(3).to_upper()))
	e.nat = str(opts.get("nat", ""))
	e.team = team
	e.number = int(opts.get("number", id))
	e.bot = ai_pace >= 0.0
	# Time Trial puts everyone in the same car ("spec_team").
	var spec := Teams.spec_for(int(opts.get("spec_team", team)), opts.get("upgrades", {}))
	spec.apply_setup(opts.get("setup", CarSpec.PRESETS.balanced))
	e.sim = CarSim.new(spec, track)
	e.sim.compound = int(opts.get("compound", Tyres.MEDIUM if wetness < 0.3 else Tyres.INTER))
	e.sim.wetness = wetness
	e.sim.wear_scale = tyre_wear
	e.sim.damage_scale = [0.0, 0.35, 1.0][clampi(damage, 0, 2)]
	e.compounds = [e.sim.compound]
	e.next_compound = _second_compound(e.sim.compound)
	if ai_pace >= 0.0:
		e.ai = AiDriver.new(e.sim, speeds_for(team), id * 7919 + rng.randi() % 1000)
		e.ai.pace = ai_pace
		e.ai.profile_grip = reference_grip()
		e.ai.aggression = float(opts.get("aggression", 0.5))
		e.ai.consistency = float(opts.get("consistency", 0.85))
		e.ai.box_s = box_for(team)
	e.grid_slot = slot
	_place_on_grid(e)
	entries.append(e)
	order.append(e)
	return e


## The car's speed profile along the line for a team in this weather.
func speeds_for(team: int) -> PackedFloat32Array:
	var key := "%d:%.1f" % [team, wetness]
	if not _speeds.has(key):
		_speeds[key] = RacingLine.speeds(track, Teams.spec_for(team), reference_grip())
	return _speeds[key]


## The tyre grip the AI's speed profiles are worked out for.
func reference_grip() -> float:
	var w := snappedf(wetness, 0.1)
	return Tyres.grip(Tyres.MEDIUM if w < 0.3 else Tyres.INTER, w, 0.15, 1.0)


## The pit box for a team, as a distance along the lap.
func box_for(team: int) -> float:
	if track.pit.is_empty():
		return 0.0
	var boxes: Array = track.pit.boxes
	return track.wrap_s(float(boxes[clampi(team, 0, boxes.size() - 1)]))


func _place_on_grid(e: Entry) -> void:
	match kind:
		Kind.RACE:
			var g: Dictionary = track.grid[clampi(e.grid_slot, 0, track.grid.size() - 1)]
			e.sim.place(float(g.s), float(g.lat))
			e.grid_pos = Vector2(e.sim.pos.x, e.sim.pos.z)
			# Grid slots are behind the line: the first crossing starts lap 1.
			e.s_total = track.delta_s(0.0, e.sim.spot.s)
			e.lap = 0
		_:
			# A flying start: rolling towards the line at a good speed.
			var back := 420.0 + e.grid_slot * 120.0
			var s := track.wrap_s(-back)
			var lat := track.value_at(track.line_off, s)
			e.sim.place_moving(s, lat, track.value_at(track.line_speed, s) * 0.7)
			e.s_total = -back
			e.lap = 0
	e.checkpoints.clear()


## Starts the session: a race goes to the lights, the others straight to running.
func start() -> void:
	if kind == Kind.RACE:
		phase = Phase.GRID
		lights = 0
		_lights_t = 0.0
		_lights_hold = rng.randf_range(0.4, 2.6)
		for e in entries:
			e.start_position = e.grid_slot + 1
		_events("grid")
	else:
		phase = Phase.RACING
	_update_order()


func entry(id: int) -> Entry:
	for e in entries:
		if e.id == id:
			return e
	return null


## Advances the session by dt seconds (call with DT steps).
func step(dt: float) -> void:
	clock += dt
	if not authority:
		# Another device runs the rules: the phase, lights and timing arrive
		# from there. This copy only drives its own cars.
		if phase == Phase.RACING or phase == Phase.FINISHED:
			time += dt
		var waiting := phase == Phase.GRID or phase == Phase.LIGHTS
		if waiting:
			_hold_on_grid()
		_drive_cars(dt, waiting)
		if not waiting:
			_contacts()
		return
	match phase:
		Phase.GRID:
			_hold_on_grid()
			if clock > 2.0 and not hold_start:
				phase = Phase.LIGHTS
				_lights_t = 0.0
		Phase.LIGHTS:
			_lights_t += dt
			var want := mini(5, int(_lights_t / LIGHT_INTERVAL) + 1)
			if want != lights:
				lights = want
				_events("light", {"n": lights})
			if _lights_t >= 5.0 * LIGHT_INTERVAL + _lights_hold:
				lights = 0
				phase = Phase.RACING
				time = 0.0
				_events("lights_out")
				for e in entries:
					e.lap_start = 0.0
					e.sector_start = 0.0
		Phase.RACING, Phase.FINISHED:
			time += dt
	if phase == Phase.GRID or phase == Phase.LIGHTS:
		_drive_cars(dt, true)
		return
	_drive_cars(dt, false)
	_contacts()
	if authority:
		_rules(dt)


func _hold_on_grid() -> void:
	for e in entries:
		e.sim.vel = Vector2.ZERO
		e.sim.yaw_rate = 0.0


## Drives every local car one tick: AI fills its input, people's input was
## set before step(). On the grid the cars are held on their brakes. Each AI
## thinks every AI_EVERY ticks (40 Hz is plenty for a driver), staggered
## across the field.
func _drive_cars(dt: float, held: bool) -> void:
	_tick += 1
	_measure_gaps()
	for k in entries.size():
		var e: Entry = entries[k]
		if e.remote or e.cleared:
			continue
		if e.ai and not e.retired and (_tick + k) % AI_EVERY == 0 \
				and not (e.finished and kind == Kind.RACE and e.sim.speed < 1.0):
			_traffic(k)
			e.ai.hold = held
			e.ai.drive(dt * AI_EVERY, e.input)
			if e.finished:
				e.input.throttle *= 0.4
		if e.retired:
			e.input.clear()
			e.input.brake = 1.0
		if e.pit_stop_t > 0.0:
			e.input.clear()
			e.input.brake = 1.0
		e.sim.allow_reverse = e.ai == null and not held and e.pit_stop_t <= 0.0
		if held or e.pit_stop_t > 0.0:
			e.sim.reverse = false
		if held:
			# Revs allowed, wheels held; a jump start shows as creeping forward.
			var rev := e.input.throttle
			e.input.throttle = 0.0
			e.input.brake = 1.0
			e.sim.step(dt, e.input)
			e.input.throttle = rev
			e.sim.engine_load = rev
			e.sim.rpm = lerpf(e.sim.rpm, e.sim.spec.rpm_idle + rev * 7000.0, 0.1)
			continue
		_aero(k)
		e.sim.step(dt, e.input)


## Works out every pair's distance along the lap once a tick.
func _measure_gaps() -> void:
	var n := entries.size()
	if _gaps.size() != n * n:
		_gaps.resize(n * n)
	for i in n:
		var si: float = entries[i].sim.spot.s
		for j in range(i + 1, n):
			var g := track.delta_s(si, entries[j].sim.spot.s)
			_gaps[i * n + j] = g
			_gaps[j * n + i] = -g


## How far car j is ahead of car i along the lap (negative: behind).
func gap_between(i: int, j: int) -> float:
	return _gaps[i * entries.size() + j]


## Slipstream and turbulent air from the car ahead.
func _aero(k: int) -> void:
	var e: Entry = entries[k]
	e.sim.drag_scale = 1.0
	e.sim.downforce_scale = 1.0
	var best := 999.0
	var n := entries.size()
	for j in n:
		if j == k:
			continue
		var gap := _gaps[k * n + j]
		if gap <= 1.0 or gap > 50.0:
			continue
		var o: Entry = entries[j]
		if o.retired or absf(o.sim.spot.lat - e.sim.spot.lat) > 2.6:
			continue
		best = minf(best, gap)
	if best < 50.0:
		e.sim.drag_scale = 1.0 - 0.3 * (1.0 - best / 50.0)
		if best < 22.0:
			e.sim.downforce_scale = 1.0 - 0.16 * (1.0 - best / 22.0)


## Tells one AI about the cars around it.
func _traffic(k: int) -> void:
	var e: Entry = entries[k]
	var ai := e.ai
	ai.traffic.clear()
	ai.traffic_gap.resize(0)
	ai.traffic_lat.resize(0)
	var n := entries.size()
	var base := k * n
	for j in n:
		if j == k:
			continue
		var gap := _gaps[base + j]
		if gap > 200.0 or gap < -60.0:
			continue
		var o: Entry = entries[j]
		var sp := o.sim.spot
		# A car parked off the track, or in the pit lane when we aren't, isn't in the way.
		if o.cleared or (o.retired and o.sim.speed < 1.0 and absf(sp.lat) > track.value_at(track.half, sp.s)):
			continue
		if sp.in_pit != e.sim.spot.in_pit and absf(gap) > 3.0:
			continue
		ai.traffic.append(o.sim)
		ai.traffic_gap.append(gap)
		ai.traffic_lat.append(sp.lat)
	ai.blue = e.blue
	ai.vsc = 0.62 if vsc else 0.0


## Car against car: two boxes pushed apart with an impulse.
func _contacts() -> void:
	var n := entries.size()
	for i in n:
		var a: Entry = entries[i]
		if a.cleared:
			continue
		for j in range(i + 1, n):
			if absf(_gaps[i * n + j]) > 8.0:
				continue
			var b: Entry = entries[j]
			if b.cleared:
				continue
			if a.remote and b.remote:
				continue
			var pa := Vector2(a.sim.pos.x, a.sim.pos.z)
			var pb := Vector2(b.sim.pos.x, b.sim.pos.z)
			if pa.distance_squared_to(pb) > 36.0:
				continue
			if absf(a.sim.pos.y - b.sim.pos.y) > 2.5:
				continue
			_collide(a, b, pa, pb)


func _collide(a: Entry, b: Entry, pa: Vector2, pb: Vector2) -> void:
	# Separating axis test on the two cars' footprints.
	var axes := [a.sim.forward2(), a.sim.left2(), b.sim.forward2(), b.sim.left2()]
	var min_depth := INF
	var min_axis := Vector2.ZERO
	var d := pb - pa
	for ax in axes:
		var ra := _extent(a.sim, ax)
		var rb := _extent(b.sim, ax)
		var dist := absf(d.dot(ax))
		var depth := ra + rb - dist
		if depth <= 0.0:
			return
		if depth < min_depth:
			min_depth = depth
			min_axis = ax if d.dot(ax) >= 0.0 else -ax
	var rel := b.sim.vel - a.sim.vel
	var vn := rel.dot(min_axis)
	var push := min_axis * min_depth * 0.5
	var imp := Vector2.ZERO
	var hit := 0.0
	if vn < 0.0:
		imp = min_axis * (-vn) * 0.6
		hit = -vn
	var wa := 0.0 if a.remote else 1.0
	var wb := 0.0 if b.remote else 1.0
	if wa + wb == 0.0:
		return
	var sa := wa / (wa + wb) * 2.0
	var sb := wb / (wa + wb) * 2.0
	if not a.remote:
		a.sim.bump(-push * sa, -imp * 0.5 * sa, hit)
	if not b.remote:
		b.sim.bump(push * sb, imp * 0.5 * sb, hit)
	if hit > 3.0:
		_events("contact", {"a": a.id, "b": b.id, "speed": hit})


func _extent(c: CarSim, axis: Vector2) -> float:
	return absf(c.forward2().dot(axis)) * CarSim.HALF_LENGTH + absf(c.left2().dot(axis)) * CarSim.HALF_WIDTH


# --- The rules (host only) ----------------------------------------------

func _rules(dt: float) -> void:
	for e in entries:
		e.sim.wetness = wetness
		_progress(e)
		_pit(e, dt)
		_track_limits(e)
		_drs(e)
		_retirement(e, dt)
	if _tick % ORDER_EVERY == 0:
		_update_order()
	if _tick % 30 == 0:
		_weather(dt * 30.0)
		_flags(dt * 30.0)
		_strategy()
	_check_finish()


## Laps, sectors and timing loops as a car moves round.
func _progress(e: Entry) -> void:
	if e.retired:
		return
	var s := e.sim.spot.s
	var prev := fposmod(e.s_total, track.length)
	var ds := track.delta_s(prev, s)
	if absf(ds) > 60.0:
		ds = 0.0
	var before := e.s_total
	e.s_total += ds
	# Timing loops every 50 m give the gaps.
	var cp := int(floorf(e.s_total / CHECKPOINT))
	if cp > int(floorf(before / CHECKPOINT)) and phase != Phase.GRID:
		e.checkpoints[cp] = time
		if e.checkpoints.size() > 400:
			e.checkpoints.erase(e.checkpoints.keys().min())
	# Sectors.
	var sec := track.sector_of(s)
	if e.lap >= 1 or kind != Kind.RACE:
		if sec != e.sector and ((sec == e.sector + 1) or (sec == 0 and e.sector == 2)):
			var st := time - e.sector_start
			if sec != 0:
				e.sectors[e.sector] = st
				_sector_done(e, e.sector, st)
			e.sector_start = time
		e.sector = sec
	# Crossing the line.
	var lap_now := int(floorf(e.s_total / track.length))
	if lap_now + 1 > e.lap and e.s_total >= 0.0 and not e.finished:
		_cross_line(e)


func _sector_done(e: Entry, sec: int, t: float) -> void:
	if e.lap_valid and (e.best_sectors[sec] == 0.0 or t < e.best_sectors[sec]):
		e.best_sectors[sec] = t
	_events("sector", {"id": e.id, "sector": sec, "time": t})


func _cross_line(e: Entry) -> void:
	var first := e.lap == 0
	e.lap += 1
	if not first:
		var lt := time - e.lap_start
		var st := time - e.sector_start
		e.sectors[2] = st
		_sector_done(e, 2, st)
		e.last_sectors = e.sectors.duplicate()
		e.last_lap = lt
		var valid := e.lap_valid
		if valid and (e.best_lap == 0.0 or lt < e.best_lap):
			e.best_lap = lt
			_events("personal_best", {"id": e.id, "time": lt})
		if valid and (fastest.time == 0.0 or lt < float(fastest.time)):
			fastest = {"id": e.id, "time": lt, "lap": e.lap - 1}
			_events("fastest_lap", {"id": e.id, "time": lt})
		_events("lap", {"id": e.id, "lap": e.lap - 1, "time": lt, "valid": valid})
	e.lap_start = time
	e.sector_start = time
	e.sector = 0
	e.lap_valid = true
	e.sectors = [0.0, 0.0, 0.0]
	if kind == Kind.RACE and e.lap == 3 and not _drs_said:
		_drs_said = true
		_events("drs_enabled")
	if kind == Kind.RACE and leader_finished_t >= 0.0 and not e.finished:
		_finish(e)
	elif kind == Kind.RACE and not first and e.lap > laps and not e.finished:
		_finish(e)


func _finish(e: Entry) -> void:
	e.finished = true
	e.finish_time = time
	if leader_finished_t < 0.0:
		leader_finished_t = time
		_events("chequered", {"id": e.id})
	_events("finished", {"id": e.id, "position": e.position})


## Into the pit lane, the limiter, the stop in the box and back out.
func _pit(e: Entry, dt: float) -> void:
	if track.pit.is_empty():
		return
	var in_lane := e.sim.spot.in_pit
	if in_lane and not e.in_pit_lane:
		e.in_pit_lane = true
		e.speeding = false
		_events("pit_in", {"id": e.id})
	elif not in_lane and e.in_pit_lane and absf(track.delta_s(0.0, e.sim.spot.s) - float(track.pit.exit)) < 40.0:
		e.in_pit_lane = false
		_events("pit_out", {"id": e.id})
	elif not in_lane and e.in_pit_lane:
		e.in_pit_lane = false
	if not e.in_pit_lane:
		return
	var d := track.delta_s(0.0, e.sim.spot.s)
	if d > float(track.pit.limit_in) and d < float(track.pit.limit_out):
		if e.sim.kmh() > Track.PIT_LIMIT_KMH + 1.5 and not e.speeding:
			e.speeding = true
			e.penalty += SPEEDING_PENALTY
			_events("penalty", {"id": e.id, "seconds": SPEEDING_PENALTY, "why": "Speeding in the pit lane"})
	# The stop.
	if e.pit_stop_t > 0.0:
		e.pit_stop_t -= dt
		if e.pit_stop_t <= 0.0:
			e.pit_stop_t = 0.0
			e.sim.compound = e.next_compound
			e.sim.wear = 0.0
			e.sim.tyre_temp = 0.75
			e.sim.wing_damage = 0.0
			if not e.compounds.has(e.sim.compound):
				e.compounds.append(e.sim.compound)
			e.stops += 1
			e.next_compound = _second_compound(e.sim.compound)
			_events("pit_done", {"id": e.id, "compound": e.sim.compound})
			if e.ai:
				e.ai.pit_request = false
				e.ai.pit_phase = AiDriver.PitPhase.LEAVING
		return
	var box := box_for(e.team)
	var to_box := absf(track.delta_s(e.sim.spot.s, box))
	var box_lat := float(track.pit.box_lat) * float(track.pit.side)
	if to_box < 3.0 and absf(e.sim.spot.lat - box_lat) < 3.0 and e.sim.speed < 1.0:
		var wanted := e.ai == null or e.ai.pit_request
		if wanted:
			var t := BASE_STOP + rng.randf_range(0.0, 0.6)
			if e.sim.wing_damage > 0.25:
				t += WING_CHANGE
			e.pit_stop_t = t
			_events("pit_stop", {"id": e.id, "time": t})
			if e.ai:
				e.ai.pit_phase = AiDriver.PitPhase.STOPPED


## All four wheels past the white lines in a corner is a warning; the fourth
## time is a penalty. In qualifying and Time Trial the lap doesn't count.
func _track_limits(e: Entry) -> void:
	if e.sim.wheels_out < 4 or e.sim.spot.in_pit or e.retired:
		return
	var c := track.next_corner(e.sim.spot.s)
	if c.is_empty():
		return
	var inside := track.delta_s(float(c.start) - 30.0, e.sim.spot.s) >= 0.0 and track.delta_s(e.sim.spot.s, float(c.end) + 40.0) >= 0.0
	if not inside or e.last_corner == int(c.number) * 1000 + e.lap:
		return
	e.last_corner = int(c.number) * 1000 + e.lap
	if kind != Kind.RACE:
		if e.lap_valid:
			e.lap_valid = false
			_events("lap_invalid", {"id": e.id, "corner": c.number})
		return
	e.lap_valid = false
	e.warnings += 1
	if e.warnings == MAX_WARNINGS:
		_events("black_white", {"id": e.id, "corner": c.number})
	elif e.warnings > MAX_WARNINGS:
		e.penalty += LIMITS_PENALTY
		_events("penalty", {"id": e.id, "seconds": LIMITS_PENALTY, "why": "Track limits"})
	else:
		_events("track_limits", {"id": e.id, "corner": c.number, "count": e.warnings})


## DRS: within a second of the car ahead at the detection line opens the
## wing in the next zone. Not on the first two laps, nor in the wet.
func _drs(e: Entry) -> void:
	if not drs_enabled or track.drs.is_empty() or e.retired:
		e.sim.drs_open = false
		return
	var allowed := kind != Kind.RACE or (e.lap >= 3 and not vsc and wetness < 0.3)
	var s := e.sim.spot.s
	for z in track.drs:
		var det := float(z.detect)
		var prev := s - e.sim.speed * DT
		if track.delta_s(prev, det) > 0.0 and track.delta_s(det, s) >= 0.0:
			e.drs_ok = kind != Kind.RACE or (allowed and _gap_ahead(e) < 1.0)
			if e.drs_ok and not e.bot:
				_events("drs_ready", {"id": e.id})
		var in_zone := track.delta_s(float(z.start), s) >= 0.0 and track.delta_s(s, float(z.end)) >= 0.0
		if in_zone:
			if e.drs_ok and e.input.drs and allowed and not e.sim.drs_open:
				e.sim.drs_open = true
			return
	e.sim.drs_open = false


## Seconds to the car ahead on the road, from the timing loops.
func _gap_ahead(e: Entry) -> float:
	var idx := order.find(e)
	if idx <= 0:
		return 99.0
	var ahead: Entry = order[idx - 1]
	var cp := int(floorf(e.s_total / CHECKPOINT))
	if ahead.checkpoints.has(cp) and e.checkpoints.has(cp):
		return float(e.checkpoints[cp]) - float(ahead.checkpoints[cp])
	return 99.0


## Heavy damage retires a car; it pulls off and the virtual safety car comes out.
func _retirement(e: Entry, dt: float) -> void:
	if e.retired:
		# Once stopped, the marshals push the car clear of the track.
		if not e.cleared and e.sim.speed < 2.0 and time - e.retire_t > RECOVERY_TIME:
			_clear_wreck(e)
		return
	if kind != Kind.RACE:
		return
	if e.sim.damage >= 1.0:
		e.retired = true
		e.retire_t = time
		_events("retired", {"id": e.id})
		if not vsc and phase == Phase.RACING and leader_finished_t < 0.0:
			vsc = true
			vsc_t = rng.randf_range(35.0, 55.0)
			_events("vsc", {"on": true})
		return
	# Stuck and going nowhere for a long time counts as a retirement too.
	if e.sim.speed < 1.0 and phase == Phase.RACING and e.pit_stop_t <= 0.0 and not e.finished and e.ai:
		e.stalled_t += dt
		if e.stalled_t > 25.0:
			e.sim.damage = 1.0
	else:
		e.stalled_t = 0.0


## Rain from the forecast wets the road; a dry line comes back slowly. The
## AI's speeds follow the road in steps.
func _weather(dt: float) -> void:
	if forecast.is_empty():
		return
	var r := float(forecast[0][1])
	for k in forecast.size():
		if time >= float(forecast[k][0]):
			r = float(forecast[k][1])
			if k + 1 < forecast.size():
				var t0 := float(forecast[k][0])
				var t1 := float(forecast[k + 1][0])
				r = lerpf(r, float(forecast[k + 1][1]), clampf((time - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0))
	if absf(r - rain) > 0.05 and (r > 0.1) != (rain > 0.1):
		_events("rain", {"on": r > 0.1})
	rain = r
	if rain > wetness:
		wetness = minf(rain, wetness + dt * (0.004 + rain * 0.01))
	else:
		wetness = maxf(rain, wetness - dt * 0.0025)
	var step_now := int(roundf(wetness * 10.0))
	if step_now != _wet_step:
		_wet_step = step_now
		for e in entries:
			if e.ai:
				e.ai.speeds = speeds_for(e.team)
				e.ai.profile_grip = reference_grip()


func _flags(dt: float) -> void:
	if vsc:
		vsc_t -= dt
		if vsc_t <= 0.0:
			vsc = false
			_events("vsc", {"on": false})
	# Yellow in a sector with a slow or stopped car near the track.
	var y := [false, false, false]
	for e in entries:
		if e.sim.speed < 8.0 and phase == Phase.RACING and not e.sim.spot.in_pit and e.pit_stop_t <= 0.0:
			if absf(e.sim.spot.lat) < track.value_at(track.half, e.sim.spot.s) + 10.0:
				y[track.sector_of(e.sim.spot.s)] = true
	if y != yellow:
		yellow = y
		_events("yellow", {"sectors": y})
	# Blue flags: a car about to be lapped.
	if kind != Kind.RACE or order.is_empty():
		return
	for e in order:
		var was: bool = e.blue
		e.blue = false
		if e.retired or e.finished:
			continue
		for o in order:
			if o == e or o.retired:
				continue
			var behind: float = e.s_total - o.s_total
			# o is behind on the road but a lap or more ahead in the race.
			var road := track.delta_s(o.sim.spot.s, e.sim.spot.s)
			if road > 0.0 and road < 70.0 and o.s_total - e.s_total > track.length * 0.5:
				e.blue = true
				break
			if behind > 1e9:
				break
		if e.blue and not was and not e.bot:
			_events("blue", {"id": e.id})


## Moves a retired car behind the barrier on its nearer side, where it
## stays out of the race (no contact, no traffic).
func _clear_wreck(e: Entry) -> void:
	var s := e.sim.spot.s
	var side := 0 if e.sim.spot.lat > 0.0 else 1
	var out := track.barrier_off(s, side) + 4.0
	e.sim.place(s, out if side == 0 else -out)
	e.sim.vel = Vector2.ZERO
	e.cleared = true
	_events("cleared", {"id": e.id})


## AI pit calls: worn tyres, the second compound the rules require, or the
## wrong tyres for the weather.
func _strategy() -> void:
	if kind != Kind.RACE or phase != Phase.RACING:
		return
	for e in entries:
		if e.ai == null or e.retired or e.finished or e.ai.pit_request or e.pit_stop_t > 0.0:
			continue
		var laps_left: int = laps - e.lap + 1
		if laps_left <= 1:
			continue
		var c: int = e.sim.compound
		var want := false
		if Tyres.is_slick(c) and wetness > 0.4:
			e.next_compound = Tyres.INTER if wetness < 0.75 else Tyres.WET
			want = true
		elif not Tyres.is_slick(c) and wetness < 0.15:
			e.next_compound = Tyres.MEDIUM if laps_left > 8 else Tyres.SOFT
			want = true
		elif e.sim.wear > 0.72 and laps_left > 2:
			want = true
		elif mandatory_compounds and e.compounds.size() < 2 and Tyres.is_slick(c) and wetness < 0.3:
			# Make the required stop by two thirds distance.
			if e.lap >= int(laps * (0.4 + (e.id % 5) * 0.06)):
				want = true
		if e.sim.wing_damage > 0.5 and laps_left > 2:
			want = true
		if want:
			e.ai.pit_request = true


func _second_compound(c: int) -> int:
	match c:
		Tyres.SOFT:
			return Tyres.MEDIUM
		Tyres.MEDIUM:
			return Tyres.HARD
		Tyres.HARD:
			return Tyres.MEDIUM
	return c


func _check_finish() -> void:
	if phase == Phase.FINISHED or kind != Kind.RACE:
		return
	if leader_finished_t < 0.0:
		return
	var all_done := true
	for e in entries:
		if not e.finished and not e.retired:
			all_done = false
	if all_done or time - leader_finished_t > FINISH_GRACE:
		phase = Phase.FINISHED
		for e in entries:
			if not e.finished and not e.retired:
				e.finished = true
				e.finish_time = time
		_update_order()
		_award_points()
		_events("race_over")


## Running order: finishers by when they finished, then by distance covered.
func _update_order() -> void:
	order.sort_custom(_ahead)
	var leader: Entry = order[0] if not order.is_empty() else null
	var prev: Entry = null
	for i in order.size():
		var e: Entry = order[i]
		var was := e.position
		e.position = i + 1
		if leader and e != leader:
			if phase == Phase.FINISHED or e.finished:
				e.laps_down = maxi(0, leader.lap - e.lap)
			else:
				e.laps_down = maxi(0, int(floorf((leader.s_total - e.s_total) / track.length)))
			e.gap = _time_gap(leader, e)
			e.interval = _time_gap(prev, e) if prev else 0.0
		else:
			e.gap = 0.0
			e.interval = 0.0
			e.laps_down = 0
		if was != 0 and was != e.position and phase == Phase.RACING and kind == Kind.RACE:
			if e.position < was:
				e.overtakes += 1
			_events("position", {"id": e.id, "from": was, "to": e.position})
		prev = e


func _ahead(a: Entry, b: Entry) -> bool:
	if kind != Kind.RACE:
		# Best lap first; no lap yet goes last.
		var ta := a.best_lap if a.best_lap > 0.0 else INF
		var tb := b.best_lap if b.best_lap > 0.0 else INF
		if ta != tb:
			return ta < tb
		return a.id < b.id
	if a.retired != b.retired:
		return b.retired
	if a.retired and b.retired:
		return a.s_total > b.s_total
	if phase == Phase.FINISHED:
		var fa := a.finish_time + a.penalty + (99999.0 if not a.finished else 0.0)
		var fb := b.finish_time + b.penalty + (99999.0 if not b.finished else 0.0)
		# Lapped cars finish behind every car on the lead lap.
		if a.lap != b.lap:
			return a.lap > b.lap
		return fa < fb
	if a.finished != b.finished:
		return a.finished and (not b.finished)
	if a.finished and b.finished:
		return a.finish_time < b.finish_time
	return a.s_total > b.s_total


func _time_gap(front: Entry, back: Entry) -> float:
	var cp := int(floorf(back.s_total / CHECKPOINT))
	for k in 3:
		if front.checkpoints.has(cp - k) and back.checkpoints.has(cp - k):
			return float(back.checkpoints[cp - k]) - float(front.checkpoints[cp - k])
	return 0.0


func _award_points() -> void:
	for e in order:
		e.points = Teams.points_for(e.position) if not e.retired else 0


## The classification: [{id, name, team, position, time, gap, laps, best,
## points, status, stops, penalty}].
func results() -> Array:
	var out := []
	var winner_t := 0.0
	for e in order:
		if e.position == 1:
			winner_t = e.finish_time + e.penalty
	for e in order:
		var status := "Finished"
		if e.retired:
			status = "Retired"
		elif e.laps_down > 0:
			status = "+%d lap%s" % [e.laps_down, "" if e.laps_down == 1 else "s"]
		out.append({
			"id": e.id, "name": e.name, "code": e.code, "team": e.team, "nat": e.nat,
			"position": e.position, "time": e.finish_time + e.penalty,
			"gap": (e.finish_time + e.penalty - winner_t) if e.finished and e.laps_down == 0 else 0.0,
			"laps": maxi(0, e.lap - 1), "best": e.best_lap, "points": e.points,
			"status": status, "stops": e.stops, "penalty": e.penalty, "bot": e.bot,
			"start": e.start_position, "fastest": fastest.id == e.id,
		})
	return out


func _events(type: String, data := {}) -> void:
	var ev := data.duplicate()
	ev["type"] = type
	ev["t"] = time
	events.append(ev)
	if events.size() > 200:
		events = events.slice(events.size() - 200)


## Everything needed to go back to this moment (the rewind).
func snapshot() -> Dictionary:
	var cars := []
	for e in entries:
		var fields := {}
		for prop in e.get_property_list():
			if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var key: String = prop.name
			if key in ["sim", "input", "ai"]:
				continue
			var v = e.get(key)
			fields[key] = v.duplicate(true) if v is Array or v is Dictionary else v
		var ai := []
		if e.ai:
			ai = [e.ai.offset, e.ai.pit_phase, e.ai.pit_request]
		cars.append([e.sim.save_state(), fields, ai, e.sim.limiter_on, e.sim.drs_open])
	var ids := []
	for e in order:
		ids.append(e.id)
	return {
		"cars": cars, "order": ids, "time": time, "clock": clock, "phase": phase,
		"lights": lights, "vsc": vsc, "vsc_t": vsc_t, "fastest": fastest.duplicate(),
		"leader_finished_t": leader_finished_t, "yellow": yellow.duplicate(),
		"wetness": wetness, "rain": rain, "tick": _tick,
	}


func restore(snap: Dictionary) -> void:
	var cars: Array = snap.cars
	for k in mini(cars.size(), entries.size()):
		var e: Entry = entries[k]
		var c: Array = cars[k]
		e.sim.load_state(c[0])
		var fields: Dictionary = c[1]
		for key in fields:
			var v = fields[key]
			e.set(key, v.duplicate(true) if v is Array or v is Dictionary else v)
		if e.ai and not (c[2] as Array).is_empty():
			e.ai.offset = c[2][0]
			e.ai.pit_phase = c[2][1]
			e.ai.pit_request = c[2][2]
		e.sim.limiter_on = c[3]
		e.sim.drs_open = c[4]
		e.input.clear()
	var by_id := {}
	for e in entries:
		by_id[e.id] = e
	order.clear()
	for id in snap.order:
		order.append(by_id[id])
	time = snap.time
	clock = snap.clock
	phase = snap.phase
	lights = snap.lights
	vsc = snap.vsc
	vsc_t = snap.vsc_t
	fastest = snap.fastest.duplicate()
	leader_finished_t = snap.leader_finished_t
	yellow = snap.yellow.duplicate()
	wetness = snap.wetness
	rain = snap.rain
	_tick = snap.tick
	events.clear()


## Takes the events since the last call.
func drain_events() -> Array:
	var out := events
	events = []
	return out


## Whether the session is over (race finished).
func is_over() -> bool:
	return phase == Phase.FINISHED
