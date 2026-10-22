shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 panel_size = vec2(760.0, 460.0);
uniform vec2 direction = vec2(1.0, 0.0);
uniform float blur_radius : hint_range(0.0, 40.0) = 24.0;
uniform float corner_radius : hint_range(0.0, 24.0) = 8.0;
uniform bool finish_glass = false;
uniform float darkening : hint_range(0.0, 1.0) = 0.48;
uniform float saturation : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	// Derivatives keep radius consistent in UI units under stretch/HiDPI.
	vec2 ui_to_screen = SCREEN_PIXEL_SIZE / max(fwidth(UV), vec2(0.000001));
	vec2 screen_min = SCREEN_UV - UV * ui_to_screen;
	vec2 inset = SCREEN_PIXEL_SIZE * 0.5;
	vec2 low = screen_min + inset;
	vec2 high = screen_min + ui_to_screen - inset;
	vec2 delta_uv = direction * (ui_to_screen / max(panel_size, vec2(1.0))) * blur_radius / 12.0;
	// Dense separable Gaussian: large sparse offsets leave repeated edges in pixel art.
	vec3 col = vec3(0.0);
	float total_weight = 0.0;
	for (int i = -12; i <= 12; i++) {
		float weight = exp(-float(i * i) / 50.0);
		col += texture(screen_texture, clamp(SCREEN_UV + delta_uv * float(i), low, high)).rgb * weight;
		total_weight += weight;
	}
	col /= total_weight;
	if (finish_glass) {
		float luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(luminance), col, saturation);
		col = mix(col, vec3(0.075), darkening);
		// Bright snow/lights must not wash out labels or item silhouettes.
		float glass_luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col *= min(1.0, 0.22 / max(glass_luminance, 0.001));
		col += vec3(0.008 * (1.0 - UV.y));
	}
	vec2 half_size = panel_size * 0.5;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	vec2 q = abs((UV - vec2(0.5)) * panel_size) - half_size + vec2(radius);
	float distance_to_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(-0.6, 0.6, distance_to_edge);
	// Alpha is the edge mask: mixing in sharp world pixels would undo the blur.
	COLOR = vec4(col, mask);
}
