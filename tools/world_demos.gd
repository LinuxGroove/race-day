extends RefCounted
## Test layouts for the world builder (tools/world_shot.gd): between them
## they use both pit sides, banking, climbs, a bridge over a river, a
## tunnel, the hotel over the track, two crossovers and every landmark kind.
## They aren't circuits in the game; Circuits has those.

const IDS := ["gp", "street", "spiral", "oval"]


static func info(id: String) -> Dictionary:
	match id:
		"gp":
			return {"id": "demo_gp", "name": "Demo GP", "layout": "Grand Prix", "theme": "parkland", "time": "day", "rain": 0.2}
		"street":
			return {"id": "demo_street", "name": "Demo Street", "layout": "Grand Prix", "theme": "harbour", "time": "night", "rain": 0.1}
		"spiral":
			return {"id": "demo_spiral", "name": "Demo Spiral", "layout": "Grand Prix", "theme": "countryside", "time": "dusk_to_night", "rain": 0.3}
		"oval":
			return {"id": "demo_oval", "name": "Demo Oval", "layout": "Oval", "theme": "oval", "time": "dusk", "rain": 0.0}
	return {}


static func plan(id: String) -> TrackPlan:
	match id:
		"gp":
			return _gp()
		"street":
			return _street()
		"spiral":
			return _spiral()
		"oval":
			return _oval()
	return _gp()


## A parkland Grand Prix circuit of about 5 km, pits on the right.
static func _gp() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 420.0
	p.straight(TrackPlan.AUTO)
	p.mark("grandstand", {"side": 1, "distance": 34.0, "size": 180.0})
	p.mark("pits_tower", {"side": -1, "distance": 70.0, "size": 30.0})
	p.mark("big_screen", {"side": 1, "distance": 60.0, "size": 20.0})
	p.right(90.0, 70.0)
	p.mark("grandstand", {"side": -1, "distance": 60.0, "size": 120.0})
	p.straight(TrackPlan.AUTO)
	p.left(60.0, 120.0).right(60.0, 120.0)
	p.straight(260.0, {"climb": 14.0})
	p.mark("forest", {"side": -1, "distance": 160.0, "size": 320.0})
	p.mark("lake", {"side": 1, "distance": 260.0, "size": 380.0})
	p.right(120.0, 90.0, {"bank": 5.0})
	p.straight(140.0)
	p.straight(80.0, {"feature": "bridge"})
	p.mark("river", {"side": 1, "distance": 0.0, "size": 60.0})
	p.straight(80.0, {"feature": "bridge"})
	p.straight(140.0)
	p.chicane(true, 45.0, 35.0, 18.0)
	p.straight(380.0, {"climb": -14.0})
	p.mark("hills", {"side": -1, "distance": 420.0, "size": 300.0})
	p.mark("windmills", {"side": 1, "distance": 160.0, "size": 300.0})
	p.left(45.0, 200.0)
	p.straight(400.0)
	p.right(105.0, 80.0)
	p.straight(300.0)
	p.right(90.0, 100.0)
	return p


## A harbour street circuit: walls, a tunnel, the hotel and the sea; pits on
## the left.
static func _street() -> TrackPlan:
	var p := TrackPlan.new()
	p.street()
	p.width = 13.0
	p.pit_side = 1
	p.start_at = 360.0
	p.straight(700.0)
	p.mark("buildings", {"side": -1, "distance": 60.0, "size": 260.0})
	p.mark("hotel", {"side": 1, "distance": 0.0, "size": 70.0})
	p.right(90.0, 28.0)
	p.straight(TrackPlan.AUTO)
	p.mark("village", {"side": -1, "distance": 90.0, "size": 200.0})
	p.left(90.0, 32.0)
	p.straight(500.0)
	p.right(90.0, 45.0)
	p.straight(160.0)
	p.straight(280.0, {"feature": "tunnel"})
	p.mark("marina", {"side": 1, "distance": 140.0, "size": 220.0})
	p.mark("sea", {"side": 1, "distance": 320.0, "size": 600.0})
	p.mark("lighthouse", {"side": 1, "distance": 90.0, "size": 30.0})
	p.straight(200.0)
	p.chicane(false, 50.0, 25.0, 12.0)
	p.right(90.0, 40.0)
	p.straight(TrackPlan.AUTO)
	p.mark("buildings", {"side": 1, "distance": 70.0, "size": 300.0})
	p.right(90.0, 30.0)
	p.straight(1000.0)
	p.right(90.0, 55.0)
	return p


## Two crossovers: a curl that climbs over the start straight, and a long
## straight that bridges it further up. Countryside, farms and hills.
static func _spiral() -> TrackPlan:
	var p := TrackPlan.new()
	p.classic()
	p.start_at = 300.0
	p.straight(720.0, {"feature": "under"})
	p.mark("farm", {"side": 1, "distance": 160.0, "size": 220.0})
	p.left(270.0, 75.0, {"climb": 9.0})
	p.straight(160.0, {"feature": "over"})
	p.straight(180.0, {"climb": -9.0})
	p.right(90.0, 60.0)
	p.mark("dunes", {"side": 1, "distance": 200.0, "size": 260.0})
	p.straight(420.0)
	p.mark("hangars", {"side": -1, "distance": 140.0, "size": 200.0})
	p.right(90.0, 60.0)
	p.straight(260.0, {"climb": 9.0})
	p.straight(160.0, {"feature": "over"})
	p.straight(260.0, {"climb": -9.0})
	p.mark("cliff", {"side": -1, "distance": 160.0, "size": 200.0})
	p.right(90.0, 60.0)
	p.straight(700.0)
	p.mark("rock_wall", {"side": 1, "distance": 60.0, "size": 300.0})
	p.right(90.0, 60.0)
	p.straight(500.0)
	p.right(90.0, 60.0)
	p.straight(TrackPlan.AUTO)
	p.mark("village", {"side": -1, "distance": 150.0, "size": 220.0})
	p.right(90.0, 60.0)
	p.straight(TrackPlan.AUTO)
	p.right(90.0, 60.0)
	return p


## A banked oval.
static func _oval() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 300.0
	p.edge = {"kind": TrackPlan.Runoff.TARMAC, "width": 8.0, "barrier": TrackPlan.Barrier.WALL}
	p.corner_outside = {"kind": TrackPlan.Runoff.TARMAC, "width": 10.0, "barrier": TrackPlan.Barrier.WALL}
	p.width = 16.0
	p.pit_side = 1
	p.straight(800.0)
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 400.0})
	p.left(180.0, 220.0, {"bank": 20.0})
	p.straight(800.0)
	p.mark("grandstand", {"side": -1, "distance": 50.0, "size": 300.0})
	p.left(180.0, 220.0, {"bank": 20.0})
	return p
