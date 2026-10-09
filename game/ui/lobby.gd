extends Node
## The lobby before a race: who's driving and for which team, a second
## player on another controller for split screen, the race settings, the
## join code, and the host's Start button. AI drivers fill the rest of the
## grid.
##
## Menus are driven by the first player. A second controller joins with
## Start and steers only its own card: d-pad left and right change team,
## B leaves.

const STICK := 0.6
const REPEAT := 0.28
const RULE_ROWS := [
	["circuit", "Circuit", []],
	["laps", "Race length", [[3, "3 laps"], [5, "5 laps"], [8, "8 laps"], [12, "12 laps"], [20, "20 laps"]]],
	["qualifying", "Qualifying", [["none", "None (random grid)"], ["one_lap", "One lap"], ["timed", "Timed session"]]],
	["difficulty", "AI difficulty", [[40, "Easy (40)"], [55, "Gentle (55)"], [70, "Medium (70)"], [85, "Hard (85)"], [95, "Expert (95)"], [100, "Legend (100)"], [110, "Beyond (110)"]]],
	["weather", "Weather", [["dry", "Dry"], ["random", "As the forecast says"], ["mixed", "Changeable"], ["wet", "Wet"]]],
	["grid", "Grid", [[8, "8 cars"], [12, "12 cars"], [16, "16 cars"], [20, "20 cars"]]],
	["damage", "Damage", [[0, "Off"], [1, "Light"], [2, "Full"]]],
	["tyre_wear", "Tyre wear", [[0.0, "Off"], [1.0, "Normal"], [2.0, "Double"]]],
]

var _roster: VBoxContainer
var _cyclers := {}
var _code: Label
var _status: Label
var _about: Label
var _start: Button
var _team: LGCycler
var _seat_box: HBoxContainer
var _join_hint: Label
var _cards := {}
## Per pad: {"buttons": {button: bool}, "repeat": seconds}
var _pads := {}


func _ready() -> void:
	LGInput.filter_claimed_pads = true
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.08, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	ui.add_child(margin)
	LGScreenFit.fill(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := LGUi.label(_title_text(), "HeaderMedium")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_code = LGUi.label("", "HeaderMedium")
	_code.add_theme_color_override("font_color", Color("ffd23f"))
	head.add_child(_code)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)
	_build_drivers(body)
	_build_rules(body)
	_seat_box = HBoxContainer.new()
	_seat_box.add_theme_constant_override("separation", 12)
	col.add_child(_seat_box)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	_status = LGUi.label("", "HintLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var leave := LGUi.button("Leave", _leave, 200)
	leave.theme_type_variation = "DangerButton"
	bottom.add_child(leave)
	_start = LGUi.button("Start the weekend", _start_race, 300)
	bottom.add_child(_start)
	# Methods, not lambdas: a lambda stays connected to the autoload after the
	# lobby is freed.
	Session.roster_changed.connect(_refresh)
	Session.settings_changed.connect(_refresh)
	Session.seats_changed.connect(_refresh_seats)
	Session.status.connect(_on_status)
	Session.left.connect(_on_left)
	_refresh()
	_refresh_seats()
	if Session.is_host():
		_start.grab_focus.call_deferred()
	else:
		_team.grab_focus.call_deferred()


func _exit_tree() -> void:
	LGInput.filter_claimed_pads = false


func _build_drivers(body: HBoxContainer) -> void:
	var left := PanelContainer.new()
	left.theme_type_variation = "DarkPanel"
	left.custom_minimum_size.x = 520
	body.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	left.add_child(lcol)
	lcol.add_child(LGUi.label("Drivers", "HeaderMedium"))
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 0)
	lcol.add_child(_roster)
	lcol.add_child(LGUi.label("Your team", "HeaderMedium"))
	var teams := []
	for i in Teams.TEAMS.size():
		teams.append([i, str(Teams.TEAMS[i].name)])
	_team = LGCycler.make("Team", teams, int(Session.local_seats[0].team), _on_team, 470)
	lcol.add_child(_team)
	var about := LGUi.label("Teams are listed quickest first. Two of you can share a team.", "HintLabel")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = 470
	lcol.add_child(about)
	_join_hint = LGUi.label("", "HintLabel")
	_join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_hint.custom_minimum_size.x = 470
	lcol.add_child(_join_hint)


