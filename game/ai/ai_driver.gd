class_name AiDriver
extends RefCounted
## Drives one car like a racing driver: the racing line at the speed the car
## can carry there, scaled by the driver's pace, with room left for other
## cars. It fills the same CarInput the player's controls do and drives the
## same physics, so it never cheats and never rubber-bands.
##
## The race tells it about the cars around it each tick (`traffic`), whether
## it's being lapped (`blue`), and when to pit (`pit_request`). The pit lane
## is driven the same way, with a lateral path into the lane and the box.

## How the AI handles the pit lane.
enum PitPhase { NONE, ENTERING, TO_BOX, STOPPED, LEAVING }

## Metres before the pit entry where a pitting car starts moving over.
const PIT_COMMIT := 300.0
## Metres after the pit exit to drift from the track's edge to the line.
const PIT_REJOIN := 250.0
## Speed at the pit entry line, m/s.
const PIT_ENTRY_SPEED := 24.0

var car: CarSim
var track: Track
## Speeds along the line for this car (from RacingLine.speeds).
var speeds := PackedFloat32Array()
## The tyre grip `speeds` was worked out for (Tyres.grip of the reference tyre).
var profile_grip := 1.0
## 0.80 (gentle) to 1.0 (on the limit); a little over 1 for the best drivers
## at 110 difficulty.
var pace := 0.95
## 0 to 1: how readily the driver dives down the inside.
var aggression := 0.5
## 0 to 1: how rarely the driver makes a mistake.
var consistency := 0.8
var blue := false
var pit_request := false
var pit_phase := PitPhase.NONE
## The box's distance along the lap (from the race).
var box_s := 0.0
## Only follow the line, no racecraft (Time Trial ghosts, the pit assist).
var solo := false
## Virtual safety car: speeds capped at this share of the line speed (0 off).
var vsc := 0.0
## On the grid: rev the engine and wait.
var hold := false
## The cars around, filled by the race: each car, how far ahead (+) or
## behind (-) it is along the lap, and its lateral position.
var traffic: Array = []
var traffic_gap := PackedFloat32Array()
var traffic_lat := PackedFloat32Array()

var offset := 0.0
## What set the speed this tick ("line", "traffic", "pit", "path"), and the
## speed itself: for tests and the debug overlay.
var why := ""
var target_speed := 0.0
var _target_offset := 0.0
var _vmax := 90.0
var _mistake_t := 0.0
var _mistake := 0.0
var _rng := RandomNumberGenerator.new()
var _stuck_t := 0.0
var _reverse_t := 0.0


func _init(p_car: CarSim = null, p_speeds := PackedFloat32Array(), seed := 0) -> void:
	car = p_car
	if car:
		track = car.track
	speeds = p_speeds
	_rng.seed = seed
	if car:
		_vmax = car.spec.top_gear_speed() * 0.97


