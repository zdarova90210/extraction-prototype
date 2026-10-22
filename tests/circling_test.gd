extends SceneTree
## Reproduce circular movement with real CharacterBody2D motion and perception.

const YARD = preload("res://tests/fixtures/system_yard.tscn")
const GUARD = preload("res://scenes/enemy.tscn")
var _checks: int = 0
var _failures: int = 0
var _yard: Node2D
var _player: CharacterBody2D
var _guard: CharacterBody2D
var _driver: OrbitDriver
var _shots: Array[int] = []
var _async_navigation: bool = "--async-navigation" in OS.get_cmdline_user_args()


class OrbitDriver extends Node:
	var player: CharacterBody2D
	var guard: CharacterBody2D
	var radius: float = 100.0
	var direction: float = 1.0
	var ticks: int = 0
	var moving_ticks: int = 0
	var bounded_turn: bool = true
	var last_angle: float = 0.0
	var saw_reload: bool = false

	func _physics_process(delta: float) -> void:
		var offset := player.global_position - guard.global_position
		var point := guard.global_position + offset.normalized().rotated(direction * player.move_speed / radius * delta) * radius
		var displacement := point - player.global_position
		player.velocity = displacement.limit_length(player.move_speed * delta) / delta
		var previous := player.global_position
		player.move_and_slide()
		if player.global_position.distance_to(previous) > player.move_speed * delta * 0.8:
			moving_ticks += 1
		ticks += 1
		bounded_turn = bounded_turn and absf(angle_difference(last_angle, guard.aim.global_rotation)) <= deg_to_rad(guard.turn_speed) * delta + 0.001
		last_angle = guard.aim.global_rotation
		saw_reload = saw_reload or guard.weapon.is_reloading


func _initialize() -> void:
	if not _async_navigation:
		NavigationServer2D.map_set_use_async_iterations(root.get_world_2d().navigation_map, false)
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _fresh(radius: float, direction: float = 1.0) -> void:
	if is_instance_valid(_yard):
		_yard.queue_free()
		await _ticks(2)
	_yard = YARD.instantiate()
	_yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	_yard.play_start_audio = false
	if not _async_navigation:
		NavigationServer2D.region_set_use_async_iterations(_yard.get_node("Navigation").get_rid(), false)
	root.add_child(_yard)
	current_scene = _yard
	_player = _yard.get_node("Player")
	_guard = _yard.get_node("Enemy")
	_player.set_physics_process(false)
	_guard.set_physics_process(false)
	_guard.patrol_start = null
	_guard.patrol_end = null
	_guard.global_position = Vector2(1850, 400) # Clear part of the saved yard.
	_player.global_position = _guard.global_position + Vector2(radius, 0)
	_guard.aim.global_rotation = 0.0
	_guard._desired_angle = 0.0
	_guard.reload_reposition_distance = 0.0
	# Keep long observations alive; attack timing and ballistic rules are real.
	_guard.weapon.damage = 1.0
	_driver = OrbitDriver.new()
	_driver.player = _player
	_driver.guard = _guard
	_driver.radius = radius
	_driver.direction = direction
	_driver.set_physics_process(false)
	_yard.add_child(_driver)
	_shots.clear()
	_guard.weapon.shot_fired.connect(func(_from: Vector2, _to: Vector2, _hit: bool): _shots.append(_driver.ticks))
	await _ticks(4)


func _start() -> void:
	_guard.set_physics_process(true)
	_driver.set_physics_process(true)


func _run() -> void:
	for radius in [35.0, 45.0, 100.0, 180.0]:
		await _fresh(radius, -1.0 if radius == 100.0 else 1.0)
		_start()
		await _ticks(250)
		_check(_driver.moving_ticks >= 245, "Player keeps moving at normal speed around radius %.0f" % radius)
		# Readiness pauses during real alignment/perception gaps near the body;
		# assert a bounded attack, rather than exact stationary-duel timing.
		_check(not _shots.is_empty() and _shots[0] <= 90, "Guard fires within 1.5 seconds against radius %.0f circling" % radius)
		_check(_shots.size() > _guard.burst_size and _driver.saw_reload, "Circling cannot block later bursts or reloads at radius %.0f" % radius)
		_check(_driver.bounded_turn, "Circling response preserves finite turn speed at radius %.0f" % radius)
		_check(_player.health < _player.max_health, "Moving player can actually be hit at radius %.0f" % radius)
		print("ORBIT: radius %.0f, first shot tick %d, shots %d" % [radius, _shots[0] if not _shots.is_empty() else -1, _shots.size()])

	await _fresh(100.0)
	_guard.reload_reposition_distance = 110.0
	_start()
	await _ticks(250)
	_check(_shots.size() > _guard.burst_size and _guard.global_position.distance_to(Vector2(1850, 400)) > 40.0, "Normal reload repositioning still allows attacks against circling")

	await _fresh(120.0)
	var other := GUARD.instantiate() as CharacterBody2D
	other.target = _player
	other.position = Vector2(1910, 400)
	other.get_node("Aim").rotation = 0.0
	# Weapon onready is not initialized until the scene enters the tree.
	other.get_node("Aim/Weapon").damage = 1.0
	other.reload_reposition_distance = 0.0
	_yard.add_child(other)
	var other_shots: Array[int] = []
	other.weapon.shot_fired.connect(func(_from: Vector2, _to: Vector2, _hit: bool): other_shots.append(_driver.ticks))
	_start()
	await _ticks(250)
	_check(_shots.size() > _guard.burst_size and other_shots.size() > other.burst_size, "Two nearby guards both complete repeated attacks against continuous movement")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
