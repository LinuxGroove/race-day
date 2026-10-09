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
## How many full turns the corners add up to: 1 for an ordinary lap, 0 for
## a figure of eight (one loop each way, with a crossover).
var winding := 1
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


## A copy of this plan: its settings, pieces and landmarks.
func copy() -> TrackPlan:
	var p := TrackPlan.new()
	p.width = width
	p.start_at = start_at
	p.pit_side = pit_side
	p.pit_before = pit_before
	p.pit_after = pit_after
	p.edge = edge.duplicate(true)
	p.corner_outside = corner_outside.duplicate(true)
	p.kerb_radius = kerb_radius
	p.winding = winding
	p.pieces = pieces.duplicate(true)
	p.landmarks = landmarks.duplicate(true)
	return p


## A copy whose AUTO straights have the lengths that close the lap, and
## whose corners make exactly a full turn: the plan as Track lays it.
func resolved() -> TrackPlan:
	var p := copy()
	p.pieces = Track.solve_pieces(self)
	return p


## The same circuit driven the other way round. The start line, the pit
## lane and every landmark stay where they are on the ground: the pit lane
## and the landmarks change sides relative to the cars, the pit entry and
## exit swap ends, and climbs become drops.
func reversed() -> TrackPlan:
	var base := resolved()
	var p := base.copy()
	var count := base.pieces.size()
	p.pieces = []
	for j in count:
		p.pieces.append(_reverse_piece(base.pieces[(count - j) % count]))
	p.start_at = float(base.pieces[0].length) - base.start_at
	p.pit_side = -base.pit_side
	p.pit_before = base.pit_after
	p.pit_after = base.pit_before
	p.landmarks = []
	for l in base.landmarks:
		var m: Dictionary = l.duplicate(true)
		# A landmark sits at the end of `piece` pieces: the same spot on the
		# ground is the end of this many reversed pieces.
		m["piece"] = (count - int(l.piece)) % count + 1
		m["side"] = -int(l.get("side", 1))
		p.landmarks.append(m)
	return p


static func _reverse_piece(pc: Dictionary) -> Dictionary:
	var r: Dictionary = pc.duplicate(true)
	r["angle"] = -float(pc.angle)
	if pc.has("climb"):
		r["climb"] = -float(pc.climb)
	r.erase("left")
	r.erase("right")
	if pc.has("right"):
		r["left"] = pc.right.duplicate(true)
	if pc.has("left"):
		r["right"] = pc.left.duplicate(true)
	return r


## A shorter layout: pieces `from` up to (not including) `to` are replaced
## by the link road in `link`, which needs two AUTO straights of its own
## (and whose corners make up the turn the cut pieces made). The rest of
## the lap lies exactly where it did, with its landmarks; the link's own
## landmarks come along too.
func shortcut(from: int, to: int, link: TrackPlan) -> TrackPlan:
	var base := resolved()
	var p := base.copy()
	p.pieces = base.pieces.slice(0, from) + link.pieces.duplicate(true) + base.pieces.slice(to)
	var shift := link.pieces.size() - (to - from)
	p.landmarks = []
	for l in base.landmarks:
		var k := int(l.piece)
		if k > from and k < to:
			continue
		var m: Dictionary = l.duplicate(true)
		if k >= to:
			m["piece"] = k + shift
		p.landmarks.append(m)
	for l in link.landmarks:
		var m: Dictionary = l.duplicate(true)
		m["piece"] = int(l.piece) + from
		p.landmarks.append(m)
	return p
