class_name Circuits
extends RefCounted
## Every circuit and layout in the game, in calendar order, with what the
## menus, the view and the race need to know about each.
##
## A layout's id is its circuit's id for the Grand Prix layout (the one a
## championship round uses, e.g. "greenfield") and "<circuit>_<layout>" for
## the others ("greenfield_club", "bellwood_oval").
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


## The Grand Prix layout of each round, in calendar order: one per
## circuit, without the Proving Ground or the second layouts.
static func calendar() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _all():
		if int(i.round) > 0 and i.id == i.venue:
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
		"greenfield":
			return _greenfield()
		"port_lumen":
			return _port_lumen()
		"monte_pineta":
			return _monte_pineta()
		"ardenwood":
			return _ardenwood()
		"kingsfield":
			return _kingsfield()
		"twin_bridges":
			return _twin_bridges()
		"sandhaven":
			return _sandhaven()
		"neon_marina":
			return _neon_marina()
		"sierra_alta":
			return _sierra_alta()
		"lakeside_isle":
			return _lakeside_isle()
		"hay_valley":
			return _hay_valley()
		"bellwood":
			return _bellwood()
		"bellwood_oval":
			return _bellwood_oval()
		"cliffside":
			return _cliffside()
		"misty_hills":
			return _misty_hills()
		"redrock_canyon":
			return _redrock_canyon()
		"harbour_lights":
			return _harbour_lights()
		"greenfield_club":
			return _greenfield_club()
		"port_lumen_reverse":
			return _port_lumen().reversed()
		"monte_pineta_junior":
			return _monte_pineta_junior()
		"ardenwood_reverse":
			return _ardenwood().reversed()
		"kingsfield_international":
			return _kingsfield_international()
		"twin_bridges_reverse":
			return _twin_bridges().reversed()
		"sandhaven_reverse":
			return _sandhaven().reversed()
		"neon_marina_short":
			return _neon_marina_short()
		"sierra_alta_reverse":
			return _sierra_alta().reversed()
		"lakeside_isle_reverse":
			return _lakeside_isle().reversed()
		"hay_valley_reverse":
			return _hay_valley().reversed()
		"cliffside_reverse":
			return _cliffside().reversed()
		"misty_hills_reverse":
			return _misty_hills_reverse()
		"redrock_canyon_national":
			return _redrock_canyon_national()
		"harbour_lights_short":
			return _harbour_lights_short()
	push_error("No circuit %s" % id)
	return ProvingGround.plan()


