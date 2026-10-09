class_name RaceHud
extends Control
## One player's race display: position and lap, the timing tower, lap times
## and the delta, the dash (speed, gear, revs, DRS, the limiter, tyres and
## damage), the track map, the start lights, flags and the race engineer's
## radio.

const PANEL := Color(0.06, 0.07, 0.1, 0.72)
const TEXT := Color(0.97, 0.97, 0.98)
const DIM := Color(0.7, 0.74, 0.8)
const GOOD := Color("4fd16a")
const BEST := Color("b36bff")
const WARN := Color("ffd23f")
const BAD := Color("ff5a4f")

var index := 0
var split := false
var scene: RaceScene
var driver: PlayerDriver

var _pos: Label
var _lap: Label
var _lap_time: Label
var _last: Label
var _best: Label
var _delta: Label
var _tower: VBoxContainer
var _tower_box: PanelContainer
var _tower_rows: Array = []
var _dash: Dash
var _map: TrackMap
var _lights: Lights
var _banner: Label
var _flag: Label
var _radio: Label
var _radio_box: PanelContainer
var _toast: Label
var _pit: Label
var _radio_queue: Array = []
var _radio_t := 0.0
var _banner_t := 0.0
var _toast_t := 0.0
var _show_tower := true
var _splits := PackedFloat32Array()
var _best_splits := PackedFloat32Array()
var _said := {}
var _font_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_scale = 0.8 if split else 1.0
	# Half a screen has no room for the tower beside the map: Tab shows it.
	_show_tower = bool(LGSettings.get_value("hud", "tower")) and not split
	# Top left: position and lap.
	var tl := _panel(Vector2(16, 14), Control.PRESET_TOP_LEFT)
	var col := VBoxContainer.new()
	tl.add_child(col)
	_pos = _label("P-", 46, TEXT, LGTheme.heading_font)
	_lap = _label("", 20, DIM)
	col.add_child(_pos)
	col.add_child(_lap)
	# The tower under it.
	_tower_box = PanelContainer.new()
	_tower_box.add_theme_stylebox_override("panel", _box(PANEL))
	_tower_box.position = Vector2(16, 120 * _font_scale)
	add_child(_tower_box)
	_tower = VBoxContainer.new()
	_tower.add_theme_constant_override("separation", 0)
	_tower_box.add_child(_tower)
	# Top right: times.
	var tr := PanelContainer.new()
	tr.add_theme_stylebox_override("panel", _box(PANEL))
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_left = -16
	tr.offset_right = -16
	tr.offset_top = 14
	tr.custom_minimum_size.x = 210 * _font_scale
	add_child(tr)
	var tcol := VBoxContainer.new()
	tr.add_child(tcol)
	_lap_time = _label("", 34, TEXT, LGTheme.heading_font)
	_lap_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delta = _label("", 22, GOOD)
	_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_last = _label("", 18, DIM)
	_last.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best = _label("", 18, DIM)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l in [_lap_time, _delta, _last, _best]:
		tcol.add_child(l)
	# Bottom right: the dash.
	_dash = Dash.new()
	_dash.scale_by = _font_scale
	_dash.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash.custom_minimum_size = Vector2(300, 150) * _font_scale
	_dash.size = _dash.custom_minimum_size
	_dash.position = Vector2(-316, -166) * _font_scale
	add_child(_dash)
	# Bottom left: the map.
	_map = TrackMap.new()
	_map.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var ms := 210.0 * _font_scale
	_map.custom_minimum_size = Vector2(ms, ms)
	_map.size = _map.custom_minimum_size
	_map.position = Vector2(16, -ms - 16)
	add_child(_map)
	# Middle: lights, banners, flags and the radio.
	_lights = Lights.new()
	_lights.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lights.custom_minimum_size = Vector2(360, 80)
	_lights.size = _lights.custom_minimum_size
	_lights.position = Vector2(-180, 60)
	add_child(_lights)
	_banner = _label("", 54, TEXT, LGTheme.heading_font)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position = Vector2(-400, -140)
	_banner.custom_minimum_size = Vector2(800, 0)
	add_child(_banner)
	_flag = _label("", 24, Color.BLACK, LGTheme.heading_font)
	_flag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flag.custom_minimum_size = Vector2(520, 0)
	_flag.position = Vector2(-260, 18)
	_flag.add_theme_constant_override("outline_size", 0)
	add_child(_flag)
	_radio_box = PanelContainer.new()
	_radio_box.add_theme_stylebox_override("panel", _box(Color(0.05, 0.12, 0.2, 0.85)))
	_radio_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_radio_box.position = Vector2(-300, -120 * _font_scale)
	_radio_box.custom_minimum_size = Vector2(600, 0)
	_radio_box.visible = false
	add_child(_radio_box)
	_radio = _label("", 22, TEXT)
	_radio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_box.add_child(_radio)
	_toast = _label("", 22, TEXT)
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.position = Vector2(-150, 40)
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_toast)
	_pit = _label("", 22, WARN, LGTheme.heading_font)
	_pit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pit.position = Vector2(-316, -210 * _font_scale)
	add_child(_pit)


