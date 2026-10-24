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
	await _check_contact_movement(room)
	await _check_prop_approaches(room)
	await _check_loot_facing(room)
	await _check_dressing(room)
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
	_check(sprite.texture is ViewportTexture and visual.model.get_child_count() == 5, "Forest player uses the shared modular visual with five saved rigs")
	for facing in 8:
		player.aim.rotation = facing * PI / 4.0
		visual.sync_actor()
		_check(visual.direction_index == facing, "Forest visual selects direction %d from the actor's real Aim" % facing)
	player.aim.rotation = 0.0
	player.velocity = Vector2.RIGHT * 100
	player.moved.emit(20.0)
	await _ticks(2)
	var walking_phase: float = visual.phase
	_check(walking_phase > 0.0 and visual.gait_blend > 0.0, "Actual travel advances shared articulated gait")
	player.velocity = Vector2.ZERO
	player.moved.emit(0.0)
	await _ticks(12)
	_check(is_zero_approx(visual.gait_blend) and visual.phase == walking_phase, "Stopping settles the gait without resetting its phase")
	player.aim.rotation = PI
	await _ticks(2)
	_check(visual.direction_index == 4 and visual.rig.scale.x < 0 and is_zero_approx(visual.global_rotation), "Facing left mirrors the saved rig without rotating the body")
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
	var upper_body: Vector2 = enemy.global_position + Vector2(0, -56)
	_check(player.weapon.try_fire(player.weapon.aim_from_screen(upper_body, player), player), "Player can aim at the drawn upper body through input projection")
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
	_check(spawned.get_node("Aim/BodyVisual").scene_file_path == "res://scenes/characters/character_visual.tscn", "F2 uses the same shared character scene as saved guards")
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


func _walk(player: CharacterBody2D, direction: Vector2, ticks: int) -> void:
	for tick in range(ticks):
		player.velocity = direction * 250
		player.move_and_slide()
		await _ticks(1)
	player.velocity = Vector2.ZERO


func _check_contact_movement(room: Node2D) -> void:
	var player: CharacterBody2D = room.get_node("Player")
	var initial := player.position
	# This exact approach wedged the old 30 px passage: down could not escape.
	player.position = Vector2(785, 640)
	await _ticks(2)
	await _walk(player, Vector2.UP, 60)
	_check(player.position.y < 500, "Actual walking traverses the formerly wedged log/chest corridor")
	var stop := player.position
	await _walk(player, Vector2.DOWN, 20)
	_check(player.position.y > stop.y + 70, "Player can reverse and leave the former pocket without teleport or recovery")
	var stump: StaticBody2D = room.get_node("Dressing/TimberYard/Stump1")
	for from_north in [true, false]:
		player.position = stump.position + Vector2(0, -85 if from_north else 85)
		await _ticks(2)
		await _walk(player, Vector2.DOWN if from_north else Vector2.UP, 35)
		var gap := absf(player.global_position.y - stump.global_position.y)
		_check(absf(gap - (stump.size.y * 0.5 + 15)) < 0.5, "Stump contact stops the ground collider at its real footprint " + ("from north" if from_north else "from south"))
		_check((player.position.y < stump.position.y) == from_north, "Blocking and front/back ordering agree at stump contact")
		stop = player.position
		await _walk(player, Vector2.UP if from_north else Vector2.DOWN, 14)
		_check(player.position.distance_to(stop) > 50, "Stump contact always allows walking back out")
	var logs: StaticBody2D = room.get_node("Obstacles/WestLogs")
	player.position = logs.position + Vector2(0, 160)
	await _ticks(2)
	await _walk(player, Vector2.UP, 45)
	_check(absf(player.position.y - (logs.position.y + logs.size.y * 0.5 + 15)) < 0.5, "Walking north meets log footprint at the feet, without a phantom 30 px gap")
	var visual: Node2D = player.get_node("Aim/BodyVisual")
	visual.sync_actor()
	_check(absf(visual.get_node("Shadow").position.y) < 3, "Visible contact shadow and movement center share the ground origin")
	var health: float = player.health
	_check(player.weapon.try_fire(player.position + Vector2.DOWN * 200, player) and player.health == health, "Ground contact does not place the shot origin inside cover or the shooter's own hurtbox")
	player.restore_state()
	player.position = initial
	await _ticks(26)


