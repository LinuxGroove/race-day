extends SceneTree
## Draws every circuit layout as a PNG map, for checking shapes (and as a
## start for the minimap): run-off, the track shaded by height (the higher
## road drawn over the lower at a crossover), kerbs, the pit lane, the start
## line, corner numbers and landmarks.
##
##   MAPS=/tmp/maps godot --headless --path . -s tools/circuit_maps.gd
##   MAPS=/tmp/maps CIRCUIT=twin_gp godot --headless --path . -s tools/circuit_maps.gd
##
## MAPS is the directory to write to, CIRCUIT picks layouts (comma
## separated, default all) and SIZE sets the image's longer side in pixels.

const LANDMARK_COLOURS := {
	"grandstand": Color("e0e0e0"), "lake": Color("3a7bd5"), "sea": Color("1f4fa8"),
	"river": Color("4a90d9"), "buildings": Color("9a8f86"), "hangars": Color("8a9aa8"),
	"hotel": Color("f2c14e"), "forest": Color("2e6b30"), "cliff": Color("8b6a4f"),
	"rock_wall": Color("b0583a"), "marina": Color("66c2e0"), "farm": Color("c9a646"),
	"dunes": Color("e3c27a"), "hills": Color("6e8f4e"), "lighthouse": Color("ffffff"),
	"village": Color("c47f5a"), "pits_tower": Color("d0d0d0"), "big_screen": Color("202020"),
	"windmills": Color("dadada"),
}

## Landmarks drawn as a dot rather than their size.
const POINTS := ["grandstand", "pits_tower", "big_screen", "lighthouse", "hotel", "windmills"]

## 3 by 5 digits for corner numbers.
const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
]

var _img: Image
var _scale := 1.0
var _origin := Vector2.ZERO


func _init() -> void:
	var dir := OS.get_environment("MAPS")
	if dir == "":
		printerr("Set MAPS to the directory for the maps")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var want := OS.get_environment("CIRCUIT")
	var size := int(OS.get_environment("SIZE")) if OS.get_environment("SIZE") != "" else 1400
	for id in Circuits.ids():
		if want != "" and not id in want.split(","):
			continue
		var t := Circuits.track(id)
		var path := dir.path_join(id + ".png")
		draw(t, size).save_png(path)
		print("%s: %.2f km -> %s" % [id, t.length / 1000.0, path])
	quit()


