class_name Circuits
extends RefCounted
## Every circuit and layout in the game, in calendar order, with what the
## menus, the view and the race need to know about each.
##
## A layout's info: {"id", "venue" (the circuit's id), "name" (the circuit),
## "layout" ("Grand Prix", "National", ...), "round" (1 to 16, 0 for the
## Proving Ground), "theme" (the scenery: see THEMES), "time" (see TIMES),
## "rain" (0 to 1, the chance of a wet weekend), "laps" (a full-length race),
## "blurb" (a line for the menus), "clockwise" (which way round the lap
## runs; a figure of eight says which way its first loop turns),
## "length_km" (the lap, rounded: tools/circuit_check.gd checks it)}, and
## sometimes "air" (air density as a share of sea level, for a mountain
## circuit) and "max_slope" (the steepest climb, rise over run, where a
## layout is steeper than the usual 10 percent).

const THEMES := [
	"parkland", "harbour", "forest", "airfield", "desert", "city", "mountain",
	"lake", "countryside", "oval", "cliff", "hills", "canyon", "proving",
]
const TIMES := ["day", "dusk", "night", "dusk_to_night"]

const AUTO := TrackPlan.AUTO
const RO := TrackPlan.Runoff
const BA := TrackPlan.Barrier

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
			return ProvingGround.plan()
		"greenfield_gp":
			return _greenfield()
		"lumen_gp":
			return _port_lumen()
		"pineta_gp":
			return _monte_pineta()
		"ardenwood_gp":
			return _ardenwood()
	push_error("No circuit %s" % id)
	return ProvingGround.plan()


static func _all() -> Array:
	return [
		{"id": "greenfield_gp", "venue": "greenfield", "name": "Greenfield Park", "layout": "Grand Prix", "round": 1, "theme": "parkland", "time": "day", "rain": 0.25, "laps": 56, "clockwise": true, "length_km": 5.3, "blurb": "Parkland round a boating lake: medium speed and forgiving run-off."},
		{"id": "lumen_gp", "venue": "lumen", "name": "Port Lumen", "layout": "Grand Prix", "round": 2, "theme": "harbour", "time": "day", "rain": 0.15, "laps": 78, "clockwise": true, "length_km": 3.3, "blurb": "Harbour streets: slow, narrow and walled in. Qualifying decides the race."},
		{"id": "pineta_gp", "venue": "pineta", "name": "Monte Pineta", "layout": "Grand Prix", "round": 3, "theme": "forest", "time": "day", "rain": 0.2, "laps": 53, "clockwise": true, "length_km": 5.8, "blurb": "The temple of speed: long straights, three chicanes and the slipstream."},
		{"id": "proving", "venue": "proving", "name": "The Proving Ground", "layout": "Test Loop", "round": 0, "theme": "proving", "time": "day", "rain": 0.0, "laps": 5, "blurb": "A quiet loop to learn the car."},
	]


# --- 1 Greenfield Park ---------------------------------------------------

## Parkland round a boating lake, clockwise: a long main straight, a tight
## first corner, the lakeside sweeps and a fast back straight under the trees.
static func _greenfield() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 520.0
	p.pit_after = 220.0
	p.straight(AUTO)
	p.mark("pits_tower", {"side": -1, "distance": 45.0, "size": 30.0})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 220.0, "covered": true})
	p.right(85, 55).left(30, 120)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.straight(250).right(85, 42)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(200).left(40, 130).straight(520).right(50, 100)
	p.mark("lake", {"side": -1, "distance": 330.0, "size": 460.0, "boats": true})
	p.straight(260).esses(false, 45, 65).straight(160)
	p.right(30, 250).straight(420).right(90, 38)
	p.straight(AUTO).chicane(false, 50, 28, 12).straight(200)
	p.mark("forest", {"side": 1, "distance": 80.0, "size": 300.0})
	p.left(20, 250).straight(250).right(65, 50)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0, "covered": true})
	p.straight(200).right(45, 110)
	return p


# --- 2 Port Lumen --------------------------------------------------------

