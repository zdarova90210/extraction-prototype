@tool
class_name FootstepSurface
extends Node2D
## Nonphysical ground patch: the same editable bounds drive drawing and sound.

@export var profile: FootstepProfile
## Optional movement rustle. A plant patch can have a cue without a floor profile.
@export var brush_cue: SoundCue
@export var priority: int = 0
## Reuse the saved floor polygon, so editing its outline also changes its sound.
@export var ground_polygon: Polygon2D
## Follow opaque water pixels instead of its rectangular texture canvas.
@export var ground_sprite: Sprite2D
var _image: Image
@export var size: Vector2 = Vector2(240, 96):
	set(value):
		size = Vector2(maxf(8.0, value.x), maxf(8.0, value.y))
		queue_redraw()
@export var draw_deck: bool = true:
	set(value):
		draw_deck = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"footstep_surfaces")
	if ground_sprite != null and ground_sprite.texture != null:
		_image = ground_sprite.texture.get_image()


func contains_point(point: Vector2) -> bool:
	if ground_polygon != null:
		return Geometry2D.is_point_in_polygon(ground_polygon.to_local(point), ground_polygon.polygon)
	if ground_sprite != null:
		if _image == null:
			return false
		var pixel := Vector2i((ground_sprite.to_local(point) - ground_sprite.get_rect().position).floor())
		if not Rect2i(Vector2i.ZERO, _image.get_size()).has_point(pixel):
			return false
		if ground_sprite.flip_h:
			pixel.x = _image.get_width() - 1 - pixel.x
		if ground_sprite.flip_v:
			pixel.y = _image.get_height() - 1 - pixel.y
		return _image.get_pixelv(pixel).a >= 0.5
	return Rect2(-size * 0.5, size).has_point(to_local(point))


func _draw() -> void:
	if not draw_deck:
		return
	var rect := Rect2(-size * 0.5, size)
	# A flush grate: all recess shading stays INSIDE the walking surface.
	draw_rect(rect, Color("303c3e"))
	var inset := minf(4.0, minf(size.x, size.y) * 0.2)
	var inner := rect.grow(-inset)
	draw_rect(inner, Color("202b2d"))
	for x in range(0, int(inner.size.x), 12):
		var start := inner.position + Vector2(x, 0)
		draw_line(start, start + Vector2(0, inner.size.y), Color("3c4a4c"), 2.0)
	for y in range(0, int(inner.size.y), 10):
		var start := inner.position + Vector2(0, y)
		draw_line(start, start + Vector2(inner.size.x, 0), Color("394749"), 2.0)
	# Inner shadow at the lit edges reads as a shallow recess, not a raised lid.
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("1c2729"), 2.0)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), Color("1c2729"), 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color("465354"), 1.0)
	draw_line(Vector2(rect.end.x, rect.position.y), rect.end, Color("465354"), 1.0)
