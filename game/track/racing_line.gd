class_name RacingLine
extends RefCounted
## Works out a track's racing line and the speed a car can carry along it.
##
## The line is the path inside the white lines that bends least (minimum
## curvature), which gives the classic outside, apex, outside through each
## corner. The speeds come from the line's curvature and the car's grip
## and downforce, then braking and acceleration passes join them up.

## How close to the white line the line runs (half a car plus a little).
const EDGE_MARGIN := 1.25
## Kerbs on the inside of a corner can be used this much.
const KERB_USE := 0.9
## The share of the tyres' grip the AI's speeds use: a margin for bumps,
## kerbs and the car moving about.
const MU_SHARE := 0.885


static func compute(t: Track) -> void:
	var n := t.n
	var off := PackedFloat32Array()
	off.resize(n)
	var lim_l := PackedFloat32Array()
	var lim_r := PackedFloat32Array()
	lim_l.resize(n)
	lim_r.resize(n)
	for i in n:
		lim_l[i] = t.half[i] - EDGE_MARGIN + (KERB_USE if t.kerb[0][i] else 0.0)
		lim_r[i] = t.half[i] - EDGE_MARGIN + (KERB_USE if t.kerb[1][i] else 0.0)
	var cx := PackedFloat32Array()
	var cz := PackedFloat32Array()
	var nx := PackedFloat32Array()
	var nz := PackedFloat32Array()
	cx.resize(n)
	cz.resize(n)
	nx.resize(n)
	nz.resize(n)
	for i in n:
		cx[i] = t.pos[i].x
		cz[i] = t.pos[i].z
		nx[i] = t.normal[i].x
		nz[i] = t.normal[i].y
	# Minimum curvature: each point moves to where the fourth difference of
	# the path is zero (the path bends as evenly as it can), over long spans
	# first and then shorter ones.
	for pass_span in [[24, 60], [12, 80], [6, 100], [3, 120], [1, 160]]:
		var k: int = maxi(1, int(round(pass_span[0] * Track.STEP / t.step)))
		for _it in int(pass_span[1]):
			for i in n:
				var a2 := posmod(i - 2 * k, n)
				var a := posmod(i - k, n)
				var b := (i + k) % n
				var b2 := (i + 2 * k) % n
				var mx := (4.0 * (cx[a] + nx[a] * off[a] + cx[b] + nx[b] * off[b]) - (cx[a2] + nx[a2] * off[a2] + cx[b2] + nx[b2] * off[b2])) / 6.0
				var mz := (4.0 * (cz[a] + nz[a] * off[a] + cz[b] + nz[b] * off[b]) - (cz[a2] + nz[a2] * off[a2] + cz[b2] + nz[b2] * off[b2])) / 6.0
				var target := (mx - cx[i]) * nx[i] + (mz - cz[i]) * nz[i]
				off[i] = clampf(lerpf(off[i], target, 0.8), -lim_r[i], lim_l[i])
	t.line_off = off
	t.line_curv = _curvature(t, off)
	t.line_speed = speeds(t, CarSpec.new(), 1.0)


## Curvature of the line, from the circle through points 8 m either side.
static func _curvature(t: Track, off: PackedFloat32Array) -> PackedFloat32Array:
	var n := t.n
	var k := maxi(2, int(round(8.0 / t.step)))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := _pt(t, off, posmod(i - k, n))
		var b := _pt(t, off, i)
		var c := _pt(t, off, (i + k) % n)
		var ab := b - a
		var bc := c - b
		var ac := c - a
		var cross := ab.x * bc.y - ab.y * bc.x
		var denom := ab.length() * bc.length() * ac.length()
		# Positive turns left: a turn from +z towards +x has a negative cross.
		out[i] = -2.0 * cross / denom if denom > 0.0001 else 0.0
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		smooth[i] = (out[posmod(i - 1, n)] + out[i] * 2.0 + out[(i + 1) % n]) * 0.25
	return smooth


static func _pt(t: Track, off: PackedFloat32Array, i: int) -> Vector2:
	return Vector2(t.pos[i].x + t.normal[i].x * off[i], t.pos[i].z + t.normal[i].y * off[i])


## The fastest a car can take a bend of curvature `kappa` (1/m) on a flat
## road, with grip scaled by `grip_scale`.
static func corner_speed(spec: CarSpec, grip_scale: float, kappa: float) -> float:
	var mu := spec.grip * grip_scale * MU_SHARE
	var den := spec.mass * absf(kappa) - mu * 0.5 * CarSpec.AIR * spec.cl_a
	if den <= 0.0:
		return INF
	return sqrt(mu * spec.mass * CarSpec.G / den)


## The fastest speed (m/s) at each sample along the line for a car, with
## grip scaled by `grip_scale` (weather, tyres). Corners from the line's
## curvature; then a braking pass backwards and an acceleration pass forwards.
static func speeds(t: Track, spec: CarSpec, grip_scale: float) -> PackedFloat32Array:
	var n := t.n
	var mu := spec.grip * grip_scale * MU_SHARE
	var m := spec.mass
	var d := 0.5 * CarSpec.AIR * spec.cl_a
	var vmax := spec.top_gear_speed() * spec.rpm_limit / spec.rpm_max
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var kappa := absf(t.line_curv[i])
		# Banking helps: a banked corner adds g * sin(bank) towards the inside.
		var bank_help := absf(atan(t.bank[i])) if signf(t.bank[i]) * signf(-t.line_curv[i]) > 0.0 else -absf(atan(t.bank[i]))
		var g_eff := CarSpec.G * (1.0 + bank_help * 2.2)
		var den := m * kappa - mu * d
		if kappa < 0.00005 or den <= 0.0:
			v[i] = vmax
		else:
			v[i] = minf(vmax, sqrt(mu * m * g_eff / den))
	# Two laps of each pass so the wrap at the start line joins up.
	for _lap in 2:
		for kk in n:
			var i := n - 1 - kk
			var j := (i + 1) % n
			var vj := v[j]
			var a := _decel(spec, mu, vj, t.line_curv[j])
			var lim := sqrt(vj * vj + 2.0 * a * t.step)
			if v[i] > lim:
				v[i] = lim
	for _lap in 2:
		for i in n:
			var j := (i + 1) % n
			var vi := v[i]
			var a := _accel(spec, mu, vi, t.line_curv[i])
			var lim := sqrt(vi * vi + 2.0 * a * t.step)
			if v[j] > lim:
				v[j] = lim
	return v


## Braking deceleration available at speed v on a curve (friction circle).
static func _decel(spec: CarSpec, mu: float, v: float, kappa: float) -> float:
	var load := spec.mass * CarSpec.G + spec.downforce(v)
	var total := mu * load / spec.mass
	var lat := v * v * absf(kappa)
	var long := sqrt(maxf(0.0, total * total - lat * lat))
	return minf(long, spec.brake_force / spec.mass) * 0.92 + spec.drag(v) / spec.mass


## Acceleration available at speed v: engine power, traction and drag.
static func _accel(spec: CarSpec, mu: float, v: float, kappa: float) -> float:
	var load := spec.mass * CarSpec.G * (spec.cg_front / (spec.cg_front + spec.cg_rear)) + spec.downforce(v) * (1.0 - spec.aero_front)
	var total := mu * load / spec.mass
	var lat := v * v * absf(kappa)
	var traction := sqrt(maxf(0.0, total * total - lat * lat))
	var engine := spec.power * 0.92 / maxf(v, 8.0) / spec.mass
	return maxf(0.0, minf(traction, engine) - spec.drag(v) / spec.mass - 0.15)
