class_name GhostLap
extends RefCounted
## A recorded lap: where the car was, which way it faced and how its front
## wheels were turned, 20 times a second. Positions rather than inputs, so a
## ghost replays the same on every computer. About 15 KB for a 90 s lap.

const RATE := 20.0
const VERSION := 1

var layout := ""
var team := 0
var time := 0.0
## x, y, z, yaw and steer per sample.
var frames := PackedFloat32Array()
var _clock := 0.0


func clear() -> void:
	frames = PackedFloat32Array()
	_clock = 0.0
	time = 0.0


func sample_count() -> int:
	return frames.size() / 5


## Call every physics tick while the lap is on.
func record(sim: CarSim, dt: float) -> void:
	if sample_count() > 0:
		_clock += dt
		if _clock + 0.0001 < 1.0 / RATE:
			return
		_clock -= 1.0 / RATE
	frames.append_array([sim.pos.x, sim.pos.y, sim.pos.z, sim.yaw, sim.steer_angle])


## Where the ghost is `t` seconds into the lap: [position, yaw, steer].
func sample(t: float) -> Array:
	var n := sample_count()
	if n == 0:
		return [Vector3.ZERO, 0.0, 0.0]
	var f := clampf(t * RATE, 0.0, n - 1.0)
	var i := int(f)
	var j := mini(i + 1, n - 1)
	var u := f - i
	var a := Vector3(frames[i * 5], frames[i * 5 + 1], frames[i * 5 + 2])
	var b := Vector3(frames[j * 5], frames[j * 5 + 1], frames[j * 5 + 2])
	return [a.lerp(b, u), lerp_angle(frames[i * 5 + 3], frames[j * 5 + 3], u), lerpf(frames[i * 5 + 4], frames[j * 5 + 4], u)]


func to_dict() -> Dictionary:
	return {"v": VERSION, "layout": layout, "team": team, "time": time, "frames": frames}


static func from_dict(d: Dictionary) -> GhostLap:
	if int(d.get("v", 0)) != VERSION:
		return null
	var g := GhostLap.new()
	g.layout = str(d.get("layout", ""))
	g.team = int(d.get("team", 0))
	g.time = float(d.get("time", 0.0))
	g.frames = d.get("frames", PackedFloat32Array())
	return g
