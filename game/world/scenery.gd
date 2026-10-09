class_name Scenery
extends RefCounted
## The land's dressing: water bodies and hills from the landmarks (shaped
## into the terrain before it is built), then trees, rocks, buildings and
## boats by the circuit's theme, and every landmark kind.

var view: TrackView
var track: Track
var terrain: Terrain
var detail := 1
var rng := RandomNumberGenerator.new()
var scatter := PropKit.Scatter.new(350.0)
var root: Node3D


func _init(v: TrackView) -> void:
	view = v
	track = v.track
	terrain = v.terrain
	detail = v.detail
	rng.seed = hash(track.id + "scenery")


## The centre of a landmark on the ground plane.
func landmark_point(l: Dictionary, extra := 0.0) -> Vector2:
	var p := track.world(float(l.s), float(l.side) * (float(l.distance) + extra))
	return Vector2(p.x, p.z)


## The lowest track height within `r` metres of a point.
func track_low(p: Vector2, r: float) -> float:
	var low := INF
	for i in track.samples_near(p, r):
		low = minf(low, track.pos[i].y)
	if low == INF:
		low = terrain.base_height if terrain.base_height != 0.0 else track.pos[0].y
	return low


## Water and hills go into the terrain before it is built.
func shape_land() -> void:
	terrain = view.terrain
	for l in track.landmarks:
		var kind := str(l.kind)
		var size := float(l.get("size", 80.0))
		var c := landmark_point(l)
		var side := float(l.side)
		var i := track.index_at(float(l.s))
		var nrm := track.normal[i] * side
		var tan := track.tangent[i]
		match kind:
			"lake", "marina":
				terrain.waters.append({"kind": "lake", "centre": c, "radius": size * 0.5, "level": track_low(c, size * 0.5 + 120.0) - 1.6})
			"river":
				var crossing := float(l.distance) < size * 0.5
				var dir := nrm if crossing else tan
				var w := clampf(size * 0.35, 30.0, 90.0)
				terrain.waters.append({"kind": "river", "centre": c, "dir": dir, "width": w, "length": 4000.0 if crossing else size * 2.5, "level": track_low(c, 150.0) - 4.0})
			"sea":
				var drop := 28.0 if view.theme() == "cliff" else 2.2
				terrain.waters.append({"kind": "sea", "centre": landmark_point(l, -size * 0.25), "dir": nrm, "level": track_low(c, size + 200.0) - drop})
			"hills":
				terrain.mounds.append({"kind": "hills", "centre": c, "radius": size * 0.6, "height": clampf(size * 0.12, 10.0, 40.0)})
			"dunes":
				terrain.mounds.append({"kind": "dunes", "centre": c, "radius": size * 0.6, "height": clampf(size * 0.08, 6.0, 22.0)})
			"rock_wall":
				for k in range(-int(size * 0.5), int(size * 0.5) + 1, 40):
					var q := track.world(float(l.s) + k, side * float(l.distance))
					terrain.mounds.append({"kind": "rock", "centre": Vector2(q.x, q.z), "radius": 55.0, "height": 34.0})


## Places the theme's scenery and the landmarks' models.
func build() -> void:
	root = Node3D.new()
	root.name = "Scenery"
	view.add_child(root)
	_water_planes()
	scatter.build(root)


func _water_planes() -> void:
	for w in terrain.waters:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var c: Vector2 = w.centre
		match str(w.kind):
			"lake":
				pm.size = Vector2.ONE * float(w.radius) * 2.2
			"river":
				pm.size = Vector2(float(w.width) + 30.0, float(w.length))
				var dir: Vector2 = w.dir
				mi.rotation.y = atan2(dir.x, dir.y)
			"sea":
				pm.size = Vector2.ONE * 24000.0
				var dir: Vector2 = w.dir
				c += dir * 12000.0
		pm.material = WorldLook.water()
		mi.mesh = pm
		mi.position = Vector3(c.x, float(w.level), c.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
