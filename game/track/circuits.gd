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
	push_error("No circuit %s" % id)
	return ProvingGround.plan()


static func _all() -> Array:
	return [
		{"id": "greenfield", "venue": "greenfield", "name": "Greenfield Park", "layout": "Grand Prix", "round": 1, "theme": "parkland", "time": "day", "rain": 0.25, "laps": 56, "clockwise": true, "length_km": 5.3, "blurb": "Parkland round a boating lake: medium speed and forgiving run-off."},
		{"id": "port_lumen", "venue": "port_lumen", "name": "Port Lumen", "layout": "Grand Prix", "round": 2, "theme": "harbour", "time": "day", "rain": 0.15, "laps": 78, "clockwise": true, "length_km": 3.3, "blurb": "Harbour streets: slow, narrow and walled in. Qualifying decides the race."},
		{"id": "monte_pineta", "venue": "monte_pineta", "name": "Monte Pineta", "layout": "Grand Prix", "round": 3, "theme": "forest", "time": "day", "rain": 0.2, "laps": 53, "clockwise": true, "length_km": 5.8, "blurb": "The temple of speed: long straights, three chicanes and the slipstream."},
		{"id": "ardenwood", "venue": "ardenwood", "name": "Ardenwood", "layout": "Grand Prix", "round": 4, "theme": "forest", "time": "day", "rain": 0.45, "laps": 44, "clockwise": true, "length_km": 6.9, "blurb": "A forest valley: big climbs, fast sweeps and a bridge over the river."},
		{"id": "kingsfield", "venue": "kingsfield", "name": "Kingsfield", "layout": "Grand Prix", "round": 5, "theme": "airfield", "time": "day", "rain": 0.4, "laps": 52, "clockwise": true, "length_km": 5.8, "blurb": "A former airfield: very fast, flowing corners on a wide, open track."},
		{"id": "twin_bridges", "venue": "twin_bridges", "name": "Twin Bridges", "layout": "Grand Prix", "round": 6, "theme": "parkland", "time": "day", "rain": 0.35, "laps": 53, "clockwise": true, "length_km": 5.8, "blurb": "A figure of eight: technical esses, a hairpin and the crossover bridge."},
		{"id": "sandhaven", "venue": "sandhaven", "name": "Sandhaven", "layout": "Grand Prix", "round": 7, "theme": "desert", "time": "night", "rain": 0.0, "laps": 57, "clockwise": true, "length_km": 5.4, "blurb": "A desert night race: hard braking zones and tyres that wear fast."},
		{"id": "neon_marina", "venue": "neon_marina", "name": "Neon Marina", "layout": "Grand Prix", "round": 8, "theme": "city", "time": "night", "rain": 0.2, "laps": 61, "clockwise": false, "length_km": 5.0, "blurb": "Twenty corners between the city towers at night. The walls punish mistakes."},
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
