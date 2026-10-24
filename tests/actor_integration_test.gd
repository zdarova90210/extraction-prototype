extends "res://tests/loot_slots_test.gd"
## Real forest actors and input: shared art, immediate fire, safe UI, healing and death.

const CHARACTER = preload("res://scenes/characters/character_visual.tscn")
const SHOT = preload("res://scripts/shot_effect.gd")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room: Node2D = load("res://scenes/forest_dusk.tscn").instantiate()
	room.play_start_audio = false
	root.add_child(room)
	current_scene = room
	var player: CharacterBody2D = room.player
	var guard: CharacterBody2D = room.get_node("Enemy")
	guard.set_physics_process(false)
	player.set_physics_process(false)
	player.position = Vector2(700, 730)
	guard.position = Vector2(850, 730)
	await _ticks(5)
	var visual: Node2D = player.body_visual
	var other: Node2D = guard.body_visual
	_check(visual.scene_file_path == CHARACTER.resource_path and other.scene_file_path == CHARACTER.resource_path, "Forest player and guard instance the same visual as the animation stand")
	_check(visual.get_node("Pixels").get_texture() != other.get_node("Pixels").get_texture(), "Each actor owns an independent pose viewport")
	_check(player.move_speed == 250.0 and guard.move_speed == 135.0 and player.weapon.damage == 20.0 and guard.weapon.damage == 18.0, "Visual adoption preserves movement and combat balance")
	_check(player.get_node("CollisionShape2D").shape.radius == 15 and guard.agent.radius == 15, "Ground collisions and navigation radius stay at 15 px")
	_check(player.aim.position == Vector2(0, -30) and player.get_node("Camera2D").position == Vector2(0, -30), "Interaction origin and camera composition retain their established height")
	player.weapon.max_range = 500.0
	for index in 8:
		player.aim.rotation = index * PI / 4.0
		guard.aim.rotation = player.aim.rotation
		visual.sync_actor()
		other.sync_actor()
		_check(visual.direction_index == index and other.direction_index == index and is_zero_approx(visual.global_rotation), "Both real actors select upright view %d" % index)
		_check(player.weapon.visual_muzzle == visual.get_node("MuzzleAnchor") and player.weapon.visual_muzzle.global_position.distance_to(player.global_position + visual.muzzle_offset()) < 0.05, "Real weapon follows the active rig muzzle in view %d" % index)
	# Actual input, with world coordinates transformed through the real camera.
	player.set_physics_process(true)
	await _move_mouse(guard.global_position + Vector2(0, -30))
	_mouse_right(true)
	var magazine: int = player.weapon.ammo
	var before_pose: Transform2D = visual.grip.transform
	await _ticks(20)
	_check(visual.grip.transform == before_pose and player.weapon.ammo == magazine, "RMB has no stance or fire action in the real forest")
	var muzzle_before: Vector2 = player.weapon.visual_muzzle.global_position
	var health_before: float = guard.health
	Input.action_press("shoot")
	await _ticks(2)
	Input.action_release("shoot")
	_check(player.weapon.ammo == magazine - 1 and guard.health == health_before - player.weapon.damage, "LMB fires immediately and hits the real forest guard")
	var effects := room.get_children().filter(func(node): return node.get_script() == SHOT)
	_check(not effects.is_empty() and effects.back().global_position.distance_to(muzzle_before) < 0.5, "Forest tracer starts at the drawn pre-recoil muzzle")
	_mouse_right(false)
	await _ticks(30)
	magazine = player.weapon.ammo
	Input.action_press("shoot")
	await _ticks(2)
	_check(player.weapon.ammo == magazine - 1, "Forest LMB fires immediately after standing idle, without RMB")
	var pause: Control = room.get_node("HUD/PauseMenu")
	pause.set_open(true)
	await _ticks(4)
	pause.set_open(false)
	magazine = player.weapon.ammo
	Input.action_press("shoot")
	await _ticks(25)
	_check(player.weapon.ammo == magazine, "Held fire cannot become a shot after closing pause")
	Input.action_release("shoot")
	await _ticks(2)
	await _key(KEY_TAB)
	_check(room.get_node("HUD/LootMenu").visible and not player.input_enabled, "Real Tab opens backpack and blocks gameplay input")
	await _key(KEY_TAB)
	await _ticks(2)
	_check(player.input_enabled, "Closing backpack returns actor input")
	# Healing still owns its established rules.
	player.take_damage(40)
	_check(player.item_use.use_first_healing_item(), "The real forest actor can start healing")
	magazine = player.weapon.ammo
	_mouse_right(true)
	Input.action_press("shoot")
	await _ticks(20)
	_check(player.item_use.is_using and player.weapon.ammo == magazine, "Healing blocks fire through held mouse input")
	Input.action_release("shoot")
	_mouse_right(false)
	await _ticks(165)
	_check(player.health == 100.0 and not player.item_use.is_using and player.get_node("Inventory").item_count == 1, "Healing completes with one real medkit consumption")
	await _key(KEY_C)
	await _ticks(18)
	var start := player.position
	Input.action_press("move_left")
	await _ticks(20)
	Input.action_release("move_left")
	_check(player.sneaking and visual.sneak_blend > 0.99 and player.position.distance_to(start) > 45.0 and player.position.distance_to(start) < 55.0, "C applies the accepted slow gait to actual forest movement")
	await _key(KEY_C)
	await _ticks(18)
	start = player.position
	Input.action_press("move_right")
	await _ticks(20)
	Input.action_release("move_right")
	_check(not player.sneaking and player.position.distance_to(start) > 78.0 and player.position.distance_to(start) < 88.0, "Ordinary movement returns to its existing 250 px/s speed")
	# A rotated frozen guard must also fall horizontally at its ground origin.
	guard.aim.rotation = -PI / 2
	other.sync_actor()
	guard.aim.rotation = 0.0
	guard.take_damage(10000)
	await _ticks(2)
	var corpse: Sprite2D = other.get_node("Sprite")
	_check(other.fallen and absf(angle_difference(corpse.global_rotation, PI / 2)) < 0.01 and other.global_position.distance_to(guard.global_position) < 0.01, "Frozen and live guards share a horizontal corpse rooted on the ground")
	_check(not other.grip.visible and guard.get_node("Hurtbox").collision_layer == 0 and not guard.weapon.enabled, "Death removes held weapon and disables hurtbox/fire")
	player.take_damage(10000)
	await _ticks(2)
	_check(visual.fallen and player.get_node("Hurtbox").collision_layer == 0 and room.death_screen.visible, "Player death uses the same corpse and existing raid defeat flow")
	room.restore_player()
	await _ticks(2)
	_check(not visual.fallen and visual.grip.visible and player.get_node("Hurtbox").collision_layer == 2 and not room.death_screen.visible, "F2 recovery restores standing art, weapon and damage silhouette")
	room.free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _move_mouse(world: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_canvas_transform() * world
	event.global_position = event.position
	Input.parse_input_event(event)
	await _ticks(2)

func _mouse_right(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = down
	event.position = root.get_mouse_position()
	event.global_position = event.position
	Input.parse_input_event(event)