static func _all() -> Array:
	return [
		{"id": "greenfield", "venue": "greenfield", "name": "Greenfield Park", "layout": "Grand Prix", "round": 1, "theme": "parkland", "time": "day", "rain": 0.25, "laps": 60, "clockwise": true, "length_km": 5.10, "blurb": "Parkland round a boating lake: medium speed and forgiving run-off."},
		{"id": "greenfield_club", "venue": "greenfield", "name": "Greenfield Park", "layout": "Club", "round": 1, "theme": "parkland", "time": "day", "rain": 0.25, "laps": 84, "clockwise": true, "length_km": 3.61, "blurb": "The short way round: up the middle of the park beside the lake."},
		{"id": "port_lumen", "venue": "port_lumen", "name": "Port Lumen", "layout": "Grand Prix", "round": 2, "theme": "harbour", "time": "day", "rain": 0.15, "laps": 88, "clockwise": true, "length_km": 3.47, "blurb": "Harbour streets: slow, narrow and walled in. Qualifying decides the race."},
		{"id": "port_lumen_reverse", "venue": "port_lumen", "name": "Port Lumen", "layout": "Reverse", "round": 2, "theme": "harbour", "time": "day", "rain": 0.15, "laps": 88, "clockwise": false, "length_km": 3.47, "blurb": "The harbour streets the other way: down the hill and up through the tunnel."},
		{"id": "monte_pineta", "venue": "monte_pineta", "name": "Monte Pineta", "layout": "Grand Prix", "round": 3, "theme": "forest", "time": "day", "rain": 0.2, "laps": 56, "clockwise": true, "length_km": 5.44, "blurb": "The temple of speed: long straights, three chicanes and the slipstream."},
		{"id": "monte_pineta_junior", "venue": "monte_pineta", "name": "Monte Pineta", "layout": "Junior", "round": 3, "theme": "forest", "time": "day", "rain": 0.2, "laps": 77, "clockwise": true, "length_km": 3.97, "blurb": "The first chicane, a link road through the pines and the long final right."},
		{"id": "ardenwood", "venue": "ardenwood", "name": "Ardenwood", "layout": "Grand Prix", "round": 4, "theme": "forest", "time": "day", "rain": 0.45, "laps": 44, "clockwise": true, "length_km": 6.97, "blurb": "A forest valley: big climbs, fast sweeps and a bridge over the river."},
		{"id": "ardenwood_reverse", "venue": "ardenwood", "name": "Ardenwood", "layout": "Reverse", "round": 4, "theme": "forest", "time": "day", "rain": 0.45, "laps": 44, "clockwise": false, "length_km": 6.97, "blurb": "The forest valley the other way: down the long hill and up from the river."},
		{"id": "kingsfield", "venue": "kingsfield", "name": "Kingsfield", "layout": "Grand Prix", "round": 5, "theme": "airfield", "time": "day", "rain": 0.4, "laps": 58, "clockwise": true, "length_km": 5.23, "blurb": "A former airfield: very fast, flowing corners on a wide, open track."},
		{"id": "kingsfield_international", "venue": "kingsfield", "name": "Kingsfield", "layout": "International", "round": 5, "theme": "airfield", "time": "day", "rain": 0.4, "laps": 63, "clockwise": true, "length_km": 4.87, "blurb": "Across the airfield from the loop to the hangar straight."},
		{"id": "twin_bridges", "venue": "twin_bridges", "name": "Twin Bridges", "layout": "Grand Prix", "round": 6, "theme": "parkland", "time": "day", "rain": 0.35, "laps": 62, "clockwise": true, "length_km": 4.95, "blurb": "A figure of eight: technical esses, a hairpin and the crossover bridge."},
		{"id": "twin_bridges_reverse", "venue": "twin_bridges", "name": "Twin Bridges", "layout": "Reverse", "round": 6, "theme": "parkland", "time": "day", "rain": 0.35, "laps": 62, "clockwise": false, "length_km": 4.95, "blurb": "The figure of eight the other way round, still over the bridge."},
		{"id": "sandhaven", "venue": "sandhaven", "name": "Sandhaven", "layout": "Grand Prix", "round": 7, "theme": "desert", "time": "night", "rain": 0.0, "laps": 53, "clockwise": true, "length_km": 5.73, "blurb": "A desert night race: hard braking zones and tyres that wear fast."},
		{"id": "sandhaven_reverse", "venue": "sandhaven", "name": "Sandhaven", "layout": "Reverse", "round": 7, "theme": "desert", "time": "night", "rain": 0.0, "laps": 53, "clockwise": false, "length_km": 5.73, "blurb": "The desert night the other way: new braking zones on old straights."},
		{"id": "neon_marina", "venue": "neon_marina", "name": "Neon Marina", "layout": "Grand Prix", "round": 8, "theme": "city", "time": "night", "rain": 0.2, "laps": 66, "clockwise": false, "length_km": 4.60, "blurb": "Twenty corners between the city towers at night. The walls punish mistakes."},
		{"id": "neon_marina_short", "venue": "neon_marina", "name": "Neon Marina", "layout": "Short", "round": 8, "theme": "city", "time": "night", "rain": 0.2, "laps": 70, "clockwise": false, "length_km": 4.36, "blurb": "The bay, the bridge and a quicker way back through the city."},
		{"id": "sierra_alta", "venue": "sierra_alta", "name": "Sierra Alta", "layout": "Grand Prix", "round": 9, "theme": "mountain", "time": "day", "rain": 0.2, "laps": 75, "clockwise": true, "length_km": 4.07, "air": 0.78, "blurb": "High in the mountains: thin air, less downforce and a stadium section."},
		{"id": "sierra_alta_reverse", "venue": "sierra_alta", "name": "Sierra Alta", "layout": "Reverse", "round": 9, "theme": "mountain", "time": "day", "rain": 0.2, "laps": 75, "clockwise": false, "length_km": 4.07, "air": 0.78, "blurb": "Into the stadium first, then down the mountainside the other way."},
		{"id": "lakeside_isle", "venue": "lakeside_isle", "name": "Lakeside Isle", "layout": "Grand Prix", "round": 10, "theme": "lake", "time": "day", "rain": 0.3, "laps": 77, "clockwise": true, "length_km": 3.95, "blurb": "An island in a river: stop and go, a hairpin and a wall at the last chicane."},
		{"id": "lakeside_isle_reverse", "venue": "lakeside_isle", "name": "Lakeside Isle", "layout": "Reverse", "round": 10, "theme": "lake", "time": "day", "rain": 0.3, "laps": 77, "clockwise": false, "length_km": 3.95, "blurb": "The island the other way round, with the hairpin to start."},
		{"id": "hay_valley", "venue": "hay_valley", "name": "Hay Valley", "layout": "Grand Prix", "round": 11, "theme": "countryside", "time": "day", "rain": 0.35, "laps": 48, "clockwise": true, "length_km": 6.35, "blurb": "An old countryside circuit: narrow, cambered and quick, with grass beside the kerbs."},
		{"id": "hay_valley_reverse", "venue": "hay_valley", "name": "Hay Valley", "layout": "Reverse", "round": 11, "theme": "countryside", "time": "day", "rain": 0.35, "laps": 48, "clockwise": false, "length_km": 6.35, "blurb": "The old countryside lap the other way round."},
		{"id": "bellwood", "venue": "bellwood", "name": "Bellwood Speedway", "layout": "Road Course", "round": 12, "theme": "oval", "time": "day", "rain": 0.15, "laps": 66, "clockwise": false, "length_km": 4.59, "blurb": "One banked corner flat out, then a twisty infield."},
		{"id": "cliffside", "venue": "cliffside", "name": "Cliffside", "layout": "Grand Prix", "round": 13, "theme": "cliff", "time": "day", "rain": 0.25, "laps": 61, "clockwise": true, "length_km": 4.96, "blurb": "Coastal cliffs above the sea: blind crests and one steep drop."},
		{"id": "cliffside_reverse", "venue": "cliffside", "name": "Cliffside", "layout": "Reverse", "round": 13, "theme": "cliff", "time": "day", "rain": 0.25, "laps": 61, "clockwise": false, "length_km": 4.96, "blurb": "The cliffs the other way: the drop becomes a climb."},
		{"id": "misty_hills", "venue": "misty_hills", "name": "Misty Hills", "layout": "Grand Prix", "round": 14, "theme": "hills", "time": "day", "rain": 0.65, "laps": 70, "clockwise": false, "length_km": 4.39, "blurb": "The rain round: a short, busy lap through wooded hills, anticlockwise."},
		{"id": "misty_hills_reverse", "venue": "misty_hills", "name": "Misty Hills", "layout": "Reverse", "round": 14, "theme": "hills", "time": "day", "rain": 0.65, "laps": 70, "clockwise": true, "length_km": 4.39, "blurb": "Clockwise through the misty woods."},
		{"id": "redrock_canyon", "venue": "redrock_canyon", "name": "Redrock Canyon", "layout": "Grand Prix", "round": 15, "theme": "canyon", "time": "day", "rain": 0.1, "laps": 55, "clockwise": false, "length_km": 5.50, "max_slope": 0.125, "blurb": "A red-rock canyon: a steep climb to the first corner and wide run-off."},
		{"id": "redrock_canyon_national", "venue": "redrock_canyon", "name": "Redrock Canyon", "layout": "National", "round": 15, "theme": "canyon", "time": "day", "rain": 0.1, "laps": 75, "clockwise": false, "length_km": 4.05, "max_slope": 0.125, "blurb": "Up the climb and straight along the canyon floor to the stadium."},
		{"id": "harbour_lights", "venue": "harbour_lights", "name": "Harbour Lights", "layout": "Grand Prix", "round": 16, "theme": "harbour", "time": "dusk_to_night", "rain": 0.05, "laps": 59, "clockwise": false, "length_km": 5.14, "blurb": "The finale: a marina island under the hotel bridge, from dusk into the night."},
		{"id": "harbour_lights_short", "venue": "harbour_lights", "name": "Harbour Lights", "layout": "Short", "round": 16, "theme": "harbour", "time": "dusk_to_night", "rain": 0.05, "laps": 73, "clockwise": false, "length_km": 4.17, "blurb": "Straight up the island to the marina, missing the long run by the water."},
		{"id": "bellwood_oval", "venue": "bellwood", "name": "Bellwood Speedway", "layout": "Oval", "round": 12, "theme": "oval", "time": "day", "rain": 0.15, "laps": 68, "clockwise": false, "length_km": 4.47, "blurb": "The bonus oval: two banked turns, flat out all the way round."},
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
	p.straight(AUTO, {"climb": 22.0}).left(15, 300, {"climb": 6.0}).left(70, 60, {"climb": 2.0})
	p.mark("buildings", {"side": 1, "distance": 60.0, "size": 160.0})
	p.right(70, 35).straight(150, {"climb": -9.0}).right(90, 25, {"climb": -3.0})
	p.mark("buildings", {"side": 1, "distance": 50.0, "size": 120.0})
	p.straight(110, {"climb": -6.0}).left(160, 14, {"climb": -1.0}).right(90, 25, {"climb": -3.0})
	p.straight(90, {"climb": -2.0}).right(90, 25, {"climb": -1.0})
	p.right(60, 300, {"feature": "tunnel", "climb": -2.0})
	p.mark("hotel", {"side": 1, "distance": 0.0, "size": 120.0, "over_track": true})
	p.straight(160, {"feature": "tunnel", "climb": -3.0}).straight(180)
	p.mark("sea", {"side": 1, "distance": 420.0, "size": 600.0})
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
	p.left(15, 400).straight(300).left(50, 85).right(70, 105).left(25, 120)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0})
	p.straight(1000).right(140, 110)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 200.0, "round": true})
	return p


