extends Node
## The title screen and every menu before a race: Quick Race, Championship,
## Career, Time Trial, Racing School, split screen, local network and online
## play, how to play, settings, your name and driver, and about.

const LOBBY := "res://game/ui/lobby.tscn"
const TITLE_COLOR := Color("ffd23f")
const DIFFICULTY := [[40, "Easy (40)"], [55, "Gentle (55)"], [70, "Medium (70)"], [85, "Hard (85)"], [95, "Expert (95)"], [100, "Legend (100)"], [110, "Beyond (110)"]]
const DISTANCE := [[3, "3 laps"], [5, "5 laps"], [8, "8 laps"], [12, "12 laps"], [20, "20 laps"]]
const QUALI := [["none", "No qualifying"], ["one_lap", "One lap"], ["timed", "Timed session"], ["knockout", "Knockout (Q1, Q2, Q3)"]]
const SEASON := [[4, "Mini (4 rounds)"], [8, "Short (8 rounds)"], [16, "Full season (16 rounds)"], [0, "Your own calendar"]]

## Which page to open on arrival (championship, career, time_trial, school).
var open_page := ""
## Shown once when arriving here, e.g. why the last race ended.
var message := ""

var _ui: Control
var _col: VBoxContainer
var _status: Label
var _hosts_box: VBoxContainer
var _about_scroll: ScrollContainer
var _search_label: Label
var _search_since := 0
var _last_status := ""
var _net_controls: Array = []
var _net_label: Label
var _net_up := true
var _net_check_at := 0
var _leaving := false
var _season_len := 8
## Your own calendar: venue -> the layout raced there, or "" to skip it.
var _own_calendar := {}
var _champ_laps := 5
var _champ_diff := 70
var _champ_quali := "one_lap"


func _ready() -> void:
	LGInput.filter_claimed_pads = false
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.08, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var version := LGUi.label("v%s" % GameConfig.version(), "HintLabel")
	_ui.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_col = LGUi.centered_column(_ui, 600)
	LGScreenFit.center(_col)
	Session.status.connect(_on_status)
	Session.hosts_found.connect(_on_hosts)
	RaceSounds.play_music("title")
	if str(LGSettings.get_value("player", "name")).strip_edges() == "":
		_show_name(true)
		return
	match open_page:
		"championship":
			_show_championship()
		"career":
			_show_career()
		"time_trial":
			_show_time_trial()
		"school":
			_show_school()
		_:
			_show_main()


func _on_status(text: String) -> void:
	_last_status = text
	if _status and is_instance_valid(_status):
		_status.text = text


func _clear() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_hosts_box = null
	_about_scroll = null
	_search_label = null
	_search_since = 0
	_net_controls = []
	_net_label = null


func _process(_delta: float) -> void:
	if not _net_controls.is_empty() and Time.get_ticks_msec() >= _net_check_at:
		_apply_network(false)
	if _search_label and is_instance_valid(_search_label) and _search_since > 0:
		var secs := (Time.get_ticks_msec() - _search_since) / 1000
		_search_label.text = "Looking for players... %d:%02d" % [secs / 60, secs % 60]


func _add_title() -> void:
	var title := LGUi.label("Race Day", "HeaderLarge")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_col.add_child(title)
	var tag := LGUi.label("Qualify on Saturday. Win on Sunday. Do it sixteen times.", "HintLabel")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(tag)


