class_name SoundBank
extends RefCounted
## Loads the baked sounds in assets/audio/ (and the Kenney files the game
## uses) once and shares them: every car's players point at the same
## streams. A missing file gives null, and callers then just stay quiet.
##
##   var s := SoundBank.stream("engine/on_3")     # res://assets/audio/engine/on_3.wav

const DIR := "res://assets/audio/"
const KENNEY := "res://assets/kenney/audio/"

static var _cache := {}


## A baked sound by name ("car/squeal"), or a full res:// path.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := name if name.begins_with("res://") else DIR + name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	else:
		push_warning("SoundBank: missing %s" % path)
	_cache[name] = s
	return s


## The length of a stream in seconds (0 when missing).
static func length(name: String) -> float:
	var s := stream(name)
	return s.get_length() if s else 0.0