# --- 4 Ardenwood ---------------------------------------------------------

static func _ardenwood() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 450.0
	p.pit_before = 300.0
	p.pit_after = 200.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 160.0})
	p.right(170, 28)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(380, {"climb": -20.0}).left(30, 90, {"climb": -2.0})
	p.mark("river", {"side": -1, "distance": 30.0, "size": 40.0, "across": true})
	p.right(60, 95, {"climb": 8.0}).left(20, 200, {"climb": 5.0})
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 120.0})
	p.straight(1300, {"climb": 40.0})
	p.mark("forest", {"side": -1, "distance": 90.0, "size": 600.0})
	p.right(50, 60).straight(40).left(50, 60)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(150).right(80, 90, {"climb": -3.0}).straight(AUTO, {"climb": -6.0}).right(120, 35, {"climb": -2.0})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 90.0})
	p.straight(150, {"climb": -10.0}).left(70, 120, {"climb": -8.0}).straight(150, {"climb": -8.0}).left(40, 130, {"climb": -4.0})
	p.mark("cliff", {"side": 1, "distance": 100.0, "size": 260.0})
	p.esses(true, 35, 110).right(90, 100, {"climb": -2.0})
	p.mark("forest", {"side": 1, "distance": 90.0, "size": 500.0})
	p.straight(300, {"climb": 2.0}).straight(140, {"feature": "bridge"})
	p.mark("river", {"side": 1, "distance": 0.0, "size": 60.0, "across": true})
	p.right(60, 250, {"climb": 8.0}).straight(100, {"climb": 2.0}).right(30, 200, {"climb": 2.0}).straight(800, {"climb": -6.0})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.chicane(true, 55, 25, 15, {"climb": 0.7}).left(90, 60, {"climb": 2.0})
	return p


