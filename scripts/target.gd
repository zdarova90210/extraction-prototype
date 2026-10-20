@tool
extends StaticBody2D
## A stationary damageable body, with a non-colliding wreck on destruction.

signal health_changed(current: float, maximum: float)
signal destroyed

@export_range(1.0, 2000.0, 1.0) var max_health: float = 100.0

var health: float = 100.0
var is_destroyed: bool = false
var _hit_time: float = 0.0


func _ready() -> void:
	health = max_health
	queue_redraw()


func take_damage(amount: float) -> void:
	if Engine.is_editor_hint() or is_destroyed or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hit_time = 0.16
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_destroyed = true
		# Defer collision changes to safely support calls during a physics tick.
		set_deferred("collision_layer", 0)
		$CollisionShape2D.set_deferred("disabled", true)
		destroyed.emit()
	queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _hit_time > 0.0:
		_hit_time = maxf(0.0, _hit_time - delta)
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(3, 5), 29.0, Color(0.025, 0.033, 0.034, 0.65))
	if is_destroyed:
		draw_rect(Rect2(-25, -18, 50, 36), Color("393e3b"))
		draw_line(Vector2(-20, -14), Vector2(18, 12), Color("73634b"), 4.0, true)
		draw_line(Vector2(15, -15), Vector2(-16, 10), Color("73634b"), 4.0, true)
		return
	draw_rect(Rect2(-28, -28, 56, 56), Color("242e30"))
	draw_rect(Rect2(-25, -25, 50, 50), Color("b19a72"), false, 2.0)
	var plate_color := Color("8e6250") if _hit_time <= 0.0 else Color("f5d594")
	draw_circle(Vector2.ZERO, 21.0, plate_color)
	draw_arc(Vector2.ZERO, 14.0, 0, TAU, 32, Color("d3b98c"), 2.0, true)
	draw_circle(Vector2.ZERO, 5.0, Color("323b39"))
	draw_rect(Rect2(-28, -41, 56, 5), Color("172025"))
	var ratio := 1.0 if Engine.is_editor_hint() else health / max_health
	draw_rect(Rect2(-28, -41, 56 * ratio, 5), Color("c6aa72"))