func _add_status(text := "") -> void:
	_status = LGUi.label(text, "HintLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(_status)


func _hint(text: String) -> void:
	var l := LGUi.label(text, "HintLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(l)


func _show_main() -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.button("Quick Race", _quick_race))
	_col.add_child(LGUi.button("Championship", _show_championship))
	_col.add_child(LGUi.button("Career", _show_career))
	_col.add_child(LGUi.button("Time Trial", _show_time_trial))
	_col.add_child(LGUi.button("Racing School", _show_school))
	_col.add_child(LGUi.button("How to play", _show_howto))
	_col.add_child(LGUi.button("Local network play", _show_local))
	_col.add_child(LGUi.button("Play online", _show_online))
	_col.add_child(LGUi.button("Settings", _show_settings))
	_col.add_child(LGUi.button("Your driver: %s, %s" % [Session.player_name(), Teams.team(Session.player_team()).name], _show_driver))
	_col.add_child(LGUi.button("About Race Day", _show_about))
	var quit := LGUi.button("Quit", _quit)
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	_add_status(message)
	message = ""
	LGUi.focus_first(_col)


func _quit() -> void:
	LGScenes.quit()


## Claims the screen for one action that leaves it; false if one is running.
func _claim() -> bool:
	if _leaving or LGScenes.is_busy():
		return false
	_leaving = true
	return true


# --- Your driver --------------------------------------------------------

func _show_name(first_time: bool) -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.label("What should we call you?", "HeaderMedium"))
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.placeholder_text = "Your name"
	edit.text = str(LGSettings.get_value("player", "name"))
	edit.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(edit)
	_col.add_child(edit)
	edit.text_submitted.connect(_save_name.bind(edit, first_time))
	_col.add_child(LGUi.button("OK", _save_name.bind("", edit, first_time)))
	if not first_time:
		_col.add_child(LGUi.button("Back", _show_driver))
	edit.grab_focus.call_deferred()
	# With a controller, go straight to the on-screen keyboard (deferred, so
	# the press that chose this page has been let go and types nothing).
	if LGInput.menu_pad() >= 0 or (first_time and not Input.get_connected_joypads().is_empty()):
		_open_keyboard.call_deferred(edit)


func _open_keyboard(edit: LineEdit) -> void:
	if is_instance_valid(edit) and edit.is_inside_tree():
		OnScreenKeyboard.open(edit)


func _save_name(_t: String, edit: LineEdit, first_time: bool) -> void:
	var n := edit.text.strip_edges()
	if n == "":
		n = "Driver %d" % randi_range(10, 99)
	LGSettings.set_value("player", "name", n)
	Session.local_seats[0].name = n
	if first_time:
		_show_driver()
	else:
		_show_driver()


func _show_driver() -> void:
	_clear()
	_col.add_child(LGUi.label("Your driver", "HeaderMedium"))
	_col.add_child(LGUi.button("Name: %s" % Session.player_name(), _show_name.bind(false)))
	var teams := []
	for i in Teams.TEAMS.size():
		teams.append([i, Teams.TEAMS[i].name])
	_col.add_child(LGCycler.make("Team", teams, Session.player_team(), _set_team, 520))
	var numbers := []
	for n in range(2, 100):
		numbers.append([n, str(n)])
	_col.add_child(LGCycler.make("Car number", numbers, int(LGSettings.get_value("player", "number")), _set_value.bind("player", "number"), 520))
	_hint("Quick Race, Time Trial and the Championship use this team's car. The Career starts at Tankco.")
	_col.add_child(LGUi.button("Done", _show_main))
	LGUi.focus_first(_col)


func _set_team(v: Variant) -> void:
	LGSettings.set_value("player", "team", v)
	Session.local_seats[0].team = int(v)


func _set_value(value: Variant, section: String, key: String) -> void:
	LGSettings.set_value(section, key, value)


# --- Quick Race and split screen ----------------------------------------

func _quick_race() -> void:
	if not _claim():
		return
	Session.start_solo()
	LGScenes.change_scene(LOBBY)


# --- Championship -------------------------------------------------------

