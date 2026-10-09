class_name Circuits
extends RefCounted
## Every circuit and layout in the game, in calendar order, with what the
## menus, the view and the race need to know about each.
##
## A layout's info: {"id", "venue" (the circuit's id), "name" (the circuit),
## "layout" ("Grand Prix", "National", ...), "round" (1 to 16, 0 for the
## Proving Ground), "theme" (the scenery: see THEMES), "time" (see TIMES),
## "rain" (0 to 1, the chance of a wet weekend), "laps" (a full-length race),
## "blurb" (a line for the menus)}.

const THEMES := [
	"parkland", "harbour", "forest", "airfield", "desert", "city", "mountain",
	"lake", "countryside", "oval", "cliff", "hills", "canyon", "proving",
]
const TIMES := ["day", "dusk", "night", "dusk_to_night"]

static var _tracks := {}


## Every layout id, in calendar order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _all():
		out.append(i.id)
	return out


static func info(id: String) -> Dictionary:
	for i in _all():
		if i.id == id:
			return i
	return {}


## The built track for a layout (built once, then kept).
static func track(id: String) -> Track:
	if not _tracks.has(id):
		var i := info(id)
		_tracks[id] = Track.build(plan(id), id, "%s %s" % [i.get("name", id), i.get("layout", "")])
	return _tracks[id]


static func plan(id: String) -> TrackPlan:
	match id:
		"proving":
			return _proving()
	push_error("No circuit %s" % id)
	return _proving()


static func _all() -> Array:
	return [
		{"id": "proving", "venue": "proving", "name": "The Proving Ground", "layout": "Test Loop", "round": 0, "theme": "proving", "time": "day", "rain": 0.0, "laps": 5, "blurb": "A quiet loop to learn the car."},
	]


static func _proving() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 300.0
	p.straight(TrackPlan.AUTO).right(90, 60).straight(400).right(60, 120).left(60, 90).straight(TrackPlan.AUTO).right(90, 45).straight(600).right(90, 150).straight(900).right(90, 70)
	return p
