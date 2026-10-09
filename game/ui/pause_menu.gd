class_name PauseMenu
extends Control
## The pause menu: resume, restart, the assists and camera comfort settings,
## and leaving the race. Online and LAN races keep running underneath.

const BRAKING_LINE := [["off", "Off"], ["corners", "Corners only"], ["full", "Full"]]
const GEARS := [["auto", "Automatic"], ["manual", "Manual"]]
const SOFTNESS := [[0.6, "Very soft"], [0.8, "Soft"], [1.0, "Normal"], [1.3, "Tight"]]
const HEAD := [[0.0, "Still"], [0.3, "A little"], [0.7, "More"], [1.0, "Full"]]
const FOVS := [[60.0, "60"], [65.0, "65"], [70.0, "70"], [75.0, "75"], [80.0, "80"], [90.0, "90"]]

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
	_col.add_child(LGUi.button("Assists", _assists))
	_col.add_child(LGUi.button("Camera and comfort", _camera))
	_col.add_child(LGUi.button("Sound and screen", _sound))
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
