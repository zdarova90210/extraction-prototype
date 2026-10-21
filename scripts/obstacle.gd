@tool
extends StaticBody2D
## Editor-visible reusable cover. Size updates BOTH drawing and collision.

enum Kind { WALL, CRATE, CONTAINER }

@export var impact_cue: SoundCue
@export_range(4.0, 24.0, 1.0, "suffix:px") var container_face_depth: float = 12.0:
	set(value):
		container_face_depth = value
		queue_redraw()

@export var kind: Kind = Kind.CRATE:
	set(value):
		kind = value
		queue_redraw()
@export var size: Vector2 = Vector2(80, 80):
	set(value):
		size = Vector2(maxf(value.x, 16.0), maxf(value.y, 16.0))
		_sync_shape()
		queue_redraw()


func _ready() -> void:
	_sync_shape()
	queue_redraw()


func get_impact_cue() -> SoundCue:
	if impact_cue != null:
		return impact_cue
	match kind:
		Kind.CRATE:
			return preload("res://resources/audio/combat/wood.tres")
		Kind.CONTAINER:
			return preload("res://resources/audio/combat/metal.tres")
	return preload("res://resources/audio/combat/concrete.tres")


func _sync_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	# Each instance owns its shape; resizing one crate never resizes another.
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle


func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	if kind == Kind.CONTAINER:
		_draw_container(rect)
		return
	draw_rect(Rect2(rect.position + Vector2(6, 7), size), Color(0.02, 0.03, 0.03, 0.5))
	var color := Color("4b5150")
	if kind == Kind.CRATE:
		color = Color("70634c")
	draw_rect(rect, color)
	draw_rect(rect, Color("202c2e"), false, 3.0)
	draw_line(rect.position + Vector2(2, 2), rect.position + Vector2(size.x - 2, 2), color.lightened(0.22), 3.0)
	var inner := rect.grow(-9.0)
	if kind == Kind.CRATE:
		draw_rect(inner, color.darkened(0.25), false, 3.0)
		draw_line(inner.position, inner.end, color.darkened(0.25), 4.0)
		draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), color.darkened(0.25), 4.0)
	else:
		for x in range(int(inner.position.x), int(inner.end.x), 64):
			draw_line(Vector2(x, rect.position.y + 5), Vector2(x, rect.end.y - 5), color.darkened(0.2), 2.0)


func _draw_container(footprint: Rect2) -> void:
	# Roof and visible faces share the existing collision footprint. Only the
	# translucent cast shadow extends onto the ground; no invisible cover is added.
	var depth := minf(container_face_depth, minf(size.x, size.y) * 0.3)
	var side := depth * 0.65
	var roof := Rect2(footprint.position, size - Vector2(side, depth))
	draw_rect(Rect2(footprint.position + Vector2(side + 5, depth + 5), size), Color(0.015, 0.025, 0.026, 0.18))
	draw_rect(Rect2(footprint.position + Vector2(side, depth), size), Color(0.015, 0.025, 0.026, 0.40))
	draw_rect(footprint, Color("263638"))
	draw_rect(Rect2(Vector2(roof.end.x, footprint.position.y), Vector2(side, size.y)), Color("30474b"))
	draw_rect(Rect2(Vector2(footprint.position.x, roof.end.y), Vector2(size.x - side, depth)), Color("2b3d40"))
	draw_rect(roof, Color("496164"))
	var rib_inset := minf(9.0, minf(roof.size.x, roof.size.y) * 0.2)
	var panel := roof.grow(-rib_inset)
	for x in range(int(panel.position.x), int(panel.end.x), 18):
		draw_line(Vector2(x, panel.position.y), Vector2(x, panel.end.y), Color("30484c"), 3.0)
		draw_line(Vector2(x + 2, panel.position.y), Vector2(x + 2, panel.end.y), Color("597276"), 1.0)
		# The shorter, darker continuation makes the front face legible as height.
		draw_line(Vector2(x, roof.end.y + 3), Vector2(x, footprint.end.y - 2), Color("1d2d30"), 2.0)
	draw_rect(footprint, Color("1c292c"), false, 2.0)
	draw_line(roof.position + Vector2(2, 2), Vector2(roof.end.x - 1, roof.position.y + 2), Color("799093"), 2.0)
	draw_line(roof.position + Vector2(2, 2), Vector2(roof.position.x + 2, roof.end.y), Color("667f82"), 2.0)
	draw_line(Vector2(roof.position.x + 2, roof.end.y), roof.end, Color("708789"), 1.0)
	draw_line(Vector2(roof.end.x, roof.position.y + 2), roof.end, Color("263b3e"), 2.0)
