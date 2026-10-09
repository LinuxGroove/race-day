class_name Scenery
extends RefCounted
## The land's dressing: water bodies and hills from the landmarks (shaped
## into the terrain before it is built), then trees, rocks, buildings and
## boats by the circuit's theme, and every landmark kind.
##
## Everything repeated goes through one Scatter (MultiMeshes in cells with
## visibility ranges); `detail` sets how many trees and props there are.

const TREE_BUDGET := [1400, 3200, 6500]
## Nature Kit leaves are minty; this greens them to sit with the grass.
const TREE_TINT := Color(0.78, 0.96, 0.62)

var view: TrackView
var track: Track
var terrain: Terrain
var roads: RoadBuilder
var detail := 1
var rng := RandomNumberGenerator.new()
var scatter := PropKit.Scatter.new(700.0)
var root: Node3D
var _density := FastNoiseLite.new()


func _init(v: TrackView) -> void:
	view = v
	track = v.track
	terrain = v.terrain
	roads = v.roads
	detail = v.detail
	rng.seed = hash(track.id + "scenery")
	_density.seed = rng.seed & 0xffff
	_density.frequency = 1.0 / 260.0


## The centre of a landmark on the ground plane.
func landmark_point(l: Dictionary, extra := 0.0) -> Vector2:
	var p := track.world(float(l.s), float(l.side) * (float(l.distance) + extra))
	return Vector2(p.x, p.z)


## The lowest track height within `r` metres of a point.
func track_low(p: Vector2, r: float) -> float:
	var low := INF
	for i in track.samples_near(p, r):
		low = minf(low, track.pos[i].y)
	if low == INF:
		var sum := 0.0
		for q in track.pos:
			sum += q.y
		low = sum / track.n
	return low


## Water and hills go into the terrain before it is built.
func shape_land() -> void:
	terrain = view.terrain
	for l in track.landmarks:
		var kind := str(l.kind)
		var size := float(l.get("size", 80.0))
		var c := landmark_point(l)
		var side := float(l.side)
		var i := track.index_at(float(l.s))
		var nrm := track.normal[i] * side
		var tan := track.tangent[i]
		match kind:
			"lake", "marina":
				terrain.waters.append({"kind": "lake", "centre": c, "radius": size * 0.5, "level": track_low(c, size * 0.5 + 120.0) - 1.6})
			"river":
				var crossing := float(l.distance) < size * 0.5
				var dir := nrm if crossing else tan
				var w := clampf(size * 0.35, 30.0, 90.0)
				terrain.waters.append({"kind": "river", "centre": c, "dir": dir, "width": w, "length": 4000.0 if crossing else size * 2.5, "level": track_low(c, 150.0) - 4.0})
			"sea":
				var drop := 28.0 if view.theme() == "cliff" else 2.2
				terrain.waters.append({"kind": "sea", "centre": landmark_point(l, -size * 0.25), "dir": nrm, "level": track_low(c, size + 200.0) - drop})
			"hills":
				terrain.mounds.append({"kind": "hills", "centre": c, "radius": size * 0.6, "height": clampf(size * 0.12, 10.0, 40.0)})
			"dunes":
				terrain.mounds.append({"kind": "dunes", "centre": c, "radius": size * 0.6, "height": clampf(size * 0.08, 6.0, 22.0)})
			"rock_wall":
				for k in range(-int(size * 0.5), int(size * 0.5) + 1, 40):
					var q := track.world(float(l.s) + k, side * float(l.distance))
					terrain.mounds.append({"kind": "rock", "centre": Vector2(q.x, q.z), "radius": 55.0, "height": 34.0})


## Places the theme's scenery and the landmarks' models.
func build() -> void:
	root = Node3D.new()
	root.name = "Scenery"
	view.add_child(root)
	_water_planes()
	for l in track.landmarks:
		_landmark(l)
	_theme()
	scatter.build(root)


# --- Placing -------------------------------------------------------------

## Whether a spot is open land: clear of the track by `room` metres, not
## under water, not on a building's footprint.
func is_free(p: Vector2, room := 8.0) -> bool:
	if terrain.clearance(p.x, p.y) < room:
		return false
	if terrain.is_water(p):
		return false
	for r in view.taken:
		if (r as Rect2).has_point(p):
			return false
	return true


