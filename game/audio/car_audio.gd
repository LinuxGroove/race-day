class_name CarAudio
extends Node3D
## Everything one car sounds like: the engine (EngineSynth's baked loops,
## crossfaded and pitched by rpm, with gear-change cuts, pops, the rev and
## pit limiters, the turbo and the hybrid whine), tyres squealing and
## scrubbing, kerbs, gravel and grass, wind, spray in the wet, scraping a
## wall and thumps on contact. All on the "SFX" bus, positioned in 3D.
##
## Attach it under the car's visual node (it follows the node), then:
##
##   var audio := CarAudio.new()
##   car_visual.add_child(audio)
##   audio.setup(entry.sim.spec, is_local_driver)
##   # each rendered frame (from _process), after the race has stepped:
##   audio.update(entry.sim, entry.input.throttle, delta)
##   # when the camera changes (the cockpit camera is inside):
##   audio.set_view(camera_is_cockpit)
##   # for a "contact" event from Race.drain_events() on this car:
##   audio.hit(event.speed)
##
## `is_player` cars (the people driving on this device) always play every
## layer. Other cars play the engine, tyres, kerbs and surfaces, and only the
## nearest AudioBudget.max_ai of them at once (see AudioBudget; for split
## screen set AudioBudget.listeners to the players' cameras). Other cars get
## a Doppler shift from their own velocity and the listener's.
##
## `update` can run every frame or every physics tick. Wall hits are caught
## from `sim.wall_t` even between calls; contact with other cars only shows
## in `sim.impact` for one tick, so pass the race's "contact" events to
## `hit()` if update runs once a frame. With audio off (headless runs use the
## dummy driver) it all still runs, silently, and a missing sound file only
## leaves that layer quiet.

const BUS := "SFX"
const COCKPIT_BUS := "Cockpit"
const SPEED_OF_SOUND := 343.0
## Layer levels (dB) on top of each sound's baked level.
const TRIM := {
	"engine": 0.0, "limiter": 0.0, "pit": -2.0, "turbo": -3.0, "drive": -3.0,
	"pop": -5.0, "squeal": -5.0, "scrub": -6.0, "kerb": -1.0, "gravel": -4.0,
	"grass": -7.0, "wind": -8.0, "spray": -9.0, "scrape": -5.0, "thump": -1.0,
}
## How loud the cockpit is: the exhaust is behind and muffled by the bus's
## filter, the intake, turbo and gears are right behind the driver's head.
## (The engine's level applies to the whines and limiters as well.)
const INSIDE := {"engine": -3.0, "turbo": 6.0, "drive": 7.0, "wind": 3.0, "squeal": 2.0}
## Headroom for a pack of cars, and the people's own cars a little quieter
## still: they are always right next to the camera.
const MASTER_DB := -6.0
const OWN_CAR_DB := -3.0

var spec: CarSpec
var is_player := false
## Set by AudioBudget: whether this (non-player) car may be heard now.
var audible := true
var inside := false
var engine := EngineSynth.new()

var _fade := 0.0
var _active := false
var _on: Array[AudioStreamPlayer3D] = []
var _off: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_i := 0
var _pops: Array[AudioStreamWAV] = []
var _rng := RandomNumberGenerator.new()
var _wall_t := 99.0
var _last_speed := 0.0
var _hit_cool := 0.0
var _pending_hit := 0.0
var _scrape := 0.0
var _dop := 1.0
var _surf := {"gravel": 0.0, "grass": 0.0}