func _build_rules(body: HBoxContainer) -> void:
	var right := PanelContainer.new()
	right.theme_type_variation = "DarkPanel"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(LGUi.label("The race", "HeaderMedium"))
	for row in RULE_ROWS:
		var key: String = row[0]
		var options: Array = row[2]
		if key == "circuit":
			options = []
			for id in Circuits.ids():
				options.append([id, str(Circuits.info(id).get("name", id))])
		var c := LGCycler.make(row[1], options, Session.settings.get(key), _set_rule.bind(key), 520)
		_cyclers[key] = c
		box.add_child(c)
	_about = LGUi.label("", "HintLabel")
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size.x = 500
	box.add_child(_about)


func _set_rule(value: Variant, key: String) -> void:
	Session.set_setting(key, value)


func _on_team(v: Variant) -> void:
	Session.set_seat_value(0, "team", int(v))


func _start_race() -> void:
	Session.start_match()


func _on_status(text: String) -> void:
	_status.text = text


func _on_left(reason: String) -> void:
	LGScenes.change_scene("res://game/ui/title.tscn", func(n): n.set("message", reason))


func _title_text() -> String:
	match Session.mode:
		Session.Mode.SOLO:
			return "Quick Race" if Session.local_seats.size() < 2 else "Split screen"
		Session.Mode.LAN_HOST, Session.Mode.ONLINE_HOST:
			return "Your race"
	return "Joined a race"


func _refresh() -> void:
	for c in _roster.get_children():
		_roster.remove_child(c)
		c.queue_free()
	var ids: Array = Session.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Session.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = Teams.team(int(p.get("team", 0))).main
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var tags := []
		if int(p.peer) == Session.local_id():
			tags.append("you" if int(p.seat) == 0 else "player %d" % (int(p.seat) + 1))
		if int(p.peer) == 1 and int(p.seat) == 0 and Session.is_networked():
			tags.append("host")
		var name := LGUi.label("%s%s" % [p.name, ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""])
		name.add_theme_font_size_override("font_size", 20)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(LGUi.label(str(Teams.team(int(p.get("team", 0))).name), "HintLabel"))
		_roster.add_child(row)
	var host := Session.is_host()
	for key in _cyclers:
		_cyclers[key].set_value(Session.settings.get(key))
		_cyclers[key].set_read_only(not host)
	var info := Circuits.info(str(Session.settings.get("circuit", "")))
	var fill := maxi(0, int(Session.settings.get("grid", 20)) - Session.players.size())
	_about.text = "%s\n\n%d AI drivers fill the grid." % [str(info.get("about", "")), fill]
	_start.visible = host
	_start.disabled = not Session.can_start()
	var blocker := Session.start_blocker()
	if Session.quick and Session.quick_seconds_left() > 0.0:
		if Session.mode == Session.Mode.SOLO:
			_status.text = "Nobody else was looking for a race, so it's you and the AI."
		elif host:
			_status.text = "AI drivers fill the grid when the countdown ends."
		else:
			_status.text = "The weekend starts by itself when the countdown ends."
	elif host and blocker != "":
		_status.text = blocker
	elif not host:
		_status.text = "Waiting for the host to start the weekend."
	_refresh_code()


func _refresh_code() -> void:
	if Session.quick:
		var left := ceili(Session.quick_seconds_left())
		_code.text = "Quick match: starts in %d s" % left if left > 0 else "Quick match"
		return
	match Session.mode:
		Session.Mode.LAN_HOST:
			_code.text = "Join code: %s" % JoinCode.pretty(Session.join_code) if Session.join_code != "" else "No network found"
		Session.Mode.ONLINE_HOST, Session.Mode.ONLINE_CLIENT:
			_code.text = "Room code: %s" % Session.join_code
		_:
			_code.text = ""


# --- Split screen -------------------------------------------------------

