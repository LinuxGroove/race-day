class_name SoundSynth
extends RefCounted
## Recipes for every synthesized sound other than the engine: tyres, kerbs,
## gravel and grass, wind, spray, wall scrapes and thumps (CarAudio's loops
## and one-shots), and the race's beeps, chimes, radio, wheel guns and crowd
## (RaceSounds). `tools/bake_engine.gd` bakes them into assets/audio/; the
## game only plays the files. Loops say so in their doc and loop seamlessly.

const RATE := AudioDsp.RATE


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


# --- Car loops ----------------------------------------------------------------

## Loop: a tyre sliding sideways, a warbling squeal near 1 kHz.
static func squeal() -> PackedFloat32Array:
	var rng := _rng(11)
	var n := RATE * 2
	var out := _buf(2.0)
	for spec: Array in [[880.0, 30.0, 1.0], [1320.0, 18.0, 0.55], [2050.0, 12.0, 0.3]]:
		var nz := AudioDsp.noise(n, rng)
		AudioDsp.chain(nz, [AudioDsp.bandpass(spec[0], spec[1]), AudioDsp.bandpass(spec[0], spec[1])], true)
		AudioDsp.level(nz, -20.0, -3.0)
		AudioDsp.mix_into(out, nz, spec[2])
	# A tonal core whose pitch wanders; the wander has no net drift, so the
	# phase comes back round at the end of the loop.
	var dev := AudioDsp.smooth_loop(n, 14, -45.0, 45.0, rng)
	var mean := 0.0
	for v in dev:
		mean += v
	mean /= n
	var ph := 0.0
	for i in n:
		ph += TAU * (1000.0 + dev[i] - mean) / RATE
		out[i] += 0.035 * (sin(ph) + 0.3 * sin(2.0 * ph))
	AudioDsp.multiply(out, AudioDsp.smooth_loop(n, 12, 0.6, 1.0, rng))
	AudioDsp.level(out, -16.0, -2.0)
	return out


## Loop: a locked or spinning tyre scrubbing, rougher and lower.
static func scrub() -> PackedFloat32Array:
	var rng := _rng(12)
	var n := RATE * 3 / 2
	var out := AudioDsp.noise(n, rng)
	var low := out.duplicate()
	AudioDsp.chain(out, [AudioDsp.bandpass(750.0, 1.6), AudioDsp.peak(1500.0, 2.0, 6.0)], true)
	AudioDsp.chain(low, [AudioDsp.bandpass(130.0, 1.2)], true)
	AudioDsp.mix_into(out, low, 0.8)
	AudioDsp.multiply(out, AudioDsp.smooth_loop(n, 60, 0.35, 1.0, rng))
	AudioDsp.level(out, -16.0, -2.0)
	return out


## Loop: kerb stripes at 25 a second (25 m/s over 1 m stripes); play at
## pitch speed / 25.
static func kerb() -> PackedFloat32Array:
	var rng := _rng(13)
	var out := _buf(1.0)
	var n := out.size()
	var step := n / 25
	for k in 25:
		var amp := 1.0 if k % 2 == 0 else 0.75
		amp *= rng.randf_range(0.9, 1.1)
		for i in step * 2:
			var t := float(i) / RATE
			var j := (k * step + i) % n
			out[j] += amp * (sin(TAU * 62.0 * t) * exp(-t / 0.016) + 0.3 * sin(TAU * 180.0 * t) * exp(-t / 0.008) + 0.7 * rng.randf_range(-1.0, 1.0) * exp(-t / 0.004))
	AudioDsp.chain(out, [AudioDsp.lowpass(2400.0), AudioDsp.highpass(30.0)], true)
	AudioDsp.level(out, -14.0, -2.0)
	return out


