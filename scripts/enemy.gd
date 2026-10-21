extends CharacterBody2D
## One guard: finite perception, last known position, navigation and timed bursts.

signal health_changed(current: float, maximum: float)
signal damaged
signal state_changed(description: String)
signal died
signal moved(distance: float)

enum State { PATROL, INVESTIGATE, SEARCH, AIM, BURST, RELOAD, DEAD }

@export var target: CharacterBody2D
@export var patrol_start: Node2D
@export var patrol_end: Node2D
@export_range(1.0, 1000.0, 1.0) var max_health: float = 150.0
@export_range(20.0, 400.0, 5.0) var move_speed: float = 135.0
@export_range(50.0, 1200.0, 10.0) var sight_range: float = 640.0
@export_range(30.0, 360.0, 5.0) var field_of_view: float = 150.0
@export_range(50.0, 1200.0, 10.0) var hearing_range: float = 750.0
@export_range(50.0, 800.0, 10.0) var preferred_distance: float = 560.0
@export_range(0.2, 4.0, 0.05) var aim_duration: float = 0.7
@export_range(1, 12, 1) var burst_size: int = 4
@export_range(0.0, 240.0, 5.0) var reload_reposition_distance: float = 110.0
@export_range(1.0, 20.0, 0.5) var memory_duration: float = 6.0
@export_range(0.5, 10.0, 0.5) var search_duration: float = 3.0
@export_group("Turning and Attack Memory")
@export_range(90.0, 1440.0, 30.0, "suffix:deg/s") var turn_speed: float = 540.0
@export_range(1.0, 15.0, 1.0, "suffix:deg") var aim_tolerance: float = 6.0
@export_range(5.0, 60.0, 1.0, "suffix:deg") var prepared_angle: float = 18.0
@export_range(0.3, 3.0, 0.05, "suffix:s") var preparation_memory: float = 1.25
@export_range(0.2, 3.0, 0.05, "suffix:s") var preparation_decay: float = 0.7
@export_range(0.2, 1.5, 0.05, "suffix:s") var movement_commitment: float = 0.65

var health: float = 100.0
var is_dead: bool = false
var behavior_enabled: bool = true
var state: State = State.PATROL
var last_known_position: Vector2 = Vector2.ZERO
var _state_time: float = 0.0
var _memory_time: float = 0.0
var _shots_left: int = 0
var _burst_direction: Vector2 = Vector2.LEFT
var _patrol_index: int = 0
var _repath_time: float = 0.0
var _has_destination: bool = false
var _sees_target: bool = false
var _warning_end: Vector2 = Vector2.ZERO
var _reload_destination: Vector2 = Vector2.ZERO
var _reload_side: float = 1.0
var _desired_angle: float = 0.0
var _preparation: float = 0.0
var _prepared_position: Vector2 = Vector2.ZERO
var _time_without_sight: float = 100.0
var _movement_time: float = 0.0
var _investigation_destination: Vector2 = Vector2.ZERO

@onready var aim: Node2D = $Aim
@onready var weapon: Node2D = $Aim/Weapon
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var caption: Label = $Caption


func _ready() -> void:
	add_to_group("guards")
	health = max_health
	_desired_angle = aim.global_rotation
	_update_caption()


func can_see_target() -> bool:
	if not is_instance_valid(target) or target.is_dead or is_dead:
		return false
	var offset := target.global_position - global_position
	if offset.length() > sight_range:
		return false
	if offset.length() > 1.0:
		var facing := Vector2.RIGHT.rotated(aim.global_rotation)
		if facing.dot(offset.normalized()) < cos(deg_to_rad(field_of_view * 0.5)):
			return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 7, [get_rid()])
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == target


func hear_shot(origin: Vector2) -> void:
	if is_dead or not behavior_enabled or global_position.distance_to(origin) > hearing_range:
		return
	if state in [State.PATROL, State.INVESTIGATE, State.SEARCH] and not _sees_target:
		last_known_position = origin
		_memory_time = memory_duration
		_change_state(State.INVESTIGATE)


