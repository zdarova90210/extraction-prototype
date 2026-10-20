extends SceneTree
## Integration checks in the real 2D physics world, without external packages.

const YARD = preload("res://scenes/test_yard.tscn")
const OBSTACLE = preload("res://scenes/obstacle.tscn")

var _failures: int = 0
var _checks: int = 0
var _shot_count: int = 0
var _last_endpoint: Vector2 = Vector2.ZERO


func _initialize() -> void:
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
		# physics_frame precedes node physics callbacks; inspect AFTER the tick.
		await process_frame


func _record_shot(_from: Vector2, endpoint: Vector2, _hit: bool) -> void:
	_shot_count += 1
	_last_endpoint = endpoint


func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/test_yard.tscn", "Main scene is the editable yard")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Compatibility renderer")
	for action in ["move_left", "move_right", "move_up", "move_down", "shoot", "reload", "restart"]:
		_check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Input binding: " + action)
	var yard := YARD.instantiate()
	root.add_child(yard)
	current_scene = yard
	# Isolate the original ballistics/movement regression fixture from the live duel.
	yard.get_node("Enemy").process_mode = Node.PROCESS_MODE_DISABLED
	yard.get_node("Obstacles/CombatCover").queue_free()
	var player: CharacterBody2D = yard.get_node("Player")
	var weapon: Node2D = player.get_node("Aim/Weapon")
	weapon.magazine_size = 100
	weapon.ammo = 100
	# Controlled values verify configurable ballistics independently of live balance.
	weapon.damage = 25.0
	weapon.fire_rate = 6.0
	weapon.max_range = 1000.0
	var target: StaticBody2D = yard.get_node("Target")
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	weapon.shot_fired.connect(_record_shot)
	await _ticks(3)
	_check(is_equal_approx(target.health, target.max_health), "Target initializes from Inspector health")

	# Measure actual displacement, including the same physics loop as gameplay.
	var start := Vector2(250, 650)
	player.global_position = start
	Input.action_press("move_right")
	await _ticks(60)
	Input.action_release("move_right")
	var straight_distance := player.global_position.distance_to(start)
	_check(absf(straight_distance - player.move_speed) < 5.0, "WASD movement uses exported speed")
	player.global_position = start
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _ticks(60)
	Input.action_release("move_right")
	Input.action_release("move_down")
	_check(absf(player.global_position.distance_to(start) - straight_distance) < 5.0, "Diagonal speed equals straight speed")

	player.global_position = Vector2(130, 600)
	Input.action_press("move_left")
	await _ticks(40)
	Input.action_release("move_left")
	_check(player.global_position.x >= 114.0 and player.global_position.x <= 117.0, "World wall stops player")
	player.global_position = Vector2(850, 400)
	Input.action_press("move_left")
	await _ticks(40)
	Input.action_release("move_left")
	_check(player.global_position.x >= 798.0 and player.global_position.x <= 802.0, "Crate stops player")
	_check(camera.get_screen_center_position().distance_to(player.global_position) < 2.0, "Camera follows within map limits")

	# In headless, Window reads a dummy system cursor; synthetic mouse events
	# cannot move it. Check the world-space aiming invariant at its actual position.
	player.global_position = Vector2(900, 540)
	await _ticks(3)
	var aim: Node2D = player.get_node("Aim")
	var cursor_direction := player.global_position.direction_to(player.get_global_mouse_position())
	_check(Vector2.RIGHT.rotated(aim.global_rotation).dot(cursor_direction) > 0.999, "Weapon points at viewport cursor in world coordinates")
	_check(is_zero_approx(camera.global_rotation), "Aiming does not rotate camera")
	player.set_physics_process(false)
	# Aim and shoot through the exact production weapon API, with real raycasts.
	aim.rotation = 0.0
	_check(weapon.try_fire(target.global_position, player), "First shot fires immediately")
	_check(is_equal_approx(target.health, 75.0), "Unobstructed shot deals exported damage")
	_check(_last_endpoint.is_equal_approx(Vector2(1162, 540)), "Tracer ends at nearest target surface")
	_check(not weapon.try_fire(target.global_position, player), "Same-tick second shot blocked by cooldown")
	await _ticks(11)
	weapon.damage = 10.0
	weapon.try_fire(target.global_position, player)
	_check(is_equal_approx(target.health, 65.0), "Changing exported damage changes actual hit")

	var cover := OBSTACLE.instantiate()
	cover.position = Vector2(1040, 540)
	cover.size = Vector2(40, 120)
	yard.add_child(cover)
	await _ticks(11)
	weapon.try_fire(target.global_position, player)
	_check(is_equal_approx(target.health, 65.0), "Cover blocks damage to target behind it")
	_check(is_equal_approx(_last_endpoint.x, 1020.0), "Tracer stops at cover")
	# The muzzle extends into cover, but the ray must not skip the wall.
	player.global_position = Vector2(1005, 540)
	await _ticks(11)
	weapon.try_fire(target.global_position, player)
	_check(is_equal_approx(target.health, 65.0) and is_equal_approx(_last_endpoint.x, 1020.0), "Muzzle touching wall cannot shoot through it")
	player.global_position = cover.global_position
	await _ticks(11)
	weapon.try_fire(target.global_position, player)
	_check(is_equal_approx(target.health, 65.0), "Ray originating inside cover is blocked")
	cover.queue_free()
	player.global_position = Vector2(900, 540)
	await _ticks(11)

	# Also exercise the production input path for held LMB and the rate limit.
	weapon.fire_rate = 6.0
	weapon.damage = 1.0
	player.set_physics_process(true)
	_shot_count = 0
	Input.action_press("shoot")
	await _ticks(60)
	Input.action_release("shoot")
	player.set_physics_process(false)
	_check(_shot_count == 6, "Holding LMB fires six shots per second at 6 shots/s")
	await _ticks(11)
	weapon.fire_rate = 12.0
	_shot_count = 0
	player.set_physics_process(true)
	Input.action_press("shoot")
	await _ticks(60)
	Input.action_release("shoot")
	player.set_physics_process(false)
	_check(_shot_count == 12, "Changing fire rate changes held-fire cadence")
	await _ticks(11)
	weapon.max_range = 50.0
	var previous_health: float = target.health
	weapon.try_fire(target.global_position, player)
	_check(is_equal_approx(target.health, previous_health), "Range limits damage")
	weapon.max_range = 1000.0
	await _ticks(11)
	weapon.damage = 500.0
	weapon.try_fire(target.global_position, player)
	await _ticks(2)
	_check(target.is_destroyed and is_zero_approx(target.health), "Lethal shot destroys target")
	_check(target.collision_layer == 0 and target.get_node("CollisionShape2D").disabled, "Wreck no longer blocks shots or movement")
	_check(not yard.has_node("HUD/TargetStatus"), "Target destruction needs no debug counter in gameplay HUD")
	target.take_damage(500.0)
	_check(is_zero_approx(target.health), "Destroyed target ignores further damage")
	await _ticks(15)
	# All temporary shot effects should be freed after their lifetime.
	var effect_count := 0
	for child in yard.get_children():
		if child.get_script() == preload("res://scripts/shot_effect.gd"):
			effect_count += 1
	_check(effect_count == 0, "Temporary shot visuals clean themselves up")

	var crate_a: StaticBody2D = yard.get_node("Obstacles/WestCrate")
	var crate_b: StaticBody2D = yard.get_node("Obstacles/PassageCrate")
	crate_a.size = Vector2(120, 65)
	_check(crate_a.get_node("CollisionShape2D").shape.size == Vector2(120, 65), "Obstacle size updates collision")
	_check(crate_b.get_node("CollisionShape2D").shape.size == Vector2(88, 88), "Resizing obstacle does not modify other instances")

	# Send the actual restart key action through scene input handling.
	var restart := InputEventAction.new()
	restart.action = "restart"
	restart.pressed = true
	root.push_input(restart)
	await _ticks(4)
	_check(current_scene != yard and current_scene.get_node("Target").health == 100.0, "Enter reloads map and restores target")
	_check(current_scene.get_node("Player").position == Vector2(650, 565), "Restart restores spawn")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
