class_name Trackside
extends RefCounted
## Everything that stands beside the track: barriers (tyre walls, armco,
## catch fences; concrete walls are part of the ground), the pit building
## and garages, the paddock, the start gantry and its lights, grandstands,
## camera towers, marshal flags, billboards and banner towers, and light
## posts (lit at night).
##
## Repeated pieces go into MultiMeshes split into cells, with visibility
## ranges, so a whole lap of barriers costs a few dozen draw calls.

## Racing Kit v2 at real scale (a 5.5 m car).
const V2_SCALE := 4.9
## Kenney's buildings face +z; this turns them if a kit faces the other way.
const FRONT := 0.0

var view: TrackView
var track: Track
var roads: RoadBuilder
var terrain: Terrain
var detail := 1
var scatter := PropKit.Scatter.new(500.0)
var root: Node3D
var rng := RandomNumberGenerator.new()
## TV camera positions (on the camera towers), light post lamp positions.
var cameras: Array = []
var lamps: Array = []
var start_lights: StartLights
## Footprints others must keep clear of: [Rect2] in world x/z.
var taken: Array = []


func _init(v: TrackView) -> void:
	view = v
	track = v.track
	roads = v.roads
	terrain = v.terrain
	detail = v.detail
	rng.seed = hash(track.id + "trackside")


func build() -> void:
	root = Node3D.new()
	root.name = "Trackside"
	view.add_child(root)
	_barriers()
	_gantry()
	_pits()
	_main_grandstands()
	_landmark_grandstands()
	_camera_towers()
	_billboards()
	_light_posts()
	_marshals()
	scatter.build(root)
	view.taken.append_array(taken)


# --- Helpers -------------------------------------------------------------

## Visibility range for small props by detail level.
func vis(near: float) -> float:
	return near * [0.6, 1.0, 1.5][detail]


## A transform at (s, lat) on the ground, turned `yaw` from the track's
## heading, scaled by `sc`. Off the track the terrain gives the height.
func at(s: float, lat: float, yaw := 0.0, sc := Vector3.ONE, on_terrain := true) -> Transform3D:
	var p := track.world(track.wrap_s(s), lat)
	if on_terrain and absf(lat) > track.value_at(track.half, s) + 1.0:
		var hb: float = absf(lat) - roads.bar[0 if lat > 0.0 else 1][track.index_at(s)]
		if hb > 1.0:
			p.y = minf(p.y, terrain.height(p.x, p.z)) if hb < 6.0 else terrain.height(p.x, p.z)
	var b := Basis(Vector3.UP, track.heading_at(track.wrap_s(s)) + yaw).scaled(sc)
	return Transform3D(b, p)


## The turn (from the track's heading) that points a model's front (+z)
## at the track from `side` (1 left, -1 right).
static func face(side: float) -> float:
	return -side * PI * 0.5 + FRONT


## The lowest ground under a footprint (so buildings never float).
func ground_under(c: Vector3, radius: float) -> float:
	var y := terrain.height(c.x, c.z)
	for k in 6:
		var a := TAU * k / 6.0
		y = minf(y, terrain.height(c.x + cos(a) * radius, c.z + sin(a) * radius))
	return y


func _take(xf: Transform3D, half_size: float) -> void:
	taken.append(Rect2(xf.origin.x - half_size, xf.origin.z - half_size, half_size * 2.0, half_size * 2.0))


# --- Barriers ------------------------------------------------------------

func _barriers() -> void:
	var guard := PropKit.mesh(PropKit.V2 + "guardrail-double.glb")
	var tyres := PropKit.mesh(PropKit.V2 + "barrels.glb")
	var fence := PropKit.mesh(PropKit.V2 + "fence-open-tall.glb")
	var n := track.n
	for side in 2:
		var sg := RoadBuilder.sgn(side)
		var kind := -1
		var anchor := Vector3.ZERO
		var anchor_s := 0.0
		for k in n + 1:
			var i := k % n
			var kk: int = track.barrier[side][i]
			if roads.deck[i]:
				kk = TrackPlan.Barrier.WALL
			var p := roads.point(i, sg * (float(roads.bar[side][i]) + 0.4))
			if kk != kind:
				kind = kk
				anchor = p
				anchor_s = i * track.step
				continue
			# Longer pieces where the barrier runs straight: fewer copies.
			var seg := 6.0 if absf(track.curv[i]) < 0.004 else 4.0
			var d := anchor.distance_to(p)
			if d < seg:
				continue
			var mid := (anchor + p) * 0.5
			var dir := (p - anchor) / d
			var yaw := atan2(dir.x, dir.z) - PI * 0.5
			match kind:
				TrackPlan.Barrier.ARMCO:
					_seg(guard, mid, yaw, d, Vector3(1.0 / 1.0, 3.0, 4.0), side, 0.0)
				TrackPlan.Barrier.TYRES:
					_seg(tyres, mid, yaw, d, Vector3(1.0, 3.6, 4.0), side, 0.0)
				TrackPlan.Barrier.FENCE:
					_seg(guard, mid, yaw, d, Vector3(1.0, 3.0, 4.0), side, 0.0)
					_seg(fence, mid, yaw, d, Vector3(1.0, 4.4, 4.0), side, 1.4)
			anchor = p
			anchor_s = i * track.step


