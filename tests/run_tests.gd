extends Node
## Headless tests: run with
##   godot --headless --path . tests/run_tests.tscn
## Add `-- --games=N` to race N whole AI races (default 1), each on the next
## circuit of the calendar, and `--only=_test_name` to run one test.
## Exits non-zero on failure.

var failures := 0
var checks := 0
var games := 1
var only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = maxi(0, arg.substr(8).to_int())
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGTheme.apply(get_tree().root)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGSettings.set_value("player", "name", "Tester", false)
	# Keep the player's own progress out of it.
	Progress.save_path = "user://test_progress.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.load_progress()
	await get_tree().process_frame
	for t in ["_test_circuits", "_test_teams", "_test_weather", "_test_ghost", "_test_lap_reference",
			"_test_session_config", "_test_progress", "_test_snapshot", "_test_safety_car", "_test_net_pack",
			"_test_school_stretches", "_test_menus", "_test_race_scene", "_test_school_run", "_test_knockout", "_test_races"]:
		if only != "" and t != only:
			continue
		printerr("- ", t)
		await call(t)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	print("%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAILED: ", what)


# --- Data -----------------------------------------------------------------

func _test_circuits() -> void:
	var ids := Circuits.ids()
	check(ids.size() >= 1, "there are circuits")
	check(Circuits.calendar().size() >= 1 or ids.size() == 1, "there's a calendar")
	for id in ids:
		var info := Circuits.info(id)
		check(str(info.get("name", "")) != "", "%s has a name" % id)
		var t := Circuits.track(id)
		check(t != null and t.length > 900.0, "%s builds (%.0f m)" % [id, t.length if t else 0.0])
		if t == null:
			continue
		check(t.corners.size() >= 3, "%s has corners" % id)
		check(t.grid.size() >= GameConfig.GRID_SIZE, "%s has %d grid slots" % [id, t.grid.size()])
		var slowest := INF
		for v in t.line_speed:
			slowest = minf(slowest, v)
		check(slowest > 8.0, "%s: the racing line never stops (%.1f m/s)" % [id, slowest])
		if int(info.get("round", 0)) > 0:
			check(not t.pit.is_empty(), "%s has a pit lane" % id)


func _test_teams() -> void:
	check(Teams.TEAMS.size() == 10, "ten teams")
	check(Teams.DRIVERS.size() >= 20, "twenty AI drivers")
	check(Teams.team_index("tankco") == Teams.TEAMS.size() - 1, "Tankco is the slowest team")
	var total := 0
	for p in range(1, 21):
		total += Teams.points_for(p)
	check(total == 101, "points for the top ten add up to 101")
	for i in Teams.TEAMS.size():
		check(CarView.CHASSIS.has(str(Teams.team(i).chassis)), "%s has a chassis" % Teams.team(i).name)


func _test_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	check(Weather.make("dry", 1.0, rng).wet == 0.0, "dry is dry")
	check(Weather.make("wet", 0.0, rng).wet >= 0.5, "wet is wet")
	var mixed := Weather.make("mixed", 0.0, rng)
	check(mixed.wet == 0.0 and mixed.forecast.size() >= 3, "a changeable forecast starts dry and rains later")


func _test_ghost() -> void:
	var t := Circuits.track(Circuits.ids()[0])
	var sim := CarSim.new(Teams.spec_for(5), t)
	sim.place_moving(100.0, 0.0, 40.0)
	var g := GhostLap.new()
	for k in 240:
		sim.pos += Vector3(sim.vel.x, 0, sim.vel.y) * Race.DT
		g.record(sim, Race.DT)
	g.time = 2.0
	var back := GhostLap.from_dict(g.to_dict())
	check(back.sample_count() == g.sample_count() and back.sample_count() > 30, "a ghost survives saving")
	var a: Vector3 = g.sample(1.0)[0]
	var b: Vector3 = back.sample(1.0)[0]
	check(a.distance_to(b) < 0.01, "a saved ghost replays in the same place")


func _test_lap_reference() -> void:
	var t := Circuits.track(Circuits.ids()[0])
	var lap := LapReference.measure(t)
	check(lap > t.length / 90.0 and lap < t.length / 25.0, "the reference lap is a plausible time (%.1f s for %.0f m)" % [lap, t.length])
	var m := LapReference.medals(t)
	check(float(m[0]) < float(m[1]) and float(m[1]) < float(m[2]), "medal times get easier")