func set_behavior_enabled(active: bool) -> void:
	behavior_enabled = active
	# Freeze AI, weapon timers and spatial audio together; SceneTree pause stays with PauseMenu.
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	velocity = Vector2.ZERO
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_dead or not is_instance_valid(target) or target.is_dead:
		velocity = Vector2.ZERO
		return
	velocity = Vector2.ZERO
	_repath_time -= delta
	if state != State.AIM:
		_state_time -= delta
	_memory_time -= delta
	_movement_time = maxf(0.0, _movement_time - delta)
	_sees_target = can_see_target()
	if _sees_target:
		last_known_position = target.global_position
		_memory_time = memory_duration
		_time_without_sight = 0.0
	else:
		_time_without_sight += delta
	if _time_without_sight > preparation_memory:
		_preparation = maxf(0.0, _preparation - delta / preparation_decay)
	match state:
		State.PATROL:
			if _sees_target:
				_engage()
			else:
				_patrol()
		State.INVESTIGATE:
			if _sees_target and _movement_time <= 0.0 and global_position.distance_to(last_known_position) <= preferred_distance:
				_engage()
			elif not _sees_target and (global_position.distance_to(last_known_position) < 22.0 or _memory_time <= 0.0):
				_change_state(State.SEARCH)
			else:
				if _movement_time <= 0.0:
					_investigation_destination = last_known_position
					_movement_time = movement_commitment
				_move_to(_investigation_destination)
				if _sees_target:
					_face(last_known_position)
		State.SEARCH:
			if _sees_target:
				_engage()
			elif _state_time <= 0.0:
				_change_state(State.PATROL)
			else:
				_desired_angle = aim.global_rotation + delta * 1.6
		State.AIM:
			if not _sees_target and _time_without_sight > preparation_memory:
				_change_state(State.INVESTIGATE)
			else:
				# Follow continuous visible movement. Compare successive observed
				# positions, not total travel since preparation began: circling must
				# not reset the windup on every accumulated angular threshold.
				if _sees_target:
					if _prepared_angle_difference() > deg_to_rad(prepared_angle):
						_preparation = 0.0
					_prepared_position = last_known_position
				_face(last_known_position)
		State.BURST:
			# Finish the committed burst along its fixed direction, even if the
			# player hid. The shared raycast still stops at solid cover.
			if _shots_left <= 0 or weapon.ammo <= 0:
				_change_state(State.RELOAD)
			elif weapon.try_fire(global_position + _burst_direction * weapon.max_range, self):
				_shots_left -= 1
		State.RELOAD:
			if not weapon.is_reloading:
				if _sees_target:
					_engage()
				else:
					_change_state(State.INVESTIGATE)
			else:
				# Brief peeks cannot cancel the already chosen change of angle.
				_move_to(_reload_destination)
				_face(last_known_position)
	aim.global_rotation = rotate_toward(aim.global_rotation, _desired_angle, deg_to_rad(turn_speed) * delta)
	# Judge alignment after this frame's bounded turn, so a close moving target
	# cannot stall preparation through a permanent one-frame aiming lag.
	if state == State.AIM:
		if absf(angle_difference(aim.global_rotation, _desired_angle)) <= deg_to_rad(aim_tolerance):
			_preparation = minf(1.0, _preparation + delta / aim_duration)
		_state_time = aim_duration * (1.0 - _preparation)
		if _state_time <= 0.0:
			_change_state(State.RELOAD if weapon.ammo <= 0 else State.BURST)
	move_and_slide()
	moved.emit(get_position_delta().length())
	if state == State.AIM:
		var direction := Vector2.RIGHT.rotated(aim.global_rotation)
		_warning_end = global_position + direction * weapon.max_range
		var query := PhysicsRayQueryParameters2D.create(global_position, _warning_end, 7, [get_rid()])
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_warning_end = hit["position"]
	_update_caption()
	queue_redraw()


func _engage() -> void:
	if global_position.distance_to(last_known_position) > preferred_distance:
		_change_state(State.INVESTIGATE)
		_move_to(last_known_position)
	else:
		_change_state(State.AIM)
		_face(last_known_position)


func _face(point: Vector2) -> void:
	if global_position.distance_squared_to(point) > 1.0:
		_desired_angle = global_position.direction_to(point).angle()