## One barrier piece from the chord's middle, stretched to the chord.
func _seg(m: Mesh, mid: Vector3, yaw: float, length: float, sc: Vector3, side: int, back: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var out := b.z * (-1.0 if side == 0 else 1.0)
	# The model's x runs along the barrier; its own length is one unit.
	var basis := b.scaled_local(Vector3(length * sc.x, sc.y, sc.z))
	if side == 1:
		basis = basis * Basis(Vector3.UP, PI)
	# Barriers are low and thin: their shadows aren't worth drawing them
	# twice more.
	scatter.add(m, Transform3D(basis, mid + out * back), vis(900.0), false)


# --- Start gantry --------------------------------------------------------

func _gantry() -> void:
	var s := 3.0
	var h := track.value_at(track.half, s)
	var span := 2.0 * (h + 2.6)
	var g := PropKit.mesh(PropKit.V2 + "gantry.glb")
	var gs := g.get_aabb().size
	var xf := at(s, 0.0, PI, Vector3(span / gs.x, V2_SCALE, V2_SCALE), false)
	scatter.add(g, xf, 0.0, true)
	start_lights = StartLights.new()
	# The lights face the grid, which lies behind the line.
	var lx := at(s - 0.6, 0.0, PI, Vector3.ONE, false)
	lx.origin.y += gs.y * V2_SCALE - 3.2
	start_lights.transform = lx
	root.add_child(start_lights)
	# A start/finish arch with the flags further up the straight on longer
	# straights is busy; one checkered banner tower each side instead.
	var flag := PropKit.mesh(PropKit.V1 + "flagCheckers.glb")
	for sg: float in [1.0, -1.0]:
		scatter.add(flag, at(1.0, sg * (h + 3.2), 0.0, Vector3.ONE * 7.0, false), vis(600.0))


# --- Pits ----------------------------------------------------------------

func _pits() -> void:
	var pit := track.pit
	if pit.is_empty():
		return
	var sg := float(pit.side)
	var garage := PropKit.mesh(PropKit.V2 + "pitstop-garage-open.glb")
	var closed := PropKit.mesh(PropKit.V2 + "pitstop-garage-closed.glb")
	var upper := PropKit.mesh(PropKit.V2 + "pitstop-windows.glb")
	var roof := PropKit.mesh(PropKit.V2 + "pitstop-windows-roof.glb")
	var tank := PropKit.mesh(PropKit.V1 + "pitsGarage.glb")
	var gsz := garage.get_aabb().size
	var width := 15.0
	var sc := width / gsz.x
	var depth := gsz.z * sc
	var back := roads.pit_outer + depth * 0.5 + 0.4
	var boxes: Array = pit.boxes
	var first := float(boxes[0]) - width * 3.0
	var last := float(boxes[boxes.size() - 1]) + width * 3.0
	var s := first
	var k := -3
	while s <= last + 0.1:
		var is_box := k >= 0 and k < boxes.size()
		var m := garage if is_box else closed
		var xf := at(s, sg * back, face(sg), Vector3.ONE * sc, false)
		xf.origin.y = track.world(track.wrap_s(s), sg * float(pit.outer_lat)).y
		if is_box and k == boxes.size() - 1:
			# The last box is Tankco's: the old Racing Kit garage with its banner.
			var tsz := tank.get_aabb().size
			var txf := at(s, sg * back, face(sg), Vector3(width / tsz.x, width / tsz.x * 1.1, depth / tsz.z), false)
			txf.origin.y = xf.origin.y
			scatter.add(tank, txf, 0.0, true)
		else:
			scatter.add(m, xf, 0.0, true)
		var up := xf
		up.origin.y += gsz.y * sc
		scatter.add(roof if k % 4 == 0 else upper, up, 0.0, true)
		_take(xf, width * 0.6)
		s += width
		k += 1
	# The paddock behind: team trucks and tents.
	var trucks := [PropKit.mesh(PropKit.V2 + "truck-a.glb"), PropKit.mesh(PropKit.V2 + "truck-b.glb")]
	var tent := PropKit.mesh(PropKit.V2 + "tent-roof-large.glb")
	var pl := back + depth * 0.5 + 14.0
	for b in boxes.size():
		var bs := float(boxes[b])
		var txf := at(bs, sg * pl, 0.0, Vector3.ONE * V2_SCALE)
		scatter.add(trucks[b % 2], txf, vis(500.0))
		if b % 3 == 1:
			scatter.add(tent, at(bs + 7.0, sg * (pl + 16.0), 0.0, Vector3.ONE * 4.0), vis(500.0))
		_take(txf, 10.0)
	# A control tower at the end of the pit building.
	var tower := PropKit.mesh(PropKit.V1 + "pitsOfficeRoof.glb")
	var tsz2 := tower.get_aabb().size
	var t_sc := 22.0 / tsz2.x
	var to := at(last + 24.0, sg * (back + 4.0), face(sg), Vector3(t_sc, t_sc * 1.6, t_sc), false)
	to.origin.y = track.world(track.wrap_s(last), sg * float(pit.outer_lat)).y
	scatter.add(tower, to, 0.0, true)
	_take(to, 16.0)


# --- Grandstands ---------------------------------------------------------

## A row of grandstands from s0 to s1 facing the track, `gap` metres behind
## the barrier on `side` (1 left, -1 right).
func grandstand_row(s0: float, s1: float, side: float, dist := 0.0, covered := true) -> void:
	var m := PropKit.mesh(PropKit.V1 + ("grandStandCovered.glb" if covered else "grandStand.glb"))
	var sz := m.get_aabb().size
	var width := 16.0
	var sc := width / sz.x
	var depth := sz.z * sc
	var s := s0
	while s <= s1:
		var si := track.index_at(track.wrap_s(s))
		var b: float = roads.bar[0 if side > 0.0 else 1][si]
		var lat := side * maxf(dist, b + depth * 0.5 + 6.0)
		var xf := at(s, lat, face(side), Vector3.ONE * sc)
		xf.origin.y = ground_under(xf.origin, depth * 0.5) - 0.3
		# Stands on bends follow the outside of the bend.
		scatter.add(m, xf, 0.0, true)
		_take(xf, depth * 0.6)
		s += width


func _main_grandstands() -> void:
	var side := -float(track.pit.get("side", -1))
	grandstand_row(-260.0, 160.0, side)


func _landmark_grandstands() -> void:
	for l in track.landmarks:
		if str(l.kind) != "grandstand":
			continue
		var size := float(l.size)
		grandstand_row(float(l.s) - size * 0.5, float(l.s) + size * 0.5, float(l.side), float(l.distance), int(float(l.s)) % 2 == 0)


# --- Camera towers -------------------------------------------------------

func _camera_towers() -> void:
	var cam := PropKit.mesh(PropKit.V2 + "camera.glb")
	var tower := _tower_mesh()
	var spots := []
	for c in track.corners:
		spots.append([float(c.apex), -float(c.dir)])
	spots.append([-120.0, -float(track.pit.get("side", -1))])
	for sp in spots:
		var s: float = sp[0]
		var side: float = sp[1]
		var si := track.index_at(track.wrap_s(s))
		var b: float = roads.bar[0 if side > 0.0 else 1][si]
		var xf := at(s, side * (b + 9.0), 0.0, Vector3.ONE)
		if _blocked(xf.origin):
			xf = at(s + 30.0, side * (b + 14.0), 0.0, Vector3.ONE)
		var p := xf.origin
		scatter.add(tower, Transform3D(Basis(), p), vis(900.0))
		var to_track := track.world(track.wrap_s(s), 0.0) - p
		var yaw := atan2(to_track.x, to_track.z)
		scatter.add(cam, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 4.0), p + Vector3.UP * 8.0), vis(700.0))
		cameras.append(p + Vector3.UP * 10.2)


