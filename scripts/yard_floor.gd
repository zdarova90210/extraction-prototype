@tool
extends Node2D
## Decorative floor only. The map's physical objects live in test_yard.tscn.

@export var size: Vector2 = Vector2(1760, 1120):
	set(value):
		size = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("2a3435"))
	for x in range(0, int(size.x), 80):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("303b3c"), 1.0)
	for y in range(0, int(size.y), 80):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("303b3c"), 1.0)
	# Worn service road and loading area.
	draw_rect(Rect2(120, 425, size.x - 260, 265), Color("303837"))
	for x in range(170, int(size.x) - 200, 120):
		draw_rect(Rect2(x, 550, 58, 5), Color("8c805b"))
	draw_rect(Rect2(940, 335, 490, 410), Color("7f7859"), false, 3.0)
	for y in range(360, 735, 32):
		draw_line(Vector2(945, y), Vector2(961, y - 16), Color("a19264"), 4.0)
	# Drain gratings and fixed oil stains, all cosmetic and deterministic.
	for origin in [Vector2(280, 790), Vector2(1450, 240)]:
		draw_rect(Rect2(origin, Vector2(100, 25)), Color("182729"))
		for offset in range(5, 100, 10):
			draw_line(origin + Vector2(offset, 3), origin + Vector2(offset, 22), Color("485452"), 2.0)
	for origin in [Vector2(390, 350), Vector2(1320, 850), Vector2(790, 230)]:
		draw_circle(origin, 32.0, Color(0.08, 0.11, 0.11, 0.32))
