class_name ProvingGround
extends RefCounted
## The Proving Ground: a private test track laid from the Racing Kit's grid
## road pieces exactly as they come. One list of pieces (`LAP`, in tiles)
## makes both the plan the simulation drives and the tiles the view lays,
## so the two match: straights are whole tiles, corners are the kit's three
## quarter circles and the S-bend is two short arcs.
##
## A tile is `TILE` metres square, which makes the kit's road (white lines
## included) the usual 14 m wide.

## One kit tile in metres.
const TILE := 16.75
## How much the kit's (paper thin) tiles are raised: kerbs and lines stand
## a few centimetres proud of the road.
const TILE_Y := 5.0
const KIT := "res://assets/kenney/racing-kit/"

## The lap in tiles, from the start of the main straight:
## ["S", n] a straight of n tiles; ["R" or "L", size, edge] a 90 degree
## corner of the kit's small (1), large (2) or larger (3) piece, with
## "plain" grass, a red and white "border" or a "sand" trap round it;
## ["C", dir] the kit's S-bend, stepping half a tile left (1) or right (-1).
const LAP := [
	["S", 52], ["R", 1, "sand"], ["S", 4], ["R", 3, "border"], ["S", 6], ["L", 2, "plain"],
	["S", 22], ["R", 2, "sand"], ["S", 16], ["C", -1], ["S", 6], ["C", 1], ["S", 4],
	["R", 3, "sand"], ["S", 12], ["L", 1, "border"], ["S", 10], ["R", 1, "plain"], ["S", 3],
	["R", 2, "border"], ["S", 14], ["L", 3, "plain"], ["S", 2], ["L", 2, "sand"], ["S", 14],
	["R", 2, "plain"], ["S", 3], ["R", 2, "plain"],
]

## Along the main straight, in tiles from its start: the grid's front, the
## pit lane's entry and exit pieces, and the garages.
const GRID_FRONT := 22
const GRID_TILES := 6
const PIT_IN := 8
const PIT_OUT := 32
const GARAGES := [16, 26]

const SIZES := ["", "Small", "Large", "Larger"]


## The circuit as a plan whose straights and corners match the tiles.
static func plan() -> TrackPlan:
	var p := TrackPlan.new()
	p.width = 14.0
	p.edge = {"kind": TrackPlan.Runoff.GRASS, "width": 12.0, "barrier": TrackPlan.Barrier.ARMCO}
	p.corner_outside = p.edge.duplicate()
	# The kit's corners have no kerbs; its borders are flat, like tarmac.
	p.kerb_radius = 0.0
	p.pit_side = -1
	p.start_at = start_at()
	p.pit_before = p.start_at - PIT_IN * TILE
	p.pit_after = PIT_OUT * TILE - p.start_at
	for pc: Array in LAP:
		match str(pc[0]):
			"S":
				p.straight(int(pc[1]) * TILE)
			"R", "L":
				var r := (int(pc[1]) - 0.5) * TILE
				var opts := _corner_edge(str(pc[2]))
				if pc[0] == "R":
					p.right(90.0, r, opts)
				else:
					p.left(90.0, r, opts)
			"C":
				var a := rad_to_deg(bend_angle())
				var r := bend_radius()
				if int(pc[1]) > 0:
					p.left(a, r).right(a, r)
				else:
					p.right(a, r).left(a, r)
	return p


## Where the start line sits: the front grid box (its middle) is 10 m
## behind it, as on every circuit's grid.
static func start_at() -> float:
	return (GRID_FRONT - 0.25) * TILE + 10.0


## Each half of the S-bend: it moves a quarter tile sideways over one tile.
static func bend_angle() -> float:
	return 2.0 * atan(0.25)


static func bend_radius() -> float:
	return TILE / sin(bend_angle())


static func _corner_edge(edge: String) -> Dictionary:
	match edge:
		"sand":
			return {"outside": {"kind": TrackPlan.Runoff.SAND, "width": 9.0, "barrier": TrackPlan.Barrier.TYRES}}
		"border":
			return {"outside": {"kind": TrackPlan.Runoff.TARMAC, "width": 8.0, "barrier": TrackPlan.Barrier.TYRES}}
	return {}