## Fills `input` for one tick.
func drive(dt: float, input: CarInput) -> void:
	input.clear()
	if hold:
		input.throttle = 0.55
		_stuck_t = 0.0
		_reverse_t = 0.0
		return
	var sp := car.spot
	var v := car.forward_speed()
	var i := sp.idx
	# Speed target: the line's speed a little ahead, scaled by pace. Flat
	# out where the line is flat out.
	var look_i := (i + int(maxf(v, 0.0) * 0.12 / track.step) + 1) % track.n
	var line_v := speeds[look_i]
	var vt := INF
	if line_v < _vmax:
		vt = line_v * pace * (1.0 + _mistake)
		# The line's speeds are for warm, part-worn mediums: slower on
		# harder, colder or more worn tyres.
		vt *= sqrt(Tyres.grip(car.compound, car.wetness, car.wear, car.tyre_temp) / profile_grip)
		# A damaged front wing, or the turbulent air close behind another
		# car, takes front downforce: slower in the corners.
		if car.downforce_scale < 1.0 or car.wing_damage > 0.0:
			var spec := car.spec
			var front := spec.mass * CarSpec.G * spec.cg_rear / (spec.cg_front + spec.cg_rear)
			var down := spec.downforce(line_v)
			var w := car.wing_damage
			var now := front + down * car.downforce_scale * (1.0 - w * 0.3) * spec.aero_front * (1.0 - w * 0.45)
			vt *= sqrt(now / (front + down * spec.aero_front))
	if vsc > 0.0:
		vt = minf(vt, speeds[look_i] * vsc)
	if blue:
		vt = minf(vt, line_v * 0.96)
	_racecraft(dt, v)
	_pit_phases()
	why = "line"
	var lim := _traffic_speed(v)
	if lim < vt:
		vt = lim
		why = "traffic"
	var lat_target := _lateral_target(dt)
	lim = _pit_speed(v)
	if lim < vt:
		vt = lim
		why = "pit"
	lim = _path_speed(v)
	if lim < vt:
		vt = lim
		why = "path"
	target_speed = vt
	# Steering: aim at a point ahead on the path.
	var ld := clampf(6.0 + absf(v) * 0.32, 8.0, 40.0)
	var ts := sp.s + ld
	var aim := _path_point(ts, lat_target)
	var f := car.forward2()
	var lf := car.left2()
	var d := aim - Vector2(car.pos.x, car.pos.z)
	var local := Vector2(d.dot(f), d.dot(lf))
	var alpha := atan2(local.y, maxf(local.x, 0.5))
	var wheelbase := car.spec.cg_front + car.spec.cg_rear
	var delta := atan(2.0 * wheelbase * sin(alpha) / ld)
	# Catch a slide: steer into it, and steady the car's rotation towards
	# the rate the path asks for.
	var slip := atan2(car.vel.dot(lf), maxf(absf(v), 3.0))
	if absf(v) > 8.0:
		var want_rate := 2.0 * v * sin(alpha) / ld
		delta += clampf(slip, -0.4, 0.4) * 0.6 + (want_rate - car.yaw_rate) * 0.05
	input.steer = clampf(-delta / car.spec.steer_max, -1.0, 1.0)
	# Throttle and brake towards the target speed, with ABS and traction
	# control of its own.
	var err := vt - v
	if err > 0.0:
		input.throttle = clampf(err * 0.15 + 0.3, 0.0, 1.0) if vt < INF else 1.0
		# Sliding: ease off until the rear tyres grip again.
		if absf(slip) > 0.1:
			input.throttle *= clampf(1.0 - (absf(slip) - 0.1) * 6.0, 0.0, 1.0)
		input.throttle = minf(input.throttle, car.throttle_limit() + 0.04)
	else:
		input.brake = clampf(-err * 0.22, 0.0, 1.0)
		# Leave the tyres the grip the corner is already using.
		var side := minf(car.lat_use(), 0.9)
		input.brake = minf(input.brake, car.brake_limit() * 0.98 * sqrt(1.0 - side * side))
		# The rear stepping out under braking: ease off until it grips.
		if absf(slip) > 0.05 and absf(v) > 15.0:
			input.brake *= clampf(1.0 - (absf(slip) - 0.05) * 10.0, 0.15, 1.0)
	_recover(dt, input, v, vt > 2.0)
	_maybe_mistake(dt)
	input.drs = true


## The world point on the path at distance s, `lat` across.
func _path_point(s: float, lat: float) -> Vector2:
	var w := track.world(s, lat)
	return Vector2(w.x, w.z)


## Where the car wants to be across the track at a point a little ahead:
## the racing line plus its offset, or the pit lane.
func _lateral_target(dt: float) -> float:
	offset = move_toward(offset, _target_offset, 3.0 * dt)
	return _lat_at(car.spot.s + clampf(car.forward_speed() * 0.5, 6.0, 30.0))


## The car's path across the track at distance s.
func _lat_at(s: float) -> float:
	var pl := _pit_lat(s)
	if not is_nan(pl):
		return pl
	var half := track.value_at(track.half, s) - 1.1
	return clampf(track.value_at(track.line_off, s) + offset, -half, half)