## The map of one track, `size` pixels on its longer side.
func draw(t: Track, size: int) -> Image:
	var margin := 160.0
	var lo := Vector2(t.bounds.position.x, t.bounds.position.z) - Vector2(margin, margin)
	var span := Vector2(t.bounds.size.x, t.bounds.size.z) + Vector2(margin, margin) * 2.0
	_scale = size / maxf(span.x, span.y)
	_origin = lo
	var w := int(ceil(span.x * _scale))
	var h := int(ceil(span.y * _scale))
	_img = Image.create(w, h, false, Image.FORMAT_RGB8)
	_img.fill(Color("2f4a2a"))
	# Landmarks underneath everything.
	for l in t.landmarks:
		var s := float(l.s)
		var side := float(l.get("side", 1))
		var c := t.center_at(s)
		var nn := t.normal_at(s)
		var at := Vector2(c.x, c.z) + nn * side * float(l.get("distance", 60.0))
		var col: Color = LANDMARK_COLOURS.get(str(l.kind), Color.MAGENTA)
		var r := float(l.get("size", 80.0)) * 0.5
		if str(l.kind) in POINTS:
			r = 14.0
		_disc(at, r, col.darkened(0.25))
	# Run-off out to the barriers.
	for i in t.n:
		var s := i * t.step
		for side in 2:
			var sign := 1.0 if side == 0 else -1.0
			var kind := t.runoff_kind(s, side)
			var col := Color("4f7a3f")
			match kind:
				TrackPlan.Runoff.GRAVEL, TrackPlan.Runoff.SAND:
					col = Color("cdb98a")
				TrackPlan.Runoff.TARMAC, TrackPlan.Runoff.WALL:
					col = Color("6d6d72")
			var off := t.barrier_off(s, side)
			_seg(t.world(s, sign * off * 0.5), t.world(s + t.step, sign * off * 0.5), off * 0.5, col)
	# Barriers.
	for i in t.n:
		var s := i * t.step
		for side in 2:
			var sign := 1.0 if side == 0 else -1.0
			_seg(t.world(s, sign * t.barrier_off(s, side)), t.world(s + t.step, sign * t.barrier_off(s + t.step, side)), 0.0, Color("b02020"))
	# The pit lane.
	if not t.pit.is_empty():
		var side := float(t.pit.side)
		var s := float(t.pit.entry)
		while s < float(t.pit.exit):
			var lat := float(t.pit.lane_lat) * side
			var into := clampf((s - float(t.pit.entry)) / 110.0, 0.0, 1.0)
			var out := clampf((float(t.pit.exit) - s) / 90.0, 0.0, 1.0)
			lat = lerpf(t.value_at(t.half, s) * side, lat, minf(into, out))
			_seg(t.world(s, lat), t.world(s + 2.0, lat), 3.5, Color("4a6fb0"))
			s += 2.0
	# The track in bands of height, lowest first, so the upper road of a
	# crossover is drawn over the lower one; shaded by height.
	var lo_y := t.bounds.position.y
	var hi_y := t.bounds.end.y
	var bands := {}
	for i in t.n:
		var b := int(floorf((t.pos[i].y - lo_y) / 4.0))
		if not bands.has(b):
			bands[b] = []
		bands[b].append(i)
	var keys: Array = bands.keys()
	keys.sort()
	for b in keys:
		for i in bands[b]:
			var s := int(i) * t.step
			_seg(t.world(s, 0.0), t.world(s + t.step * 1.5, 0.0), t.value_at(t.half, s) + 1.0, Color("f0f0f0"))
		for i in bands[b]:
			var s := int(i) * t.step
			var f := 0.5 if hi_y - lo_y < 1.0 else (t.pos[i].y - lo_y) / (hi_y - lo_y)
			var col := Color("3c3c44").lerp(Color("a8a8b8"), f)
			var feat := t.feature_at(s)
			if feat == "tunnel":
				col = Color("1a1a1a")
			elif feat == "bridge":
				col = col.lerp(Color("5a8fd0"), 0.45)
			elif feat == "over":
				col = col.lerp(Color("d08030"), 0.4)
			_seg(t.world(s, 0.0), t.world(s + t.step * 1.5, 0.0), t.value_at(t.half, s) - 0.6, col)
	# Kerbs.
	for i in t.n:
		var s := i * t.step
		for side in 2:
			if t.has_kerb(s, side):
				var sign := 1.0 if side == 0 else -1.0
				var lat := sign * (t.value_at(t.half, s) + Track.KERB_WIDTH * 0.5)
				_seg(t.world(s, lat), t.world(s + t.step, lat), 0.8, Color("e03030") if i % 4 < 2 else Color.WHITE)
	# The racing line.
	for i in range(0, t.n, 2):
		var s := i * t.step
		_seg(t.line_point(s), t.line_point(s + t.step), 0.0, Color("e8d040"))
	# DRS zones.
	for z in t.drs:
		var s := float(z.start)
		while t.delta_s(s, float(z.end)) > 0.0:
			_seg(t.world(s, 0.0), t.world(s + 2.0, 0.0), 0.0, Color("30d0ff"))
			s += 2.0
	# The start line and the direction of travel.
	var hw := t.value_at(t.half, 0.0)
	_seg(t.world(0.0, hw + 2.0), t.world(0.0, -hw - 2.0), 1.5, Color("ffffff"))
	_seg(t.world(1.5, hw), t.world(1.5, -hw), 0.0, Color("000000"))
	var a := t.world(30.0, 0.0)
	_seg(a, t.world(10.0, 9.0), 1.0, Color("ff3030"))
	_seg(a, t.world(10.0, -9.0), 1.0, Color("ff3030"))
	# Corner numbers, outside each apex.
	for c in t.corners:
		var s := float(c.apex)
		var side := -float(c.dir)
		var off := t.barrier_off(s, 0 if side > 0.0 else 1) + 26.0 / maxf(_scale, 0.3)
		_number(t.world(s, side * off), int(c.number))
	return _img


func _px(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _origin) * _scale


## A thick line between two world points, `r` metres either side.
func _seg(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var pa := _px(a)
	var pb := _px(b)
	var rp := maxf(r * _scale, 0.5)
	var steps := maxi(1, int(ceil(pa.distance_to(pb) / maxf(rp * 0.7, 0.5))))
	for k in steps + 1:
		_disc_px(pa.lerp(pb, float(k) / steps), rp, col)


func _disc(p: Vector2, r: float, col: Color) -> void:
	_disc_px((p - _origin) * _scale, r * _scale, col)


func _disc_px(c: Vector2, r: float, col: Color) -> void:
	var x0 := maxi(0, int(floorf(c.x - r)))
	var x1 := mini(_img.get_width() - 1, int(ceilf(c.x + r)))
	var y0 := maxi(0, int(floorf(c.y - r)))
	var y1 := mini(_img.get_height() - 1, int(ceilf(c.y + r)))
	var r2 := maxf(r * r, 0.5)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if (x + 0.5 - c.x) * (x + 0.5 - c.x) + (y + 0.5 - c.y) * (y + 0.5 - c.y) <= r2:
				_img.set_pixel(x, y, col)


## A corner number in 3 by 5 pixel digits, three times the size.
func _number(at: Vector3, num: int) -> void:
	var text := str(num)
	var px := _px(at)
	var cell := 3
	var w := text.length() * 4 * cell
	var x0 := int(px.x) - w / 2
	var y0 := int(px.y) - 5 * cell / 2
	_img.fill_rect(Rect2i(x0 - 2, y0 - 2, w + 2, 5 * cell + 4), Color("000000"))
	for k in text.length():
		var pattern: String = DIGITS[int(text[k])]
		for row in 5:
			for col in 3:
				if pattern[row * 3 + col] == "1":
					_img.fill_rect(Rect2i(x0 + k * 4 * cell + col * cell, y0 + row * cell, cell, cell), Color("ffe040"))
