class_name PlayerDriver
extends RefCounted
## Turns one player's controls into a CarInput each physics tick, through
## the assists they have on: steering help, braking help, ABS, traction
## control, automatic gears and the assisted pit stop (the car drives the
## pit lane itself, like the real pit limiter and a race engineer's "box,
## box").

var seat: LGSeat
var entry: Race.Entry
var race: Race
## Assists, read from settings when the session starts (see refresh()).
var steering_help := false
var braking_help := false
var abs := true
var tc := true
var auto_gears := true
var pit_assist := true
## The player has asked to pit this lap.
var pit_requested := false
## The assisted pit stop is driving the car.
var piloting := false
## Tests and screenshots: the car drives itself all the time.
var autopilot := false
## The braking line: off, corners or full.
var line_mode := "corners"
## Assists a Racing School test fixes, whatever the settings say.
var overrides := {}

var _steer := 0.0
var _throttle := 0.0
var _brake := 0.0
var _pilot: AiDriver
var _was_stopped := false
var _profile := PackedFloat32Array()


func _init(p_seat: LGSeat, p_entry: Race.Entry, p_race: Race) -> void:
	seat = p_seat
	entry = p_entry
	race = p_race
	refresh()
	_profile = race.speeds_for(entry.team)
	_pilot = AiDriver.new(entry.sim, _profile, 99)
	_pilot.solo = true
	_pilot.pace = 0.92
	_pilot.profile_grip = race.reference_grip()
	_pilot.box_s = race.box_for(entry.team)


## Reads the assists from settings (they can change in the pause menu).
func refresh() -> void:
	steering_help = bool(_assist("steering_help"))
	braking_help = bool(_assist("braking_help"))
	abs = bool(_assist("abs"))
	tc = bool(_assist("tc"))
	auto_gears = str(_assist("gears")) != "manual"
	pit_assist = bool(_assist("pit"))
	line_mode = str(_assist("braking_line"))


func _assist(key: String) -> Variant:
	return overrides[key] if overrides.has(key) else LGSettings.get_value("assists", key)


## Which assists are on, for the results screen and the boards (0 to 6).
func assist_count() -> int:
	return int(steering_help) + int(braking_help) + int(abs) + int(tc) + int(auto_gears) + int(pit_assist)


## Fills the entry's input for one tick of dt seconds. `frozen` holds the car
## (grid, lights, menus).
func drive(dt: float, frozen := false) -> void:
	var input := entry.input
	var sim := entry.sim
	seat.poll(GameConfig.SEAT_ACTIONS)
	if seat.just_pressed("pit") and not race.track.pit.is_empty():
		pit_requested = not pit_requested
	sim.auto_gears = auto_gears
	if _assisted_pit(dt, input):
		return
	input.clear()
	if autopilot and not frozen:
		_pilot.drive(dt, input)
		return
	# Holding the brake when stopped selects reverse, to back out of trouble.
	sim.allow_reverse = not frozen
	var keyboard := not seat.has_pad() or LGInput.family == "keyboard"
	var raw_steer := seat.strength("steer_right") - seat.strength("steer_left")
	var raw_throttle := seat.strength("throttle")
	var raw_brake := seat.strength("brake")
	var v := absf(sim.forward_speed())
	if keyboard:
		# Keys are all or nothing: ramp the wheel and pedals like hands and
		# feet would, and steer less at speed.
		var lock := lerpf(1.0, 0.35, clampf(v / 70.0, 0.0, 1.0))
		var target := raw_steer * lock
		var rate := 2.4 if absf(target) > absf(_steer) and signf(target) == signf(_steer) else 5.0
		_steer = move_toward(_steer, target, rate * dt)
		_throttle = move_toward(_throttle, raw_throttle, 6.0 * dt)
		_brake = move_toward(_brake, raw_brake, 8.0 * dt)
	else:
		# A stick: a gentle curve near the middle, a little less lock at speed.
		var curved := signf(raw_steer) * pow(absf(raw_steer), 1.6)
		_steer = curved * lerpf(1.0, 0.55, clampf(v / 80.0, 0.0, 1.0))
		_throttle = raw_throttle
		_brake = raw_brake
	input.steer = _steer
	input.throttle = _throttle
	input.brake = _brake
	if frozen:
		input.steer = 0.0
		input.brake = 1.0
		return
	if steering_help:
		input.steer = _steering_help(input.steer, v)
	if braking_help:
		var want := _braking_help(v)
		if want > input.brake:
			input.brake = want
			input.throttle = minf(input.throttle, 0.2)
	if abs and input.brake > 0.0:
		input.brake = minf(input.brake, sim.brake_limit() * 1.02)
	if tc and input.throttle > 0.0:
		input.throttle = minf(input.throttle, sim.throttle_limit() * 1.04 + 0.02)
	if not auto_gears:
		input.shift_up = seat.just_pressed("shift_up")
		input.shift_down = seat.just_pressed("shift_down")
	input.drs = seat.held("drs")
	input.limiter = seat.just_pressed("limiter")


