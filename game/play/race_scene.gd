class_name RaceScene
extends Node3D
## One race weekend on screen: the circuit, the cars, a view (camera and HUD)
## for each player on this device, and the sessions in order: qualifying
## then the race, or a Time Trial, or a Racing School test.
##
## `config` (set before the scene enters the tree):
##   "mode"        quick, championship, career, time_trial, school or multiplayer
##   "circuit"     a Circuits id
##   "laps"        race laps
##   "qualifying"  none, one_lap or timed
##   "drivers"     the grid from Grid.build (people and AI)
##   "forecast"    [[seconds, rain 0..1], ...]; "wet" the starting wetness
##   "seed", "damage" (0-2), "tyre_wear", "difficulty"
##   "school"      a RacingSchool test (mode school)
##   "title"       what the HUD and results call this event
## Multiplayer: the host runs the race; each device drives its own players'
## cars and sends their state (see RaceNet).

signal session_over(kind: int, results: Array)

const QUALI_SESSION := 8.0 * 60.0
## Knockout qualifying: the three parts' lengths, shortened from the real ones.
const KNOCKOUT_PARTS := [300.0, 240.0, 200.0]

var config := {}
var track: Track
var info := {}
var race: Race
var kind := Race.Kind.RACE
## Sessions still to run, in order.
var sessions: Array = []
var grid_order: Array = []
var quali_results: Array = []
var players: Array = []
var views: Array = []
var car_views := {}
var net: RaceNet
var ghost: GhostLap
var ghost_view: CarView
var best_ghost: GhostLap
var recording := GhostLap.new()
## The Racing School test being driven (mode school).
var school: RacingSchool
var paused := false
var over := false
var world: Node3D
var atmosphere: Node
var track_view: Node3D
var sounds: RaceSounds
var safety_car: Node3D
var _sc_lights: Array = []
var _sc_blink := 0.0

var _rng := RandomNumberGenerator.new()
var _ref_lap := 0.0
var _quali_clock := 0.0
## Knockout qualifying: the part being run (1 to 3, 0 for other formats),
## who is still in, and the rows of those knocked out (best first).
var quali_part := 0
var _ko_alive := {}
var _ko_out: Array = []
## Timed sessions: each person's lap count when the flag fell.
var _flag_laps := {}
var _quali_ai := []
var _rewind: Array = []
var _rewind_t := 0.0
var _results_shown := false
var _hud_layer: CanvasLayer
var _pause_menu: Control
var _results: Control


func _ready() -> void:
	_rng.seed = int(config.get("seed", 1))
	var layout := str(config.get("circuit", "proving"))
	info = Circuits.info(layout)
	track = Circuits.track(layout)
	_build_world()
	RaceSounds.stop_music()
	sounds = RaceSounds.new()
	add_child(sounds)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 1
	add_child(_hud_layer)
	match str(config.get("mode", "quick")):
		"time_trial":
			sessions = [Race.Kind.TIME_TRIAL]
		"school":
			sessions = [Race.Kind.SCHOOL]
		_:
			var q := str(config.get("qualifying", "one_lap"))
			sessions = [Race.Kind.QUALIFYING, Race.Kind.RACE] if q != "none" else [Race.Kind.RACE]
			if q == "knockout":
				sessions = [Race.Kind.QUALIFYING, Race.Kind.QUALIFYING, Race.Kind.QUALIFYING, Race.Kind.RACE]
	grid_order = config.get("drivers", []).duplicate(true)
	if Session.is_networked():
		net = RaceNet.new()
		net.name = "RaceNet"
		add_child(net)
		net.setup(self)
	_next_session()
	Session.report_loaded()


func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var detail := int(LGSettings.get_value("video", "detail"))
	var view_path := "res://game/world/track_view.gd"
	if ResourceLoader.exists(view_path):
		track_view = load(view_path).create(track, info, detail) if load(view_path).has_method("create") else null
	if track_view == null:
		track_view = DebugRoad.create(track)
	world.add_child(track_view)
	var atmo_path := "res://game/world/atmosphere.gd"
	if ResourceLoader.exists(atmo_path):
		atmosphere = load(atmo_path).create(str(info.get("time", "day")), float(config.get("wet", 0.0)))
		world.add_child(atmosphere)
	else:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.55, 0.75, 0.95)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.75, 0.8)
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		world.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 220.0
		world.add_child(sun)


