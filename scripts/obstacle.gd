@tool
extends StaticBody2D
## Editor-visible reusable cover. Size updates BOTH drawing and collision.

enum Kind { WALL, CRATE, CONTAINER }

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
	draw_rect(Rect2(rect.position + Vector2(6, 7), size), Color(0.02, 0.03, 0.03, 0.5))
	var color := Color("4b5150")
	if kind == Kind.CRATE:
		color = Color("70634c")
	elif kind == Kind.CONTAINER:
		color = Color("3e5757")
	draw_rect(rect, color)
	draw_rect(rect, Color("202c2e"), false, 3.0)
	draw_line(rect.position + Vector2(2, 2), rect.position + Vector2(size.x - 2, 2), color.lightened(0.22), 3.0)
	var inner := rect.grow(-9.0)
	if kind == Kind.CRATE:
		draw_rect(inner, color.darkened(0.25), false, 3.0)
		draw_line(inner.position, inner.end, color.darkened(0.25), 4.0)
		draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), color.darkened(0.25), 4.0)
	elif kind == Kind.CONTAINER:
		for x in range(int(inner.position.x), int(inner.end.x), 18):
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), color.darkened(0.25), 3.0)
	else:
		for x in range(int(inner.position.x), int(inner.end.x), 64):
			draw_line(Vector2(x, rect.position.y + 5), Vector2(x, rect.end.y - 5), color.darkened(0.2), 2.0)
