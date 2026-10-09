class_name TrackPlan
extends RefCounted
## A circuit written as a list of straights and corners, the way a track map
## reads: "a 900 m straight, a 90 degree right of 60 m radius, ...". Track
## turns a plan into a closed centreline in metres.
##
## Each piece can also climb, bank, change width and set its run-off. Two
## straights marked AUTO get the lengths that close the lap, and the corners
## must add up to one full turn (360 degrees either way).
##
## Lateral offsets are positive to the LEFT of the direction of travel, like
## the car's own frame.

const AUTO := -1.0

enum Runoff { GRASS, GRAVEL, TARMAC, SAND, WALL }
enum Barrier { ARMCO, TYRES, WALL, FENCE, NONE }

## Track width in metres (the white lines are this far apart).
var width := 14.0
## Where the start line sits along the first piece, in metres.
var start_at := 200.0
## Which side the pit lane is on: 1 left, -1 right.
var pit_side := -1
## The pit lane leaves this far before the start line and rejoins this far after it.
var pit_before := 340.0
var pit_after := 260.0
## The default edges for both sides: run-off kind, its width to the barrier,
## and the barrier. Corners put `corner_outside` on their outside.
var edge := {"kind": Runoff.GRASS, "width": 14.0, "barrier": Barrier.ARMCO}
var corner_outside := {"kind": Runoff.GRAVEL, "width": 26.0, "barrier": Barrier.TYRES}
## Kerbs on corners tighter than this radius.
var kerb_radius := 320.0
## The pieces: {"kind": "line"/"arc", "length", "angle" (radians, + left),
## "radius", "climb", "bank" (degrees, + raises the outside), "width",
## "left", "right" (edge overrides), "feature" (see FEATURES)}.
var pieces: Array = []
## Scenery beside the track, placed with mark(): {"kind", "piece" (it sits at
## the end of this many pieces), "side" (1 left, -1 right), "distance" (metres
## from the centreline), "size" (metres), plus anything the kind needs}.
var landmarks: Array = []

## What a piece can be, for the view: "tunnel" (roofed), "bridge" (over water
## or a road), "over" and "under" (the two halves of a crossover).
const FEATURES := ["tunnel", "bridge", "over", "under"]
## Landmark kinds the view knows how to build.
const LANDMARKS := [
	"grandstand", "lake", "sea", "river", "buildings", "hangars", "hotel",
	"forest", "cliff", "rock_wall", "marina", "farm", "dunes", "hills",
	"lighthouse", "village", "pits_tower", "big_screen", "windmills",
]


## A straight of `length` metres (or AUTO).
func straight(length: float, opts := {}) -> TrackPlan:
	var p := {"kind": "line", "length": length, "angle": 0.0, "radius": 0.0}
	p.merge(opts)
	pieces.append(p)
	return self


## A right-hand corner turning `degrees` on a `radius` in metres.
func right(degrees: float, radius: float, opts := {}) -> TrackPlan:
	return _arc(-deg_to_rad(degrees), radius, opts)


## A left-hand corner turning `degrees` on a `radius` in metres.
func left(degrees: float, radius: float, opts := {}) -> TrackPlan:
	return _arc(deg_to_rad(degrees), radius, opts)


## A chicane: a quick flick one way and back, `degrees` each way.
func chicane(first_right: bool, degrees := 40.0, radius := 30.0, gap := 15.0, opts := {}) -> TrackPlan:
	if first_right:
		right(degrees, radius, opts)
		straight(gap, opts)
		left(degrees, radius, opts)
	else:
		left(degrees, radius, opts)
		straight(gap, opts)
		right(degrees, radius, opts)
	return self


## An S: one way then the other, each `degrees`, with no straight between.
func esses(first_right: bool, degrees: float, radius: float, opts := {}) -> TrackPlan:
	if first_right:
		right(degrees, radius, opts)
		left(degrees, radius, opts)
	else:
		left(degrees, radius, opts)
		right(degrees, radius, opts)
	return self


func _arc(angle: float, radius: float, opts: Dictionary) -> TrackPlan:
	var p := {"kind": "arc", "length": absf(angle) * radius, "angle": angle, "radius": radius}
	p.merge(opts)
	pieces.append(p)
	return self


## Puts a landmark beside the track where the plan has reached so far.
## `opts` holds "side", "distance", "size" and anything the kind needs.
func mark(kind: String, opts := {}) -> TrackPlan:
	var l := {"kind": kind, "piece": pieces.size(), "side": 1, "distance": 60.0, "size": 80.0}
	l.merge(opts, true)
	landmarks.append(l)
	return self


## The sum of every corner's angle, in degrees (360 or -360 for a lap).
func total_turn() -> float:
	var t := 0.0
	for p in pieces:
		t += float(p.angle)
	return rad_to_deg(t)


## Edges for a street circuit: walls close to the track.
func street() -> TrackPlan:
	edge = {"kind": Runoff.TARMAC, "width": 2.5, "barrier": Barrier.WALL}
	corner_outside = {"kind": Runoff.TARMAC, "width": 9.0, "barrier": Barrier.TYRES}
	return self


## Edges for a modern circuit: wide tarmac run-off and catch fences.
func modern() -> TrackPlan:
	edge = {"kind": Runoff.GRASS, "width": 16.0, "barrier": Barrier.FENCE}
	corner_outside = {"kind": Runoff.TARMAC, "width": 30.0, "barrier": Barrier.TYRES}
	return self


## Edges for an old-fashioned circuit: grass right up to the armco.
func classic() -> TrackPlan:
	edge = {"kind": Runoff.GRASS, "width": 6.0, "barrier": Barrier.ARMCO}
	corner_outside = {"kind": Runoff.GRASS, "width": 12.0, "barrier": Barrier.ARMCO}
	return self


## Edges for a desert circuit: sand beside the track.
func desert() -> TrackPlan:
	edge = {"kind": Runoff.TARMAC, "width": 14.0, "barrier": Barrier.FENCE}
	corner_outside = {"kind": Runoff.TARMAC, "width": 28.0, "barrier": Barrier.TYRES}
	return self
