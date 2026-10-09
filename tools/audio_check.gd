extends Node
## Checks the car and race sounds without anyone listening.
##
##   godot --headless --path . tools/audio_check.tscn -- --out=/tmp/audio
##
## renders example sounds to WAV files in --out (an engine sweep from 4000 to
## 12000 rpm on and off the throttle, gear changes, the rev and pit limiters,
## a squeal and an onboard lap of an AI car), mixing the baked loops the way
## CarAudio drives its players, and prints for each: level, peak, clipped
## samples, the worst jump between samples, and for the sweep the measured
## firing frequency against the rpm. Then it checks every loop's seam and
## prints the CPU and memory cost.
##
##   xvfb-run -a godot --path . --write-movie /tmp/audio/live.png --fixed-fps 60 \
##       --resolution 320x180 tools/audio_check.tscn -- --live
##
## records what Godot itself plays (in /tmp/audio/live.wav): a race of AI
## cars on the Proving Ground with CarAudio on each, heard from beside the
## start line (to 24 s), then onboard the leader (to 34 s), then from the
## cockpit (to 42 s).

const OUT_RATE := 44100
const FRAME := 1.0 / 60.0

var out_dir := "user://audio_check"
var _loops := {}


func _ready() -> void:
	var live := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--live":
			live = true
	if live:
		_live()
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_render_all()
	_check_loops()
	await _cpu()
	get_tree().quit()


# --- Offline renders ----------------------------------------------------------

## One playing sample in the offline mix.
class Voice:
	var buf: PackedFloat32Array
	var pos := 0.0
	var loop := true
	var gain := 0.0
	var done := false


func _samples(name: String) -> PackedFloat32Array:
	if not _loops.has(name):
		_loops[name] = AudioDsp.wav_samples(SoundBank.stream(name) as AudioStreamWAV)
	return _loops[name]


## Mixes `count` output samples of a voice, ramping its gain to `to` the way
## Godot ramps a player's volume across a mix buffer.
func _mix(out: PackedFloat32Array, start: int, count: int, v: Voice, to: float, pitch: float) -> void:
	var n := v.buf.size()
	if n == 0 or v.done:
		return
	var from := v.gain
	v.gain = to
	if from < 0.0005 and to < 0.0005:
		return
	var step := pitch * AudioDsp.RATE / OUT_RATE
	for i in count:
		var k := int(v.pos)
		var t := v.pos - k
		var a: float = v.buf[k]
		var b := 0.0
		if k + 1 < n:
			b = v.buf[k + 1]
		elif v.loop:
			b = v.buf[0]
		out[start + i] += lerpf(a, b, t) * lerpf(from, to, float(i) / count)
		v.pos += step
		if v.pos >= n:
			if v.loop:
				v.pos -= n
			else:
				v.done = true
				return


## Renders `seconds` of an engine driven by `control(t) -> [rpm, throttle,
## gear, pit_limited, speed, slide]`.
func _render_engine(seconds: float, control: Callable, spec: CarSpec) -> PackedFloat32Array:
	var eng := EngineSynth.new()
	eng.rng.seed = 7
	var out := PackedFloat32Array()
	out.resize(int(seconds * 60.0) * (OUT_RATE / 60))
	var on: Array[Voice] = []
	var off: Array[Voice] = []
	for i in EngineSynth.BANDS.size():
		on.append(_voice("engine/on_%d" % i, true, 0.1 * i))
		off.append(_voice("engine/off_%d" % i, true, 0.1 * i))
	var lim := _voice("engine/limiter", true)
	var pit := _voice("engine/pit_limiter", true)
	var turbo := _voice("engine/turbo", true)
	var drive := _voice("engine/drive", true)
	var squeal := _voice("car/squeal", true)
	var shots: Array[Voice] = []
	var per := OUT_RATE / 60
	var frames := int(seconds * 60.0)
	var trim := func(layer: String) -> float: return db_to_linear(float(CarAudio.TRIM.get(layer, 0.0)))
	for f in frames:
		var c: Array = control.call(f * FRAME)
		eng.update(c[0], c[1], c[2], spec.rpm_limit, c[3], c[4], FRAME)
		var at := f * per
		for i in on.size():
			_mix(out, at, per, on[i], eng.on_gain[i], eng.band_pitch[i])
			_mix(out, at, per, off[i], eng.off_gain[i], eng.band_pitch[i])
		_mix(out, at, per, lim, eng.limiter_gain, eng.limiter_pitch)
		_mix(out, at, per, pit, eng.pit_gain * trim.call("pit"), eng.pit_pitch)
		_mix(out, at, per, turbo, eng.turbo_gain * trim.call("turbo"), eng.turbo_pitch)
		_mix(out, at, per, drive, eng.drive_gain * trim.call("drive"), eng.drive_pitch)
		var slide: float = c[5] if c.size() > 5 else 0.0
		_mix(out, at, per, squeal, slide * trim.call("squeal"), 0.92 + 0.2 * slide + float(c[4]) / 600.0)
		for p: float in eng.take_pops():
			var s := _voice("engine/pop_%d" % (shots.size() % EngineSynth.POPS), false)
			s.gain = p * eng.level * trim.call("pop")
			shots.append(s)
		for s in shots:
			_mix(out, at, per, s, s.gain, 1.0)
	# Same headroom as the game: the SFX bus at 0 dB, a car close by (+3 dB).
	AudioDsp.scale(out, db_to_linear(3.0))
	return out