func attach(p_scene: RaceScene, p_driver: PlayerDriver) -> void:
	scene = p_scene
	driver = p_driver
	_map.setup(scene, driver)
	_dash.driver = driver


func session_started() -> void:
	_splits = PackedFloat32Array()
	_best_splits = PackedFloat32Array()
	_said.clear()
	_banner.text = ""
	match scene.kind:
		Race.Kind.QUALIFYING:
			var timed := scene.quali_clock_left() >= 0.0
			_say("Qualifying. %s" % ("Set your best lap before the flag." if timed else "One flying lap. Make it count."))
		Race.Kind.TIME_TRIAL:
			var m := scene.medals()
			_say("Time Trial. Gold is %s." % GameConfig.time_text(float(m[0])))
		Race.Kind.RACE:
			_say("Grid's formed. %d laps. Watch the lights." % scene.race.laps)
		Race.Kind.SCHOOL:
			if scene.school:
				_say(str(scene.school.test.brief))


func toggle_tower() -> void:
	_show_tower = not _show_tower


func show_camera_name(text: String) -> void:
	_toast.text = text
	_toast_t = 1.2


# --- Every frame ----------------------------------------------------------

func _process(dt: float) -> void:
	if scene == null or driver == null or scene.race == null:
		return
	var race := scene.race
	var e := driver.entry
	_update_top(race, e)
	_update_times(race, e)
	_update_tower(race, e)
	_lights.lit = race.lights if race.phase == Race.Phase.LIGHTS else 0
	_lights.visible = race.phase == Race.Phase.LIGHTS or race.phase == Race.Phase.GRID
	_update_flags(race, e)
	_pit.text = ""
	if driver.piloting:
		_pit.text = "PIT ASSIST"
	elif driver.pit_requested:
		_pit.text = "BOX THIS LAP"
	elif e.sim.limiter_on:
		_pit.text = "LIMITER"
	_banner_t -= dt
	if _banner_t <= 0.0:
		_banner.text = ""
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0
	_radio_t -= dt
	if _radio_t <= 0.0:
		if _radio_queue.is_empty():
			_radio_box.visible = false
		else:
			_radio.text = _radio_queue.pop_front()
			if index == 0 and scene.sounds:
				scene.sounds.radio()
			_radio_box.visible = bool(LGSettings.get_value("hud", "radio"))
			_radio_t = 3.6
	if e.sim.wear > 0.7 and not _said.has("wear") and scene.kind == Race.Kind.RACE:
		_said["wear"] = true
		_say("Tyres are going off. Press %s to box." % LGInput.label_for_action("pit"))
	_map.visible = bool(LGSettings.get_value("hud", "map"))