func _show_championship() -> void:
	_clear()
	_col.add_child(LGUi.label("Championship", "HeaderMedium"))
	var c := Progress.championship()
	if c.is_empty() or int(c.round) >= c.calendar.size():
		if not c.is_empty():
			_hint("Season over. You finished P%d in the championship." % Progress.standing_of(c, Progress.PLAYER_ID))
			_standings_box(c, 10)
		_hint("A season of grands prix with qualifying, points and a title to win, for %s." % Teams.team(Session.player_team()).name)
		_col.add_child(LGCycler.make("Season", SEASON, _season_len, _set_season_len, 520))
		_col.add_child(LGCycler.make("Race length", DISTANCE, _champ_laps, _set_champ_laps, 520))
		_col.add_child(LGCycler.make("AI difficulty", DIFFICULTY, _champ_diff, _set_champ_diff, 520))
		_col.add_child(LGCycler.make("Qualifying", QUALI, _champ_quali, _set_champ_quali, 520))
		_col.add_child(LGUi.button("Start the season", _start_championship))
	else:
		var round := int(c.round)
		var next: String = c.calendar[round]
		_hint("Round %d of %d: %s. You're P%d with %d points." % [round + 1, c.calendar.size(), Circuits.info(next).get("name", next), maxi(1, Progress.standing_of(c, Progress.PLAYER_ID)), int(c.standings.get(Progress.PLAYER_ID, 0))])
		_col.add_child(LGUi.button("Go racing: %s" % Circuits.info(next).get("name", next), _race_championship))
		_standings_box(c, 10)
		var quit := LGUi.button("Abandon the season", _abandon_championship)
		quit.theme_type_variation = "DangerButton"
		_col.add_child(quit)
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _standings_box(c: Dictionary, rows: int) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	for r in Progress.standings(c).slice(0, rows):
		var mine := int(r[0]) == Progress.PLAYER_ID
		for text in ["%d." % (Progress.standing_of(c, int(r[0]))), str(r[2]), "%d pts" % int(r[1])]:
			var l := LGUi.label(text)
			l.add_theme_font_size_override("font_size", 18)
			if mine:
				l.add_theme_color_override("font_color", TITLE_COLOR)
			grid.add_child(l)
	_col.add_child(grid)


func _set_season_len(v: Variant) -> void:
	_season_len = int(v)


func _set_champ_laps(v: Variant) -> void:
	_champ_laps = int(v)


func _set_champ_diff(v: Variant) -> void:
	_champ_diff = int(v)


func _set_champ_quali(v: Variant) -> void:
	_champ_quali = str(v)


func _start_championship() -> void:
	var cal := Array(Circuits.calendar())
	if cal.is_empty():
		cal = Array(Circuits.ids())
	if _season_len == 0:
		_show_own_calendar()
		return
	# Shorter seasons keep a spread of the calendar.
	var pick := []
	var n := mini(_season_len, cal.size())
	for i in n:
		pick.append(cal[int(floor(i * cal.size() / float(n)))])
	Progress.start_championship(pick, _champ_laps, _champ_diff, _champ_quali)
	_race_championship()


