shader_type canvas_item;
uniform float atlas_column : hint_range(0.0, 1.0) = 0.0;
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec2 tile_uv = fract(UV);
	tile_uv.x = (tile_uv.x + atlas_column) * 0.5;
	COLOR = texture(TEXTURE, tile_uv) * vertex_color;
}
