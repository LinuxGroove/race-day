extends SceneTree
## Development aid: prints terrain heights across the track at a few places.
##   godot --headless --path . -s tools/world_debug.gd -- gp

const Demos := preload("res://tools/world_demos.gd")


func _init() -> void:
	var id: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "gp"
	if id == "all":
		for d in Demos.IDS:
			var tr := Track.build(Demos.plan(d), d, d)
			print("%s: %.0f m, %d corners, features %s, pit %s" % [d, tr.length, tr.corners.size(), tr.features, tr.pit.get("side", 0)])
		var pg := Track.build(ProvingGround.plan(), "proving", "proving")
		print("proving: %.0f m, %d corners" % [pg.length, pg.corners.size()])
		quit()
		return
	var info := Demos.info(id)
	var track := Track.build(Demos.plan(id), info.id, info.name)
	var v := TrackView.create(track, info, 1)
	var t := v.terrain
	print("base %.1f grid %dx%d origin %s" % [t.base_height, t.nx, t.nz, t.origin])
	for s in [0.0, 300.0, track.length * 0.5]:
		var line := "s=%5.0f y=%5.1f |" % [s, track.center_at(s).y]
		for lat in [-200, -100, -60, -40, -25, -15, 0, 15, 25, 40, 60, 100, 200]:
			var p := track.world(s, lat)
			line += " %d:%.1f/%.0f" % [lat, t.height(p.x, p.z), minf(t.clearance(p.x, p.z), 999)]
		print(line)
	v.free()
	quit()
