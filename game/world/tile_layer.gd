class_name TileLayer
extends RefCounted
## Lays the Racing Kit's grid road tiles (the Proving Ground) into the
## ground chunks, with the ground material, so they get wet in the rain and
## lit at night like generated road, and cost no extra draw calls.

## How wet each of the kit's materials gets (the road most, grass least).
const WET := {"road": 1.0, "grey": 0.9, "white": 0.9, "red": 0.9, "grass": 0.25, "sand": 0.2}
## The kit's materials in the world's colours, so tiles match generated
## road and land.
const COLOURS := {
	"road": WorldLook.ROAD, "grey": WorldLook.LINE, "white": WorldLook.KERB_WHITE,
	"red": WorldLook.KERB_RED, "grass": WorldLook.GRASS, "sand": WorldLook.SAND,
}
## Borders and sand traps lie over the corner tiles' grass.
const OVERLAY_LIFT := 0.02


## Merges `tiles` (from ProvingGround.tiles) into the chunk meshes made by
## RoadBuilder.build, and returns the new chunk meshes.
static func merge(view: TrackView, tiles: Array, meshes: Array) -> Array:
	var track := view.track
	var bufs := []
	for m in meshes:
		var b := MeshBuf.new()
		if m != null:
			var am := m as ArrayMesh
			for si in am.get_surface_count():
				b.append_arrays(am.surface_get_arrays(si), Transform3D())
		bufs.append(b)
	if bufs.is_empty():
		bufs.append(MeshBuf.new())
	# Pole is on the left on some layouts: the grid pieces flip to match.
	var flip_grid := not track.grid.is_empty() and float(track.grid[0].lat) > 0.0
	for t: Dictionary in tiles:
		var tile := t
		if flip_grid and bool(t.get("grid", false)):
			tile = t.duplicate()
			tile.mirror = not bool(t.mirror)
		var xf := ProvingGround.transform(tile)
		var at: Vector3 = tile.pos
		var spot := track.locate(Vector2(at.x, at.z), -1)
		xf.origin.y += track.pos[spot.idx].y
		var scene := str(tile.scene)
		if scene.ends_with("Border") or scene.ends_with("Sand") or scene.ends_with("Inner"):
			xf.origin.y += OVERLAY_LIFT
		var b: MeshBuf = bufs[clampi(spot.idx / RoadBuilder.CHUNK, 0, bufs.size() - 1)]
		for part: Dictionary in PropKit.parts(ProvingGround.path(tile)):
			var mask := float(WET.get(str(part.name), 0.5))
			var col: Color = COLOURS.get(str(part.name), part.col)
			b.append_arrays(part.arrays, xf * (part.xf as Transform3D), WorldLook.wet(col, mask))
	var out := []
	for b: MeshBuf in bufs:
		out.append(b.commit(null, WorldLook.ground()) if not b.is_empty() else null)
	return out