func _update_top(race: Race, e: Race.Entry) -> void:
	match scene.kind:
		Race.Kind.RACE:
			_pos.text = "P%d" % e.position + ("/%d" % race.entries.size())
			_lap.text = "LAP %d/%d" % [clampi(e.lap, 1, race.laps), race.laps] if not e.finished else "FINISHED"
		Race.Kind.QUALIFYING:
			var board := scene.quali_board()
			var p := 0
			for i in board.size():
				if int(board[i].id) == e.id:
					p = i + 1
			_pos.text = "P%d" % p if p > 0 else "QUALI"
			var left := scene.quali_clock_left()
			_lap.text = ("%s LEFT" % GameConfig.time_text(left, 0)) if left >= 0.0 else ("OUT LAP" if e.lap < 1 else "FLYING LAP")
		Race.Kind.TIME_TRIAL:
			_pos.text = "TIME TRIAL"
			_lap.text = "LAP %d" % maxi(1, e.lap)
		Race.Kind.SCHOOL:
			_pos.text = "SCHOOL"
			var sc := scene.school
			if sc and sc.reference > 0.0 and str(sc.test.kind) != "overtake":
				_lap.text = "GOLD %s" % GameConfig.time_text(float(sc.targets()[0]))
			elif sc and sc.rival:
				var m := e.s_total - sc.rival.s_total
				_lap.text = "%s %.0f M" % ["AHEAD" if m > 0.0 else "BEHIND", absf(m)]
			else:
				_lap.text = ""
		_:
			_pos.text = ""
			_lap.text = ""


func _update_times(race: Race, e: Race.Entry) -> void:
	var t := race.time - e.lap_start if e.lap >= 1 and race.phase == Race.Phase.RACING else 0.0
	if scene.school and str(scene.school.test.kind) != "lap":
		t = scene.school.elapsed
	_lap_time.text = GameConfig.time_text(t) if t > 0.0 and not e.finished else ""
	if not e.lap_valid and scene.kind != Race.Kind.RACE:
		_lap_time.add_theme_color_override("font_color", BAD)
	else:
		_lap_time.add_theme_color_override("font_color", TEXT)
	_last.text = "LAST  %s" % GameConfig.time_text(e.last_lap) if e.last_lap > 0.0 else ""
	_best.text = "BEST  %s" % GameConfig.time_text(e.best_lap) if e.best_lap > 0.0 else ""
	# The delta to the best lap, from splits every 50 m.
	_delta.text = ""
	if e.lap >= 1 and t > 0.0:
		var into := fposmod(e.s_total, race.track.length)
		var k := int(into / 50.0)
		if _splits.size() <= k:
			_splits.resize(k + 1)
		_splits[k] = t
		if k < _best_splits.size() and _best_splits[k] > 0.0 and scene.kind != Race.Kind.RACE:
			var d := t - _best_splits[k]
			_delta.text = "%+.2f" % d
			_delta.add_theme_color_override("font_color", GOOD if d <= 0.0 else BAD)


func _update_tower(race: Race, e: Race.Entry) -> void:
	_tower_box.visible = _show_tower and scene.kind != Race.Kind.TIME_TRIAL and scene.kind != Race.Kind.SCHOOL
	if not _tower_box.visible:
		return
	var rows := []
	if scene.kind == Race.Kind.QUALIFYING:
		var best := 0.0
		for r in scene.quali_board():
			if best == 0.0:
				best = float(r.time)
			rows.append([r.code, int(r.team), "+%.3f" % (float(r.time) - best) if float(r.time) > best else GameConfig.time_text(float(r.time)), int(r.id) == e.id])
	elif scene.kind == Race.Kind.RACE:
		var me := race.order.find(e)
		# Show the top three, then the cars around the player.
		var show := {}
		for i in mini(3, race.order.size()):
			show[i] = true
		var max_rows := 8 if split else 12
		var around := maxi(2, (max_rows - 3) / 2)
		for i in range(maxi(0, me - around), mini(race.order.size(), me + around + 1)):
			show[i] = true
		var keys := show.keys()
		keys.sort()
		for i in keys:
			var o: Race.Entry = race.order[i]
			var gap := ""
			if i == 0:
				gap = "Leader" if race.phase != Race.Phase.FINISHED else GameConfig.time_text(o.finish_time)
			elif o.retired:
				gap = "OUT"
			elif o.in_pit_lane:
				gap = "PIT"
			elif o.laps_down > 0:
				gap = "+%d L" % o.laps_down
			else:
				gap = "+%.1f" % o.gap
			rows.append([o.code, o.team, gap, o == e, o.position])
	else:
		_tower_box.visible = false
		return
	while _tower_rows.size() < rows.size():
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var num := _label("", 18, DIM)
		num.custom_minimum_size = Vector2(30, 0) * _font_scale
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(5, 20) * _font_scale
		var code := _label("", 19, TEXT)
		code.custom_minimum_size = Vector2(56, 0) * _font_scale
		var gap := _label("", 17, DIM)
		gap.custom_minimum_size = Vector2(82, 0) * _font_scale
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for c in [num, bar, code, gap]:
			r.add_child(c)
		_tower.add_child(r)
		_tower_rows.append([r, num, bar, code, gap])
	for i in _tower_rows.size():
		var tr: Array = _tower_rows[i]
		tr[0].visible = i < rows.size()
		if i >= rows.size():
			continue
		var row: Array = rows[i]
		tr[1].text = str(row[4]) if row.size() > 4 else str(i + 1)
		tr[2].color = Teams.team(int(row[1])).main
		tr[3].text = str(row[0])
		tr[3].add_theme_color_override("font_color", WARN if row[3] else TEXT)
		tr[4].text = str(row[2])