# --- Sessions -------------------------------------------------------------

func _next_session() -> void:
	if sessions.is_empty():
		return
	kind = sessions.pop_front()
	_start_session()


func _start_session() -> void:
	over = false
	if kind == Race.Kind.QUALIFYING and str(config.get("qualifying", "")) == "knockout":
		quali_part += 1
	_results_shown = false
	_rewind.clear()
	var laps := int(config.get("laps", 5))
	if kind != Race.Kind.RACE:
		laps = 999
	race = Race.new(track, kind, laps, int(config.get("seed", 1)) + kind * 101)
	race.authority = net == null or Session.is_host()
	race.damage = int(config.get("damage", 1))
	race.tyre_wear = float(config.get("tyre_wear", 1.0))
	race.wetness = float(config.get("wet", 0.0))
	race.forecast = config.get("forecast", [])
	race.mandatory_compounds = laps >= 8 and kind == Race.Kind.RACE
	race.drs_enabled = kind == Race.Kind.RACE
	var drivers := _drivers_for_session()
	for i in drivers.size():
		var d: Dictionary = drivers[i]
		var opts := {"code": d.code, "nat": d.nat, "number": d.number, "aggression": d.aggression, "consistency": d.consistency}
		if kind == Race.Kind.TIME_TRIAL or kind == Race.Kind.SCHOOL:
			opts["spec_team"] = LapReference.TEAM
		var pace := float(d.pace) if bool(d.bot) else -1.0
		var e := race.add_car(int(d.id), str(d.name), int(d.team), i, pace, opts)
		e.peer = int(d.peer)
		e.seat = int(d.seat)
		e.bot = bool(d.bot)
		# Other devices' players are driven there.
		if not e.bot and e.peer != Session.local_id():
			e.remote = true
	race.start()
	if kind == Race.Kind.SCHOOL:
		_begin_school()
	_sync_car_views()
	_setup_players()
	if kind == Race.Kind.QUALIFYING:
		_prepare_ai_quali()
	if kind == Race.Kind.TIME_TRIAL:
		_prepare_time_trial()
	for v in views:
		v.hud.session_started()
	sounds.race = race
	sounds.focus_ids = []
	for p in players:
		sounds.focus_ids.append(p.entry.id)
	if net:
		net.session_started()


## Who's on track this session: everyone in a race; people only in
## qualifying (the AI's laps are worked out) and Time Trial.
func _drivers_for_session() -> Array:
	if kind == Race.Kind.RACE:
		return grid_order
	var out := []
	for d in grid_order:
		if not bool(d.bot) and (quali_part <= 1 or _ko_alive.has(int(d.id))):
			out.append(d)
	return out


func _sync_car_views() -> void:
	var keep := {}
	for e in race.entries:
		keep[e.id] = true
		if not car_views.has(e.id):
			var v := CarView.create(e.team)
			v.name = "Car%d" % e.id
			world.add_child(v)
			car_views[e.id] = v
			var a := CarAudio.new()
			v.add_child(a)
			a.setup(e.sim.spec, not e.bot and e.peer == Session.local_id())
			v.set_meta("audio", a)
		var cv: CarView = car_views[e.id]
		cv.visible = true
		cv.follow(e.sim, 0.0)
		cv.reset_physics_interpolation()
	for id in car_views.keys():
		if not keep.has(id):
			car_views[id].visible = false


func _setup_players() -> void:
	var locals := []
	for e in race.entries:
		if not e.bot and not e.remote:
			locals.append(e)
	locals.sort_custom(func(a, b): return a.seat < b.seat)
	var first := players.is_empty()
	players.clear()
	for e in locals:
		players.append(PlayerDriver.new(Session.seat_input(e.seat), e, race))
	if first or views.size() != players.size():
		_build_views()
	if school:
		_school_players()
	for i in views.size():
		var pv: PlayerView = views[i]
		if i < players.size():
			var p: PlayerDriver = players[i]
			pv.attach(self, p, car_views[p.entry.id])