func ground(p: Vector2) -> float:
	return terrain.height(p.x, p.y)


## Adds a model at a point on the ground, turned `yaw`, scaled `sc`.
func put(m: Mesh, p: Vector2, yaw: float, sc: float, vis := 0.0, sink := 0.2, shadow := true) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
	scatter.add(m, Transform3D(b, Vector3(p.x, ground(p) - sink, p.y)), vis, shadow)


## A random spot beside the track, `from` to `to` metres beyond the barrier.
func near_track(from: float, to: float) -> Vector2:
	var i := rng.randi() % track.n
	var side := rng.randi() % 2
	var d := float(roads.bar[side][i]) + rng.randf_range(from, to)
	var nn := track.normal[i] * RoadBuilder.sgn(side)
	var p := Vector2(track.pos[i].x, track.pos[i].z) + nn * d
	return p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))


func _models(dir: String, names: Array, tint := Color.WHITE) -> Array:
	var out := []
	for nm in names:
		out.append(PropKit.mesh(dir + str(nm) + ".glb", true, tint))
	return out


func vis(near: float) -> float:
	return near * [0.6, 1.0, 1.4][detail]


# --- Themes --------------------------------------------------------------

## Trees and props by theme: [models, scale range, how many of the budget,
## how close to the track they may grow].
func _theme() -> void:
	var t := view.theme()
	var nk := PropKit.NATURE
	var leafy := _models(nk, ["tree_default", "tree_oak", "tree_fat", "tree_simple", "tree_default_dark"], TREE_TINT)
	var pines := _models(nk, ["tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineRoundD", "tree_pineTallD"], TREE_TINT)
	var palms := _models(nk, ["tree_palmTall", "tree_palm", "tree_palmBend"], TREE_TINT)
	var bushes := _models(nk, ["plant_bushLarge", "plant_bush"], TREE_TINT)
	var rocks := _models(nk, ["rock_largeA", "rock_largeB", "rock_largeD", "rock_tallA", "rock_tallB"])
	var red_rocks := _models(nk, ["rock_tallA", "rock_tallB", "rock_tallE", "rock_tallH", "rock_largeD", "rock_largeF"], Color(1.25, 0.72, 0.52))
	var cacti := _models(nk, ["cactus_tall", "cactus_short"])
	var budget: int = TREE_BUDGET[detail]
	match t:
		"parkland", "lake", "oval":
			_trees(leafy, budget * (0.5 if t == "oval" else 1.0), Vector2(9, 13), 10.0, 0.0)
			_trees(bushes, budget * 0.15, Vector2(6, 9), 6.0, 0.0)
		"forest", "mountain":
			_trees(pines, budget * 1.3, Vector2(9, 15), 8.0, -0.25)
			_trees(rocks, budget * 0.08, Vector2(8, 18), 12.0, 0.0)
			_trees(leafy, budget * 0.2, Vector2(9, 12), 12.0, 0.1)
		"hills", "cliff":
			_trees(leafy, budget * 0.6, Vector2(9, 13), 10.0, 0.0)
			_trees(pines, budget * 0.5, Vector2(9, 13), 10.0, 0.0)
			_trees(rocks, budget * 0.08, Vector2(8, 16), 12.0, 0.0)
		"countryside":
			_hedgerows(leafy, budget)
			_trees(leafy, budget * 0.3, Vector2(9, 13), 10.0, 0.2)
		"desert":
			_trees(cacti, budget * 0.3, Vector2(9, 14), 8.0, 0.0)
			_trees(rocks, budget * 0.08, Vector2(8, 16), 12.0, 0.0)
			_trees(palms, budget * 0.08, Vector2(9, 12), 10.0, 0.3)
		"canyon":
			_trees(red_rocks, budget * 0.25, Vector2(12, 30), 10.0, 0.0)
			_trees(cacti, budget * 0.15, Vector2(9, 13), 8.0, 0.0)
		"airfield":
			_trees(leafy, budget * 0.25, Vector2(9, 13), 40.0, 0.3)
			_airfield()
		"harbour":
			_trees(palms, budget * 0.25, Vector2(9, 12), 8.0, 0.0)
			_city(0.6)
		"city":
			_trees(leafy, budget * 0.15, Vector2(7, 10), 8.0, 0.0)
			_city(1.0)
		"proving":
			_trees(leafy, budget * 0.3, Vector2(9, 13), 30.0, 0.3)
			_proving()


