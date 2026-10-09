class_name CarView
extends Node3D
## A car on screen: the team's chassis from the kits in its livery, scaled to
## a real 5.5 m formula car, with wheels that steer and turn, a helmet in the
## cockpit and a rain light. The race moves it from its CarSim each physics
## tick, and physics interpolation smooths it between ticks.
##
## The wheels sit on the ground under each of them (the road's slope and
## banking, crests and dips, kerbs), and only the body pitches and rolls on
## its springs, so the tyres never sink into the road.

## Each chassis: the model, its scale to real size, and where the driver's
## eyes and helmet are (metres, car frame: +z forward, +x left).
const CHASSIS := {
	"race": {"path": "res://assets/kenney/car-kit/race.glb", "scale": 2.15, "eye": Vector3(0, 1.05, -0.25), "light_to_accent": 1.0},
	"future": {"path": "res://assets/kenney/car-kit/race-future.glb", "scale": 2.1, "eye": Vector3(0, 1.2, -0.3), "light_to_accent": 1.0},
	"racer": {"path": "res://assets/kenney/racing-kit-v2/racer-%s.glb", "scale": 4.4, "eye": Vector3(0, 1.05, -0.35), "light_to_accent": 1.0},
	"classic": {"path": "res://assets/kenney/racing-kit/raceCar%s.glb", "scale": 4.1, "eye": Vector3(0, 0.95, -0.55), "light_to_accent": 0.0},
}
const LIVERY := preload("res://game/car/livery.gdshader")

var team := 0
var chassis := "race"
var eye := Vector3(0, 1.0, -0.3)
## The T-cam: just above the top of the car, behind the driver's head.
var tcam := Vector3(0, 1.6, -1.0)
## Front and rear wheels: [[node, rest transform], ...].
var _front: Array = []
var _rear: Array = []
var _body: Node3D
var _wheels_node: Node3D
## Where the tyres touch the ground, from the car's middle: half the track
## (left to right) and the front and rear axles.
var _half_track := 0.7
var _axle_f := 1.6
var _axle_r := 1.6
## Where the body pitches and rolls about (the wheels' centre height).
var _pivot := Vector3(0, 0.6, 0)
var _ground := Track.Spot.new()
var _rain_light: MeshInstance3D
var _rain_mat: StandardMaterial3D
var _blink := 0.0


static func create(p_team: int) -> CarView:
	var v := CarView.new()
	v.team = p_team
	v._build()
	return v


func _build() -> void:
	var t := Teams.team(team)
	chassis = str(t.chassis)
	var c: Dictionary = CHASSIS[chassis]
	eye = c.eye
	var path := str(c.path)
	if "%s" in path:
		path = path % str(t.variant)
	var model: Node3D = load(path).instantiate()
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_body.add_child(model)
	_body.scale = Vector3.ONE * float(c.scale)
	# Centre the model on its wheels so the car turns about its middle, with
	# the bottoms of the tyres on the ground.
	var wheels := _find_wheels(model)
	var centre := Vector3.ZERO
	var bottom := INF
	for w in wheels:
		centre += _local_pos(model, w)
		bottom = minf(bottom, (_local_xf(model, w) * (w as MeshInstance3D).get_aabb()).position.y)
	if not wheels.is_empty():
		centre /= wheels.size()
	else:
		bottom = 0.0
	model.position -= Vector3(centre.x, bottom, centre.z)
	_paint(model, t, c)
	# The wheels hang off their own node so the body can move on its springs
	# without them.
	_wheels_node = Node3D.new()
	_wheels_node.name = "Wheels"
	_wheels_node.scale = _body.scale
	add_child(_wheels_node)
	var sc := float(c.scale)
	var fronts := 0.0
	var rears := 0.0
	if not wheels.is_empty():
		_half_track = 0.0
	for w in wheels:
		var xf := Transform3D(Basis(), model.position) * _local_xf(model, w)
		w.get_parent().remove_child(w)
		w.owner = null
		_wheels_node.add_child(w)
		w.transform = xf
		# The middle of the tyre (a wheel's origin can sit on its inner face).
		var p := (xf * (w as MeshInstance3D).get_aabb()).get_center() * sc
		_half_track = maxf(_half_track, absf(p.x))
		_pivot.y = p.y
		if p.z > 0.0:
			_front.append([w, xf])
			fronts += p.z
		else:
			_rear.append([w, xf])
			rears -= p.z
	if not _front.is_empty() and not _rear.is_empty():
		_axle_f = fronts / _front.size()
		_axle_r = rears / _rear.size()
	tcam = Vector3(0.0, _top(model) * float(c.scale) + 0.35, eye.z - 0.45)
	_add_helmet(t)
	_add_rain_light(CarSim.BODIES.get(chassis, CarSim.BODIES.race).z)


## The height of the model's highest point, in its own units.
func _top(model: Node3D) -> float:
	var top := 0.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b: AABB = _local_xf(model, mi) * mi.get_aabb()
		top = maxf(top, b.end.y)
	return top


func _find_wheels(model: Node) -> Array:
	var out := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if "wheel" in str(mi.name).to_lower():
			out.append(mi)
	return out


## A node's position in the model's own frame.
func _local_pos(model: Node3D, n: Node3D) -> Vector3:
	return _local_xf(model, n).origin


