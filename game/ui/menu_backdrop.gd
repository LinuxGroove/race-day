class_name MenuBackdrop
extends Node3D
## Behind the menus: a few AI cars lapping a circuit, filmed by a slow,
## steady trackside camera that hands from car to car.

const CARS := 6
const SHOT_TIME := 9.0

var track: Track
var race: Race
var views := {}
var camera: Camera3D
var _shot_t := 0.0
var _subject := 0
var _spot := Vector3.ZERO


func _ready() -> void:
	var ids := Circuits.ids()
	var layout := "greenfield" if Circuits.info("greenfield").size() > 0 else str(ids[0])
	var info := Circuits.info(layout)
	track = Circuits.track(layout)
	var view_path := "res://game/world/track_view.gd"
	var tv: Node3D = null
	if ResourceLoader.exists(view_path):
		tv = load(view_path).create(track, info, 0)
	if tv == null:
		tv = DebugRoad.create(track)
	add_child(tv)
	var atmo_path := "res://game/world/atmosphere.gd"
	if ResourceLoader.exists(atmo_path):
		add_child(load(atmo_path).create(str(info.get("time", "day")), 0.0))
	else:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.55, 0.75, 0.95)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.75, 0.8)
		env.environment = e
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		add_child(sun)
	race = Race.new(track, Race.Kind.PRACTICE, 999, randi())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in CARS:
		var team := rng.randi_range(0, Teams.TEAMS.size() - 1)
		var e := race.add_car(-1 - i, "AI", team, i * 2, rng.randf_range(0.9, 0.97), {"consistency": 0.95})
		var v := CarView.create(team)
		add_child(v)
		views[e.id] = v
	race.start()
	# Spread them round the lap.
	for k in race.entries.size():
		var e: Race.Entry = race.entries[k]
		var s := track.length * float(k) / CARS
		e.sim.place_moving(s, track.value_at(track.line_off, s), track.value_at(track.line_speed, s) * 0.8)
		e.s_total = s
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()
	_new_shot()


func _physics_process(_dt: float) -> void:
	race.step(Race.DT)
	for e in race.entries:
		(views[e.id] as CarView).follow(e.sim, Race.DT)


func _process(dt: float) -> void:
	_shot_t += dt
	if _shot_t > SHOT_TIME:
		_new_shot()
	var e: Race.Entry = race.entries[_subject]
	var target := e.sim.pos + Vector3.UP * 0.8
	# A trackside camera that pans to follow, like television.
	var want := Transform3D().looking_at(target - _spot, Vector3.UP)
	camera.global_position = _spot
	camera.basis = camera.basis.slerp(want.basis, clampf(dt * 4.0, 0.0, 1.0)).orthonormalized()


## Picks the next car and a spot beside the road ahead of it.
func _new_shot() -> void:
	_shot_t = 0.0
	_subject = (_subject + 1) % race.entries.size()
	var e: Race.Entry = race.entries[_subject]
	var s := track.wrap_s(e.sim.spot.s + 140.0)
	var side := 1.0 if randf() < 0.5 else -1.0
	var lat := side * (track.value_at(track.half, s) + 9.0)
	_spot = track.world(s, lat) + Vector3.UP * 3.5
	camera.global_position = _spot
	camera.look_at(e.sim.pos + Vector3.UP * 0.8, Vector3.UP)