func _prepared_angle_difference() -> float:
	return absf(global_position.direction_to(_prepared_position).angle_to(global_position.direction_to(last_known_position)))


func _patrol() -> void:
	var point := patrol_start if _patrol_index == 0 else patrol_end
	if not is_instance_valid(point):
		return
	if global_position.distance_to(point.global_position) < 16.0:
		_patrol_index = 1 - _patrol_index
	else:
		_move_to(point.global_position)


func _move_to(destination: Vector2) -> void:
	if NavigationServer2D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	if not _has_destination or agent.target_position.distance_to(destination) > 12.0 or _repath_time <= 0.0:
		agent.target_position = destination
		_has_destination = true
		_repath_time = 0.35
	var next := agent.get_next_path_position()
	if agent.is_navigation_finished():
		return
	velocity = global_position.direction_to(next) * move_speed
	if velocity.length_squared() > 1.0:
		_desired_angle = velocity.angle()


func _change_state(next: State) -> void:
	if state == next:
		return
	if state == State.AIM:
		$ReadyAudio.stop()
	state = next
	match state:
		State.AIM:
			if _prepared_angle_difference() > deg_to_rad(prepared_angle):
				_preparation = 0.0
			_prepared_position = last_known_position
			_state_time = aim_duration * (1.0 - _preparation)
			if behavior_enabled:
				$ReadyAudio.play()
		State.BURST:
			# Fire where the weapon actually points; never snap the body at firing.
			_burst_direction = Vector2.RIGHT.rotated(aim.global_rotation)
			_desired_angle = aim.global_rotation
			_shots_left = burst_size
		State.RELOAD:
			_preparation = 0.0
			weapon.request_reload()
			_reload_destination = global_position
			var map := agent.get_navigation_map()
			if reload_reposition_distance > 0.0 and NavigationServer2D.map_get_iteration_id(map) > 0:
				var lateral := global_position.direction_to(last_known_position).orthogonal()
				var candidate := global_position + lateral * reload_reposition_distance * _reload_side
				_reload_destination = NavigationServer2D.map_get_closest_point(map, candidate)
				_reload_side *= -1.0
		State.INVESTIGATE:
			_investigation_destination = last_known_position
			_movement_time = movement_commitment
		State.SEARCH:
			_state_time = search_duration
	_update_caption()
	state_changed.emit(get_state_description())


func get_state_description() -> String:
	match state:
		State.PATROL: return "ПАТРУЛЬ"
		State.INVESTIGATE: return "ПРОВЕРЯЕТ"
		State.SEARCH: return "ИЩЕТ"
		State.AIM: return "ЦЕЛИТСЯ"
		State.BURST: return "ОГОНЬ"
		State.RELOAD: return "ПЕРЕЗАРЯДКА"
		State.DEAD: return "НЕЙТРАЛИЗОВАН"
	return ""


func _update_caption() -> void:
	caption.text = get_state_description()
	caption.modulate = Color("f0b878") if state in [State.AIM, State.BURST] else Color("a8b5ae")


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	$Aim/BodyVisual.flash_hit()
	health_changed.emit(health, max_health)
	damaged.emit()
	if health > 0.0 and state == State.PATROL:
		# An impact raises suspicion without revealing the shooter's hidden position.
		_change_state(State.SEARCH)
	if health <= 0.0:
		is_dead = true
		velocity = Vector2.ZERO
		weapon.stop()
		$Aim/Weapon.hide()
		$Aim/BodyVisual.fallen = true
		set_deferred("collision_layer", 0)
		$CollisionShape2D.set_deferred("disabled", true)
		_change_state(State.DEAD)
		died.emit()
	queue_redraw()


func _draw() -> void:
	if is_dead or not behavior_enabled:
		return
	if state == State.AIM:
		var progress := _preparation
		draw_line(Vector2.ZERO, to_local(_warning_end), Color(0.95, 0.36, 0.23, 0.25 + progress * 0.55), 1.5, true)
		draw_arc(Vector2.ZERO, 25.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, Color("efb37b"), 2.0, true)
