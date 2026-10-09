class_name CarSim
extends RefCounted
## One car's physics, with no nodes: a two-axle tyre model on the track's
## surface, stepped at 120 Hz. The same code drives the player's car, the AI
## and the cars in headless tests, so lap times mean the same everywhere.
##
## The car sits on the surface the track describes (height, slope, banking,
## kerbs, run-off) and hits the barriers the track places. Tyres give grip
## that rises with load and downforce and falls away when they slide or
## lock. Assists (see Assists) change the controls before they get here.
##
## Frames: the car's forward is +Z of its yaw (Kenney's cars face +Z) and
## "left" is +X at yaw 0. Steering input +1 is full right lock.

enum Surface { ROAD, KERB, GRASS, GRAVEL, TARMAC, SAND, PIT }

## Grip and rolling resistance on each surface (as a share of load).
const SURFACE_GRIP := [1.0, 0.93, 0.55, 0.5, 0.95, 0.45, 0.97]
const SURFACE_ROLL := [0.012, 0.02, 0.07, 0.34, 0.016, 0.26, 0.014]
## Each chassis's footprint from the middle of its wheels (CarView's origin),
## for barriers and contact: half its width, and how far the nose and the
## tail reach. Tests check these cover the models.
const BODIES := {
	"race": Vector3(1.40, 3.01, 2.49),
	"future": Vector3(1.26, 3.15, 2.44),
	"racer": Vector3(1.51, 2.86, 2.06),
	"classic": Vector3(1.49, 3.00, 2.51),
}
## The pit wall's half thickness (RoadBuilder draws it 0.7 m thick).
const PIT_WALL_HALF := 0.35
const SHIFT_UP_RPM := 11650.0
const SHIFT_DOWN_RPM := 7400.0
const PIT_LIMIT := Track.PIT_LIMIT_KMH / 3.6

var spec: CarSpec
var track: Track
var spot := Track.Spot.new()
## The footprint (see BODIES).
var half_width := 1.40
var nose := 3.01
var tail := 2.49

var pos := Vector3.ZERO
var yaw := 0.0
var vel := Vector2.ZERO
var yaw_rate := 0.0
## Current front wheel angle (radians, + left).
var steer_angle := 0.0
var gear := 0
var rpm := 4200.0
var auto_gears := true
var reverse := false
## Holding the brake at a standstill selects reverse: people's cars only,
## and never on the grid or in the box. The AI sets `reverse` itself.
var allow_reverse := false
var drs_open := false
var limiter_on := false

var compound := Tyres.MEDIUM
var wear := 0.0
var tyre_temp := 0.8
## 0 dry to 1 soaked, set by the race.
var wetness := 0.0
## Tyre wear speed (0 off, 1 normal, 2 double), set by the race.
var wear_scale := 1.0
## Damage: the front wing (0 fine to 1 gone) and the car overall.
var wing_damage := 0.0
var damage := 0.0
## How much damage contact does (0 off, 0.4 visual only still costs a bit, 1 full).
var damage_scale := 1.0
## Set each tick by the race: less drag in a slipstream, less downforce in
## the turbulent air close behind another car.
var drag_scale := 1.0
var downforce_scale := 1.0
## Overall grip scale (weather, the AI's caution); 1 normally.
var grip_scale := 1.0
## Seconds since the car last touched a barrier.
var wall_t := 99.0

## Outputs for the view, the HUD, sound and rumble.
var speed := 0.0
var long_g := 0.0
var lat_g := 0.0
var front_lock := 0.0
var rear_spin := 0.0
var sliding := 0.0
var on_kerb := 0.0
var surface := Surface.ROAD
var off_track := false
## Wheels beyond the white lines (0 to 4), for track limits.
var wheels_out := 0
## Contact this tick: impact speed with a barrier or another car (m/s).
var impact := 0.0
var wheel_turn_front := 0.0
var wheel_turn_rear := 0.0
var engine_load := 0.0

var _ax := 0.0
var _wheel_surf := [0, 0, 0, 0]
var _reverse_t := 0
var _last_lat := 0.0
var _corner := Track.Spot.new()


func _init(p_spec: CarSpec = null, p_track: Track = null) -> void:
	spec = p_spec if p_spec else CarSpec.new()
	track = p_track


## Gives the car a chassis's footprint (a key of BODIES).
func set_body(chassis: String) -> void:
	var b: Vector3 = BODIES.get(chassis, BODIES.race)
	half_width = b.x
	nose = b.y
	tail = b.z


