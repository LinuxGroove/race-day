class_name AudioDsp
extends RefCounted
## A small kit for making sounds offline: noise, biquad filters, envelopes,
## levels and writing WAV files. `tools/bake_engine.gd` uses it (through
## EngineSynth and SoundSynth) to bake the loops in `assets/audio/`; nothing
## here runs while the game plays.
##
## Loops are made seamless by filtering them circularly: `filter_loop` runs a
## filter over the end of the buffer first, so its state at the start is what
## it would be coming round from the end. Anything periodic in the input
## (pulses, envelopes made by `smooth_loop`) stays periodic in the output.

const RATE := 32000


## Biquad coefficients [b0, b1, b2, a1, a2], from the RBJ audio EQ cookbook.
static func lowpass(f: float, q := 0.707) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var c := cos(w)
	var a0 := 1.0 + al
	return PackedFloat64Array([(1.0 - c) * 0.5 / a0, (1.0 - c) / a0, (1.0 - c) * 0.5 / a0, -2.0 * c / a0, (1.0 - al) / a0])


static func highpass(f: float, q := 0.707) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var c := cos(w)
	var a0 := 1.0 + al
	return PackedFloat64Array([(1.0 + c) * 0.5 / a0, -(1.0 + c) / a0, (1.0 + c) * 0.5 / a0, -2.0 * c / a0, (1.0 - al) / a0])


## Band-pass with 0 dB at the centre.
static func bandpass(f: float, q := 1.0) -> PackedFloat64Array:
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var c := cos(w)
	var a0 := 1.0 + al
	return PackedFloat64Array([al / a0, 0.0, -al / a0, -2.0 * c / a0, (1.0 - al) / a0])


## Peaking EQ: `db` of boost (or cut) around f.
static func peak(f: float, q: float, db: float) -> PackedFloat64Array:
	var a := pow(10.0, db / 40.0)
	var w := TAU * f / RATE
	var al := sin(w) / (2.0 * q)
	var c := cos(w)
	var a0 := 1.0 + al / a
	return PackedFloat64Array([(1.0 + al * a) / a0, -2.0 * c / a0, (1.0 - al * a) / a0, -2.0 * c / a0, (1.0 - al / a) / a0])


## Runs a biquad over a one-shot buffer, in place.
static func filter(buf: PackedFloat32Array, c: PackedFloat64Array) -> void:
	_run(buf, c, 0, false)


## Runs a biquad over a looping buffer, in place, so the result still loops.
static func filter_loop(buf: PackedFloat32Array, c: PackedFloat64Array) -> void:
	_run(buf, c, mini(buf.size(), 16000), true)


