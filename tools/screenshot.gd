extends Node
## Screenshots of a race for checking the look: starts a Quick Race (or Time
## Trial), lets it run, and saves PNGs from each camera.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 tools/screenshot.tscn -- out=/tmp/shots circuit=greenfield wait=14 \
##   [views=chase_near,cockpit] [split=1] [tt=1] [rain=1]

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