func _check_prop_approaches(room: Node2D) -> void:
	var player: CharacterBody2D = room.get_node("Player")
	var initial := player.position
	# Approach real saved instances, including off-center rock lobes. Testing the
	# stopped feet against source alpha catches the old invisible northern gap.
	for path in ["LootContainers/WoodCache", "LootContainers/EastSupplies", "Obstacles/BackRocks", "Obstacles/SouthRocks"]:
		var prop: StaticBody2D = room.get_node(path)
		var sprite: Sprite2D = prop.get_node("Sprite")
		var image := sprite.texture.get_image()
		var sideways := 32.0 if "Rocks" in path else 8.0
		for offset in [-sideways, 0.0, sideways]:
			player.global_position = prop.global_position + Vector2(offset, -60)
			await _ticks(2)
			await _walk(player, Vector2.DOWN, 24)
			var label := str(prop.name) + " x=" + str(offset)
			var stopped_by_prop := false
			for index in range(player.get_slide_collision_count()):
				stopped_by_prop = stopped_by_prop or player.get_slide_collision(index).get_collider() == prop
			_check(stopped_by_prop and player.global_position.y < prop.global_position.y, "North approach meets the actual prop footprint: " + label)
			var foot := Vector2i(sprite.to_local(player.global_position + Vector2(0, -1.5)) - sprite.get_rect().position)
			var inside_image := Rect2i(Vector2i.ZERO, image.get_size()).has_point(foot)
			_check(inside_image and image.get_pixelv(foot).a > 0.5, "Stopped feet overlap opaque artwork instead of an invisible gap: " + label)
			var stop := player.global_position
			await _walk(player, Vector2.UP, 10)
			_check(player.global_position.distance_to(stop) > 30, "Prop contact allows reversing out: " + label)
	player.global_position = initial
	await _ticks(2)


func _check_loot_facing(room: Node2D) -> void:
	var player: CharacterBody2D = room.get_node("Player")
	var initial := player.global_position
	var initial_aim: float = player.aim.rotation
	var chest: StaticBody2D = room.get_node("LootContainers/WoodCache")
	var interaction: Node = player.get_node("LootInteraction")
	var menu: Control = room.get_node("HUD/LootMenu")
	# Actual stops at the same saved chest, including the reported southern
	# approach. Cardinal facing is independent of the selection implementation.
	for offset in [Vector2(0, 60), Vector2(0, -60), Vector2(-52, 0), Vector2(60, 0)]:
		player.global_position = chest.global_position + offset
		await _ticks(2)
		var direction: Vector2 = -offset.normalized()
		await _walk(player, direction, 24)
		var label := " from " + str(offset)
		_check(interaction.can_reach(chest), "Real chest contact remains reachable" + label)
		player.aim.rotation = direction.angle()
		await _ticks(2)
		_check(interaction.can_interact(chest) and interaction._nearest() == chest and chest.get_node("Hint").visible, "Facing the visible chest at contact selects it" + label)
		await _key(KEY_E)
		_check(menu.visible and menu._container == chest, "Actual E opens the facing chest" + label)
		menu.close_menu()
		player.aim.rotation = direction.angle() + PI
		await _ticks(2)
		_check(not interaction.can_interact(chest) and not chest.get_node("Hint").visible, "Facing away at contact removes the chest hint" + label)
		await _key(KEY_E)
		_check(not menu.visible, "Actual E cannot open the chest behind the player" + label)
	# A ground item's visible center remains at ground height, unlike a raised
	# chest. The same contract must support both without a global Y correction.
	var ground: GroundItem = load("res://scenes/ground_item.tscn").instantiate()
	room.add_child(ground)
	ground.global_position = Vector2(700, 730)
	var items: Array[ItemDefinition] = [load("res://resources/items/metal.tres")]
	ground.inventory.replace_slots(items)
	for offset in [Vector2(0, 36), Vector2(0, -36), Vector2(-36, 0), Vector2(36, 0)]:
		player.global_position = ground.global_position + offset
		player.aim.look_at(ground.global_position)
		await _ticks(2)
		_check(interaction.can_interact(ground) and interaction._nearest() == ground, "Visible ground item is selected" + str(offset))
		player.aim.rotation += PI
		await _ticks(2)
		_check(not interaction.can_interact(ground), "Ground item behind the visual aim is rejected" + str(offset))
	player.global_position = ground.global_position + Vector2(0, 30)
	player.aim.rotation = PI / 2
	_check(interaction.can_interact(ground), "Coincident visible target and aim do not create an undefined-facing dead zone")
	ground.free()
	player.global_position = initial
	player.aim.rotation = initial_aim
	await _ticks(2)


