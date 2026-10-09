class_name Weather
extends RefCounted
## The weather for a weekend: how wet the road starts and when rain comes
## and goes, as a forecast the race follows ([[seconds, rain 0..1], ...]).

var wet := 0.0
var forecast: Array = []


## `kind`: dry, mixed, wet or random (which uses the circuit's chance of rain).
static func make(kind: String, rain_chance: float, rng: RandomNumberGenerator) -> Weather:
	var w := Weather.new()
	if kind == "random":
		var r := rng.randf()
		if r < rain_chance * 0.45:
			kind = "wet"
		elif r < rain_chance:
			kind = "mixed"
		else:
			kind = "dry"
	match kind:
		"wet":
			var heavy := rng.randf_range(0.5, 0.9)
			w.wet = heavy
			w.forecast = [[0.0, heavy], [rng.randf_range(300.0, 900.0), rng.randf_range(0.2, heavy)]]
		"mixed":
			# Dry to start, a shower part way through, then drying.
			var start := rng.randf_range(90.0, 400.0)
			var peak := rng.randf_range(0.45, 0.85)
			w.forecast = [[0.0, 0.0], [start, 0.0], [start + 60.0, peak], [start + rng.randf_range(240.0, 600.0), peak], [start + 900.0, 0.0]]
		_:
			w.forecast = []
	return w