# --- 5 Kingsfield --------------------------------------------------------

## A wartime airfield, clockwise, wide and open: the fast first right, the
## slow loop, the long straight to the twisty infield, then the great fast
## esses, the hangar straight and the long final right.
static func _kingsfield() -> TrackPlan:
	var p := TrackPlan.new().modern()
	p.width = 15.0
	p.start_at = 520.0
	p.pit_after = 240.0
	p.straight(AUTO)
	p.mark("pits_tower", {"side": -1, "distance": 50.0, "size": 30.0})
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 220.0, "covered": true})
	p.right(60, 200).left(30, 220).right(90, 40)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.left(130, 25).left(50, 100).straight(400)
	p.mark("hangars", {"side": 1, "distance": 110.0, "size": 300.0})
	p.left(90, 50)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 140.0})
	p.right(180, 55).right(20, 200).straight(500).right(130, 150)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 140.0})
	p.left(35, 150).right(50, 110).left(60, 90).right(70, 85).left(25, 150)
	p.mark("hangars", {"side": -1, "distance": 90.0, "size": 60.0, "radar": true})
	p.straight(1250)
	p.mark("hangars", {"side": 1, "distance": 120.0, "size": 260.0})
	p.right(90, 110).straight(AUTO).chicane(false, 40, 30, 10)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.right(90, 70)
	return p


# --- 6 Twin Bridges ------------------------------------------------------

## A figure of eight like the Racing Kit's own circuit: the first loop turns
## right through the long esses and passes under the bridge, the second
## turns left through the hairpin and the double left, crosses over the
## first, and ends with the fast left and the last chicane.
static func _twin_bridges() -> TrackPlan:
	var p := TrackPlan.new()
	p.winding = 0
	p.start_at = 500.0
	p.pit_after = 240.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 220.0, "covered": true})
	p.mark("big_screen", {"side": -1, "distance": 60.0, "size": 30.0})
	p.right(60, 120).right(80, 70)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.left(50, 90, {"climb": 1.5}).right(60, 80, {"climb": 1.5}).left(60, 80, {"climb": 1.5}).right(40, 100, {"climb": 1.5})
	p.left(60, 150, {"climb": 4.0}).straight(200).right(40, 100, {"climb": -2.0}).right(70, 50, {"climb": -2.0})
	p.straight(250, {"climb": -6.0}).straight(700, {"feature": "under"})
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 100.0})
	p.straight(300).left(160, 22)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.right(60, 250).left(150, 70, {"climb": 3.0})
	p.mark("forest", {"side": 1, "distance": 80.0, "size": 300.0})
	p.straight(160, {"climb": 7.0}).straight(AUTO, {"feature": "over"})
	p.left(80, 220, {"climb": -4.0}).chicane(true, 50, 22, 10, {"climb": -0.7}).right(150, 150, {"climb": -4.0})
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	return p


# --- 7 Sandhaven ---------------------------------------------------------

