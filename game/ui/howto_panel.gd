class_name HowToPanel
extends Control
## How to play: a few pages on the weekend, driving, the braking line and
## assists, tyres and pit stops, flags, the cameras and the controls.
## Opened from the title and pause menus.

signal closed

const CONTROLS := [
	["steer_right", "Steer"],
	["throttle", "Throttle"],
	["brake", "Brake (hold when stopped to reverse)"],
	["shift_up", "Shift up (manual gears)"],
	["shift_down", "Shift down (manual gears)"],
	["drs", "DRS (when the HUD says it's ready)"],
	["limiter", "Pit limiter"],
	["pit", "Ask to pit this lap"],
	["camera", "Change camera"],
	["look_back", "Look behind"],
	["rewind", "Rewind (offline)"],
	["tower", "Show or hide the timing tower"],
	["pause", "Pause"],
]

var _title: Label
var _body: Label
var _extra: VBoxContainer
var _count: Label
var _prev: Button
var _next: Button
var _page := 0


static func pages() -> Array:
	return [
		{"title": "Race day", "body":
			"A weekend is qualifying, then the race. Qualifying sets the grid: one flying lap, a timed session, or a knockout in three parts. The race starts when the five red lights go out.\n\nTwenty-five points for a win, then 18, 15, 12, 10, 8, 6, 4, 2 and 1. Championship and Career add them up over a season."},
		{"title": "Driving", "body":
			"These cars grip hard, but only so hard. Brake in a straight line before the corner, turn in, and squeeze the throttle on the way out. Too much brake locks the wheels; too much throttle out of a slow corner spins the rear.\n\nThe quickest line is wide on the way in, close to the inside in the middle, and wide on the way out."},
		{"title": "The braking line", "body":
			"The line on the road shows where to go and how fast: green, you can go faster; yellow, about right; red, brake now.\n\nAssists help while you learn: braking and steering help, anti-lock brakes, traction control, automatic gears, a pit lane that drives itself, and rewind. Take them off one at a time in the pause menu as you get quicker."},
		{"title": "Tyres and pit stops", "body":
			"Soft tyres are fastest and wear quickest; hard last longest. In the wet, use intermediates or full wets. In longer races you must use two kinds of dry tyre, so plan a stop.\n\nPress the pit button to ask for a stop. Slow down for the pit entry, turn the limiter on before the white line, and stop in your box. The crew does the rest."},
		{"title": "Flags and the safety car", "body":
			"Yellow: slow down, danger ahead, no overtaking. Blue: a faster car is lapping you, let it by. The safety car and the virtual safety car slow the whole field after a crash: hold your place until the green flag.\n\nAll four wheels past the white lines in a corner is a warning; a few of those and it's a time penalty. Speeding in the pit lane is a penalty too."},
		{"title": "Overtaking", "body":
			"Follow closely on a straight and the slipstream pulls you along. Within a second of the car ahead at the detection line, DRS opens your wing in the next zone for extra speed.\n\nTurbulent air close behind another car costs grip in the corners, so time your attack: a better exit, a later brake, or DRS."},
		{"title": "Cameras", "body":
			"Four cameras: chase near, chase far, the T-cam above the helmet and the cockpit. The camera button cycles them.\n\nIf you feel queasy, the comfort settings help: a level horizon, no shake and a still head are on from the start, and a softer chase camera turns more gently."},
		{"title": "Controls", "body": "", "controls": true},
	]


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	panel.custom_minimum_size = Vector2(780, 520)
	center.add_child(panel)
	LGScreenFit.center(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = LGUi.label("", "HeaderMedium")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_body = LGUi.label("")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 720
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 380
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 4)
	scroll.add_child(_extra)
	_count = LGUi.label("", "HintLabel")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_prev = LGUi.button("Previous", _go.bind(-1), 200)
	row.add_child(_prev)
	_next = LGUi.button("Next", _go.bind(1), 200)
	row.add_child(_next)


func open() -> void:
	LGSettings.set_value("tutorial", "howto_seen", true)
	_page = 0
	visible = true
	_show_page()
	_next.grab_focus.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _go(dir: int) -> void:
	_page += dir
	if _page >= pages().size():
		close()
		return
	_page = maxi(_page, 0)
	_show_page()
	(_prev if dir < 0 and _prev.visible else _next).grab_focus.call_deferred()


func _show_page() -> void:
	var all := pages()
	var page: Dictionary = all[_page]
	_title.text = page.title
	_body.text = page.body
	_body.visible = page.body != ""
	for c in _extra.get_children():
		_extra.remove_child(c)
		c.queue_free()
	var controls: bool = page.get("controls", false)
	(_extra.get_parent() as Control).visible = controls
	if controls:
		for pair in CONTROLS:
			_extra.add_child(ActionPrompt.make(pair[0], pair[1], 28))
	_count.text = "%d / %d" % [_page + 1, all.size()]
	_prev.visible = _page > 0
	_next.text = "Done" if _page == all.size() - 1 else "Next"


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