func _check_dressing(room: Node2D) -> void:
	var map := room.get_world_2d().navigation_map
	var start := Vector2(470, 700)
	# Real saved map destinations: all loot approaches, F2 spawns and both exits
	# from the courtyard, not just the easier geometry on the technical fixture.
	var destinations := {
		"hut supplies": Vector2(440, 580),
		"wood cache": Vector2(820, 515),
		"east supplies": Vector2(1295, 705),
		"north extraction": Vector2(1120, 90),
		"southern entrance": Vector2(480, 930),
		"behind hut": Vector2(350, 305),
	}
	for marker in room.get_node("GuardSpawns").get_children():
		destinations["guard " + str(marker.name)] = marker.global_position
	for label in destinations:
		var destination: Vector2 = destinations[label]
		var path := NavigationServer2D.map_get_path(map, start, destination, true)
		_check(path.size() >= 2 and path[-1].distance_to(destination) < 5, "Dressed forest navigation reaches " + label)
	var world := room.get_world_2d().direct_space_state
	var bench: StaticBody2D = room.get_node("Dressing/TimberYard/Workbench1")
	var ray := PhysicsRayQueryParameters2D.create(bench.global_position - Vector2(90, 0), bench.global_position + Vector2(90, 0), 1)
	var hit := world.intersect_ray(ray)
	_check(hit.get("collider") == bench, "New solid workbench blocks actual combat rays")
	var player: CharacterBody2D = room.get_node("Player")
	var saved_position := player.global_position
	var shrub: Node2D = room.get_node("Dressing/Vegetation/Shrub1")
	player.global_position = shrub.global_position - Vector2(40, 0)
	await _ticks(2)
	for tick in range(24):
		player.velocity = Vector2(240, 0)
		player.move_and_slide()
		await _ticks(1)
	_check(player.global_position.x > shrub.global_position.x + 35, "New bushes remain passable in actual forest movement")
	var puddle: Sprite2D = room.get_node("Dressing/GroundDetails/puddle_0")
	player.global_position = puddle.global_position - Vector2(0, 35)
	await _ticks(2)
	for tick in range(22):
		player.velocity = Vector2(0, 240)
		player.move_and_slide()
		await _ticks(1)
	_check(player.global_position.y > puddle.global_position.y + 30, "Shallow water is ground detail and never blocks walking")
	player.velocity = Vector2.ZERO
	player.global_position = saved_position
	await _ticks(2)


func _check_contact_shadows() -> void:
	for scene_path in ["res://scenes/player.tscn", "res://scenes/enemy.tscn"]:
		var actor: CharacterBody2D = load(scene_path).instantiate()
		root.add_child(actor)
		actor.set_physics_process(false)
		var visual: Node2D = actor.get_node("Aim/BodyVisual")
		var shadow: Polygon2D = visual.get_node("Shadow")
		var feet_aligned := true
		var ray_origins_stable := true
		# All dusk frames share a 64 px, bottom-aligned canvas. Check every pose,
		# including mirrored views, against that art contract rather than an offset.
		for facing in [0.0, PI, PI / 2, -PI / 2]:
			actor.aim.rotation = facing
			actor.velocity = Vector2.RIGHT.rotated(facing) * 100
			for pose in range(4):
				actor.moved.emit(visual.walk_gait.stride_distance / 4.0)
				visual.sync_actor()
				feet_aligned = feet_aligned and absf(shadow.position.y) < 3.0 and absf(shadow.rotation) < 0.01
				var offset := Vector2(0, -30)
				ray_origins_stable = ray_origins_stable and actor.aim.global_position.distance_to(actor.global_position + offset) < 0.01 and actor.weapon.aim_from_screen(actor.aim.global_position + Vector2.RIGHT * 100, actor).distance_to(actor.global_position + Vector2.RIGHT * 100) < 0.01
		_check(feet_aligned, "Contact shadow stays at the feet through walking and facing: " + actor.name)
		_check(ray_origins_stable, "Render aim projects to the ground plane in every facing: " + actor.name)
		actor.velocity = Vector2.ZERO
		actor.take_damage(10000)
		await _ticks(2)
		_check(visual.fallen and shadow.position.y < 16.0 and shadow.scale.x > 2.0, "Death places an extended shadow under the fallen body: " + actor.name)
		if actor.has_method("restore_state"):
			actor.restore_state()
			await _ticks(2)
			_check(not visual.fallen and absf(shadow.position.y) < 3.0 and shadow.scale.x < 2.0, "Revival restores the standing ground contact shadow")
		actor.free()
		await _ticks(1)


