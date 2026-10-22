shader_type canvas_item;

void fragment() {
	// Reject faint halos without changing the source PNG/alpha.
	if (texture(TEXTURE, UV).a < 0.5) {
		discard;
	}
}
