extends "res://tests/loot_slots_test.gd"
## Movement and shot rules in the saved playable forest, using both real weapons.

var _async_navigation := "--async-navigation" in OS.get_cmdline_user_args()
var _last_hit: Object

func _initialize() -> void:
	if not _async_navigation:
		NavigationServer2D.map_set_use_async_iterations(root.get_world_2d().navigation_map, false)
	_run.call_deferred()

func _run() -> void:
	var room: Node2D = load("res://scenes/forest_dusk.tscn").instantiate()
	room.play_start_audio = false
	if not _async_navigation:
		NavigationServer2D.region_set_use_async_iterations(room.get_node("Navigation").get_rid(), false)
	root.add_child(room)
	current_scene = room
	var player: CharacterBody2D = room.get_node("Player")
	var guard: CharacterBody2D = room.get_node("Enemy")
	# Keep bodies in physics; disabling process_mode would remove them from rays.
	player.set_physics_process(false)
	guard.set_physics_process(false)
	player.weapon.hit_registered.connect(_record_hit)
	guard.weapon.hit_registered.connect(_record_hit)
	await _ticks(8)
	var cases := {
		"LootContainers/HutSupplies": Vector2.RIGHT,
		"LootContainers/WoodCache": Vector2.RIGHT,
		"LootContainers/EastSupplies": Vector2.DOWN,
		"Dressing/TimberYard/Firewood1": Vector2.RIGHT,
		"Dressing/TimberYard/Firewood2": Vector2.RIGHT,
		"Dressing/TimberYard/Stump1": Vector2.RIGHT,
		"Dressing/TimberYard/Stump2": Vector2.RIGHT,
		"Dressing/TimberYard/Stump3": Vector2.RIGHT,
		"Dressing/TimberYard/Workbench1": Vector2.DOWN,
		"Obstacles/WestLogs": Vector2.RIGHT,
		"Obstacles/EastLogs": Vector2.DOWN,
		"Obstacles/BackRocks": Vector2.RIGHT,
		"Obstacles/Hut": Vector2.DOWN,
		"Obstacles/Pine12": Vector2.RIGHT,
		"Obstacles/NorthFence5": Vector2.DOWN,
	}
	for path in cases:
		var obstacle: WorldObstacle = room.get_node(path)
		var high: bool = path.begins_with("Obstacles/")
		_check(obstacle.blocks_movement and obstacle.blocks_shots == high, "Saved forest rules: " + path)
		await _shoot_across(obstacle, cases[path], player, guard)
	# Actual approaches and retreat at both a low and a high saved object.
	for path in ["LootContainers/WoodCache", "Dressing/TimberYard/Stump1", "Obstacles/WestLogs"]:
		var obstacle: WorldObstacle = room.get_node(path)
		# The chest and big logs share a deliberately narrow side passage.
		# Approach from north/south, rather than teleport inside the neighbour.
		var axis := Vector2.RIGHT if path.ends_with("Stump1") else Vector2.DOWN
		for side in [-1.0, 1.0]:
			guard.position = Vector2(1480, 500)
			var footprint: Rect2 = obstacle.get_node("CollisionShape2D").shape.get_rect()
			var center := obstacle.global_position + footprint.get_center()
			var half_extent: float = (footprint.size.x if axis.x != 0 else footprint.size.y) * 0.5
			player.position = center + axis * side * (half_extent + 40)
			await _ticks(2)
			await _walk(player, -axis * side, 24)
			var distance: float = absf((player.position - center).dot(axis))
			_check(distance >= half_extent + 14.8 and distance < half_extent + 16, "Saved ground footprint stops feet: %s, side %.0f" % [path, side])
			var contact := player.position
			await _walk(player, axis * side, ceili(35.0 * Engine.physics_ticks_per_second / player.move_speed))
			_check(player.position.distance_to(contact) > 25, "Free retreat from contact: %s, side %.0f" % [path, side])
	await _check_independent_flags(room, player, guard)
	await _check_close_and_stacked_cover(room, player, guard)
	_check_serialized_override(room)
	room.free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _record_hit(_point: Vector2, collider: Object) -> void:
	_last_hit = collider

func _shoot_across(obstacle: WorldObstacle, axis: Vector2, player: CharacterBody2D, guard: CharacterBody2D) -> void:
	var footprint: Rect2 = obstacle.get_node("CollisionShape2D").shape.get_rect()
	var center := obstacle.global_position + footprint.get_center()
	var distance: float = (footprint.size.x if axis.x != 0 else footprint.size.y) * 0.5 + 35
	for side in [-1.0, 1.0]:
		player.position = center - axis * distance * side
		guard.position = center + axis * distance * side
		player.aim.look_at(guard.position + Vector2(0, -30))
		guard.aim.rotation = guard.position.direction_to(player.position).angle()
		player.health = player.max_health
		guard.health = guard.max_health
		player.weapon.restore_state()
		guard.weapon.restore_state()
		await _ticks(2)
		var label := "%s, side %.0f" % [obstacle.name, side]
		_check(guard.can_see_target() == not obstacle.blocks_shots, "Guard sight uses shot obstacles: " + label)
		for pair in [[player, guard], [guard, player]]:
			var shooter: CharacterBody2D = pair[0]
			var victim: CharacterBody2D = pair[1]
			var health: float = victim.health
			_last_hit = null
			var fired: bool = shooter.weapon.try_fire(victim.position, shooter)
			var expected: float = health - (0.0 if obstacle.blocks_shots else shooter.weapon.damage)
			_check(fired and is_equal_approx(victim.health, expected), "Real damage %s through %s" % [shooter.name, label])
			var correct_hit: bool = _last_hit == obstacle if obstacle.blocks_shots else (_last_hit == victim or (_last_hit is Node and _last_hit.get_parent() == victim))
			_check(correct_hit, "Hit/material event chooses the correct surface: %s, %s" % [shooter.name, label])
		# The aiming state must use the same sight rules without a drawn laser.
		guard.state = guard.State.AIM
		guard.last_known_position = player.position
		guard._prepared_position = player.position
		guard._desired_angle = guard.aim.rotation
		guard._time_without_sight = 0
		guard._preparation = 0
		guard._physics_process(0)
		_check(guard._sees_target == not obstacle.blocks_shots, "Aiming sight agrees with shot rule: " + label)
		guard.state = guard.State.PATROL

