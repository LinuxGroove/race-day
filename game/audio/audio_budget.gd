class_name AudioBudget
extends RefCounted
## Who can be heard: keeps track of the listeners and of every CarAudio, and
## lets only the `max_ai` other cars nearest a listener play (people's own
## cars always play). Cars that drop out of the budget fade out over about
## half a second and stop their players; cars that come in fade in.
##
## CarAudio registers itself and calls `refresh()` from its update, so a
## game needs nothing more for one screen. For split screen, set the
## players' cameras (or any Node3D) as the listeners:
##
##   AudioBudget.listeners = [camera_a, camera_b]
##   AudioBudget.max_ai = 6
##
## With no listeners set it uses the current camera of the cars' viewport.
## Listener positions and velocities are tracked here each frame for
## CarAudio's own Doppler shift (Godot's Doppler is left off: it needs the
## camera's tracking on and jitters when frames and physics ticks differ).

const RANK_MS := 100
## Faster than this (m/s) between frames is a camera cut, not movement.
const CUT_SPEED := 150.0

static var listeners: Array = []
static var max_ai := 6
## Listener positions and smoothed velocities this frame.
static var positions := PackedVector3Array()
static var velocities := PackedVector3Array()

static var _cars: Array = []
static var _frame := -1
static var _rank_ms := -100000
static var _last_us := 0


static func register(car: Node3D) -> void:
	if not _cars.has(car):
		_cars.append(car)
	_rank_ms = -100000


static func unregister(car: Node3D) -> void:
	_cars.erase(car)


## Updates the listeners once per frame and the ranking every RANK_MS.
static func refresh() -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	_track_listeners()
	var now := Time.get_ticks_msec()
	if now - _rank_ms >= RANK_MS:
		_rank_ms = now
		_rank()


## The nearest listener to a point: [position, velocity], or [] if none.
static func nearest(p: Vector3) -> Array:
	var best := -1
	var bd := INF
	for i in positions.size():
		var d := p.distance_squared_to(positions[i])
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return []
	return [positions[best], velocities[best]]


static func distance_to_listener(p: Vector3) -> float:
	var near := nearest(p)
	return INF if near.is_empty() else p.distance_to(near[0])


static func _track_listeners() -> void:
	var nodes: Array = []
	for l in listeners:
		if is_instance_valid(l) and (l as Node3D).is_inside_tree():
			nodes.append(l)
	if nodes.is_empty():
		for c in _cars:
			if is_instance_valid(c) and (c as Node3D).is_inside_tree():
				var cam := (c as Node3D).get_viewport().get_camera_3d()
				if cam:
					nodes.append(cam)
				break
	var us := Time.get_ticks_usec()
	var dt := clampf((us - _last_us) / 1e6, 0.001, 0.25)
	_last_us = us
	if nodes.size() != positions.size():
		positions.resize(nodes.size())
		velocities.resize(nodes.size())
		for i in nodes.size():
			positions[i] = (nodes[i] as Node3D).global_position
			velocities[i] = Vector3.ZERO
		return
	for i in nodes.size():
		var p := (nodes[i] as Node3D).global_position
		var v := (p - positions[i]) / dt
		if v.length() > CUT_SPEED:
			v = velocities[i]
		velocities[i] = velocities[i].lerp(v, clampf(dt * 8.0, 0.0, 1.0))
		positions[i] = p


static func _rank() -> void:
	var others: Array = []
	for i in range(_cars.size() - 1, -1, -1):
		var c = _cars[i]
		if not is_instance_valid(c):
			_cars.remove_at(i)
			continue
		if c.is_player:
			continue
		var d := distance_to_listener((c as Node3D).global_position) if (c as Node3D).is_inside_tree() else INF
		# Cars already playing keep their place unless another is clearly nearer.
		if c.audible:
			d *= 0.8
		others.append([d, c])
	others.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in others.size():
		others[k][1].audible = k < max_ai and others[k][0] < INF
