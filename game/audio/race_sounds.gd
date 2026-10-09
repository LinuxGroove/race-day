class_name RaceSounds
extends Node
## The race's one-shot sounds and the crowd, plus music and menu sounds
## through LGAudio. Everything is on the "SFX" bus (music on "Music").
##
## In the race scene:
##
##   var sounds := RaceSounds.new()
##   add_child(sounds)
##   sounds.race = race                    # for car positions (cheers, wheel guns)
##   sounds.focus_ids = [player_entry.id]  # whose laps, penalties and warnings are heard
##   for stand in grandstands: sounds.add_grandstand(stand.global_position, 1.0)
##   # each frame, with the events the view drained from the race:
##   sounds.handle_events(events)
##   # before each team radio message:
##   sounds.radio()
##
## handle_events plays: a beep per start light and a higher tone at lights
## out, a lap beep, a chime for a penalty and a softer one for a track limits
## warning (focus cars only), wheel guns at any car's pit stop, and cheers
## from the nearest grandstand when a car takes the lead or finishes on the
## podium (a big one at the chequered flag). Each sound also has its own
## method for scenes that don't run a Race (the Racing School, replays).
##
## Menus, anywhere (static, through the LGAudio autoload):
##
##   RaceSounds.play_music("title")     # or "paddock", "results"
##   RaceSounds.stop_music()
##   RaceSounds.ui("accept")            # move, accept, back, toggle, error, tick

const KENNEY := SoundBank.KENNEY
const MUSIC := {
	"title": KENNEY + "music-loops/time-driving.ogg",
	"paddock": KENNEY + "music-loops/flowing-rocks.ogg",
	"results": KENNEY + "music-loops/mission-plausible.ogg",
}
const MUSIC_DB := -8.0
const UI := {
	"move": KENNEY + "interface-sounds/select_002.ogg",
	"accept": KENNEY + "interface-sounds/confirmation_001.ogg",
	"back": KENNEY + "interface-sounds/back_002.ogg",
	"toggle": KENNEY + "interface-sounds/toggle_001.ogg",
	"error": KENNEY + "interface-sounds/error_004.ogg",
	"tick": KENNEY + "interface-sounds/tick_002.ogg",
}
const UI_DB := -6.0
## Grandstand cheers reach this far (m); further cars get none.
const CHEER_RANGE := 220.0

var race: Race
## The cars whose laps, penalties and warnings this screen hears.
var focus_ids: Array = []
## The crowd murmur's level at each grandstand (dB).
var crowd_db := -10.0

var _stands: Array[AudioStreamPlayer3D] = []
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _timers: Array = []
var _warn_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 12.0
		p.max_distance = 400.0
		p.max_db = 2.0
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	_warn_t = maxf(0.0, _warn_t - delta)
	for i in range(_timers.size() - 1, -1, -1):
		var t: Array = _timers[i]
		t[0] -= delta
		if t[0] <= 0.0:
			_timers.remove_at(i)
			_play_at(t[1], t[2], t[3], t[4])


## Plays the sounds for a batch of Race events (see the class doc).
func handle_events(events: Array) -> void:
	for ev: Dictionary in events:
		var id: int = ev.get("id", -1)
		var mine := focus_ids.has(id)
		match ev.get("type", ""):
			"light":
				start_light(int(ev.get("n", 1)))
			"lights_out":
				lights_out()
			"lap":
				if mine:
					lap()
			"penalty":
				if mine:
					penalty()
			"track_limits", "black_white", "lap_invalid":
				if mine:
					warning()
			"pit_stop":
				var at = _car_pos(id)
				if at != null:
					wheel_guns(at, float(ev.get("time", 2.4)))
			"position":
				if int(ev.get("to", 0)) == 1 and int(ev.get("from", 0)) > 1:
					var at = _car_pos(id)
					if at != null:
						cheer(at)
			"chequered":
				var at = _car_pos(id)
				if at != null:
					cheer(at, true)
			"finished":
				var pos := int(ev.get("position", 99))
				var at = _car_pos(id)
				if at != null and pos > 1 and pos <= 3:
					cheer(at)


