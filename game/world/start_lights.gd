class_name StartLights
extends Node3D
## The five pairs of red start lights hanging from the start gantry, facing
## the grid. They light one pair at a time and go out together.

const PODS := 5
const OFF := Color("2a1414")
const ON := Color("ff2a1a")

var _lamps: Array = []
var _on: StandardMaterial3D
var _off: StandardMaterial3D


func _init() -> void:
	name = "StartLights"
	_on = WorldLook.glow(ON, 6.0)
	_off = WorldLook.flat(OFF, 0.4)
	var housing := BoxMesh.new()
	housing.size = Vector3(0.9, 2.3, 0.5)
	var lamp := SphereMesh.new()
	lamp.radius = 0.3
	lamp.height = 0.36
	lamp.radial_segments = 12
	lamp.rings = 6
	var dark := WorldLook.flat(Color("1d1e24"), 0.5)
	for k in PODS:
		var x := (k - (PODS - 1) * 0.5) * 1.25
		var h := MeshInstance3D.new()
		h.mesh = housing
		h.material_override = dark
		h.position = Vector3(x, 0, 0)
		add_child(h)
		for row in 2:
			var l := MeshInstance3D.new()
			l.mesh = lamp
			l.material_override = _off
			l.position = Vector3(x, 0.45 - row * 0.85, 0.22)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(l)
			_lamps.append(l)


## `lit` pairs of red lights on (0 to 5); `out` turns them all off (go!).
func set_lights(lit: int, out: bool) -> void:
	for k in _lamps.size():
		var pod := k / 2
		var on := not out and pod < lit
		(_lamps[k] as MeshInstance3D).material_override = _on if on else _off