## The speed the car's own path allows when it's off the racing line: a
## line through the inside of a corner, or across into the pit lane, is
## tighter than the racing line and slower.
func _path_speed(v: float) -> float:
	var lim := INF
	if pit_phase == PitPhase.NONE and absf(offset) < 0.3 and absf(_target_offset) < 0.3:
		return lim
	var grip := Tyres.grip(car.compound, car.wetness, car.wear, car.tyre_temp)
	for k in 4:
		var dist := maxf(v, 0.0) * 0.12 + k * 22.0
		var s := car.spot.s + dist
		var lat := _lat_at(s)
		# Curvature of the path: the bend at this offset plus how fast the
		# offset itself is changing.
		var kc := track.value_at(track.curv, s)
		var bend := (_lat_at(s - 5.0) - 2.0 * lat + _lat_at(s + 5.0)) / 25.0
		var k_path := absf(kc / maxf(1.0 - kc * lat, 0.2) + bend)
		var k_line := absf(track.value_at(track.line_curv, s))
		if k_path <= k_line + 0.0015:
			continue
		# A little more margin than the racing line: the car is working
		# harder off it.
		var ok := RacingLine.corner_speed(car.spec, grip, k_path) * pace * 0.94
		lim = minf(lim, sqrt(ok * ok + 2.0 * 8.0 * maxf(dist - 6.0, 0.0)))
	return lim


## Moves through the pit stop's phases as the car goes round.
func _pit_phases() -> void:
	if track.pit.is_empty():
		return
	var side := float(track.pit.side)
	var d := track.delta_s(0.0, car.spot.s)
	match pit_phase:
		PitPhase.NONE:
			if pit_request:
				var to_entry := track.delta_s(car.spot.s, track.wrap_s(float(track.pit.entry)))
				if to_entry > 0.0 and to_entry < PIT_COMMIT:
					pit_phase = PitPhase.ENTERING
		PitPhase.ENTERING, PitPhase.TO_BOX:
			# Missed the lane (pushed wide, or a spin): try again next lap.
			if d > float(track.pit.wall_in) - 4.0 and d < float(track.pit.exit) \
					and car.spot.lat * side < float(track.pit.wall_lat):
				pit_phase = PitPhase.NONE
		PitPhase.LEAVING:
			if d > float(track.pit.exit) + PIT_REJOIN or d < float(track.pit.entry):
				pit_phase = PitPhase.NONE
				offset = 0.0


## The lateral position of the path through the pit lane at s, or NAN when
## not pitting. Into the lane: over to the pit side of the track before the
## entry, then into the lane before the pit wall starts. Out: along the lane
## until the wall ends, then back onto the track at its edge.
func _pit_lat(s: float) -> float:
	if track.pit.is_empty() or pit_phase == PitPhase.NONE:
		return NAN
	var side := float(track.pit.side)
	var d := track.delta_s(0.0, s)
	var entry := float(track.pit.entry)
	var exit := float(track.pit.exit)
	var lane := float(track.pit.lane_lat) * side
	var edge := (track.value_at(track.half, s) - 1.8) * side
	match pit_phase:
		PitPhase.ENTERING, PitPhase.TO_BOX:
			if d < entry - PIT_COMMIT or d > exit:
				return NAN
			var lat: float
			if d < entry:
				var over := clampf((d - entry + PIT_COMMIT - 40.0) / (PIT_COMMIT - 60.0), 0.0, 1.0)
				lat = lerpf(track.value_at(track.line_off, s) + offset, edge, smoothstep(0.0, 1.0, over))
			else:
				var into := clampf((d - entry) / (float(track.pit.wall_in) - entry - 12.0), 0.0, 1.0)
				lat = lerpf(edge, lane, smoothstep(0.0, 1.0, into))
			var to_box := track.delta_s(s, box_s)
			if absf(to_box) < 45.0:
				lat = lerpf(lat, float(track.pit.box_lat) * side, clampf(1.0 - absf(to_box) / 45.0, 0.0, 1.0))
			return lat
		PitPhase.STOPPED:
			return float(track.pit.box_lat) * side
		PitPhase.LEAVING:
			if d > exit + PIT_REJOIN or d < entry:
				return NAN
			if d > exit:
				# Back on the track: from its edge over to the racing line.
				var back := smoothstep(0.0, 1.0, (d - exit) / PIT_REJOIN)
				return lerpf(edge, track.value_at(track.line_off, s), back)
			var wall_out := float(track.pit.wall_out)
			var out := clampf((d - wall_out - 4.0) / (exit - wall_out - 4.0), 0.0, 1.0)
			var lat2 := lerpf(lane, edge, smoothstep(0.0, 1.0, out))
			var from_box := track.delta_s(box_s, s)
			if from_box < 40.0:
				lat2 = lerpf(float(track.pit.box_lat) * side, lat2, clampf(from_box / 40.0, 0.0, 1.0))
			return lat2
	return NAN