static func _run(buf: PackedFloat32Array, c: PackedFloat64Array, warm: int, _loop: bool) -> void:
	var b0 := c[0]
	var b1 := c[1]
	var b2 := c[2]
	var a1 := c[3]
	var a2 := c[4]
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var n := buf.size()
	# Warm the filter on the end of the loop so the start joins it smoothly.
	for i in range(n - warm, n):
		var x: float = buf[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
	for i in n:
		var x: float = buf[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] = y


## Chains several filters over a buffer.
static func chain(buf: PackedFloat32Array, filters: Array, loop: bool) -> void:
	for c: PackedFloat64Array in filters:
		if loop:
			filter_loop(buf, c)
		else:
			filter(buf, c)


## White noise in -1..1.
static func noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## A smooth random curve that loops: `points` random values from lo to hi,
## spread evenly over n samples and joined with cosine easing.
static func smooth_loop(n: int, points: int, lo: float, hi: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	points = maxi(points, 1)
	var vals := PackedFloat32Array()
	for k in points:
		vals.append(rng.randf_range(lo, hi))
	var out := PackedFloat32Array()
	out.resize(n)
	var seg := float(n) / points
	for i in n:
		var p := i / seg
		var k := int(p)
		var t := p - k
		var a: float = vals[k % points]
		var b: float = vals[(k + 1) % points]
		out[i] = lerpf(a, b, 0.5 - 0.5 * cos(t * PI))
	return out


static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, at := 0) -> void:
	var n := mini(src.size(), dst.size() - at)
	for i in n:
		dst[at + i] += src[i] * gain


static func multiply(dst: PackedFloat32Array, env: PackedFloat32Array) -> void:
	for i in dst.size():
		dst[i] *= env[i]


static func scale(buf: PackedFloat32Array, g: float) -> void:
	for i in buf.size():
		buf[i] *= g


## tanh soft clipping, scaled so a full-scale input stays near full scale.
static func soft_clip(buf: PackedFloat32Array, drive: float) -> void:
	var norm := 1.0 / tanh(drive)
	for i in buf.size():
		buf[i] = tanh(buf[i] * drive) * norm


static func rms(buf: PackedFloat32Array) -> float:
	var s := 0.0
	for v in buf:
		s += v * v
	return sqrt(s / maxf(buf.size(), 1))


static func peak_of(buf: PackedFloat32Array) -> float:
	var p := 0.0
	for v in buf:
		p = maxf(p, absf(v))
	return p


## Scales to an RMS level (dBFS), then makes sure the peak stays under
## `ceiling_db` (soft-clipping the few samples above it).
static func level(buf: PackedFloat32Array, rms_db: float, ceiling_db := -1.0) -> void:
	var r := rms(buf)
	if r <= 0.0:
		return
	scale(buf, db_to_linear(rms_db) / r)
	var ceiling := db_to_linear(ceiling_db)
	if peak_of(buf) > ceiling:
		for i in buf.size():
			var v: float = buf[i]
			if absf(v) > ceiling * 0.8:
				var over := (absf(v) - ceiling * 0.8) / (ceiling * 0.2)
				buf[i] = signf(v) * ceiling * (0.8 + 0.2 * tanh(over))


## Scales so the loudest sample sits at `peak_db`.
static func normalize_peak(buf: PackedFloat32Array, peak_db: float) -> void:
	var p := peak_of(buf)
	if p > 0.0:
		scale(buf, db_to_linear(peak_db) / p)


## Short linear fades at the ends of a one-shot, so it starts and ends at 0.
static func fade(buf: PackedFloat32Array, in_s: float, out_s: float) -> void:
	var n := buf.size()
	var fi := mini(int(in_s * RATE), n)
	var fo := mini(int(out_s * RATE), n)
	for i in fi:
		buf[i] *= float(i) / fi
	for i in fo:
		buf[n - 1 - i] *= float(i) / fo


## A sine (with optional linear glide) added into buf from `at` for `len_s`,
## shaped by an attack and an exponential decay.
static func add_tone(buf: PackedFloat32Array, f0: float, f1: float, at: float, len_s: float, gain: float, attack := 0.005, decay := 0.0) -> void:
	var start := int(at * RATE)
	var n := mini(int(len_s * RATE), buf.size() - start)
	var ph := 0.0
	var rel := mini(int(0.01 * RATE), n)
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, float(i) / maxf(n, 1))
		ph += TAU * f / RATE
		var env := minf(1.0, t / maxf(attack, 0.0001))
		if decay > 0.0:
			env *= exp(-t / decay)
		if i > n - rel:
			env *= float(n - i) / rel
		buf[start + i] += sin(ph) * env * gain


## Writes 16-bit mono PCM. A loop gets a `smpl` chunk with its loop points.
## When the file has no `.import` yet, writes one that keeps it uncompressed
## (and looping), so loops join without a click.
static func save_wav(path: String, buf: PackedFloat32Array, loop: bool, rate := RATE) -> Error:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(roundf(buf[i] * 32767.0)), -32768, 32767))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var smpl_size := 36 + 24 if loop else 0
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(4 + 24 + 8 + data.size() + (8 + smpl_size if loop else 0))
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	if loop:
		f.store_buffer("smpl".to_ascii_buffer())
		f.store_32(smpl_size)
		for v in [0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0]:
			f.store_32(v)
		for v in [0, 0, 0, n - 1, 0, 0]:
			f.store_32(v)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	var imp := path + ".import"
	if not FileAccess.file_exists(imp):
		var g := FileAccess.open(imp, FileAccess.WRITE)
		if g:
			g.store_string("[remap]\n\nimporter=\"wav\"\ntype=\"AudioStreamWAV\"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=%d\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n" % (2 if loop else 1))
			g.close()
	return OK


## Decodes an AudioStreamWAV (16-bit PCM mono, or the left channel of
## stereo) into floats, for checks and offline renders.
static func wav_samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var ch := 2 if w.stereo else 1
	var d := w.data
	var n := d.size() / (2 * ch)
	out.resize(n)
	for i in n:
		out[i] = d.decode_s16(i * 2 * ch) / 32768.0
	return out