## Scatters `count` copies near the track and on the land beyond, in
## clumps where the density noise allows (`clump` -1 dense to 1 sparse).
func _trees(models: Array, count: float, scale_range: Vector2, room: float, clump: float) -> void:
	var placed := 0
	var tries := 0
	var target := int(count)
	while placed < target and tries < target * 6:
		tries += 1
		var p: Vector2
		if rng.randf() < 0.7:
			p = near_track(room, room + 220.0 * pow(rng.randf(), 1.6) + 10.0)
		else:
			p = terrain.origin + Vector2(rng.randf() * terrain.nx, rng.randf() * terrain.nz) * Terrain.CELL
		if _density.get_noise_2dv(p) < clump:
			continue
		if not is_free(p, room):
			continue
		var m: Mesh = models[rng.randi() % models.size()]
		put(m, p, rng.randf() * TAU, rng.randf_range(scale_range.x, scale_range.y), vis(1100.0), 0.3)
		placed += 1


## Lines of trees along field edges, for farmland.
func _hedgerows(models: Array, budget: int) -> void:
	var lines := 40 + detail * 20
	for k in lines:
		var a := near_track(30.0, 400.0)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var length := rng.randf_range(120.0, 400.0)
		var step := 14.0
		var d := 0.0
		while d < length:
			var p := a + dir * d
			if is_free(p, 12.0):
				put(models[rng.randi() % models.size()], p, rng.randf() * TAU, rng.randf_range(8.0, 11.0), vis(1000.0), 0.3)
			d += step + rng.randf() * 6.0


# --- Town and city -------------------------------------------------------

