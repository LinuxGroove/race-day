class_name Track
extends RefCounted
## A built circuit: the centreline sampled every STEP metres, with height,
## banking, width, run-off, kerbs, the racing line and its speeds, corners,
## sectors, DRS zones, the pit lane and the grid. Everything the cars, the AI,
## the rules and the view need comes from here, so a circuit is one plan.
##
## Distances along the lap (s) start at the start line. Lateral offsets (lat)
## are positive to the left of the direction of travel. Positions are in
## metres with Y up; a heading of 0 points along +Z (the way Kenney's cars face).

const STEP := 2.0
## Pit lane: the wall between it and the track sits this far outside the
## track edge, and the lane is this wide beyond it.
const PIT_WALL_GAP := 3.0
const PIT_LANE_WIDTH := 11.0
const PIT_LIMIT_KMH := 80.0
## Kerb width outside the white line, and how far kerbs stand above the road.
const KERB_WIDTH := 1.6
const KERB_LIFT := 0.03

## A point on the track: where a position is along the lap and across it.
class Spot:
	var idx := 0
	var s := 0.0
	var lat := 0.0
	var y := 0.0
	var half := 7.0
	## Height change per metre along the track, and across it (to the left).
	var slope := 0.0
	var bank := 0.0
	var tangent := Vector2(0, 1)
	var normal := Vector2(1, 0)
	var in_pit := false

var id := ""
var name := ""
var length := 0.0
var n := 0
var step := STEP
var plan: TrackPlan

var pos := PackedVector3Array()
var tangent := PackedVector2Array()
var normal := PackedVector2Array()
var curv := PackedFloat32Array()
## Height change across the track per metre to the left.
var bank := PackedFloat32Array()
var half := PackedFloat32Array()
## Run-off per side: 0 is the left, 1 the right.
## (Plain arrays: packed arrays inside an Array are copied when changed.)
var run_kind := [[], []]
var run_width := [[], []]
var barrier := [[], []]
var kerb := [[], []]
## Distance from the centreline to the barrier per sample and side, pulled in
## on the inside of tight corners so the ground never folds over itself. The
## cars hit the barriers here and the view stands them here.
var bar := [PackedFloat32Array(), PackedFloat32Array()]

var line_off := PackedFloat32Array()
var line_speed := PackedFloat32Array()
var line_curv := PackedFloat32Array()
## {"start", "end", "apex", "dir" (1 left, -1 right), "radius", "number"}
var corners: Array = []
## {"detect", "start", "end"}
var drs: Array = []
## The ends of sectors 1 and 2.
var sectors := [0.0, 0.0]
## {"side", "entry", "exit", "wall_in", "wall_out", "limit_in", "limit_out",
## "wall_lat", "lane_lat", "box_lat", "outer_lat", "boxes": [s, ...]} with
## the s values as distances along the lap (entry and limit_in are negative,
## before the line).
var pit := {}
## Stretches with a feature (TrackPlan.FEATURES): [{"kind", "from", "to"}],
## with from and to as distances along the lap (to may wrap past from).
var features: Array = []
## The plan's landmarks with "s" (distance along the lap) worked out.
var landmarks: Array = []
## Grid slots behind the line: [{"s", "lat"}], pole first.
var grid: Array = []
var bounds := AABB()

var _hash := {}
const HASH_CELL := 40.0


## Builds a track from a plan. `track_id` names it for saves and boards.
static func build(p_plan: TrackPlan, track_id := "", track_name := "") -> Track:
	var t := Track.new()
	t.id = track_id
	t.name = track_name
	t.plan = p_plan
	t._build()
	return t


## A plan's pieces as the build lays them: corners closed to a full turn
## and AUTO straights given their lengths. TrackPlan.resolved() uses this.
static func solve_pieces(p_plan: TrackPlan) -> Array:
	var t := Track.new()
	t.plan = p_plan
	var pieces: Array = p_plan.pieces.duplicate(true)
	t._close_heading(pieces)
	t._solve_autos(pieces)
	return pieces


# --- Queries -------------------------------------------------------------

## The sample index for distance s along the lap.
func index_at(s: float) -> int:
	return posmod(int(floorf(s / step)), n)


## Wraps a distance into [0, length).
func wrap_s(s: float) -> float:
	return fposmod(s, length)