## Loop: stones rattling under a car in the gravel trap.
static func gravel() -> PackedFloat32Array:
	var rng := _rng(14)
	var n := RATE * 2
	var stones := _buf(2.0)
	for k in 1800:
		var at := rng.randi_range(0, n - 1)
		stones[at] += pow(rng.randf(), 2.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	AudioDsp.chain(stones, [AudioDsp.bandpass(2400.0, 0.7), AudioDsp.peak(900.0, 1.0, 4.0)], true)
	var rumble := AudioDsp.noise(n, rng)
	AudioDsp.chain(rumble, [AudioDsp.lowpass(140.0), AudioDsp.lowpass(140.0)], true)
	AudioDsp.level(stones, -18.0, -3.0)
	AudioDsp.level(rumble, -20.0, -3.0)
	AudioDsp.mix_into(stones, rumble, 1.0)
	AudioDsp.level(stones, -16.0, -2.0)
	return stones


## Loop: tyres swishing over grass on bumpy ground.
static func grass() -> PackedFloat32Array:
	var rng := _rng(15)
	var n := RATE * 2
	var out := AudioDsp.noise(n, rng)
	AudioDsp.chain(out, [AudioDsp.lowpass(900.0), AudioDsp.bandpass(350.0, 0.6)], true)
	AudioDsp.multiply(out, AudioDsp.smooth_loop(n, 16, 0.35, 1.0, rng))
	AudioDsp.level(out, -18.0, -3.0)
	for k in 12:
		var at := rng.randi_range(0, n - 1)
		var amp := rng.randf_range(0.1, 0.3)
		for i in int(RATE * 0.12):
			var t := float(i) / RATE
			out[(at + i) % n] += amp * sin(TAU * 48.0 * t) * exp(-t / 0.03)
	AudioDsp.level(out, -16.0, -2.0)
	return out


## Loop: wind round the car and the helmet, with slow gusts.
static func wind() -> PackedFloat32Array:
	var rng := _rng(16)
	var n := RATE * 4
	var a := AudioDsp.noise(n, rng)
	var b := a.duplicate()
	AudioDsp.chain(a, [AudioDsp.bandpass(450.0, 0.5)], true)
	AudioDsp.chain(b, [AudioDsp.bandpass(1400.0, 0.8)], true)
	AudioDsp.mix_into(a, b, 0.45)
	AudioDsp.chain(a, [AudioDsp.lowpass(3000.0)], true)
	AudioDsp.multiply(a, AudioDsp.smooth_loop(n, 6, 0.7, 1.0, rng))
	AudioDsp.level(a, -16.0, -2.0)
	return a


## Loop: spray hissing off wet tyres.
static func spray() -> PackedFloat32Array:
	var rng := _rng(17)
	var n := RATE * 2
	var out := AudioDsp.noise(n, rng)
	AudioDsp.chain(out, [AudioDsp.highpass(2200.0), AudioDsp.lowpass(9000.0), AudioDsp.peak(5500.0, 1.0, 3.0)], true)
	AudioDsp.multiply(out, AudioDsp.smooth_loop(n, 12, 0.6, 1.0, rng))
	AudioDsp.level(out, -18.0, -2.0)
	return out


## Loop: bodywork grinding along a wall, metallic and uneven.
static func scrape() -> PackedFloat32Array:
	var rng := _rng(18)
	var n := RATE * 3 / 2
	var src := AudioDsp.noise(n, rng)
	AudioDsp.multiply(src, AudioDsp.smooth_loop(n, 38, 0.1, 1.0, rng))
	var out := _buf(1.5)
	for spec: Array in [[1130.0, 1.0], [1870.0, 0.8], [2950.0, 0.6], [4210.0, 0.4]]:
		var r := src.duplicate()
		AudioDsp.chain(r, [AudioDsp.bandpass(spec[0], 35.0)], true)
		AudioDsp.mix_into(out, r, spec[1] * 4.0)
	var broad := src.duplicate()
	AudioDsp.chain(broad, [AudioDsp.bandpass(3000.0, 0.8)], true)
	AudioDsp.mix_into(out, broad, 0.5)
	AudioDsp.level(out, -16.0, -2.0)
	return out


## One-shot: a heavy thump for contact (about 0.4 s).
static func thump() -> PackedFloat32Array:
	var rng := _rng(19)
	var out := _buf(0.4)
	var n := out.size()
	var nz := AudioDsp.noise(n, rng)
	var body := nz.duplicate()
	for i in n:
		var t := float(i) / RATE
		nz[i] *= exp(-t / 0.025)
		body[i] *= exp(-t / 0.06)
	AudioDsp.chain(nz, [AudioDsp.lowpass(1200.0)], false)
	AudioDsp.chain(body, [AudioDsp.bandpass(190.0, 1.0)], false)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(75.0, 38.0, minf(t / 0.2, 1.0)) / RATE
		out[i] = sin(ph) * exp(-t / 0.09) + nz[i] * 1.2 + body[i] * 2.0
	AudioDsp.fade(out, 0.0005, 0.05)
	AudioDsp.normalize_peak(out, -1.5)
	return out


# --- Race sounds --------------------------------------------------------------

## One-shot: one start light coming on.
static func light_beep() -> PackedFloat32Array:
	var out := _buf(0.22)
	AudioDsp.add_tone(out, 880.0, 880.0, 0.0, 0.2, 0.7, 0.003, 0.25)
	AudioDsp.add_tone(out, 1760.0, 1760.0, 0.0, 0.2, 0.15, 0.003, 0.12)
	AudioDsp.normalize_peak(out, -4.0)
	return out


## One-shot: lights out, a higher, longer tone.
static func lights_out() -> PackedFloat32Array:
	var out := _buf(0.65)
	AudioDsp.add_tone(out, 1320.0, 1320.0, 0.0, 0.6, 0.7, 0.003, 0.4)
	AudioDsp.add_tone(out, 2640.0, 2640.0, 0.0, 0.6, 0.12, 0.003, 0.2)
	AudioDsp.add_tone(out, 660.0, 660.0, 0.0, 0.6, 0.2, 0.003, 0.3)
	AudioDsp.normalize_peak(out, -3.0)
	return out


## One-shot: a lap completed, two short high beeps.
static func lap_beep() -> PackedFloat32Array:
	var out := _buf(0.24)
	AudioDsp.add_tone(out, 1568.0, 1568.0, 0.0, 0.07, 0.6, 0.003, 0.1)
	AudioDsp.add_tone(out, 1568.0, 1568.0, 0.12, 0.09, 0.6, 0.003, 0.12)
	AudioDsp.normalize_peak(out, -6.0)
	return out


## One-shot: the radio opening: a click, a burst of static and a pip.
static func radio() -> PackedFloat32Array:
	var rng := _rng(21)
	var out := _buf(0.2)
	var n := out.size()
	var st := AudioDsp.noise(n, rng)
	var crackle := AudioDsp.smooth_loop(n, 30, 0.2, 1.0, rng)
	for i in n:
		var t := float(i) / RATE
		st[i] *= crackle[i] * (exp(-t / 0.05) if t > 0.01 else t / 0.01)
	AudioDsp.chain(st, [AudioDsp.bandpass(1800.0, 0.9), AudioDsp.highpass(500.0)], false)
	AudioDsp.mix_into(out, st, 1.0)
	out[0] += 0.12
	out[1] -= 0.08
	AudioDsp.add_tone(out, 1150.0, 1150.0, 0.02, 0.06, 0.12, 0.002)
	AudioDsp.fade(out, 0.0, 0.03)
	AudioDsp.normalize_peak(out, -6.0)
	return out


static func _bell(out: PackedFloat32Array, f: float, at: float, gain: float, decay: float) -> void:
	AudioDsp.add_tone(out, f, f, at, decay * 4.0, gain, 0.002, decay)
	AudioDsp.add_tone(out, f * 2.0, f * 2.0, at, decay * 3.0, gain * 0.25, 0.002, decay * 0.6)
	AudioDsp.add_tone(out, f * 2.76, f * 2.76, at, decay * 2.0, gain * 0.12, 0.002, decay * 0.35)


## One-shot: a penalty, two falling chimes.
static func penalty() -> PackedFloat32Array:
	var out := _buf(1.1)
	_bell(out, 988.0, 0.0, 0.6, 0.25)
	_bell(out, 659.0, 0.22, 0.7, 0.3)
	AudioDsp.fade(out, 0.0, 0.05)
	AudioDsp.normalize_peak(out, -5.0)
	return out


## One-shot: a warning (track limits), one soft chime.
static func warning() -> PackedFloat32Array:
	var out := _buf(0.8)
	_bell(out, 880.0, 0.0, 0.6, 0.22)
	AudioDsp.fade(out, 0.0, 0.05)
	AudioDsp.normalize_peak(out, -7.0)
	return out


## One-shot: four wheel guns at once (about 0.6 s): the rattle of the
## hammers, the air motor's whine and the hiss of air.
static func wheel_guns() -> PackedFloat32Array:
	var rng := _rng(22)
	var out := _buf(0.65)
	var n := out.size()
	for g in 4:
		var start := g * 0.03 + rng.randf_range(0.0, 0.02)
		var length := rng.randf_range(0.3, 0.4)
		var rate := rng.randf_range(38.0, 48.0)
		var clicks := _buf(0.65)
		var t := start
		while t < start + length:
			var i0 := int(t * RATE)
			var amp := rng.randf_range(0.6, 1.0)
			for i in int(RATE * 0.006):
				if i0 + i < n:
					clicks[i0 + i] += amp * rng.randf_range(-1.0, 1.0) * exp(-float(i) / RATE / 0.0015)
			t += 1.0 / rate
		AudioDsp.chain(clicks, [AudioDsp.bandpass(rng.randf_range(3000.0, 3800.0), 3.0), AudioDsp.peak(5200.0, 4.0, 8.0)], false)
		AudioDsp.mix_into(out, clicks, 2.5)
		var f := rng.randf_range(850.0, 1100.0)
		AudioDsp.add_tone(out, f * 0.7, f, start, length, 0.06, 0.04)
	var hiss := AudioDsp.noise(n, rng)
	for i in n:
		var tt := float(i) / RATE
		hiss[i] *= 0.15 * clampf(tt / 0.05, 0.0, 1.0) * clampf((0.55 - tt) / 0.1, 0.0, 1.0)
	AudioDsp.chain(hiss, [AudioDsp.highpass(3500.0), AudioDsp.lowpass(10000.0)], false)
	AudioDsp.mix_into(out, hiss, 1.0)
	AudioDsp.fade(out, 0.001, 0.04)
	AudioDsp.level(out, -16.0, -2.0)
	return out


## Murmuring voices: `groups` of people, each a band of noise shaped like a
## voice and coming and going a few times a second.
static func _babble(n: int, groups: int, rng: RandomNumberGenerator, loop: bool, bright := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var seconds := float(n) / RATE
	for g in groups:
		var v := AudioDsp.noise(n, rng)
		var f2 := v.duplicate()
		AudioDsp.chain(v, [AudioDsp.bandpass(rng.randf_range(380.0, 750.0) * bright, 2.2)], loop)
		AudioDsp.chain(f2, [AudioDsp.bandpass(rng.randf_range(1000.0, 2300.0) * bright, 3.0)], loop)
		AudioDsp.mix_into(v, f2, 0.6)
		var am := AudioDsp.smooth_loop(n, int(seconds * rng.randf_range(3.0, 5.0)), -0.4, 1.0, rng)
		for i in n:
			var a := maxf(am[i], 0.0)
			v[i] *= a * a
		AudioDsp.mix_into(out, v, 1.0)
	return out


## Loop: a grandstand's murmur.
static func crowd() -> PackedFloat32Array:
	var rng := _rng(23)
	var n := RATE * 6
	var out := _babble(n, 12, rng, true)
	var wash := AudioDsp.noise(n, rng)
	AudioDsp.chain(wash, [AudioDsp.bandpass(650.0, 0.5)], true)
	AudioDsp.level(out, -20.0, -3.0)
	AudioDsp.level(wash, -30.0, -3.0)
	AudioDsp.mix_into(out, wash, 1.0)
	AudioDsp.chain(out, [AudioDsp.lowpass(4200.0)], true)
	AudioDsp.level(out, -18.0, -3.0)
	return out


## One-shot: a grandstand cheering: a swell of voices, whoops, whistles and
## applause. `seconds` long (3 for a pass for the lead, 5 at the flag).
static func cheer(seconds := 3.0, seed := 24) -> PackedFloat32Array:
	var rng := _rng(seed)
	var n := int(seconds * RATE)
	var out := _babble(n, 14, rng, false, 1.25)
	AudioDsp.level(out, -18.0, -3.0)
	# Whoops: voices gliding up and back down.
	for k in 8:
		var at := rng.randf_range(0.1, seconds * 0.5)
		var len_s := rng.randf_range(0.5, 1.1)
		var f0 := rng.randf_range(240.0, 380.0)
		var whoop := PackedFloat32Array()
		whoop.resize(n)
		var start := int(at * RATE)
		var ph := 0.0
		for i in range(start, mini(n, start + int(len_s * RATE))):
			var u := float(i - start) / (len_s * RATE)
			var f := f0 * (1.0 + 0.6 * sin(u * PI)) * (1.0 + 0.015 * sin(TAU * 5.5 * u * len_s))
			ph += TAU * f / RATE
			# A buzzy voice: a few harmonics.
			whoop[i] = (sin(ph) + 0.5 * sin(2.0 * ph) + 0.3 * sin(3.0 * ph) + 0.15 * sin(4.0 * ph)) * sin(u * PI)
		AudioDsp.chain(whoop, [AudioDsp.peak(800.0, 1.5, 6.0), AudioDsp.lowpass(3000.0)], false)
		AudioDsp.mix_into(out, whoop, 0.035)
	# Whistles.
	for k in 3:
		var at := rng.randf_range(0.2, seconds * 0.6)
		var f := rng.randf_range(2000.0, 2800.0)
		AudioDsp.add_tone(out, f, f * rng.randf_range(1.1, 1.3), at, rng.randf_range(0.3, 0.6), 0.05, 0.03)
	# Applause.
	var claps := PackedFloat32Array()
	claps.resize(n)
	for k in int(seconds * 90.0):
		var at := int(rng.randf_range(0.0, seconds - 0.02) * RATE)
		var amp := rng.randf_range(0.3, 1.0)
		for i in int(RATE * 0.012):
			claps[at + i] += amp * rng.randf_range(-1.0, 1.0) * exp(-float(i) / RATE / 0.003)
	AudioDsp.chain(claps, [AudioDsp.bandpass(1500.0, 0.9)], false)
	AudioDsp.mix_into(out, claps, 0.25)
	# Swell in, hold, die away.
	for i in n:
		var t := float(i) / RATE
		var env := clampf(t / 0.35, 0.0, 1.0) * clampf((seconds - t) / (seconds * 0.55), 0.0, 1.0)
		out[i] *= env
	AudioDsp.fade(out, 0.01, 0.1)
	AudioDsp.level(out, -15.0, -2.0)
	return out
