extends SceneTree
## Builds a layout's world and saves screenshots from a few cameras, for
## checking the look without playing (needs a renderer, so run under xvfb):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 -s tools/world_shot.gd -- --layout=gp --out=/tmp/shots
## Options:
##   --layout=ID     a Circuits id, or a test layout: gp, street, spiral, oval
##   --out=DIR       where the PNGs go (default /tmp/world_shots)
##   --theme=NAME --time=NAME   override the layout's scenery or time of day
##   --detail=0|1|2  scenery detail (default 1)
##   --shots=a,b     any of grid, corner, chase, bird, pit, feature, landmarks,
##                   night, rain (default all but landmarks)
##   --cars          puts a few cars on the grid for scale

const Demos := preload("res://tools/world_demos.gd")

var opts := {}
var view: TrackView
var atmo: Atmosphere
var cam: Camera3D
var track: Track
var out_dir := "/tmp/world_shots"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a).trim_prefix("--")
		if "=" in s:
			opts[s.get_slice("=", 0)] = s.get_slice("=", 1)
		else:
			opts[s] = true
	out_dir = str(opts.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var id := str(opts.get("layout", "gp"))
	var info: Dictionary
	if id in Demos.IDS:
		info = Demos.info(id)
		track = Track.build(Demos.plan(id), info.id, info.name)
	else:
		info = Circuits.info(id)
		if info.is_empty():
			printerr("No layout ", id)
			quit(1)
			return
		track = Circuits.track(id)
	info = info.duplicate()
	if opts.has("theme"):
		info.theme = opts.theme
	if opts.has("time"):
		info.time = opts.time
	print("Layout %s: %.0f m, %d corners, theme %s, time %s" % [id, track.length, track.corners.size(), info.theme, info.time])
	var t0 := Time.get_ticks_msec()
	view = TrackView.create(track, info, int(opts.get("detail", 1)))
	var t1 := Time.get_ticks_msec()
	root.add_child(view)
	atmo = Atmosphere.create(info, view)
	root.add_child(atmo)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 12000.0
	root.add_child(cam)
	atmo.follow(cam)
	if opts.has("cars"):
		_cars()
	print("Built in %d ms: %s" % [t1 - t0, view.stats])
	print("Counts: %s" % view.count())
	var shots := str(opts.get("shots", "grid,corner,chase,bird,pit,feature,night,rain")).split(",")
	for shot in shots:
		await _shot(shot)
	await _frames(2)
	print("Rendered: %s" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	await _frames(4)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("Saved %s (%d draw calls, %d primitives)" % [path, draws, prims])


## Puts the camera at `from` looking at `to`.
func _look(from: Vector3, to: Vector3) -> void:
	cam.global_transform = Transform3D(Basis(), from).looking_at(to, Vector3.UP)


## A chase camera 6 m behind and 2 m above a car at s on the racing line.
func _chase(s: float) -> void:
	var p := track.line_point(s, 0.6)
	var t := track.tangent_at(s)
	var dir := Vector3(t.x, 0, t.y)
	_look(p - dir * 6.0 + Vector3.UP * 2.0, p + dir * 25.0 + Vector3.UP * 0.6)


func _shot(shot: String) -> void:
	atmo.set_rain(0.0)
	atmo.set_time(0.0)
	match shot:
		"grid":
			var back := track.wrap_s(-60.0)
			_look(track.world(back, 0.0, 3.0), track.world(40.0, 0.0, 1.5))
			await _save("grid")
			_look(track.world(track.wrap_s(-12.0), 0.0, 1.2), track.world(30.0, 0.0, 4.0))
			await _save("lights")
		"corner":
			if track.corners.is_empty():
				return
			var c: Dictionary = track.corners[0]
			_chase(track.wrap_s(float(c.start) - 30.0))
			await _save("corner")
		"chase":
			for k in mini(4, track.corners.size()):
				var c: Dictionary = track.corners[(k * 3 + 1) % track.corners.size()]
				_chase(track.wrap_s(float(c.start) - 40.0))
				await _save("chase_%d" % k)
		"bird":
			var b := track.bounds
			var c := b.get_center()
			var size := maxf(b.size.x, b.size.z)
			_look(c + Vector3(0, size * 0.75, size * 0.55), c)
			await _save("bird")
			var s0 := track.wrap_s(-80.0)
			var p := track.world(s0, 0.0)
			var n := track.normal_at(s0) * float(track.pit.get("side", -1))
			_look(p + Vector3(n.x, 0, n.y) * 120.0 + Vector3.UP * 70.0, track.world(40.0, 0.0))
			await _save("bird_start")
		"pit":
			if track.pit.is_empty():
				return
			var sg := float(track.pit.side)
			var s := float(track.pit.limit_in) + 10.0
			var lat := sg * float(track.pit.lane_lat)
			_look(track.world(track.wrap_s(s), lat, 2.5), track.world(track.wrap_s(s + 80.0), lat + sg * 4.0, 1.5))
			await _save("pit")
		"feature":
			var k := 0
			for f in track.features:
				_chase(track.wrap_s(float(f.from) - 50.0))
				await _save("feature_%d_%s" % [k, f.kind])
				var mid := track.wrap_s(float(f.from) + track.delta_s(float(f.from), float(f.to)) * 0.5)
				var p := track.world(mid, 0.0)
				var n := track.normal_at(mid)
				_look(p + Vector3(n.x, 0, n.y) * 70.0 + Vector3.UP * 25.0, p)
				await _save("feature_%d_%s_side" % [k, f.kind])
				k += 1
		"landmarks":
			var k := 0
			for l in track.landmarks:
				var s := float(l.s)
				var side := float(l.side)
				var p := track.world(s, -side * 10.0, 6.0)
				var to := track.world(s, side * (float(l.distance) + 20.0), 0.0)
				_look(p + (p - to).normalized() * 40.0 + Vector3.UP * 20.0, to)
				await _save("landmark_%d_%s" % [k, l.kind])
				k += 1
		"night":
			atmo.set_time(1.0)
			var night_info := view.info.duplicate()
			if str(night_info.time) == "day" or str(night_info.time) == "dusk":
				return
			var c: Dictionary = track.corners[0]
			_chase(track.wrap_s(float(c.start) - 30.0))
			await _save("night_corner")
			_look(track.world(track.wrap_s(-60.0), 0.0, 3.0), track.world(40.0, 0.0, 1.5))
			view.set_lights(5, false)
			await _save("night_grid")
			view.set_lights(0, true)
		"rain":
			atmo.set_rain(0.85)
			var c: Dictionary = track.corners[0]
			_chase(track.wrap_s(float(c.start) - 30.0))
			await _save("rain_corner")
			_look(track.world(track.wrap_s(-60.0), 0.0, 3.0), track.world(40.0, 0.0, 1.5))
			await _save("rain_grid")
			atmo.set_rain(0.0)


## A few cars on the grid, for judging scale.
func _cars() -> void:
	var models := ["res://assets/kenney/car-kit/race.glb", "res://assets/kenney/car-kit/race-future.glb"]
	for k in mini(8, track.grid.size()):
		var g: Dictionary = track.grid[k]
		var s := float(g.s)
		var p := track.world(s, float(g.lat))
		var car: Node3D = (load(models[k % 2]) as PackedScene).instantiate()
		car.scale = Vector3.ONE * 2.15
		root.add_child(car)
		car.global_position = p
		car.rotation.y = track.heading_at(s)
	var c: Dictionary = track.corners[0] if not track.corners.is_empty() else {"start": 100.0}
	var s2 := track.wrap_s(float(c.start) - 30.0)
	var car2: Node3D = (load(models[0]) as PackedScene).instantiate()
	car2.scale = Vector3.ONE * 2.15
	root.add_child(car2)
	car2.global_position = track.line_point(s2)
	car2.rotation.y = track.heading_at(s2)
