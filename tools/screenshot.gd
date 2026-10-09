extends Node
## Screenshots of a race for checking the look: starts a Quick Race (or Time
## Trial), lets it run, and saves PNGs from each camera.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 tools/screenshot.tscn -- out=/tmp/shots circuit=greenfield wait=14 \
##   [views=chase_near,cockpit] [split=1] [tt=1] [rain=1]
##
## Or every layout from every camera, the menus and the race screens, as
## JPEGs in folders with a README.md listing them:
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots [only=greenfield]

var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		_args[kv[0].trim_prefix("--")] = kv[1] if kv.size() > 1 else "1"
	# Stay alive when the race replaces the current scene.
	get_tree().current_scene = null
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGTheme.apply(get_tree().root, 22)
	if _args.has("all"):
		await _all(str(_args.all), str(_args.get("only", "")))
		return
	var out := str(_args.get("out", "/tmp/shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var circuit := str(_args.get("circuit", ""))
	if Circuits.info(circuit).is_empty():
		circuit = Circuits.ids()[0]
	if _args.has("menu"):
		# A menu screen: title (with page=...) or lobby.
		var menu := str(_args.menu)
		if menu == "lobby":
			Session.start_solo()
			LGScenes.change_scene("res://game/ui/lobby.tscn")
		else:
			LGSettings.set_value("player", "name", "Ken")
			LGScenes.change_scene("res://game/ui/title.tscn", func(n): n.set("open_page", str(_args.get("page", ""))))
		await get_tree().create_timer(float(_args.get("wait", "4"))).timeout
		get_viewport().get_texture().get_image().save_png("%s/menu_%s%s.png" % [out, menu, str(_args.get("page", ""))])
		get_tree().quit()
		return
	if _args.has("school"):
		RacingSchool.start(str(_args.school))
	elif _args.has("tt"):
		Session.start_time_trial(circuit)
	else:
		Session.start_solo()
		if _args.has("split"):
			Session.add_local_seat(0)
		var settings: Dictionary = Session.settings.duplicate()
		settings.circuit = circuit
		settings.laps = 3
		settings.qualifying = "none"
		settings.weather = "wet" if _args.has("rain") else "dry"
		Session.launch(Session.make_config(Session.local_people(), settings, "quick"))
	await get_tree().create_timer(0.5).timeout
	while LGScenes.is_busy():
		await get_tree().process_frame
	var scene := get_tree().current_scene as RaceScene
	print("race scene up: ", scene != null, " fps ", Engine.get_frames_per_second())
	# Slow software rendering mustn't slow the race: let physics catch up,
	# and let the AI drive the player's cars.
	Engine.max_physics_steps_per_frame = 120
	for p in scene.players:
		p.autopilot = true
	var wait := float(_args.get("wait", "12"))
	await get_tree().create_timer(wait).timeout
	var views := str(_args.get("views", "chase_near,chase_far,tcam,cockpit")).split(",")
	for v in views:
		for pv in scene.views:
			pv.camera.set_view(v)
		for i in 20:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%s.png" % [out, str(scene.config.get("circuit", circuit)) + str(_args.get("school", "")), v]
		img.save_png(path)
		print("saved ", path, " fps ", Engine.get_frames_per_second())
	get_tree().quit()


# --- Everything -----------------------------------------------------------

const RACE_VIEWS := ["chase_near", "tcam", "cockpit", "chase_far"]

var _lines: Array = []


func _all(dir: String, only: String) -> void:
	var root := dir if dir.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(dir)
	LGSettings.set_value("player", "name", "Ken")
	LGSettings.set_value("player", "team", 9)
	Engine.max_physics_steps_per_frame = 120
	_lines = ["# Screenshots", "", "Every layout of Race Day from each camera, the race screens and the menus, made with:", "",
		"    xvfb-run -a -s \"-screen 0 1280x720x24\" godot --path . --rendering-driver opengl3 --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots", ""]
	if only == "":
		await _menus(root)
	for id in Circuits.ids():
		if only != "" and not id.begins_with(only):
			continue
		await _layout(root, id)
	if only == "":
		await _extras(root)
		var f := FileAccess.open(root.path_join("README.md"), FileAccess.WRITE)
		f.store_string("\n".join(_lines) + "\n")
	get_tree().quit()


func _shot(root: String, folder: String, file: String, caption: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(root.path_join(folder))
	get_viewport().get_texture().get_image().save_jpg(root.path_join(folder).path_join(file + ".jpg"), 0.85)
	_lines.append("**%s**" % caption)
	_lines.append("")
	_lines.append("![%s](%s/%s.jpg)" % [caption, folder, file])
	_lines.append("")
	print("Saved ", folder, "/", file)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _menus(root: String) -> void:
	_lines.append_array(["## Menus", ""])
	Session.leave()
	for page in ["", "championship", "career", "time_trial", "school"]:
		LGScenes.change_scene("res://game/ui/title.tscn", func(n): n.set("open_page", page))
		await LGScenes.scene_changed
		await _wait(2.5)
		await _shot(root, "menus", "title" + ("-" + page if page != "" else ""), "Title" + (": " + page.capitalize() if page != "" else ""))
	Session.start_solo()
	LGScenes.change_scene("res://game/ui/lobby.tscn")
	await LGScenes.scene_changed
	await _wait(2.5)
	await _shot(root, "menus", "lobby", "Quick Race lobby")


## A quick race on a layout with the AI driving the player's car.
func _race(id: String, extra := {}) -> RaceScene:
	Session.start_solo()
	if extra.has("split"):
		Session.add_local_seat(0)
	var settings: Dictionary = Session.settings.duplicate()
	settings.circuit = id
	settings.laps = 3
	settings.qualifying = "none"
	settings.weather = str(extra.get("weather", "dry"))
	settings.grid = 20
	Session.launch(Session.make_config(Session.local_people(), settings, "quick"))
	var scene := await _race_scene()
	for p in scene.players:
		p.autopilot = true
	return scene


## Waits for the race scene to be up, past any other scene change.
func _race_scene() -> RaceScene:
	await get_tree().process_frame
	while LGScenes.is_busy() or not get_tree().current_scene is RaceScene:
		await get_tree().process_frame
	return get_tree().current_scene as RaceScene


func _layout(root: String, id: String) -> void:
	var info := Circuits.info(id)
	var folder := str(info.get("circuit", id))
	var name := str(info.get("name", id))
	_lines.append_array(["## %s" % name, ""])
	var scene := await _race(id)
	var pv: PlayerView = scene.views[0]
	# The grid under the lights.
	while scene.race.phase != Race.Phase.LIGHTS or scene.race.lights < 4:
		await get_tree().process_frame
	pv.camera.set_view("chase_far")
	await _wait(0.4)
	await _shot(root, folder, id + "-start", "%s: the start" % name)
	# Racing in the pack.
	while scene.race.phase != Race.Phase.RACING or scene.race.time < 14.0:
		await get_tree().process_frame
	for v in RACE_VIEWS:
		pv.camera.set_view(v)
		await _wait(0.5)
		await _shot(root, folder, id + "-" + v, "%s: %s" % [name, GameConfig.CAMERA_NAMES[v]])
	# Television: from beside the road ahead, the car coming past.
	var e: Race.Entry = pv.driver.entry
	var t := scene.track
	var s := t.wrap_s(e.sim.spot.s + 70.0)
	var side := -1.0 if t.value_at(t.line_off, s) > 0.0 else 1.0
	var spot := t.world(s, side * (t.value_at(t.half, s) + 7.0)) + Vector3.UP * 3.0
	pv.camera.set_view("free")
	pv.hud.visible = false
	for k in 30:
		pv.camera.global_transform = Transform3D(Basis.looking_at(e.sim.pos + Vector3.UP - spot, Vector3.UP), spot)
		await get_tree().process_frame
	await _shot(root, folder, id + "-tv", "%s: from the trackside" % name)
	# The whole layout from above.
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	var y := 0.0
	var n := int(t.length / 20.0)
	for k in n:
		var p := t.world(k * 20.0, 0.0)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
		y += p.y / n
	var centre := (lo + hi) * 0.5 + Vector3.UP * y
	var extent := maxf(hi.x - lo.x, (hi.z - lo.z) * 1.6)
	var eye := centre + Vector3(0, extent * 0.75, extent * 0.55)
	pv.camera.global_transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	pv.camera.fov = 50.0
	await _wait(1.0)
	await _shot(root, folder, id + "-above", "%s: the layout from above" % name)
	pv.hud.visible = true


## Race screens: rain, split screen, the pause menu, results, Time Trial and
## a Racing School test.
func _extras(root: String) -> void:
	_lines.append_array(["## Race screens", ""])
	var id := "greenfield" if not Circuits.info("greenfield").is_empty() else str(Circuits.ids()[0])
	var scene := await _race(id, {"weather": "wet"})
	while scene.race.phase != Race.Phase.RACING or scene.race.time < 12.0:
		await get_tree().process_frame
	await _shot(root, "race", "rain", "Racing in the rain")
	scene.toggle_pause()
	await _wait(0.6)
	await _shot(root, "race", "pause", "The pause menu")
	scene.toggle_pause()
	scene._show_results(scene.race.results(), false)
	await _wait(0.6)
	await _shot(root, "race", "results", "Race results")
	scene = await _race(id, {"split": true})
	while scene.race.phase != Race.Phase.RACING or scene.race.time < 10.0:
		await get_tree().process_frame
	await _shot(root, "race", "split", "Split screen")
	Session.start_time_trial(id)
	scene = await _race_scene()
	for p in scene.players:
		p.autopilot = true
	await _wait(8.0)
	await _shot(root, "race", "time-trial", "Time Trial")
	RacingSchool.start("brake")
	scene = await _race_scene()
	for p in scene.players:
		p.autopilot = true
	await _wait(5.0)
	await _shot(root, "race", "school", "Racing School: braking for a hairpin")
	while not scene.school.done:
		await get_tree().process_frame
	await _wait(1.0)
	await _shot(root, "race", "school-result", "Racing School: a medal")