func _voice(name: String, loop: bool, offset := 0.0) -> Voice:
	var v := Voice.new()
	v.buf = _samples(name)
	v.loop = loop
	v.pos = fmod(offset * AudioDsp.RATE, maxf(v.buf.size(), 1))
	return v


## The rpm in a gear at a speed, as CarSim works it out.
static func _rpm_in(spec: CarSpec, g: int, v: float) -> float:
	return v / spec.wheel_radius * 60.0 / TAU * spec.gears[g]


func _render_all() -> void:
	var spec := CarSpec.new()
	var jobs := {
		"sweep_on": [8.0, func(t: float) -> Array: return [lerpf(4000.0, 12000.0, t / 8.0), 1.0, 3, false, 40.0]],
		"sweep_off": [8.0, func(t: float) -> Array: return [lerpf(12000.0, 4000.0, t / 8.0), 0.0, 3, false, 40.0]],
		"limiter": [3.0, func(t: float) -> Array: return [minf(11000.0 + t * 4000.0, spec.rpm_limit), 1.0, 7, false, 80.0]],
		"pit_limiter": [4.0, func(t: float) -> Array: return [7960.0, 1.0, 1, t > 0.5, 22.0]],
		"squeal": [4.0, func(t: float) -> Array: return [9000.0, 0.6, 3, false, 35.0, clampf(sin(t / 4.0 * PI) * 1.4, 0.0, 1.0)]],
	}
	# Gear changes: full throttle from 15 m/s through the gears, then braking
	# down through them, with CarSim's shift points and rpm smoothing.
	var g := [0]
	var speed := [15.0]
	var rpm := [8000.0]
	var gearbox := func(t: float) -> Array:
		var thr := 1.0 if t < 9.0 else 0.0
		for k in 2:
			var dt := FRAME / 2.0
			if thr > 0.0:
				speed[0] += maxf(0.8, 13.0 - speed[0] / 7.0) * dt
			else:
				speed[0] = maxf(15.0, speed[0] - 40.0 * dt)
			if rpm[0] > CarSim.SHIFT_UP_RPM and g[0] < 7:
				g[0] += 1
			elif g[0] > 0 and rpm[0] < CarSim.SHIFT_DOWN_RPM and _rpm_in(spec, g[0] - 1, speed[0]) < CarSim.SHIFT_UP_RPM - 600.0:
				g[0] -= 1
			rpm[0] = lerpf(rpm[0], clampf(_rpm_in(spec, g[0], speed[0]), spec.rpm_idle, spec.rpm_limit), 0.35)
		return [rpm[0], thr, g[0], false, speed[0]]
	jobs["gears"] = [13.0, gearbox]
	jobs["onboard"] = [30.0, _onboard_control()]
	print("Renders in %s" % ProjectSettings.globalize_path(out_dir))
	for name: String in jobs:
		var job: Array = jobs[name]
		var buf := _render_engine(job[0], job[1], spec)
		AudioDsp.save_wav(out_dir.path_join(name + ".wav"), buf, false, OUT_RATE)
		var clipped := 0
		for v in buf:
			if absf(v) >= 0.999:
				clipped += 1
		print("  %-12s rms %6.1f dB  peak %6.1f dB  clipped %d  worst jump %.3f" % [name, linear_to_db(AudioDsp.rms(buf)), linear_to_db(AudioDsp.peak_of(buf)), clipped, _worst_jump(buf)])
		if name == "sweep_on" or name == "sweep_off":
			var line := "    firing Hz (want / got):"
			for r in [4500.0, 6000.0, 7500.0, 9000.0, 10500.0, 11500.0]:
				var t: float = (r - 4000.0) / 8000.0 * 8.0
				if name == "sweep_off":
					t = 8.0 - t
				var f := _pitch(buf, int(t * OUT_RATE), r / 20.0)
				line += "  %d/%.1f" % [int(r / 20.0), f]
			print(line)
	# The .import files save_wav writes next to renders are not needed.
	for f in DirAccess.get_files_at(out_dir):
		if f.ends_with(".import"):
			DirAccess.remove_absolute(out_dir.path_join(f))


