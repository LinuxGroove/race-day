class_name EngineSynth
extends RefCounted
## A 1.6 litre V6 turbo hybrid: the engine note for every car.
##
## Twenty cars can't each run a live synthesizer, so the engine is baked:
## `tools/bake_engine.gd` calls the static `bake_*` functions below and saves
## seamless loops to `assets/audio/engine/`: an on-throttle and an overrun
## loop for each rpm band in BANDS, the rev limiter, the pit limiter's
## bouncing note, the turbo and the hybrid drive whines, and a few exhaust
## pops. Each band's loop is recorded at its BANDS rpm and played back at
## pitch rpm / band, crossfading between neighbouring bands.
##
## An EngineSynth instance is one car's engine at run time: call `update()`
## with the car's state each frame, then read the gains (linear, 0 to about
## 1) and pitch scales of each voice and `take_pops()` for the one-shot pops.
## CarAudio applies them to its players; `tools/audio_check.gd` mixes them
## offline to check the result. It holds no nodes and costs a few
## microseconds a frame.
##
##   var eng := EngineSynth.new()
##   eng.update(sim.rpm, throttle, sim.gear, sim.spec.rpm_limit, pit_limited, sim.speed, dt)
##   player_on[i].volume_db = linear_to_db(eng.on_gain[i]); player_on[i].pitch_scale = eng.band_pitch[i]

const RATE := AudioDsp.RATE
## The rpm each band's loop is recorded at. 32000 * 120 / rpm (one engine
## cycle, two turns of the crank) is a whole number of samples for each.
const BANDS := [4000.0, 5000.0, 6400.0, 8000.0, 9600.0, 12000.0]
## The rev limiter loop bounces round this rpm, the pit limiter's round PIT_RPM.
const LIMITER_RPM := 12150.0
const PIT_RPM := 8000.0
## The drive whine is recorded at this rpm; the turbo whistle at full spool.
const DRIVE_RPM := 10000.0
const POPS := 4
const DIR := "res://assets/audio/engine/"

## Per voice, after update(): gains (linear) and pitch scales.
var on_gain := PackedFloat32Array()
var off_gain := PackedFloat32Array()
var band_pitch := PackedFloat32Array()
var limiter_gain := 0.0
var limiter_pitch := 1.0
var pit_gain := 0.0
var pit_pitch := 1.0
var turbo_gain := 0.0
var turbo_pitch := 1.0
var drive_gain := 0.0
var drive_pitch := 1.0
## Overall engine level (linear), for the layers that follow it.
var level := 0.0

var rpm_s := 4200.0
var load_s := 0.0
var spool := 0.0
var _gear := 0
var _cut := 0.0
var _blip := 0.0
var _limiter := 0.0
var _pit := 0.0
var _crackle_t := 0.3
var _pops: Array = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	on_gain.resize(BANDS.size())
	off_gain.resize(BANDS.size())
	band_pitch.resize(BANDS.size())
	rng.randomize()