## Builds the players. `is_local` is true for a car driven by a person on
## this device (all layers, no budget); false for AI and remote drivers.
func setup(p_spec: CarSpec, is_local: bool) -> void:
	spec = p_spec
	is_player = is_local
	audible = is_local
	_rng.randomize()
	for c in get_children():
		c.queue_free()
	_on.clear()
	_off.clear()
	_loops.clear()
	_shots.clear()
	for i in EngineSynth.BANDS.size():
		_on.append(_player("engine/on_%d" % i, 10.0, 400.0))
		_off.append(_player("engine/off_%d" % i, 10.0, 400.0))
	_loops.limiter = _player("engine/limiter", 10.0, 400.0)
	_loops.pit = _player("engine/pit_limiter", 10.0, 400.0)
	_loops.squeal = _player("car/squeal", 8.0, 250.0)
	_loops.scrub = _player("car/scrub", 8.0, 200.0)
	_loops.kerb = _player("car/kerb", 6.0, 150.0)
	_loops.gravel = _player("car/gravel", 6.0, 150.0)
	_loops.grass = _player("car/grass", 5.0, 120.0)
	if is_player:
		_loops.turbo = _player("engine/turbo", 5.0, 150.0)
		_loops.drive = _player("engine/drive", 5.0, 150.0)
		_loops.wind = _player("car/wind", 4.0, 60.0)
		_loops.spray = _player("car/spray", 5.0, 120.0)
		_loops.scrape = _player("car/scrape", 6.0, 150.0)
	for i in (4 if is_player else 2):
		_shots.append(_player("", 8.0, 300.0))
	_pops.clear()
	for i in EngineSynth.POPS:
		var s := SoundBank.stream("engine/pop_%d" % i) as AudioStreamWAV
		if s:
			_pops.append(s)
	_apply_buses()


## The cockpit camera (inside) or any other camera.
func set_view(p_inside: bool) -> void:
	if inside == p_inside:
		return
	inside = p_inside
	_apply_buses()


## Contact with another car (or anything) at this speed (m/s).
func hit(speed: float) -> void:
	_pending_hit = maxf(_pending_hit, speed)


## Steps the sound from the car's state. `throttle` is the driver's pedal
## (0 to 1); pass a negative value to use the throttle the car applied.
func update(sim: CarSim, throttle := -1.0, dt := 1.0 / 60.0) -> void:
	if sim == null or spec == null:
		return
	dt = clampf(dt, 0.0, 0.1)
	if not is_player:
		AudioBudget.refresh()
	_fade = move_toward(_fade, 1.0 if is_player or audible else 0.0, dt * 2.0)
	_hit_cool = maxf(0.0, _hit_cool - dt)
	_watch_contact(sim)
	if _fade <= 0.0:
		if _active:
			_silence()
		engine.rpm_s = sim.rpm
		return
	_active = true
	var thr := throttle if throttle >= 0.0 else sim.engine_load
	var pit_limited := sim.limiter_on and sim.spot.in_pit and sim.speed > CarSim.PIT_LIMIT - 1.5
	engine.update(sim.rpm, thr, sim.gear, sim.spec.rpm_limit, pit_limited, sim.speed, dt)
	var dop := 1.0 if is_player else _doppler(sim, dt)
	var g := _fade * _fade * db_to_linear(MASTER_DB + (OWN_CAR_DB if is_player else 0.0))
	var e := g * _db("engine")
	for i in _on.size():
		_band(i, engine.on_gain[i] * e, engine.off_gain[i] * e, engine.band_pitch[i] * dop)
	_voice(_loops.limiter, engine.limiter_gain * e * _db("limiter"), engine.limiter_pitch * dop)
	_voice(_loops.pit, engine.pit_gain * e * _db("pit"), engine.pit_pitch * dop)
	for p: float in engine.take_pops():
		if not _pops.is_empty():
			_shot(_pops[_rng.randi() % _pops.size()], p * engine.level * e * _db("pop"), _rng.randf_range(0.9, 1.1) * dop)
	# Tyres: squeal from sliding on tarmac, scrub from locking or spinning.
	var v := sim.speed
	var moving := clampf((v - 3.0) / 10.0, 0.0, 1.0)
	var grippy := sim.surface == CarSim.Surface.ROAD or sim.surface == CarSim.Surface.KERB or sim.surface == CarSim.Surface.TARMAC or sim.surface == CarSim.Surface.PIT
	var wet := 1.0 - 0.7 * clampf(sim.wetness, 0.0, 1.0)
	var slide := clampf((sim.sliding - 0.1) / 0.7, 0.0, 1.0) if grippy else 0.0
	_voice(_loops.squeal, slide * moving * wet * g * _db("squeal"), (0.92 + 0.2 * slide + v / 600.0) * dop)
	var lock := clampf(maxf(sim.front_lock, sim.rear_spin), 0.0, 1.0) if grippy else 0.0
	_voice(_loops.scrub, lock * moving * wet * g * _db("scrub"), (0.8 + v / 150.0) * dop)
	# Kerbs and run-off.
	_voice(_loops.kerb, clampf(sim.on_kerb, 0.0, 1.0) * clampf(v / 8.0, 0.0, 1.0) * g * _db("kerb"), clampf(v / 25.0, 0.4, 2.5) * dop)
	var loose := sim.surface == CarSim.Surface.GRAVEL or sim.surface == CarSim.Surface.SAND
	_surf.gravel = move_toward(_surf.gravel, 1.0 if loose else 0.0, dt * 8.0)
	_surf.grass = move_toward(_surf.grass, 1.0 if sim.surface == CarSim.Surface.GRASS else 0.0, dt * 8.0)
	var rough := clampf(v / 30.0, 0.0, 1.0)
	_voice(_loops.gravel, _surf.gravel * sqrt(rough) * g * _db("gravel"), (0.75 + rough * 0.4) * dop)
	_voice(_loops.grass, _surf.grass * sqrt(rough) * g * _db("grass"), (0.8 + rough * 0.4) * dop)
	if is_player:
		_voice(_loops.turbo, engine.turbo_gain * e * _db("turbo"), engine.turbo_pitch)
		_voice(_loops.drive, engine.drive_gain * e * _db("drive"), engine.drive_pitch)
		var air := clampf(v / 85.0, 0.0, 1.2)
		_voice(_loops.wind, air * air * g * _db("wind"), 0.8 + v / 300.0)
		_voice(_loops.spray, clampf(sim.wetness, 0.0, 1.0) * clampf(v / 40.0, 0.0, 1.0) * g * _db("spray"), 0.85 + v / 400.0)
		var scraping := sim.wall_t < 0.12 and v > 3.0
		_scrape = move_toward(_scrape, clampf(v / 40.0, 0.25, 1.0) if scraping else 0.0, dt * (20.0 if scraping else 6.0))
		_voice(_loops.scrape, _scrape * g * _db("scrape"), 0.85 + v / 200.0)
	if _pending_hit > 0.0:
		_play_hit(_pending_hit, g, dop)
		_pending_hit = 0.0