func _walk(player: CharacterBody2D, direction: Vector2, frames: int) -> void:
	for frame in frames:
		player.velocity = direction * player.move_speed
		player.move_and_slide()
		await _ticks(1)
	player.velocity = Vector2.ZERO

func _check_independent_flags(room: Node2D, player: CharacterBody2D, guard: CharacterBody2D) -> void:
	var wood: WorldObstacle = room.get_node("Dressing/TimberYard/Firewood2")
	var collision: CollisionShape2D = wood.get_node("CollisionShape2D")
	var original_shape := collision.shape
	var sprite: Sprite2D = wood.get_node("Sprite")
	var original_transform := sprite.transform
	for movement in [false, true]:
		for shots in [false, true]:
			wood.blocks_movement = movement
			wood.blocks_shots = shots
			await _ticks(2)
			await _shoot_across(wood, Vector2.RIGHT, player, guard)
			guard.position = Vector2(1480, 500)
			player.position = wood.position + Vector2(-70, 0)
			await _ticks(2)
			await _walk(player, Vector2.RIGHT, 28)
			_check((player.position.x < wood.position.x) == movement, "Actual movement independent of shooting: move %s, shots %s" % [movement, shots])
			room.get_node("Navigation").rebuild()
			await _ticks(8)
			var map: RID = room.get_world_2d().navigation_map
			var outside: bool = NavigationServer2D.map_get_closest_point(map, wood.global_position).distance_to(wood.global_position) > 10
			_check(outside == movement, "Navigation uses only the movement rule: move %s, shots %s" % [movement, shots])
	_check(collision.shape == original_shape and sprite.transform == original_transform, "Rule edits preserve the authored footprint and artwork")
	wood.blocks_movement = true
	wood.blocks_shots = false

func _check_serialized_override(room: Node2D) -> void:
	var wood: WorldObstacle = load("res://scenes/forest_dusk/firewood.tscn").instantiate()
	wood.blocks_shots = true # Taller variant of a normally low type.
	var packed := PackedScene.new()
	_check(packed.pack(wood) == OK and ResourceSaver.save(packed, "res://artifacts/obstacle_override.tscn") == OK, "Instance-specific obstacle rule saves as a native scene")
	wood.free()
	var restored: WorldObstacle = load("res://artifacts/obstacle_override.tscn").instantiate()
	room.add_child(restored)
	restored.position = Vector2(-4000, -4000)
	_check(restored.blocks_movement and restored.blocks_shots and restored.collision_layer == 17, "Saved high variant restores both rules and physics layer")
	_check(not room.get_node("Dressing/TimberYard/Firewood1").blocks_shots, "Instance override does not change other low firewood")
	restored.free()

func _check_close_and_stacked_cover(room: Node2D, player: CharacterBody2D, guard: CharacterBody2D) -> void:
	var high: WorldObstacle = room.get_node("Obstacles/WestLogs")
	# This saved line crosses the big logs and then the low chest. Reverse it
	# to cover the opposite order, rather than testing just isolated props.
	for side in [false, true]:
		player.position = Vector2(900 if side else 550, 570)
		guard.position = Vector2(550 if side else 900, 570)
		player.weapon.restore_state()
		await _ticks(2)
		var health: float = guard.health
		_last_hit = null
		_check(player.weapon.try_fire(guard.position, player) and guard.health == health and _last_hit == high, "Nearest high cover stops a shot with low cover before/after it: %s" % side)
	var left: float = high.position.x - high.size.x * 0.5
	guard.position = Vector2(900, 560)
	for inside in [false, true]:
		player.position = Vector2(high.position.x if inside else left - 15.05, 560)
		player.aim.rotation = 0
		player.get_node("Aim/BodyVisual").sync_actor()
		player.weapon.restore_state()
		await _ticks(2)
		if not inside:
			_check(player.weapon.visual_muzzle.global_position.x > left, "Actual drawn muzzle extends into tall cover at contact")
		var health: float = guard.health
		_last_hit = null
		_check(player.weapon.try_fire(guard.position, player) and guard.health == health and _last_hit == high, "Tall cover cannot be bypassed at contact/from inside: %s" % inside)