func _update_flags(race: Race, e: Race.Entry) -> void:
	var text := ""
	var col := Color(0, 0, 0, 0)
	if race.sc:
		text = "SAFETY CAR IN THIS LAP" if race.sc_in else "SAFETY CAR"
		col = WARN
	elif race.vsc:
		text = "VIRTUAL SAFETY CAR"
		col = WARN
	elif e.blue:
		text = "BLUE FLAG"
		col = Color("3e8bff")
	elif race.yellow[race.track.sector_of(e.sim.spot.s)]:
		text = "YELLOW FLAG"
		col = WARN
	elif race.phase == Race.Phase.FINISHED or e.finished:
		text = "CHEQUERED FLAG"
		col = Color.WHITE
	_flag.text = text
	_flag.visible = text != ""
	var sb := _box(col)
	_flag.add_theme_stylebox_override("normal", sb)


# --- Events -------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	if driver == null:
		return
	var me := driver.entry.id
	var mine := int(ev.get("id", -99999)) == me
	match str(ev.type):
		"lights_out":
			_flash("GO!", 1.2)
			_say("Go, go, go!")
		"lap":
			if mine:
				if bool(ev.valid) and (_best_splits.is_empty() or float(ev.time) <= driver.entry.best_lap + 0.0001):
					_best_splits = _splits.duplicate()
				_splits = PackedFloat32Array()
				if scene.kind == Race.Kind.RACE:
					_lap_radio(ev)
				elif scene.kind == Race.Kind.QUALIFYING:
					_say("%s. %s" % [GameConfig.time_text(float(ev.time)), _quali_place()] if bool(ev.valid) else "That lap's deleted for track limits.")
		"personal_best":
			if mine and scene.kind != Race.Kind.RACE:
				_flash(GameConfig.time_text(float(ev.time)), 2.0)
		"fastest_lap":
			if mine and scene.kind == Race.Kind.RACE:
				_say("Fastest lap of the race. Great job.")
		"penalty":
			if mine:
				_say("%d-second penalty: %s." % [int(ev.seconds), str(ev.why).to_lower()])
		"track_limits":
			if mine:
				_say("Track limits at turn %d. Warning %d of 3." % [int(ev.corner), int(ev.count)])
		"black_white":
			if mine:
				_say("Black and white flag. Next time over the limits is a penalty.")
		"lap_invalid":
			if mine:
				_say("Lap deleted: track limits at turn %d." % int(ev.corner))
		"drs_enabled":
			_say("DRS is enabled. Within a second at the line, press %s." % LGInput.label_for_action("drs"))
		"drs_ready":
			if mine:
				_toast.text = "DRS"
				_toast_t = 1.0
		"vsc":
			_say("Virtual safety car. Slow down and hold position." if bool(ev.on) else "VSC ending. Be ready to go.")
		"sc":
			if bool(ev.on) and bool(ev.get("in", false)):
				_say("Safety car in this lap. Get ready for the restart.")
			elif bool(ev.on):
				_say("Safety car, safety car. No overtaking. Close up to the car in front.")
			else:
				_say("Green flag! Go, go, go!")
		"blue":
			if mine:
				_say("Blue flags. Let the leaders through.")
		"retired":
			if mine:
				_say("That's terminal. We're out. Sorry.")
			else:
				_say("%s is out of the race." % _name_of(int(ev.id)))
		"rain":
			_say("Rain is coming. Intermediates will be quicker soon." if bool(ev.on) else "It's drying out. Slicks soon.")
		"pit_stop":
			if mine:
				_say("Box, box. Stationary.")
		"pit_done":
			if mine:
				_say("Go, go! %s tyres on." % Tyres.NAMES[int(ev.compound)])
		"chequered":
			if mine:
				_flash("WINNER!", 4.0)
		"finished":
			if mine and int(ev.id) != int(scene.race.order[0].id if not scene.race.order.is_empty() else -1):
				_flash("P%d" % driver.entry.position, 4.0)
			if mine:
				_say(_finish_line(driver.entry.position))
		"quali_time":
			pass
		"tt_best":
			var m := int(ev.medal)
			_flash(GameConfig.time_text(float(ev.time)), 2.5)
			if m >= 0:
				_say("New best lap: %s. That's %s." % [GameConfig.time_text(float(ev.time)), LapReference.MEDAL_NAMES[m].to_lower()])
			else:
				_say("New best lap: %s." % GameConfig.time_text(float(ev.time)))
		"rewind":
			_toast.text = "Rewind"
			_toast_t = 1.0
		"radio":
			_say(str(ev.text))