# --- Session and progress ---------------------------------------------------

func _test_session_config() -> void:
	Session.start_solo()
	var config := Session.make_config(Session.local_people(), Session.settings, "quick", 7)
	var drivers: Array = config.drivers
	check(drivers.size() == int(Session.settings.grid), "the grid is full (%d)" % drivers.size())
	var ids := {}
	var people := 0
	for d in drivers:
		ids[int(d.id)] = true
		if not bool(d.bot):
			people += 1
	check(ids.size() == drivers.size(), "every driver has their own id")
	check(people == 1, "one person on a solo grid")
	var teams := {}
	for d in drivers:
		teams[int(d.team)] = int(teams.get(int(d.team), 0)) + 1
	var two_each := true
	for k in teams:
		if int(teams[k]) > 2:
			two_each = false
	check(two_each, "no team runs more than two cars")
	Session.leave()


func _test_progress() -> void:
	var cal := Array(Circuits.calendar())
	if cal.is_empty():
		cal = [Circuits.ids()[0]]
	Progress.start_championship(cal.slice(0, 2), 3, 70.0, "none")
	var config := Progress.championship_config()
	check(str(config.circuit) == str(cal[0]), "the championship starts at round one")
	var results := []
	for i in 20:
		var id := Progress.PLAYER_ID if i == 2 else -1 - i
		results.append({"id": id, "name": "D%d" % i, "code": "D%02d" % i, "team": i / 2, "points": Teams.points_for(i + 1), "position": i + 1})
	Progress.record_championship_round(config, results)
	var c := Progress.championship()
	check(int(c.round) == 1, "a round is recorded")
	check(Progress.standing_of(c, Progress.PLAYER_ID) == 3, "third in the race is third in the standings")
	Progress.end_championship()
	check(Progress.championship().is_empty(), "a championship can be ended")
	Progress.start_career(3, 70.0)
	var career := Progress.career()
	check(int(career.team) == Teams.team_index("tankco"), "a career starts at Tankco")
	for r in Progress.career().season_state.calendar.size():
		Progress.record_career_round(Progress.career_config(), results)
	career = Progress.career()
	check(not career.offers.is_empty(), "third every week brings offers from better teams")
	var upgraded := int(career.upgrades.engine) + int(career.upgrades.aero) + int(career.upgrades.brakes)
	check(upgraded > 0, "the team develops the car through the season")
	var offer := int(career.offers[0]) if not career.offers.is_empty() else 0
	Progress.next_career_season(offer)
	check(int(Progress.career().season) == 2 and int(Progress.career().team) == offer, "a new season with a new team")
	Progress.end_career()
	check(Progress.record_school("brake", 2) and not Progress.record_school("brake", 2) and Progress.record_school("brake", 0), "school medals only get better")


# --- The race -------------------------------------------------------------

func _test_snapshot() -> void:
	var t := Circuits.track(Circuits.ids()[0])
	var race := Race.new(t, Race.Kind.RACE, 3, 11)
	for i in 6:
		race.add_car(-1 - i, "AI %d" % i, i, i, 0.9)
	race.start()
	while race.phase != Race.Phase.RACING or race.time < 4.0:
		race.step(Race.DT)
	var snap := race.snapshot()
	var where: Vector3 = race.entries[0].sim.pos
	var when := race.time
	for k in 600:
		race.step(Race.DT)
	check(race.entries[0].sim.pos.distance_to(where) > 50.0, "cars move on")
	race.restore(snap)
	check(race.entries[0].sim.pos.distance_to(where) < 0.01 and is_equal_approx(race.time, when), "the rewind puts everything back")


