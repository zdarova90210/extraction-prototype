extends Node2D
## Local scene wiring only; gameplay objects do not depend on this map.

@onready var target: StaticBody2D = $Target
@onready var status: Label = $HUD/Bottom/Status


func _ready() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	target.health_changed.connect(_on_target_health_changed)
	target.destroyed.connect(_on_target_destroyed)
	_on_target_health_changed(target.health, target.max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo():
		get_tree().reload_current_scene()


func _on_target_health_changed(current: float, maximum: float) -> void:
	status.text = "МИШЕНЬ  %d / %d" % [ceili(current), ceili(maximum)]


func _on_target_destroyed() -> void:
	status.text = "МИШЕНЬ РАЗРУШЕНА  ·  R — повторить"