## Steps the engine model. `throttle` is the driver's pedal (0 to 1),
## `pit_limited` whether the pit lane limiter is holding the car.
func update(rpm: float, throttle: float, gear: int, rpm_limit: float, pit_limited: bool, speed: float, dt: float) -> void:
	dt = clampf(dt, 0.0, 0.1)
	rpm_s = lerpf(rpm_s, rpm, 1.0 - exp(-dt * 45.0))
	var r := rpm_s
	var thr := clampf(throttle, 0.0, 1.0)
	load_s = lerpf(load_s, thr, 1.0 - exp(-dt * (30.0 if thr > load_s else 14.0)))
	# Gear changes: an upshift cuts the ignition for a moment, a downshift
	# blips the throttle; both can pop.
	if gear > _gear and _gear >= 0 and load_s > 0.3:
		_cut = 1.0
		if rng.randf() < 0.5:
			_pop(0.18 + 0.12 * rng.randf())
	elif gear < _gear:
		_blip = 1.0
		if rng.randf() < 0.7:
			_pop(0.3 + 0.35 * rng.randf())
	_gear = gear
	# Hold the cut for about 35 ms, then let it go over about 60 ms.
	var cut_mul := 1.0 - 0.8 * clampf(_cut * 1.6, 0.0, 1.0)
	_cut = maxf(0.0, _cut - dt / 0.095)
	var blip := _blip * _blip
	_blip = maxf(0.0, _blip - dt / 0.12)
	# Limiters.
	var lim_on := thr > 0.5 and rpm >= rpm_limit - 60.0 and not pit_limited
	_limiter = move_toward(_limiter, 1.0 if lim_on else 0.0, dt * 25.0)
	_pit = move_toward(_pit, 1.0 if pit_limited and thr > 0.3 else 0.0, dt * 8.0)
	# Overrun crackles at high rpm off the throttle.
	if load_s < 0.15 and r > 7500.0 and speed > 15.0:
		_crackle_t -= dt * (r - 7500.0) / 4500.0
		if _crackle_t <= 0.0:
			_crackle_t = rng.randf_range(0.12, 0.6)
			_pop(rng.randf_range(0.08, 0.3))
	# Levels: louder with revs; the overrun is quieter and softer.
	var x := clampf((r - 4000.0) / 8300.0, 0.0, 1.0)
	level = db_to_linear(lerpf(-10.0, 0.0, x))
	var on_amt := sqrt(clampf(load_s + blip * 0.6, 0.0, 1.0))
	var off_amt := sqrt(clampf(1.0 - load_s - blip * 0.6, 0.0, 1.0))
	var lim_keep := 1.0 - maxf(_limiter, _pit)
	var on_level := level * on_amt * cut_mul * lim_keep
	var off_level := level * db_to_linear(lerpf(-11.0, -6.0, x)) * off_amt * lerpf(1.0, 0.4, _pit)
	_band_weights(r, on_level, off_level)
	limiter_gain = level * _limiter * on_amt
	limiter_pitch = r / LIMITER_RPM
	pit_gain = db_to_linear(-3.0) * _pit
	pit_pitch = r / PIT_RPM
	# The turbo spools up slowly and runs down slower; the hybrid drive whine
	# follows the revs and the load.
	var want := load_s * clampf((r - 5500.0) / 6000.0, 0.0, 1.0)
	spool = move_toward(spool, want, dt * (1.4 if want > spool else 0.7))
	turbo_gain = 0.32 * pow(spool, 1.5)
	turbo_pitch = 0.55 + 0.45 * pow(spool, 0.7)
	drive_gain = 0.22 * (0.35 + 0.65 * load_s) * clampf(speed / 12.0, 0.0, 1.0)
	drive_pitch = r / DRIVE_RPM


## The pops triggered since the last call, as gains (linear).
func take_pops() -> Array:
	var out := _pops
	_pops = []
	return out


func _pop(gain: float) -> void:
	if _pops.size() < 4:
		_pops.append(gain)


## Equal-power crossfade between the two bands either side of the rpm, in
## log rpm.
func _band_weights(r: float, on_level: float, off_level: float) -> void:
	var nb := BANDS.size()
	var k := 0
	var t := 0.0
	if r <= BANDS[0]:
		k = 0
	elif r >= BANDS[nb - 1]:
		k = nb - 1
	else:
		while k < nb - 2 and r >= BANDS[k + 1]:
			k += 1
		t = log(r / BANDS[k]) / log(BANDS[k + 1] / BANDS[k])
	for i in nb:
		var w := 0.0
		if i == k:
			w = cos(t * PI * 0.5)
		elif i == k + 1:
			w = sin(t * PI * 0.5)
		on_gain[i] = w * on_level
		off_gain[i] = w * off_level
		band_pitch[i] = r / BANDS[i]


# --- Baking -----------------------------------------------------------------

## One band's on-throttle loop (about 1.2 s).
static func bake_on(rpm: float, seed := 1) -> PackedFloat32Array:
	var period := int(roundf(RATE * 120.0 / rpm))
	var cycles := maxi(1, int(roundf(38400.0 / period)))
	var n := period * cycles
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(rpm)
	var events := _steady_events(n, cycles, rng, 0.05, 0.004, 0.0)
	return _render(n, events, rng, false)


## One band's overrun loop: the engine dragging the car with the throttle shut.
static func bake_off(rpm: float, seed := 2) -> PackedFloat32Array:
	var period := int(roundf(RATE * 120.0 / rpm))
	var cycles := maxi(1, int(roundf(38400.0 / period)))
	var n := period * cycles
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(rpm)
	var events := _steady_events(n, cycles, rng, 0.4, 0.012, 0.07)
	return _render(n, events, rng, true)


