extends Node2D
## One physics ray per shot: nearest solid object stops both damage and tracer.

signal shot_fired(from: Vector2, to: Vector2, hit: bool)

const SHOT_EFFECT = preload("res://scripts/shot_effect.gd")
const SHOT_MASK: int = 1 | 4 # World + Targets, excluding the Player layer.

@export_range(1.0, 500.0, 1.0) var damage: float = 25.0
@export_range(0.5, 30.0, 0.5, "suffix:shots/s") var fire_rate: float = 6.0
@export_range(50.0, 2400.0, 10.0, "suffix:px") var max_range: float = 1000.0

var _cooldown: float = 0.0
var _flash_time: float = 0.0

@onready var muzzle: Marker2D = $Muzzle


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		queue_redraw()


func try_fire(aim_position: Vector2, shooter: CollisionObject2D) -> bool:
	if _cooldown > 0.00001:
		return false
	var origin := shooter.global_position
	var direction := origin.direction_to(aim_position)
	if direction.is_zero_approx():
		return false
	_cooldown = 1.0 / maxf(fire_rate, 0.5)
	_flash_time = 0.055
	queue_redraw()
	var endpoint := origin + direction * max_range
	# Start at body center, not the muzzle: a barrel touching/poking into a wall
	# must never allow shots through it. Also detect origins inside solid shapes.
	var query := PhysicsRayQueryParameters2D.create(origin, endpoint, SHOT_MASK, [shooter.get_rid()])
	query.hit_from_inside = true
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		endpoint = result["position"]
		var collider: Object = result["collider"]
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
	var muzzle_distance := origin.distance_to(muzzle.global_position)
	var start := origin + direction * minf(muzzle_distance, origin.distance_to(endpoint))
	var effect := Node2D.new()
	effect.set_script(SHOT_EFFECT)
	get_tree().current_scene.add_child(effect)
	effect.setup(start, endpoint, not result.is_empty())
	shot_fired.emit(start, endpoint, not result.is_empty())
	return true


func _draw() -> void:
	if _flash_time > 0.0:
		draw_colored_polygon(PackedVector2Array([
			Vector2(29, -5), Vector2(46, 0), Vector2(29, 5), Vector2(34, 0)
		]), Color(1.0, 0.79, 0.40, 0.9))