## Signed distance from a to b along the lap, the short way round.
func delta_s(a: float, b: float) -> float:
	var d := fposmod(b - a + length * 0.5, length) - length * 0.5
	return d


## The centreline point at s, interpolated.
func center_at(s: float) -> Vector3:
	s = wrap_s(s)
	var i := int(s / step) % n
	var f := s / step - floorf(s / step)
	return pos[i].lerp(pos[(i + 1) % n], f)


func tangent_at(s: float) -> Vector2:
	s = wrap_s(s)
	var i := int(s / step) % n
	var f := s / step - floorf(s / step)
	return tangent[i].lerp(tangent[(i + 1) % n], f).normalized()


func normal_at(s: float) -> Vector2:
	var t := tangent_at(s)
	return Vector2(t.y, -t.x)


## Heading (yaw) of the track at s.
func heading_at(s: float) -> float:
	var t := tangent_at(s)
	return atan2(t.x, t.y)


## Interpolates a per-sample float array (packed or plain) at s.
func value_at(arr, s: float) -> float:
	s = wrap_s(s)
	var i := int(s / step) % n
	var f := s / step - floorf(s / step)
	return lerpf(arr[i], arr[(i + 1) % n], f)


## The surface height at (s, lat). Past the track edge the run-off stays
## level with the edge.
func height_at(s: float, lat: float) -> float:
	var c := center_at(s)
	var h := value_at(half, s)
	return c.y + clampf(lat, -h, h) * value_at(bank, s)


## World position of (s, lat) on the surface.
func world(s: float, lat: float, lift := 0.0) -> Vector3:
	var c := center_at(s)
	var nn := normal_at(s)
	return Vector3(c.x + nn.x * lat, height_at(s, lat) + lift, c.z + nn.y * lat)


## Where the racing line is at s.
func line_point(s: float, lift := 0.0) -> Vector3:
	return world(s, value_at(line_off, s), lift)


## The run-off on one side at s: side 0 left, 1 right.
func runoff_width(s: float, side: int) -> float:
	return value_at(run_width[side], s)


## Distance from the centreline to the barrier on a side (positive).
func barrier_off(s: float, side: int) -> float:
	return value_at(bar[side], s)


## The height of the ground a wheel rolls on at a point: the road with its
## banking, the kerbs standing a little proud of it, and the run-off. Fills
## `out` with where the point is.
func ground_y(p: Vector2, hint: int, out: Spot) -> float:
	locate(p, hint, out)
	var a := absf(out.lat)
	var side := 0 if out.lat > 0.0 else 1
	if a > out.half and a < out.half + KERB_WIDTH and has_kerb(out.s, side) and a < barrier_off(out.s, side):
		return out.y + KERB_LIFT
	return out.y


func has_kerb(s: float, side: int) -> bool:
	return kerb[side][index_at(s)] != 0


func runoff_kind(s: float, side: int) -> int:
	return run_kind[side][index_at(s)]


## Whether s lies between the pit entry and exit.
func in_pit_range(s: float) -> bool:
	if pit.is_empty():
		return false
	var d := delta_s(0.0, s)
	return d >= pit.entry and d <= pit.exit


## Whether the pit wall separates the pit lane from the track at s.
func pit_wall_at(s: float) -> bool:
	if pit.is_empty():
		return false
	var d := delta_s(0.0, s)
	return d >= pit.wall_in and d <= pit.wall_out


