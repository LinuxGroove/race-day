class_name Terrain
extends RefCounted
## The ground round a circuit: a height grid that meets the track's edges,
## rolls away into the theme's landscape (hills, mountains, dunes) and keeps
## going to the horizon on a coarse outer grid. Water (lakes, rivers, the
## sea) is cut into it, and scenery asks it for heights and clear ground.
##
## Near the track the ground sits a little below the run-off, which a sloped
## verge covers, so the two never fight.

## Grid spacing near the track, and how far the detailed grid reaches past it.
const CELL := 10.0
const MARGIN := 700.0
## The ground sits this far under the track's edges.
const LOWER := 0.35
## Under the Racing Kit's tiles, which have no verge, the ground comes up
## to just under their grass.
const TILE_LOWER := 0.1
## Outer grid: spacing and reach from the middle of the circuit.
const FAR_CELL := 250.0
const FAR_REACH := 9000.0
const CHUNK_CELLS := 32

var track: Track
var roads: RoadBuilder
var theme := "parkland"

var origin := Vector2.ZERO
var nx := 0
var nz := 0
## Final heights at the grid's vertices.
var h := PackedFloat32Array()
## How far each vertex lies outside the barriers (negative inside them).
var d_out := PackedFloat32Array()
## Heights of the nearest track edge, for the vertices near the track.
var near_h := PackedFloat32Array()
## Water bodies: {"kind": "lake"/"river"/"sea", "level", "centre", "radius",
## "dir" (Vector2 for rivers and the sea), "width"}.
var waters: Array = []
## Raised or dug areas from landmarks: {"centre", "radius", "height", "kind"}.
var mounds: Array = []
var base_height := 0.0

var _noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _coarse := PackedFloat32Array()
var _cx := 0
var _cz := 0
const COARSE := 60.0


func _init(t: Track, r: RoadBuilder, p_theme: String) -> void:
	track = t
	roads = r
	theme = p_theme
	_noise.seed = hash(t.id) & 0xffff
	_noise.frequency = 1.0 / 900.0
	_noise.fractal_octaves = 4
	_detail_noise.seed = _noise.seed + 7
	_detail_noise.frequency = 1.0 / 120.0


## Theme: how rough the land gets away from the track (metres).
func _relief() -> float:
	match theme:
		"mountain":
			return 70.0
		"hills", "forest", "cliff":
			return 34.0
		"canyon":
			return 26.0
		"countryside", "parkland", "lake":
			return 12.0
		"desert":
			return 9.0
	return 4.0


## Builds the height grid. Call after adding waters and mounds.
func build() -> void:
	var lo := Vector2(track.bounds.position.x, track.bounds.position.z) - Vector2.ONE * MARGIN
	var hi := Vector2(track.bounds.end.x, track.bounds.end.z) + Vector2.ONE * MARGIN
	origin = lo
	nx = ceili((hi.x - lo.x) / CELL) + 1
	nz = ceili((hi.y - lo.y) / CELL) + 1
	var count := nx * nz
	h.resize(count)
	d_out.resize(count)
	near_h.resize(count)
	d_out.fill(1e6)
	near_h.fill(0.0)
	var sum := 0.0
	for p in track.pos:
		sum += p.y
	base_height = sum / track.n
	_splat_track()
	_coarse_field()
	for z in nz:
		for x in nx:
			var k := z * nx + x
			var p := origin + Vector2(x, z) * CELL
			h[k] = _height_for(p, d_out[k], near_h[k])
	_smooth_near()


## Every few metres along the lap, writes the nearest edge height and the
## distance outside the barrier to the grid vertices beside the track.
func _splat_track() -> void:
	var n := track.n
	var i := 0
	while i < n:
		if roads.deck[i]:
			i += 1
			continue
		var p := track.pos[i]
		var nn := track.normal[i]
		var t := track.tangent[i]
		for side in 2:
			var sg := RoadBuilder.sgn(side)
			var b: float = roads.bar[side][i]
			var reach := b + 70.0
			var lat := 0.0
			while lat <= reach:
				var q := Vector2(p.x + nn.x * lat * sg, p.z + nn.y * lat * sg)
				var gx := roundi((q.x - origin.x) / CELL)
				var gz := roundi((q.y - origin.y) / CELL)
				if gx >= 0 and gz >= 0 and gx < nx and gz < nz:
					var k := gz * nx + gx
					var v := origin + Vector2(gx, gz) * CELL
					var rel := v - Vector2(p.x, p.z)
					var vlat := rel.dot(nn)
					var along := rel.dot(t)
					var side_v := 0 if vlat > 0.0 else 1
					var bb: float = roads.bar[side_v][i]
					var dd := absf(vlat) - bb
					if dd < d_out[k] and absf(along) < 12.0:
						d_out[k] = dd
						var slope := (track.pos[(i + 1) % n].y - p.y) / track.step
						near_h[k] = p.y + clampf(vlat, -track.half[i], track.half[i]) * track.bank[i] + along * slope
				lat += 4.0
		i += 2