## Speed limit for the pit lane, and braking to stop in the box.
func _pit_speed(v: float) -> float:
	if pit_phase == PitPhase.NONE or track.pit.is_empty():
		return INF
	if pit_phase == PitPhase.STOPPED:
		return 0.0
	var d := track.delta_s(0.0, car.spot.s)
	var lim := INF
	if d > float(track.pit.limit_in) - 10.0 and d < float(track.pit.limit_out):
		lim = CarSim.PIT_LIMIT - 0.6
	elif pit_phase in [PitPhase.ENTERING, PitPhase.TO_BOX]:
		# Slow for the turn into the lane, then to the limit by the line.
		var to_entry := track.delta_s(car.spot.s, track.wrap_s(float(track.pit.entry)))
		if to_entry > 0.0:
			lim = sqrt(PIT_ENTRY_SPEED * PIT_ENTRY_SPEED + 2.0 * 10.0 * to_entry)
		var to_line := track.delta_s(car.spot.s, track.wrap_s(float(track.pit.limit_in) - 10.0))
		if to_line > 0.0:
			lim = minf(lim, sqrt(CarSim.PIT_LIMIT * CarSim.PIT_LIMIT + 2.0 * 14.0 * to_line))
	if pit_phase in [PitPhase.ENTERING, PitPhase.TO_BOX]:
		var to_box := track.delta_s(car.spot.s, box_s)
		if to_box > -1.0 and to_box < 60.0:
			pit_phase = PitPhase.TO_BOX
			lim = minf(lim, sqrt(maxf(0.0, 2.0 * 5.0 * maxf(to_box - 0.4, 0.0))))
	return lim


## Looks at the cars around and picks an offset from the line: pass a slower
## car on the side with room, keep space from a car alongside, and move
## aside for a leader lapping us.
func _racecraft(dt: float, v: float) -> void:
	if solo or pit_phase != PitPhase.NONE:
		_target_offset = 0.0
		return
	var want := 0.0
	var my_lat := car.spot.lat
	var line_here := track.value_at(track.line_off, car.spot.s)
	var half := track.value_at(track.half, car.spot.s) - 1.2
	for k in traffic.size():
		var other: CarSim = traffic[k]
		var gap := traffic_gap[k]
		var their_lat := traffic_lat[k]
		var dl := their_lat - my_lat
		# Side by side, centre to centre, with a little room between.
		var wide := car.half_width + other.half_width
		if gap > 0.0 and gap < 35.0 and absf(dl) < wide + 0.64:
			var closing := v - other.forward_speed()
			if closing > 0.3 or gap < 12.0:
				# Pass on the side with more room.
				var room_left := half - their_lat
				var room_right := their_lat + half
				var side := 1.0 if room_left > room_right else -1.0
				if aggression > 0.6 and absf(their_lat - line_here) < 1.5:
					side = signf(-track.value_at(track.line_off, car.spot.s + 60.0)) if absf(track.value_at(track.line_off, car.spot.s + 60.0)) > 1.0 else side
				want = (their_lat + side * (wide + 1.34)) - line_here
		elif absf(gap) < 6.5 and absf(dl) < wide + 1.04:
			# Alongside: hold a car's width of room.
			var away := -signf(dl) if dl != 0.0 else 1.0
			want = (their_lat + away * (wide + 1.14)) - line_here
		elif gap < 0.0 and gap > -70.0 and blue:
			want = -signf(line_here) * 3.5 if absf(line_here) > 0.5 else 3.5
	_target_offset = clampf(want, -half - line_here, half - line_here)