## Steering help: no more lock than the front tyres can use, and a touch of
## opposite lock when the rear steps out.
func _steering_help(steer: float, v: float) -> float:
	var sim := entry.sim
	if v < 8.0:
		return steer
	# The steering angle that uses the front tyres' grip at this speed.
	var spec := sim.spec
	var wb := spec.cg_front + spec.cg_rear
	var a_max := spec.grip * CarSpec.G * 1.2
	var useful := atan(wb * a_max / (v * v)) * 1.25
	var cap := clampf(useful / spec.steer_max, 0.15, 1.0)
	var out := clampf(steer, -cap, cap)
	# The car's slip: rotating faster than the steering asks for means the
	# rear is going; steer into it.
	var expected := v * tan(-sim.steer_angle) / wb
	var excess := sim.yaw_rate - expected
	if absf(excess) > 0.15:
		out += clampf(excess * 0.35, -0.4, 0.4)
	return clampf(out, -1.0, 1.0)


## Braking help: how much brake keeps the car to the speed the next corners
## allow (the same speeds the braking line shows).
func _braking_help(v: float) -> float:
	var sim := entry.sim
	if sim.spot.in_pit:
		return 0.0
	var t := race.track
	var s := sim.spot.s
	var need := 0.0
	var d := 10.0
	while d < 260.0:
		var limit := t.value_at(_profile, t.wrap_s(s + d)) * 0.97
		var decel := 11.0
		var allowed := sqrt(limit * limit + 2.0 * decel * maxf(d - 8.0, 0.0))
		if v > allowed:
			need = maxf(need, clampf((v - allowed) / 6.0 + 0.35, 0.0, 1.0))
		d += 10.0
	return need


## The assisted pit stop: once a stop is asked for, the car drives itself from
## the pit entry to the box and back out to the track. Returns true while it
## drives.
func _assisted_pit(dt: float, input: CarInput) -> bool:
	var t := race.track
	if t.pit.is_empty():
		return false
	var sim := entry.sim
	if not pit_assist:
		piloting = false
		return false
	if not piloting:
		var to_entry := t.delta_s(sim.spot.s, t.wrap_s(float(t.pit.entry)))
		if pit_requested and to_entry > 0.0 and to_entry < AiDriver.PIT_COMMIT - 20.0:
			piloting = true
			_pilot.pit_request = true
			_pilot.pit_phase = AiDriver.PitPhase.NONE
			_pilot.offset = sim.spot.lat - t.value_at(t.line_off, sim.spot.s)
		else:
			return false
	# The race holds the car in its box; then it's time to leave.
	if entry.pit_stop_t > 0.0:
		_was_stopped = true
		_pilot.pit_phase = AiDriver.PitPhase.STOPPED
	elif _was_stopped:
		_was_stopped = false
		pit_requested = false
		_pilot.pit_request = false
		_pilot.pit_phase = AiDriver.PitPhase.LEAVING
	_pilot.drive(dt, input)
	if not sim.limiter_on and sim.spot.in_pit:
		input.limiter = true
	if _pilot.pit_phase == AiDriver.PitPhase.NONE and not _pilot.pit_request:
		# Back on track: the car is the player's again.
		piloting = false
		pit_requested = false
		if sim.limiter_on:
			input.limiter = true
		return true
	if _pilot.pit_phase == AiDriver.PitPhase.NONE and _pilot.pit_request:
		# Missed the entry: give the car back and keep the request for next lap.
		var to_entry := t.delta_s(sim.spot.s, t.wrap_s(float(t.pit.entry)))
		if to_entry < 0.0 or to_entry > AiDriver.PIT_COMMIT:
			piloting = false
			return false
	return true