func _lap_radio(ev: Dictionary) -> void:
	var e := driver.entry
	var race := scene.race
	if e.lap == race.laps and not _said.has("last"):
		_said["last"] = true
		_say("Last lap. Bring it home.")
		return
	var idx := race.order.find(e)
	var ahead := ""
	if idx > 0:
		var o: Race.Entry = race.order[idx - 1]
		ahead = " %.1f to %s ahead." % [maxf(0.0, e.gap - o.gap), o.code]
	_say("Lap %d: %s. P%d.%s" % [int(ev.lap), GameConfig.time_text(float(ev.time)), e.position, ahead])


func _quali_place() -> String:
	var board := scene.quali_board()
	for i in board.size():
		if int(board[i].id) == driver.entry.id:
			return "Provisional P%d." % (i + 1)
	return ""


static func _finish_line(position: int) -> String:
	match position:
		1:
			return "You win! Fantastic drive!"
		2, 3:
			return "P%d, on the podium! Great job." % position
	if position <= 10:
		return "P%d. Points on the board." % position
	return "P%d. We'll go again next time." % position


func _name_of(id: int) -> String:
	var e := scene.race.entry(id)
	return e.name if e else "A car"


func _say(text: String) -> void:
	if _radio_queue.size() > 3:
		_radio_queue.pop_front()
	_radio_queue.append(text)


func _flash(text: String, t: float) -> void:
	_banner.text = text
	_banner_t = t


# --- Pieces -------------------------------------------------------------