## Desert under floodlights, clockwise: long straights into hard stops at
## tight corners, a fast run of esses through the dunes and a hairpin.
static func _sandhaven() -> TrackPlan:
	var p := TrackPlan.new().desert()
	p.width = 15.0
	p.start_at = 520.0
	p.pit_after = 240.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 240.0, "covered": true})
	p.mark("pits_tower", {"side": -1, "distance": 50.0, "size": 40.0})
	p.right(100, 28).left(25, 80).right(15, 300)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 140.0})
	p.straight(AUTO).right(95, 38)
	p.mark("dunes", {"side": 1, "distance": 160.0, "size": 400.0})
	p.straight(600).esses(false, 40, 110).straight(100).right(130, 22)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 100.0})
	p.left(80, 35, {"climb": -6.0}).straight(400, {"climb": -2.0})
	p.mark("rock_wall", {"side": -1, "distance": 120.0, "size": 300.0})
	p.left(70, 60, {"climb": 2.0}).right(70, 160, {"climb": 3.0}).straight(500, {"climb": 3.0}).right(80, 45)
	p.mark("dunes", {"side": 1, "distance": 160.0, "size": 500.0})
	p.straight(900).right(45, 45)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 140.0})
	return p


# --- 8 Neon Marina -------------------------------------------------------

static func _neon_marina() -> TrackPlan:
	var p := TrackPlan.new().street()
	p.width = 12.0
	p.kerb_radius = 200.0
	p.start_at = 500.0
	p.pit_side = 1
	p.pit_before = 280.0
	p.pit_after = 200.0
	p.straight(AUTO)
	p.mark("marina", {"side": -1, "distance": 220.0, "size": 300.0, "boats": true})
	p.mark("grandstand", {"side": 1, "distance": 22.0, "size": 200.0})
	p.mark("buildings", {"side": 1, "distance": 90.0, "size": 260.0, "towers": true})
	p.left(40, 80).right(40, 80).straight(150).left(90, 30)
	p.mark("grandstand", {"side": -1, "distance": 25.0, "size": 80.0})
	p.straight(300, {"feature": "bridge"})
	p.mark("marina", {"side": -1, "distance": 0.0, "size": 120.0, "across": true})
	p.left(90, 28).straight(100).right(90, 30).straight(120).right(90, 30)
	p.mark("big_screen", {"side": -1, "distance": 30.0, "size": 30.0})
	p.straight(100).left(90, 28).straight(200).left(90, 30)
	p.mark("buildings", {"side": 1, "distance": 80.0, "size": 220.0, "towers": true})
	p.straight(150).chicane(true, 45, 25, 12).straight(200).right(90, 30)
	p.mark("grandstand", {"side": -1, "distance": 25.0, "size": 80.0})
	p.straight(120).left(90, 30).straight(100).left(30, 60).right(30, 60).straight(420)
	p.mark("buildings", {"side": 1, "distance": 80.0, "size": 200.0, "towers": true})
	p.left(90, 28).straight(150).right(90, 30).straight(80).left(90, 30)
	p.mark("grandstand", {"side": 1, "distance": 25.0, "size": 100.0})
	p.straight(AUTO).left(60, 60).right(60, 60).straight(150).left(90, 35)
	p.mark("buildings", {"side": 1, "distance": 80.0, "size": 200.0, "towers": true})
	return p


# --- 9 Sierra Alta -------------------------------------------------------

## A mountain circuit in thin air, clockwise: the long main straight into
## the first chicane, a hairpin, the fast esses on the hillside, then the
## stadium section between the round grandstands and the long last right.
static func _sierra_alta() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 560.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 220.0})
	p.mark("hills", {"side": -1, "distance": 300.0, "size": 500.0})
	p.right(75, 35).left(50, 40).right(40, 60)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 140.0})
	p.straight(300).left(40, 35).right(60, 35).straight(AUTO, {"climb": 4.0}).right(120, 30)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 90.0})
	p.straight(200, {"climb": 3.0}).left(40, 120).right(50, 110, {"climb": 2.0}).left(40, 120).right(30, 150, {"climb": -2.0}).left(25, 150)
	p.mark("hills", {"side": 1, "distance": 220.0, "size": 600.0})
	p.straight(700, {"climb": -3.0}).right(90, 60, {"climb": -2.0}).straight(400, {"climb": -2.0})
	p.mark("grandstand", {"side": -1, "distance": 60.0, "size": 220.0, "round": true, "stadium": true})
	p.left(60, 30).right(120, 30).left(60, 35)
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 160.0, "round": true, "stadium": true})
	p.right(90, 130)
	return p


# --- 10 Lakeside Isle ----------------------------------------------------

static func _lakeside_isle() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 520.0
	p.pit_after = 220.0
	p.corner_outside = {"kind": RO.GRAVEL, "width": 18.0, "barrier": BA.TYRES}
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 200.0})
	p.mark("river", {"side": 1, "distance": 160.0, "size": 120.0, "along": true})
	p.left(30, 60).right(120, 40)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0})
	p.straight(AUTO).right(90, 50)
	p.mark("river", {"side": 1, "distance": 130.0, "size": 120.0, "along": true})
	p.straight(400).chicane(true, 50, 30, 12)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	p.straight(500).right(30, 100).left(30, 100).straight(500)
	p.mark("forest", {"side": -1, "distance": 110.0, "size": 200.0})
	p.right(90, 22).straight(300).right(90, 22)
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 140.0})
	p.straight(600)
	p.mark("lake", {"side": -1, "distance": 130.0, "size": 160.0, "rowing": true})
	p.right(55, 25).straight(12)
	p.left(55, 25, {"outside": {"kind": RO.TARMAC, "width": 1.5, "barrier": BA.WALL}})
	p.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0})
	return p


