extends SceneTree
## Live scenes: open duels, range, movement and reload pressure.

const YARD = preload("res://scenes/test_yard.tscn")
var _checks: int = 0
var _failures: int = 0
var _yard: Node2D
var _player: CharacterBody2D
var _enemy: CharacterBody2D
var _weapon: Node2D
var _async_navigation: bool = "--async-navigation" in OS.get_cmdline_user_args()


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


func _fresh() -> void:
	Input.action_release("move_right")
	if is_instance_valid(_yard):
		_yard.queue_free()
		await _ticks(2)
	_yard = YARD.instantiate()
	if not _async_navigation:
		NavigationServer2D.region_set_use_async_iterations(_yard.get_node("Navigation").get_rid(), false)
	root.add_child(_yard)
	current_scene = _yard
	_player = _yard.get_node("Player")
	_enemy = _yard.get_node("Enemy")
	_weapon = _player.get_node("Aim/Weapon")
	_player.set_physics_process(false)
	_enemy.patrol_start = null
	_enemy.patrol_end = null
	# An unobstructed lane within the saved yard; do not alter map geometry.
	_player.global_position = Vector2(1340, 650)
	_enemy.global_position = Vector2(1340, 440)
	_enemy.get_node("Aim").global_rotation = PI * 0.5
	await _ticks(4)


func _shoot_duel() -> Dictionary:
	var shots := 0
	var elapsed := 0
	while not _enemy.is_dead and not _player.is_dead and elapsed < 360:
		# Perfect tracking deliberately gives the player the strongest open duel.
		if _weapon.try_fire(_enemy.global_position, _player):
			shots += 1
		await _ticks(1)
		elapsed += 1
	return {"shots": shots, "seconds": elapsed / 60.0, "health": _player.health}


func _run() -> void:
	await _fresh()
	# Historical fixture: demonstrate the reported no-risk kill with old tuning.
	_weapon.damage = 25.0
	_weapon.fire_rate = 6.0
	_weapon.max_range = 1000.0
	_enemy.max_health = 100.0
	_enemy.health = 100.0
	_enemy.health_changed.emit(100.0, 100.0)
	_enemy.aim_duration = 0.9
	_enemy._state_time = 0.9
	_enemy.burst_size = 3
	_enemy.reload_reposition_distance = 0.0
	_enemy.weapon.damage = 14.0
	_enemy.weapon.magazine_size = 3
	_enemy.weapon.ammo = 3
	_enemy.weapon.reload_duration = 2.2
	var before := await _shoot_duel()
	_check(_enemy.is_dead and before.shots == 4 and before.health == 100.0, "Old tuning kills guard before any return fire")

	await _fresh()
	var after := await _shoot_duel()
	_check(_enemy.is_dead and not _player.is_dead and after.shots == 8, "Accurate starting weapon still wins an open duel in eight hits")
	_check(after.seconds > before.seconds * 3.0, "Open kill takes materially longer than old half-second burst")
	_check(after.health > 0.0 and after.health <= 30.0, "Even perfect stationary aim now costs most player health")
	print("DUEL: old %.2fs / %.0f HP, current %.2fs / %.0f HP" % [before.seconds, before.health, after.seconds, after.health])
	_check(ceili(_enemy.weapon.reload_duration * _weapon.fire_rate) * _weapon.damage < _enemy.max_health, "One enemy reload window cannot erase a fresh guard")

	await _fresh()
	# The guard can engage just beyond the player's shortened range.
	_player.global_position = Vector2(1340, 990)
	_enemy.set_physics_process(false)
	await _ticks(2)
	_check(_weapon.try_fire(_enemy.global_position, _player) and _enemy.health == _enemy.max_health, "Player ray no longer damages a guard 550 px away")
	_enemy._change_state(_enemy.State.PATROL)
	_enemy.set_physics_process(true)
	await _ticks(3)
	_check(_enemy.state == _enemy.State.AIM, "Guard prepares fire at 550 px rather than walking into player range")
	await _ticks(85)
	_check(_player.health < _player.max_health, "Guard range advantage produces real hits through the open lane")

	await _fresh()
	var elapsed := 0
	while not _player.is_dead and elapsed < 300:
		await _ticks(1)
		elapsed += 1
	_check(_player.is_dead and elapsed > 60 and elapsed < 300, "Standing in the open without responding is lethal within five seconds")

	await _fresh()
	elapsed = 0
	while _player.health == _player.max_health and elapsed < 120:
		await _ticks(1)
		elapsed += 1
	_check(_player.health == _player.max_health - _enemy.weapon.damage, "First hitscan shot lands after readable preparation")
	var health_after_first: float = _player.health
	var burst_direction: Vector2 = _enemy._burst_direction
	var start := _player.global_position
	Input.action_press("move_right")
	_player.set_physics_process(true)
	await _ticks(27)
	Input.action_release("move_right")
	_player.set_physics_process(false)
	await _ticks(20)
	_check(_player.global_position.x > start.x + 90.0, "Real movement input strafes out of the firing lane")
	_check(_player.health == health_after_first, "Strafing after first hit avoids all later shots of the fixed burst")
	_check(_enemy._burst_direction.is_equal_approx(burst_direction), "Burst direction stays fixed instead of tracking the moving player")
	_check(_enemy.state == _enemy.State.RELOAD, "Missed burst still consumes ammunition and opens reload window")
	var reload_start := _enemy.global_position
	var ammo_during_reload: int = _enemy.weapon.ammo
	await _ticks(30)
	_check(_enemy.global_position.distance_to(reload_start) > 45.0, "Guard navigates to a new angle while reloading")
	_check(_enemy.weapon.ammo == ammo_during_reload and _player.health == health_after_first, "Reload movement neither fires nor refills early")

	await _fresh()
	_player.global_position = Vector2(650, 565)
	_enemy.last_known_position = Vector2(1170, 440)
	_enemy.get_node("Aim").global_rotation = PI
	_enemy.weapon.ammo = 0
	_enemy._change_state(_enemy.State.RELOAD)
	var remembered: Vector2 = _enemy.last_known_position
	var investigation_start := _enemy.global_position
	await _ticks(30)
	_check(_enemy.last_known_position.is_equal_approx(remembered), "Reloading guard cannot learn the hidden player's new position")
	_check(_enemy.agent.target_position.is_equal_approx(_enemy._reload_destination) and _enemy.global_position.distance_to(investigation_start) > 45.0, "On lost sight, reload movement keeps its chosen angle without tracking hidden player")
	_check(_player.health == _player.max_health, "Hidden player takes no damage during reload pursuit")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
