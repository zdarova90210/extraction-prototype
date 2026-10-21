@tool
class_name FootstepSurface
extends Node2D
## Nonphysical ground patch: the same editable bounds drive drawing and sound.

@export var profile: FootstepProfile
@export var priority: int = 0
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


func contains_point(point: Vector2) -> bool:
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
