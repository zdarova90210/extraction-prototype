@tool
extends "res://scripts/world_cover.gd"
## Test-only geometric marker. All collision/material behavior is production code.

func _draw() -> void:
	draw_rect(Rect2(-size * 0.5, size), Color(0.31, 0.34, 0.33))