## The safety car bunches the field up without anyone passing, then goes in.
func _test_safety_car() -> void:
	var t := Circuits.track(Circuits.ids()[0])
	var race := Race.new(t, Race.Kind.RACE, 10, 21)
	for i in 10:
		race.add_car(-1 - i, "AI %d" % i, i, i, 0.85 + i * 0.01)
	race.start()
	while race.phase != Race.Phase.RACING or race.time < 40.0:
		race.step(Race.DT)
	race.deploy_safety_car()
	var spread_before: float = race.order[0].s_total - race.order[race.order.size() - 1].s_total
	var before := []
	for e in race.order:
		before.append(e.id)
	for k in 120 * 50:
		race.step(Race.DT)
	var after := []
	for e in race.order:
		after.append(e.id)
	var spread: float = race.order[0].s_total - race.order[race.order.size() - 1].s_total
	check(race.sc, "the safety car is still out")
	var widest := 0.0
	for k in range(1, race.order.size()):
		widest = maxf(widest, race.order[k - 1].s_total - race.order[k].s_total)
	check(widest < 70.0, "the field queues up close behind (widest gap %.0f m, %.0f m to %.0f m in all)" % [widest, spread_before, spread])
	check(after == before, "nobody passes behind the safety car")
	check(race.safety_car_s() >= 0.0 and race.sc_s > race.order[0].s_total, "the leader stays behind the safety car")
	var limit := race.time + 200.0
	while race.sc and race.time < limit:
		race.step(Race.DT)
	check(not race.sc, "the safety car comes in")


func _test_net_pack() -> void:
	var t := Circuits.track(Circuits.ids()[0])
	var race := Race.new(t, Race.Kind.RACE, 3, 1)
	var a := race.add_car(4, "A", 2, 0, -1.0)
	var b := race.add_car(8, "B", 2, 1, -1.0)
	a.sim.place_moving(300.0, 1.0, 50.0)
	a.sim.gear = 6
	a.sim.wear = 0.3
	var net := RaceNet.new()
	net._unpack(b, RaceNet._pack(a), true)
	check(b.sim.pos.distance_to(a.sim.pos) < 0.01 and b.sim.gear == 6 and is_equal_approx(b.sim.wear, 0.3), "a car's state crosses the network")
	net.free()


func _test_school_stretches() -> void:
	for id in Circuits.ids():
		var t := Circuits.track(id)
		for test in RacingSchool.TESTS:
			if not str(test.kind) in ["segment", "overtake"]:
				continue
			var st := RacingSchool.stretch(t, test)
			check(float(st[1]) > 150.0 and float(st[1]) < t.length, "%s: %s covers a stretch (%.0f m)" % [id, test.id, st[1]])


