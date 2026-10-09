shader_type spatial;
// Kenney's colormap with the team's colours painted over it: the kit's own
// livery colour (any saturated pixel) becomes the team's main colour and
// its light panels the accent, keeping the kit's shading.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec3 main_color : source_color = vec3(1.0, 0.3, 0.2);
uniform vec3 accent_color : source_color = vec3(1.0);
uniform float key_bright = 0.93;
uniform float light_to_accent = 1.0;
uniform float roughness_value = 0.45;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.001);
	if (sat > 0.32) {
		c = main_color * clamp(mx / key_bright, 0.55, 1.15);
	} else if (mx > 0.82 && light_to_accent > 0.5) {
		c = accent_color * clamp(mx / 0.93, 0.7, 1.1);
	}
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