## Pick the rounds and the layout raced at each.
func _show_own_calendar() -> void:
	_clear()
	_col.add_child(LGUi.label("Your calendar", "HeaderMedium"))
	_hint("Pick the rounds, and which layout to race at each.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for gp in Circuits.calendar():
		var info := Circuits.info(gp)
		var venue := str(info.venue)
		var options := [["", "Not this year"]]
		for id in Circuits.ids():
			var other := Circuits.info(id)
			if str(other.venue) == venue:
				options.append([id, str(other.layout)])
		var current: String = _own_calendar.get(venue, gp)
		_own_calendar[venue] = current
		list.add_child(LGCycler.make("%d. %s" % [int(info.round), info.name], options, current, _set_own_round.bind(venue), 560))
	_col.add_child(LGUi.button("Start the season", _start_own_calendar))
	_col.add_child(LGUi.button("Back", _show_championship))
	LGUi.focus_first(_col)


func _set_own_round(v: Variant, venue: String) -> void:
	_own_calendar[venue] = str(v)


func _start_own_calendar() -> void:
	var pick := []
	for gp in Circuits.calendar():
		var id: String = _own_calendar.get(str(Circuits.info(gp).venue), gp)
		if id != "":
			pick.append(id)
	if pick.is_empty():
		_hint("Pick at least one round.")
		return
	Progress.start_championship(pick, _champ_laps, _champ_diff, _champ_quali)
	_race_championship()


func _race_championship() -> void:
	if not _claim():
		return
	Session.start_solo()
	Session.launch(Progress.championship_config())


func _abandon_championship() -> void:
	Progress.end_championship()
	_show_championship()


# --- Career -------------------------------------------------------------

func _show_career() -> void:
	_clear()
	_col.add_child(LGUi.label("Career", "HeaderMedium"))
	var c := Progress.career()
	if c.is_empty():
		_hint("You've got a seat at Tankco Racing, the slowest team on the grid. Beat your team-mate, score points the car shouldn't, and better teams will start calling.")
		_col.add_child(LGCycler.make("Race length", DISTANCE, _champ_laps, _set_champ_laps, 520))
		_col.add_child(LGCycler.make("AI difficulty", DIFFICULTY, _champ_diff, _set_champ_diff, 520))
		_col.add_child(LGUi.button("Sign for Tankco", _start_career))
		_col.add_child(LGUi.button("Back", _show_main))
		LGUi.focus_first(_col)
		return
	var s: Dictionary = c.season_state
	var team := Teams.team(int(c.team))
	var up: Dictionary = c.upgrades
	_hint("Season %d with %s. Car upgrades: engine %d, aero %d, brakes %d." % [int(c.season), team.name, int(up.engine), int(up.aero), int(up.brakes)])
	if int(s.round) >= s.calendar.size():
		var place := Progress.standing_of(s, Progress.PLAYER_ID)
		_hint("Season over: P%d in the championship." % place)
		var offers: Array = c.offers
		if offers.is_empty():
			_hint("No other team has called. Another year to show them.")
		else:
			_hint("These teams want you next season:")
			for t in offers:
				_col.add_child(LGUi.button("Sign for %s" % Teams.team(int(t)).name, _next_season.bind(int(t))))
		_col.add_child(LGUi.button("Stay at %s" % team.name, _next_season.bind(-1)))
	else:
		var next: String = s.calendar[int(s.round)]
		_hint("Round %d of %d: %s. You're P%d with %d points." % [int(s.round) + 1, s.calendar.size(), Circuits.info(next).get("name", next), maxi(1, Progress.standing_of(s, Progress.PLAYER_ID)), int(s.standings.get(Progress.PLAYER_ID, 0))])
		_col.add_child(LGUi.button("Go racing: %s" % Circuits.info(next).get("name", next), _race_career))
		_standings_box(s, 8)
	var quit := LGUi.button("Retire (end the career)", _end_career)
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _start_career() -> void:
	Progress.start_career(_champ_laps, _champ_diff)
	_show_career()


func _race_career() -> void:
	if not _claim():
		return
	Session.start_solo()
	Session.launch(Progress.career_config())


func _next_season(team: int) -> void:
	Progress.next_career_season(team)
	_show_career()


func _end_career() -> void:
	Progress.end_career()
	_show_career()


# --- Time Trial ---------------------------------------------------------

func _show_time_trial() -> void:
	_clear()
	_col.add_child(LGUi.label("Time Trial", "HeaderMedium"))
	_hint("Everyone drives the same car. Beat the medal times and your own ghost.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for id in Circuits.ids():
		var i := Circuits.info(id)
		var best := Progress.best_time(id)
		var text := "%s %s" % [i.name, i.layout]
		if best > 0.0:
			text += "   %s" % GameConfig.time_text(best)
		list.add_child(LGUi.button(text, _start_tt.bind(id), 560))
	var boards := LGUi.button("Online lap times", _show_lap_boards)
	_col.add_child(boards)
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _start_tt(id: String) -> void:
	if _claim():
		Session.start_time_trial(id)


func _show_lap_boards() -> void:
	_clear()
	_col.add_child(LGUi.label("Online lap times", "HeaderMedium"))
	if not LGOnline.is_enabled() or not LGNetwork.is_up():
		_hint(LGNetwork.OFFLINE_TEXT if not LGNetwork.is_up() else "Turn on online play in Settings to see everyone's lap times.")
	else:
		var boards := []
		for id in Circuits.ids():
			boards.append(["lap_%s" % id.replace("-", "_"), "%s %s" % [Circuits.info(id).name, Circuits.info(id).layout]])
		var panel := LGLeaderboardPanel.new()
		panel.setup(GameConfig.GAME_ID, Session.player_name(), boards, record_text)
		_col.add_child(panel)
	_col.add_child(LGUi.button("Back", _show_time_trial))
	LGUi.focus_first(_col)


# --- Racing School ------------------------------------------------------

func _show_school() -> void:
	_clear()
	_col.add_child(LGUi.label("Racing School", "HeaderMedium"))
	_hint("Short tests, each with bronze, silver and gold. The gentlest way in.")
	for t in RacingSchool.TESTS:
		if not RacingSchool.available(t):
			continue
		var m := Progress.school_medal(str(t.id))
		var medal: String = "" if m < 0 else "   " + str(LapReference.MEDAL_NAMES[m])
		_col.add_child(LGUi.button("%s%s" % [t.name, medal], _start_school.bind(str(t.id)), 560))
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _start_school(id: String) -> void:
	if _claim():
		RacingSchool.start(id)


# --- Local network ------------------------------------------------------

func _show_local() -> void:
	_clear()
	_col.add_child(LGUi.label("Local network play", "HeaderMedium"))
	_hint("Race others on the same Wi-Fi or wired network. AI drivers fill the grid.")
	var host := LGUi.button("Host on this network", _host_lan)
	var join := LGUi.button("Join on this network", _show_join)
	_col.add_child(host)
	_col.add_child(join)
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	_watch_network([host, join], "You're not connected to a network. Connect to Wi-Fi or plug in a network cable to race others nearby.")
	LGUi.focus_first(_col)


func _watch_network(controls: Array, offline_text: String) -> void:
	_net_controls = controls
	_net_label = LGUi.label(offline_text, "HintLabel")
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_label.add_theme_color_override("font_color", TITLE_COLOR)
	_col.add_child(_net_label)
	_col.move_child(_net_label, 1)
	_apply_network(true)


func _apply_network(force: bool) -> void:
	_net_check_at = Time.get_ticks_msec() + 1000
	var up := LGNetwork.is_up()
	if up == _net_up and not force:
		return
	_net_up = up
	_net_label.visible = not up
	for c in _net_controls:
		if c is BaseButton:
			c.disabled = not up
		elif c is LineEdit:
			c.editable = up
		c.focus_mode = Control.FOCUS_ALL if up else Control.FOCUS_NONE
	var focused := get_viewport().gui_get_focus_owner()
	if not force and (focused == null or focused in _net_controls or up):
		LGUi.focus_first(_col)


func _host_lan() -> void:
	if not _claim():
		return
	if Session.host_lan():
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false


func _show_join() -> void:
	_clear()
	_col.add_child(LGUi.label("Join on this network", "HeaderMedium"))
	_hint("Races hosted nearby show up here.")
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 8)
	_col.add_child(_hosts_box)
	_on_hosts([])
	_hint("Or type the host's join code:")
	var code := LineEdit.new()
	code.placeholder_text = "ABCD-EFGH"
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	code.text_submitted.connect(_join_code.bind(code))
	_col.add_child(LGUi.button("Join with code", _join_code.bind("", code)))
	_col.add_child(LGUi.button("Back", _back_from_join))
	_add_status()
	Session.browse_lan()
	LGUi.focus_first(_col)


func _join_code(_t: String, code: LineEdit) -> void:
	if not _claim():
		return
	if Session.join_lan_code(code.text):
		_wait_for_join()
	else:
		_leaving = false


func _back_from_join() -> void:
	Session.stop_browsing()
	_show_local()


func _on_hosts(hosts: Array) -> void:
	if _hosts_box == null or not is_instance_valid(_hosts_box):
		return
	for c in _hosts_box.get_children():
		_hosts_box.remove_child(c)
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(LGUi.label("Looking for races...", "HintLabel"))
		return
	for h in hosts:
		var racing := str(h.get("state", "lobby")) != "lobby"
		var text := "%s  (%d/%d)%s" % [h.get("name", "A race"), int(h.get("players", 0)), int(h.get("max", GameConfig.MAX_PLAYERS)), "  racing" if racing else ""]
		var b := LGUi.button(text, _join_host.bind(h))
		b.disabled = racing or int(h.get("protocol", 0)) != GameConfig.PROTOCOL
		_hosts_box.add_child(b)


func _join_host(h: Dictionary) -> void:
	if not _claim():
		return
	if Session.join_lan(str(h.address), int(h.get("port", LGSettings.get_value("lan", "port")))):
		_wait_for_join()
	else:
		_leaving = false


func _wait_for_join() -> void:
	_status.text = "Joining..."
	var result: Array = await _first_of_joined_or_left()
	if result[0] == "joined":
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false
		if is_instance_valid(_status):
			_status.text = str(result[1]) if str(result[1]) != "" else "Couldn't join."


var _join_result: Array = []


func _first_of_joined_or_left() -> Array:
	_join_result = []
	Session.joined.connect(_on_join_joined)
	Session.left.connect(_on_join_left)
	var waited := 0.0
	while _join_result.is_empty() and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	Session.joined.disconnect(_on_join_joined)
	Session.left.disconnect(_on_join_left)
	if _join_result.is_empty():
		Session.leave()
		return ["left", "The host didn't answer."]
	return _join_result


func _on_join_joined() -> void:
	if _join_result.is_empty():
		_join_result = ["joined", ""]


func _on_join_left(reason: String) -> void:
	if _join_result.is_empty():
		_join_result = ["left", reason]


# --- Online ---------------------------------------------------------------

func _show_online() -> void:
	_clear()
	_col.add_child(LGUi.label("Play online", "HeaderMedium"))
	if not LGOnline.is_enabled():
		_hint("Online play goes through a LinuxGroove game server. Turn it on in Settings.")
		_col.add_child(LGUi.button("Settings", _show_settings))
		_col.add_child(LGUi.button("Back", _show_main))
		LGUi.focus_first(_col)
		return
	_hint("Race up to eight people, with AI drivers filling the grid. Host a room and share its code, or join a friend's.")
	var quick := LGUi.button("Quick match", _quick_match)
	var host := LGUi.button("Host an online room", _host_online)
	_col.add_child(quick)
	_col.add_child(host)
	var code := LineEdit.new()
	code.placeholder_text = "Room code"
	code.max_length = 8
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	var join := LGUi.button("Join with code", _join_online.bind(code))
	var boards := LGUi.button("Leaderboards", _show_leaderboards)
	_col.add_child(join)
	_col.add_child(boards)
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	_watch_network([quick, host, code, join, boards], LGNetwork.OFFLINE_TEXT)
	LGUi.focus_first(_col)


func _quick_match() -> void:
	if not _claim():
		return
	_clear()
	_col.add_child(LGUi.label("Quick match", "HeaderMedium"))
	_search_label = LGUi.label("Connecting...")
	_search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_search_label)
	_hint("If nobody turns up within a minute, you'll race the AI instead.")
	_col.add_child(LGUi.button("Cancel", Session.cancel_quick_match))
	LGUi.focus_first(_col)
	_search_since = Time.get_ticks_msec()
	var where: String = await Session.quick_match()
	_search_since = 0
	match where:
		"lobby":
			LGScenes.change_scene(LOBBY)
			return
		"joining":
			if _search_label and is_instance_valid(_search_label):
				_search_label.text = "Found a race. Joining..."
			var result: Array = await _first_of_joined_or_left()
			if result[0] == "joined":
				LGScenes.change_scene(LOBBY)
				return
			_last_status = str(result[1]) if str(result[1]) != "" else "Couldn't join."
	_leaving = false
	var msg := _last_status
	_show_online()
	if _status:
		_status.text = msg


