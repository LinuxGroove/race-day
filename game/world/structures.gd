class_name Structures
extends RefCounted
## The track's own buildings: tunnels (walls, roof, portals and lights),
## pillars under raised road (bridges and crossovers), and the hotel that
## spans the track.
##
## Tunnel roofs cast no shadow and the tunnel has bright light strips, so a
## tunnel reads as a lit space rather than a dark hole. Pillars never stand
## on another road, so a crossover's lower road stays open.

const TUNNEL_H := 7.5
const PILLAR_EVERY := 26.0

var view: TrackView
var track: Track
var roads: RoadBuilder
var terrain: Terrain
var root: Node3D


func _init(v: TrackView) -> void:
	view = v
	track = v.track
	roads = v.roads
	terrain = v.terrain


func build() -> void:
	root = Node3D.new()
	root.name = "Structures"
	view.add_child(root)
	for f in track.features:
		match str(f.kind):
			"tunnel":
				_tunnel(f)
			"over", "bridge":
				_pillars(f)
	for l in track.landmarks:
		if str(l.kind) == "hotel":
			_hotel(l)


func _add(m: ArrayMesh, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## The samples a feature covers, in order.
func _samples(f: Dictionary) -> Array:
	var out := []
	var len := fposmod(float(f.to) - float(f.from), track.length)
	var k := 0.0
	while k <= len + 0.01:
		out.append(track.index_at(track.wrap_s(float(f.from) + k)))
		k += track.step
	return out


# --- Tunnels -------------------------------------------------------------

func _tunnel(f: Dictionary) -> void:
	var walls := MeshBuf.new()
	var roof := MeshBuf.new()
	var lights := MeshBuf.new()
	var idx := _samples(f)
	var wall_col := WorldLook.wet(Color("e4e1d8"), 0.0)
	var stripe_col := WorldLook.wet(WorldLook.KERB_RED, 0.0)
	var top_col := WorldLook.wet(Color("b9b4a6"), 0.0)
	var city := view.theme() in ["city", "harbour"]
	for k in idx.size() - 1:
		var i: int = idx[k]
		var j: int = idx[k + 1]
		for side in 2:
			var sg := RoadBuilder.sgn(side)
			var li: float = roads.bar[side][i] + 0.5
			var lj: float = roads.bar[side][j] + 0.5
			var a := roads.point(i, sg * li)
			var b := roads.point(j, sg * lj)
			var inward := Vector3(track.normal[i].x, 0, track.normal[i].y) * -sg
			# Inner face, with a red band low down for the drivers' eyes.
			walls.quad(a, b, b + Vector3.UP * 1.0, a + Vector3.UP * 1.0, stripe_col, inward)
			walls.quad(a + Vector3.UP * 1.0, b + Vector3.UP * 1.0, b + Vector3.UP * TUNNEL_H, a + Vector3.UP * TUNNEL_H, wall_col, inward)
			# Outer face.
			var ao := a - inward * 1.2
			var bo := b - inward * 1.2
			ao.y = minf(ao.y, terrain.height(ao.x, ao.z)) - 0.5
			bo.y = minf(bo.y, terrain.height(bo.x, bo.z)) - 0.5
			walls.quad(ao, bo, b - inward * 1.2 + Vector3.UP * (TUNNEL_H + 1.6), a - inward * 1.2 + Vector3.UP * (TUNNEL_H + 1.6), top_col, -inward)
		# Roof: underside (lit by its strips) and top.
		var l0 := roads.point(i, float(roads.bar[0][i]) + 1.7)
		var r0 := roads.point(i, -float(roads.bar[1][i]) - 1.7)
		var l1 := roads.point(j, float(roads.bar[0][j]) + 1.7)
		var r1 := roads.point(j, -float(roads.bar[1][j]) - 1.7)
		var y0 := maxf(l0.y, r0.y) + TUNNEL_H
		var y1 := maxf(l1.y, r1.y) + TUNNEL_H
		var ceil := WorldLook.wet(Color("cfcabd"), 0.0)
		roof.quad(Vector3(l0.x, y0, l0.z), Vector3(l1.x, y1, l1.z), Vector3(r1.x, y1, r1.z), Vector3(r0.x, y0, r0.z), ceil, Vector3.DOWN)
		roof.quad(Vector3(l0.x, y0 + 1.6, l0.z), Vector3(l1.x, y1 + 1.6, l1.z), Vector3(r1.x, y1 + 1.6, r1.z), Vector3(r0.x, y0 + 1.6, r0.z), top_col if city else WorldLook.wet(_grass(), 0.0), Vector3.UP)
		# Two strips of lights along the ceiling, in short runs.
		if k % 3 != 2:
			for lat: float in [-track.half[i] * 0.45, track.half[i] * 0.45]:
				var p0 := roads.point(i, lat)
				var p1 := roads.point(j, lat)
				p0.y = y0 - 0.08
				p1.y = y1 - 0.08
				var acr := Vector3(track.normal[i].x, 0, track.normal[i].y) * 0.35
				lights.quad(p0 - acr, p1 - acr, p1 + acr, p0 + acr, Color.WHITE, Vector3.DOWN)
	# Portals: a thick header over each mouth.
	for end: int in [0, idx.size() - 1]:
		var i: int = idx[end]
		var l := roads.point(i, float(roads.bar[0][i]) + 1.7)
		var r := roads.point(i, -float(roads.bar[1][i]) - 1.7)
		var y := maxf(l.y, r.y) + TUNNEL_H - 1.4
		var t := Vector3(track.tangent[i].x, 0, track.tangent[i].y)
		var lo := Vector3(l.x, y, l.z)
		var ro := Vector3(r.x, y, r.z)
		walls.box(lo, ro, t, 1.4, 3.0 + 0.1, WorldLook.wet(WorldLook.KERB_WHITE, 0.0), stripe_col, true)
	var wm := walls.commit(null, WorldLook.props())
	_add(wm, true)
	var rm := roof.commit(null, WorldLook.props())
	_add(rm, false)
	if not lights.is_empty():
		_add(lights.commit(null, WorldLook.glow(Color("fff6e0"), 3.0)), false)
	# A street's tunnel runs under buildings.
	if view.theme() in ["city", "harbour"]:
		_buildings_over(idx)


func _grass() -> Color:
	var cols: Array = WorldLook.TERRAIN.get(view.theme(), WorldLook.TERRAIN["parkland"])
	return cols[0]


func _buildings_over(idx: Array) -> void:
	var models := ["building-a", "building-c", "building-e", "building-j", "building-k"]
	var sc := PropKit.Scatter.new(400.0)
	var k := 4
	while k < idx.size() - 4:
		var i: int = idx[k]
		var m := PropKit.mesh(PropKit.CITY + models[k % models.size()] + ".glb")
		var sz := m.get_aabb().size
		var width := float(roads.bar[0][i]) + float(roads.bar[1][i]) + 4.0
		var s := width / maxf(sz.x, sz.z)
		var p := roads.point(i, (float(roads.bar[0][i]) - float(roads.bar[1][i])) * 0.5)
		p.y += TUNNEL_H + 1.6
		var b := Basis(Vector3.UP, atan2(track.tangent[i].x, track.tangent[i].y)).scaled(Vector3(s, s * 0.8, s))
		sc.add(m, Transform3D(b, p), 0.0, true)
		k += maxi(1, int(sz.z * s / track.step) + 1)
	sc.build(root)


# --- Pillars -------------------------------------------------------------

func _pillars(f: Dictionary) -> void:
	var b := MeshBuf.new()
	var col := WorldLook.wet(WorldLook.CONCRETE, 0.0)
	var idx := _samples(f)
	var every := maxi(1, int(PILLAR_EVERY / track.step))
	for k in range(every / 2, idx.size(), every):
		var i: int = idx[k]
		var deck_y := track.pos[i].y - RoadBuilder.DECK_DEPTH
		for side in 2:
			var sg := RoadBuilder.sgn(side)
			var lat: float = sg * (float(roads.bar[side][i]) - 0.6)
			var p := roads.point(i, lat)
			# Never on another road (the road a crossover passes over).
			if terrain.clearance(p.x, p.z) < 2.0:
				continue
			var ground := terrain.height(p.x, p.z) - 1.0
			for w in terrain.waters:
				if terrain.water_depth_mask(w, Vector2(p.x, p.z)) > 0.0:
					ground = minf(ground, float(w.level) - 3.0)
			if deck_y - ground < 1.0:
				continue
			var t := Vector3(track.tangent[i].x, 0, track.tangent[i].y)
			var base := Vector3(p.x, ground, p.z)
			b.box(base - t * 0.9, base + t * 0.9, Vector3(t.z, 0, -t.x), 1.8, deck_y - ground, col, col, true)
	if not b.is_empty():
		_add(b.commit(null, WorldLook.props()), true)


# --- The hotel over the track --------------------------------------------

func _hotel(l: Dictionary) -> void:
	var s := float(l.s)
	var i := track.index_at(s)
	var size := maxf(40.0, float(l.get("size", 60.0)))
	var b := MeshBuf.new()
	var win := MeshBuf.new()
	var t := Vector3(track.tangent[i].x, 0, track.tangent[i].y)
	var nrm := Vector3(track.normal[i].x, 0, track.normal[i].y)
	var white := WorldLook.wet(Color("f1f2f6"), 0.0)
	var frame := WorldLook.wet(Color("a7afc4"), 0.0)
	var tower_w := 26.0
	var tower_h := 52.0
	var span_lo := 13.0
	var span_hi := 25.0
	var lats := []
	for side in 2:
		var sg := RoadBuilder.sgn(side)
		var lat := sg * (float(roads.bar[side][i]) + 4.0 + tower_w * 0.5)
		lats.append(lat)
		var c := track.world(s, lat)
		c.y = minf(c.y, terrain.height(c.x, c.z)) - 0.5
		var top := c.y + tower_h
		_block(b, win, c, t, nrm, size, tower_w, tower_h, white, frame)
	# The bridge between the towers, high over the track.
	var c0 := track.world(s, lats[1])
	var c1 := track.world(s, lats[0])
	var y0 := track.pos[i].y + span_lo
	var mid := (c0 + c1) * 0.5
	mid.y = y0
	var span := c0.distance_to(c1) - tower_w * 0.4
	_block(b, win, mid, nrm, t, span, size * 0.7, span_hi - span_lo, white, frame)
	var m := b.commit(null, WorldLook.props())
	win.commit(m, TrackView.window_material())
	_add(m, true)


## A box building from its base centre: `along` is its length direction,
## `across` its depth, with bands of windows on the long faces.
func _block(b: MeshBuf, win: MeshBuf, base: Vector3, along: Vector3, across: Vector3, length: float, depth: float, height: float, col: Color, frame: Color) -> void:
	var a := along.normalized() * length * 0.5
	var d := across.normalized() * depth * 0.5
	var up := Vector3.UP * height
	var c := [base - a - d, base + a - d, base + a + d, base - a + d]
	for k in 4:
		var p0: Vector3 = c[k]
		var p1: Vector3 = c[(k + 1) % 4]
		var out := ((p0 + p1) * 0.5 - base)
		out.y = 0.0
		b.quad(p0, p1, p1 + up, p0 + up, col, out)
		# Window bands every 3.5 m.
		var y := 3.0
		while y < height - 2.0:
			var o := out.normalized() * 0.06
			var inset0 := p0.lerp(p1, 0.06) + o
			var inset1 := p0.lerp(p1, 0.94) + o
			win.quad(inset0 + Vector3.UP * y, inset1 + Vector3.UP * y, inset1 + Vector3.UP * (y + 1.6), inset0 + Vector3.UP * (y + 1.6), Color.WHITE, out)
			y += 3.5
	b.quad(c[0] + up, c[1] + up, c[2] + up, c[3] + up, frame, Vector3.UP)
	b.quad(c[0], c[1], c[2], c[3], frame, Vector3.DOWN)