# --- 11 Hay Valley -------------------------------------------------------

## An old countryside circuit, clockwise: narrow, cambered and quick, with
## grass to the barriers, long sweeping corners between the fields and a
## tight one by the farm.
static func _hay_valley() -> TrackPlan:
	var p := TrackPlan.new().classic()
	p.width = 11.5
	p.kerb_radius = 200.0
	p.start_at = 500.0
	p.pit_before = 300.0
	p.pit_after = 220.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": 1, "distance": 30.0, "size": 140.0})
	p.mark("village", {"side": -1, "distance": 160.0, "size": 200.0})
	p.right(90, 90, {"bank": 4.0})
	p.straight(600)
	p.mark("farm", {"side": 1, "distance": 120.0, "size": 300.0})
	p.right(40, 250, {"bank": 3.0}).straight(400).left(50, 180, {"bank": 3.0}).straight(300)
	p.right(110, 60, {"bank": 5.0, "width": 13.0, "outside": {"kind": RO.GRAVEL, "width": 22.0, "barrier": BA.TYRES}})
	p.mark("grandstand", {"side": 1, "distance": 30.0, "size": 90.0})
	p.straight(700, {"climb": 10.0}).left(40, 200, {"bank": 3.0}).right(70, 150, {"bank": 4.0})
	p.mark("hills", {"side": 1, "distance": 200.0, "size": 500.0})
	p.straight(AUTO, {"climb": 4.0}).right(60, 120, {"bank": 4.0}).straight(400)
	p.mark("windmills", {"side": 1, "distance": 160.0, "size": 200.0})
	p.right(50, 200, {"bank": 3.0, "outside": {"kind": RO.TARMAC, "width": 14.0, "barrier": BA.ARMCO}}).straight(500, {"climb": -14.0}).left(30, 250)
	p.mark("farm", {"side": -1, "distance": 100.0, "size": 260.0})
	p.right(60, 70, {"bank": 4.0})
	p.mark("grandstand", {"side": 1, "distance": 30.0, "size": 100.0})
	return p


# --- 12 Bellwood Speedway ------------------------------------------------

## The oval: a long front straight and a long back straight joined by two
## banked half circles, anticlockwise. Flat out all the way round.
static func _bellwood_oval() -> TrackPlan:
	var p := TrackPlan.new()
	p.width = 16.0
	p.start_at = 600.0
	p.pit_side = 1
	p.edge = {"kind": RO.GRASS, "width": 14.0, "barrier": BA.WALL}
	p.corner_outside = {"kind": RO.TARMAC, "width": 8.0, "barrier": BA.WALL}
	p.straight(1200)
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 600.0, "covered": true})
	p.mark("pits_tower", {"side": 1, "distance": 50.0, "size": 40.0})
	p.left(180, 330, {"bank": 11.0})
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 300.0})
	p.straight(1200)
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 300.0})
	p.left(180, 330, {"bank": 11.0})
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 300.0})
	return p


static func _bellwood() -> TrackPlan:
	var link := TrackPlan.new()
	link.straight(450).left(90, 45).straight(AUTO).right(90, 30)
	link.mark("grandstand", {"side": 1, "distance": 40.0, "size": 120.0})
	link.straight(AUTO).left(60, 50).right(60, 50).straight(150).right(90, 30).straight(200).left(90, 30)
	link.mark("grandstand", {"side": -1, "distance": 40.0, "size": 120.0})
	link.straight(150).left(90, 40).straight(300).left(90, 50)
	return _bellwood_oval().shortcut(2, 4, link)


# --- 13 Cliffside --------------------------------------------------------

## Coastal cliffs above the sea, clockwise: a rollercoaster of blind crests,
## a hairpin on the cliff top and one steep drop.
static func _cliffside() -> TrackPlan:
	var p := TrackPlan.new().modern()
	p.start_at = 520.0
	p.pit_after = 220.0
	p.straight(AUTO, {"climb": -4.0})
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 200.0})
	p.right(100, 60, {"climb": -4.0})
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 120.0})
	p.straight(600, {"climb": 8.0}).left(40, 120, {"climb": -6.0}).right(80, 50).straight(500, {"climb": 10.0})
	p.mark("hills", {"side": -1, "distance": 200.0, "size": 400.0})
	p.right(60, 150, {"climb": 6.0}).straight(200, {"climb": -13.0})
	p.mark("grandstand", {"side": 1, "distance": 45.0, "size": 100.0})
	p.left(90, 45, {"climb": -2.0}).straight(250, {"climb": 6.0}).right(120, 35)
	p.mark("cliff", {"side": 1, "distance": 90.0, "size": 400.0})
	p.mark("sea", {"side": 1, "distance": 400.0, "size": 800.0})
	p.straight(AUTO, {"climb": 4.0})
	p.mark("lighthouse", {"side": 1, "distance": 120.0, "size": 20.0})
	p.right(50, 100).straight(200, {"climb": -6.0}).left(70, 60).right(90, 80).straight(300, {"climb": -4.0})
	p.right(60, 200, {"climb": 5.0})
	return p


