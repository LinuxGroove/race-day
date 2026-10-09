class_name RoadBuilder
extends RefCounted
## Builds the ground along a track in chunks of about 200 m: the road with
## its white edge lines, red and white kerbs, run-off in the surface the
## simulation uses (grass, gravel, tarmac, sand), the pit lane with its
## markings, painted lines (start, grid boxes, DRS, pit speed limit),
## concrete walls and the decks of bridges. Everything is one vertex-coloured
## surface per chunk with the shared ground material.
##
## `bar` holds where the barriers stand on each side, pulled in on the
## inside of tight corners so the ground never folds over itself; trackside
## props and the terrain use it too.

const CHUNK := 100
const LINE_W := 0.45
## A strip of grass beyond the barrier that slopes into the terrain.
const VERGE := 5.0
const PAINT_LIFT := 0.035
const KERB_LIFT := 0.03
const WALL_H := 1.1
const WALL_W := 0.6
const DECK_DEPTH := 1.4

var track: Track
## The Racing Kit's tiles lay the road, kerbs and run-off (the Proving Ground).
var tiles := false
## Distance from the centreline to the barrier per side (0 left, 1 right).
var bar := [PackedFloat32Array(), PackedFloat32Array()]
## Per sample: the road is on a bridge deck (an "over" or "bridge" feature).
var deck := PackedByteArray()
var in_tunnel := PackedByteArray()
var chunk_count := 0

var _bufs: Array = []
var _terrain: Terrain


func _init(t: Track, use_tiles := false) -> void:
	track = t
	tiles = use_tiles
	_edges()


## The ground position at sample i, lat metres to the left.
func point(i: int, lat: float, lift := 0.0) -> Vector3:
	var p := track.pos[i]
	var nn := track.normal[i]
	var y := p.y + clampf(lat, -track.half[i], track.half[i]) * track.bank[i]
	return Vector3(p.x + nn.x * lat, y + lift, p.z + nn.y * lat)


## Side sign: side 0 is the left (+lat), side 1 the right.
static func sgn(side: int) -> float:
	return 1.0 if side == 0 else -1.0


func _edges() -> void:
	var n := track.n
	deck.resize(n)
	in_tunnel.resize(n)
	for side in 2:
		bar[side].resize(n)
	for i in n:
		var s := i * track.step
		var f := track.feature_at(s)
		deck[i] = 1 if f == "over" or f == "bridge" else 0
		in_tunnel[i] = 1 if f == "tunnel" else 0
		for side in 2:
			bar[side][i] = track.barrier_off(s, side)
	# Keep the inside of tight corners from folding: no further in than
	# most of the radius.
	for i in n:
		var kl := 0.0
		var kr := 0.0
		for k in range(-8, 9):
			var c := track.curv[posmod(i + k, n)]
			kl = maxf(kl, c)
			kr = maxf(kr, -c)
		var h := track.half[i]
		if kl > 0.0001:
			bar[0][i] = clampf(bar[0][i], h + 0.6, maxf(h + 0.6, 0.85 / kl))
		if kr > 0.0001:
			bar[1][i] = clampf(bar[1][i], h + 0.6, maxf(h + 0.6, 0.85 / kr))


## The outer edge of the kerb (or the road) on a side.
func kerb_out(i: int, side: int) -> float:
	var h := track.half[i]
	if track.kerb[side][i] != 0:
		return minf(h + Track.KERB_WIDTH, bar[side][i])
	return h


## Builds every chunk's mesh. The terrain gives the verge its outer height.
func build(terrain: Terrain) -> Array:
	_terrain = terrain
	var n := track.n
	chunk_count = ceili(float(n) / CHUNK)
	_bufs.clear()
	for c in chunk_count:
		_bufs.append(MeshBuf.new())
	for i in n:
		_segment(i)
	_paint_all()
	_walls()
	var out := []
	for b in _bufs:
		out.append((b as MeshBuf).commit(null, WorldLook.ground()) if not (b as MeshBuf).is_empty() else null)
	return out


func _buf_at(s: float) -> MeshBuf:
	var i := track.index_at(s)
	return _bufs[mini(i / CHUNK, chunk_count - 1)]