func _show_leaderboards() -> void:
	_clear()
	_col.add_child(LGUi.label("Leaderboards", "HeaderMedium"))
	_hint("From online races.")
	var panel := LGLeaderboardPanel.new()
	panel.setup(GameConfig.GAME_ID, Session.player_name(), [
		["wins_weekly", "Wins this week"],
		["wins", "Wins, all time"],
		["podiums", "Podiums"],
		["poles", "Pole positions"],
	], record_text)
	_col.add_child(panel)
	_col.add_child(LGUi.button("Back", _show_online))
	LGUi.focus_first(_col)


## The player's online record, from the stats the server keeps per race.
static func record_text(stats: Dictionary) -> String:
	var races := int(stats.get("races", 0))
	if races == 0:
		return "No online races yet. Finish one to start your record."
	var parts := [
		_count(races, "race", "races"),
		_count(int(stats.get("wins", 0)), "win", "wins"),
		_count(int(stats.get("podiums", 0)), "podium", "podiums"),
	]
	var poles := int(stats.get("poles", 0))
	if poles > 0:
		parts.append(_count(poles, "pole", "poles"))
	return "Your online record: %s." % ", ".join(parts)


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _host_online() -> void:
	if not _claim():
		return
	_status.text = "Connecting..."
	if await Session.host_online():
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false


