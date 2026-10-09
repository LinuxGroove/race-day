class_name PauseMenu
extends Control
## The pause menu: resume, restart, the assists and camera comfort settings,
## and leaving the race. Online and LAN races keep running underneath.

const BRAKING_LINE := [["off", "Off"], ["corners", "Corners only"], ["full", "Full"]]
const GEARS := [["auto", "Automatic"], ["manual", "Manual"]]
const SOFTNESS := [[0.6, "Very soft"], [0.8, "Soft"], [1.0, "Normal"], [1.3, "Tight"]]
const HEAD := [[0.0, "Still"], [0.3, "A little"], [0.7, "More"], [1.0, "Full"]]
const FOVS := [[60.0, "60"], [65.0, "65"], [70.0, "70"], [75.0, "75"], [80.0, "80"], [90.0, "90"]]
const PRESET_NAMES := [["low", "Low downforce"], ["balanced", "Balanced"], ["high", "High downforce"], ["custom", "Your own"]]
## The four setup sliders: key, name, [[value, label], ...], what it does.
const SETUP_ROWS := [
	["wing", "Wing level", [[0.1, "1 (least)"], [0.3, "2"], [0.5, "3"], [0.7, "4"], [0.9, "5 (most)"]],
		"More wing grips in the corners; less is faster on the straights."],
	["gear", "Gearing", [[0.15, "Long"], [0.35, "Longer"], [0.5, "Middle"], [0.65, "Shorter"], [0.85, "Short"]],
		"Short gears pull hard out of slow corners; long gears reach a higher top speed."],
	["balance", "Brake balance", [[0.54, "54% front"], [0.56, "56% front"], [0.58, "58% front"], [0.6, "60% front"], [0.62, "62% front"]],
		"More to the front is stable under braking but locks the fronts sooner."],
	["stiffness", "Suspension", [[0.1, "Soft"], [0.3, "Softer"], [0.5, "Middle"], [0.7, "Stiffer"], [0.9, "Stiff"]],
		"Stiff is sharp on smooth roads; soft rides the kerbs and bumps."],
]

var scene: RaceScene
var _col: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	center.add_child(_col)
	_main()


func _clear() -> void:
	for c in _col.get_children():
		c.queue_free()


func _main() -> void:
	_clear()
	_col.add_child(LGUi.label("Paused" if not Session.is_networked() else "Menu", "HeaderLarge"))
	_col.add_child(LGUi.button("Resume", close))
	if not Session.is_networked():
		_col.add_child(LGUi.button("Restart session", _restart))
	if scene.kind != Race.Kind.SCHOOL:
		_col.add_child(LGUi.button("Car setup", _setup))
	_col.add_child(LGUi.button("Assists", _assists))
	_col.add_child(LGUi.button("Camera and comfort", _camera))
	_col.add_child(LGUi.button("Sound and screen", _sound))
	_col.add_child(LGUi.button("How to play", _howto))
	_col.add_child(LGUi.button("Leave race", _leave))
	LGUi.focus_first(_col)


## The assists rows, shared with the title's settings.
static func assist_rows(col: Control, width := 520) -> void:
	col.add_child(LGCycler.make("Braking line", BRAKING_LINE, LGSettings.get_value("assists", "braking_line"), _set_value.bind("assists", "braking_line"), width))
	col.add_child(LGCycler.make("Braking help", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "braking_help"), _set_value.bind("assists", "braking_help"), width))
	col.add_child(LGCycler.make("Steering help", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "steering_help"), _set_value.bind("assists", "steering_help"), width))
	col.add_child(LGCycler.make("Anti-lock brakes", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "abs"), _set_value.bind("assists", "abs"), width))
	col.add_child(LGCycler.make("Traction control", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "tc"), _set_value.bind("assists", "tc"), width))
	col.add_child(LGCycler.make("Gears", GEARS, LGSettings.get_value("assists", "gears"), _set_value.bind("assists", "gears"), width))
	col.add_child(LGCycler.make("Pit lane assist", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "pit"), _set_value.bind("assists", "pit"), width))
	col.add_child(LGCycler.make("Rewind", SettingsPanel.ON_OFF, LGSettings.get_value("assists", "rewind"), _set_value.bind("assists", "rewind"), width))


