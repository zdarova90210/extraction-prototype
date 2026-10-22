extends Node
## Fade tall foreground artwork over the local player; collision/AI stay intact.

@export var visual: Sprite2D
@export_range(0.1, 0.9, 0.05) var obscured_alpha: float = 0.3
@export_range(1.0, 20.0, 0.5) var fade_speed: float = 5.0
var _subject: Node2D
var is_obscuring: bool = false


func _process(delta: float) -> void:
	if not is_instance_valid(visual):
		return
	if not is_instance_valid(_subject):
		_subject = get_tree().get_first_node_in_group(&"occlusion_subject") as Node2D
	is_obscuring = false
	if is_instance_valid(_subject) and _subject.global_position.y < visual.get_parent().global_position.y:
		var bounds := visual.get_rect()
		for offset in [Vector2(0, -32), Vector2(-12, -12), Vector2(12, -12), Vector2(0, 8)]:
			if bounds.has_point(visual.to_local(_subject.global_position + offset)):
				is_obscuring = true
				break
	var color := visual.self_modulate
	color.a = move_toward(color.a, obscured_alpha if is_obscuring else 1.0, fade_speed * delta)
	visual.self_modulate = color
