@tool
extends Node2D
## Small shared geometric character. Visual size never defines collision size.

@export var uniform_color: Color = Color("7e9b91"):
	set(value):
		uniform_color = value
		queue_redraw()
@export var armor_color: Color = Color("334c49"):
	set(value):
		armor_color = value
		queue_redraw()
var fallen: bool = false:
	set(value):
		fallen = value
		queue_redraw()
var _hit_time: float = 0.0


func flash_hit() -> void:
	_hit_time = 0.15
	queue_redraw()


func _process(delta: float) -> void:
	if _hit_time > 0.0:
		_hit_time = maxf(0.0, _hit_time - delta)
		queue_redraw()


func _draw() -> void:
	if fallen:
		draw_ellipse_body(Color("343c3a"), Color("242d2c"))
		draw_line(Vector2(-10, -10), Vector2(12, 10), Color("7c6659"), 3.0, true)
		return
	var fabric := Color("f2dbc0") if _hit_time > 0.0 else uniform_color
	draw_ellipse_body(fabric, armor_color)
	# Backpack, shoulder pads and helmet separate the silhouette from the floor.
	draw_rect(Rect2(-18, -8, 9, 16), armor_color.darkened(0.2))
	draw_circle(Vector2(0, -12), 6.0, fabric.darkened(0.2))
	draw_circle(Vector2(0, 12), 6.0, fabric.darkened(0.2))
	draw_circle(Vector2(5, 0), 9.0, fabric.lightened(0.12))
	draw_arc(Vector2(5, 0), 9.0, -1.1, 1.1, 12, Color("1c292b"), 3.0, true)
	draw_line(Vector2(-10, -9), Vector2(-10, 9), fabric.lightened(0.25), 2.0)


func draw_ellipse_body(fabric: Color, armor: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-14, -10), Vector2(-2, -15), Vector2(13, -10),
		Vector2(17, 0), Vector2(13, 10), Vector2(-2, 15), Vector2(-14, 10)
	]), fabric)
	draw_rect(Rect2(-10, -10, 13, 20), armor)
