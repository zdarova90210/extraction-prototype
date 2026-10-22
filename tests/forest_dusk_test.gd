extends "res://tests/loot_slots_test.gd"
## Real saved forest scene: presentation, passage, combat, loot and raid wiring.

func _run() -> void:
	await _check_contact_shadows()
	var room: Node2D = load("res://scenes/forest_dusk.tscn").instantiate()
	room.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(room.get_node("Navigation").get_rid(), false)
	root.add_child(room)
	current_scene = room
	var player: CharacterBody2D = room.get_node("Player")
	var enemy: CharacterBody2D = room.get_node("Enemy")
	player.set_physics_process(false)
	# Stop decisions, not the entire CollisionObject: disabled process mode removes
	# bodies from physics by default. Shot checks need an active target body.
	enemy.set_physics_process(false)
	await _ticks(6)
	var progress := root.get_node("RaidProgress")
	_check(progress.save_path.is_empty(), "Forest tests use memory progress, not the owner's save")
	_check(player.health == 100 and player.get_node("Inventory").item_count == 2, "Forest combat starts with full health and two test medkits")
	room.prepare_healing_test()
	_check(player.health == 10 and player.get_node("Inventory").item_count == 2, "F2 healing setup lowers health without duplicating the initial medkits")
	room.restore_player()
	_check(player.get_node("CollisionShape2D").shape.radius == 15 and enemy.get_node("CollisionShape2D").shape.radius == 15, "Sprite replacement keeps both physical hitboxes")
	_check(player.weapon.damage == 20 and player.weapon.fire_rate == 3 and enemy.max_health == 150, "Forest uses existing combat balance")
	var visual: Node2D = player.get_node("Aim/BodyVisual")
	var sprite: Sprite2D = visual.get_node("Sprite")
	_check(sprite.texture is AtlasTexture and visual.frames.get_animation_names().size() == 3, "Player has independent atlas views with no baked background")
	for animation in [&"down", &"side", &"up"]:
		_check(visual.frames.get_frame_count(animation) == 4, "Each facing has four aligned poses")
	player.aim.rotation = 0.0
	player.velocity = Vector2.RIGHT * 100
	player.moved.emit(20.0)
	await _ticks(2)
	var walking_texture: Texture2D = sprite.texture
	player.velocity = Vector2.ZERO
	player.moved.emit(0.0)
	await _ticks(2)
	_check(sprite.texture != walking_texture, "Walking advances with actual travel and stops in idle")
	player.aim.rotation = PI
	await _ticks(2)
	_check(sprite.flip_h and is_zero_approx(visual.global_rotation), "Facing left mirrors a sprite without rotating the body")
	var hut: StaticBody2D = room.get_node("Obstacles/Hut")
	player.global_position = Vector2(350, 315)
	await _ticks(25)
	_check(hut.get_node("Occlusion").is_obscuring and hut.get_node("Sprite").self_modulate.a < 0.31, "Walkable route behind hut fades its foreground art")
	_check(hut.collision_layer == 1 and not hut.get_node("CollisionShape2D").disabled, "Fading never disables the wall collider")
	for tick in range(50):
		player.velocity = Vector2(0, 250)
		player.move_and_slide()
		await _ticks(1)
	_check(player.position.y < 365, "Hut ground footprint blocks actual movement")
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(350, 540)
	await _ticks(25)
	_check(not hut.get_node("Occlusion").is_obscuring and hut.get_node("Sprite").self_modulate.a > 0.99, "Hut returns opaque when the player walks in front")
	player.global_position = Vector2(1020, 730)
	await _ticks(25)
	_check(room.get_node("Obstacles/Pine12/Occlusion").is_obscuring, "A real walkable tree also reveals the player behind its canopy")
	var map := room.get_world_2d().navigation_map
	var behind_path := NavigationServer2D.map_get_path(map, Vector2(130, 540), Vector2(350, 315), true)
	_check(behind_path.size() >= 2 and behind_path[-1].distance_to(Vector2(350, 315)) < 5, "Navigation reaches the passage behind the hut")
	var exit_path := NavigationServer2D.map_get_path(map, Vector2(470, 700), Vector2(1120, 90), true)
	_check(exit_path.size() >= 2 and exit_path[-1].distance_to(Vector2(1120, 90)) < 5, "Extraction gap is reachable around saved cover")
	player.global_position = Vector2(520, 560)
	enemy.global_position = Vector2(860, 560)
	await _ticks(3)
	var health_before: float = enemy.health
	_check(player.weapon.try_fire(enemy.global_position, player), "Existing player weapon fires in forest")
	_check(enemy.health == health_before, "Log cover blocks damage between shooter and enemy")
	await _ticks(25)
	player.global_position = Vector2(520, 440)
	enemy.global_position = Vector2(860, 440)
	await _ticks(3)
	_check(player.weapon.try_fire(enemy.global_position, player), "Player can fire from the open side of cover")
	_check(enemy.health == health_before - player.weapon.damage, "Clear shot damages the visible guard")
	await _ticks(25)
	var torso_health: float = enemy.health
	_check(player.weapon.try_fire(enemy.global_position + Vector2(0, -21), player), "Player can aim at the drawn upper body")
	_check(enemy.health == torso_health - player.weapon.damage, "A visible upper-body hit reaches the separate damage silhouette")
	var player_health_before: float = player.health
	_check(enemy.weapon.try_fire(player.global_position, enemy), "Guard weapon uses its existing forest target")
	_check(player.health == player_health_before - enemy.weapon.damage, "Guard shot damages the player's unchanged hitbox")
	enemy.take_damage(1000)
	await _ticks(3)
	_check(enemy.get_node("Aim/BodyVisual").fallen and not enemy.weapon.enabled, "Death updates pixel presentation and stops shared weapon")
	_check(enemy.get_node("Hurtbox").collision_layer == 0, "Dead guard silhouette stops blocking shots")
	var spawn_result: String = room.spawn_guard(1)
	_check(spawn_result.begins_with("Охранник добавлен"), "F2 spawns a guard from a saved valid marker")
	var spawned: Node2D = room.get_guards().back()
	_check(spawned.get_node("Aim/BodyVisual").frames.resource_path.ends_with("guard_frames.tres"), "F2 uses the room's pixel guard variant")
	room.set_guards_active(false)
	var chest := room.get_node("LootContainers/HutSupplies")
	player.global_position = Vector2(440, 580)
	player.aim.rotation = -PI / 2
	await _ticks(3)
	_check(player.get_node("LootInteraction").can_interact(chest), "Saved loot chest is reachable by distance, gaze and unobstructed line")
	var menu: Control = room.get_node("HUD/LootMenu")
	menu.open_container(chest)
	await _ticks(96)
	_check(chest.is_discovered(0) and not chest.is_discovered(1), "Pixel chest retains 1.5-second sequential search")
	var backpack: Inventory = player.get_node("Inventory")
	_check(chest.take_to(backpack, 0), "Revealed loot transfers through the existing Inventory")
	menu.close_menu()
	await _ticks(2)
	var count_before: int = backpack.item_count
	_check(player.get_node("LootInteraction").drop_item(2), "Loot can be dropped in a free forest spot")
	await _ticks(2)
	var dropped: GroundItem = get_nodes_in_group("ground_items")[0]
	_check(dropped.pick_up(backpack) and backpack.item_count == count_before, "Dropped loot returns without loss or duplication")
	var pause_menu: Control = room.get_node("HUD/PauseMenu")
	pause_menu.set_open(true)
	_check(paused, "Shared pause menu remains sole pause owner")
	pause_menu.set_open(false)
	_check(not paused, "Resume returns safely to forest")
	player.global_position = Vector2(1120, 90)
	await _ticks(310)
	_check(current_scene != room and progress.last_result.get("outcome") == "extracted", "Forest completes the existing extraction and returns to base")
	_check(progress.stash.item_count == count_before, "Forest loot is persisted through the shared transaction")
	# Follow the same new base button the owner uses, then exercise live AI.
	await _click(current_scene.get_node("Margin/Content/Actions/Start"))
	await _ticks(3)
	var combat_room: Node2D = current_scene
	_check(combat_room.scene_file_path == "res://scenes/forest_dusk.tscn", "Base forest button launches the saved pixel scene")
	combat_room.play_start_audio = false
	var live_player: CharacterBody2D = combat_room.get_node("Player")
	var live_guard: CharacterBody2D = combat_room.get_node("Enemy")
	live_player.set_physics_process(false)
	live_player.prevent_death = true
	live_player.global_position = Vector2(900, 425)
	var shots: Array[int] = [0]
	live_guard.weapon.shot_fired.connect(func(_from: Vector2, _to: Vector2, _hit: bool): shots[0] += 1)
	await _ticks(120)
	_check(shots[0] > 0 and live_player.health < 100, "Live forest guard detects, prepares and shoots the standing player")
	_check(is_zero_approx(live_guard.get_node("Aim/BodyVisual").global_rotation), "Live AI turns its weapon while pixel body stays upright")
	live_player.take_damage(10000)
	await _ticks(2)
	_check(live_player.health == 1 and live_player.get_node("Hurtbox").collision_layer == 2, "Immortality keeps the damage silhouette active at 1 HP")
	live_guard.set_behavior_enabled(false)
	live_player.prevent_death = false
	live_player.take_damage(1)
	await _ticks(2)
	_check(live_player.get_node("Hurtbox").collision_layer == 0, "Player death disables the damage silhouette")
	combat_room.restore_player()
	await _ticks(2)
	_check(live_player.health == 100 and live_player.get_node("Hurtbox").collision_layer == 2 and not live_player.get_node("Aim/BodyVisual").fallen, "F2 restore revives the pixel body and its damage silhouette")
	combat_room.free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_contact_shadows() -> void:
	for scene_path in ["res://scenes/player.tscn", "res://scenes/enemy.tscn"]:
		var actor: CharacterBody2D = load(scene_path).instantiate()
		root.add_child(actor)
		actor.set_physics_process(false)
		var visual: Node2D = actor.get_node("Aim/BodyVisual")
		var shadow: Polygon2D = actor.get_node("Shadow")
		var feet_aligned := true
		# All dusk frames share a 64 px, bottom-aligned canvas. Check every pose,
		# including mirrored views, against that art contract rather than an offset.
		for facing in [0.0, PI, PI / 2, -PI / 2]:
			actor.aim.rotation = facing
			actor.velocity = Vector2.RIGHT.rotated(facing) * 100
			for pose in range(4):
				actor.moved.emit(visual.stride_distance / 4.0)
				visual._sync_visual()
				feet_aligned = feet_aligned and shadow.position.y > 28.0 and shadow.position.y < 33.0 and absf(shadow.rotation) < 0.01
		_check(feet_aligned, "Contact shadow stays at the feet through walking and facing: " + actor.name)
		actor.velocity = Vector2.ZERO
		actor.take_damage(10000)
		await _ticks(2)
		_check(visual.fallen and shadow.position.y < 16.0 and shadow.scale.x > 25.0, "Death places an extended shadow under the fallen body: " + actor.name)
		if actor.has_method("restore_state"):
			actor.restore_state()
			await _ticks(2)
			_check(not visual.fallen and shadow.position.y > 28.0 and shadow.scale.x < 20.0, "Revival restores the standing contact shadow")
		actor.free()
		await _ticks(1)


