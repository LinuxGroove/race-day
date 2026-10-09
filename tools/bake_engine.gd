extends SceneTree
## Bakes every synthesized sound into assets/audio/ (engine loops, tyres,
## surfaces, wind, impacts and the race sounds), timing each one:
##   godot --headless --path . -s tools/bake_engine.gd
##   godot --headless --path . -s tools/bake_engine.gd -- --only=engine/on_3 --out=/tmp/bake
## Then `godot --headless --path . --import` to import new files. The sounds
## come from EngineSynth and SoundSynth; rerun this after changing either.

const OUT := "res://assets/audio/"


func _init() -> void:
	var out := OUT
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
	if not out.ends_with("/"):
		out += "/"
	var jobs := recipes()
	var total := 0
	var bytes := 0
	for name: String in jobs:
		if only != "" and not name.begins_with(only):
			continue
		var job: Array = jobs[name]
		var t0 := Time.get_ticks_usec()
		var buf: PackedFloat32Array = (job[0] as Callable).call()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += int(ms)
		var path := out + name + ".wav"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		AudioDsp.save_wav(path, buf, job[1])
		bytes += buf.size() * 2
		print("%-22s %6.2f s  peak %6.1f dB  rms %6.1f dB  %6d ms" % [name, buf.size() / float(AudioDsp.RATE), linear_to_db(AudioDsp.peak_of(buf)), linear_to_db(AudioDsp.rms(buf)), ms])
	print("Baked in %.1f s, %d KB of samples" % [total / 1000.0, bytes / 1024])
	quit()


## name -> [Callable that returns the samples, loops].
static func recipes() -> Dictionary:
	var r := {}
	for i in EngineSynth.BANDS.size():
		var rpm: float = EngineSynth.BANDS[i]
		r["engine/on_%d" % i] = [EngineSynth.bake_on.bind(rpm), true]
		r["engine/off_%d" % i] = [EngineSynth.bake_off.bind(rpm), true]
	r["engine/limiter"] = [EngineSynth.bake_limiter, true]
	r["engine/pit_limiter"] = [EngineSynth.bake_pit_limiter, true]
	r["engine/turbo"] = [EngineSynth.bake_turbo, true]
	r["engine/drive"] = [EngineSynth.bake_drive, true]
	for i in EngineSynth.POPS:
		r["engine/pop_%d" % i] = [EngineSynth.bake_pop.bind(i), false]
	r["car/squeal"] = [SoundSynth.squeal, true]
	r["car/scrub"] = [SoundSynth.scrub, true]
	r["car/kerb"] = [SoundSynth.kerb, true]
	r["car/gravel"] = [SoundSynth.gravel, true]
	r["car/grass"] = [SoundSynth.grass, true]
	r["car/wind"] = [SoundSynth.wind, true]
	r["car/spray"] = [SoundSynth.spray, true]
	r["car/scrape"] = [SoundSynth.scrape, true]
	r["car/thump"] = [SoundSynth.thump, false]
	r["race/light"] = [SoundSynth.light_beep, false]
	r["race/lights_out"] = [SoundSynth.lights_out, false]
	r["race/lap"] = [SoundSynth.lap_beep, false]
	r["race/radio"] = [SoundSynth.radio, false]
	r["race/penalty"] = [SoundSynth.penalty, false]
	r["race/warning"] = [SoundSynth.warning, false]
	r["race/wheel_guns"] = [SoundSynth.wheel_guns, false]
	r["race/crowd"] = [SoundSynth.crowd, true]
	r["race/cheer"] = [SoundSynth.cheer.bind(3.0, 24), false]
	r["race/cheer_big"] = [SoundSynth.cheer.bind(5.0, 25), false]
	return r