# --- 14 Misty Hills ------------------------------------------------------

## Wooded hills, anticlockwise and often wet: a short, busy lap that plunges
## into the first corner and climbs out of the hairpin, then winds back
## through the woods.
static func _misty_hills() -> TrackPlan:
	var p := TrackPlan.new().classic()
	p.width = 12.0
	p.start_at = 480.0
	p.pit_side = 1
	p.pit_before = 300.0
	p.pit_after = 200.0
	p.straight(AUTO, {"climb": -3.0})
	p.mark("grandstand", {"side": -1, "distance": 30.0, "size": 160.0})
	p.mark("forest", {"side": -1, "distance": 120.0, "size": 300.0})
	p.right(40, 150, {"climb": -8.0})
	p.mark("grandstand", {"side": -1, "distance": 35.0, "size": 120.0})
	p.left(180, 28, {"climb": 6.0}).left(30, 80)
	p.mark("grandstand", {"side": 1, "distance": 35.0, "size": 100.0})
	p.straight(830, {"climb": 3.0}).left(30, 150).straight(300, {"climb": -6.0}).left(60, 90)
	p.mark("forest", {"side": -1, "distance": 100.0, "size": 400.0})
	p.straight(300, {"climb": 4.0}).right(50, 100, {"climb": 2.0}).left(90, 60).straight(250, {"climb": -6.0})
	p.mark("hills", {"side": 1, "distance": 220.0, "size": 400.0})
	p.right(40, 120).left(70, 40, {"climb": 2.0}).straight(200, {"climb": 6.0})
	p.mark("forest", {"side": -1, "distance": 100.0, "size": 300.0})
	p.left(120, 50).straight(AUTO).right(90, 60)
	return p


# --- 15 Redrock Canyon ---------------------------------------------------

## A red-rock canyon, anticlockwise, with wide modern run-off: a steep climb
## to the first hairpin, the esses down the slope, a long back straight
## beneath the canyon wall and the twisty stadium section.
static func _redrock_canyon() -> TrackPlan:
	var p := TrackPlan.new().modern()
	p.start_at = 560.0
	p.pit_side = 1
	p.pit_after = 240.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 260.0})
	p.mark("pits_tower", {"side": 1, "distance": 50.0, "size": 40.0})
	_climb(p, 360.0, 40.0, 8)
	p.mark("rock_wall", {"side": -1, "distance": 120.0, "size": 300.0})
	p.left(150, 25, {"climb": 2.0})
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 140.0})
	p.right(30, 100, {"climb": -8.0}).straight(150, {"climb": -11.0})

	p.left(40, 120, {"climb": -4.0}).right(50, 110, {"climb": -3.0}).left(50, 110, {"climb": -3.0}).right(40, 130, {"climb": -2.0})
	p.straight(800, {"climb": -2.0}).left(60, 50).straight(770).right(40, 70).left(40, 70).straight(150).left(90, 28)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 120.0})
	p.straight(AUTO, {"climb": -7.0})
	p.mark("rock_wall", {"side": -1, "distance": 140.0, "size": 600.0})
	p.left(90, 30)
	p.mark("grandstand", {"side": 1, "distance": 50.0, "size": 140.0})
	p.straight(150, {"climb": -1.0}).right(70, 35).left(70, 35).right(50, 50).left(50, 50, {"climb": -1.0})
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 160.0, "covered": true})
	return p


# --- 16 Harbour Lights ---------------------------------------------------

