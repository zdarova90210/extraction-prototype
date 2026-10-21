extends Node2D
## One physics ray per shot: nearest solid object stops both damage and tracer.

signal shot_fired(from: Vector2, to: Vector2, hit: bool)
signal hit_registered(point: Vector2, collider: Object)
signal ammo_changed(loaded: int, capacity: int)
signal reload_changed(active: bool)
signal empty_triggered
signal active_reload_resolved(success: bool)

enum ReloadTiming { INACTIVE, AVAILABLE, SUCCESS, MISSED }

const SHOT_EFFECT = preload("res://scripts/shot_effect.gd")

@export var display_name: String = "Карабин"
@export_range(1.0, 500.0, 1.0) var damage: float = 25.0
@export_range(0.5, 30.0, 0.5, "suffix:shots/s") var fire_rate: float = 6.0
@export_range(50.0, 2400.0, 10.0, "suffix:px") var max_range: float = 1000.0
@export_range(1, 100, 1) var magazine_size: int = 12
@export_range(0.1, 10.0, 0.1, "suffix:s") var reload_duration: float = 1.5
@export_flags_2d_physics var hit_mask: int = 1 | 4 | 8
@export var tracer_color: Color = Color(1.0, 0.86, 0.56)
@export_range(0.2, 2.0, 0.05, "suffix:s") var empty_feedback_interval: float = 0.5
@export_group("Active Reload")
@export var active_reload_enabled: bool = false
@export var active_window_start_range: Vector2 = Vector2(0.2, 0.55)
@export_range(0.02, 0.25, 0.005) var active_window_width: float = 0.075
@export_range(1.05, 2.0, 0.05) var active_reload_speed: float = 1.5

var ammo: int = 0
var is_reloading: bool = false
var enabled: bool = true
var reload_timing: ReloadTiming = ReloadTiming.INACTIVE
var active_window_start: float = 0.0
var active_window_end: float = 0.0
var reload_progress: float:
	get:
		return 1.0 - _reload_remaining / reload_duration if is_reloading else 0.0

var _cooldown: float = 0.0
var _flash_time: float = 0.0
var _reload_remaining: float = 0.0
var _empty_feedback_cooldown: float = 0.0
var _reload_rng := RandomNumberGenerator.new()

@onready var muzzle: Marker2D = $Muzzle


func _ready() -> void:
	_reload_rng.randomize()
	ammo = magazine_size
	ammo_changed.emit(ammo, magazine_size)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_empty_feedback_cooldown = maxf(0.0, _empty_feedback_cooldown - delta)
	if is_reloading:
		var speed := active_reload_speed if reload_timing == ReloadTiming.SUCCESS else 1.0
		_reload_remaining = maxf(0.0, _reload_remaining - delta * speed)
		if _reload_remaining <= 0.0:
			is_reloading = false
			reload_timing = ReloadTiming.INACTIVE
			ammo = magazine_size
			ammo_changed.emit(ammo, magazine_size)
			reload_changed.emit(false)
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		queue_redraw()


func try_fire(aim_position: Vector2, shooter: CollisionObject2D) -> bool:
	if not enabled or is_reloading or _cooldown > 0.00001:
		return false
	if ammo <= 0:
		if _empty_feedback_cooldown <= 0.00001:
			_empty_feedback_cooldown = empty_feedback_interval
			empty_triggered.emit()
		return false
	var origin := shooter.global_position
	var direction := origin.direction_to(aim_position)
	if direction.is_zero_approx():
		return false
	_cooldown = 1.0 / maxf(fire_rate, 0.5)
	ammo -= 1
	ammo_changed.emit(ammo, magazine_size)
	_flash_time = 0.055
	queue_redraw()
	var endpoint := origin + direction * max_range
	# Start at body center, not the muzzle: a barrel touching/poking into a wall
	# must never allow shots through it. Also detect origins inside solid shapes.
	var query := PhysicsRayQueryParameters2D.create(origin, endpoint, hit_mask, [shooter.get_rid()])
	query.hit_from_inside = true
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		endpoint = result["position"]
		var collider: Object = result["collider"]
		# Notify presentation before damage can disable/free the struck body.
		hit_registered.emit(endpoint, collider)
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
	var muzzle_distance := origin.distance_to(muzzle.global_position)
	var start := origin + direction * minf(muzzle_distance, origin.distance_to(endpoint))
	var effect := Node2D.new()
	effect.set_script(SHOT_EFFECT)
	get_tree().current_scene.add_child(effect)
	effect.setup(start, endpoint, not result.is_empty(), tracer_color)
	shot_fired.emit(start, endpoint, not result.is_empty())
	return true


func request_reload() -> bool:
	if not enabled or is_reloading or ammo >= magazine_size:
		return false
	is_reloading = true
	_reload_remaining = reload_duration
	reload_timing = ReloadTiming.INACTIVE
	if active_reload_enabled:
		var width := clampf(active_window_width, 0.02, 0.25)
		var first := clampf(minf(active_window_start_range.x, active_window_start_range.y), 0.1, 0.9 - width)
		var last := clampf(maxf(active_window_start_range.x, active_window_start_range.y), first, 0.9 - width)
		active_window_start = _reload_rng.randf_range(first, last)
		active_window_end = active_window_start + width
		reload_timing = ReloadTiming.AVAILABLE
	reload_changed.emit(true)
	return true


func try_active_reload() -> bool:
	if not enabled or not is_reloading or reload_timing != ReloadTiming.AVAILABLE:
		return false
	# Exactly one attempt; a miss does not change the baseline reload duration.
	var success := reload_progress >= active_window_start and reload_progress <= active_window_end
	reload_timing = ReloadTiming.SUCCESS if success else ReloadTiming.MISSED
	active_reload_resolved.emit(success)
	return success


func stop() -> void:
	enabled = false
	is_reloading = false
	reload_timing = ReloadTiming.INACTIVE
	_reload_remaining = 0.0
	_flash_time = 0.0
	reload_changed.emit(false)
	queue_redraw()


func restore_state() -> void:
	# Reset runtime state for a new training attempt without replacing the actor.
	stop()
	enabled = true
	_cooldown = 0.0
	_empty_feedback_cooldown = 0.0
	ammo = magazine_size
	ammo_changed.emit(ammo, magazine_size)


func _draw() -> void:
	if _flash_time > 0.0:
		draw_colored_polygon(PackedVector2Array([
			Vector2(29, -5), Vector2(46, 0), Vector2(29, 5), Vector2(34, 0)
		]), Color(1.0, 0.79, 0.40, 0.9))