## The camera comfort rows, shared with the title's settings.
static func camera_rows(col: Control, width := 520) -> void:
	col.add_child(LGCycler.make("Level horizon", SettingsPanel.ON_OFF, LGSettings.get_value("camera", "horizon_lock"), _set_value.bind("camera", "horizon_lock"), width))
	col.add_child(LGCycler.make("Head moves with g-forces", HEAD, LGSettings.get_value("camera", "g_head"), _set_value.bind("camera", "g_head"), width))
	col.add_child(LGCycler.make("Chase camera", SOFTNESS, LGSettings.get_value("camera", "chase_softness"), _set_value.bind("camera", "chase_softness"), width))
	col.add_child(LGCycler.make("Field of view", FOVS, LGSettings.get_value("camera", "fov"), _set_value.bind("camera", "fov"), width))
	col.add_child(LGCycler.make("Wider view at speed", SettingsPanel.ON_OFF, LGSettings.get_value("camera", "speed_fov"), _set_value.bind("camera", "speed_fov"), width))
	col.add_child(LGCycler.make("Camera shake", SettingsPanel.ON_OFF, LGSettings.get_value("camera", "shake"), _set_value.bind("camera", "shake"), width))
	col.add_child(LGCycler.make("Speed in", [["kmh", "km/h"], ["mph", "mph"]], LGSettings.get_value("hud", "units"), _set_value.bind("hud", "units"), width))
	col.add_child(LGCycler.make("Team radio", SettingsPanel.ON_OFF, LGSettings.get_value("hud", "radio"), _set_value.bind("hud", "radio"), width))


static func _set_value(value: Variant, section: String, key: String) -> void:
	LGSettings.set_value(section, key, value)


func _assists() -> void:
	_clear()
	_col.add_child(LGUi.label("Assists", "HeaderMedium"))
	assist_rows(_col)
	_col.add_child(LGUi.button("Back", _main))
	LGUi.focus_first(_col)


func _camera() -> void:
	_clear()
	_col.add_child(LGUi.label("Camera and comfort", "HeaderMedium"))
	camera_rows(_col)
	_col.add_child(LGUi.button("Back", _main))
	LGUi.focus_first(_col)


func _sound() -> void:
	_clear()
	_col.add_child(LGUi.label("Sound and screen", "HeaderMedium"))
	_col.add_child(SettingsPanel.new())
	_col.add_child(LGUi.button("Back", _main))
	LGUi.focus_first(_col)


func _setup() -> void:
	_clear()
	_col.add_child(LGUi.label("Car setup: %s" % str(scene.info.get("name", "")), "HeaderMedium"))
	var setup := Progress.setup_for(scene.track.id)
	var preset := "custom"
	for k in CarSpec.PRESETS:
		if CarSpec.PRESETS[k].hash() == setup.hash():
			preset = k
	_col.add_child(LGCycler.make("Start from", PRESET_NAMES, preset, _on_preset, 560))
	for row in SETUP_ROWS:
		var c := LGCycler.make(row[1], row[2], _nearest(row[2], float(setup.get(row[0], 0.5))), _on_setup.bind(str(row[0])), 560)
		c.tooltip_text = row[3]
		_col.add_child(c)
	var note := LGUi.label("The balanced setup is always quick. Change one thing at a time and try a lap." if scene.can_change_setup()
		else "The setup is locked during the race. Changes apply from the next session.", "HintLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	_col.add_child(note)
	_col.add_child(LGUi.button("Back", _main))
	LGUi.focus_first(_col)


static func _nearest(options: Array, v: float) -> float:
	var best: float = options[0][0]
	for o in options:
		if absf(float(o[0]) - v) < absf(best - v):
			best = o[0]
	return best


func _on_preset(key: Variant) -> void:
	if CarSpec.PRESETS.has(str(key)):
		scene.apply_setup(CarSpec.PRESETS[str(key)])
		_setup.call_deferred()


func _on_setup(value: Variant, key: String) -> void:
	var setup := Progress.setup_for(scene.track.id)
	setup[key] = value
	scene.apply_setup(setup)


func _howto() -> void:
	var panel := HowToPanel.new()
	add_child(panel)
	panel.closed.connect(_on_howto_closed.bind(panel))
	panel.open()


func _on_howto_closed(panel: HowToPanel) -> void:
	panel.queue_free()
	_main()


func _restart() -> void:
	scene.restart_session()
	queue_free()


func _leave() -> void:
	scene.quit_to_menu()


func close() -> void:
	queue_free()
	scene.on_pause_closed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