## The leader of an AI race on the Proving Ground, onboard, from the lights.
func _onboard_control() -> Callable:
	var race := _make_race(6)
	race.start()
	var lead: Race.Entry = race.entries[0]
	var state := {"t": 0.0}
	return func(t: float) -> Array:
		while state.t < t:
			race.step(Race.DT)
			state.t += Race.DT
		var s := lead.sim
		return [s.rpm, lead.input.throttle, s.gear, s.limiter_on and s.spot.in_pit and s.speed > CarSim.PIT_LIMIT - 1.5, s.speed, s.sliding]


func _make_race(cars: int) -> Race:
	var race := Race.new(Circuits.track("proving"), Race.Kind.RACE, 3, 5)
	for i in cars:
		race.add_car(i + 1, "Driver %d" % (i + 1), i % 10, i, 0.9)
	return race


## Largest second difference: a click shows as a spike far above the rest.
static func _worst_jump(buf: PackedFloat32Array) -> float:
	var worst := 0.0
	for i in range(2, buf.size()):
		worst = maxf(worst, absf(buf[i] - 2.0 * buf[i - 1] + buf[i - 2]))
	return worst


## The strongest frequency within 15% of `expect` around sample `at`: a
## Goertzel scan over a Hann window of 16384 samples, in 0.2% steps.
static func _pitch(buf: PackedFloat32Array, at: int, expect: float) -> float:
	var w := 16384
	at = clampi(at - w / 2, 0, buf.size() - w)
	var win := PackedFloat32Array()
	win.resize(w)
	for i in w:
		win[i] = buf[at + i] * (0.5 - 0.5 * cos(TAU * i / w))
	var best := 0.0
	var bp := -1.0
	var f := expect * 0.85
	while f <= expect * 1.15:
		var c := 2.0 * cos(TAU * f / OUT_RATE)
		var s1 := 0.0
		var s2 := 0.0
		for i in w:
			var s0: float = win[i] + c * s1 - s2
			s2 = s1
			s1 = s0
		var power := s1 * s1 + s2 * s2 - c * s1 * s2
		if power > bp:
			bp = power
			best = f
		f *= 1.002
	return best


## Every loop's seam: the jump across the join against the largest jump
## inside the loop (under 1 means the join is no worse than the sound itself).
func _check_loops() -> void:
	print("Loop seams (join / worst inside):")
	var line := ""
	var worst := 0.0
	for name: String in _bake_names(true):
		var b := _samples(name)
		if b.size() < 3:
			print("  missing %s" % name)
			continue
		var inside := _worst_jump(b)
		var n := b.size()
		var join := maxf(absf(b[0] - 2.0 * b[n - 1] + b[n - 2]), absf(b[1] - 2.0 * b[0] + b[n - 1]))
		var ratio := join / maxf(inside, 1e-6)
		worst = maxf(worst, ratio)
		line += "  %s %.2f" % [name.get_file(), ratio]
	print(line)
	print("  worst %.2f %s" % [worst, "(ok)" if worst < 1.0 else "(CLICK)"])


static func _bake_names(loops: bool) -> Array:
	var out := []
	var script: GDScript = load("res://tools/bake_engine.gd")
	var r: Dictionary = script.recipes()
	for k: String in r:
		if r[k][1] == loops:
			out.append(k)
	return out


# --- CPU and memory -------------------------------------------------------------

