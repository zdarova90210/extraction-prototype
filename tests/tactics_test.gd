extends SceneTree
## Real perception and physics: repeated peeks, committed fire and finite turning.

const YARD = preload("res://scenes/test_yard.tscn")
const COVER = preload("res://scenes/obstacle.tscn")
var _checks: int = 0
var _failures: int = 0
var _yard: Node2D
var _player: CharacterBody2D
var _guard: CharacterBody2D
var _async_navigation: bool = "--async-navigation" in OS.get_cmdline_user_args()
var _shot_endpoints: Array[Vector2] = []


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
	_player.global_position = Vector2(1170, 440)
	_guard.global_position = Vector2(1340, 440)
	_guard.get_node("Aim").global_rotation = PI
	_guard._desired_angle = PI
	_shot_endpoints.clear()
	_guard.weapon.shot_fired.connect(func(_from: Vector2, to: Vector2, _hit: bool): _shot_endpoints.append(to))
	await _ticks(4)


func _run() -> void:
	await _fresh()
	_guard.set_physics_process(true)
	await _ticks(25)
	var prepared: float = _guard._preparation
	_player.global_position = Vector2(1280, 610) # About 71 degrees away, inside FOV.
	var angle_before: float = _guard.aim.global_rotation
	await _ticks(2) # Teleported collision reaches PhysicsServer before perception.
	var step := absf(angle_difference(angle_before, _guard.aim.global_rotation))
	_check(step > 0.01 and step <= deg_to_rad(_guard.turn_speed) / 30.0 + 0.001, "Detection turns by bounded visible steps rather than snapping")
	_check(prepared > 0.4 and _guard._preparation < 0.05, "A substantially different angle loses previous preparation")
	var bounded := true
	for tick in range(25):
		angle_before = _guard.aim.global_rotation
		await _ticks(1)
		bounded = bounded and absf(angle_difference(angle_before, _guard.aim.global_rotation)) <= deg_to_rad(_guard.turn_speed) / 60.0 + 0.001
	_check(bounded and absf(angle_difference(_guard.aim.global_rotation, _guard.global_position.direction_to(_player.global_position).angle())) < 0.01, "Turn reaches target smoothly and always obeys exported speed")
	_check(_guard.weapon.ammo == _guard.weapon.magazine_size and _player.health == 100.0, "New-angle attack waits for turning and renewed preparation")
	await _ticks(35)
	_check(_player.health < 100.0, "Guard can fire normally after turning and preparing")

	await _fresh()
	var cover := COVER.instantiate() as StaticBody2D
	cover.position = Vector2(1240, 440)
	cover.size = Vector2(30, 100)
	_yard.add_child(cover)
	_player.global_position = Vector2(1170, 300)
	_guard.aim.global_rotation = _guard.global_position.direction_to(_player.global_position).angle()
	_guard._desired_angle = _guard.aim.global_rotation
	await _ticks(2)
	_guard.set_physics_process(true)
	await _ticks(20)
	prepared = _guard._preparation
	var observed: Vector2 = _guard.last_known_position
	_player.global_position = Vector2(1170, 440)
	await _ticks(10)
	_check(not _guard.can_see_target() and _guard.state == _guard.State.AIM, "Cover hides player without cancelling an already prepared attack")
	_check(_guard._preparation > prepared and _guard.last_known_position == observed, "Brief hiding preserves preparation and reveals no hidden position")
	_player.global_position = Vector2(1170, 300)
	await _ticks(16)
	_check(_player.health < 100.0, "Returning to same corner meets fire before a fresh full preparation window")

	await _fresh()
	_guard.set_physics_process(true)
	await _ticks(20)
	observed = _guard.last_known_position
	cover = COVER.instantiate() as StaticBody2D
	cover.position = Vector2(1240, 440)
	cover.size = Vector2(30, 100)
	_yard.add_child(cover)
	_player.global_position = Vector2(1170, 470)
	await _ticks(75)
	_check(_shot_endpoints.size() == _guard.burst_size and _guard.weapon.ammo == 0, "Guard completes and spends a burst even when player remains hidden")
	var stopped := not _shot_endpoints.is_empty()
	for endpoint in _shot_endpoints:
		stopped = stopped and absf(endpoint.x - 1255.0) < 1.0
	_check(stopped and _player.health == 100.0, "Every committed ray stops at real cover instead of damaging hidden player")
	_check(_guard.last_known_position == observed, "Committed attack never tracks the hidden player's actual position")
	_check(_guard.state == _guard.State.RELOAD, "Baiting fire still opens a genuine enemy reload window")
	var chosen: Vector2 = _guard._reload_destination
	_player.global_position = Vector2(1170, 300)
	await _ticks(3)
	_player.global_position = Vector2(1170, 470)
	await _ticks(3)
	_check(_guard._reload_destination == chosen and _guard.agent.target_position == chosen, "Peeking does not cancel or replace the chosen reload movement")

	await _fresh()
	_player.global_position = Vector2(650, 565)
	_guard.last_known_position = Vector2(1170, 440)
	_guard._memory_time = _guard.memory_duration
	_guard._change_state(_guard.State.INVESTIGATE)
	_guard.set_physics_process(true)
	var start := _guard.global_position
	var stayed_moving := true
	for cycle in range(3):
		_player.global_position = Vector2(1170, 440)
		await _ticks(4)
		stayed_moving = stayed_moving and _guard.state == _guard.State.INVESTIGATE
		_player.global_position = Vector2(650, 565)
		await _ticks(4)
	_check(stayed_moving and _guard.global_position.distance_to(start) > 35.0, "Repeated glimpses cannot interrupt the committed investigation step")
	_player.global_position = Vector2(1170, 440)
	await _ticks(25)
	_check(_guard.state == _guard.State.AIM, "After finite movement commitment guard can stop and prepare an attack")

	await _fresh()
	_guard.turn_speed = 90.0 # A slower future archetype must also obey alignment.
	_player.global_position = Vector2(1280, 610)
	_guard.set_physics_process(true)
	await _ticks(2)
	_player.global_position = Vector2(650, 565)
	var timeout := 0
	while _guard.state == _guard.State.AIM and timeout < 120:
		await _ticks(1)
		timeout += 1
	_check(_guard.state == _guard.State.INVESTIGATE and _guard._preparation > 0.1, "Long sight loss ends unfinished preparation and starts investigation")
	await _ticks(60)
	_check(is_zero_approx(_guard._preparation) and _shot_endpoints.is_empty(), "Old readiness decays away and a slow guard never fires before alignment")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