## Finds where a position is on the track, searching near a previous sample
## (`hint`, or -1 to search everywhere). Fills `out` and returns it.
func locate(p: Vector2, hint: int, out: Spot = null) -> Spot:
	if out == null:
		out = Spot.new()
	var best := -1
	if hint >= 0 and hint < n:
		# Walk from the hint towards the nearer neighbour while it gets closer.
		best = hint
		var d0 := _dist2(p, hint)
		var fwd := _dist2(p, (hint + 1) % n)
		var dir := 1 if fwd < d0 else -1
		var dn := fwd if dir == 1 else _dist2(p, posmod(hint - 1, n))
		var steps := 0
		while dn < d0 and steps < 200:
			best = posmod(best + dir, n)
			d0 = dn
			dn = _dist2(p, posmod(best + dir, n))
			steps += 1
		# Lost (a rewind, a teleport): search everywhere.
		if d0 > 60.0 * 60.0:
			best = -1
	if best < 0:
		best = _nearest_any(p)
	# Project onto the segment before or after the nearest sample.
	var i := best
	var a := Vector2(pos[i].x, pos[i].z)
	var t := tangent[i]
	var along := (p - a).dot(t)
	if along < 0.0:
		i = posmod(i - 1, n)
		a = Vector2(pos[i].x, pos[i].z)
		t = tangent[i]
		along = (p - a).dot(t)
	along = clampf(along, 0.0, step)
	var f := along / step
	var j2 := (i + 1) % n
	var tt := tangent[i].lerp(tangent[j2], f).normalized()
	var nn := Vector2(tt.y, -tt.x)
	var cp := Vector2(pos[i].x, pos[i].z).lerp(Vector2(pos[j2].x, pos[j2].z), f)
	out.idx = i
	out.s = wrap_s(i * step + along)
	out.lat = (p - cp).dot(nn)
	out.tangent = tt
	out.normal = nn
	out.half = lerpf(half[i], half[j2], f)
	out.bank = lerpf(bank[i], bank[j2], f)
	var cy := lerpf(pos[i].y, pos[j2].y, f)
	out.y = cy + clampf(out.lat, -out.half, out.half) * out.bank
	out.slope = (pos[j2].y - pos[i].y) / step
	if absf(out.lat) > out.half:
		out.bank = 0.0
	out.in_pit = _in_pit_lane(out.s, out.lat)
	return out


func _dist2(p: Vector2, i: int) -> float:
	var q := pos[i]
	return (p.x - q.x) * (p.x - q.x) + (p.y - q.z) * (p.y - q.z)


func _in_pit_lane(s: float, lat: float) -> bool:
	if pit.is_empty() or not in_pit_range(s):
		return false
	return lat * pit.side > pit.wall_lat - 0.5


