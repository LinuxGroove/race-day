class_name TrackView
extends Node3D
## Everything you see of one layout: the road, kerbs and run-off the
## simulation drives on, barriers, the pits and start gantry, grandstands
## and camera towers, the land to the horizon and the theme's scenery.
## Build it once per layout with `create` and add it to the scene; pair it
## with an `Atmosphere` for the sky, the time of day and rain.
##
## `detail` (0 low, 1 medium, 2 high) thins out scenery and props for slower
## machines and split screen.

var track: Track
var info := {}
var detail := 1
var roads: RoadBuilder
var terrain: Terrain
## How long the build took (ms) and what it made, for checking performance.
var stats := {}
## Ground that buildings already stand on ([Rect2] in x/z), so scenery
## keeps clear.
var taken: Array = []

var _cameras: Array = []
## Grandstands, one point per row (middle, at crowd height), for crowd sound.
var grandstands: Array = []
var _lamps: Array = []
var _start: StartLights


## Builds the view of `track` with the circuit's `info` (Circuits.info: its
## theme and time of day).
static func create(p_track: Track, p_info: Dictionary, p_detail := 1) -> TrackView:
	var v := TrackView.new()
	v.name = "TrackView"
	v.track = p_track
	v.info = p_info
	v.detail = clampi(p_detail, 0, 2)
	v._build()
	return v


## The start lights: `lit` red lights (0 to 5); `out` puts them all out.
func set_lights(lit: int, out: bool) -> void:
	if _start:
		_start.set_lights(lit, out)


## Where the TV cameras stand (on the camera towers), for replays.
func tv_cameras() -> Array:
	return _cameras.duplicate()


## Light posts along the track (lamp positions), for night lighting.
func lamp_posts() -> Array:
	return _lamps


## Lamps on light posts, windows and screens glow by night (0 off to 1).
func set_night_glow(f: float) -> void:
	lamp_material().emission_energy_multiplier = lerpf(0.0, 4.0, f)
	window_material().emission_energy_multiplier = lerpf(0.0, 1.6, f)


## The shared material of lamp heads (bright at night, plain by day).
static func lamp_material() -> StandardMaterial3D:
	return WorldLook.glow(Color("fff4d6"), 0.0)


## The shared material of windows: glass by day, lit at night.
static func window_material() -> StandardMaterial3D:
	if _windows == null:
		_windows = StandardMaterial3D.new()
		_windows.albedo_color = Color("7f97bd")
		_windows.roughness = 0.15
		_windows.metallic = 0.35
		_windows.emission_enabled = true
		_windows.emission = Color("ffd98a")
		_windows.emission_energy_multiplier = 0.0
	return _windows


static var _windows: StandardMaterial3D


## The ground height anywhere (track, run-off or land).
func ground_height(x: float, z: float) -> float:
	return terrain.height(x, z)


func theme() -> String:
	return str(info.get("theme", "parkland"))


func is_night() -> bool:
	return str(info.get("time", "day")) in ["night", "dusk_to_night"]


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	var tiles := ProvingGround.tiles() if theme() == "proving" else []
	roads = RoadBuilder.new(track, not tiles.is_empty())
	terrain = Terrain.new(track, roads, theme())
	var scenery := Scenery.new(self)
	scenery.shape_land()
	terrain.build()
	var t1 := Time.get_ticks_msec()
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var meshes := roads.build(terrain)
	if not tiles.is_empty():
		meshes = TileLayer.merge(self, tiles, meshes)
	for m in meshes:
		if m != null:
			_add_mesh(ground, m, false)
	var t2 := Time.get_ticks_msec()
	for m in terrain.meshes(detail):
		_add_mesh(ground, m, false)
	var t3 := Time.get_ticks_msec()
	var side := Trackside.new(self)
	side.build()
	_cameras = side.cameras
	_lamps = side.lamps
	_start = side.start_lights
	var t4 := Time.get_ticks_msec()
	Structures.new(self).build()
	scenery.build()
	var t5 := Time.get_ticks_msec()
	stats = {
		"land_ms": t1 - t0, "road_ms": t2 - t1, "terrain_ms": t3 - t2,
		"trackside_ms": t4 - t3, "scenery_ms": t5 - t4, "total_ms": t5 - t0,
	}


func _add_mesh(parent: Node3D, m: Mesh, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Counts nodes, mesh instances, MultiMesh copies and surfaces (a rough
## draw call count when everything is in view).
func count() -> Dictionary:
	var c := {"nodes": 0, "meshes": 0, "multimeshes": 0, "copies": 0, "surfaces": 0, "lights": 0}
	_count(self, c)
	return c


func _count(node: Node, c: Dictionary) -> void:
	c.nodes += 1
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		c.meshes += 1
		c.surfaces += (node as MeshInstance3D).mesh.get_surface_count()
	elif node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		c.multimeshes += 1
		c.copies += mm.instance_count
		c.surfaces += mm.mesh.get_surface_count()
	elif node is Light3D:
		c.lights += 1
	for ch in node.get_children():
		_count(ch, c)