## Half the footprint's length, and its middle (the nose reaches further than
## the tail), for contact between cars.
func half_length() -> float:
	return (nose + tail) * 0.5


func box_centre() -> Vector2:
	return Vector2(pos.x, pos.z) + forward2() * (nose - tail) * 0.5


## Puts the car at (s, lat) on the track, facing along it, stopped.
func place(s: float, lat: float, heading_offset := 0.0) -> void:
	var p := track.world(s, lat)
	pos = p
	yaw = track.heading_at(s) + heading_offset
	vel = Vector2.ZERO
	yaw_rate = 0.0
	steer_angle = 0.0
	gear = 0
	rpm = spec.rpm_idle
	reverse = false
	drs_open = false
	# Start the search at s, so a crossover's other level never wins.
	spot.idx = -1
	track.locate(Vector2(pos.x, pos.z), int(track.wrap_s(s) / track.step) % track.n, spot)
	_last_lat = spot.lat


## Places the car at (s, lat) already moving at `v` m/s along the track.
func place_moving(s: float, lat: float, v: float) -> void:
	place(s, lat)
	vel = forward2() * v
	gear = _gear_for(v)


func forward2() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func left2() -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


func forward_speed() -> float:
	return vel.dot(forward2())


func kmh() -> float:
	return forward_speed() * 3.6


## The car's basis: yaw only (the view adds the surface's pitch and roll).
func basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## A snapshot of the state that matters for a rewind or a network update.
func save_state() -> Array:
	return [pos, yaw, vel, yaw_rate, steer_angle, gear, rpm, wear, tyre_temp, wing_damage, damage, spot.idx, compound, reverse]


func load_state(st: Array) -> void:
	pos = st[0]
	yaw = st[1]
	vel = st[2]
	yaw_rate = st[3]
	steer_angle = st[4]
	gear = st[5]
	rpm = st[6]
	wear = st[7]
	tyre_temp = st[8]
	wing_damage = st[9]
	damage = st[10]
	spot.idx = st[11]
	compound = st[12]
	reverse = st[13]
	track.locate(Vector2(pos.x, pos.z), spot.idx, spot)
	_last_lat = spot.lat


## The surface under a point (s, lat) on the track.
func surface_at(s: float, lat: float, in_pit: bool) -> int:
	var h := track.value_at(track.half, s)
	if absf(lat) <= h:
		return Surface.ROAD
	if in_pit:
		return Surface.PIT
	var side := 0 if lat > 0.0 else 1
	if track.has_kerb(s, side) and absf(lat) <= h + Track.KERB_WIDTH:
		return Surface.KERB
	match track.runoff_kind(s, side):
		TrackPlan.Runoff.GRAVEL:
			return Surface.GRAVEL
		TrackPlan.Runoff.TARMAC:
			return Surface.TARMAC
		TrackPlan.Runoff.SAND:
			return Surface.SAND
		TrackPlan.Runoff.WALL:
			return Surface.TARMAC
	return Surface.GRASS


## The most brake (0 to 1) the tyres can take right now without locking
## either axle, for ABS and braking help.
func brake_limit() -> float:
	var loads := _axle_loads(forward_speed())
	var front := _axle_grip(0) * loads.x * 0.97
	var rear := _axle_grip(1) * loads.y * 0.9
	var f_lim := front / maxf(spec.brake_force * spec.brake_balance, 1.0)
	var r_lim := rear / maxf(spec.brake_force * (1.0 - spec.brake_balance), 1.0)
	return clampf(minf(f_lim, r_lim), 0.0, 1.0)


## How much of the tyres' sideways grip the car is using (0 to 1).
func lat_use() -> float:
	var loads := _axle_loads(forward_speed())
	var cap := (_axle_grip(0) * loads.x + _axle_grip(1) * loads.y) / spec.mass
	return clampf(absf(lat_g) * CarSpec.G / maxf(cap, 1.0), 0.0, 1.0)


## The rear tyres' slip angle (radians): past spec.peak_slip() they slide.
func rear_slip() -> float:
	var vx := forward_speed()
	return atan2(vel.dot(left2()) - spec.cg_rear * yaw_rate, maxf(absf(vx), 6.0))