func _build_views() -> void:
	for v in views:
		v.queue_free()
	views.clear()
	var n := maxi(1, players.size())
	for i in n:
		var pv := PlayerView.new()
		pv.index = i
		pv.count = n
		_hud_layer.add_child(pv)
		views.append(pv)
	_layout_views()
	# Split screen: each player's camera hears the cars near it.
	AudioBudget.listeners = []
	if views.size() > 1:
		for pv in views:
			AudioBudget.listeners.append(pv.camera)


func _layout_views() -> void:
	var n := views.size()
	for i in n:
		var pv: PlayerView = views[i]
		# Two players split top and bottom, which keeps a wide view of the road.
		pv.anchor_left = 0.0
		pv.anchor_right = 1.0
		pv.anchor_top = float(i) / n
		pv.anchor_bottom = float(i + 1) / n
		pv.offset_left = 0
		pv.offset_right = 0
		pv.offset_top = 2 if i > 0 else 0
		pv.offset_bottom = -2 if i < n - 1 else 0


# --- The tick -----------------------------------------------------------

func _physics_process(dt: float) -> void:
	if race == null or get_tree().paused:
		return
	var frozen := race.phase == Race.Phase.GRID or race.phase == Race.Phase.LIGHTS
	for p in players:
		p.drive(Race.DT, frozen)
	if net:
		net.before_step()
	race.step(Race.DT)
	if net:
		net.after_step()
	for e in race.entries:
		var cv: CarView = car_views.get(e.id)
		if cv:
			cv.follow(e.sim, Race.DT)
			if cv.has_meta("audio"):
				(cv.get_meta("audio") as CarAudio).update(e.sim, e.input.throttle, Race.DT)
	if kind == Race.Kind.QUALIFYING:
		_quali_tick(Race.DT)
	if kind == Race.Kind.TIME_TRIAL:
		_time_trial_tick(Race.DT)
	if school:
		school.tick(Race.DT)
	_rewind_tick(Race.DT)
	var events := race.drain_events()
	sounds.handle_events(events)
	for ev in events:
		_on_event(ev)
		for v in views:
			v.hud.on_event(ev)
		if net:
			net.on_event(ev)
	_check_over()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _results_shown:
		get_viewport().set_input_as_handled()
		toggle_pause()


func _process(_dt: float) -> void:
	_show_safety_car(_dt)
	for i in players.size():
		var p: PlayerDriver = players[i]
		if i >= views.size():
			continue
		var pv: PlayerView = views[i]
		if get_tree().paused:
			continue
		if p.seat.just_pressed("camera"):
			pv.next_camera()
		if p.seat.just_pressed("tower"):
			pv.hud.toggle_tower()
		if p.seat.just_pressed("rewind"):
			rewind()
		pv.camera.look_back = p.seat.held("look_back")
		pv.camera.look = p.seat.strength("look_right") - p.seat.strength("look_left")


func toggle_pause() -> void:
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.close()
		return
	_pause_menu = PauseMenu.new()
	_pause_menu.scene = self
	_hud_layer.add_child(_pause_menu)
	# Online and LAN races keep running; the menu sits on top.
	if not Session.is_networked():
		get_tree().paused = true


func on_pause_closed() -> void:
	_pause_menu = null
	get_tree().paused = false
	for p in players:
		p.refresh()


func _on_event(ev: Dictionary) -> void:
	match str(ev.type):
		"contact":
			for k in ["a", "b"]:
				var cv: CarView = car_views.get(int(ev[k]))
				if cv and cv.has_meta("audio"):
					(cv.get_meta("audio") as CarAudio).hit(float(ev.speed))
		"lap":
			if kind == Race.Kind.TIME_TRIAL:
				_time_trial_lap(ev)
			if school:
				school.on_lap(ev)


func _check_over() -> void:
	if over:
		return
	match kind:
		Race.Kind.RACE:
			if race.is_over():
				_session_done()
			elif race.leader_finished_t >= 0.0 and _people_done():
				# Everyone on this device has finished: the rest are classified
				# where they run when the field comes home.
				pass
		Race.Kind.QUALIFYING:
			if _quali_done():
				_session_done()
		Race.Kind.SCHOOL:
			if school and school.done:
				over = true
				_results_shown = true
				if _pause_menu and is_instance_valid(_pause_menu):
					_pause_menu.queue_free()
				_results = ResultsPanel.new()
				_results.scene = self
				_results.school = school.result
				_hud_layer.add_child(_results)


