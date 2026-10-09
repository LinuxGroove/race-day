class_name Structures
extends RefCounted
## The track's own buildings: tunnels (walls, roof and lights), bridge
## pillars under raised road, and the hotel that spans the track.

var view: TrackView
var track: Track
var roads: RoadBuilder


func _init(v: TrackView) -> void:
	view = v
	track = v.track
	roads = v.roads


func build() -> void:
	pass
