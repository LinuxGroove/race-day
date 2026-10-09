class_name ResultsPanel
extends Control
## The classification after qualifying or the race: positions, times, gaps,
## stops and points, with the player's rows picked out.

var scene: RaceScene
var rows: Array = []
var qualifying := false
## A Racing School result (RacingSchool.result) instead of a classification.
var school := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RaceSounds.play_music("results")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	if not school.is_empty():
		_school_result(col)
		return
	var title := str(scene.config.get("title", "")) if scene else ""
	col.add_child(LGUi.label("%s %s" % [title, "Qualifying" if qualifying else "Race result"], "HeaderMedium"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(grid)
	var head := ["Pos", "Driver", "Team", "Time" if not qualifying else "Best lap", "Gap" if not qualifying else "", "Pts" if not qualifying else ""]
	for h in head:
		grid.add_child(_cell(h, Color(0.7, 0.75, 0.8)))
	var best := 0.0
	for r in rows:
		var mine := not bool(r.get("bot", true))
		var col_text := RaceHud.WARN if mine else RaceHud.TEXT
		grid.add_child(_cell(str(r.position), col_text))
		var name := str(r.name)
		if not qualifying and bool(r.get("fastest", false)):
			name += "  (fastest lap)"
		grid.add_child(_cell(name, col_text))
		grid.add_child(_cell(str(Teams.team(int(r.team)).name), Teams.team(int(r.team)).main.lightened(0.25)))
		if qualifying:
			var t := float(r.best)
			if best == 0.0 and t > 0.0:
				best = t
			grid.add_child(_cell(GameConfig.time_text(t) if t > 0.0 else "No time", col_text))
			grid.add_child(_cell("+%.3f" % (t - best) if t > best and best > 0.0 else "", col_text))
			grid.add_child(_cell("", col_text))
		else:
			var status := str(r.status)
			var time := ""
			if int(r.position) == 1:
				time = GameConfig.time_text(float(r.time))
			elif status == "Finished":
				time = "+%.3f" % float(r.gap)
			else:
				time = status
			grid.add_child(_cell(time, col_text))
			grid.add_child(_cell("%d stop%s%s" % [int(r.stops), "" if int(r.stops) == 1 else "s", ", +%ds" % int(r.penalty) if float(r.penalty) > 0.0 else ""], Color(0.7, 0.75, 0.8)))
			grid.add_child(_cell(str(r.points) if int(r.points) > 0 else "", col_text))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var can_continue := not Session.is_networked() or Session.is_host()
	if can_continue:
		var label := "Start the race" if qualifying else "Continue"
		buttons.add_child(LGUi.button(label, _continue, 280))
	else:
		buttons.add_child(LGUi.label("Waiting for the host...", "HintLabel"))
	LGUi.focus_first(buttons)


func _school_result(col: VBoxContainer) -> void:
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(LGUi.label(str(scene.config.get("title", "Racing School")), "HeaderMedium"))
	var medal := int(school.medal)
	var head := LGUi.label(LapReference.MEDAL_NAMES[medal] if medal >= 0 else "Not this time", "HeaderLarge")
	head.add_theme_color_override("font_color", LapReference.MEDAL_COLORS[medal] if medal >= 0 else RaceHud.BAD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var overtake := str(school.kind) == "overtake"
	if bool(school.passed) or str(school.why) == "Too slow for bronze. Try again!":
		var mine := ("%.0f m ahead" % float(school.margin)) if overtake else GameConfig.time_text(float(school.time))
		col.add_child(_centered(LGUi.label("You: %s" % mine, "HeaderMedium")))
	if str(school.why) != "":
		col.add_child(_centered(LGUi.label(str(school.why), "HintLabel")))
	var tg: Array = school.targets
	for i in 3:
		var text := ("%.0f m ahead" % float(tg[i])) if overtake else GameConfig.time_text(float(tg[i]))
		if overtake and i == 2:
			text = "ahead at the end"
		var l := _cell("%s   %s" % [LapReference.MEDAL_NAMES[i], text], LapReference.MEDAL_COLORS[i])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	if bool(school.better):
		col.add_child(_centered(LGUi.label("A new best medal!", "HintLabel")))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	buttons.add_child(LGUi.button("Try again", _retry, 240))
	buttons.add_child(LGUi.button("Back to the school", _continue, 280))
	LGUi.focus_first(buttons)


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _retry() -> void:
	scene.restart_session()


func _cell(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 19)
	return l


func _continue() -> void:
	scene.continue_weekend()
