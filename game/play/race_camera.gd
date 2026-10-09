class_name RaceCamera
extends Camera3D
## The player's camera: cockpit, T-cam, chase near or chase far.
##
## Comfort comes first (some players get motion sick): by default the
## horizon stays level, nothing shakes, the head doesn't move with g-forces,
## the field of view doesn't widen with speed, and the chase cameras follow
## the way the car is travelling through a soft spring that turns at a
## limited rate, so a spin doesn't whip the view round. Every one of those
## is a setting.

var car: CarView
var sim: CarSim
var view := "chase_near"
## Look around: -1 full left to 1 full right; look_back turns round.
var look := 0.0
var look_back := false

var _heading := 0.0
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _height := 0.0
var _look_yaw := 0.0
var _pitch := 0.0
var _head := Vector3.ZERO
var _fresh := true


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.08
	far = 6000.0
	current = true


func attach(p_car: CarView, p_sim: CarSim) -> void:
	car = p_car
	sim = p_sim
	_fresh = true


func set_view(v: String) -> void:
	view = v
	_fresh = true
	if car:
		car.set_cockpit(v == "cockpit")


func _process(dt: float) -> void:
	# "free": something else (a screenshot tool, a replay) places the camera.
	if view == "free" or car == null or sim == null or not is_instance_valid(car):
		return
	var xf := car.get_global_transform_interpolated()
	var base_fov := float(LGSettings.get_value("camera", "fov"))
	var target_fov := base_fov
	if bool(LGSettings.get_value("camera", "speed_fov")):
		target_fov += clampf(sim.speed / 90.0, 0.0, 1.0) * 8.0
	fov = lerpf(fov, target_fov, clampf(dt * 3.0, 0.0, 1.0)) if not _fresh else target_fov
	# Look around eases in and back out.
	var want_look := PI if look_back else look * deg_to_rad(110.0)
	_look_yaw = lerp_angle(_look_yaw, want_look, clampf(dt * (10.0 if look_back else 5.0), 0.0, 1.0))
	match view:
		"cockpit", "tcam":
			_onboard(xf, dt)
		_:
			_chase(xf, dt)
	_fresh = false


func _onboard(xf: Transform3D, dt: float) -> void:
	var level := bool(LGSettings.get_value("camera", "horizon_lock"))
	var g_head := float(LGSettings.get_value("camera", "g_head"))
	var local := car.eye if view == "cockpit" else car.tcam
	# The head moves a little with braking and cornering, only if asked.
	var head := Vector3(sim.lat_g * 0.025, 0.0, sim.long_g * 0.03) * g_head
	_head = head if _fresh else _head.lerp(head, clampf(dt * 6.0, 0.0, 1.0))
	var p := xf * (local + _head)
	var fwd := xf.basis.z
	var b: Basis
	if level:
		# Keep the horizon level: follow the car's heading and only a softened
		# share of the road's pitch, never its roll.
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		var pitch := asin(clampf(fwd.y, -1.0, 1.0)) * 0.7
		_pitch = pitch if _fresh else lerpf(_pitch, pitch, clampf(dt * 4.0, 0.0, 1.0))
		var dir := (flat * cos(_pitch) + Vector3.UP * sin(_pitch)).normalized()
		dir = dir.rotated(Vector3.UP, _look_yaw)
		b = Basis.looking_at(dir, Vector3.UP)
	else:
		b = Basis.looking_at(fwd.rotated(xf.basis.y, _look_yaw), xf.basis.y)
	if bool(LGSettings.get_value("camera", "shake")):
		var k := clampf(sim.speed / 80.0, 0.0, 1.0) * (0.0015 + sim.on_kerb * 0.004)
		p += Vector3(randf_range(-k, k), randf_range(-k, k), 0.0)
	global_transform = Transform3D(b, p)


func _chase(xf: Transform3D, dt: float) -> void:
	var far_cam := view == "chase_far"
	var back := 11.5 if far_cam else 7.6
	var up := 4.2 if far_cam else 2.8
	var soft := clampf(float(LGSettings.get_value("camera", "chase_softness")), 0.4, 1.6)
	# Follow the direction of travel when moving, else the way the car faces,
	# turning no faster than a calm rate so spins don't swing the view.
	var car_fwd := xf.basis.z
	var yaw_car := atan2(car_fwd.x, car_fwd.z)
	var want := yaw_car
	if sim.speed > 6.0:
		var travel := atan2(sim.vel.x, sim.vel.y)
		# Mostly the car's heading, leaning to its travel in a slide.
		var w := clampf((sim.speed - 6.0) / 20.0, 0.0, 1.0)
		var diff := wrapf(travel - yaw_car, -PI, PI)
		if absf(diff) > PI * 0.5:
			# Going backwards: keep looking the way we travel.
			want = travel
		else:
			want = yaw_car + diff * 0.6 * w
	if _fresh:
		_heading = want
	else:
		var d := wrapf(want - _heading, -PI, PI)
		var rate := deg_to_rad(140.0) * soft
		_heading += clampf(d * clampf(dt * 5.0 * soft, 0.0, 1.0), -rate * dt, rate * dt)
	var h := _heading + _look_yaw
	var dir := Vector3(sin(h), 0.0, cos(h))
	var car_pos := xf.origin
	var target := car_pos - dir * back + Vector3.UP * up
	# The camera rides the road's height smoothly rather than the car's bumps.
	var ground := car_pos.y
	_height = ground if _fresh else lerpf(_height, ground, clampf(dt * 4.0 * soft, 0.0, 1.0))
	target.y = _height + up
	if _fresh:
		_pos = target
		_vel = Vector3.ZERO
	else:
		# A critically damped spring towards the spot behind the car, solved
		# so it stays steady even when frames are slow.
		var omega := 9.0 * soft
		var x := omega * dt
		var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := _pos - target
		var temp := (_vel + change * omega) * dt
		_vel = (_vel - temp * omega) * decay
		_pos = target + (change + temp) * decay
		# Never fall too far behind at speed.
		var off := _pos - target
		if off.length() > back * 0.6:
			_pos = target + off.normalized() * back * 0.6
	var look_at := car_pos + dir * 8.0 + Vector3.UP * (1.2 if far_cam else 1.3)
	if bool(LGSettings.get_value("camera", "horizon_lock")):
		global_transform = Transform3D(Basis.looking_at(look_at - _pos, Vector3.UP), _pos)
	else:
		global_transform = Transform3D(Basis.looking_at(look_at - _pos, car.global_transform.basis.y), _pos)
	if bool(LGSettings.get_value("camera", "shake")) and sim.impact > 0.0:
		global_position += Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0.0) * clampf(sim.impact / 10.0, 0.0, 1.0)
