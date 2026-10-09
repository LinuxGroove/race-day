class_name CarInput
extends RefCounted
## One physics tick of a driver's controls. The player's pad, the AI and the
## assists all fill one of these; the car never knows who is driving.

## -1 full left lock to 1 full right lock.
var steer := 0.0
var throttle := 0.0
var brake := 0.0
## Pressed this tick (manual gears).
var shift_up := false
var shift_down := false
## Held: open the rear wing where DRS is allowed.
var drs := false
## Pressed this tick: the pit lane speed limiter on or off.
var limiter := false


func clear() -> void:
	steer = 0.0
	throttle = 0.0
	brake = 0.0
	shift_up = false
	shift_down = false
	drs = false
	limiter = false


func copy_from(o: CarInput) -> void:
	steer = o.steer
	throttle = o.throttle
	brake = o.brake
	shift_up = o.shift_up
	shift_down = o.shift_down
	drs = o.drs
	limiter = o.limiter
