class_name ProvingGround
extends RefCounted
## The Proving Ground: a private test track laid from the Racing Kit's grid
## road pieces exactly as they come. The plan follows the tiles, so the
## simulation drives the same road the view lays.


## The circuit as a plan whose straights and corners match the tiles.
static func plan() -> TrackPlan:
	var p := TrackPlan.new()
	p.start_at = 300.0
	p.straight(TrackPlan.AUTO).right(90, 60).straight(400).right(60, 120).left(60, 90).straight(TrackPlan.AUTO).right(90, 45).straight(600).right(90, 150).straight(900).right(90, 70)
	return p


## The tiles to lay: [{"scene" (a Racing Kit model name), "pos" (Vector3,
## metres), "yaw" (radians)}]. Empty until the tiles are worked out, and the
## view then builds the road from the plan like any other circuit.
static func tiles() -> Array:
	return []
