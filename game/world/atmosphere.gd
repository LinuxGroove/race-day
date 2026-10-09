class_name Atmosphere
extends Node
## The sky, sun, ambient light and fog for a circuit's time of day, the
## floodlights at night races, and rain.
##
##   var atmo := Atmosphere.create(info, view)   # info from Circuits.info
##   add_child(atmo)
##   atmo.follow(camera)        # each player's camera (rain and lights follow)
##   atmo.set_rain(0.7)         # 0 dry to 1 a downpour
##   atmo.set_time(0.5)         # dusk_to_night: 0 dusk to 1 night
##
## Night races light the track three ways, all cheap: the ground material
## glows as if floodlit, light posts have glowing lamps, and a small pool of
## real lights moves to the posts nearest each camera.

const SKY_SHADER := """
shader_type sky;
uniform sampler2D sky_a : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_b : source_color, filter_linear, repeat_enable;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float energy = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float grey : hint_range(0.0, 1.0) = 0.0;

void sky() {
	vec2 uv = vec2(atan(EYEDIR.x, EYEDIR.z) / TAU + 0.5, acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI);
	vec3 a = texture(sky_a, uv).rgb;
	vec3 b = texture(sky_b, uv).rgb;
	vec3 c = mix(a, b, blend) * tint;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(l) * vec3(0.92, 0.95, 1.0), grey);
	COLOR = c * energy;
}
"""

const SKIES := {
	"day": "res://assets/kenney/skyboxes/skybox-day.png",
	"dusk": "res://assets/kenney/skyboxes/skybox-morning.png",
	"night": "res://assets/kenney/skyboxes/skybox-night.png",
}

## Per time of day: sun elevation and direction (degrees), sun colour and
## energy, ambient colour and energy, fog colour and density, floodlights.
const LOOKS := {
	"day": {"elev": 50.0, "yaw": 149.0, "sun": Color(1.0, 0.97, 0.9), "sun_e": 1.25, "amb": Color(0.78, 0.84, 0.96), "amb_e": 0.75, "fog": Color(0.76, 0.84, 0.96), "fog_d": 0.00022, "flood": 0.0, "sky_e": 1.0},
	"dusk": {"elev": 15.0, "yaw": 250.0, "sun": Color(1.0, 0.7, 0.46), "sun_e": 1.2, "amb": Color(0.9, 0.8, 0.84), "amb_e": 1.15, "fog": Color(0.93, 0.72, 0.62), "fog_d": 0.00028, "flood": 0.25, "sky_e": 1.0},
	"night": {"elev": 58.0, "yaw": 210.0, "sun": Color(0.92, 0.93, 1.0), "sun_e": 0.55, "amb": Color(0.52, 0.56, 0.72), "amb_e": 0.55, "fog": Color(0.08, 0.1, 0.18), "fog_d": 0.00035, "flood": 1.0, "sky_e": 0.9},
}

const POOL := 6
const RAIN_LAYER := 11

var time_of_day := "day"
var env: Environment
var sun: DirectionalLight3D
var view: TrackView

var _t := 0.0
var _rain := 0.0
var _sky_mat: ShaderMaterial
var _world_env: WorldEnvironment
var _cams: Array = []
var _drops: Array = []
var _pool: Array = []


## Makes the atmosphere for a circuit: `info` from Circuits.info (or just
## its time of day, "day", "dusk", "night" or "dusk_to_night"), then the
## TrackView (for the light posts at night) or how wet it is (0 to 1).
static func create(info: Variant, view_or_wet: Variant = null) -> Atmosphere:
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	if view_or_wet is TrackView:
		a.view = view_or_wet
	a.time_of_day = str((info as Dictionary).get("time", "day")) if info is Dictionary else str(info)
	a._make()
	a.set_time(0.0)
	if view_or_wet is float or view_or_wet is int:
		a.set_rain(float(view_or_wet))
	return a


