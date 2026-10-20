extends Node2D
## Short-lived cosmetic tracer and deterministic impact sparks; no physics.

const LIFETIME: float = 0.14
var _end: Vector2 = Vector2.ZERO
var _hit: bool = false
var _remaining: float = LIFETIME
var _color: Color = Color(1.0, 0.86, 0.56)


func setup(from: Vector2, to: Vector2, hit: bool, color: Color = Color(1.0, 0.86, 0.56)) -> void:
	global_position = from
	_end = to - from
	_hit = hit
	_color = color
	z_index = 10
	queue_redraw()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
	else:
		modulate.a = _remaining / LIFETIME
		queue_redraw()


func _draw() -> void:
	draw_line(Vector2.ZERO, _end, Color(0.85, 0.64, 0.30, 0.25), 5.0, true)
	draw_line(Vector2.ZERO, _end, _color, 1.5, true)
	if _hit:
		var spread := (1.0 - _remaining / LIFETIME) * 13.0
		for index in range(5):
			var direction := Vector2.from_angle(float(index) * TAU / 5.0 + 0.3)
			draw_line(_end + direction * spread, _end + direction * (spread + 5.0), Color(1.0, 0.70, 0.32), 2.0, true)