func _nearest_any(p: Vector2) -> int:
	var cell := Vector2i(floori(p.x / HASH_CELL), floori(p.y / HASH_CELL))
	var best := 0
	var best_d := INF
	for r in range(0, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for j in _hash.get(cell + Vector2i(dx, dz), []):
					var d := p.distance_squared_to(Vector2(pos[j].x, pos[j].z))
					if d < best_d:
						best_d = d
						best = j
		if best_d < INF and sqrt(best_d) < (r - 1) * HASH_CELL:
			break
	if best_d == INF:
		for j in n:
			var d := p.distance_squared_to(Vector2(pos[j].x, pos[j].z))
			if d < best_d:
				best_d = d
				best = j
	return best


## Indices of samples within `radius` of a point (for scenery and checks).
func samples_near(p: Vector2, radius: float) -> Array:
	var out := []
	var r := ceili(radius / HASH_CELL)
	var cell := Vector2i(floori(p.x / HASH_CELL), floori(p.y / HASH_CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for j in _hash.get(cell + Vector2i(dx, dz), []):
				if p.distance_to(Vector2(pos[j].x, pos[j].z)) <= radius:
					out.append(j)
	return out


## The corner that s is in or next approaching, or {}.
func next_corner(s: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in corners:
		var d := fposmod(float(c.start) - s, length)
		if delta_s(float(c.start), s) >= 0.0 and delta_s(s, float(c.end)) >= 0.0:
			return c
		if d < best_d:
			best_d = d
			best = c
	return best


## Which sector (0, 1 or 2) s is in.
func sector_of(s: float) -> int:
	s = wrap_s(s)
	if s < sectors[0]:
		return 0
	if s < sectors[1]:
		return 1
	return 2


# --- Building ------------------------------------------------------------

func _build() -> void:
	var pieces: Array = plan.pieces.duplicate(true)
	_close_heading(pieces)
	_solve_autos(pieces)
	length = 0.0
	for p in pieces:
		length += float(p.length)
	n = maxi(8, int(round(length / STEP)))
	step = length / n
	var raw := _sample(pieces)
	var shift := int(round(plan.start_at / step))
	pos.resize(n)
	tangent.resize(n)
	normal.resize(n)
	half.resize(n)
	bank.resize(n)
	for side in 2:
		for arr in [run_kind[side], run_width[side], barrier[side], kerb[side]]:
			arr.resize(n)
			arr.fill(0)
	var heights := _smooth_loop(raw.y, 14)
	heights = _smooth_loop(heights, 14)
	var widths := _smooth_loop(raw.w, 10)
	var banks := _smooth_loop(_smooth_loop(raw.b, 14), 14)
	var rw := [_smooth_loop(PackedFloat32Array(raw.rw[0]), 8), _smooth_loop(PackedFloat32Array(raw.rw[1]), 8)]
	for i in n:
		var j := (i + shift) % n
		var p2: Vector2 = raw.p[j]
		pos[i] = Vector3(p2.x, heights[j], p2.y)
		half[i] = widths[j] * 0.5
		bank[i] = banks[j]
		for side in 2:
			run_kind[side][i] = raw.rk[side][j]
			run_width[side][i] = maxf(1.0, rw[side][j])
			barrier[side][i] = raw.bk[side][j]
	for i in n:
		var a := Vector2(pos[i].x, pos[i].z)
		var b := Vector2(pos[(i + 1) % n].x, pos[(i + 1) % n].z)
		var t := (b - a).normalized()
		tangent[i] = t
		normal[i] = Vector2(t.y, -t.x)
	_curvature()
	_place_features(pieces, shift * step)
	_hash_samples()
	_bounds()
	_pit_lane()
	_limit_runoff()
	_find_corners()
	_kerbs()
	_barriers()
	RacingLine.compute(self)
	_sectors_and_drs()
	_grid()


## Corners must make one full turn. Small errors (rounding in a plan) are
## spread over every corner; big ones are a mistake in the plan.
func _close_heading(pieces: Array) -> void:
	var total := 0.0
	var arcs := 0.0
	for p in pieces:
		total += float(p.angle)
		arcs += absf(float(p.angle))
	var target := (TAU if total > 0.0 else -TAU) * plan.winding
	var err := target - total
	if absf(err) > deg_to_rad(3.0):
		push_error("Track %s: corners turn %.1f degrees, not %d" % [id, rad_to_deg(total), 360 * plan.winding])
	if arcs <= 0.0:
		return
	for p in pieces:
		if p.kind == "arc":
			var a := float(p.angle)
			p.angle = a + err * absf(a) / arcs
			p.length = absf(float(p.angle)) * float(p.radius)


## Two AUTO straights get the lengths that bring the lap back to its start.
func _solve_autos(pieces: Array) -> void:
	var autos := []
	for i in pieces.size():
		if pieces[i].kind == "line" and float(pieces[i].length) < 0.0:
			autos.append(i)
			pieces[i].length = 0.0
	var end := _walk_end(pieces)
	if autos.is_empty():
		if end.length() > 1.0:
			push_warning("Track %s doesn't close by %.1f m" % [id, end.length()])
		return
	if autos.size() != 2:
		push_error("Track %s needs exactly two AUTO straights" % id)
		return
	var d1 := _heading_before(pieces, autos[0])
	var d2 := _heading_before(pieces, autos[1])
	var v := -end
	var det := d1.x * d2.y - d1.y * d2.x
	if absf(det) < 0.05:
		push_error("Track %s: its AUTO straights are parallel" % id)
		return
	var l1 := (v.x * d2.y - v.y * d2.x) / det
	var l2 := (d1.x * v.y - d1.y * v.x) / det
	if l1 < 0.0 or l2 < 0.0:
		push_error("Track %s can't close: AUTO straights would be %.0f m and %.0f m" % [id, l1, l2])
	pieces[autos[0]].length = maxf(l1, 1.0)
	pieces[autos[1]].length = maxf(l2, 1.0)


func _heading_before(pieces: Array, index: int) -> Vector2:
	var h := 0.0
	for i in index:
		h += float(pieces[i].angle)
	return Vector2(sin(h), cos(h))


func _walk_end(pieces: Array) -> Vector2:
	var p := Vector2.ZERO
	var h := 0.0
	for pc in pieces:
		var r := _advance(p, h, pc, float(pc.length))
		p = r[0]
		h = r[1]
	return p


## Position and heading after `u` metres into a piece that starts at p, h.
func _advance(p: Vector2, h: float, pc: Dictionary, u: float) -> Array:
	if pc.kind == "line" or float(pc.length) <= 0.0:
		return [p + Vector2(sin(h), cos(h)) * u, h]
	var k := float(pc.angle) / float(pc.length)
	var h2 := h + k * u
	return [p + Vector2((cos(h) - cos(h2)) / k, (sin(h2) - sin(h)) / k), h2]


## Samples every piece: position, height, width, bank and run-off, before
## smoothing and before moving the start line to s = 0.
func _sample(pieces: Array) -> Dictionary:
	var pts := PackedVector2Array()
	var ys := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var bs := PackedFloat32Array()
	pts.resize(n)
	ys.resize(n)
	ws.resize(n)
	bs.resize(n)
	var out := {"p": pts, "y": ys, "w": ws, "b": bs, "rk": [[], []], "rw": [[], []], "bk": [[], []]}
	for side in 2:
		for arr in [out.rk[side], out.rw[side], out.bk[side]]:
			arr.resize(n)
	var outside_mark := [[], []]
	for side in 2:
		outside_mark[side].resize(n)
		outside_mark[side].fill(-1)
	var piece_start := []
	var acc := 0.0
	for pc in pieces:
		piece_start.append(acc)
		acc += float(pc.length)
	var climb_before := []
	var c := 0.0
	for pc in pieces:
		climb_before.append(c)
		c += float(pc.get("climb", 0.0))
	var total_climb := c
	# Walk the pieces once, keeping the start pose of each.
	var starts := []
	var p := Vector2.ZERO
	var h := 0.0
	for pc in pieces:
		starts.append([p, h])
		var r := _advance(p, h, pc, float(pc.length))
		p = r[0]
		h = r[1]
	var end_err := p
	var pi := 0
	for i in n:
		var s := i * step
		while pi < pieces.size() - 1 and s >= float(piece_start[pi]) + float(pieces[pi].length):
			pi += 1
		var pc: Dictionary = pieces[pi]
		var u := s - float(piece_start[pi])
		var r := _advance(starts[pi][0], starts[pi][1], pc, u)
		# Any leftover closing error is spread along the lap.
		pts[i] = r[0] - end_err * (s / length)
		var plen := maxf(float(pc.length), 0.001)
		ys[i] = float(climb_before[pi]) + float(pc.get("climb", 0.0)) * smoothstep(0.0, 1.0, u / plen) - total_climb * (s / length)
		ws[i] = float(pc.get("width", plan.width))
		var bdeg := float(pc.get("bank", 0.0))
		var dir := signf(float(pc.angle)) if pc.kind == "arc" else -1.0
		# Raising the outside of a left-hander lifts the right (negative lat).
		bs[i] = -dir * tan(deg_to_rad(bdeg))
		for side in 2:
			var e := _edge_for(pc, side)
			out.rk[side][i] = int(e.kind)
			out.rw[side][i] = float(e.width)
			out.bk[side][i] = int(e.barrier)
	# Corners carry their outside run-off a little before and after.
	for k in pieces.size():
		var pk: Dictionary = pieces[k]
		if pk.kind != "arc" or pk.has("outside") or pk.has(_side_key(_outside_side(pk))):
			continue
		var from := int(floorf((float(piece_start[k]) - 45.0) / step))
		var to := int(ceilf((float(piece_start[k]) + float(pk.length) + 70.0) / step))
		for kk in range(from, to + 1):
			var m := posmod(kk, n)
			if outside_mark[_outside_side(pk)][m] < 0:
				outside_mark[_outside_side(pk)][m] = k
	for side in 2:
		for i in n:
			var mark: int = outside_mark[side][i]
			if mark < 0:
				continue
			var cur_piece := _piece_at(pieces, piece_start, i * step)
			var pc2: Dictionary = pieces[cur_piece]
			if pc2.kind == "arc" and _outside_side(pc2) != side:
				continue
			if pc2.has(_side_key(side)) or pc2.has("outside"):
				continue
			var co: Dictionary = plan.corner_outside
			out.rk[side][i] = int(co.kind)
			out.rw[side][i] = maxf(float(out.rw[side][i]), float(co.width))
			out.bk[side][i] = int(co.barrier)
	out.p = pts
	out.y = ys
	out.w = ws
	out.b = bs
	return out


func _place_features(pieces: Array, start: float) -> void:
	features.clear()
	landmarks.clear()
	var acc := 0.0
	var ends := []
	for pc in pieces:
		if pc.has("feature"):
			features.append({"kind": pc.feature, "from": wrap_s(acc - start), "to": wrap_s(acc + float(pc.length) - start)})
		acc += float(pc.length)
		ends.append(acc)
	# Neighbouring pieces with the same feature make one stretch.
	var joined := []
	for f in features:
		if not joined.is_empty() and joined[-1].kind == f.kind and absf(delta_s(float(joined[-1].to), float(f.from))) < 1.0:
			joined[-1].to = f.to
		else:
			joined.append(f)
	if joined.size() > 1 and joined[0].kind == joined[-1].kind and absf(delta_s(float(joined[-1].to), float(joined[0].from))) < 1.0:
		joined[0].from = joined[-1].from
		joined.pop_back()
	features = joined
	for l in plan.landmarks:
		var m: Dictionary = l.duplicate(true)
		var k := int(m.piece)
		m["s"] = wrap_s((float(ends[k - 1]) if k > 0 else 0.0) - start)
		landmarks.append(m)


## The feature at distance s ("" for none).
func feature_at(s: float) -> String:
	for f in features:
		if fposmod(s - float(f.from), length) <= fposmod(float(f.to) - float(f.from), length):
			return f.kind
	return ""


func _piece_at(pieces: Array, piece_start: Array, s: float) -> int:
	for k in range(pieces.size() - 1, -1, -1):
		if s >= float(piece_start[k]):
			return k
	return 0


static func _side_key(side: int) -> String:
	return "left" if side == 0 else "right"


## The side a corner's outside is on: a left-hander's outside is the right.
static func _outside_side(pc: Dictionary) -> int:
	return 1 if float(pc.angle) > 0.0 else 0


func _edge_for(pc: Dictionary, side: int) -> Dictionary:
	var e: Dictionary = plan.edge.duplicate()
	if pc.kind == "arc":
		var outside := _outside_side(pc) == side
		if outside:
			e = plan.corner_outside.duplicate()
		if outside and pc.has("outside"):
			e.merge(pc.outside, true)
		elif not outside and pc.has("inside"):
			e.merge(pc.inside, true)
	var key := _side_key(side)
	if pc.has(key):
		e.merge(pc[key], true)
	return e


## A circular moving average over `radius` samples each way.
func _smooth_loop(arr: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	if radius <= 0:
		return arr.duplicate()
	var sum := 0.0
	for k in range(-radius, radius + 1):
		sum += arr[posmod(k, n)]
	var w := float(2 * radius + 1)
	for i in n:
		out[i] = sum / w
		sum += arr[posmod(i + radius + 1, n)] - arr[posmod(i - radius, n)]
	return out


func _curvature() -> void:
	curv.resize(n)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a := tangent[posmod(i - 2, n)]
		var b := tangent[(i + 2) % n]
		var ang := atan2(a.x * b.y - a.y * b.x, a.dot(b))
		# Turning left (towards +lat) is positive.
		raw[i] = -ang / (4.0 * step)
	curv = _smooth_loop(raw, 2)


func _hash_samples() -> void:
	_hash.clear()
	for i in n:
		var cell := Vector2i(floori(pos[i].x / HASH_CELL), floori(pos[i].z / HASH_CELL))
		if not _hash.has(cell):
			_hash[cell] = []
		_hash[cell].append(i)


func _bounds() -> void:
	var lo := pos[0]
	var hi := pos[0]
	for p in pos:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	bounds = AABB(lo, hi - lo)


## Run-off can't reach into another part of the track: where two parts run
## close together (a hairpin, a parallel straight), each gets half the gap.
func _limit_runoff() -> void:
	for i in n:
		var p := Vector2(pos[i].x, pos[i].z)
		var reach := half[i] + maxf(run_width[0][i], run_width[1][i]) + KERB_WIDTH + 30.0
		for j in samples_near(p, reach + 10.0):
			var ds := absf(delta_s(i * step, j * step))
			var q := Vector2(pos[j].x, pos[j].z)
			var d := p.distance_to(q)
			if ds < d * 1.3 + 30.0:
				continue
			if absf(pos[i].y - pos[j].y) > 4.5:
				continue
			var side_lat := (q - p).dot(normal[i])
			var side := 0 if side_lat > 0.0 else 1
			if not pit.is_empty() and side == (0 if pit.side > 0 else 1) and in_pit_range(i * step):
				continue
			var gap := absf(side_lat) - half[i] - half[j] - KERB_WIDTH * 2.0
			var allowed := maxf(1.0, gap * 0.5 - 0.6)
			if run_width[side][i] > allowed:
				run_width[side][i] = allowed
				if allowed < 4.0:
					run_kind[side][i] = TrackPlan.Runoff.GRASS if run_kind[side][i] != TrackPlan.Runoff.TARMAC else run_kind[side][i]
					if barrier[side][i] == TrackPlan.Barrier.TYRES or barrier[side][i] == TrackPlan.Barrier.FENCE:
						barrier[side][i] = TrackPlan.Barrier.ARMCO
	for side in 2:
		run_width[side] = _min_smooth(run_width[side], 6)


## Smooths a width profile downwards only, so limits taper instead of stepping.
func _min_smooth(arr: Array, radius: int) -> Array:
	var low := arr.duplicate()
	for i in n:
		var m := float(arr[i])
		for k in range(-radius, radius + 1):
			var v := float(arr[posmod(i + k, n)]) + absf(k) * step * 0.6
			m = minf(m, v)
		low[i] = m
	return low


func _find_corners() -> void:
	corners.clear()
	var thresh := 1.0 / 420.0
	var i := 0
	# Start the scan on a straight so no corner is split by the wrap.
	var start := 0
	for k in n:
		if absf(curv[k]) < thresh * 0.5:
			start = k
			break
	var in_corner := false
	var c := {}
	for kk in n + 1:
		i = (start + kk) % n
		var k := curv[i]
		if absf(k) >= thresh and (not in_corner or signf(k) == c.dir):
			if not in_corner:
				in_corner = true
				c = {"start": i * step, "end": i * step, "apex": i * step, "dir": int(signf(k)), "peak": absf(k)}
			c.end = i * step
			if absf(k) > c.peak:
				c.peak = absf(k)
				c.apex = i * step
		elif in_corner:
			in_corner = false
			if fposmod(float(c.end) - float(c.start), length) > 6.0:
				corners.append(c)
			if absf(k) >= thresh:
				in_corner = true
				c = {"start": i * step, "end": i * step, "apex": i * step, "dir": int(signf(k)), "peak": absf(k)}
	# Merge pieces of one corner split by a brief straightening.
	var merged := []
	for cc in corners:
		if not merged.is_empty():
			var last: Dictionary = merged[-1]
			if int(last.dir) == int(cc.dir) and fposmod(float(cc.start) - float(last.end), length) < 24.0:
				last.end = cc.end
				if float(cc.peak) > float(last.peak):
					last.peak = cc.peak
					last.apex = cc.apex
				continue
		merged.append(cc)
	merged.sort_custom(func(a, b): return float(a.start) < float(b.start))
	for k in merged.size():
		merged[k].number = k + 1
		merged[k].radius = 1.0 / maxf(float(merged[k].peak), 0.0001)
	corners = merged


func _kerbs() -> void:
	for side in 2:
		kerb[side].fill(0)
	for c in corners:
		if float(c.radius) > plan.kerb_radius:
			continue
		var inside := 0 if int(c.dir) > 0 else 1
		var outside := 1 - inside
		var st := float(c.start)
		var en := float(c.end)
		var len := fposmod(en - st, length)
		_mark_kerb(inside, st + len * 0.12, st + len * 0.88)
		_mark_kerb(outside, st - 24.0, st + minf(10.0, len * 0.2))
		_mark_kerb(outside, st + len * 0.55, en + 34.0)


func _mark_kerb(side: int, from: float, to: float) -> void:
	var a := int(floorf(from / step))
	var b := int(ceilf(to / step))
	for k in range(a, b + 1):
		var kk := posmod(k, n)
		if not pit.is_empty() and side == (0 if pit.side > 0 else 1) and in_pit_range(kk * step):
			continue
		kerb[side][kk] = 1


## Where the barriers stand: past the run-off and kerbs (and the pit lane on
## its side), but no further in on the inside of a tight corner than most of
## its radius, where the ground would fold over itself.
func _barriers() -> void:
	for side in 2:
		bar[side].resize(n)
		for i in n:
			var s := i * step
			var off := half[i] + float(run_width[side][i])
			if kerb[side][i] != 0:
				off += KERB_WIDTH
			if not pit.is_empty() and side == (0 if pit.side > 0 else 1) and in_pit_range(s):
				off = maxf(off, pit.outer_lat)
			bar[side][i] = off
	for i in n:
		var kl := 0.0
		var kr := 0.0
		for k in range(-8, 9):
			var c := curv[posmod(i + k, n)]
			kl = maxf(kl, c)
			kr = maxf(kr, -c)
		var h := half[i]
		if kl > 0.0001:
			bar[0][i] = clampf(bar[0][i], h + 0.6, maxf(h + 0.6, 0.85 / kl))
		if kr > 0.0001:
			bar[1][i] = clampf(bar[1][i], h + 0.6, maxf(h + 0.6, 0.85 / kr))


func _pit_lane() -> void:
	if plan.pit_before <= 0.0:
		pit = {}
		return
	var side := plan.pit_side
	var hw := half[0]
	var wall_lat := hw + PIT_WALL_GAP
	pit = {
		"side": side,
		"entry": -plan.pit_before,
		"exit": plan.pit_after,
		"wall_in": -plan.pit_before + 110.0,
		"wall_out": plan.pit_after - 90.0,
		"limit_in": -plan.pit_before + 120.0,
		"limit_out": plan.pit_after - 100.0,
		"wall_lat": wall_lat,
		"lane_lat": wall_lat + 3.5,
		"box_lat": wall_lat + 8.5,
		"outer_lat": maxf(wall_lat + PIT_LANE_WIDTH, plan.pit_outer_min),
		"boxes": [],
	}
	# Ten teams' boxes, 15 m apart, centred between the speed limit lines.
	var mid := (float(pit.limit_in) + float(pit.limit_out)) * 0.5
	for k in 10:
		pit.boxes.append(mid + (k - 4.5) * 15.0)
	# The pit side's run-off is the pit lane itself.
	var pside := 0 if side > 0 else 1
	for i in n:
		if in_pit_range(i * step):
			run_kind[pside][i] = TrackPlan.Runoff.TARMAC
			barrier[pside][i] = TrackPlan.Barrier.WALL
			run_width[pside][i] = maxf(run_width[pside][i], pit.outer_lat - half[i])


func _sectors_and_drs() -> void:
	sectors = [length / 3.0, length * 2.0 / 3.0]
	# Nudge sector lines onto straights so they don't sit mid-corner.
	for k in 2:
		var s0: float = sectors[k]
		for c in corners:
			if delta_s(float(c.start), s0) >= 0.0 and delta_s(s0, float(c.end)) >= 0.0:
				s0 = wrap_s(float(c.end) + 40.0)
		sectors[k] = s0
	drs.clear()
	# The longest flat-out runs get DRS.
	var runs := []
	for k in corners.size():
		var a: Dictionary = corners[k]
		var b: Dictionary = corners[(k + 1) % corners.size()]
		var run := fposmod(float(b.start) - float(a.end), length)
		runs.append({"from": float(a.end), "to": float(b.start), "len": run, "after": a})
	runs.sort_custom(func(x, y): return float(x.len) > float(y.len))
	for r in runs.slice(0, 2):
		if float(r.len) < 450.0:
			continue
		var start := wrap_s(float(r.from) + 60.0)
		var end := wrap_s(float(r.to) - 60.0)
		var detect := wrap_s(float(r.after.start) - 60.0)
		drs.append({"detect": detect, "start": start, "end": end})


func _grid() -> void:
	grid.clear()
	# Pole sits on the side of the racing line into turn 1.
	var pole_side := 1.0 if value_at(line_off, 40.0) >= 0.0 else -1.0
	var hw := half[0]
	for k in 24:
		var s := -10.0 - k * 8.0
		var lat := pole_side * (hw * 0.42) * (1.0 if k % 2 == 0 else -1.0)
		grid.append({"s": wrap_s(s), "lat": lat})
