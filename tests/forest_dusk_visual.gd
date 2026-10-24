extends "res://tests/loot_slots_test.gd"
## Render the actual scene, including doorway, behind-house fade and pixel actors.


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room := load("res://scenes/forest_dusk.tscn").instantiate() as Node2D
	room.play_start_audio = false
	root.add_child(room)
	current_scene = room
	room.set_guards_active(false)
	var player: CharacterBody2D = room.get_node("Player")
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	player.aim.rotation = -0.4
	camera.force_update_scroll()
	await _ticks(10)
	await _save_forest("forest_post")
	await _capture_depth_cases()
	await _capture_loot_facing()
	await _capture_actors()
	root.size = Vector2i(3440, 1440)
	camera.force_update_scroll()
	await _ticks(5)
	await _save_forest("forest_wide")
	root.size = Vector2i(1280, 720)
	camera.force_update_scroll()
	await _ticks(5)
	player.global_position = Vector2(350, 315)
	camera.force_update_scroll()
	await _ticks(30)
	await _save_forest("forest_behind_hut")
	player.global_position = Vector2(520, 440)
	player.aim.look_at(room.get_node("Enemy").global_position)
	camera.force_update_scroll()
	await _ticks(5)
	await _save_forest("forest_cover")
	player.global_position = Vector2(440, 580)
	player.aim.rotation = -PI / 2
	room.get_node("HUD/LootMenu").open_container(room.get_node("LootContainers/HutSupplies"))
	await _ticks(96)
	await _save_forest("forest_loot")
	room.get_node("HUD/LootMenu").close_menu()
	room.free()
	await _ticks(3)
	var base: Control = load("res://scenes/base.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await _ticks(3)
	await _save_forest("forest_base_entry")
	print("Visual captures saved: %s post, wide, behind_hut, cover, loot, base_entry" % "dusk")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _frame_image() -> Image:
	await _ticks(2)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _capture_depth_cases() -> void:
	var player: CharacterBody2D = current_scene.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	var initial := player.position
	camera.zoom = Vector2(3, 3)
	player.aim.rotation = 0.0
	for path in ["Dressing/TimberYard/Stump1", "Dressing/TimberYard/Firewood2", "LootContainers/WoodCache", "Obstacles/BackRocks", "Obstacles/SouthRocks"]:
		var prop: Node2D = current_scene.get_node(path)
		var name := str(prop.name)
		var prop_sprite: Sprite2D = prop.get_node("Sprite")
		for in_front in [false, true]:
			player.position = prop.global_position + Vector2(0, 85 if in_front else -85)
			await _ticks(2)
			for tick in range(35):
				player.velocity = Vector2(0, -250 if in_front else 250)
				player.move_and_slide()
				await _ticks(1)
			player.velocity = Vector2.ZERO
			camera.force_update_scroll()
			await _ticks(30)
			await _save_forest("forest_depth_" + name + ("_front" if in_front else "_behind"))
			# Freeze optional fading for the isolated-image sorting comparison.
			# The preceding capture retains the real in-game transparency.
			var fade: Node = prop.get_node_or_null("Occlusion")
			var original_color := prop_sprite.self_modulate
			if fade != null:
				fade.set_process(false)
				prop_sprite.self_modulate.a = 1.0
			# Compare the real composited pixels with each real sprite in isolation.
			# No synthetic colors or duplicated sorting formula in the expected result.
			player.get_node("Aim/BodyVisual/Shadow").hide()
			player.weapon.hide()
			var combined: Image = await _frame_image()
			player.hide()
			var prop_only: Image = await _frame_image()
			prop_sprite.hide()
			var background: Image = await _frame_image()
			player.show()
			var actor_only: Image = await _frame_image()
			prop_sprite.show()
			var body: Sprite2D = player.get_node("Aim/BodyVisual/Sprite")
			var body_rect: Rect2 = body.get_global_transform_with_canvas() * body.get_rect()
			var prop_rect: Rect2 = prop_sprite.get_global_transform_with_canvas() * prop_sprite.get_rect()
			var region := Rect2i(body_rect.intersection(prop_rect)).intersection(Rect2i(Vector2i.ZERO, combined.get_size()))
			var overlap := 0
			var correct := 0
			var prop_image := prop_sprite.texture.get_image()
			var to_prop := prop_sprite.get_global_transform_with_canvas().affine_inverse()
			for y in range(region.position.y, region.end.y):
				for x in range(region.position.x, region.end.x):
					# Alpha fringes legitimately mix a rear actor into the edge. Check
					# ordering on opaque prop texels, retaining the strict color test.
					var uv := (to_prop * Vector2(x + 0.5, y + 0.5) - prop_sprite.get_rect().position) / prop_sprite.get_rect().size
					if prop_sprite.flip_h:
						uv.x = 1.0 - uv.x
					if prop_sprite.flip_v:
						uv.y = 1.0 - uv.y
					var texel := Vector2i((uv * Vector2(prop_image.get_size())).floor())
					if not Rect2i(Vector2i.ZERO, prop_image.get_size()).has_point(texel) or prop_image.get_pixelv(texel).a < 0.98:
						continue
					var bg := background.get_pixel(x, y)
					var actor_color := actor_only.get_pixel(x, y)
					var prop_color := prop_only.get_pixel(x, y)
					if _color_difference(bg, actor_color) > 0.03 and _color_difference(bg, prop_color) > 0.03:
						overlap += 1
						var expected := actor_color if in_front else prop_color
						if _color_difference(combined.get_pixel(x, y), expected) < 0.02:
							correct += 1
			_check(overlap > 8 and correct > overlap * 0.95, "Real sprite depth " + name + (" front" if in_front else " behind") + ": %d/%d overlap pixels" % [correct, overlap])
			player.get_node("Aim/BodyVisual/Shadow").show()
			player.weapon.show()
			prop_sprite.self_modulate = original_color
			if fade != null:
				fade.set_process(true)
	player.position = initial
	camera.zoom = Vector2(0.8, 0.8)
	camera.force_update_scroll()
	await _ticks(3)


func _capture_loot_facing() -> void:
	var player: CharacterBody2D = current_scene.get_node("Player")
	var chest: StaticBody2D = current_scene.get_node("LootContainers/WoodCache")
	var camera: Camera2D = player.get_node("Camera2D")
	var initial := player.position
	var initial_aim: float = player.aim.rotation
	player.global_position = chest.global_position + Vector2(0, 60)
	await _ticks(2)
	for tick in range(24):
		player.velocity = Vector2.UP * 250
		player.move_and_slide()
		await _ticks(1)
	player.velocity = Vector2.ZERO
	camera.zoom = Vector2(3, 3)
	for looking_up in [true, false]:
		player.aim.rotation = -PI / 2 if looking_up else PI / 2
		camera.force_update_scroll()
		await _ticks(5)
		await _save_forest("forest_loot_facing_" + ("up" if looking_up else "down"))
		_check(chest.get_node("Hint").visible == looking_up, "Rendered southern chest contact shows E only while facing up toward its art")
	player.position = initial
	player.aim.rotation = initial_aim
	camera.zoom = Vector2(0.8, 0.8)
	camera.force_update_scroll()
	await _ticks(3)


func _color_difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


func _save_forest(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + filename.replace("forest_", "dusk" + "_") + ".png")


func _capture_actors() -> void:
	var player: CharacterBody2D = current_scene.get_node("Player")
	var enemy: CharacterBody2D = current_scene.get_node("Enemy")
	var camera: Camera2D = player.get_node("Camera2D")
	var original_player_position := player.position
	var original_enemy_position := enemy.position
	player.position = Vector2(700, 730)
	enemy.position = Vector2(810, 730)
	camera.zoom = Vector2(3, 3)
	for facing in [0.0, PI / 2, -PI / 2, -PI / 4, -PI * 3 / 4, PI / 4, PI * 3 / 4]:
		player.aim.rotation = facing
		enemy.aim.rotation = facing
		enemy.get_node("Aim/BodyVisual").sync_actor()
		camera.force_update_scroll()
		await _ticks(4)
		await _save_forest("forest_actors_" + str(int(rad_to_deg(facing))))
	# Capture the reported pairing: standing player next to a real dead guard.
	player.aim.rotation = 0.0
	enemy.aim.rotation = 0.0
	enemy.take_damage(1000)
	# The capture room disables guard processing, including its hit flash timer.
	enemy.get_node("Aim/BodyVisual").advance(0.2)
	await _ticks(4)
	await _save_forest("forest_contact_shadows")
	player.position = original_player_position
	enemy.position = original_enemy_position
	camera.zoom = Vector2(0.8, 0.8)
	camera.force_update_scroll()
	await _ticks(4)
