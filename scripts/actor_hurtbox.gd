extends Area2D
## Nonblocking damage silhouette, separate from the actor's movement collider.
## Uses the actor's existing collision layer; never moves or scales the body.

var _active_layer: int
@onready var actor: CharacterBody2D = get_parent()


func _ready() -> void:
	_active_layer = collision_layer
	actor.health_changed.connect(_on_health_changed)


func take_damage(amount: float) -> void:
	actor.take_damage(amount)


func _on_health_changed(current: float, _maximum: float) -> void:
	# Restore also emits health_changed; a revived player regains this silhouette.
	set_deferred("collision_layer", _active_layer if current > 0.0 else 0)