func _segment(i: int) -> void:
	var j := (i + 1) % track.n
	var b: MeshBuf = _bufs[i / CHUNK]
	var s := i * track.step
	if not tiles:
		var ri := track.half[i] - LINE_W
		var rj := track.half[j] - LINE_W
		b.quad(point(i, -ri), point(j, -rj), point(j, rj), point(i, ri), WorldLook.wet(WorldLook.ROAD, 1.0))
	for side in 2:
		var sg := sgn(side)
		var hi := track.half[i]
		var hj := track.half[j]
		if not tiles:
			# The white line.
			b.quad(point(i, sg * (hi - LINE_W)), point(j, sg * (hj - LINE_W)), point(j, sg * hj), point(i, sg * hi), WorldLook.wet(WorldLook.LINE, 1.0))
			# Kerb.
			var ki := kerb_out(i, side)
			var kj := kerb_out(j, side)
			if ki > hi + 0.01 or kj > hj + 0.01:
				var stripe := int(floorf(s / 4.0)) % 2 == 0
				var col := WorldLook.wet(WorldLook.KERB_RED if stripe else WorldLook.KERB_WHITE, 1.0)
				b.quad(point(i, sg * hi, KERB_LIFT), point(j, sg * hj, KERB_LIFT), point(j, sg * kj, KERB_LIFT), point(i, sg * ki, KERB_LIFT), col)
			_runoff(b, i, j, side, ki, kj)
		if deck[i] or deck[j]:
			_deck_side(b, i, j, side)
		elif not tiles:
			# The verge slopes from the barrier down into the terrain.
			var bi: float = bar[side][i]
			var bj: float = bar[side][j]
			var oi := point(i, sg * (bi + VERGE))
			var oj := point(j, sg * (bj + VERGE))
			oi.y = _terrain.height(oi.x, oi.z)
			oj.y = _terrain.height(oj.x, oj.z)
			b.quad(point(i, sg * bi), point(j, sg * bj), oj, oi, WorldLook.wet(_terrain.near_colour(oi.x, oi.z), 0.2))


## Run-off from the kerb to the barrier, and the pit lane on its side.
func _runoff(b: MeshBuf, i: int, j: int, side: int, ki: float, kj: float) -> void:
	var sg := sgn(side)
	var s := i * track.step
	var bi: float = bar[side][i]
	var bj: float = bar[side][j]
	var col := WorldLook.runoff(track.run_kind[side][i])
	if deck[i]:
		col = WorldLook.wet(WorldLook.DECK, 0.9)
	var pit := track.pit
	if not pit.is_empty() and side == (0 if pit.side > 0 else 1) and track.in_pit_range(s) and track.in_pit_range(s + track.step):
		var wl: float = pit.wall_lat
		b.quad(point(i, sg * ki), point(j, sg * kj), point(j, sg * wl), point(i, sg * wl), WorldLook.wet(WorldLook.TARMAC, 0.95))
		b.quad(point(i, sg * wl), point(j, sg * wl), point(j, sg * bj), point(i, sg * bi), WorldLook.wet(WorldLook.PIT_ROAD, 1.0))
		return
	b.quad(point(i, sg * ki), point(j, sg * kj), point(j, sg * bj), point(i, sg * bi), col)


## A bridge deck's edge: a parapet and the slab's side and underside.
func _deck_side(b: MeshBuf, i: int, j: int, side: int) -> void:
	var sg := sgn(side)
	var ei: float = bar[side][i] + WALL_W
	var ej: float = bar[side][j] + WALL_W
	var a0 := point(i, sg * ei)
	var a1 := point(j, sg * ej)
	var out := Vector3(track.normal[i].x, 0, track.normal[i].y) * sg
	var down := Vector3.DOWN * DECK_DEPTH
	var deck_col := WorldLook.wet(WorldLook.CONCRETE, 0.1)
	# Outer face of the slab and underside to the middle.
	b.quad(a0, a1, a1 + down, a0 + down, deck_col, out)
	var m0 := point(i, 0.0) + down
	var m1 := point(j, 0.0) + down
	m0.y = minf(m0.y, a0.y + down.y)
	m1.y = minf(m1.y, a1.y + down.y)
	b.quad(a0 + down, a1 + down, m1, m0, WorldLook.wet(WorldLook.DECK, 0.0), Vector3.DOWN)
	if tiles:
		return
	# Run-off out to the parapet, then the parapet itself.
	var bi: float = bar[side][i]
	var bj: float = bar[side][j]
	b.quad(point(i, sg * bi), point(j, sg * bj), a1, a0, WorldLook.wet(WorldLook.DECK, 0.9))