func _cpu() -> void:
	print("Cost:")
	var spec := CarSpec.new()
	var t0 := Time.get_ticks_usec()
	for i in EngineSynth.BANDS.size():
		EngineSynth.bake_on(EngineSynth.BANDS[i])
		EngineSynth.bake_off(EngineSynth.BANDS[i])
	print("  baking the 12 engine band loops would take %d ms (they are baked ahead into assets/audio/)" % ((Time.get_ticks_usec() - t0) / 1000))
	var eng := EngineSynth.new()
	t0 = Time.get_ticks_usec()
	for i in 20000:
		eng.update(4000.0 + (i % 800) * 10.0, float(i % 50 > 20), (i / 200) % 8, spec.rpm_limit, false, 50.0, FRAME)
		eng.take_pops()
	print("  EngineSynth.update: %.1f us" % ((Time.get_ticks_usec() - t0) / 20000.0))
	# A race of 20 cars, one of them the player's, heard from the start line.
	var race := _make_race(20)
	race.start()
	var listener := Node3D.new()
	add_child(listener)
	listener.global_position = race.entries[0].sim.pos + Vector3(0, 2, 8)
	AudioBudget.listeners = [listener]
	var audios: Array[CarAudio] = []
	var holders: Array[Node3D] = []
	for k in race.entries.size():
		var e: Race.Entry = race.entries[k]
		var h := Node3D.new()
		add_child(h)
		var ca := CarAudio.new()
		h.add_child(ca)
		ca.setup(e.sim.spec, k == 0)
		audios.append(ca)
		holders.append(h)
	var update_us := 0
	var updates := 0
	var playing_sum := 0
	var playing_max := 0
	var frames := 60 * 20
	for f in frames:
		for s in 2:
			race.step(Race.DT)
		for k in audios.size():
			var e: Race.Entry = race.entries[k]
			holders[k].global_position = e.sim.pos
			var u0 := Time.get_ticks_usec()
			audios[k].update(e.sim, e.input.throttle, FRAME)
			update_us += Time.get_ticks_usec() - u0
			updates += 1
		if f % 10 == 0:
			var playing := 0
			for ca in audios:
				for p in ca.get_children():
					if p is AudioStreamPlayer3D and (p as AudioStreamPlayer3D).playing:
						playing += 1
			playing_sum += playing
			playing_max = maxi(playing_max, playing)
		if f % 120 == 0:
			await get_tree().process_frame
	var audible := 0
	for ca in audios:
		if not ca.is_player and ca.audible:
			audible += 1
	print("  CarAudio.update: %.1f us a car a frame (%.2f ms a frame for 20 cars)" % [float(update_us) / updates, float(update_us) / frames / 1000.0])
	print("  players playing: %.1f on average, %d at most (AI cars audible: %d of 19)" % [float(playing_sum) / (frames / 10), playing_max, audible])
	var nodes := 0
	for ca in audios:
		nodes += ca.get_child_count()
	print("  AudioStreamPlayer3D nodes: %d for the player's car, %d for each other car" % [audios[0].get_child_count(), audios[1].get_child_count()])
	var bytes := 0
	for name: String in _bake_names(true) + _bake_names(false):
		var s := SoundBank.stream(name) as AudioStreamWAV
		if s:
			bytes += s.data.size()
	print("  baked sounds in memory: %d KB (shared by every car)" % (bytes / 1024))
	AudioBudget.listeners = []


# --- Live check (for --write-movie) ---------------------------------------------

func _live() -> void:
	# Only the sound matters: skip drawing the 3D world.
	get_viewport().disable_3d = true
	var race := _make_race(10)
	race.start()
	var cam := Camera3D.new()
	add_child(cam)
	var start: Vector3 = race.entries[0].sim.pos
	cam.global_position = start + Vector3(14, 3, 30)
	cam.look_at(start)
	var sounds := RaceSounds.new()
	add_child(sounds)
	sounds.race = race
	sounds.focus_ids = [1]
	sounds.add_grandstand(start + Vector3(20, 4, 10))
	var audios: Array[CarAudio] = []
	var holders: Array[Node3D] = []
	for k in race.entries.size():
		var h := Node3D.new()
		add_child(h)
		var ca := CarAudio.new()
		h.add_child(ca)
		ca.setup(race.entries[k].sim.spec, k == 0)
		audios.append(ca)
		holders.append(h)
	var t := 0.0
	print("Live: start line until 24 s, onboard car 1 until 34 s, cockpit until 42 s")
	while t < 42.0:
		var dt := get_process_delta_time()
		var steps := int(round(dt / Race.DT))
		for s in steps:
			race.step(Race.DT)
		sounds.handle_events(race.drain_events())
		var lead: Race.Entry = race.entries[0]
		if t > 24.0:
			cam.global_position = lead.sim.pos + Vector3(0, 1.0, 0)
			cam.look_at(lead.sim.pos + lead.sim.basis().z * 10.0 + Vector3(0, 1.0, 0))
		audios[0].set_view(t > 34.0)
		for k in audios.size():
			var e: Race.Entry = race.entries[k]
			holders[k].global_position = e.sim.pos
			audios[k].update(e.sim, e.input.throttle, dt)
		await get_tree().process_frame
		t += dt
	get_tree().quit()