## The most throttle (0 to 1) the rear tyres can take without spinning, for
## traction control.
func throttle_limit() -> float:
	var v := absf(forward_speed())
	var loads := _axle_loads(v)
	var mu := _axle_grip(1)
	var lat_use := clampf(absf(lat_g) * CarSpec.G * spec.mass * (spec.cg_front / (spec.cg_front + spec.cg_rear)) / maxf(mu * loads.y, 1.0), 0.0, 0.95)
	var cap := mu * loads.y * sqrt(1.0 - lat_use * lat_use) * 0.96
	var full := _drive_force(1.0, v)
	if full <= 1.0:
		return 1.0
	return clampf(cap / full, 0.0, 1.0)


## Advances the car by dt seconds with these controls.
func step(dt: float, input: CarInput) -> void:
	impact = 0.0
	wall_t += dt
	if input.limiter:
		limiter_on = not limiter_on
	_gears(input)
	var f := forward2()
	var lf := left2()
	var vx := vel.dot(f)
	var vy := vel.dot(lf)
	speed = vel.length()
	# Steering: input +1 is right lock; the wheel turns at a limited rate.
	var target_steer := -clampf(input.steer, -1.0, 1.0) * spec.steer_max
	var rate := 2.6 * dt
	steer_angle = move_toward(steer_angle, target_steer, rate)
	_sample_wheels()
	var loads := _axle_loads(vx)
	var fz_f := loads.x
	var fz_r := loads.y
	var mu_f := _axle_grip(0)
	var mu_r := _axle_grip(1)
	# Tyre slip angles.
	var a := spec.cg_front
	var b := spec.cg_rear
	var vxa := maxf(absf(vx), 6.0)
	var dir := 1.0 if vx >= -0.5 else -1.0
	var alpha_f := atan2(vy + a * yaw_rate, vxa) - steer_angle * dir
	var alpha_r := atan2(vy - b * yaw_rate, vxa)
	var fy_f := -mu_f * fz_f * _pacejka(alpha_f)
	var fy_r := -mu_r * fz_r * _pacejka(alpha_r)
	# Engine and brakes.
	var throttle := clampf(input.throttle, 0.0, 1.0)
	var brake := clampf(input.brake, 0.0, 1.0)
	if limiter_on and spot.in_pit and absf(vx) > PIT_LIMIT - 0.4:
		throttle = 0.0
	var drive := 0.0
	if reverse:
		drive = -throttle * 5500.0 if vx > -6.0 else 0.0
	else:
		drive = _drive_force(throttle, vx)
		if throttle < 0.05 and vx > 2.0:
			drive -= 0.05 * spec.mass * CarSpec.G * clampf(rpm / spec.rpm_max, 0.3, 1.0)
	engine_load = throttle
	var brake_f := brake * spec.brake_force * spec.brake_balance
	var brake_r := brake * spec.brake_force * (1.0 - spec.brake_balance)
	var sv := signf(vx) if absf(vx) > 0.3 else 0.0
	# Rear axle: drive and braking against the friction circle.
	var fx_r := drive - brake_r * sv
	var cap_r := mu_r * fz_r
	rear_spin = 0.0
	var rear_locked := false
	if absf(fx_r) > cap_r:
		if brake_r * sv != 0.0 and absf(drive) < brake_r:
			rear_locked = true
		else:
			rear_spin = clampf((absf(fx_r) - cap_r) / maxf(cap_r, 1.0), 0.0, 1.0)
		fx_r = signf(fx_r) * cap_r * 0.86
		fy_r *= 0.45
	else:
		var avail := sqrt(maxf(0.0, cap_r * cap_r - fx_r * fx_r))
		fy_r = clampf(fy_r, -avail, avail)
	# Front axle: braking only.
	var fx_f := -brake_f * sv
	var cap_f := mu_f * fz_f
	front_lock = 0.0
	if absf(fx_f) > cap_f:
		front_lock = clampf((absf(fx_f) - cap_f) / maxf(cap_f, 1.0) + 0.4, 0.0, 1.0)
		fx_f = signf(fx_f) * cap_f * 0.85
		fy_f *= 0.22
	else:
		var avail_f := sqrt(maxf(0.0, cap_f * cap_f - fx_f * fx_f))
		fy_f = clampf(fy_f, -avail_f, avail_f)
	if rear_locked:
		front_lock = maxf(front_lock, 0.5)
	# Forces in the car's frame, then into the world.
	var cs := cos(steer_angle)
	var sn := sin(steer_angle)
	var fx := fx_f * cs - fy_f * sn + fx_r
	var fy := fy_f * cs + fx_f * sn + fy_r
	var mz := a * (fy_f * cs + fx_f * sn) - b * fy_r
	var world_force := f * fx + lf * fy
	# Drag and rolling resistance oppose the motion.
	if speed > 0.01:
		var vdir := vel / speed
		var drag := spec.drag(speed) * drag_scale * (1.0 - (spec.drs_drag if drs_open else 0.0)) * (1.0 + wing_damage * 0.15)
		var roll := 0.0
		for w in 4:
			roll += float(SURFACE_ROLL[_wheel_surf[w]]) * ((fz_f if w < 2 else fz_r) * 0.5)
		# Gravel and sand drag hardest at speed; a beached car can still crawl out.
		roll *= clampf(speed / 20.0, 0.35, 1.0)
		var resist := drag + roll
		# Never push the car backwards: at a crawl, resistance just stops it.
		resist = minf(resist, speed * spec.mass / dt * 0.9)
		world_force -= vdir * resist
	# Gravity along a slope or a banked corner.
	var grad := spot.tangent * spot.slope + spot.normal * spot.bank
	world_force -= grad * spec.mass * CarSpec.G
	var acc := world_force / spec.mass
	vel += acc * dt
	yaw_rate += mz / spec.yaw_inertia * dt
	# Stopped with nothing pushing: hold still instead of creeping.
	if speed < 0.6 and throttle < 0.05:
		vel *= 0.85
		yaw_rate *= 0.8
	yaw += yaw_rate * dt
	pos.x += vel.x * dt
	pos.z += vel.y * dt
	_ax = lerpf(_ax, acc.dot(f), 0.2)
	long_g = _ax / CarSpec.G
	lat_g = lerpf(lat_g, acc.dot(lf) / CarSpec.G, 0.2)
	sliding = clampf(maxf(absf(alpha_r), absf(alpha_f + steer_angle * 0.0)) / 0.25 - 0.4, 0.0, 1.0)
	sliding = maxf(sliding, maxf(front_lock, rear_spin))
	track.locate(Vector2(pos.x, pos.z), spot.idx, spot)
	_barriers()
	pos.y = spot.y
	_engine_rpm()
	_tyres(dt, fx, fy, fz_f + fz_r)
	if input.brake > 0.1:
		drs_open = false
	wheel_turn_front += vx / spec.wheel_radius * dt * (0.0 if front_lock > 0.6 else 1.0)
	wheel_turn_rear += vx / spec.wheel_radius * dt * (1.0 + rear_spin * 2.0)


