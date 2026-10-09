class_name LapReference
extends RefCounted
## A clean lap by the AI at full pace in a midfield car, per layout: the
## yardstick for AI qualifying times and Time Trial medals. Worked out once
## (about a second) and kept in user://reference_laps.cfg.

const PATH := "user://reference_laps.cfg"
## The car the reference is driven in (Solaris, midfield).
const TEAM := 5
## Bump when the car, the AI or the tracks change enough to move lap times.
const VERSION := 1

static var _cache := {}


## The reference lap for a layout, in seconds, dry.
static func time(track: Track) -> float:
	var key := "%s:%d" % [track.id, VERSION]
	if _cache.has(key):
		return _cache[key]
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var t := float(cfg.get_value("laps", key, 0.0))
	if t <= 0.0:
		t = measure(track)
		cfg.set_value("laps", key, t)
		cfg.save(PATH)
	_cache[key] = t
	return t


## Drives the lap: one car from a flying start, the second crossing of the
## line ends it.
static func measure(track: Track, team := TEAM, pace := 1.0) -> float:
	var race := Race.new(track, Race.Kind.PRACTICE, 99, 11)
	var e: Race.Entry = race.add_car(1, "Ref", team, 0, pace, {"consistency": 1.0})
	race.start()
	var limit := track.length / 20.0 + 200.0
	while race.clock < limit:
		race.step(Race.DT)
		if e.lap >= 2:
			return e.last_lap
	return track.length / 55.0


## Time Trial medal times: [gold, silver, bronze].
static func medals(track: Track) -> Array:
	var r := time(track)
	return [r * 1.005, r * 1.03, r * 1.07]


static func medal_for(track: Track, lap: float) -> int:
	if lap <= 0.0:
		return -1
	var m := medals(track)
	for i in m.size():
		if lap <= float(m[i]):
			return i
	return -1


const MEDAL_NAMES := ["Gold", "Silver", "Bronze"]
const MEDAL_COLORS := [Color("ffd23f"), Color("cfd8e3"), Color("d08a4e")]