func _enter_tree() -> void:
	AudioBudget.register(self)


func _exit_tree() -> void:
	AudioBudget.unregister(self)


## Notices hits: `impact` this tick, or a fresh wall contact since the last
## call (estimated from the speed lost).
func _watch_contact(sim: CarSim) -> void:
	var hit_speed := sim.impact
	if hit_speed <= 0.0 and sim.wall_t < _wall_t and sim.wall_t < 0.05:
		hit_speed = maxf(_last_speed - sim.speed, 0.0) * 1.5
	_wall_t = sim.wall_t
	_last_speed = sim.speed
	if hit_speed > 1.5:
		_pending_hit = maxf(_pending_hit, hit_speed)


func _play_hit(speed: float, g: float, dop: float) -> void:
	if _hit_cool > 0.0 or _fade <= 0.0:
		return
	_hit_cool = 0.12
	var x := clampf((speed - 1.5) / 15.0, 0.0, 1.0)
	var gain := db_to_linear(lerpf(-20.0, 0.0, x)) * g * _db("thump")
	_shot(SoundBank.stream("car/thump"), gain, _rng.randf_range(0.9, 1.1) * dop)
	if speed > 8.0:
		_shot(SoundBank.stream(SoundBank.KENNEY + "impact-sounds/impactPlate_heavy_00%d.ogg" % (_rng.randi() % 2)), gain * 0.8, _rng.randf_range(0.85, 1.0))
	elif speed > 3.0:
		_shot(SoundBank.stream(SoundBank.KENNEY + "impact-sounds/impactMetal_light_00%d.ogg" % (_rng.randi() % 2)), gain * 0.6, _rng.randf_range(0.9, 1.1))