func _people_done() -> bool:
	for p in players:
		if not p.entry.finished and not p.entry.retired:
			return false
	return true


func _session_done() -> void:
	over = true
	var res := _session_results()
	session_over.emit(kind, res)
	if kind == Race.Kind.QUALIFYING:
		quali_results = res
		_apply_quali_grid(res)
		_show_results(res, true)
	else:
		_show_results(res, false)


func _session_results() -> Array:
	if kind == Race.Kind.QUALIFYING:
		var rows := []
		for e in race.entries:
			rows.append({"id": e.id, "name": e.name, "code": e.code, "team": e.team, "nat": e.nat, "best": e.best_lap, "bot": false})
		for q in _quali_ai:
			rows.append({"id": q.d.id, "name": q.d.name, "code": q.d.code, "team": q.d.team, "nat": q.d.nat, "best": q.time, "bot": true})
		rows.sort_custom(func(a, b): return (float(a.best) if float(a.best) > 0.0 else INF) < (float(b.best) if float(b.best) > 0.0 else INF))
		if quali_part > 0:
			rows = _knockout(rows)
		for i in rows.size():
			rows[i]["position"] = i + 1
		return rows
	return race.results()


## Knockout: the slowest in each of the first two parts are out, and keep
## their places at the back of the grid.
func _knockout(rows: Array) -> Array:
	var n := grid_order.size()
	var cut := maxi(1, roundi(n / 4.0))
	var keep := rows.size() if quali_part >= 3 else maxi(1, rows.size() - cut)
	_ko_alive.clear()
	for i in rows.size():
		if i < keep:
			_ko_alive[int(rows[i].id)] = true
	var out := rows.slice(keep)
	var full := rows + _ko_out
	_ko_out = out + _ko_out
	# Nobody left to drive the next part: go straight to the race.
	var people_in := false
	for d in grid_order:
		if not bool(d.bot) and _ko_alive.has(int(d.id)):
			people_in = true
	if quali_part < 3 and not people_in:
		while not sessions.is_empty() and sessions[0] == Race.Kind.QUALIFYING:
			sessions.pop_front()
	return full


func _apply_quali_grid(rows: Array) -> void:
	var by_id := {}
	for d in grid_order:
		by_id[int(d.id)] = d
	var ordered := []
	for r in rows:
		if by_id.has(int(r.id)):
			ordered.append(by_id[int(r.id)])
	grid_order = ordered


func _show_results(rows: Array, qualifying: bool) -> void:
	_results_shown = true
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_results = ResultsPanel.new()
	_results.scene = self
	_results.rows = rows
	_results.qualifying = qualifying
	_hud_layer.add_child(_results)


## The results panel's "Continue": the next session, or the end of the weekend.
func continue_weekend() -> void:
	if _results:
		_results.queue_free()
		_results = null
	if not sessions.is_empty():
		if net and not Session.is_host():
			return
		_next_session()
		if net:
			net.next_session()
		return
	Session.weekend_done(config, race.results() if kind == Race.Kind.RACE else [])


## A client: the host moved the weekend on to its next session.
func continue_from_host() -> void:
	if _results:
		_results.queue_free()
		_results = null
	_next_session()


## Leaves the weekend for the menus (from the pause menu).
func quit_to_menu() -> void:
	get_tree().paused = false
	Session.quit_race()


## Restarts the current session (solo only).
func restart_session() -> void:
	if Session.is_networked():
		return
	get_tree().paused = false
	_pause_menu = null
	if _results:
		_results.queue_free()
		_results = null
	if kind == Race.Kind.QUALIFYING and quali_part > 0:
		quali_part -= 1
	_start_session()


# --- Qualifying ---------------------------------------------------------

func _prepare_ai_quali() -> void:
	_quali_clock = 0.0
	_flag_laps.clear()
	_ref_lap = LapReference.time(track)
	_quali_ai.clear()
	var timed := is_timed_quali()
	var length := quali_length()
	for d in grid_order:
		if not bool(d.bot):
			continue
		if quali_part > 1 and not _ko_alive.has(int(d.id)):
			continue
		var t := Grid.estimate_lap(_ref_lap, d, _rng, race.wetness)
		# The track rubbers in: each knockout part is a little quicker.
		t *= 1.0 - 0.003 * maxi(0, quali_part - 1)
		# One-lap: the AI's laps go up as the session runs; timed: spread
		# over the session.
		var at := _rng.randf_range(20.0, 120.0) if not timed else _rng.randf_range(length * 0.2, length - 25.0)
		_quali_ai.append({"d": d, "time": t, "at": at, "shown": false})