## Harbour streets, clockwise and walled in: up the hill from the first
## corner, round the casino square, down to the hairpin, through the tunnel
## under the hotel, then the harbour chicane and the swimming pool.
static func _port_lumen() -> TrackPlan:
	var p := TrackPlan.new().street()
	p.width = 11.0
	p.kerb_radius = 200.0
	p.start_at = 420.0
	p.pit_before = 280.0
	p.pit_after = 200.0
	p.straight(AUTO)
	p.mark("marina", {"side": -1, "distance": 90.0, "size": 260.0})
	p.mark("grandstand", {"side": 1, "distance": 25.0, "size": 120.0})
	p.right(90, 30)
	p.mark("grandstand", {"side": 1, "distance": 30.0, "size": 60.0})
	p.straight(AUTO, {"climb": 26.0}).left(15, 300, {"climb": 4.0}).left(70, 60)
	p.mark("buildings", {"side": 1, "distance": 60.0, "size": 160.0})
	p.right(70, 35).straight(150, {"climb": -9.0}).right(90, 25, {"climb": -3.0})
	p.mark("buildings", {"side": 1, "distance": 50.0, "size": 120.0})
	p.straight(110, {"climb": -6.0}).left(160, 14, {"climb": -1.0}).right(90, 25, {"climb": -3.0})
	p.straight(90, {"climb": -2.0}).right(90, 25, {"climb": -1.0})
	p.right(60, 300, {"feature": "tunnel", "climb": -2.0})
	p.mark("hotel", {"side": 1, "distance": 0.0, "size": 120.0, "over_track": true})
	p.straight(160, {"feature": "tunnel", "climb": -3.0}).straight(180)
	p.mark("sea", {"side": 1, "distance": 120.0, "size": 600.0})
	p.chicane(false, 50, 18, 10).straight(200).left(50, 50)
	p.mark("marina", {"side": -1, "distance": 80.0, "size": 220.0, "boats": true})
	p.straight(120).esses(false, 30, 60).straight(60).esses(true, 40, 40)
	p.mark("grandstand", {"side": 1, "distance": 25.0, "size": 80.0})
	p.straight(120).right(100, 20).straight(60).right(65, 30)
	return p


# --- 3 Monte Pineta ------------------------------------------------------

## A royal park of pines, clockwise: the long main straight into the first
## chicane, the great right-hander, the second chicane, two quick rights,
## the avenue under the trees, the fast chicane and the long final right.
static func _monte_pineta() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 600.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 260.0, "round": true})
	p.right(70, 20).straight(12).left(55, 25)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 140.0})
	p.straight(250).right(80, 330).straight(600)
	p.mark("forest", {"side": 1, "distance": 80.0, "size": 400.0, "trees": "pine"})
	p.chicane(false, 55, 22, 12).straight(300).right(80, 75)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(220).right(65, 70).straight(AUTO)
	p.mark("forest", {"side": -1, "distance": 90.0, "size": 500.0, "trees": "pine"})
	p.left(15, 400).straight(300).left(50, 80).right(70, 95).left(25, 110)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0})
	p.straight(1000).right(140, 110)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 200.0, "round": true})
	return p


# --- 4 Ardenwood ---------------------------------------------------------

## A forest valley, clockwise: the hairpin, down to the river and up the
## steep left-right beyond it, the long climb to the top chicane, down
## through the hairpin and the double left, then flat out back along the
## valley over the river bridge to the last chicane.
static func _ardenwood() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 450.0
	p.pit_before = 300.0
	p.pit_after = 200.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 160.0})
	p.right(170, 28)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(380, {"climb": -24.0}).left(35, 90, {"climb": -3.0}).right(65, 80, {"climb": 7.0}).left(20, 150, {"climb": 6.0})
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 120.0})
	p.straight(1000, {"climb": 30.0})
	p.mark("forest", {"side": 1, "distance": 70.0, "size": 600.0})
	p.right(50, 70).straight(30).left(45, 70).straight(200).right(70, 120, {"climb": -3.0})
	p.straight(AUTO, {"climb": -12.0}).right(150, 35, {"climb": -2.0})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 90.0})
	p.straight(250, {"climb": -10.0}).left(80, 120, {"climb": -6.0}).straight(250, {"climb": -10.0}).left(120, 130, {"climb": -12.0})
	p.mark("cliff", {"side": 1, "distance": 90.0, "size": 260.0})
	p.straight(300, {"climb": -4.0}).right(40, 100).left(40, 100).straight(300).right(70, 120)
	p.mark("forest", {"side": -1, "distance": 80.0, "size": 500.0})
	p.straight(500, {"climb": 6.0}).straight(160, {"feature": "bridge"})
	p.mark("river", {"side": 1, "distance": 0.0, "size": 60.0, "across": true})
	p.straight(400, {"climb": 12.0}).left(40, 300, {"climb": 6.0}).straight(500, {"climb": 12.0})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.chicane(true, 55, 25, 15).right(100, 100, {"climb": 4.0})
	return p