func _test_menus() -> void:
	for page in ["", "championship", "career", "time_trial", "school"]:
		var title: Node = load("res://game/ui/title.tscn").instantiate()
		title.set("open_page", page)
		add_child(title)
		await get_tree().process_frame
		check(title.get_child_count() > 1, "the title opens%s" % (" at " + page if page != "" else ""))
		title.queue_free()
		await get_tree().process_frame
	Session.start_solo()
	var lobby: Node = load("res://game/ui/lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().process_frame
	check(lobby.get_child_count() > 1, "the lobby opens")
	lobby.queue_free()
	await get_tree().process_frame
	Session.leave()


## A race weekend on screen: the scene builds, the lights go out and the
## player's car (on autopilot) gets going.
func _test_race_scene() -> void:
	Session.start_solo()
	var settings: Dictionary = Session.settings.duplicate()
	settings.circuit = Circuits.ids()[0]
	settings.qualifying = "none"
	settings.laps = 2
	settings.weather = "dry"
	var scene: RaceScene = load("res://game/play/race_scene.tscn").instantiate()
	scene.config = Session.make_config(Session.local_people(), settings, "quick", 5)
	add_child(scene)
	await get_tree().process_frame
	check(scene.players.size() == 1 and scene.views.size() == 1, "one player and one view")
	check(scene.car_views.size() == int(settings.grid), "every car is on screen")
	for p in scene.players:
		p.autopilot = true
	var frames := 0
	while (scene.race.phase != Race.Phase.RACING or scene.race.time < 4.0) and frames < 3000:
		await get_tree().physics_frame
		frames += 1
	var me: Race.Entry = scene.players[0].entry
	check(scene.race.phase == Race.Phase.RACING, "the lights go out")
	check(me.sim.speed > 20.0, "the player's car gets going (%.0f m/s)" % me.sim.speed)
	for v in GameConfig.CAMERAS:
		scene.views[0].camera.set_view(v)
		await get_tree().process_frame
		check(scene.views[0].camera.global_position.distance_to(me.sim.pos) < 15.0, "the %s camera is with the car" % v)
	scene.toggle_pause()
	check(get_tree().paused, "the pause menu pauses")
	scene.toggle_pause()
	await get_tree().process_frame
	check(not get_tree().paused, "and resumes")
	scene.queue_free()
	await get_tree().process_frame
	Session.leave()


## A Racing School test driven by the autopilot earns a medal.
func _test_school_run() -> void:
	Session.start_solo()
	var test := RacingSchool.find("brake")
	var config := Session.make_config([Session.local_people()[0]], {"circuit": RacingSchool.circuit_for(test), "grid": 1, "weather": "dry"}, "school")
	config.drivers = Grid.build([Session.local_people()[0]], 1, 100.0)
	config.forecast = []
	config.wet = 0.0
	config.qualifying = "none"
	config.school = "brake"
	var scene: RaceScene = load("res://game/play/race_scene.tscn").instantiate()
	scene.config = config
	add_child(scene)
	await get_tree().process_frame
	for p in scene.players:
		p.autopilot = true
	var frames := 0
	while not scene.school.done and frames < 120 * 60:
		await get_tree().physics_frame
		frames += 1
	check(scene.school.done, "the test ends")
	check(bool(scene.school.result.get("passed", false)), "the autopilot passes it: %s" % scene.school.result)
	scene.queue_free()
	await get_tree().process_frame
	Session.leave()


## Knockout qualifying: the player drives Q1 on autopilot (shortened), the
## slowest five go out each part, and the grid comes from all three.
func _test_knockout() -> void:
	Session.start_solo()
	var settings: Dictionary = Session.settings.duplicate()
	settings.circuit = Circuits.ids()[0]
	settings.qualifying = "knockout"
	settings.difficulty = 40
	var scene: RaceScene = load("res://game/play/race_scene.tscn").instantiate()
	scene.config = Session.make_config(Session.local_people(), settings, "quick", 9)
	add_child(scene)
	await get_tree().process_frame
	check(scene.kind == Race.Kind.QUALIFYING and scene.quali_part == 1, "knockout starts with Q1")
	for part in 3:
		if scene.kind != Race.Kind.QUALIFYING:
			break
		# Skip the clock to the flag: everyone's AI lap is in.
		scene._quali_clock = scene.quali_length()
		var frames := 0
		while not scene.over and frames < 600:
			await get_tree().physics_frame
			frames += 1
		check(scene.over, "Q%d ends at the flag" % (part + 1))
		var rows: Array = scene.quali_results
		check(rows.size() == scene.grid_order.size(), "Q%d classifies the whole grid" % (part + 1))
		scene.continue_weekend()
		await get_tree().process_frame
	check(scene.kind == Race.Kind.RACE, "the race follows qualifying")
	check(scene.grid_order.size() == int(settings.grid), "the grid is full")
	scene.queue_free()
	await get_tree().process_frame
	Session.leave()


## Whole races between AI drivers, with no scene: they finish, nobody is
## stuck, and the results add up.
func _test_races() -> void:
	var cal := Array(Circuits.calendar())
	if cal.is_empty():
		cal = Array(Circuits.ids())
	for g in games:
		var id: String = cal[g % cal.size()]
		var t := Circuits.track(id)
		var race := Race.new(t, Race.Kind.RACE, 2, 100 + g)
		var drivers := Grid.build([], GameConfig.GRID_SIZE, 70.0, g)
		for i in drivers.size():
			var d: Dictionary = drivers[i]
			race.add_car(int(d.id), str(d.name), int(d.team), i, float(d.pace), {"aggression": d.aggression, "consistency": d.consistency})
		race.start()
		var limit := t.length * 2.0 / 30.0 + 240.0
		var started := Time.get_ticks_msec()
		while not race.is_over() and race.clock < limit:
			race.step(Race.DT)
			race.drain_events()
		var res := race.results()
		var finished := 0
		var retired := 0
		for r in res:
			if str(r.status) == "Retired":
				retired += 1
			else:
				finished += 1
		print("  %s: winner %s in %.1f s, %d classified, %d retired, %d stops (%.1f s to run)" % [id, res[0].name, float(res[0].time), finished, retired,
			res.reduce(func(a, r): return a + int(r.stops), 0), (Time.get_ticks_msec() - started) / 1000.0])
		check(race.is_over(), "%s: the race finishes" % id)
		check(retired <= 3, "%s: few retirements (%d)" % [id, retired])
		var positions := {}
		for r in res:
			positions[int(r.position)] = true
		check(positions.size() == res.size(), "%s: every position is taken once" % id)
		var pts := 0
		for r in res:
			pts += int(r.points)
		check(pts >= 101 and pts <= 102, "%s: the points add up (%d)" % [id, pts])
		await get_tree().process_frame