## Doppler from the car's velocity and the nearest listener's, smoothed.
func _doppler(sim: CarSim, dt: float) -> float:
	var near := AudioBudget.nearest(global_position)
	var want := 1.0
	if not near.is_empty():
		var lp: Vector3 = near[0]
		var lv: Vector3 = near[1]
		var to_src := global_position - lp
		var d := to_src.length()
		if d > 0.5:
			var dir := to_src / d
			var vs := Vector3(sim.vel.x, 0.0, sim.vel.y)
			var toward_l := lv.dot(dir)
			var toward_s := -vs.dot(dir)
			want = clampf((SPEED_OF_SOUND + toward_l) / maxf(SPEED_OF_SOUND - toward_s, 100.0), 0.7, 1.4)
	_dop = lerpf(_dop, want, clampf(dt * 10.0, 0.0, 1.0))
	return _dop


func _db(layer: String) -> float:
	var db: float = TRIM.get(layer, 0.0)
	if inside and is_player:
		db += float(INSIDE.get(layer, 0.0))
	return db_to_linear(db)


## Sets a loop's gain (linear) and pitch, starting it (at a random point,
## so cars don't play in step) or stopping it as the gain crosses silence.
func _voice(p: AudioStreamPlayer3D, gain: float, pitch: float) -> void:
	if p == null:
		return
	if gain < 0.0005 or p.stream == null:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(gain)
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	if not p.playing:
		p.play(_rng.randf() * maxf(p.stream.get_length() - 0.05, 0.0))


## A band's on-throttle and overrun loops start and stop together, from
## the same point, so they stay in step and never cancel each other out.
func _band(i: int, on: float, off: float, pitch: float) -> void:
	var a := _on[i]
	var b := _off[i]
	if a.stream == null or b.stream == null:
		return
	if on < 0.0005 and off < 0.0005:
		if a.playing:
			a.stop()
			b.stop()
		return
	a.volume_db = linear_to_db(maxf(on, 0.0001))
	b.volume_db = linear_to_db(maxf(off, 0.0001))
	a.pitch_scale = clampf(pitch, 0.1, 4.0)
	b.pitch_scale = a.pitch_scale
	if not a.playing or not b.playing:
		var from := _rng.randf() * maxf(a.stream.get_length() - 0.05, 0.0)
		a.play(from)
		b.play(from)


func _shot(s: AudioStream, gain: float, pitch: float) -> void:
	if s == null or _shots.is_empty() or gain < 0.0005:
		return
	var p: AudioStreamPlayer3D = null
	for k in _shots.size():
		var c := _shots[(_shot_i + k) % _shots.size()]
		if not c.playing:
			p = c
			break
	if p == null:
		p = _shots[_shot_i % _shots.size()]
	_shot_i += 1
	p.stream = s
	p.volume_db = linear_to_db(gain)
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.play()


func _silence() -> void:
	for p in _on + _off:
		p.stop()
	for k in _loops:
		(_loops[k] as AudioStreamPlayer3D).stop()
	_active = false


func _player(sound: String, unit: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if sound != "":
		p.stream = SoundBank.stream(sound)
	p.bus = BUS
	p.unit_size = unit
	p.max_db = 3.0
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.panning_strength = 0.8
	add_child(p)
	return p


## In the cockpit the engine, tyres and surfaces go through the muffled
## Cockpit bus; the whines stay clear on SFX.
func _apply_buses() -> void:
	var bus := BUS
	if inside and is_player:
		bus = _cockpit_bus()
	for p in _on + _off:
		p.bus = bus
	for k in ["limiter", "pit", "squeal", "scrub", "kerb", "gravel", "grass", "wind", "spray", "scrape"]:
		if _loops.has(k):
			(_loops[k] as AudioStreamPlayer3D).bus = bus
	for p in _shots:
		p.bus = bus


## The Cockpit bus: a low-pass for the helmet and the bodywork, feeding SFX
## so the effects volume still applies. Made once, at run time.
static func _cockpit_bus() -> String:
	if AudioServer.get_bus_index(COCKPIT_BUS) >= 0:
		return COCKPIT_BUS
	if AudioServer.get_bus_index(BUS) < 0:
		return "Master"
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, COCKPIT_BUS)
	AudioServer.set_bus_send(idx, BUS)
	AudioServer.set_bus_volume_db(idx, -2.0)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 2600.0
	lp.resonance = 0.6
	AudioServer.add_bus_effect(idx, lp)
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, 2.0)
	eq.set_band_gain_db(1, 3.0)
	AudioServer.add_bus_effect(idx, eq)
	return COCKPIT_BUS