# --- Walls ---------------------------------------------------------------

func _walls() -> void:
	var n := track.n
	for side in 2:
		var sg := sgn(side)
		for i in n:
			var j := (i + 1) % n
			var kind: int = track.barrier[side][i]
			var on_deck := deck[i] != 0
			if kind != TrackPlan.Barrier.WALL and not on_deck:
				continue
			var lat_i: float = bar[side][i] + WALL_W * 0.5
			var lat_j: float = bar[side][j] + WALL_W * 0.5
			var a := point(i, sg * lat_i)
			var bb := point(j, sg * lat_j)
			var across := Vector3(track.normal[i].x, 0, track.normal[i].y)
			var prev_wall: bool = track.barrier[side][posmod(i - 1, n)] == TrackPlan.Barrier.WALL or deck[posmod(i - 1, n)] != 0
			var next_wall: bool = track.barrier[side][j] == TrackPlan.Barrier.WALL or deck[j] != 0
			var buf: MeshBuf = _bufs[i / CHUNK]
			var stripe := int(floorf(i * track.step / 6.0)) % 2 == 0
			var face := WorldLook.wet(WorldLook.CONCRETE if stripe or on_deck else Color("eceef3"), 0.15)
			buf.box(a, bb, across, WALL_W, WALL_H, face, WorldLook.wet(WorldLook.WALL_TOP, 0.2), not prev_wall or not next_wall)
	# The pit wall.
	var pit := track.pit
	if pit.is_empty():
		return
	var ps := 0 if pit.side > 0 else 1
	var s := float(pit.wall_in)
	var lat: float = sgn(ps) * float(pit.wall_lat)
	while s < float(pit.wall_out):
		var s2 := minf(s + track.step, float(pit.wall_out))
		var a := track.world(track.wrap_s(s), lat)
		var bb := track.world(track.wrap_s(s2), lat)
		var nn := track.normal_at(s)
		_buf_at(track.wrap_s(s)).box(a, bb, Vector3(nn.x, 0, nn.y), 0.7, 1.15, WorldLook.wet(WorldLook.CONCRETE, 0.1), WorldLook.wet(WorldLook.WALL_TOP, 0.2), s == float(pit.wall_in) or s2 >= float(pit.wall_out))
		s = s2


# --- Paint ---------------------------------------------------------------

## A painted strip on the road from s0 to s1 (metres, may be negative),
## between two lateral offsets.
func paint(s0: float, s1: float, lat0: float, lat1: float, col: Color, lift := PAINT_LIFT) -> void:
	var b := _buf_at(track.wrap_s(s0))
	var steps := maxi(1, ceili((s1 - s0) / 2.0))
	for k in steps:
		var a := s0 + (s1 - s0) * k / steps
		var c := s0 + (s1 - s0) * (k + 1) / steps
		b.quad(track.world(track.wrap_s(a), lat0, lift), track.world(track.wrap_s(c), lat0, lift), track.world(track.wrap_s(c), lat1, lift), track.world(track.wrap_s(a), lat1, lift), WorldLook.wet(col, 1.0))


## A painted line from (s0, lat0) to (s1, lat1), `w` metres wide.
func paint_line(s0: float, lat0: float, s1: float, lat1: float, w: float, col: Color) -> void:
	var b := _buf_at(track.wrap_s(s0))
	var steps := maxi(1, ceili(absf(s1 - s0) / 3.0))
	for k in steps:
		var f0 := float(k) / steps
		var f1 := float(k + 1) / steps
		var sa := lerpf(s0, s1, f0)
		var sb := lerpf(s0, s1, f1)
		var la := lerpf(lat0, lat1, f0)
		var lb := lerpf(lat0, lat1, f1)
		b.quad(track.world(track.wrap_s(sa), la - w * 0.5, PAINT_LIFT), track.world(track.wrap_s(sb), lb - w * 0.5, PAINT_LIFT), track.world(track.wrap_s(sb), lb + w * 0.5, PAINT_LIFT), track.world(track.wrap_s(sa), la + w * 0.5, PAINT_LIFT), WorldLook.wet(WorldLook.LINE, 1.0))