## A marina island, anticlockwise, from dusk into the night: a twisty start,
## the long run beside the water, and the tight marina section that passes
## under the hotel.
static func _harbour_lights() -> TrackPlan:
	var p := TrackPlan.new().modern()
	p.start_at = 560.0
	p.pit_side = 1
	p.pit_after = 240.0
	p.straight(AUTO)
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 220.0, "covered": true})
	p.left(90, 35)
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 100.0})
	p.straight(200).right(40, 80).left(40, 80).straight(150).right(60, 40).left(60, 40)
	p.straight(AUTO).left(90, 30)
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 120.0})
	p.straight(800)
	p.mark("marina", {"side": -1, "distance": 160.0, "size": 300.0, "boats": true})

	p.chicane(false, 50, 25, 12).straight(600).left(90, 40)
	p.mark("sea", {"side": -1, "distance": 300.0, "size": 600.0})
	p.straight(140).straight(160, {"feature": "tunnel"})
	p.mark("hotel", {"side": 1, "distance": 0.0, "size": 160.0, "over_track": true})
	p.straight(100).right(90, 30).straight(100).left(90, 28).straight(200).left(90, 30)
	p.mark("marina", {"side": 1, "distance": 140.0, "size": 260.0, "boats": true})
	p.straight(120).right(90, 30).straight(150).left(90, 30).straight(200).right(40, 80).left(40, 80)
	p.mark("grandstand", {"side": -1, "distance": 45.0, "size": 140.0})
	return p


# --- Helpers -------------------------------------------------------------

## A straight that climbs `climb` metres at a steady slope, laid as `count`
## short pieces (one piece eases in and out of its climb, so a long climb
## in one piece is steepest in its middle).
static func _climb(p: TrackPlan, length: float, climb: float, count: int) -> TrackPlan:
	for k in count:
		p.straight(length / count, {"climb": climb / count})
	return p


# --- Second layouts ------------------------------------------------------

## Greenfield Park's club circuit: from the third corner straight up the
## middle of the park beside the lake to the back of the lap.
static func _greenfield_club() -> TrackPlan:
	var link := TrackPlan.new()
	link.right(40, 100).straight(AUTO).chicane(false, 45, 30, 12).straight(300).right(70, 60)
	link.mark("lake", {"side": 1, "distance": 220.0, "size": 300.0, "boats": true})
	link.straight(AUTO).esses(true, 40, 70)
	return _greenfield().shortcut(6, 23, link)


## Monte Pineta's junior circuit: after the first chicane, a link road
## through the pines to the long straight before the final corner.
static func _monte_pineta_junior() -> TrackPlan:
	var link := TrackPlan.new()
	link.right(60, 60).straight(AUTO).chicane(true, 50, 25, 12).right(70, 60)

	link.mark("forest", {"side": 1, "distance": 90.0, "size": 300.0, "trees": "pine"})
	link.straight(AUTO).right(75, 70)
	link.mark("grandstand", {"side": 1, "distance": 40.0, "size": 100.0})
	return _monte_pineta().shortcut(5, 20, link)


## Kingsfield's international circuit: from the long right after the loop
## across the airfield to the hangar straight, missing the esses.
static func _kingsfield_international() -> TrackPlan:
	var link := TrackPlan.new()
	link.right(40, 150).straight(AUTO)
	link.mark("hangars", {"side": 1, "distance": 110.0, "size": 260.0})
	link.right(90, 70).straight(AUTO)
	return _kingsfield().shortcut(10, 17, link)


## Neon Marina's short circuit: over the bridge, then straight up the
## avenue to the run back to the last corners.
static func _neon_marina_short() -> TrackPlan:
	var link := TrackPlan.new()
	link.straight(AUTO).left(90, 30)
	link.mark("buildings", {"side": -1, "distance": 80.0, "size": 200.0, "towers": true})
	link.straight(AUTO)
	return _neon_marina().shortcut(6, 26, link)


## Redrock Canyon's national circuit: from the esses straight along the
## canyon floor to the stadium section.
static func _redrock_canyon_national() -> TrackPlan:
	var link := TrackPlan.new()
	link.left(60, 50).straight(AUTO, {"climb": -14.0}).chicane(true, 45, 30, 12)
	link.mark("rock_wall", {"side": -1, "distance": 140.0, "size": 400.0})
	link.straight(500).left(90, 40).straight(AUTO, {"climb": -7.0})
	link.mark("grandstand", {"side": 1, "distance": 50.0, "size": 140.0})
	return _level(_redrock_canyon().shortcut(12, 24, link), 13)


## Harbour Lights' short circuit: from the first corners straight up the
## island to the marina section.
static func _harbour_lights_short() -> TrackPlan:
	var link := TrackPlan.new()
	link.left(90, 40).straight(AUTO).left(30, 60)
	link.mark("marina", {"side": -1, "distance": 160.0, "size": 300.0, "boats": true})
	link.straight(AUTO).right(30, 60)
	return _harbour_lights().shortcut(6, 21, link)

## Misty Hills the other way round, clockwise. The start line moves a
## little further from the corner that now comes before the pit entry.
static func _misty_hills_reverse() -> TrackPlan:
	var p := _misty_hills().reversed()
	p.start_at += 40.0
	return p


## Sets one piece's climb so the lap's climbs add up to zero.
static func _level(p: TrackPlan, piece: int) -> TrackPlan:
	var total := 0.0
	for pc in p.pieces:
		total += float(pc.get("climb", 0.0))
	p.pieces[piece]["climb"] = float(p.pieces[piece].get("climb", 0.0)) - total
	return p
