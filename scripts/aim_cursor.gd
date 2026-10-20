extends Control
## Screen-space aiming feedback; independent of camera movement and game physics.

@export_range(10.0, 40.0, 1.0) var reload_radius: float = 18.0
@export var reticle_color: Color = Color("e2e9df")
@export var reload_color: Color = Color("dcc28a")
@export var empty_color: Color = Color("f0ac62")
@export var timing_color: Color = Color("81c7b1")
@export_range(0.3, 2.0, 0.1, "suffix:s") var empty_feedback_duration: float = 0.8

var is_reload_active: bool:
	get:
		return is_instance_valid(_player) and not _player.is_dead and is_instance_valid(_weapon) and _weapon.is_reloading
var reload_progress: float:
	get:
		return clampf(_weapon.reload_progress, 0.0, 1.0) if is_reload_active else 0.0
var is_empty_feedback_active: bool:
	get:
		return _empty_feedback_time > 0.0 and is_instance_valid(_player) and not _player.is_dead and is_instance_valid(_weapon) and _weapon.ammo == 0 and not _weapon.is_reloading

var _player: CharacterBody2D
var _weapon: Node2D
var _cursor_position: Vector2 = Vector2.ZERO
var _pointer_inside: bool = true
var _empty_feedback_time: float = 0.0


func _ready() -> void:
	_cursor_position = get_local_mouse_position()
	var viewport := get_viewport()
	if viewport is Window:
		viewport.mouse_entered.connect(_on_mouse_entered)
		viewport.mouse_exited.connect(_on_mouse_exited)
	get_viewport().size_changed.connect(_on_viewport_resized)


func bind(player: CharacterBody2D, weapon: Node2D) -> void:
	if is_instance_valid(_weapon) and _weapon.empty_triggered.is_connected(_on_empty_triggered):
		_weapon.empty_triggered.disconnect(_on_empty_triggered)
	_player = player
	_weapon = weapon
	_weapon.empty_triggered.connect(_on_empty_triggered)
	_empty_feedback_time = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_cursor_position = get_global_transform_with_canvas().affine_inverse() * event.position
		_pointer_inside = get_rect().has_point(_cursor_position)


func _process(delta: float) -> void:
	_empty_feedback_time = maxf(0.0, _empty_feedback_time - delta)
	if is_reload_active or not is_instance_valid(_player) or _player.is_dead or (is_instance_valid(_weapon) and _weapon.ammo > 0):
		_empty_feedback_time = 0.0
	var alive: bool = is_instance_valid(_player) and not _player.is_dead
	var mode := Input.MOUSE_MODE_HIDDEN if alive and _pointer_inside and get_window().has_focus() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
	queue_redraw()


func _on_empty_triggered() -> void:
	_empty_feedback_time = empty_feedback_duration
	queue_redraw()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_mouse_entered() -> void:
	_pointer_inside = true
	_cursor_position = get_local_mouse_position()


func _on_mouse_exited() -> void:
	_pointer_inside = false


func _on_viewport_resized() -> void:
	sync_pointer()


func sync_pointer() -> void:
	_cursor_position = get_local_mouse_position()
	_pointer_inside = get_rect().has_point(_cursor_position)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_player) or _player.is_dead or not _pointer_inside:
		return
	var shadow := Color(0.025, 0.04, 0.04, 0.9)
	var warning: bool = is_empty_feedback_active
	var kick := maxf(0.0, (_empty_feedback_time / empty_feedback_duration - 0.6) / 0.4) if warning else 0.0
	var color := empty_color if warning else reticle_color
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var from: Vector2 = _cursor_position + direction * (5.0 + kick * 2.0)
		var to: Vector2 = _cursor_position + direction * (10.0 + kick * 4.0)
		draw_line(from, to, shadow, 4.0, true)
		draw_line(from, to, color, 2.0 if warning else 1.5, true)
	if warning:
		var key := Rect2(_cursor_position + Vector2(-9, 19), Vector2(18, 18))
		draw_rect(key, shadow)
		draw_rect(key, empty_color, false, 1.0)
		draw_string(ThemeDB.fallback_font, _cursor_position + Vector2(-4.5, 32), "R", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, empty_color)
	if is_reload_active:
		var timing_available: bool = _weapon.reload_timing == _weapon.ReloadTiming.AVAILABLE
		var timing_success: bool = _weapon.reload_timing == _weapon.ReloadTiming.SUCCESS
		var ring_color := timing_color if timing_success else reload_color
		draw_arc(_cursor_position, reload_radius, -PI * 0.5, PI * 1.5, 64, shadow, 6.0, true)
		draw_arc(_cursor_position, reload_radius, -PI * 0.5, PI * 1.5, 64, Color(0.62, 0.68, 0.63, 0.35), 2.5, true)
		if timing_available:
			var start_angle: float = -PI * 0.5 + TAU * _weapon.active_window_start
			var end_angle: float = -PI * 0.5 + TAU * _weapon.active_window_end
			draw_arc(_cursor_position, reload_radius, start_angle, end_angle, 16, timing_color, 5.0, true)
			for angle in [start_angle, end_angle]:
				var direction := Vector2.from_angle(angle)
				draw_line(_cursor_position + direction * (reload_radius - 4), _cursor_position + direction * (reload_radius + 4), timing_color, 1.5, true)
			if reload_progress <= _weapon.active_window_end:
				var key := Rect2(_cursor_position + Vector2(-8, reload_radius + 8), Vector2(16, 17))
				draw_rect(key, shadow)
				draw_string(ThemeDB.fallback_font, key.position + Vector2(3.5, 13), "R", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, timing_color)
		if reload_progress > 0.0:
			draw_arc(_cursor_position, reload_radius, -PI * 0.5, -PI * 0.5 + TAU * reload_progress, 64, ring_color, 2.5, true)
			var tip := Vector2.from_angle(-PI * 0.5 + TAU * reload_progress)
			draw_line(_cursor_position + tip * (reload_radius - 3), _cursor_position + tip * (reload_radius + 3), ring_color, 2.0, true)
		if timing_success:
			var mark := _cursor_position + Vector2(0, reload_radius + 13)
			draw_line(mark + Vector2(-4, 0), mark + Vector2(-1, 3), timing_color, 2.0, true)
			draw_line(mark + Vector2(-1, 3), mark + Vector2(5, -4), timing_color, 2.0, true)