## A smooth field of the track's heights, so the land between parts of the
## lap sits at a sensible level.
func _coarse_field() -> void:
	_cx = ceili(nx * CELL / COARSE) + 2
	_cz = ceili(nz * CELL / COARSE) + 2
	_coarse.resize(_cx * _cz)
	var pts := []
	var stride := maxi(1, track.n / 160)
	for i in range(0, track.n, stride):
		pts.append(track.pos[i])
	for z in _cz:
		for x in _cx:
			var p := origin + Vector2(x, z) * COARSE
			var ws := 0.0
			var hs := 0.0
			for q in pts:
				var v: Vector3 = q
				var d2 := (v.x - p.x) * (v.x - p.x) + (v.z - p.y) * (v.z - p.y)
				var w := 1.0 / (d2 + 22500.0)
				w *= w
				ws += w
				hs += w * v.y
			_coarse[z * _cx + x] = hs / ws if ws > 0.0 else base_height


func _coarse_at(p: Vector2) -> float:
	var fx := clampf((p.x - origin.x) / COARSE, 0.0, _cx - 1.001)
	var fz := clampf((p.y - origin.y) / COARSE, 0.0, _cz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(_coarse[z0 * _cx + x0], _coarse[z0 * _cx + x0 + 1], tx)
	var b := lerpf(_coarse[(z0 + 1) * _cx + x0], _coarse[(z0 + 1) * _cx + x0 + 1], tx)
	return lerpf(a, b, tz)


## How far a point is from the edge of the detailed grid (0 at the edge).
func _edge_fade(p: Vector2) -> float:
	var ex := minf(p.x - origin.x, origin.x + (nx - 1) * CELL - p.x)
	var ez := minf(p.y - origin.y, origin.y + (nz - 1) * CELL - p.y)
	return smoothstep(0.0, 350.0, minf(ex, ez))


func _height_for(p: Vector2, dd: float, nh: float) -> float:
	var fade := _edge_fade(p)
	var away := smoothstep(25.0, 260.0, dd)
	var land := lerpf(base_height, _coarse_at(p), fade)
	var relief := _relief()
	var nz_v := _noise.get_noise_2dv(p) * relief * 1.6 + _detail_noise.get_noise_2dv(p) * relief * 0.18
	land += nz_v * away * fade + _far_rise(p) * (1.0 - fade)
	land = _shape(p, land, dd)
	var near := smoothstep(6.0, 45.0, dd)
	if dd > 9e5:
		near = 1.0
	return lerpf(nh - (TILE_LOWER if roads.tiles else LOWER), land, near)


## The land's shape far out, matching the outer grid at the detailed grid's edge.
func _far_rise(_p: Vector2) -> float:
	return 0.0


## Water and landmark mounds shape the land.
func _shape(p: Vector2, land: float, dd: float) -> float:
	var clear := smoothstep(10.0, 40.0, dd)
	if dd > 9e5:
		clear = 1.0
	for m in mounds:
		var c: Vector2 = m.centre
		var r: float = m.radius
		var d := p.distance_to(c)
		if d < r:
			var f := 0.5 + 0.5 * cos(PI * d / r)
			if m.kind == "dunes":
				f *= 0.6 + 0.4 * sin(p.x * 0.05 + p.y * 0.03)
			# Hills and dunes keep back from the track; canyon walls crowd it.
			var room := clear if m.kind == "rock" else (smoothstep(30.0, 160.0, dd) if dd < 9e5 else 1.0)
			land += float(m.height) * f * room
	for w in waters:
		var depth := water_depth_mask(w, p)
		if depth > 0.0:
			land = lerpf(land, float(w.level) - 4.0, depth * clear)
	return land


## 0 outside a water body, rising to 1 a little way inside its edge.
func water_depth_mask(w: Dictionary, p: Vector2) -> float:
	match str(w.kind):
		"lake":
			var d := p.distance_to(w.centre)
			return 1.0 - smoothstep(float(w.radius) - 30.0, float(w.radius), d)
		"river":
			var dir: Vector2 = w.dir
			var rel: Vector2 = p - w.centre
			var across := absf(rel.dot(Vector2(-dir.y, dir.x)))
			var along := absf(rel.dot(dir))
			if along > float(w.length) * 0.5:
				return 0.0
			return 1.0 - smoothstep(float(w.width) * 0.5 - 12.0, float(w.width) * 0.5, across)
		"sea":
			var dir: Vector2 = w.dir
			var c: Vector2 = w.centre
			var out := (p - c).dot(dir)
			return smoothstep(-20.0, 20.0, out)
	return 0.0


## Whether a point is under water.
func is_water(p: Vector2) -> bool:
	for w in waters:
		if water_depth_mask(w, p) > 0.3 and height(p.x, p.y) < float(w.level):
			return true
	return false


## Blurs the band between the track and the open land once, to take the
## steps out of the splatted heights.
func _smooth_near() -> void:
	var out: PackedFloat32Array = h.duplicate()
	for z in range(1, nz - 1):
		for x in range(1, nx - 1):
			var k := z * nx + x
			var dd := d_out[k]
			if dd < 6.0 or dd > 120.0:
				continue
			var s := 0.0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					s += h[k + dz * nx + dx]
			out[k] = s / 9.0
	h = out


## The ground height at a point (on the detailed grid; outside it the far land).
func height(x: float, z: float) -> float:
	var fx := (x - origin.x) / CELL
	var fz := (z - origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= nx - 1 or fz >= nz - 1:
		return far_height(Vector2(x, z))
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var k := z0 * nx + x0
	var a := lerpf(h[k], h[k + 1], tx)
	var b := lerpf(h[k + nx], h[k + nx + 1], tx)
	return lerpf(a, b, tz)


## How far a point lies outside the barriers (huge where nothing was splatted).
func clearance(x: float, z: float) -> float:
	var gx := roundi((x - origin.x) / CELL)
	var gz := roundi((z - origin.y) / CELL)
	if gx < 0 or gz < 0 or gx >= nx or gz >= nz:
		return 1e6
	var best := 1e6
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var xx := clampi(gx + dx, 0, nx - 1)
			var zz := clampi(gz + dz, 0, nz - 1)
			best = minf(best, d_out[zz * nx + xx])
	return best


## The land beyond the detailed grid, out to the horizon.
func far_height(p: Vector2) -> float:
	var c := Vector2(track.bounds.get_center().x, track.bounds.get_center().z)
	var r := p.distance_to(c)
	var inner := maxf(track.bounds.size.x, track.bounds.size.z) * 0.5 + MARGIN
	var t := smoothstep(inner * 0.8, inner + 3500.0, r)
	var rise := 0.0
	match theme:
		"mountain":
			rise = 650.0
		"canyon":
			rise = 260.0
		"hills", "forest", "cliff":
			rise = 220.0
		"desert":
			rise = 70.0
		"countryside", "parkland", "lake", "airfield":
			rise = 90.0
		"city", "harbour", "oval", "proving":
			rise = 40.0
	var ridge := (_noise.get_noise_2d(p.x * 0.35, p.y * 0.35) * 0.6 + 0.55)
	var land := base_height - 2.0 + rise * t * maxf(0.0, ridge)
	for w in waters:
		if str(w.kind) == "sea":
			var depth := water_depth_mask(w, p)
			land = lerpf(land, float(w.level) - 6.0, depth)
	return land


## The terrain colour near a point (for verges).
func near_colour(_x: float, _z: float) -> Color:
	var cols: Array = WorldLook.TERRAIN.get(theme, WorldLook.TERRAIN["parkland"])
	return cols[0]


# --- Meshes --------------------------------------------------------------

## The detailed grid as chunked meshes, plus the outer land.
func meshes(detail: int) -> Array:
	var out := []
	var cols: Array = WorldLook.TERRAIN.get(theme, WorldLook.TERRAIN["parkland"])
	var c_near: Color = cols[0]
	var c_far: Color = cols[1]
	var rock := WorldLook.RED_ROCK if theme == "canyon" or theme == "desert" else WorldLook.ROCK
	var normals := PackedVector3Array()
	normals.resize(nx * nz)
	for z in nz:
		for x in nx:
			var hl := h[z * nx + maxi(x - 1, 0)]
			var hr := h[z * nx + mini(x + 1, nx - 1)]
			var hd := h[maxi(z - 1, 0) * nx + x]
			var hu := h[mini(z + 1, nz - 1) * nx + x]
			normals[z * nx + x] = Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
	var colours := PackedColorArray()
	colours.resize(nx * nz)
	for z in nz:
		for x in nx:
			var k := z * nx + x
			var p := origin + Vector2(x, z) * CELL
			var dd := d_out[k]
			var t := smoothstep(20.0, 300.0, dd) if dd < 9e5 else 1.0
			var col := c_near.lerp(c_far, t * (0.5 + 0.5 * _detail_noise.get_noise_2dv(p * 2.0)))
			# Mowing stripes near the track.
			if dd < 60.0 and theme != "desert" and theme != "canyon":
				var stripe := int(floorf((p.x + p.y) / 14.0)) % 2 == 0
				if stripe:
					col = col.darkened(0.04)
			var steep := 1.0 - normals[k].y
			if steep > 0.25:
				col = col.lerp(rock, smoothstep(0.25, 0.5, steep))
			for w in waters:
				if water_depth_mask(w, p) > 0.0 and h[k] < float(w.level) + 1.2:
					col = WorldLook.SHORE
			colours[k] = WorldLook.wet(col, 0.2)
	var step := 1 if detail >= 1 else 2
	for cz in range(0, nz - 1, CHUNK_CELLS):
		for cx in range(0, nx - 1, CHUNK_CELLS):
			var b := MeshBuf.new()
			var z := cz
			while z < mini(cz + CHUNK_CELLS, nz - 1):
				var x := cx
				var z2 := mini(z + step, nz - 1)
				while x < mini(cx + CHUNK_CELLS, nx - 1):
					var x2 := mini(x + step, nx - 1)
					var k00 := z * nx + x
					var k10 := z * nx + x2
					var k11 := z2 * nx + x2
					var k01 := z2 * nx + x
					# Skip cells wholly under the road.
					if d_out[k00] < -3.0 and d_out[k10] < -3.0 and d_out[k11] < -3.0 and d_out[k01] < -3.0:
						x = x2
						continue
					b.quad_smooth(_v(x, z), _v(x2, z), _v(x2, z2), _v(x, z2), normals[k00], normals[k10], normals[k11], normals[k01], colours[k00], colours[k10], colours[k11], colours[k01])
					x = x2
				z = z2
			if not b.is_empty():
				out.append(b.commit(null, WorldLook.ground()))
	out.append(_far_mesh(c_far, rock))
	return out


func _v(x: int, z: int) -> Vector3:
	return Vector3(origin.x + x * CELL, h[z * nx + x], origin.y + z * CELL)


## A coarse ring of land out to the horizon, tucked just under the detailed
## grid where they overlap.
func _far_mesh(col: Color, rock: Color) -> ArrayMesh:
	var c := Vector2(track.bounds.get_center().x, track.bounds.get_center().z)
	var n := ceili(FAR_REACH * 2.0 / FAR_CELL)
	var o := c - Vector2.ONE * FAR_REACH
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	var lo := origin + Vector2.ONE * CELL * 2.0
	var hi := origin + Vector2(nx - 3, nz - 3) * CELL
	for z in n + 1:
		for x in n + 1:
			var p := o + Vector2(x, z) * FAR_CELL
			var y := far_height(p)
			if p.x > lo.x and p.y > lo.y and p.x < hi.x and p.y < hi.y:
				y = minf(y, height(clampf(p.x, origin.x, hi.x), clampf(p.y, origin.y, hi.y)) - 3.0)
			hs[z * (n + 1) + x] = y
	var b := MeshBuf.new()
	for z in n:
		for x in n:
			var p := o + Vector2(x, z) * FAR_CELL
			var a := Vector3(p.x, hs[z * (n + 1) + x], p.y)
			var bb := Vector3(p.x + FAR_CELL, hs[z * (n + 1) + x + 1], p.y)
			var cc := Vector3(p.x + FAR_CELL, hs[(z + 1) * (n + 1) + x + 1], p.y + FAR_CELL)
			var d := Vector3(p.x, hs[(z + 1) * (n + 1) + x], p.y + FAR_CELL)
			var steep := absf(cc.y - a.y) / FAR_CELL
			var k := col.lerp(rock, smoothstep(0.15, 0.5, steep))
			if theme == "mountain" and maxf(a.y, cc.y) > base_height + 420.0:
				k = Color("f2f4f8")
			b.quad(a, bb, cc, d, WorldLook.wet(k, 0.1))
	return b.commit(null, WorldLook.ground())
