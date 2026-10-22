extends SceneTree
## Real physics integration: magazine, health, perception, burst timing and paths.

const YARD = preload("res://tests/fixtures/system_yard.tscn")
const OBSTACLE = preload("res://tests/fixtures/cover.tscn")
var _checks: int = 0
var _failures: int = 0
var _yard: Node2D
var _player: CharacterBody2D
var _enemy: CharacterBody2D
var _weapon: Node2D
var _async_navigation: bool = "--async-navigation" in OS.get_cmdline_user_args()


func _initialize() -> void:
	# Fixed-FPS tests run much faster than wall time. Synchronous map iterations
	# make immediate path assertions deterministic without changing gameplay code.
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
	_enemy = _yard.get_node("Enemy")
	_weapon = _player.get_node("Aim/Weapon")
	await _ticks(4)


func _duel_positions() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector2(1170, 440)
	_enemy.global_position = Vector2(1340, 440)
	_enemy.get_node("Aim").global_rotation = PI
	_enemy.patrol_start = null
	_enemy.patrol_end = null


func _path_length(path: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func _run() -> void:
	await _fresh()
	_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	_check(_weapon.ammo == 12 and _weapon.magazine_size == 12, "Player spawns with a loaded 12-round magazine")
	_check(not _weapon.request_reload(), "Full magazine cannot start reload")
	for shot in range(12):
		_check(_weapon.try_fire(Vector2(900, 565), _player), "Magazine shot %d fires" % (shot + 1))
		await _ticks(ceili(60.0 / _weapon.fire_rate) + 1)
	_check(_weapon.ammo == 0, "Every successful shot consumes one round")
	_check(not _weapon.try_fire(Vector2(900, 565), _player), "Empty magazine blocks firing")
	await _ticks(20)
	_check(_weapon.ammo == 0, "Empty magazine does not refill automatically")
	_check(_player.get_node("AmmoFeedback/Readout").text == "0 / 12", "Local ammo readout reflects empty magazine")
	Input.action_press("reload")
	await _ticks(1)
	Input.action_release("reload")
	_check(_weapon.is_reloading, "R action starts reload through player input")
	_check(not _weapon.request_reload(), "Repeated reload cannot restart its timer")
	_check(not _weapon.try_fire(Vector2(900, 565), _player), "Cannot fire during reload")
	await _ticks(30)
	_check(_weapon.ammo == 0 and _weapon.is_reloading, "Magazine stays empty until reload completes")
	_check(_yard.get_node("HUD/AimCursor").is_reload_active, "Reload indicator is active at aiming cursor")
	_check(_yard.get_node("HUD/AimCursor").reload_progress > 0.2 and _yard.get_node("HUD/AimCursor").reload_progress < 0.8, "Cursor ring follows actual reload progress")
	await _ticks(65)
	_check(_weapon.ammo == 12 and not _weapon.is_reloading, "Reload completes after configured duration")
	_check(_player.get_node("AmmoFeedback/Readout").text == "12 / 12", "Local ammo readout reflects completed reload")
	_check(not _yard.get_node("HUD/AimCursor").is_reload_active, "Reload ring hides on completion")
	_player.take_damage(-10.0)
	_check(_player.health == 100.0, "Non-positive damage does not heal or hurt")
	_player.take_damage(14.0)
	_check(_player.health == 86.0, "Player receives damage")
	_check(_player.get_node("HealthBar").current_health == 86.0, "Overhead bar reflects player health immediately")
	_weapon.try_fire(Vector2(900, 565), _player)
	_weapon.request_reload()
	_player.take_damage(1000.0)
	await _ticks(1)
	_check(_player.is_dead and _player.health == 0.0, "Lethal damage kills player")
	_check(not _weapon.enabled and not _weapon.is_reloading, "Death stops weapon and cancels reload")
	_check(_yard.get_node("HUD/DeathScreen").visible, "Death presents restart screen")
	_check(not _yard.get_node("HUD/AimCursor").is_reload_active, "Death hides reload ring")
	var death_position := _player.global_position
	Input.action_press("move_right")
	Input.action_press("shoot")
	Input.action_press("reload")
	await _ticks(15)
	Input.action_release("move_right")
	Input.action_release("shoot")
	Input.action_release("reload")
	_check(_player.global_position.is_equal_approx(death_position), "Dead player cannot move")
	_check(not _weapon.try_fire(Vector2(900, 565), _player), "Dead player cannot shoot")
	_player.take_damage(20.0)
	_check(_player.health == 0.0, "Further damage cannot change death state")
	var restart := InputEventAction.new()
	restart.action = "restart"
	restart.pressed = true
	root.push_input(restart)
	await _ticks(4)
	_yard = current_scene
	_check(_yard.get_node("Player").health == 10.0 and _yard.get_node("Player/Aim/Weapon").ammo == 12, "Enter restores audio-test starting health and full magazine")
	_check(not _yard.get_node("Enemy").is_dead, "Enter restores guard")

	await _fresh()
	_duel_positions()
	_enemy.set_physics_process(false)
	await _ticks(2)
	_check(_enemy.can_see_target(), "Guard sees unobstructed player in front")
	_player.global_position = Vector2(1440, 440)
	await _ticks(2)
	_check(not _enemy.can_see_target(), "Guard cannot see behind its field of view")
	_player.global_position = Vector2(650, 440)
	await _ticks(2)
	_check(not _enemy.can_see_target(), "Guard sight has limited range")
	_player.global_position = Vector2(1170, 440)
	var cover := OBSTACLE.instantiate()
	cover.position = Vector2(1240, 440)
	cover.size = Vector2(30, 100)
	_yard.add_child(cover)
	await _ticks(2)
	_check(not _enemy.can_see_target(), "Wall blocks guard vision")
	_enemy.get_node("Aim/Weapon").try_fire(_player.global_position, _enemy)
	_check(_player.health == 100.0, "Wall also blocks enemy bullets")
	cover.queue_free()
	await _ticks(2)
	_check(_enemy.can_see_target(), "Removing cover restores vision")
	for shot in range(ceili(_enemy.max_health / _weapon.damage)):
		_weapon.try_fire(_enemy.global_position, _player)
		if shot == 0:
			_check(_enemy.health == _enemy.max_health - _weapon.damage, "Player bullets damage guard through enemy collision layer")
		await _ticks(ceili(60.0 / _weapon.fire_rate) + 1)
	_check(_enemy.is_dead and _enemy.health == 0.0, "Accurate hits kill guard according to live damage and health")
	_check(_enemy.collision_layer == 0 and _enemy.get_node("CollisionShape2D").disabled, "Guard corpse has no collision")
	_check(not _enemy.get_node("Aim/Weapon").enabled, "Dead guard cannot fire")
	_check(_yard.get_node("HUD/PauseMenu/DeveloperPanel").content.get_node("Count").text.ends_with("живы: 0"), "Guard death updates developer count without a gameplay victory banner")

	await _fresh()
	_duel_positions()
	await _ticks(2)
	_check(_enemy.state == _enemy.State.AIM, "Detection starts a telegraphed aiming phase")
	await _ticks(floori(_enemy.aim_duration * 60.0) - 6)
	_check(_player.health == 100.0 and _enemy.state == _enemy.State.AIM, "Guard gives reaction time before first hitscan shot")
	await _ticks(ceili(_enemy.burst_size / _enemy.weapon.fire_rate * 60.0) + 10)
	_check(_player.health == _player.max_health - _enemy.burst_size * _enemy.weapon.damage, "Full burst deals configured damage on each hit")
	_check(_enemy.state == _enemy.State.RELOAD and _enemy.get_node("Aim/Weapon").is_reloading, "Burst ends with enemy reload")
	var health_after_burst: float = _player.health
	await _ticks(floori(_enemy.weapon.reload_duration * 30.0))
	_check(_player.health == health_after_burst, "Enemy reload leaves a safe attack window")

	await _fresh()
	_duel_positions()
	await _ticks(2)
	var remembered := _player.global_position
	_player.global_position = Vector2(650, 565)
	await _ticks(2)
	_check(_enemy.state == _enemy.State.AIM, "Brief sight loss preserves preparation for the last observed angle")
	_check(_enemy.last_known_position.is_equal_approx(remembered), "Guard remembers last visible position, not hidden player position")
	var search_wait := 0
	while _enemy.state != _enemy.State.SEARCH and search_wait < 420:
		await _ticks(1)
		search_wait += 1
	_check(_enemy.state == _enemy.State.SEARCH, "After committed fire and reload, guard investigates remembered position and searches")
	_check(_player.health == 100.0, "Guard cannot shoot hidden player through cover")
	await _ticks(190)
	_check(_enemy.state == _enemy.State.PATROL, "Unsuccessful search returns to patrol")

	await _fresh()
	_player.set_physics_process(false)
	_enemy.patrol_start = null
	_enemy.patrol_end = null
	_enemy.global_position = Vector2(1340, 440)
	_enemy.get_node("Aim").global_rotation = PI
	await _ticks(2)
	_check(not _enemy.can_see_target(), "Starting cover conceals player")
	var guard_start := _enemy.global_position
	_weapon.try_fire(Vector2(1200, 565), _player)
	await _ticks(2)
	_check(_enemy.state == _enemy.State.INVESTIGATE, "Unseen player shot attracts guard")
	_check(_enemy.last_known_position.distance_to(_player.global_position) < 40.0, "Guard investigates shot origin")
	await _ticks(90)
	_check(_enemy.global_position.distance_to(guard_start) > 80.0, "Investigation moves guard along navigation path")

	# Query real navigation around the central cover, then move it as in editor.
	_enemy.set_physics_process(false)
	var map := _yard.get_world_2d().navigation_map
	var before := NavigationServer2D.map_get_path(map, Vector2(900, 535), Vector2(1100, 535), true)
	_check(before.size() >= 3 and _path_length(before) > 280.0, "Navigation routes around central cover")
	_yard.get_node("Obstacles/CombatCover").position = Vector2(990, 250)
	await _ticks(2) # Allow the moved StaticBody2D transform to reach PhysicsServer2D.
	_yard.get_node("Navigation").rebuild()
	await _ticks(3)
	var after := NavigationServer2D.map_get_path(map, Vector2(900, 535), Vector2(1100, 535), true)
	_check(after.size() >= 2 and _path_length(after) < 205.0, "Navigation rebake honors moved scene obstacle")
	_check(_yard.get_node("Obstacles/WestCrate").position == Vector2(360, 360), "Navigation does not rewrite map objects")
	var around_target := NavigationServer2D.map_get_path(map, Vector2(1120, 540), Vector2(1260, 540), true)
	_check(_path_length(around_target) > 160.0, "Stationary target is also a navigation obstacle")
	_yard.get_node("Target").take_damage(1000.0)
	await _ticks(4)
	var through_wreck := NavigationServer2D.map_get_path(map, Vector2(1120, 540), Vector2(1260, 540), true)
	_check(through_wreck.size() >= 2 and _path_length(through_wreck) < 145.0, "Target destruction opens its navigation space")
	_enemy.state = _enemy.State.PATROL
	_enemy.take_damage(1.0)
	_check(_enemy.state == _enemy.State.SEARCH, "An unseen impact makes a patrolling guard search")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
