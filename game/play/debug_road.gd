class_name DebugRoad
extends Node3D
## A plain stand-in for the track scenery: the road, kerbs and run-off as
## flat ribbons and a light. Used when the full TrackView isn't available
## (tests, tools).


static func create(track: Track) -> DebugRoad:
	var d := DebugRoad.new()
	d._build(track)
	return d


func _build(t: Track) -> void:
	_ribbon(t, func(i): return -t.half[i], func(i): return t.half[i], 0.02, Color(0.36, 0.37, 0.4))
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		_ribbon(t, func(i): return sgn * t.half[i] if sgn < 0 else t.half[i] - 0.25, func(i): return sgn * t.half[i] + 0.25 if sgn < 0 else t.half[i], 0.03, Color(0.95, 0.95, 0.95))
		_ribbon(t, func(i): return minf(sgn * t.half[i], sgn * (t.half[i] + t.run_width[side][i])), func(i): return maxf(sgn * t.half[i], sgn * (t.half[i] + t.run_width[side][i])), 0.0, Color(0.42, 0.62, 0.3))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(t.bounds.size.x + 2000.0, t.bounds.size.z + 2000.0)
	ground.mesh = plane
	ground.position = t.bounds.get_center() - Vector3(0, t.bounds.size.y * 0.5 + 0.5, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.55, 0.27)
	ground.material_override = gm
	add_child(ground)


func _ribbon(t: Track, a: Callable, b: Callable, lift: float, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in t.n + 1:
		var k := i % t.n
		var s := k * t.step
		var p0 := t.world(s, float(a.call(k)), lift)
		var p1 := t.world(s, float(b.call(k)), lift)
		if i > 0:
			var k0 := (i - 1) % t.n
			var s0 := k0 * t.step
			var q0 := t.world(s0, float(a.call(k0)), lift)
			var q1 := t.world(s0, float(b.call(k0)), lift)
			st.set_normal(Vector3.UP)
			st.add_vertex(q0)
			st.add_vertex(p0)
			st.add_vertex(p1)
			st.add_vertex(q0)
			st.add_vertex(p1)
			st.add_vertex(q1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