func _join_online(code: LineEdit) -> void:
	if not _claim():
		return
	_status.text = "Connecting..."
	if await Session.join_online(code.text):
		_wait_for_join()
	else:
		_leaving = false


# --- Settings and about -------------------------------------------------

func _show_howto() -> void:
	var panel := HowToPanel.new()
	_ui.add_child(panel)
	panel.closed.connect(_on_howto_closed.bind(panel))
	panel.open()


func _on_howto_closed(panel: HowToPanel) -> void:
	panel.queue_free()
	_show_main()


func _show_settings() -> void:
	_clear()
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	_col.add_child(LGUi.button("Assists", _show_assists))
	_col.add_child(LGUi.button("Camera and comfort", _show_camera))
	_col.add_child(LGCycler.make("Scenery detail", [[0, "Low"], [1, "Medium"], [2, "High"]], LGSettings.get_value("video", "detail"), _set_value.bind("video", "detail"), 520))
	_col.add_child(LGCycler.make("Best lap's ghost", SettingsPanel.ON_OFF, LGSettings.get_value("play", "ghost"), _set_value.bind("play", "ghost"), 520))
	_col.add_child(SettingsPanel.new())
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _show_assists() -> void:
	_clear()
	_col.add_child(LGUi.label("Assists", "HeaderMedium"))
	PauseMenu.assist_rows(_col)
	_col.add_child(LGUi.button("Back", _show_settings))
	LGUi.focus_first(_col)


