class_name MeshBuf
extends RefCounted
## Collects triangles with colours (and optionally UVs) and turns them into
## one surface of an ArrayMesh. The world's road, run-off, walls and terrain
## are built from these, a chunk at a time.
##
## Colours are stored as sRGB; the alpha channel carries how wet the surface
## looks in the rain (1 for tarmac, low for grass).

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var idx := PackedInt32Array()
var with_uv := false


func is_empty() -> bool:
	return idx.is_empty()


## A triangle facing roughly `want` (flipped if needed), flat shaded.
func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, want := Vector3.UP) -> void:
	var nn := (b - a).cross(cc - a)
	# Godot's front faces wind clockwise, so their normal is -(b-a)x(c-a).
	if nn.dot(want) > 0.0:
		var t := b
		b = cc
		cc = t
		nn = -nn
	var fn := -nn.normalized() if nn.length_squared() > 1e-12 else want
	var base := v.size()
	v.append(a)
	v.append(b)
	v.append(cc)
	for k in 3:
		n.append(fn)
		c.append(col)
		if with_uv:
			uv.append(Vector2.ZERO)
	idx.append(base)
	idx.append(base + 1)
	idx.append(base + 2)


## A quad a-b-c-d (in order round its edge) facing roughly `want`, with
## one normal for the whole quad.
func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, want := Vector3.UP) -> void:
	var nn := (cc - a).cross(d - b)
	if nn.length_squared() < 1e-12:
		nn = (b - a).cross(cc - a)
	var fn := nn.normalized()
	if fn.dot(want) < 0.0:
		fn = -fn
	var base := v.size()
	v.append(a)
	v.append(b)
	v.append(cc)
	v.append(d)
	for k in 4:
		n.append(fn)
		c.append(col)
		if with_uv:
			uv.append(Vector2.ZERO)
	# Wind each triangle clockwise as seen from the side fn points to.
	if (b - a).cross(cc - a).dot(fn) > 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A quad with smooth normals given per corner (for terrain and road).
func quad_smooth(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, ca: Color, cb: Color, ccol: Color, cd: Color) -> void:
	var base := v.size()
	v.append(a)
	v.append(b)
	v.append(cc)
	v.append(d)
	n.append(na)
	n.append(nb)
	n.append(nc)
	n.append(nd)
	c.append(ca)
	c.append(cb)
	c.append(ccol)
	c.append(cd)
	if with_uv:
		for k in 4:
			uv.append(Vector2.ZERO)
	var up := na + nb + nc + nd
	if (b - a).cross(cc - a).dot(up) > 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A box between two points along a line (a wall, a slab): `a` and `b` are
## the bottom centre of each end, `side` points across it, `w` is its
## thickness and `h` its height. Ends are left open unless `caps`.
func box(a: Vector3, b: Vector3, side: Vector3, w: float, h: float, col: Color, top_col: Color, caps := false) -> void:
	var s := side.normalized() * w * 0.5
	var up := Vector3.UP * h
	var a0 := a - s
	var a1 := a + s
	var b0 := b - s
	var b1 := b + s
	quad(a0, b0, b0 + up, a0 + up, col, -s)
	quad(a1, a1 + up, b1 + up, b1, col, s)
	quad(a0 + up, b0 + up, b1 + up, a1 + up, top_col, Vector3.UP)
	if caps:
		var along := (a - b).normalized()
		quad(a0, a0 + up, a1 + up, a1, col, along)
		quad(b0, b1, b1 + up, b0 + up, col, -along)


## Appends another mesh's surface arrays moved by `xf`.
func append_arrays(arrs: Array, xf: Transform3D, col_override := Color(0, 0, 0, 0)) -> void:
	var vv: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var nv = arrs[Mesh.ARRAY_NORMAL]
	var cv = arrs[Mesh.ARRAY_COLOR]
	var iv = arrs[Mesh.ARRAY_INDEX]
	var base := v.size()
	var basis := xf.basis.inverse().transposed()
	for k in vv.size():
		v.append(xf * vv[k])
		n.append((basis * nv[k]).normalized() if nv != null else Vector3.UP)
		if col_override.a > 0.0 or cv == null:
			c.append(col_override)
		else:
			c.append(cv[k])
		if with_uv:
			uv.append(Vector2.ZERO)
	var flip := xf.basis.determinant() < 0.0
	if iv == null:
		for k in range(0, vv.size(), 3):
			if flip:
				idx.append_array([base + k, base + k + 2, base + k + 1])
			else:
				idx.append_array([base + k, base + k + 1, base + k + 2])
	else:
		var ii: PackedInt32Array = iv
		for k in range(0, ii.size(), 3):
			if flip:
				idx.append_array([base + ii[k], base + ii[k + 2], base + ii[k + 1]])
			else:
				idx.append_array([base + ii[k], base + ii[k + 1], base + ii[k + 2]])


## Adds this buffer as a surface of `mesh` (made if null) and returns it.
func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if is_empty():
		return mesh
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = v
	arrs[Mesh.ARRAY_NORMAL] = n
	arrs[Mesh.ARRAY_COLOR] = c
	if with_uv:
		arrs[Mesh.ARRAY_TEX_UV] = uv
	arrs[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
