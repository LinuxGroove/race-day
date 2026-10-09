class_name PropKit
extends RefCounted
## Kenney models flattened into single meshes, for MultiMeshes and for
## merging into the ground. Flat-coloured materials (the Racing Kit, Nature
## Kit) become vertex colours on one surface; textured ones (colormap kits)
## keep their own material, so most models draw in one call.
##
## Models are recentred: x and z on the middle of the model, y on its base.
## Racing Kit v1 models sit off their origin, so this matters there.

const V1 := "res://assets/kenney/racing-kit/"
const V2 := "res://assets/kenney/racing-kit-v2/"
const NATURE := "res://assets/kenney/nature-kit/"
const CITY := "res://assets/kenney/city-commercial/"
const SUBURB := "res://assets/kenney/city-suburban/"
const INDUSTRY := "res://assets/kenney/city-industrial/"
const ROADS := "res://assets/kenney/city-roads/"
const WATERCRAFT := "res://assets/kenney/watercraft/"
const SPACE := "res://assets/kenney/space-kit/"
const TOWN := "res://assets/kenney/fantasy-town/"
const CARS := "res://assets/kenney/car-kit/"

## How much of the flat kits' lost colour to restore (see `deepen`).
const DEEPEN := 0.6

static var _cache := {}
static var _raw := {}


## A model as one mesh, recentred (or as authored with `centre` false), its
## flat colours multiplied by `tint`.
static func mesh(path: String, centre := true, tint := Color.WHITE) -> ArrayMesh:
	var key := path + ("#c" if centre else "#o") + ("" if tint == Color.WHITE else tint.to_html())
	if _cache.has(key):
		return _cache[key]
	var parts := _flatten(path)
	var aabb := _parts_aabb(parts)
	var shift := Vector3.ZERO
	if centre:
		shift = -Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5)
	var xf := Transform3D(Basis(), shift)
	var m := ArrayMesh.new()
	m.resource_name = path.get_file().get_basename()
	var colour := MeshBuf.new()
	var textured := {}
	for p in parts:
		var mat: Material = p.mat
		if p.tex:
			if not textured.has(mat):
				var tb := MeshBuf.new()
				tb.with_uv = true
				textured[mat] = tb
			_append_uv(textured[mat], p.arrays, p.xf, xf)
		else:
			colour.append_arrays(p.arrays, xf * p.xf, p.col * tint)
	if not colour.is_empty():
		colour.commit(m, WorldLook.props())
	for mat in textured:
		textured[mat].commit(m, mat)
	_cache[key] = m
	return m


## The size of a model (its bounding box), in its own units.
static func size(path: String) -> Vector3:
	return mesh(path).get_aabb().size


## The flat-coloured parts' colours by material name, for tiles that are
## recoloured to match generated ground.
static func parts(path: String) -> Array:
	return _flatten(path)


static func _flatten(path: String) -> Array:
	if _raw.has(path):
		return _raw[path]
	var out := []
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("No model " + path)
		_raw[path] = out
		return out
	var root := scene.instantiate()
	_walk(root, Transform3D(), out, path.begins_with(V1))
	root.free()
	_raw[path] = out
	return out


static func _walk(node: Node, xf: Transform3D, out: Array, deep: bool) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var m := mi.mesh
		for si in m.get_surface_count():
			var mat := mi.get_surface_override_material(si)
			if mat == null:
				mat = m.surface_get_material(si)
			var col := Color.WHITE
			var tex := false
			var name := ""
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				col = bm.albedo_color
				tex = bm.albedo_texture != null
				name = bm.resource_name
			out.append({"arrays": m.surface_get_arrays(si), "xf": t, "mat": mat, "col": deepen(col) if deep else Color(col.r, col.g, col.b, 1.0), "tex": tex, "name": name})
	for ch in node.get_children():
		_walk(ch, t, out, deep)


## The Racing Kit (v1) stores its sRGB colours as linear factors, so
## they import paler than drawn; this brings most of the colour back.
static func deepen(col: Color) -> Color:
	var d := col.lerp(col.srgb_to_linear(), DEEPEN)
	return Color(d.r, d.g, d.b, 1.0)


static func _parts_aabb(parts: Array) -> AABB:
	var lo := Vector3.ONE * 1e9
	var hi := -lo
	for p in parts:
		var vv: PackedVector3Array = p.arrays[Mesh.ARRAY_VERTEX]
		var pxf: Transform3D = p.xf
		for q in vv:
			var w := pxf * q
			lo = lo.min(w)
			hi = hi.max(w)
	if lo.x > hi.x:
		return AABB()
	return AABB(lo, hi - lo)


static func _append_uv(buf: MeshBuf, arrs: Array, pxf: Transform3D, xf: Transform3D) -> void:
	var start := buf.v.size()
	buf.append_arrays(arrs, xf * pxf, Color.WHITE)
	var uvs = arrs[Mesh.ARRAY_TEX_UV]
	if uvs != null:
		var u: PackedVector2Array = uvs
		for k in u.size():
			buf.uv[start + k] = u[k]


# --- Placing many copies -------------------------------------------------

## Collects copies of meshes and builds them as MultiMeshes, split into
## square cells so each draws only when near a camera.
class Scatter:
	var cell := 400.0
	## {mesh: {Vector2i cell: [Transform3D]}}
	var _items := {}
	var _opts := {}

	func _init(cell_size := 400.0) -> void:
		cell = cell_size

	## Adds a copy. `vis` is how far away it still draws (0 for always),
	## `shadow` whether it casts shadows.
	func add(m: Mesh, xf: Transform3D, vis := 0.0, shadow := true) -> void:
		if m == null:
			return
		if not _items.has(m):
			_items[m] = {}
			_opts[m] = [vis, shadow]
		var k := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
		if not _items[m].has(k):
			_items[m][k] = []
		_items[m][k].append(xf)

	func count() -> int:
		var c := 0
		for m in _items:
			for k in _items[m]:
				c += _items[m][k].size()
		return c

	## Builds the MultiMeshInstance3Ds under `parent`.
	func build(parent: Node3D) -> void:
		for m in _items:
			var vis: float = _opts[m][0]
			var shadow: bool = _opts[m][1]
			for k in _items[m]:
				var list: Array = _items[m][k]
				# The instance sits in the middle of its copies, so distance
				# checks (visibility ranges) measure from there.
				var mid := Vector3.ZERO
				for xf in list:
					mid += (xf as Transform3D).origin
				mid /= list.size()
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = m
				mm.instance_count = list.size()
				for i in list.size():
					var xf: Transform3D = list[i]
					xf.origin -= mid
					mm.set_instance_transform(i, xf)
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.position = mid
				if vis > 0.0:
					mmi.visibility_range_end = vis
					mmi.visibility_range_end_margin = vis * 0.1
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(mmi)