## One start light coming on (1 to 5).
func start_light(_n := 1) -> void:
	_sfx("race/light", -6.0)


func lights_out() -> void:
	_sfx("race/lights_out", -5.0)


func lap() -> void:
	_sfx("race/lap", -8.0)


## The radio opening, before a message from the team.
func radio() -> void:
	_sfx("race/radio", -6.0)


func penalty() -> void:
	_sfx("race/penalty", -4.0)


func warning() -> void:
	if _warn_t > 0.0:
		return
	_warn_t = 1.0
	_sfx("race/warning", -5.0)


## Wheel guns at a pit stop: the wheels off at once, back on at the end of
## a stop `stop_time` seconds long.
func wheel_guns(at: Vector3, stop_time := 2.4) -> void:
	var s := SoundBank.stream("race/wheel_guns")
	_play_at(s, at, -2.0, _rng.randf_range(0.97, 1.03))
	_timers.append([maxf(stop_time - 0.9, 0.5), s, at, -2.0, _rng.randf_range(1.0, 1.06)])


## A cheer from the grandstand nearest `near` (if one is in range), or
## from the nearest one at all when `big` (the chequered flag).
func cheer(near: Vector3, big := false) -> void:
	var stand := _nearest_stand(near, INF if big else CHEER_RANGE)
	if stand == null:
		return
	var s := SoundBank.stream("race/cheer_big" if big else "race/cheer")
	_play_at(s, stand.global_position, 0.0 if big else -3.0, _rng.randf_range(0.95, 1.05))


## A grandstand at `at`: a crowd murmur there, and cheers from it. `size`
## scales how far it carries (1 for a normal stand).
func add_grandstand(at: Vector3, size := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = SoundBank.stream("race/crowd")
	p.bus = "SFX"
	p.unit_size = 10.0 * size
	p.max_distance = 180.0 * size
	p.max_db = 0.0
	p.volume_db = crowd_db
	p.attenuation_filter_cutoff_hz = 6000.0
	add_child(p)
	p.global_position = at
	if p.stream:
		p.play(_rng.randf() * p.stream.get_length())
	_stands.append(p)


func clear_grandstands() -> void:
	for p in _stands:
		p.queue_free()
	_stands.clear()


static func play_music(which := "title") -> void:
	var a := _lg_audio()
	if a and MUSIC.has(which):
		a.play_music(MUSIC[which], MUSIC_DB)


static func stop_music() -> void:
	var a := _lg_audio()
	if a:
		a.stop_music()


static func ui(kind: String) -> void:
	var a := _lg_audio()
	if a and UI.has(kind):
		a.play_sfx(UI[kind], UI_DB, 0.03)


static func _lg_audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("LGAudio") if tree else null


## A flat (not positional) one-shot through LGAudio.
func _sfx(name: String, db: float) -> void:
	var a := _lg_audio()
	var s := SoundBank.stream(name)
	if a and s:
		a.play_sfx(s, db)


func _play_at(s: AudioStream, at: Vector3, db: float, pitch: float) -> void:
	if s == null or _pool.is_empty() or not is_inside_tree():
		return
	var p: AudioStreamPlayer3D = null
	for k in _pool.size():
		var c := _pool[(_pool_i + k) % _pool.size()]
		if not c.playing:
			p = c
			break
	if p == null:
		p = _pool[_pool_i % _pool.size()]
	_pool_i += 1
	p.global_position = at
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _car_pos(id: int) -> Variant:
	if race == null:
		return null
	var e := race.entry(id)
	return e.sim.pos if e and e.sim else null


func _nearest_stand(at: Vector3, within: float) -> AudioStreamPlayer3D:
	var best: AudioStreamPlayer3D = null
	var bd := within
	for p in _stands:
		var d := p.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = p
	return best
