class_name WorldLook
extends RefCounted
## The world's colours and shared materials. Track surfaces use the Racing
## Kit's own colours (its road, white, red, grass and sand materials), so
## generated road and the kit's tiles match.
##
## Everything on the ground shares one material, so the rain can make it all
## wet at once (`set_wetness`), and night circuits can light it
## (`set_floodlight`).

## The Racing Kit's colours after `PropKit.deepen` (the road a little
## lighter, so it reads at dusk); its tiles are drawn in these too.
const ROAD := Color("6c6c71")
const LINE := Color("f5f5f8")
const KERB_RED := Color("e9605d")
const KERB_WHITE := Color("f5f5f8")
const GRASS := Color("6aa488")
const GRASS_DARK := Color("609c7f")
const GRAVEL := Color("d3c7aa")
const SAND := Color("e2b874")
const TARMAC := Color("7d828e")
const PIT_ROAD := Color("66666c")
const CONCRETE := Color("d6d7de")
const WALL_TOP := Color("e9605d")
const DECK := Color("9a9eaa")
const DRS_LINE := Color("f5f5f8")
const BOX_LINE := Color("f5d24a")
const WATER := Color("5fa3c9")
const ROCK := Color("9a958b")
const RED_ROCK := Color("b8683f")
const SHORE := Color("d8cba5")

## Terrain colours per theme: [near the track, further out].
const TERRAIN := {
	"parkland": [Color("6aa883"), Color("5f9d76")],
	"harbour": [Color("6fa888"), Color("a9a596")],
	"forest": [Color("5f9c71"), Color("518f64")],
	"airfield": [Color("86ad6c"), Color("7ba364")],
	"desert": [Color("dcb57c"), Color("d1a568")],
	"city": [Color("72a483"), Color("9c9ea8")],
	"mountain": [Color("6f9f72"), Color("8d8a7c")],
	"lake": [Color("68a681"), Color("5c9b75")],
	"countryside": [Color("80ad6a"), Color("9cb65e")],
	"oval": [Color("6aa883"), Color("63a07b")],
	"cliff": [Color("78a873"), Color("9a9884")],
	"hills": [Color("66a477"), Color("5a986a")],
	"canyon": [Color("d08d5f"), Color("c07a4c")],
	"proving": [Color("6aa488"), Color("639d80")],
}

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float floodlight : hint_range(0.0, 2.0) = 0.0;
uniform vec3 flood_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float tint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint_color : source_color = vec3(1.0);

varying float wet_mask;

void vertex() {
	wet_mask = COLOR.a;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb);
	base = mix(base, base * tint_color, tint);
	float w = clamp(wetness * wet_mask, 0.0, 1.0);
	ALBEDO = base * (1.0 - 0.42 * w);
	ROUGHNESS = mix(0.93, 0.16, w);
	SPECULAR = mix(0.25, 0.75, w);
	// Night circuits: the floodlights light everything near the track.
	EMISSION = base * flood_color * floodlight * 0.32 * (1.0 - 0.3 * w);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 color : source_color = vec3(0.37, 0.64, 0.79);
uniform vec3 deep : source_color = vec3(0.22, 0.45, 0.66);
uniform float glow : hint_range(0.0, 1.0) = 0.0;

float wave(vec2 p, float t) {
	return sin(p.x * 0.11 + t * 0.9) * 0.5 + sin(p.y * 0.07 - t * 0.7) * 0.5 + sin((p.x + p.y) * 0.19 + t * 1.3) * 0.25;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float e = 0.6;
	float dx = wave(wp.xz + vec2(e, 0.0), t) - wave(wp.xz - vec2(e, 0.0), t);
	float dz = wave(wp.xz + vec2(0.0, e), t) - wave(wp.xz - vec2(0.0, e), t);
	vec3 nw = normalize(vec3(-dx * 0.35, 1.0, -dz * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float f = clamp(wave(wp.xz * 0.3, t * 0.5) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(deep, color, f * 0.6 + 0.2);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION = color * glow * 0.15;
}
"""

static var _ground: ShaderMaterial
static var _props: StandardMaterial3D
static var _water: ShaderMaterial
static var _glow := {}
static var _flat := {}


## The one material every ground mesh (road, run-off, terrain) uses.
static func ground() -> ShaderMaterial:
	if _ground == null:
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		_ground = ShaderMaterial.new()
		_ground.shader = sh
	return _ground


## Vertex-coloured props (the Racing Kit and Nature Kit's flat colours).
static func props() -> StandardMaterial3D:
	if _props == null:
		_props = StandardMaterial3D.new()
		_props.vertex_color_use_as_albedo = true
		_props.vertex_color_is_srgb = true
		_props.roughness = 0.85
	return _props


static func water() -> ShaderMaterial:
	if _water == null:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water = ShaderMaterial.new()
		_water.shader = sh
	return _water


## A plain colour that glows (lamps, screens, windows at night).
static func glow(col: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "%s/%.2f" % [col.to_html(), energy]
	if not _glow.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
		m.roughness = 0.6
		_glow[key] = m
	return _glow[key]


## A plain lit colour.
static func flat(col: Color, rough := 0.8) -> StandardMaterial3D:
	var key := "%s/%.2f" % [col.to_html(), rough]
	if not _flat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		_flat[key] = m
	return _flat[key]


## Rain: 0 dry, 1 soaked. Darkens and glosses the road.
static func set_wetness(w: float) -> void:
	ground().set_shader_parameter("wetness", clampf(w, 0.0, 1.0))


## Night: how strongly the floodlights light the ground (0 for day).
static func set_floodlight(f: float, col := Color(1.0, 0.95, 0.85)) -> void:
	ground().set_shader_parameter("floodlight", f)
	ground().set_shader_parameter("flood_color", col)
	water().set_shader_parameter("glow", clampf(f, 0.0, 1.0))


## Colour with a wetness mask in alpha.
static func wet(col: Color, mask: float) -> Color:
	return Color(col.r, col.g, col.b, mask)


## The run-off colour for a TrackPlan.Runoff kind.
static func runoff(kind: int) -> Color:
	match kind:
		TrackPlan.Runoff.GRAVEL:
			return wet(GRAVEL, 0.3)
		TrackPlan.Runoff.TARMAC, TrackPlan.Runoff.WALL:
			return wet(TARMAC, 0.95)
		TrackPlan.Runoff.SAND:
			return wet(SAND, 0.2)
	return wet(GRASS, 0.25)
