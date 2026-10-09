class_name BrakingLine
extends MeshInstance3D
## The racing line drawn on the road ahead of one player's car: green where
## the car can go faster, amber where it's about right, red where it must
## brake. "corners" shows it only from the braking points through the
## corners; "full" shows it all the way round. Only that player's camera
## sees it (its own render layer).

const AHEAD := 260.0
const STEP := 3.0
const WIDTH := 0.55

var driver: PlayerDriver
var mode := "corners"
var _mesh := ImmediateMesh.new()
var _profile := PackedFloat32Array()


func setup(p_driver: PlayerDriver, layer: int) -> void:
	driver = p_driver
	mesh = _mesh
	layers = 1 << layer
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	_profile = driver.race.speeds_for(driver.entry.team)


func _process(_dt: float) -> void:
	_mesh.clear_surfaces()
	if driver == null:
		return
	mode = driver.line_mode
	if mode == "off" or driver.entry.sim.spot.in_pit:
		return
	var t := driver.race.track
	var sim := driver.entry.sim
	var v := absf(sim.forward_speed())
	var s0 := sim.spot.s + 4.0
	var d := 0.0
	var vis_prev := false
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var have := false
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color()
	while d < AHEAD:
		var s := t.wrap_s(s0 + d)
		var target := t.value_at(_profile, s) * 0.97
		# What the car would be doing here if it braked now: the speed it
		# could still have at this point.
		var reach := sqrt(maxf(0.0, v * v - 2.0 * 10.0 * d))
		var c: Color
		var show := mode == "full"
		if reach > target + 4.0:
			c = Color(0.95, 0.18, 0.12, 0.75)
			show = true
		elif reach > target - 3.0:
			c = Color(1.0, 0.75, 0.1, 0.7)
			show = true
		else:
			c = Color(0.25, 0.9, 0.35, 0.55)
			if absf(t.value_at(t.line_curv, s)) > 1.0 / 500.0:
				show = true
		var lat := t.value_at(t.line_off, s)
		var centre := t.world(s, lat, 0.07)
		var nrm := t.normal_at(s)
		var off := Vector3(nrm.x, 0, nrm.y) * WIDTH * 0.5
		var l := centre + off
		var r := centre - off
		if have and show and vis_prev:
			_mesh.surface_set_color(prev_c)
			_mesh.surface_add_vertex(prev_l)
			_mesh.surface_add_vertex(prev_r)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(l)
			_mesh.surface_set_color(prev_c)
			_mesh.surface_add_vertex(prev_r)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(r)
			_mesh.surface_add_vertex(l)
		prev_l = l
		prev_r = r
		prev_c = c
		have = true
		vis_prev = show
		d += STEP
	# An ImmediateMesh surface needs at least one triangle.
	_mesh.surface_set_color(Color(0, 0, 0, 0))
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_end()