## Blocks of buildings round the track; `amount` 1 for a city, less for a
## harbour town.
func _city(amount: float) -> void:
	var city := _models(PropKit.CITY, ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h", "building-i", "building-j", "building-k", "building-l"])
	var tall := _models(PropKit.CITY, ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e", "building-m", "building-n"])
	var far := _models(PropKit.CITY, ["low-detail-building-a", "low-detail-building-b", "low-detail-building-c", "low-detail-building-d", "low-detail-building-e", "low-detail-building-wide-a"])
	# Buildings line the track, a street's width behind the barrier.
	var s := 0.0
	var gap := 26.0 / amount
	while s < track.length:
		for side in 2:
			if rng.randf() > 0.75 * amount + 0.2:
				continue
			var i := track.index_at(s)
			var d := float(roads.bar[side][i]) + rng.randf_range(14.0, 24.0)
			var nn := track.normal[i] * RoadBuilder.sgn(side)
			var p := Vector2(track.pos[i].x, track.pos[i].z) + nn * d
			if not is_free(p, 10.0):
				continue
			var yaw := atan2(-nn.x, -nn.y)
			var m: Mesh = city[rng.randi() % city.size()]
			if rng.randf() < 0.22 * amount:
				m = tall[rng.randi() % tall.size()]
			put(m, p, yaw, 12.0, 0.0, 0.5)
			_claim(p, 10.0)
		s += gap
	# A skyline further out (low-detail blocks).
	var count := int((120 + detail * 80) * amount)
	for k in count:
		var p := near_track(90.0, 600.0)
		if not is_free(p, 40.0):
			continue
		put(far[rng.randi() % far.size()], p, rng.randf() * TAU, rng.randf_range(12.0, 22.0), 0.0, 0.5)
		_claim(p, 8.0)
	# Street lights along the barriers.
	var lamp := PropKit.mesh(PropKit.ROADS + "light-curved.glb")
	s = 0.0
	while s < track.length:
		var i := track.index_at(s)
		var side := int(s / 55.0) % 2
		var nn := track.normal[i] * RoadBuilder.sgn(side)
		var p := Vector2(track.pos[i].x, track.pos[i].z) + nn * (float(roads.bar[side][i]) + 2.0)
		if is_free(p, 1.0):
			put(lamp, p, atan2(-nn.x, -nn.y) + PI * 0.5, 9.0, vis(500.0), 0.0)
		s += 55.0


func _claim(p: Vector2, r: float) -> void:
	view.taken.append(Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0))


# --- Airfield and proving ground -----------------------------------------

func _airfield() -> void:
	var radar := PropKit.mesh(PropKit.V1 + "radarEquipment.glb")
	var dish := PropKit.mesh(PropKit.SPACE + "satelliteDish_large.glb")
	for k in 4 + detail * 2:
		var p := near_track(40.0, 300.0)
		if is_free(p, 30.0):
			put(radar if k % 2 == 0 else dish, p, rng.randf() * TAU, 14.0 if k % 2 == 0 else 22.0, vis(1500.0))
			_claim(p, 12.0)
	_runway(near_track(160.0, 260.0), rng.randf() * TAU, 900.0)


## An old runway: a long concrete strip with its markings.
func _runway(c: Vector2, yaw: float, length: float) -> void:
	var b := MeshBuf.new()
	var dir := Vector2(sin(yaw), cos(yaw))
	var acr := Vector2(dir.y, -dir.x)
	var w := 45.0
	var steps := int(length / 30.0)
	for k in steps:
		var a := c + dir * (-length * 0.5 + k * 30.0)
		var e := a + dir * 30.0
		var pa := [a - acr * w * 0.5, e - acr * w * 0.5, e + acr * w * 0.5, a + acr * w * 0.5]
		var vs := []
		var ok := true
		for q in pa:
			var qq: Vector2 = q
			if terrain.clearance(qq.x, qq.y) < 6.0:
				ok = false
			vs.append(Vector3(qq.x, ground(qq) + 0.12, qq.y))
		if not ok:
			continue
		b.quad(vs[0], vs[1], vs[2], vs[3], WorldLook.wet(Color("a9aab0"), 0.9))
		if k % 2 == 0:
			var m0 := a + dir * 4.0
			var m1 := a + dir * 20.0
			var ys := ground(m0) + 0.16
			b.quad(Vector3(m0.x - acr.x * 0.6, ys, m0.y - acr.y * 0.6), Vector3(m1.x - acr.x * 0.6, ys, m1.y - acr.y * 0.6), Vector3(m1.x + acr.x * 0.6, ys, m1.y + acr.y * 0.6), Vector3(m0.x + acr.x * 0.6, ys, m0.y + acr.y * 0.6), WorldLook.wet(WorldLook.LINE, 0.9))
	if not b.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = b.commit(null, WorldLook.ground())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _proving() -> void:
	var sheds := _models(PropKit.INDUSTRY, ["building-a", "building-c", "building-g", "building-q"])
	for k in 5:
		var p := near_track(50.0, 180.0)
		if is_free(p, 30.0):
			put(sheds[k % sheds.size()], p, rng.randf() * TAU, 12.0, 0.0, 0.3)
			_claim(p, 16.0)
	var cone := PropKit.mesh(PropKit.V2 + "traffic-cone.glb")
	for c in track.corners:
		for k in 3:
			var s := float(c.start) - 60.0 - k * 50.0
			var i := track.index_at(track.wrap_s(s))
			var side := 0 if float(c.dir) < 0.0 else 1
			var q := roads.point(i, RoadBuilder.sgn(side) * (track.half[i] + 2.5))
			scatter.add(cone, Transform3D(Basis().scaled(Vector3.ONE * 3.0), q), vis(300.0), false)


# --- Water ---------------------------------------------------------------

func _water_planes() -> void:
	for w in terrain.waters:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var c: Vector2 = w.centre
		match str(w.kind):
			"lake":
				pm.size = Vector2.ONE * float(w.radius) * 2.2
			"river":
				pm.size = Vector2(float(w.width) + 30.0, float(w.length))
				var dir: Vector2 = w.dir
				mi.rotation.y = atan2(dir.x, dir.y)
			"sea":
				pm.size = Vector2.ONE * 24000.0
				var dir: Vector2 = w.dir
				c += dir * 11800.0
		pm.material = WorldLook.water()
		mi.mesh = pm
		mi.position = Vector3(c.x, float(w.level), c.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Boats on a water body near a point, within `radius`.
func _boats(c: Vector2, radius: float, models: Array, count: int, level: float, scale: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		if not terrain.is_water(p) or ground(p) > level - 1.5:
			continue
		var m: Mesh = models[rng.randi() % models.size()]
		scatter.add(m, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), Vector3(p.x, level - 0.3, p.y)), vis(1400.0), true)
		placed += 1


func _water_of(c: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for w in terrain.waters:
		var wc: Vector2 = w.centre
		var d := wc.distance_to(c)
		if d < bd:
			bd = d
			best = w
	return best


# --- Landmarks -----------------------------------------------------------

func _landmark(l: Dictionary) -> void:
	var kind := str(l.kind)
	var size := float(l.get("size", 80.0))
	var c := landmark_point(l)
	var side := float(l.side)
	var i := track.index_at(float(l.s))
	var nrm := track.normal[i] * side
	var face := atan2(-nrm.x, -nrm.y)
	var wk := WATERCRAFT_SCALE
	match kind:
		"lake":
			var w := _water_of(c)
			_boats(c, size * 0.45, _models(PropKit.WATERCRAFT, ["boat-row-small", "boat-row-large"]), 6 + detail * 3, float(w.get("level", 0.0)), wk)
			_ring_trees(c, size * 0.5 + 12.0, 26 + detail * 12)
		"marina":
			var w := _water_of(c)
			var lvl := float(w.get("level", 0.0))
			_jetties(c, size, lvl, nrm)
			_boats(c, size * 0.4, _models(PropKit.WATERCRAFT, ["boat-speed-a", "boat-speed-d", "boat-sail-a", "boat-sail-b", "boat-speed-j"]), 8 + detail * 6, lvl, wk)
		"sea":
			var w := _water_of(c)
			var lvl := float(w.get("level", 0.0))
			var far := c + nrm * size * 0.5
			_boats(far, size * 0.6, _models(PropKit.WATERCRAFT, ["boat-sail-a", "boat-sail-b", "boat-speed-c", "boat-fishing-small"]), 6 + detail * 4, lvl, wk)
			_boats(far + nrm * size, size * 0.6, _models(PropKit.WATERCRAFT, ["ship-cargo-a", "ship-ocean-liner", "ship-large"]), 2 + detail, lvl, wk * 1.6)
		"river":
			var w := _water_of(c)
			_boats(c, 140.0, _models(PropKit.WATERCRAFT, ["boat-row-small", "boat-tug-c"]), 2 + detail, float(w.get("level", 0.0)), wk)
		"buildings":
			_block_of(c, size, face, _models(PropKit.CITY, ["building-a", "building-b", "building-f", "building-g", "building-i", "building-l", "building-skyscraper-a", "building-skyscraper-c"]), 12.0, 30.0)
		"village":
			_block_of(c, size, face, _models(PropKit.SUBURB, ["building-type-a", "building-type-b", "building-type-c", "building-type-d", "building-type-f", "building-type-k", "building-type-n", "building-type-t"]), 8.0, 26.0)
			_ring_trees(c, size * 0.5, 14 + detail * 6)
		"hangars":
			_row(c, size, face, nrm, _models(PropKit.SPACE, ["hangar_largeA", "hangar_roundA", "hangar_largeB"]), 15.0)
			_runway(c + nrm * 110.0, face + PI * 0.5, maxf(size * 2.5, 600.0))
		"forest":
			_forest(c, size)
		"cliff":
			_rocks(c, size, 26, Vector2(20.0, 42.0), Color.WHITE if view.theme() != "canyon" else Color(1.25, 0.72, 0.52))
		"rock_wall":
			for k in range(-int(size * 0.5), int(size * 0.5) + 1, 22):
				var q := track.world(track.wrap_s(float(l.s) + k), side * (float(l.distance) + rng.randf_range(0.0, 20.0)))
				var p := Vector2(q.x, q.z)
				if is_free(p, 4.0):
					var m := PropKit.mesh(PropKit.NATURE + ["rock_tallA", "rock_tallB", "rock_tallH", "rock_tallE"][rng.randi() % 4] + ".glb", true, Color(1.25, 0.72, 0.52) if view.theme() in ["canyon", "desert"] else Color.WHITE)
					put(m, p, rng.randf() * TAU, rng.randf_range(28.0, 46.0), 0.0, 4.0)
		"farm":
			_farm(c, size, face)
		"dunes":
			_trees(_models(PropKit.NATURE, ["cactus_tall", "rock_largeA"]), 10 + detail * 6, Vector2(8, 12), 20.0, -1.0)
		"hills":
			_forest(c, size * 0.6)
		"lighthouse":
			_lighthouse(c)
		"pits_tower":
			var m := PropKit.mesh(PropKit.CITY + "building-skyscraper-a.glb")
			put(m, c, face, 11.0, 0.0, 0.5)
			_claim(c, 12.0)
		"big_screen":
			_big_screen(c, face, maxf(size, 16.0))
		"windmills":
			_windmills(c, size)


const WATERCRAFT_SCALE := 3.0


## Trees in a ring round a point (a lake's shore).
func _ring_trees(c: Vector2, r: float, count: int) -> void:
	var leafy := _models(PropKit.NATURE, ["tree_default", "tree_oak", "tree_fat", "tree_simple"], TREE_TINT)
	for k in count:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * (r + rng.randf_range(0.0, 40.0))
		if is_free(p, 10.0):
			put(leafy[rng.randi() % leafy.size()], p, rng.randf() * TAU, rng.randf_range(9.0, 13.0), vis(1100.0), 0.3)


func _forest(c: Vector2, size: float) -> void:
	var pines := _models(PropKit.NATURE, ["tree_pineTallA", "tree_pineTallB", "tree_pineRoundD", "tree_pineTallD"], TREE_TINT)
	var count := int(size * size / 900.0 * (0.6 + detail * 0.4))
	for k in mini(count, 700):
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * size * 0.5
		if is_free(p, 9.0):
			put(pines[rng.randi() % pines.size()], p, rng.randf() * TAU, rng.randf_range(9.0, 15.0), vis(1200.0), 0.3)


## Buildings on a grid across an area, facing the track.
func _block_of(c: Vector2, size: float, face: float, models: Array, sc: float, spacing: float) -> void:
	var dir := Vector2(sin(face), cos(face))
	var acr := Vector2(dir.y, -dir.x)
	var n := int(size / spacing)
	for a in n:
		for b in n:
			var p := c + acr * (a - n * 0.5) * spacing + dir * (b - n * 0.5) * spacing
			p += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			if rng.randf() < 0.15 or not is_free(p, 10.0):
				continue
			put(models[rng.randi() % models.size()], p, face + (PI * 0.5 * (rng.randi() % 4) if b > 0 else 0.0), sc, 0.0, 0.5)
			_claim(p, spacing * 0.4)


## Buildings in a row facing the track.
func _row(c: Vector2, size: float, face: float, nrm: Vector2, models: Array, sc: float) -> void:
	var acr := Vector2(nrm.y, -nrm.x)
	var k := 0
	var d := -size * 0.5
	while d <= size * 0.5:
		var p := c + acr * d
		if is_free(p, 20.0):
			put(models[k % models.size()], p, face, sc, 0.0, 0.3)
			_claim(p, 24.0)
		d += 55.0
		k += 1


func _rocks(c: Vector2, size: float, count: int, sc: Vector2, tint: Color) -> void:
	var models := _models(PropKit.NATURE, ["rock_tallA", "rock_tallB", "rock_largeD", "rock_tallH", "cliff_block_rock"], tint)
	for k in count:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * size * 0.5
		if is_free(p, 6.0):
			put(models[rng.randi() % models.size()], p, rng.randf() * TAU, rng.randf_range(sc.x, sc.y), 0.0, 2.0)


func _jetties(c: Vector2, size: float, level: float, nrm: Vector2) -> void:
	var b := MeshBuf.new()
	var wood := WorldLook.wet(Color("b98a5a"), 0.0)
	var acr := Vector2(nrm.y, -nrm.x)
	var shore := c - nrm * size * 0.42
	for k in 5:
		var root_p := shore + acr * (k - 2) * 34.0
		var tip := root_p + nrm * 70.0
		var a := Vector3(root_p.x, level + 0.8, root_p.y)
		var e := Vector3(tip.x, level + 0.8, tip.y)
		b.box(a, e, Vector3(acr.x, 0, acr.y), 4.0, 0.5, wood, wood, true)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit(null, WorldLook.props())
	root.add_child(mi)
	var houses := _models(PropKit.WATERCRAFT, ["boat-house-a", "boat-house-c"])
	for k in 3:
		var p := shore - nrm * 30.0 + acr * (k - 1) * 60.0
		if is_free(p, 6.0):
			put(houses[k % 2], p, atan2(nrm.x, nrm.y), 5.0, 0.0, 0.3)


func _farm(c: Vector2, size: float, face: float) -> void:
	var barns := _models(PropKit.INDUSTRY, ["building-h", "building-i", "building-k"])
	var houses := _models(PropKit.SUBURB, ["building-type-b", "building-type-d"])
	put(barns[0], c, face, 12.0, 0.0, 0.3)
	_claim(c, 18.0)
	var h := c + Vector2(sin(face + 1.2), cos(face + 1.2)) * 40.0
	if is_free(h, 8.0):
		put(houses[0], h, face, 8.0, 0.0, 0.3)
		_claim(h, 10.0)
	var mill := PropKit.mesh(PropKit.TOWN + "windmill.glb")
	var mp := c + Vector2(sin(face - 1.4), cos(face - 1.4)) * 45.0
	if is_free(mp, 8.0):
		put(mill, mp, face, 8.0, 0.0, 0.3)
		_claim(mp, 10.0)
	# Fields of crops in rows, with a fence round them.
	var crops := _models(PropKit.NATURE, ["crops_cornStageD", "crops_wheatStageB", "crops_cornStageC"])
	var fence := PropKit.mesh(PropKit.NATURE + "fence_simple.glb")
	var dir := Vector2(sin(face), cos(face))
	var acr := Vector2(dir.y, -dir.x)
	var field := c + acr * size * 0.45
	var crop: Mesh = crops[rng.randi() % crops.size()]
	var n := int(size * 0.5 / 5.0)
	for a in n:
		for b in n:
			var p := field + acr * (a - n * 0.5) * 5.0 + dir * (b - n * 0.5) * 5.0
			if is_free(p, 10.0):
				put(crop, p, 0.0, 4.5, vis(500.0), 0.0, false)
	var edge := n * 5.0 * 0.5
	for k in int(edge * 2.0 / 4.0):
		for sgn: float in [-1.0, 1.0]:
			var p: Vector2 = field + acr * (k * 4.0 - edge) + dir * edge * sgn
			if is_free(p, 10.0):
				put(fence, p, face + PI * 0.5, 4.0, vis(400.0), 0.0, false)


func _lighthouse(c: Vector2) -> void:
	var b := MeshBuf.new()
	var y0 := ground(c) - 1.0
	var h := 34.0
	var seg := 12
	for k in 8:
		var col := WorldLook.wet(WorldLook.KERB_RED if k % 2 == 0 else Color.WHITE, 0.0)
		var ya := y0 + h * k / 8.0
		var yb := y0 + h * (k + 1) / 8.0
		var ra := lerpf(5.0, 3.2, float(k) / 8.0)
		var rb := lerpf(5.0, 3.2, float(k + 1) / 8.0)
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var p0 := Vector3(c.x + cos(a0) * ra, ya, c.y + sin(a0) * ra)
			var p1 := Vector3(c.x + cos(a1) * ra, ya, c.y + sin(a1) * ra)
			var q0 := Vector3(c.x + cos(a0) * rb, yb, c.y + sin(a0) * rb)
			var q1 := Vector3(c.x + cos(a1) * rb, yb, c.y + sin(a1) * rb)
			b.quad(p0, p1, q1, q0, col, Vector3(cos(a0 + PI / seg), 0, sin(a0 + PI / seg)))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit(null, WorldLook.props())
	root.add_child(mi)
	var lamp := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.6
	cyl.bottom_radius = 2.6
	cyl.height = 3.5
	lamp.mesh = cyl
	lamp.material_override = TrackView.lamp_material()
	lamp.position = Vector3(c.x, y0 + h + 1.75, c.y)
	root.add_child(lamp)
	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 3.4
	cone.height = 2.5
	cap.mesh = cone
	cap.material_override = WorldLook.flat(Color("2e3440"))
	cap.position = lamp.position + Vector3.UP * 3.0
	root.add_child(cap)
	_claim(c, 8.0)


func _big_screen(c: Vector2, face: float, w: float) -> void:
	var b := MeshBuf.new()
	var scr := MeshBuf.new()
	var y0 := ground(c) - 0.5
	var dir := Vector2(sin(face), cos(face))
	var acr := Vector3(dir.y, 0, -dir.x)
	var fwd := Vector3(dir.x, 0, dir.y)
	var base := Vector3(c.x, y0, c.y)
	var h := w * 0.56
	var grey := WorldLook.wet(Color("3b3f4c"), 0.0)
	for sgn: float in [-1.0, 1.0]:
		var leg := base + acr * sgn * w * 0.35
		b.box(leg - fwd * 0.5, leg + fwd * 0.5, acr, 1.2, 9.0, grey, grey, true)
	var lo := base + Vector3.UP * 9.0
	b.box(lo - acr * w * 0.5, lo + acr * w * 0.5, fwd, 1.6, h, grey, grey, true)
	var f := fwd * 0.85
	scr.quad(lo - acr * w * 0.46 + Vector3.UP * h * 0.06 + f, lo + acr * w * 0.46 + Vector3.UP * h * 0.06 + f, lo + acr * w * 0.46 + Vector3.UP * h * 0.94 + f, lo - acr * w * 0.46 + Vector3.UP * h * 0.94 + f, Color.WHITE, fwd)
	var m := b.commit(null, WorldLook.props())
	scr.commit(m, WorldLook.glow(Color("3d7bd6"), 1.2))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	root.add_child(mi)
	_claim(c, w * 0.5)


## Wind turbines across an area.
func _windmills(c: Vector2, size: float) -> void:
	var turbine := _turbine_mesh()
	for k in 4 + detail * 2:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * size * 0.5
		if is_free(p, 30.0):
			put(turbine, p, rng.randf_range(-0.3, 0.3) + 0.8, 1.0, 0.0, 0.5)
			_claim(p, 6.0)


func _turbine_mesh() -> ArrayMesh:
	var b := MeshBuf.new()
	var white := WorldLook.wet(Color("f2f3f7"), 0.0)
	var h := 60.0
	var seg := 8
	for j in seg:
		var a0 := TAU * j / seg
		var a1 := TAU * (j + 1) / seg
		b.quad(Vector3(cos(a0) * 2.0, 0, sin(a0) * 2.0), Vector3(cos(a1) * 2.0, 0, sin(a1) * 2.0), Vector3(cos(a1) * 1.1, h, sin(a1) * 1.1), Vector3(cos(a0) * 1.1, h, sin(a0) * 1.1), white, Vector3(cos(a0 + PI / seg), 0, sin(a0 + PI / seg)))
	b.box(Vector3(0, h, -2.5), Vector3(0, h, 4.0), Vector3.RIGHT, 2.6, 2.6, white, white, true)
	var hub := Vector3(0, h + 1.3, 4.2)
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		var tip := hub + dir * 26.0
		b.quad(hub + side * 1.2, tip + side * 0.3, tip - side * 0.3, hub - side * 1.0, white, Vector3.BACK)
		b.quad(hub + side * 1.2, hub - side * 1.0, tip - side * 0.3, tip + side * 0.3, white, Vector3.FORWARD)
	return b.commit(null, WorldLook.props())