## Front and rear axle loads (N) with downforce and weight transfer.
func _axle_loads(vx: float) -> Vector2:
	var m := spec.mass
	var l := spec.cg_front + spec.cg_rear
	var down := spec.downforce(vx) * downforce_scale * (1.0 - wing_damage * 0.3)
	var front_share := spec.aero_front * (1.0 - wing_damage * 0.45)
	var transfer := m * _ax * spec.cg_height / l
	var fz_f := m * CarSpec.G * spec.cg_rear / l + down * front_share - transfer
	var fz_r := m * CarSpec.G * spec.cg_front / l + down * (1.0 - front_share) + transfer
	return Vector2(maxf(fz_f, 300.0), maxf(fz_r, 300.0))


## Grip of an axle (0 front, 1 rear): the tyre, the weather, the surface.
func _axle_grip(axle: int) -> float:
	var tyre := Tyres.grip(compound, wetness, wear, tyre_temp)
	var surf := (float(SURFACE_GRIP[_wheel_surf[axle * 2]]) + float(SURFACE_GRIP[_wheel_surf[axle * 2 + 1]])) * 0.5
	# Wet grass and gravel are even worse; kerbs are slippery when wet.
	if wetness > 0.0 and surf < 1.0:
		surf *= 1.0 - 0.25 * wetness
	var stiff := 1.0 - (spec.stiffness - 0.5) * 0.04 * (1.0 + on_kerb * 3.0)
	return spec.grip * tyre * surf * stiff * grip_scale * (spec.rear_grip if axle == 1 else 1.0)


func _pacejka(alpha: float) -> float:
	return sin(spec.tyre_c * atan(spec.tyre_b * alpha))