func _show_camera() -> void:
	_clear()
	_col.add_child(LGUi.label("Camera and comfort", "HeaderMedium"))
	_hint("The calm settings are the defaults. Change them if you like more movement.")
	PauseMenu.camera_rows(_col)
	_col.add_child(LGUi.button("Back", _show_settings))
	LGUi.focus_first(_col)


func _show_about() -> void:
	_clear()
	_col.add_child(LGUi.label("About Race Day", "HeaderMedium"))
	_about_scroll = ScrollContainer.new()
	_about_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_about_scroll.custom_minimum_size = Vector2(620, 480)
	_col.add_child(_about_scroll)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about_scroll.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = ABOUT_TEXT % GameConfig.version()
	panel.add_child(text)
	var back := LGUi.button("Back", _show_main)
	_col.add_child(back)
	back.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if _about_scroll == null or not is_instance_valid(_about_scroll):
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_about_scroll.scroll_vertical += step * 60
		get_viewport().set_input_as_handled()


const ABOUT_TEXT := """[center][b]Race Day[/b]  v%s
A LinuxGroove game

[b]Art, sound, music and fonts[/b]
Kenney (kenney.nl)
Released under CC0. Thank you, Kenney!

Racing Kit, Car Kit, City Kit, Nature Kit, Watercraft Pack,
Flag Pack, Mini Arena, Input Prompts, UI Pack - Adventure,
Kenney Fonts, Music Loops, Impact Sounds, Interface Sounds

[b]Made with[/b]
Godot Engine (godotengine.org), MIT
Nakama Godot client by Heroic Labs, Apache-2.0

Copyright (c) 2026 The LinuxGroove team
Race Day is free software under the MIT license.[/center]"""
