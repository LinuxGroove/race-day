class_name PlayerView
extends Control
## One player's share of the screen: a viewport onto the shared world with
## their camera, their braking line and their HUD. Two of these split the
## screen top and bottom.

## Render layers 11 and 12 hold each player's own braking line.
const LINE_LAYER := 10

var index := 0
var count := 1
var camera: RaceCamera
var hud: RaceHud
var line: BrakingLine
var driver: PlayerDriver
var _container: SubViewportContainer
var _viewport: SubViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.audio_listener_enable_3d = index == 0
	_container.add_child(_viewport)
	camera = RaceCamera.new()
	camera.view = _saved_view()
	# Each camera sees everything but the other players' braking lines.
	var mask := 0xFFFFF
	for i in 2:
		if i != index:
			mask &= ~(1 << (LINE_LAYER + i))
	camera.cull_mask = mask
	_viewport.add_child(camera)
	hud = RaceHud.new()
	hud.index = index
	hud.split = count > 1
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hud)


func _saved_view() -> String:
	var v := str(LGSettings.get_value("camera", "view"))
	return v if v in GameConfig.CAMERAS else "chase_near"


func attach(scene: RaceScene, p_driver: PlayerDriver, car: CarView) -> void:
	driver = p_driver
	camera.attach(car, p_driver.entry.sim)
	camera.set_view(camera.view)
	camera.make_current()
	if line == null:
		line = BrakingLine.new()
		scene.world.add_child(line)
	line.setup(p_driver, LINE_LAYER + index)
	hud.attach(scene, p_driver)
	if car.has_meta("audio"):
		(car.get_meta("audio") as CarAudio).set_view(camera.view == "cockpit")


func next_camera() -> void:
	var i := GameConfig.CAMERAS.find(camera.view)
	var v: String = GameConfig.CAMERAS[(i + 1) % GameConfig.CAMERAS.size()]
	camera.set_view(v)
	if index == 0:
		LGSettings.set_value("camera", "view", v)
	hud.show_camera_name(GameConfig.CAMERA_NAMES[v])
	if camera.car and camera.car.has_meta("audio"):
		(camera.car.get_meta("audio") as CarAudio).set_view(v == "cockpit")


func _exit_tree() -> void:
	if line and is_instance_valid(line):
		line.queue_free()