func _make() -> void:
	env = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_sky_mat.shader = sh
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	add_child(_world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.shadow_blur = 1.5
	add_child(sun)


## For dusk_to_night circuits: 0 is dusk, 1 full night. Other circuits keep
## their own time whatever `t` is.
func set_time(t: float) -> void:
	_t = clampf(t, 0.0, 1.0)
	var a: Dictionary
	var b: Dictionary
	var f := 0.0
	match time_of_day:
		"dusk_to_night":
			a = LOOKS.dusk
			b = LOOKS.night
			f = _t
		"dusk", "night":
			a = LOOKS[time_of_day]
			b = a
		_:
			a = LOOKS.day
			b = a
	_sky_mat.set_shader_parameter("sky_a", load(SKIES["dusk" if time_of_day == "dusk_to_night" else (time_of_day if SKIES.has(time_of_day) else "day")]))
	_sky_mat.set_shader_parameter("sky_b", load(SKIES["night" if time_of_day == "dusk_to_night" else (time_of_day if SKIES.has(time_of_day) else "day")]))
	_sky_mat.set_shader_parameter("blend", f)
	var elev := lerpf(float(a.elev), float(b.elev), f)
	var yaw := lerp_angle(deg_to_rad(float(a.yaw)), deg_to_rad(float(b.yaw)), f)
	var dir := Vector3(sin(yaw) * cos(deg_to_rad(elev)), sin(deg_to_rad(elev)), cos(yaw) * cos(deg_to_rad(elev)))
	sun.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
	_apply(a, b, f)


func _apply(a: Dictionary, b: Dictionary, f: float) -> void:
	var wet := _rain
	var sun_e := lerpf(float(a.sun_e), float(b.sun_e), f) * (1.0 - 0.6 * wet)
	sun.light_color = (a.sun as Color).lerp(b.sun, f)
	sun.light_energy = sun_e
	var amb: Color = (a.amb as Color).lerp(b.amb, f)
	env.ambient_light_color = amb.lerp(Color(0.62, 0.66, 0.72), wet * 0.6)
	env.ambient_light_energy = lerpf(float(a.amb_e), float(b.amb_e), f) * (1.0 + 0.25 * wet)
	var fog: Color = (a.fog as Color).lerp(b.fog, f)
	env.fog_light_color = fog.lerp(Color(0.58, 0.62, 0.68) * (1.0 - 0.7 * f if time_of_day == "dusk_to_night" else 1.0), wet * 0.7)
	env.fog_density = lerpf(float(a.fog_d), float(b.fog_d), f) * (1.0 + 5.0 * wet)
	env.fog_sky_affect = wet * 0.85
	_sky_mat.set_shader_parameter("energy", lerpf(float(a.sky_e), float(b.sky_e), f) * (1.0 - 0.35 * wet))
	_sky_mat.set_shader_parameter("grey", wet * 0.75)
	var flood := lerpf(float(a.flood), float(b.flood), f)
	WorldLook.set_floodlight(flood)
	WorldLook.set_wetness(wet)
	env.ssr_enabled = false
	for l in _pool:
		(l as OmniLight3D).visible = flood > 0.3
		(l as OmniLight3D).light_energy = 3.0 * flood
	if view:
		view.set_night_glow(flood)


## Rain from 0 (dry) to 1: wet, glossy road, grey sky, fog and falling rain.
func set_rain(amount: float) -> void:
	_rain = clampf(amount, 0.0, 1.0)
	set_time(_t)
	for d in _drops:
		var p := d as GPUParticles3D
		p.emitting = _rain > 0.01
		p.amount_ratio = maxf(0.05, _rain)


## Rain falls round this camera and night lights follow it. Call once per
## player camera (split screen calls it twice); each camera sees only its
## own rain.
func follow(camera: Camera3D) -> void:
	if camera in _cams:
		return
	var k := _cams.size()
	_cams.append(camera)
	var drops := _make_rain()
	var layer := 1 << (RAIN_LAYER - 1 + k)
	drops.layers = layer
	add_child(drops)
	_drops.append(drops)
	# Each camera ignores the other cameras' rain.
	for other in _cams:
		if other != camera:
			(other as Camera3D).cull_mask &= ~layer
	for j in k:
		camera.cull_mask &= ~(1 << (RAIN_LAYER - 1 + j))
	drops.emitting = _rain > 0.01
	drops.amount_ratio = maxf(0.05, _rain)
	if view and not view.lamp_posts().is_empty():
		for i in POOL / 2:
			var l := OmniLight3D.new()
			l.omni_range = 55.0
			l.omni_attenuation = 1.2
			l.light_color = Color(1.0, 0.93, 0.8)
			l.shadow_enabled = false
			add_child(l)
			_pool.append(l)
	set_time(_t)


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 5000
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(38, 2, 38)
	m.direction = Vector3(0.05, -1, 0.0)
	m.spread = 3.0
	m.initial_velocity_min = 24.0
	m.initial_velocity_max = 28.0
	m.gravity = Vector3(0, -9.8, 0)
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.75)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	# Drops right in front of the lens would smear across the screen.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.5
	mat.distance_fade_max_distance = 5.0
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _ready() -> void:
	# Made with just a time of day: the circuit's view is usually a sibling.
	if view == null and get_parent():
		for ch in get_parent().get_children():
			if ch is TrackView:
				view = ch
				break


func _process(_delta: float) -> void:
	# A scene that never calls follow() still gets rain round its camera.
	if _cams.is_empty():
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		if cam:
			follow(cam)
	for k in _cams.size():
		var cam := _cams[k] as Camera3D
		if not is_instance_valid(cam):
			continue
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		var at := cam.global_position + fwd.normalized() * 18.0 + Vector3(0, 16, 0)
		(_drops[k] as GPUParticles3D).global_position = at
	_place_pool()


## Moves the real lights to the posts nearest the cameras.
func _place_pool() -> void:
	if _pool.is_empty() or not (_pool[0] as OmniLight3D).visible:
		return
	var posts := view.lamp_posts()
	var per := maxi(1, _pool.size() / maxi(1, _cams.size()))
	var used := {}
	var li := 0
	for cam in _cams:
		if not is_instance_valid(cam):
			continue
		var cp: Vector3 = (cam as Camera3D).global_position
		var near := []
		for i in posts.size():
			var d := cp.distance_squared_to(posts[i])
			near.append([d, i])
		near.sort_custom(func(x, y): return x[0] < y[0])
		var placed := 0
		for e in near:
			if placed >= per or li >= _pool.size():
				break
			if used.has(e[1]):
				continue
			used[e[1]] = true
			(_pool[li] as OmniLight3D).global_position = posts[e[1]] + Vector3(0, -1.5, 0)
			li += 1
			placed += 1