func _paint_all() -> void:
	var h := track.half[0] - LINE_W
	# Start line: a chequered band and a white line.
	var cells := int(floorf(h * 2.0 / 1.0))
	var cw := h * 2.0 / cells
	for row in 2:
		for k in cells:
			var black := (k + row) % 2 == 0
			paint(-0.9 + row * 0.9, -0.9 + row * 0.9 + 0.9, -h + k * cw, -h + (k + 1) * cw, Color("1d1d22") if black else WorldLook.LINE)
	if not tiles:
		_paint_grid()
	for z in track.drs:
		var hd := track.value_at(track.half, float(z.detect)) - LINE_W
		paint(float(z.detect), float(z.detect) + 0.5, -hd, hd, WorldLook.DRS_LINE)
		var ha := track.value_at(track.half, float(z.start)) - LINE_W
		paint(float(z.start), float(z.start) + 0.5, -ha, ha, WorldLook.DRS_LINE)
		# Dashes before the activation line.
		for k in 4:
			paint(float(z.start) - 6.0 - k * 4.0, float(z.start) - 4.0 - k * 4.0, -0.2, 0.2, WorldLook.DRS_LINE)
	_paint_pit()


func _paint_grid() -> void:
	for g in track.grid:
		var s := float(g.s)
		if s > track.length * 0.5:
			s -= track.length
		var lat := float(g.lat)
		var front := s + 2.8
		paint(front, front + 0.35, lat - 1.6, lat + 1.6, WorldLook.LINE)
		paint(front - 2.2, front, lat - 1.6, lat - 1.25, WorldLook.LINE)
		paint(front - 2.2, front, lat + 1.25, lat + 1.6, WorldLook.LINE)


func _paint_pit() -> void:
	var pit := track.pit
	if pit.is_empty():
		return
	var sg := float(pit.side)
	var wl := float(pit.wall_lat)
	var ol := float(pit.outer_lat)
	var hw := track.half[0]
	if not tiles:
		# Entry and exit lines from the track edge to the pit wall.
		paint_line(float(pit.entry), sg * hw, float(pit.wall_in), sg * (wl - 0.3), 0.4, WorldLook.LINE)
		paint_line(float(pit.wall_out), sg * (wl - 0.3), float(pit.exit), sg * hw, 0.4, WorldLook.LINE)
		# Lane edges.
		paint(float(pit.wall_in), float(pit.wall_out), sg * (wl + 0.6), sg * (wl + 1.0), WorldLook.LINE)
		var fast := (float(pit.lane_lat) + float(pit.box_lat)) * 0.5 - 0.6
		for k in int((float(pit.limit_out) - float(pit.limit_in)) / 6.0):
			var a := float(pit.limit_in) + k * 6.0
			paint(a, a + 3.0, sg * fast, sg * (fast + 0.3), WorldLook.LINE)
		# The team boxes.
		for bs in pit.boxes:
			var c := float(bs)
			var bl := float(pit.box_lat)
			paint(c - 3.4, c + 3.4, sg * (bl - 2.0), sg * (bl - 1.7), WorldLook.BOX_LINE)
			paint(c - 3.4, c + 3.4, sg * (bl + 1.7), sg * (bl + 2.0), WorldLook.BOX_LINE)
			paint(c + 3.1, c + 3.4, sg * (bl - 1.7), sg * (bl + 1.7), WorldLook.BOX_LINE)
			paint(c - 3.4, c - 3.1, sg * (bl - 1.7), sg * (bl + 1.7), WorldLook.BOX_LINE)
	# Speed limit lines across the lane.
	for s: float in [float(pit.limit_in), float(pit.limit_out)]:
		for k in 6:
			var a := wl + 1.0 + k * (ol - wl - 1.5) / 6.0
			paint(s, s + 0.6, sg * a, sg * (a + (ol - wl - 1.5) / 12.0), WorldLook.LINE)