## Where each wheel is on the track, and so what it's running on.
func _sample_wheels() -> void:
	var rel := yaw - atan2(spot.tangent.x, spot.tangent.y)
	var sr := sin(rel)
	var cr := cos(rel)
	var kerb_n := 0
	var out := 0
	var off := 0
	var h := spot.half
	for w in 4:
		var along := spec.cg_front if w < 2 else -spec.cg_rear
		var side := spec.track_width * 0.5 * (1.0 if w % 2 == 0 else -1.0)
		var lat := spot.lat + along * sr + side * cr
		var surf := Surface.ROAD
		if absf(lat) > h:
			var s := spot.s + along * cr - side * sr
			surf = _surface_off_road(track.index_at(s), lat, h)
			if not spot.in_pit:
				if absf(lat) > h + 0.1:
					out += 1
		_wheel_surf[w] = surf
		if surf == Surface.KERB:
			kerb_n += 1
		elif surf == Surface.GRASS or surf == Surface.GRAVEL or surf == Surface.SAND:
			off += 1
	on_kerb = kerb_n / 4.0
	wheels_out = out
	off_track = off >= 2
	surface = _wheel_surf[0] if off < 2 else _wheel_surf[2]


func _surface_off_road(i: int, lat: float, h: float) -> int:
	if spot.in_pit:
		return Surface.PIT
	var side := 0 if lat > 0.0 else 1
	if track.kerb[side][i] and absf(lat) <= h + Track.KERB_WIDTH:
		return Surface.KERB
	match int(track.run_kind[side][i]):
		TrackPlan.Runoff.GRAVEL:
			return Surface.GRAVEL
		TrackPlan.Runoff.TARMAC, TrackPlan.Runoff.WALL:
			return Surface.TARMAC
		TrackPlan.Runoff.SAND:
			return Surface.SAND
	return Surface.GRASS


func _drive_force(throttle: float, vx: float) -> float:
	if throttle <= 0.0:
		return 0.0
	var ratio: float = spec.gears[gear]
	var wheel_rpm := absf(vx) / spec.wheel_radius * 60.0 / TAU
	var engine_rpm := maxf(wheel_rpm * ratio, spec.rpm_idle + throttle * 5200.0)
	if engine_rpm >= spec.rpm_limit:
		return 0.0
	var torque_cap := spec.power / (10500.0 / 60.0 * TAU) * ratio / spec.wheel_radius
	var p := spec.power_at(engine_rpm)
	return throttle * minf(torque_cap, p / maxf(absf(vx), 0.5))


func _gears(input: CarInput) -> void:
	var vx := forward_speed()
	# Reverse: held brake while stopped selects it; throttle forward clears it.
	if allow_reverse and not reverse and absf(vx) < 0.8 and input.brake > 0.6 and input.throttle < 0.05:
		_reverse_t += 1
		if _reverse_t > 60:
			reverse = true
	else:
		_reverse_t = 0
	if reverse:
		if input.brake < 0.05 and input.throttle < 0.05 and absf(vx) < 0.5:
			reverse = false
		return
	if auto_gears:
		if rpm > SHIFT_UP_RPM and gear < spec.gears.size() - 1:
			gear += 1
		elif gear > 0 and rpm < SHIFT_DOWN_RPM:
			var lower_rpm := _rpm_in(gear - 1, vx)
			if lower_rpm < SHIFT_UP_RPM - 600.0:
				gear -= 1
	else:
		if input.shift_up and gear < spec.gears.size() - 1:
			gear += 1
		if input.shift_down and gear > 0 and _rpm_in(gear - 1, vx) < spec.rpm_limit + 200.0:
			gear -= 1


func _rpm_in(g: int, vx: float) -> float:
	return absf(vx) / spec.wheel_radius * 60.0 / TAU * float(spec.gears[g])


func _gear_for(v: float) -> int:
	for g in spec.gears.size():
		if _rpm_in(g, v) < SHIFT_UP_RPM - 400.0:
			return g
	return spec.gears.size() - 1


func _engine_rpm() -> void:
	var vx := forward_speed()
	var target := _rpm_in(gear, vx)
	var idle := spec.rpm_idle + engine_load * 5200.0 * clampf(1.0 - absf(vx) / 25.0, 0.0, 1.0)
	target = maxf(target, idle)
	if rear_spin > 0.0:
		target += rear_spin * 2500.0
	rpm = lerpf(rpm, minf(target, spec.rpm_limit), 0.35)