## Brakes for a slower car directly ahead.
func _traffic_speed(v: float) -> float:
	var lim := INF
	for k in traffic.size():
		var gap := traffic_gap[k]
		if gap <= 0.0:
			continue
		var other: CarSim = traffic[k]
		# Where its speed is heading: a car ahead on the brakes slows fast.
		var ov := maxf(0.0, other.forward_speed() + minf(other.long_g, 0.0) * CarSpec.G * 0.5)
		# Far enough ahead to brake down to its speed in time?
		if gap > maxf(14.0, (v * v - ov * ov) / 24.0 + v * 0.6 + 10.0):
			continue
		# In the way now, or where our path will be when we get there. A car
		# sliding across the road, or coming back on after a spin, is where
		# it's heading, and wider when it's sideways.
		var their := traffic_lat[k]
		var arrive := clampf(gap / maxf(v - ov, 1.0), 0.0, 2.0)
		var drift := other.vel.dot(track.normal_at(other.spot.s)) * arrive
		var rel := absf(wrapf(other.yaw - track.heading_at(other.spot.s), -PI, PI))
		var reach := car.half_width + other.half_width + 0.64 + (1.6 if rel > 0.5 and rel < PI - 0.5 else 0.0)
		var path_lat := _lat_at(car.spot.s + gap)
		var path_dl := _miss(path_lat, their, their + drift)
		if _miss(car.spot.lat, their, their + drift) > reach and path_dl > reach:
			continue
		var room := gap - 7.0
		var safe := sqrt(maxf(0.0, ov * ov + 2.0 * 14.0 * maxf(room, 0.0)))
		if room < 0.0:
			safe = ov - 2.0
		# Already moving over to pass: keep rolling to get round it.
		if path_dl > reach + 0.2:
			safe = maxf(safe, minf(v, 12.0) if room > 1.0 else 6.0)
		lim = minf(lim, safe)
	return lim


## How far `lat` is from a car going from `a` to `b` across the road.
static func _miss(lat: float, a: float, b: float) -> float:
	if lat >= minf(a, b) and lat <= maxf(a, b):
		return 0.0
	return minf(absf(lat - a), absf(lat - b))


## Gets going again after a spin or a trip into the gravel: turns round
## slowly when facing the wrong way, and backs off a wall it's stuck against.
func _recover(dt: float, input: CarInput, v: float, wants_go: bool) -> void:
	var rel := wrapf(car.yaw - track.heading_at(car.spot.s), -PI, PI)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		car.reverse = _reverse_t > 0.0
		input.brake = 0.0
		input.throttle = 0.6 if car.reverse else 0.0
		# Backing up: steer so the nose swings back along the track.
		input.steer = clampf(-signf(rel) * 1.0, -1.0, 1.0) if absf(rel) > 0.1 else 0.0
		return
	car.reverse = false
	# Not getting anywhere: stopped, or scraping along a barrier nose first.
	if (absf(v) < 1.5 and wants_go) or (car.wall_t < 0.2 and absf(rel) > 0.35 and absf(v) < 14.0):
		_stuck_t += dt
	else:
		_stuck_t = 0.0
	if _stuck_t > 1.5:
		_stuck_t = 0.0
		_reverse_t = 1.4
		return
	if absf(rel) > 1.2 and absf(v) < 12.0:
		# Facing the wrong way: turn round slowly.
		input.brake = 0.0
		input.throttle = 0.6
		input.steer = clampf(signf(rel) * 1.0, -1.0, 1.0)


## Now and then a driver brakes a touch late or carries too much speed.
func _maybe_mistake(dt: float) -> void:
	if _mistake_t > 0.0:
		_mistake_t -= dt
		if _mistake_t <= 0.0:
			_mistake = 0.0
		return
	# About one slip every few laps for an average driver.
	var chance := (1.0 - consistency) * 0.025 * dt
	if _rng.randf() < chance:
		_mistake = _rng.randf_range(0.015, 0.045)
		_mistake_t = _rng.randf_range(1.0, 2.0)