func is_timed_quali() -> bool:
	return str(config.get("qualifying", "one_lap")) in ["timed", "knockout"]


func quali_length() -> float:
	if quali_part > 0:
		return KNOCKOUT_PARTS[quali_part - 1]
	return QUALI_SESSION


## "Q1", "Q2" or "Q3" in knockout qualifying, else "".
func quali_part_name() -> String:
	return "Q%d" % quali_part if quali_part > 0 else ""


## What the results panel's button starts next.
func next_session_name() -> String:
	if sessions.is_empty():
		return ""
	if sessions[0] == Race.Kind.QUALIFYING:
		return "Q%d" % (quali_part + 1)
	return "the race"


func _quali_tick(dt: float) -> void:
	_quali_clock += dt
	for q in _quali_ai:
		if not q.shown and _quali_clock >= float(q.at):
			q.shown = true
			for v in views:
				v.hud.on_event({"type": "quali_time", "name": q.d.name, "code": q.d.code, "time": q.time, "id": q.d.id})


func _quali_done() -> bool:
	if is_timed_quali():
		if _quali_clock < quali_length():
			return false
		# People can finish a flying lap they started before the flag.
		for e in race.entries:
			if e.bot:
				continue
			if not _flag_laps.has(e.id):
				_flag_laps[e.id] = e.lap
			var on_lap: bool = e.lap >= 1 and e.lap_valid and not e.sim.spot.in_pit and e.sim.speed > 5.0
			if on_lap and e.lap == int(_flag_laps[e.id]) and race.time - e.lap_start < _ref_lap * 1.4:
				return false
		return true
	# One flying lap each: done when every person has set (or blown) a lap.
	for e in race.entries:
		if e.bot:
			continue
		if e.lap < 2:
			return false
	return true


func quali_clock_left() -> float:
	if not is_timed_quali():
		return -1.0
	return maxf(0.0, quali_length() - _quali_clock)


## Qualifying times posted so far (for the HUD's board): [{code, name, time}].
func quali_board() -> Array:
	var rows := []
	for q in _quali_ai:
		if q.shown:
			rows.append({"id": q.d.id, "code": q.d.code, "name": q.d.name, "time": q.time, "team": q.d.team})
	for e in race.entries:
		if e.best_lap > 0.0:
			rows.append({"id": e.id, "code": e.code, "name": e.name, "time": e.best_lap, "team": e.team})
	rows.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return rows


# --- Time Trial ---------------------------------------------------------

func _prepare_time_trial() -> void:
	_ref_lap = LapReference.time(track)
	best_ghost = Progress.load_ghost(track.id) if bool(LGSettings.get_value("play", "ghost")) else null
	recording.clear()
	recording.layout = track.id
	if best_ghost and best_ghost.sample_count() > 0:
		if ghost_view == null:
			ghost_view = CarView.create(best_ghost.team)
			ghost_view.name = "Ghost"
			world.add_child(ghost_view)
			_ghostify(ghost_view)
		ghost_view.visible = false


func _ghostify(v: Node) -> void:
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(mi as MeshInstance3D).material_override = m
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _time_trial_tick(dt: float) -> void:
	if players.is_empty():
		return
	var e: Race.Entry = players[0].entry
	if e.lap >= 1:
		recording.record(e.sim, dt)
	if ghost_view and best_ghost and e.lap >= 1:
		var t := race.time - e.lap_start
		ghost_view.visible = t < best_ghost.time + 2.0
		var smp := best_ghost.sample(t)
		ghost_view.global_transform = Transform3D(Basis(Vector3.UP, float(smp[1])), smp[0])


