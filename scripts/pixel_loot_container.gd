@tool
extends "res://scripts/loot_container.gd"
## Shared loot ownership/search; only the prototype drawing is replaced.


func _draw() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.self_modulate = Color(1.25, 1.25, 1.1) if _highlighted else Color.WHITE
