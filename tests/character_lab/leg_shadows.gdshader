shader_type canvas_item;

// Lift painted shadow detail without widening the silhouette or washing out
// the darkest outline. Shared by both legs, including their articulated parts.
uniform float shadow_lift : hint_range(0.0, 0.08, 0.005) = 0.035;

void fragment() {
	float luminance = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float shadow = smoothstep(0.02, 0.08, luminance)
		* (1.0 - smoothstep(0.25, 0.5, luminance));
	COLOR.rgb += vec3(1.0, 0.92, 0.8) * shadow_lift * shadow;
}
