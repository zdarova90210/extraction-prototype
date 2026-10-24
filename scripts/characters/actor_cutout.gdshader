shader_type canvas_item;

varying vec4 actor_tint;

void vertex() {
	actor_tint = COLOR;
}

void fragment() {
	// SubViewport RGB is premultiplied. Solid pixel clusters must not reveal
	// scenery through resampling fringes; retain intentional CanvasItem fading.
	vec4 pose = texture(TEXTURE, UV);
	if (pose.a < 0.5) {
		discard;
	}
	COLOR = vec4(pose.rgb / max(pose.a, 0.001), 1.0) * actor_tint;
}