func _time_trial_lap(ev: Dictionary) -> void:
	if players.is_empty() or int(ev.id) != players[0].entry.id:
		return
	var lap := float(ev.time)
	var valid := bool(ev.valid)
	if valid:
		recording.time = lap
		recording.team = players[0].entry.team
		if Progress.record_time_trial(track.id, lap, recording, players[0].assist_count()):
			best_ghost = recording
			recording = GhostLap.new()
			recording.layout = track.id
			if ghost_view == null:
				ghost_view = CarView.create(best_ghost.team)
				world.add_child(ghost_view)
				_ghostify(ghost_view)
			for v in views:
				v.hud.on_event({"type": "tt_best", "time": lap, "medal": LapReference.medal_for(track, lap)})
			Session.submit_time_trial(track.id, lap)
			recording.clear()
			return
	recording.clear()
	recording.layout = track.id


func medals() -> Array:
	return LapReference.medals(track)


# --- The safety car ---------------------------------------------------------

func _show_safety_car(dt: float) -> void:
	if race == null or not race.sc:
		if safety_car:
			safety_car.visible = false
		return
	if safety_car == null:
		safety_car = Node3D.new()
		safety_car.name = "SafetyCar"
		var body: Node3D = load("res://assets/kenney/car-kit/sedan-sports.glb").instantiate()
		body.scale = Vector3.ONE * 2.1
		safety_car.add_child(body)
		for side in [-1.0, 1.0]:
			var light := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.7, 0.18, 0.3)
			light.mesh = box
			light.position = Vector3(side * 0.4, 2.05, -0.3)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("ffb21f")
			m.emission_enabled = true
			m.emission = Color("ffb21f")
			light.material_override = m
			safety_car.add_child(light)
			_sc_lights.append(m)
		world.add_child(safety_car)
	safety_car.visible = true
	var s := race.safety_car_s()
	var lat := track.value_at(track.line_off, s)
	var p := track.world(s, lat)
	safety_car.global_transform = Transform3D(Basis(Vector3.UP, track.heading_at(s)), p)
	_sc_blink += dt
	for k in _sc_lights.size():
		var on := int(_sc_blink * 3.0) % 2 == k
		(_sc_lights[k] as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.0


# --- Racing School -----------------------------------------------------

func _begin_school() -> void:
	if school == null:
		school = RacingSchool.new(self, str(config.get("school", "")))
	for e in race.entries:
		if not e.bot:
			school.begin(e)
			break


## Fixes the assists a test is about, and asks for the stop in the pit test.
func _school_players() -> void:
	for p in players:
		p.overrides = school.test.get("assists", {})
		p.refresh()
		p.pit_requested = str(school.test.kind) == "pit"


# --- Rewind -------------------------------------------------------------

## Snapshots every half second for the last 10 s (offline races only).
func _rewind_tick(dt: float) -> void:
	if Session.is_networked() or school != null or not bool(LGSettings.get_value("assists", "rewind")):
		return
	if race.phase != Race.Phase.RACING:
		return
	_rewind_t += dt
	if _rewind_t < 0.5:
		return
	_rewind_t = 0.0
	_rewind.append(race.snapshot())
	if _rewind.size() > 20:
		_rewind.pop_front()


## Goes back about three seconds.
func rewind() -> void:
	if Session.is_networked() or school != null or not bool(LGSettings.get_value("assists", "rewind")) or _rewind.size() < 2:
		return
	var back := mini(6, _rewind.size() - 1)
	var snap: Dictionary = _rewind[_rewind.size() - 1 - back]
	_rewind.resize(_rewind.size() - back)
	race.restore(snap)
	recording.clear()
	for e in race.entries:
		var cv: CarView = car_views.get(e.id)
		if cv:
			cv.follow(e.sim, 1.0)
			cv.reset_physics_interpolation()
	for v in views:
		v.hud.on_event({"type": "rewind"})
		v.camera.set_view(v.camera.view)


# --- Network ------------------------------------------------------------

func on_player_left(peer: int) -> void:
	if race == null:
		return
	for e in race.entries:
		if e.peer == peer and not e.bot:
			# Their car is taken over by the AI so the race goes on.
			e.remote = false
			e.bot = true
			e.ai = AiDriver.new(e.sim, race.speeds_for(e.team), e.id)
			e.ai.pace = 0.95
			e.ai.profile_grip = race.reference_grip()
			e.ai.box_s = race.box_for(e.team)


func _exit_tree() -> void:
	AudioBudget.listeners = []