## The tiles to lay: [{"scene" (a Racing Kit model name), "pos" (Vector3:
## where the road enters the tile, on its centreline), "yaw" (the heading
## there, radians, 0 along +z), "mirror" (laid flipped left for right),
## "reverse" (laid back to front), "length" (tiles), "grid" (a grid piece,
## flipped as a whole when pole is on the other side)}]. `transform` turns
## one into the transform from the kit model to the world.
static func tiles() -> Array:
	var out := []
	var p := Vector2.ZERO
	var h := 0.0
	for k in LAP.size():
		var pc: Array = LAP[k]
		var f := Vector2(sin(h), cos(h))
		var right := Vector2(-cos(h), sin(h))
		match str(pc[0]):
			"S":
				for u in int(pc[1]):
					var at := p + f * (u * TILE)
					if k == 0:
						_main_straight(out, u, at, h, right)
					else:
						out.append(_tile("roadStraight", at, h))
				p += f * (int(pc[1]) * TILE)
			"R", "L":
				var size := int(pc[1])
				var name: String = "roadCorner" + str(SIZES[size])
				var mirror: bool = pc[0] == "L"
				out.append(_tile(name, p, h, mirror))
				var edge := str(pc[2])
				if edge != "plain":
					var suffix := "Border" if edge == "border" else "Sand"
					out.append(_tile(name + suffix, p, h, mirror))
					if size > 1:
						out.append(_tile(name + suffix + "Inner", p, h, mirror))
				var r := (size - 0.5) * TILE
				var side := -right if mirror else right
				p += f * r + side * r
				h += PI * 0.5 if mirror else -PI * 0.5
			"C":
				# The kit's S-bend steps left; mirrored, it steps right.
				var left := int(pc[1]) > 0
				out.append(_tile("roadCurved", p, h, not left))
				p += f * (2.0 * TILE) + (-right if left else right) * (0.5 * TILE)
	return out


## The main straight's tile `u`: the grid, the pit entry and exit, and the
## pit lane beside it.
static func _main_straight(out: Array, u: int, at: Vector2, h: float, right: Vector2) -> void:
	if u == PIT_IN:
		out.append(_tile("roadPitEntry", at, h, false, false, 2))
	elif u == PIT_OUT - 2:
		out.append(_tile("roadPitEntry", at, h, true, true, 2))
	elif u >= GRID_FRONT - GRID_TILES * 2 and u < GRID_FRONT:
		if (u - GRID_FRONT) % 2 == 0:
			var t := _tile("roadStartPositions", at, h, false, false, 2)
			t["grid"] = true
			out.append(t)
	elif not (u > PIT_IN and u < PIT_IN + 2) and not (u > PIT_OUT - 2 and u < PIT_OUT):
		out.append(_tile("roadStraight", at, h))
	if u >= PIT_IN + 2 and u < PIT_OUT - 2:
		var garage := u >= int(GARAGES[0]) and u < int(GARAGES[1])
		out.append(_tile("roadPitGarage" if garage else "roadPitStraight", at + right * TILE, h))


static func _tile(scene: String, at: Vector2, yaw: float, mirror := false, reverse := false, length := 1) -> Dictionary:
	return {"scene": scene, "pos": Vector3(at.x, 0.0, at.y), "yaw": yaw, "mirror": mirror, "reverse": reverse, "length": length}


## The transform from a tile's kit model (as authored, in kit units) to the
## world. The kit's road runs along -z with its middle at x 0.15 and enters
## at z -0.65; corners turn right and the S-bend steps left.
static func transform(tile: Dictionary) -> Transform3D:
	var yaw := float(tile.yaw)
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	var reverse := bool(tile.get("reverse", false))
	var sx := -1.0 if reverse else 1.0
	if bool(tile.get("mirror", false)):
		sx = -sx
	var sz := 1.0 if reverse else -1.0
	var basis := Basis(right * sx * TILE, Vector3.UP * TILE_Y, f * sz * TILE)
	var entry := Vector3(0.15, 0.0, -0.65 - (float(tile.get("length", 1)) if reverse else 0.0))
	var pos: Vector3 = tile.pos
	return Transform3D(basis, pos - basis * entry)


## How far from the centreline the tiles' pit lane ends (its outer white
## line), for the wall and garages behind it.
static func pit_outer() -> float:
	return TILE * 1.43


## The kit model's path for a tile.
static func path(tile: Dictionary) -> String:
	return KIT + str(tile.scene) + ".glb"
