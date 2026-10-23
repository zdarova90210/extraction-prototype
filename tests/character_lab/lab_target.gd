@tool
extends "res://tests/fixtures/target.gd"
## Same damageable test target; only its drawing is lifted above the ground collider.

func _draw() -> void:
	draw_line(Vector2(0, -50), Vector2(0, 0), Color("665b45"), 6.0)
	draw_line(Vector2(-17, 1), Vector2(17, 1), Color("35352e"), 4.0)
	draw_set_transform(Vector2(0, -50))
	super._draw()
	draw_set_transform(Vector2.ZERO)