func _local_xf(model: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur and cur != model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _paint(model: Node3D, t: Dictionary, c: Dictionary) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			if not mat is StandardMaterial3D:
				continue
			var sm := mat as StandardMaterial3D
			if sm.albedo_texture:
				var sh := ShaderMaterial.new()
				sh.shader = LIVERY
				sh.set_shader_parameter("albedo_tex", sm.albedo_texture)
				sh.set_shader_parameter("main_color", t.main)
				sh.set_shader_parameter("accent_color", t.accent)
				sh.set_shader_parameter("light_to_accent", float(c.light_to_accent))
				mi.set_surface_override_material(si, sh)
			else:
				# The Racing Kit's cars use plain colours: repaint the body colour.
				var n := sm.resource_name.to_lower()
				if n in ["glass", "black", "dark", "metal"]:
					continue
				var m2 := sm.duplicate() as StandardMaterial3D
				if n == "cartire":
					# Tyres and wings in carbon black, like the newer kits.
					m2.albedo_color = Color(0.13, 0.13, 0.15)
				else:
					m2.albedo_color = t.accent if n == "grey" else t.main
				mi.set_surface_override_material(si, m2)


func _add_helmet(t: Dictionary) -> void:
	var helmet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.36
	sphere.radial_segments = 12
	sphere.rings = 6
	helmet.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = t.accent
	m.roughness = 0.3
	helmet.material_override = m
	helmet.position = eye + Vector3(0, -0.12, -0.05)
	helmet.name = "Helmet"
	add_child(helmet)


## The rain light, on the back of the car `tail` metres behind its middle.
func _add_rain_light(tail: float) -> void:
	_rain_light = MeshInstance3D.new()
	_rain_light.name = "RainLight"
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.1, 0.05)
	_rain_light.mesh = box
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.albedo_color = Color(0.25, 0.02, 0.02)
	_rain_mat.emission_enabled = true
	_rain_mat.emission = Color(1, 0.05, 0.03)
	_rain_mat.emission_energy_multiplier = 0.0
	_rain_light.material_override = _rain_mat
	_rain_light.position = Vector3(0, 0.55, 0.1 - tail)
	add_child(_rain_light)


## Hides the helmet and the car's nose for the cockpit camera (the camera
## sits inside the helmet).
func set_cockpit(on: bool) -> void:
	var h := get_node_or_null("Helmet")
	if h:
		h.visible = not on


## Moves the car to its simulation state. Call from the physics tick.
func follow(sim: CarSim, dt: float) -> void:
	var f2 := sim.forward2()
	var l2 := sim.left2()
	# The ground under each tyre: front left, front right, rear left, rear right.
	var at := Vector2(sim.pos.x, sim.pos.z)
	var h := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var p := at + f2 * (_axle_f if k < 2 else -_axle_r) + l2 * (_half_track if k % 2 == 0 else -_half_track)
		h[k] = sim.track.ground_y(p, sim.spot.idx, _ground) if sim.track else sim.pos.y
	# The car rests on the plane through them, lifted a touch when the ground
	# twists so no tyre sinks in.
	var pitch: float = ((h[0] + h[1]) - (h[2] + h[3])) * 0.5 / (_axle_f + _axle_r)
	var roll: float = ((h[0] + h[2]) - (h[1] + h[3])) * 0.25 / _half_track
	var mid: float = (h[0] + h[1] + h[2] + h[3]) * 0.25 + (_axle_r - _axle_f) * 0.5 * pitch
	var lift := 0.0
	for k in 4:
		var z := _axle_f if k < 2 else -_axle_r
		var x := _half_track if k % 2 == 0 else -_half_track
		lift = maxf(lift, float(h[k]) - (mid + pitch * z + roll * x))
	var fwd := Vector3(f2.x, pitch, f2.y).normalized()
	var up := fwd.cross(Vector3(l2.x, roll, l2.y)).normalized()
	var b := Basis(up.cross(fwd).normalized(), up, fwd)
	global_transform = Transform3D(b, Vector3(sim.pos.x, mid + lift, sim.pos.z))
	# The body settles a little under braking, accelerating and cornering:
	# nose down on the brakes, leaning out of a corner.
	var dive := clampf(-sim.long_g * 0.008, -0.03, 0.03)
	var lean := clampf(sim.lat_g * 0.006, -0.025, 0.025)
	var tilt := Basis(Vector3.RIGHT, dive) * Basis(Vector3.BACK, lean)
	_body.transform = Transform3D(tilt.scaled_local(_wheels_node.scale), _pivot - tilt * _pivot)
	_wheels(sim)
	_blink += dt
	var lit := sim.wetness > 0.2 or (sim.limiter_on and sim.spot.in_pit)
	_rain_mat.emission_energy_multiplier = (3.0 if fmod(_blink, 0.5) < 0.25 else 0.4) if lit else 0.0


func _wheels(sim: CarSim) -> void:
	# Wheel turns are in radians of the real wheel; the model's wheels are
	# smaller, but they turn the same way.
	var steer := sim.steer_angle * 1.6
	for w in _front:
		var node: Node3D = w[0]
		var rest: Transform3D = w[1]
		node.transform = Transform3D(Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, fmod(sim.wheel_turn_front, TAU)) * rest.basis, rest.origin)
	for w in _rear:
		var node: Node3D = w[0]
		var rest: Transform3D = w[1]
		node.transform = Transform3D(Basis(Vector3.RIGHT, fmod(sim.wheel_turn_rear, TAU)) * rest.basis, rest.origin)


## Where the driver's eyes are, in the world.
func eye_global() -> Vector3:
	return global_transform * eye
