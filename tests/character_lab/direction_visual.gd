extends "res://tests/loot_slots_test.gd"
## Actual eight-view poses and animation rendered by Godot, not an illustrated mockup.

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
	var names := ["Вправо", "Вниз-вправо", "Вниз", "Вниз-влево", "Влево", "Вверх-влево", "Вверх", "Вверх-вправо"]
	for index in 8:
		var visual: Node2D = load("res://tests/character_lab/character_visual.tscn").instantiate()
		visual.position = Vector2(-2000, -2000)
		root.add_child(visual)
		visual.set_physics_process(false)
		visual.direction_override = index
		visual.reset_pose()
		models.append(visual)
		var corner := Vector2((index % 4) * 320, (index / 4) * 336)
		var crop := AtlasTexture.new()
		crop.atlas = visual.get_node("Pixels").get_texture()
		crop.region = Rect2(16, 24, 96, 88)
		var drawing := TextureRect.new()
		drawing.position = corner + Vector2(16, 40)
		drawing.size = Vector2(288, 264)
		drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drawing.texture = crop
		drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		drawing.material = material
		stage.add_child(drawing)
		var caption := Label.new()
		caption.position = corner + Vector2(18, 12)
		caption.text = names[index]
		caption.add_theme_font_size_override("font_size", 18)
		stage.add_child(caption)
	for pose in ["lowered", "raising", "aim", "walk", "sneak", "shot"]:
		for visual in models:
			visual.sneaking = pose == "sneak"
			visual.reset_pose()
			visual.aim_blend = 0.0 if pose == "lowered" else (0.5 if pose == "raising" else 1.0)
			if pose in ["walk", "sneak"]:
				visual.gait_blend = 1.0
				visual.phase = PI * 0.5
			if pose == "shot":
				visual.recoil = 1.0
				visual.flash_remaining = 0.055
			visual.apply_pose()
		await _ticks(2)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png("res://artifacts/character_directions_%s.png" % pose) == OK)
	var directory := "res://artifacts/character_direction_frames/"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	for frame in 56:
		for visual in models:
			visual.sneaking = false
			visual.sneak_blend = 0.0
			visual.gait_blend = 1.0
			visual.aim_blend = 1.0
			visual.recoil = 0.0
			visual.flash_remaining = 0.0
			visual.phase = frame * TAU / 14.0
			visual.apply_pose()
		await _ticks(1)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	await _capture_pair(models, [5, 7], "rear", ["Вверх-влево", "Вверх-вправо"])
	for visual in models:
		visual.queue_free()
	stage.queue_free()
	await _ticks(2)
	var room: Node2D = load("res://tests/character_lab/character_motion_lab.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.actor.input_enabled = false
	room.actor.visual.set_physics_process(false)
	room._preview_direction(2)
	room.get_node("UI/Panel/Direction").select(2)
	room.actor.visual.aim_blend = 1.0
	room.actor.visual.apply_pose()
	await _ticks(2)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://artifacts/character_lab_direction_room.png") == OK)
	room.free()
	await _ticks(2)
	print("Visual captures saved: eight character directions, raises, gaits, shot and timed frames")
	quit()

func _capture_pair(models: Array[Node2D], indices: Array[int], prefix: String, names: Array[String]) -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(640, 336)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(640, 336)
	background.color = Color("20272a")
	stage.add_child(background)
	var views := [models[indices[0]], models[indices[1]]]
	for index in 2:
		var visual: Node2D = views[index]
		visual.reset_pose()
		var crop := AtlasTexture.new()
		crop.atlas = visual.get_node("Pixels").get_texture()
		crop.region = Rect2(16, 24, 96, 88)
		var drawing := TextureRect.new()
		drawing.position = Vector2(16 + index * 320, 40)
		drawing.size = Vector2(288, 264)
		drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drawing.texture = crop
		drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		drawing.material = material
		stage.add_child(drawing)
		var caption := Label.new()
		caption.position = Vector2(18 + index * 320, 12)
		caption.text = names[index]
		caption.add_theme_font_size_override("font_size", 18)
		stage.add_child(caption)
	var directory := "res://artifacts/character_%s_arms_frames/" % prefix
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	for frame in 72:
		for visual: Node2D in views:
			visual.aim_requested = frame >= 12 and frame < 48
			visual.advance(1.0 / 30.0)
		await _ticks(1)
		await RenderingServer.frame_post_draw
		var captured := stage.get_texture().get_image()
		assert(captured.save_png(directory + "%03d.png" % frame) == OK)
		if frame in [11, 36]:
			assert(captured.save_png("res://artifacts/character_%s_arms_%s.png" % [prefix, "lowered" if frame == 11 else "raised"]) == OK)
	# Same rear views in motion: five walk / three sneak cycles in 3.5 seconds
	# at the lab's 120 / 72 px/s. Preserve ground position and native pixel scale.
	for sneak in [false, true]:
		var gait_name := "sneak" if sneak else "walk"
		directory = "res://artifacts/character_%s_%s_frames/" % [prefix, gait_name]
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
		for frame in 70:
			for visual: Node2D in views:
				visual.sneak_blend = 1.0 if sneak else 0.0
				visual.gait_blend = 1.0
				visual.aim_blend = 1.0
				visual.motion_vector = Vector2.from_angle(visual.aim_angle)
				visual.phase = frame * TAU / 14.0 * (0.6 if sneak else 1.0)
				visual.apply_pose()
			await _ticks(1)
			await RenderingServer.frame_post_draw
			assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	stage.queue_free()
	await _ticks(2)
