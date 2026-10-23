extends "res://tests/loot_slots_test.gd"
## Captures actual rig states; PNGs are verification artifacts, not generated assets.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room := load("res://tests/character_lab/character_motion_lab.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await _ticks(5)
	var actor: CharacterBody2D = room.actor
	actor.input_enabled = false
	var visual: Node2D = actor.visual
	visual.set_physics_process(false)
	for pose in ["lowered", "raising", "aim", "step_a", "step_b", "shot", "sneak_step", "sneak_contact"]:
		var sneak: bool = pose.begins_with("sneak_")
		actor.set_sneaking(sneak)
		room.get_node("UI/Panel/Sneak").set_pressed_no_signal(sneak)
		visual.reset_pose()
		visual.aim_blend = 0.5 if pose == "raising" else (0.0 if pose == "lowered" else 1.0)
		if pose == "step_a" or pose == "sneak_step":
			visual.gait_blend = 1.0
			visual.phase = PI / 2.0
		elif pose == "step_b" or pose == "sneak_contact":
			visual.gait_blend = 1.0
			visual.phase = PI * 1.5
		visual.apply_pose()
		if pose == "shot":
			actor.fire_current_pose()
		await _ticks(2)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://artifacts/character_lab_" + pose + ".png") == OK)
	# A small animation assembled from the same rendered model, not a separate drawing.
	actor.set_sneaking(false)
	visual.reset_pose()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/character_lab_frames"))
	var preview := SubViewport.new()
	preview.size = Vector2i(320, 336)
	preview.disable_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(preview)
	var background := ColorRect.new()
	background.size = Vector2(320, 336)
	background.color = Color("20272a")
	preview.add_child(background)
	var crop := AtlasTexture.new()
	crop.atlas = visual.get_node("Pixels").get_texture()
	crop.region = Rect2(16, 24, 96, 88)
	var drawing := TextureRect.new()
	drawing.position = Vector2(16, 40)
	drawing.size = Vector2(288, 264)
	drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawing.texture = crop
	drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	drawing.material = material
	preview.add_child(drawing)
	var caption := Label.new()
	caption.position = Vector2(18, 12)
	caption.add_theme_font_size_override("font_size", 16)
	preview.add_child(caption)
	for frame in 64:
		visual.gait_blend = 1.0
		visual.aim_blend = clampf((float(frame) - 12.0) / 12.0, 0.0, 1.0)
		if frame > 48:
			visual.aim_blend = 1.0 - (frame - 48.0) / 15.0
		visual.phase = frame * TAU / 16.0
		visual.recoil = maxf(0.0, 1.0 - (frame - 36.0) / 3.0) if frame >= 36 and frame < 40 else 0.0
		visual.flash_remaining = 0.05 if frame == 36 else 0.0
		visual.apply_pose()
		caption.text = "Ходьба · оружие опущено" if frame < 12 else ("Подъём оружия" if frame < 24 else ("Выстрел / отдача" if frame >= 36 and frame < 40 else ("Опускание оружия" if frame > 48 else "Ходьба · прицеливание")))
		await _ticks(1)
		await RenderingServer.frame_post_draw
		assert(preview.get_texture().get_image().save_png("res://artifacts/character_lab_frames/%03d.png" % frame) == OK)
	preview.queue_free()
	await _capture_gait_comparison(actor, visual)
	room.free()
	await _ticks(2)
	print("Visual captures saved: character_lab poses, both gaits and a timed comparison")
	quit(0)

func _capture_gait_comparison(actor: CharacterBody2D, walking: Node2D) -> void:
	var sneaking: Node2D = load("res://tests/character_lab/character_visual.tscn").instantiate()
	sneaking.position = Vector2(-2000, -2000)
	root.add_child(sneaking)
	sneaking.set_physics_process(false)
	sneaking.sneaking = true
	sneaking.reset_pose()
	walking.sneaking = false
	walking.reset_pose()
	var stage := SubViewport.new()
	stage.size = Vector2i(640, 336)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(640, 336)
	background.color = Color("20272a")
	stage.add_child(background)
	for index in 2:
		var model := walking if index == 0 else sneaking
		var crop := AtlasTexture.new()
		crop.atlas = model.get_node("Pixels").get_texture()
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
		var label := Label.new()
		label.position = Vector2(18 + index * 320, 12)
		label.text = "Обычная ходьба" if index == 0 else "Подкрадывание"
		label.add_theme_font_size_override("font_size", 18)
		stage.add_child(label)
		# Fixed ticks make the change in crown height readable without moving the floor.
		for height in [88.0, 280.0]:
			var tick := Line2D.new()
			tick.points = PackedVector2Array([Vector2(22 + index * 320, height), Vector2(36 + index * 320, height)])
			tick.width = 1.0
			tick.default_color = Color("607071")
			stage.add_child(tick)
	var directory := "res://artifacts/character_lab_gaits/"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	# Default speeds give five walking cycles and three sneaking cycles in the
	# same interval. Playback timing comes from the actor, not a slowed GIF guess.
	var seconds: float = walking.walk_gait.stride_distance / actor.move_speed * 5.0
	const FRAME_COUNT := 85
	var timing := FileAccess.open(directory + "timing.json", FileAccess.WRITE)
	assert(timing != null)
	timing.store_string(JSON.stringify({"frame_duration_ms": seconds * 1000.0 / FRAME_COUNT, "frame_count": FRAME_COUNT}))
	timing.close()
	for frame in FRAME_COUNT:
		var elapsed := seconds * frame / FRAME_COUNT
		walking.gait_blend = 1.0
		walking.aim_blend = 1.0
		walking.phase = elapsed * actor.move_speed / walking.walk_gait.stride_distance * TAU
		walking.apply_pose()
		sneaking.gait_blend = 1.0
		sneaking.aim_blend = 1.0
		sneaking.phase = elapsed * actor.move_speed * actor.sneak_speed_multiplier / sneaking.sneak_gait.stride_distance * TAU
		sneaking.apply_pose()
		await _ticks(1)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	stage.queue_free()
	sneaking.queue_free()