func _panel(pos: Vector2, preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL))
	p.set_anchors_preset(preset)
	p.position = pos
	add_child(p)
	return p


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * _font_scale))
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 3)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## The dash: speed, gear, a rev bar with shift lights, and badges for DRS,
## the limiter, the tyres and damage.
class Dash:
	extends Control
	var driver: PlayerDriver
	var scale_by := 1.0

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if driver == null:
			return
		var sim := driver.entry.sim
		var s := scale_by
		var w := size.x
		draw_rect(Rect2(Vector2.ZERO, size), RaceHud.PANEL)
		var font := LGTheme.heading_font if LGTheme.heading_font else get_theme_default_font()
		# Revs: twelve lights, green then red then blue.
		var frac := clampf((sim.rpm - 7000.0) / (sim.spec.rpm_limit - 7000.0), 0.0, 1.0)
		var n := 12
		for i in n:
			var on := frac * n > i
			var c := Color("3fdc5a") if i < 5 else (Color("ff4b3e") if i < 9 else Color("4f8bff"))
			if not on:
				c = Color(c, 0.18)
			draw_rect(Rect2(Vector2(14 + i * (w - 28) / n, 10) , Vector2((w - 28) / n - 4, 12 * s)), c)
		var speed := GameConfig.speed_text(absf(sim.forward_speed()))
		draw_string(font, Vector2(14, 92 * s), speed, HORIZONTAL_ALIGNMENT_LEFT, -1, int(54 * s), RaceHud.TEXT)
		draw_string(font, Vector2(16, 116 * s), GameConfig.speed_unit(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), RaceHud.DIM)
		var gear := "N" if sim.gear == 0 else ("R" if sim.reverse else str(sim.gear))
		draw_string(font, Vector2(w - 82 * s, 98 * s), gear, HORIZONTAL_ALIGNMENT_CENTER, 64 * s, int(64 * s), RaceHud.WARN)
		# Badges along the bottom.
		var x := 14.0
		var y := size.y - 14.0 * s
		var drs_col := RaceHud.GOOD if sim.drs_open else (RaceHud.WARN if driver.entry.drs_ok else Color(1, 1, 1, 0.25))
		draw_string(font, Vector2(x, y), "DRS", HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), drs_col)
		x += 54 * s
		var comp := sim.compound
		draw_circle(Vector2(x + 9 * s, y - 6 * s), 9 * s, Tyres.COLORS[comp])
		draw_string(font, Vector2(x + 4 * s, y - 1 * s), Tyres.LETTERS[comp], HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color.BLACK)
		draw_string(font, Vector2(x + 22 * s, y), "%d%%" % roundi((1.0 - sim.wear) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), RaceHud.TEXT)
		x += 80 * s
		if sim.wing_damage > 0.05 or sim.damage > 0.1:
			draw_string(font, Vector2(x, y), "DMG %d%%" % roundi(maxf(sim.wing_damage, sim.damage) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), RaceHud.BAD)


## A map of the circuit with every car on it.
class TrackMap:
	extends Control
	var scene: RaceScene
	var driver: PlayerDriver
	var _pts := PackedVector2Array()
	var _scale := 1.0
	var _centre := Vector2.ZERO

	func setup(p_scene: RaceScene, p_driver: PlayerDriver) -> void:
		scene = p_scene
		driver = p_driver
		var t := scene.track
		var b := t.bounds
		var span := maxf(b.size.x, b.size.z)
		_scale = (minf(size.x, size.y) - 16.0) / maxf(span, 1.0)
		_centre = Vector2(b.get_center().x, b.get_center().z)
		_pts = PackedVector2Array()
		var k := 0
		while k < t.n:
			_pts.append(_to_map(t.pos[k]))
			k += 4
		_pts.append(_pts[0])

	func _to_map(p: Vector3) -> Vector2:
		# Seen from above with +z down the screen, +x is to the left.
		return Vector2(-(p.x - _centre.x), p.z - _centre.y) * _scale + size * 0.5

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if scene == null or scene.race == null or _pts.size() < 2:
			return
		draw_polyline(_pts, Color(0, 0, 0, 0.6), 7.0, true)
		draw_polyline(_pts, Color(0.92, 0.94, 0.97, 0.9), 3.5, true)
		var start := _to_map(scene.track.pos[0])
		draw_circle(start, 4.0, Color.WHITE)
		var mine: Race.Entry = driver.entry
		for e in scene.race.entries:
			if e == mine or e.cleared:
				continue
			draw_circle(_to_map(e.sim.pos), 4.0, Teams.team(e.team).main)
		draw_circle(_to_map(mine.sim.pos), 7.0, Color.BLACK)
		draw_circle(_to_map(mine.sim.pos), 5.5, RaceHud.WARN)


## The five red start lights.
class Lights:
	extends Control
	var lit := 0

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06, 0.85))
		for i in 5:
			var c := Vector2(36 + i * 72, size.y * 0.5)
			draw_circle(c, 24, Color(0.15, 0.02, 0.02))
			if i < lit:
				draw_circle(c, 22, Color(1.0, 0.12, 0.08))