func _blocked(p: Vector3) -> bool:
	for r in taken:
		if (r as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


## A scaffold tower 8 m tall with a platform, built once.
func _tower_mesh() -> ArrayMesh:
	var b := MeshBuf.new()
	var col := Color("b8bccb")
	var top := Color("e9605d")
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var base := Vector3(cx * 1.1, 0, cz * 1.1)
			b.box(base - Vector3(0.12, 0, 0), base + Vector3(0.12, 0, 0), Vector3(0, 0, 1), 0.24, 8.0, col, col, true)
	b.box(Vector3(-1.5, 8.0, 0), Vector3(1.5, 8.0, 0), Vector3(0, 0, 1), 3.0, 0.3, col, top, true)
	for k in 3:
		var y := 2.0 + k * 2.2
		b.box(Vector3(-1.1, y, -1.1), Vector3(1.1, y, 1.1), Vector3(1, 0, -1), 0.12, 0.12, col, col)
		b.box(Vector3(-1.1, y, 1.1), Vector3(1.1, y, -1.1), Vector3(1, 0, 1), 0.12, 0.12, col, col)
	for i in b.c.size():
		b.c[i] = WorldLook.wet(b.c[i], 0.0)
	return b.commit(null, WorldLook.props())


# --- Billboards, banners, flags ------------------------------------------

func _billboards() -> void:
	var boards := [PropKit.mesh(PropKit.V1 + "billboard.glb"), PropKit.mesh(PropKit.V1 + "billboardLow.glb")]
	var towers := [PropKit.mesh(PropKit.V1 + "bannerTowerRed.glb"), PropKit.mesh(PropKit.V1 + "bannerTowerGreen.glb")]
	var banners := [PropKit.mesh(PropKit.V2 + "banners-green.glb"), PropKit.mesh(PropKit.V2 + "banners-yellow.glb")]
	var every: float = [420.0, 280.0, 200.0][detail]
	var s := 120.0
	var k := 0
	while s < track.length - 80.0:
		var side := 1.0 if k % 2 == 0 else -1.0
		var si := track.index_at(s)
		var b: float = roads.bar[0 if side > 0.0 else 1][si]
		var xf := at(s, side * (b + 5.0), face(side), Vector3.ONE * 9.0)
		if not _blocked(xf.origin) and track.feature_at(s) == "":
			scatter.add(boards[k % 2], xf, vis(800.0))
		s += every
		k += 1
	# Banner towers and flags at the turn-in of each corner, on the outside.
	for c in track.corners:
		var side := -float(c.dir)
		var s0 := track.wrap_s(float(c.start) - 30.0)
		var b0: float = roads.bar[0 if side > 0.0 else 1][track.index_at(s0)]
		var xf := at(s0, side * (b0 + 4.0), face(side), Vector3.ONE * 9.0)
		if not _blocked(xf.origin):
			scatter.add(towers[int(c.number) % 2], xf, vis(700.0))
		var s1 := track.wrap_s(float(c.end) + 25.0)
		var b1: float = roads.bar[0 if side > 0.0 else 1][track.index_at(s1)]
		var xf2 := at(s1, side * (b1 + 3.0), 0.0, Vector3.ONE * V2_SCALE)
		if not _blocked(xf2.origin):
			scatter.add(banners[int(c.number) % 2], xf2, vis(600.0))


func _marshals() -> void:
	var flags := [PropKit.mesh(PropKit.V2 + "flag-green.glb"), PropKit.mesh(PropKit.V2 + "flag-yellow.glb")]
	var hut := PropKit.mesh(PropKit.V2 + "tent-closed-square.glb")
	var every: float = [600.0, 400.0, 300.0][detail]
	var s := 200.0
	var k := 0
	while s < track.length - 100.0:
		var side := -1.0 if k % 2 == 0 else 1.0
		var si := track.index_at(s)
		var b: float = roads.bar[0 if side > 0.0 else 1][si]
		var xf := at(s, side * (b + 4.0), 0.0, Vector3.ONE * 3.0)
		if not _blocked(xf.origin) and track.feature_at(s) == "":
			scatter.add(hut, xf, vis(400.0))
			var fx := at(s + 3.0, side * (b + 2.0), PI * 0.5, Vector3.ONE * 3.0)
			scatter.add(flags[k % 2], fx, vis(400.0))
		s += every
		k += 1


# --- Light posts ---------------------------------------------------------

## Floodlight towers all round night circuits; by day only along the pits.
func _light_posts() -> void:
	var post := PropKit.mesh(PropKit.V2 + "lights-high.glb")
	var psz := post.get_aabb().size
	var head := BoxMesh.new()
	head.size = Vector3(2.6, 0.9, 0.5)
	head.material = TrackView.lamp_material()
	var night := view.is_night() or str(view.info.get("time", "")) == "dusk"
	var sc := 13.0 / psz.y
	var s := 0.0
	var k := 0
	var every := 70.0
	while s < track.length:
		var near_start := absf(track.delta_s(0.0, s)) < 260.0
		if night or near_start:
			var side := 1.0 if k % 2 == 0 else -1.0
			var si := track.index_at(s)
			var b: float = roads.bar[0 if side > 0.0 else 1][si]
			var xf := at(s, side * (b + 2.5), face(side), Vector3.ONE * sc)
			var f := track.feature_at(s)
			if not _blocked(xf.origin) and f != "tunnel" and f != "over" and f != "bridge":
				scatter.add(post, xf, vis(900.0))
				var top := xf.origin + Vector3.UP * (psz.y * sc - 0.6)
				var to_track := (track.world(s, 0.0) - xf.origin)
				to_track.y = 0.0
				var yaw := atan2(to_track.x, to_track.z)
				var hb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.5)
				scatter.add(head, Transform3D(hb, top + to_track.normalized() * 0.5), vis(1600.0), false)
				lamps.append(top + to_track.normalized() * 3.0)
		s += every
		k += 1
