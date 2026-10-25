extends "res://tests/loot_slots_test.gd"
## Native review of the selected outfit, plus the real guard's removed laser.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := SubViewport.new()
	stage.size = Vector2i(1280, 672)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(1280, 672)
	background.color = Color("20272a")
	stage.add_child(background)
	var models: Array[Node2D] = []
	var captions := ["Вправо", "Вниз-вправо", "Вниз", "Вниз-влево", "Влево", "Вверх-влево", "Вверх", "Вверх-вправо"]
	for index in 8:
		var visual: Node2D = load("res://scenes/characters/watchman/visual.tscn").instantiate()
		visual.position = Vector2(-2000, -2000)
		root.add_child(visual)
		visual.set_physics_process(false)
		visual.direction_override = index
		visual.reset_pose()
		models.append(visual)
		var crop := AtlasTexture.new()
		crop.atlas = visual.get_node("Pixels").get_texture()
		crop.region = Rect2(16, 24, 96, 88)
		var drawing := TextureRect.new()
		drawing.position = Vector2((index % 4) * 320 + 16, (index / 4) * 336 + 40)
		drawing.size = Vector2(288, 264)
		drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drawing.texture = crop
		drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		drawing.material = material
		stage.add_child(drawing)
		var label := Label.new()
		label.position = drawing.position + Vector2(0, -28)
		label.text = captions[index]
		stage.add_child(label)
	for edge in [-22.0, 0.0, 22.0]:
		for model in models:
			model.aim_angle = model.direction_override * PI / 4.0 + deg_to_rad(edge)
			model.apply_pose()
		await _ticks(2)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png("res://artifacts/watchman_hold_%d.png" % roundi(edge)) == OK)
		for model in models:
			var painted: Image = model.get_node("Pixels").get_texture().get_image()
			var bounds := painted.get_used_rect()
			_check(bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < 128 and bounds.end.y < 128, "Watchman is not clipped by pose viewport: view %d, edge %.0f" % [model.direction_override, edge])
	for gait in ["walk", "sneak"]:
		var directory: String = "res://artifacts/watchman_" + gait + "_frames/"
		assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
		for frame in 28:
			for model in models:
				model.aim_angle = model.direction_override * PI / 4.0 + deg_to_rad(22.0) * sin(frame * TAU / 28.0)
				model.gait_blend = 1.0
				model.sneak_blend = 1.0 if gait == "sneak" else 0.0
				model.motion_vector = Vector2.from_angle(model.aim_angle)
				model.phase = frame * TAU / 14.0
				model.recoil = 0.0
				model.apply_pose()
			await _ticks(1)
			await RenderingServer.frame_post_draw
			assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	for model in models:
		model.free()
	stage.free()
	await _capture_ready_guard()
	print("Visual captures saved: watchman directions, sectors, gaits and forest readiness without laser")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _capture_ready_guard() -> void:
	var room: Node2D = load("res://scenes/forest_dusk.tscn").instantiate()
	room.play_start_audio = false
	root.add_child(room)
	current_scene = room
	room.set_guards_active(false)
	var player: CharacterBody2D = room.player
	var guard: CharacterBody2D = room.get_node("Enemy")
	guard.process_mode = Node.PROCESS_MODE_INHERIT
	player.set_physics_process(false)
	guard.set_physics_process(false)
	player.position = Vector2(700, 730)
	guard.position = Vector2(850, 730)
	guard.behavior_enabled = true
	guard.aim.rotation = PI
	guard.body_visual.sync_actor()
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.force_update_scroll()
	guard.state = guard.State.PATROL
	guard.queue_redraw()
	await _ticks(3)
	await RenderingServer.frame_post_draw
	var before: Image = root.get_texture().get_image()
	var transform := root.get_canvas_transform()
	# Positive control: the image comparison must notice the removed kind of beam.
	var control := Line2D.new()
	control.points = PackedVector2Array([guard.aim.global_position, player.aim.global_position])
	control.width = 1.5
	control.antialiased = true
	control.default_color = Color(0.95, 0.36, 0.23, 0.7)
	control.z_index = 100
	room.add_child(control)
	await _ticks(2)
	await RenderingServer.frame_post_draw
	_check(_ray_difference(before, root.get_texture().get_image(), transform, guard.aim.global_position) > 0, "Laser image regression detects a deliberately drawn control beam")
	control.free()
	guard.state = guard.State.AIM
	guard._preparation = 0.5
	guard.last_known_position = player.position
	guard._prepared_position = player.position
	guard._desired_angle = PI
	guard._time_without_sight = 0.0
	guard._physics_process(0.0)
	await _ticks(2)
	await RenderingServer.frame_post_draw
	var after: Image = root.get_texture().get_image()
	_check(_ray_difference(before, after, transform, guard.aim.global_position) == 0, "Preparing real watchman draws no laser along the former warning ray")
	_check(guard.state == guard.State.AIM and guard._sees_target and is_equal_approx(guard._preparation, 0.5) and guard.aim_duration == 0.7 and guard.turn_speed == 540.0, "Visible target stays in timed preparation without changing turn or attack delay")
	assert(after.save_png("res://artifacts/forest_watchman_ready.png") == OK)
	room.free()
	await _ticks(2)

func _ray_difference(before: Image, after: Image, transform: Transform2D, origin: Vector2) -> int:
	var changed := 0
	for distance in range(65, 125):
		var point := Vector2i((transform * (origin + Vector2.LEFT * distance)).round())
		# The 0.8 camera scale can put a narrow beam between pixel centres.
		for offset in range(-2, 3):
			var sample := point + Vector2i(0, offset)
			if before.get_pixelv(sample) != after.get_pixelv(sample):
				changed += 1
	return changed
