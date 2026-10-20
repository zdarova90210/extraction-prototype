@tool
extends Area2D
## World-local extraction countdown. Does not decide rewards or scene changes.

signal completed
@export var size: Vector2 = Vector2(160, 100):
	set(value):
		size = value.max(Vector2(60, 60))
		if is_node_ready():
			$CollisionShape2D.shape.size = size
		queue_redraw()
@export_range(0.5, 20.0, 0.5, "suffix:s") var duration: float = 5.0
var elapsed: float = 0.0
var _player: CharacterBody2D
var _finished: bool = false
var _failure: String = ""


func _ready() -> void:
	$CollisionShape2D.shape.size = size
	_update_status()


func bind(player: CharacterBody2D) -> void:
	_player = player


func contains_player() -> bool:
	return is_instance_valid(_player) and Rect2(-size * 0.5, size).has_point(to_local(_player.global_position))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _finished:
		return
	if not contains_player() or _player.is_dead:
		elapsed = 0.0
		_failure = ""
	elif _failure.is_empty():
		elapsed = minf(duration, elapsed + delta)
		if elapsed >= duration:
			_finished = true
			completed.emit()
	_update_status()
	queue_redraw()


func save_failed(message: String) -> void:
	_finished = false
	elapsed = 0.0
	_failure = message + "\nВыйдите из зоны и попробуйте снова."
	_update_status()


func _update_status() -> void:
	var status: Label = $Status
	if not _failure.is_empty():
		status.text = _failure
	elif elapsed > 0.0:
		status.text = "ЭВАКУАЦИЯ · %.1f с" % maxf(0.0, duration - elapsed)
	else:
		status.text = "ЭВАКУАЦИЯ · %.1f с\nОставайтесь внутри зоны" % duration


func _draw() -> void:
	var area := Rect2(-size * 0.5, size)
	draw_rect(area, Color(0.16, 0.34, 0.26, 0.30))
	draw_rect(area, Color(0.48, 0.74, 0.53, 0.85), false, 2.0)
	for x in range(int(-size.x * 0.5 + 12), int(size.x * 0.5), 20):
		draw_line(Vector2(x, size.y * 0.5 - 12), Vector2(x + 8, size.y * 0.5 - 20), Color(0.48, 0.74, 0.53, 0.4), 2)
	if elapsed > 0.0:
		draw_rect(Rect2(-size * 0.5 + Vector2(6, 6), Vector2((size.x - 12) * elapsed / duration, 5)), Color("b1d7a2"))