## The rev limiter: firing up to the limit, cutting and falling back, 12
## times a second.
static func bake_limiter() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := RATE * 3 / 4
	var events := _bouncing_events(n, 9, LIMITER_RPM - 180.0, LIMITER_RPM + 180.0, 0.55, 0.06, rng)
	return _render(n, events, rng, false)


## The pit lane limiter: a slower, deeper bounce as the speed is held.
static func bake_pit_limiter() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var n := RATE
	var events := _bouncing_events(n, 7, PIT_RPM - 350.0, PIT_RPM + 350.0, 0.6, 0.18, rng)
	return _render(n, events, rng, false)


## Firing events for a steady rpm: [position (samples), amplitude, width
## factor]. Six cylinders fire in each cycle, alternating banks; each has its
## own small difference in strength and timing, which gives the engine its
## character, plus a little randomness from cycle to cycle.
static func _steady_events(n: int, cycles: int, rng: RandomNumberGenerator, amp_jitter: float, time_jitter: float, misfire: float) -> Array:
	var cyl_amp := [1.0, 0.9, 1.06, 0.95, 1.03, 0.92]
	var cyl_off := [0.0, 0.012, -0.008, 0.015, -0.01, 0.006]
	var events := []
	var interval := float(n) / (cycles * 6)
	for c in cycles:
		for k in 6:
			var idx := c * 6 + k
			var pos: float = (idx + cyl_off[k] + rng.randf_range(-time_jitter, time_jitter)) * interval
			var amp: float = cyl_amp[k] * (1.0 + rng.randf_range(-amp_jitter, amp_jitter))
			if misfire > 0.0 and rng.randf() < misfire:
				amp *= 0.15
			var bank := 1.0 if k % 2 == 0 else 1.12
			events.append([pos, amp, interval, bank])
	return events


## Firing events for a bouncing rpm: `bounces` times over n samples the rpm
## rises from lo to hi while firing, then falls back with the ignition cut
## (amplitude `cut_amp`). The rpm curve is scaled so a whole number of
## firings fits the loop.
static func _bouncing_events(n: int, bounces: int, lo: float, hi: float, fire_share: float, cut_amp: float, rng: RandomNumberGenerator) -> Array:
	var seg := float(n) / bounces
	# Firings per sample at each sample: rpm / 60 * 3 / RATE.
	var rate := PackedFloat32Array()
	rate.resize(n)
	var total := 0.0
	for i in n:
		var u := fmod(i, seg) / seg
		var r := 0.0
		if u < fire_share:
			r = lerpf(lo, hi, sin(u / fire_share * PI * 0.5))
		else:
			r = lerpf(hi, lo, sin((u - fire_share) / (1.0 - fire_share) * PI * 0.5))
		rate[i] = r / 20.0 / RATE
		total += rate[i]
	var fix := roundf(total) / total
	var events := []
	# Start half a firing in, so exactly round(total) firings land in the loop.
	var ph := 0.5
	var count := 0
	for i in n:
		var step := rate[i] * fix
		var next := ph + step
		if floorf(next) > floorf(ph):
			var u := fmod(i, seg) / seg
			var firing := u < fire_share
			var k := count % 6
			var amp := (1.0 if firing else cut_amp) * (1.0 + rng.randf_range(-0.06, 0.06))
			if not firing and rng.randf() < 0.15:
				amp = 0.5
			var frac := (floorf(next) - ph) / maxf(step, 1e-9)
			events.append([i + frac, amp * (1.06 if k % 2 == 0 else 0.94), 1.0 / step, 1.0 if k % 2 == 0 else 1.12])
			count += 1
		ph = next
	return events