func _tyres(dt: float, fx: float, fy: float, load: float) -> void:
	var use := clampf(Vector2(fx, fy).length() / maxf(load * spec.grip, 1.0), 0.0, 1.5)
	var rate := Tyres.wear_rate(compound, wetness) * wear_scale
	var moving := clampf(speed / 30.0, 0.0, 1.0)
	wear = minf(1.0, wear + dt * rate * moving * (0.35 + 0.65 * use * use) * (1.0 + sliding * 3.0))
	# Tyres warm up while driving hard and cool slowly when crawling.
	var heat := moving * (0.4 + use) - 0.3
	tyre_temp = clampf(tyre_temp + heat * dt / 30.0, 0.0, 1.0)


## Keeps the car's footprint inside the barriers (and on its side of the
## pit wall): whichever corner reaches furthest into one pushes the car back
## out, and a corner hitting it turns the car as well as slowing it.
func _barriers() -> void:
	for pass_i in 2:
		var side := 0 if spot.lat > 0.0 else 1
		var pit_wall := track.pit_wall_at(spot.s) or track.pit_wall_at(spot.s + nose) or track.pit_wall_at(spot.s - tail)
		# Nowhere near either: nothing to do.
		if not pit_wall and absf(spot.lat) < track.barrier_off(spot.s, side) - nose - 1.5:
			break
		var was_lane := false
		var pside := 0.0
		var wall := 0.0
		if pit_wall:
			pside = float(track.pit.side)
			wall = float(track.pit.wall_lat)
			was_lane = _last_lat * pside > wall
		var deepest := 0.0
		var hit_n := Vector2.ZERO
		var hit_r := Vector2.ZERO
		var f := forward2()
		var l := left2()
		for k in 4:
			var r := f * (nose if k < 2 else -tail) + l * (half_width if k % 2 == 0 else -half_width)
			var c := track.locate(Vector2(pos.x, pos.z) + r, spot.idx, _corner)
			var cside := 0 if c.lat > 0.0 else 1
			var over := absf(c.lat) - track.barrier_off(c.s, cside)
			if over > deepest:
				deepest = over
				hit_n = c.normal * (1.0 if c.lat > 0.0 else -1.0)
				hit_r = r
			if pit_wall and track.pit_wall_at(c.s):
				# Into the wall's face on the side the car came from.
				var rel := c.lat * pside - wall
				var depth := PIT_WALL_HALF - rel if was_lane else PIT_WALL_HALF + rel
				if depth > deepest and depth < PIT_WALL_HALF * 2.0 + half_width:
					deepest = depth
					hit_n = c.normal * (-pside if was_lane else pside)
					hit_r = r
		if deepest <= 0.0:
			break
		_hit_wall(hit_n, deepest, hit_r)
	_last_lat = spot.lat


## Pushes the car back off a wall facing -n (n points into the wall), hit by
## the point `r` from the car's middle.
func _hit_wall(n: Vector2, depth: float, r := Vector2.ZERO) -> void:
	pos.x -= n.x * depth
	pos.z -= n.y * depth
	# The point's own speed into the wall, with the car's turning.
	var arm := Vector2(r.y, -r.x).dot(n)
	var vn := vel.dot(n) + yaw_rate * arm
	if vn > 0.0:
		# A little bounce, shared between pushing the car back and turning it.
		var j := 1.2 * vn / (1.0 / spec.mass + arm * arm / spec.yaw_inertia)
		vel -= n * j / spec.mass
		yaw_rate -= arm * j / spec.yaw_inertia
		# Scraping along the wall.
		var t := Vector2(n.y, -n.x)
		var vt := vel.dot(t)
		vel -= t * vt * clampf(vn * 0.03, 0.0, 0.5)
		impact = maxf(impact, vn)
		wall_t = 0.0
		if vn > 6.0:
			var hit := (vn - 6.0) * 0.035 * damage_scale
			damage = minf(1.0, damage + hit)
			wing_damage = minf(1.0, wing_damage + hit * 1.6)
	track.locate(Vector2(pos.x, pos.z), spot.idx, spot)


## Contact with another car: called by the race with the push to apply.
func bump(push: Vector2, impulse: Vector2, hit_speed: float) -> void:
	pos.x += push.x
	pos.z += push.y
	vel += impulse
	track.locate(Vector2(pos.x, pos.z), spot.idx, spot)
	impact = maxf(impact, hit_speed)
	if hit_speed > 7.0:
		var hit := (hit_speed - 7.0) * 0.03 * damage_scale
		damage = minf(1.0, damage + hit)
		wing_damage = minf(1.0, wing_damage + hit * 1.4)