func _refresh_seats() -> void:
	_team.set_value(int(Session.local_seats[0].team))
	for i in _cards.keys():
		if i >= Session.local_seats.size():
			_cards[i].queue_free()
			_cards.erase(i)
	for i in range(1, Session.local_seats.size()):
		if not _cards.has(i):
			var card := SeatCard.new()
			_seat_box.add_child(card)
			card.setup(i)
			_cards[i] = card
		_cards[i].show_seat(Session.local_seats[i])
	_seat_box.visible = Session.local_seats.size() > 1
	var room := Session.local_seats.size() < GameConfig.MAX_LOCAL
	_join_hint.visible = room
	_join_hint.text = "Racing a friend on one screen? Press Start on another controller." if room else ""


func _process(delta: float) -> void:
	if Session.quick:
		_refresh_code()
	var menu_pad := LGInput.menu_pad()
	for pad in Input.get_connected_joypads():
		var state: Dictionary = _pads.get(pad, {"buttons": {}, "repeat": 0.0})
		_pads[pad] = state
		var seat := Session.seat_for_pad(pad)
		if _pressed(pad, state, JOY_BUTTON_START):
			if seat < 0 and pad != menu_pad:
				if Session.add_local_seat(pad) < 0 and Session.local_seats.size() >= GameConfig.MAX_LOCAL:
					_status.text = "Up to %d players can share one screen." % GameConfig.MAX_LOCAL
			elif seat < 0 and Session.is_host() and not _start.disabled:
				_start.grab_focus()
		if seat <= 0:
			continue
		if _pressed(pad, state, JOY_BUTTON_B):
			Session.remove_local_seat(seat)
			continue
		var dir := _direction(pad, state, delta)
		if dir != 0:
			var team := wrapi(int(Session.local_seats[seat].team) + dir, 0, Teams.TEAMS.size())
			Session.set_seat_value(seat, "team", team)
	for pad in _pads.keys():
		if not pad in Input.get_connected_joypads():
			_pads.erase(pad)


## True on the frame `button` went down on `pad`.
func _pressed(pad: int, state: Dictionary, button: int) -> bool:
	var down := Input.is_joy_button_pressed(pad, button)
	var was := bool(state.buttons.get(button, false))
	state.buttons[button] = down
	return down and not was


## Left or right on a second player's d-pad or stick, with key-repeat.
func _direction(pad: int, state: Dictionary, delta: float) -> int:
	var x := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
	var d := 0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT) or x < -STICK:
		d = -1
	elif Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT) or x > STICK:
		d = 1
	if d == 0:
		state.repeat = 0.0
		return 0
	state.repeat = float(state.repeat) - delta
	if float(state.repeat) > 0.0:
		return 0
	state.repeat = REPEAT
	return d


func _leave() -> void:
	# Session.left takes everyone back to the title screen.
	Session.leave("")


## A second player's card: their team and how to change it.
class SeatCard extends PanelContainer:
	var index := 0
	var _swatch: ColorRect
	var _name: Label
	var _what: Label

	func setup(p_index: int) -> void:
		index = p_index
		theme_type_variation = "GlassPanel"
		custom_minimum_size.x = 440
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		add_child(row)
		_swatch = ColorRect.new()
		_swatch.custom_minimum_size = Vector2(16, 70)
		row.add_child(_swatch)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_name = LGUi.label("", "NameLabel")
		col.add_child(_name)
		_what = LGUi.label("")
		col.add_child(_what)
		var seat: Dictionary = Session.local_seats[index]
		var family := LGInput.family_for_joypad(int(seat.pad))
		var help := HBoxContainer.new()
		help.add_theme_constant_override("separation", 14)
		col.add_child(help)
		help.add_child(_glyph_hint(family, [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT], "Team"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_B], "Leave"))

	func show_seat(seat: Dictionary) -> void:
		var t := Teams.team(int(seat.team))
		_name.text = str(seat.name)
		_swatch.color = t.main
		_what.text = str(t.name)

	static func _glyph_hint(family: String, buttons: Array, text: String) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		for b in buttons:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(28, 28)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = LGInput.pad_glyph(family, b)
			box.add_child(icon)
		box.add_child(LGUi.label(" " + text, "HintLabel"))
		return box