## Turns firing events into sound: a pressure pulse for each event, some
## combustion roar shaped by the same pulses, then the exhaust's resonances,
## a gentle top end and a little saturation.
static func _render(n: int, events: Array, rng: RandomNumberGenerator, overrun: bool) -> PackedFloat32Array:
	var pulse := PackedFloat32Array()
	pulse.resize(n)
	var env := PackedFloat32Array()
	env.resize(n)
	var width_share := 0.38 if overrun else 0.5
	for ev: Array in events:
		var t0: float = ev[0]
		var amp: float = ev[1]
		var interval: float = ev[2]
		var bank: float = ev[3]
		var w := interval * width_share * bank * rng.randf_range(0.94, 1.06)
		var i0 := int(ceilf(t0))
		var i1 := int(ceilf(t0 + w))
		for i in range(i0, i1):
			var x := (i - t0) / w
			# A sharp rise, a rounded body and a small suck-back after it.
			var s := sin(PI * x)
			var v := s * s * (1.0 - 1.45 * x) + (0.35 * exp(-x * 18.0) if x < 0.3 else 0.0)
			var j := posmod(i, n)
			pulse[j] += v * amp
			env[j] += s * amp
	var roar := AudioDsp.noise(n, rng)
	AudioDsp.multiply(roar, env)
	AudioDsp.chain(roar, [AudioDsp.bandpass(2600.0, 0.6), AudioDsp.lowpass(5200.0)], true)
	AudioDsp.mix_into(pulse, roar, 0.10 if overrun else 0.16)
	if overrun:
		AudioDsp.chain(pulse, [
			AudioDsp.highpass(45.0),
			AudioDsp.peak(230.0, 0.9, 5.0),
			AudioDsp.peak(900.0, 1.2, 2.0),
			AudioDsp.lowpass(2600.0, 0.6),
			AudioDsp.lowpass(4800.0),
		], true)
	else:
		AudioDsp.chain(pulse, [
			AudioDsp.highpass(50.0),
			AudioDsp.peak(320.0, 0.9, 4.0),
			AudioDsp.peak(1750.0, 1.1, 3.0),
			AudioDsp.lowpass(5800.0, 0.6),
			AudioDsp.lowpass(8500.0),
		], true)
	AudioDsp.level(pulse, -12.0, -1.0)
	AudioDsp.soft_clip(pulse, 1.3)
	AudioDsp.level(pulse, -16.0, -1.5)
	return pulse


## Turbo whistle at full spool: a tone near 3 kHz with a little vibrato,
## a faint overtone and the rush of air round it. A one second loop.
static func bake_turbo() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * 3000.0 * t + 4.0 * sin(TAU * 3.0 * t)
		out[i] = sin(ph) + 0.18 * sin(2.0 * ph + 0.5) + 0.08 * sin(1.5 * ph)
	var air := AudioDsp.noise(n, rng)
	AudioDsp.chain(air, [AudioDsp.bandpass(3000.0, 3.0), AudioDsp.bandpass(3000.0, 2.0)], true)
	AudioDsp.mix_into(out, air, 1.2)
	AudioDsp.level(out, -16.0, -3.0)
	return out


## The hybrid motor and the gears at DRIVE_RPM: a few clean whines with a
## slight flutter. A one second loop.
static func bake_drive() -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var flutter := 1.0 + 0.12 * sin(TAU * 13.0 * t)
		out[i] = (sin(TAU * 1900.0 * t) + 0.5 * sin(TAU * 2850.0 * t + 1.0) + 0.22 * sin(TAU * 4750.0 * t + 2.0)) * flutter
	AudioDsp.level(out, -16.0, -3.0)
	return out


## An exhaust pop or crackle (about 0.15 s).
static func bake_pop(seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + seed
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var crack := AudioDsp.noise(n, rng)
	var tau := rng.randf_range(0.008, 0.02)
	for i in n:
		crack[i] *= exp(-float(i) / RATE / tau)
	AudioDsp.chain(crack, [AudioDsp.bandpass(rng.randf_range(1100.0, 1900.0), 0.7), AudioDsp.lowpass(6000.0)], false)
	var thump_f := rng.randf_range(80.0, 120.0)
	for i in n:
		var t := float(i) / RATE
		out[i] = crack[i] * 3.0 + 0.6 * sin(TAU * thump_f * t * (1.0 - t * 1.5)) * exp(-t / 0.03)
	# A second, smaller crack for some of them.
	if seed % 2 == 1:
		var at := int(RATE * rng.randf_range(0.025, 0.05))
		for i in range(at, n):
			out[i] += crack[i - at] * 1.5
	AudioDsp.fade(out, 0.0005, 0.02)
	AudioDsp.normalize_peak(out, -2.0)
	return out
