@tool
extends AmbientSpot
## Decorative source: the ambience scheduler owns crackles; this fixture owns its hum.

@export var hum_stream: AudioStream
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var hum_volume_db: float = -3.0
@export_range(0.0, 1.5, 0.05) var light_energy: float = 0.55
@export_range(0.0, 0.4, 0.01) var flicker_depth: float = 0.18

var _rng := RandomNumberGenerator.new()
var _level: float = 1.0
var _target_level: float = 1.0
var _change_remaining: float = 0.0
var _warmup: float = 0.0
var _phase: float = 0.0
var _running: bool = false
var _was_sputtering: bool = false
@onready var hum: AudioStreamPlayer2D = $Hum
@onready var pool: PointLight2D = $Pool
@onready var emitter: Line2D = $Emitter


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rng.randomize()
	_phase = _rng.randf_range(0.0, TAU)


func start_ambience() -> void:
	if Engine.is_editor_hint() or _running:
		return
	_running = true
	_warmup = 0.0
	hum.stream = hum_stream
	hum.volume_db = -60.0
	if hum_stream != null:
		hum.play(_rng.randf_range(0.0, maxf(0.0, hum_stream.get_length() - 0.1)))


func stop_ambience() -> void:
	stop()
	hum.stop()
	_running = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	_warmup = minf(1.5, _warmup + delta)
	hum.volume_db = linear_to_db(db_to_linear(hum_volume_db) * maxf(0.001, smoothstep(0.0, 1.5, _warmup)))
	_phase += delta * 0.8
	_change_remaining -= delta
	if playing != _was_sputtering:
		_change_remaining = 0.0
		_was_sputtering = playing
	if _change_remaining <= 0.0:
		# A sparse, soft dip only while this very fixture is audibly sputtering.
		_target_level = _rng.randf_range(1.0 - flicker_depth, 1.0) if playing else 1.0
		_change_remaining = _rng.randf_range(0.09, 0.24) if playing else _rng.randf_range(0.8, 1.8)
	_level = move_toward(_level, _target_level, delta * 2.5)
	var brightness := _level * (0.99 + sin(_phase) * 0.01)
	pool.energy = light_energy * brightness
	emitter.modulate = Color(brightness, brightness, brightness)


func _draw() -> void:
	# Surface-mounted housing on the inner face of a wall; no physical footprint.
	draw_polyline(PackedVector2Array([Vector2(-58, -16), Vector2(-58, -27), Vector2(-13, -27), Vector2(-13, -18)]), Color("20292a"), 3.0)
	draw_rect(Rect2(-66, -14, 132, 30), Color(0.025, 0.035, 0.035, 0.35))
	draw_rect(Rect2(-68, -20, 136, 28), Color("151e21"))
	draw_rect(Rect2(-65, -19, 130, 4), Color("607273"))
	draw_rect(Rect2(-62, -13, 124, 14), Color("87958b"))
	draw_rect(Rect2(-60, -11, 120, 9), Color("d3d4af"))
	for x in [-51.0, 0.0, 51.0]:
		draw_line(Vector2(x, -16), Vector2(x, 6), Color("38474a"), 3.0)
	draw_rect(Rect2(-67, 4, 134, 4), Color("1c292c"))
	draw_circle(Vector2(-63, -5), 2.0, Color("93a09a"))
	draw_circle(Vector2(63, -5), 2.0, Color("93a09a"))
