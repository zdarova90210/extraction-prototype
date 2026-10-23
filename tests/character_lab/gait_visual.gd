extends "res://tests/character_lab/direction_visual.gd"
## Rows = actual travel direction, columns = body view. No generated illustrations.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := SubViewport.new()
	stage.size = Vector2i(2048, 2000)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(stage.size)
	background.color = Color("20272a")
	stage.add_child(background)
	var title := Label.new()
	title.position = Vector2(20, 8)
	title.add_theme_font_size_override("font_size", 22)
	stage.add_child(title)
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	var models: Array[Node2D] = []
	for direction in 8:
		var caption := Label.new()
		caption.text = "Взгляд " + arrows[direction]
		caption.position = Vector2(176 + direction * 232, 44)
		caption.add_theme_font_size_override("font_size", 18)
		stage.add_child(caption)
		caption = Label.new()
		caption.text = "Шаг " + arrows[direction]
		caption.position = Vector2(16, 168 + direction * 232)
		caption.add_theme_font_size_override("font_size", 20)
		stage.add_child(caption)
	for movement in 8:
		for bearing in 8:
			var visual: Node2D = load("res://tests/character_lab/character_visual.tscn").instantiate()
			visual.position = Vector2(-2000, -2000)
			root.add_child(visual)
			visual.set_physics_process(false)
			visual.direction_override = bearing
			visual.reset_pose()
			models.append(visual)
			var crop := AtlasTexture.new()
			crop.atlas = visual.get_node("Pixels").get_texture()
			crop.region = Rect2(16, 24, 96, 88)
			var drawing := TextureRect.new()
			drawing.position = Vector2(176 + bearing * 232, 112 + movement * 232)
			drawing.size = Vector2(192, 176)
			drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			drawing.texture = crop
			drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var material := CanvasItemMaterial.new()
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
			drawing.material = material
			stage.add_child(drawing)
	for sneak in [false, true]:
		var gait_name := "sneak" if sneak else "walk"
		for sample in 4:
			title.text = "%s · столбцы: взгляд · строки: движение · фаза %d/4" % ["Подкрадывание" if sneak else "Ходьба", sample]
			for movement in 8:
				for bearing in 8:
					var visual: Node2D = models[movement * 8 + bearing]
					visual.motion_vector = Vector2.from_angle(movement * PI / 4.0)
					visual._motion_direction = -1.0 if visual.motion_vector.dot(Vector2.from_angle(bearing * PI / 4.0)) < -0.1 else 1.0
					visual.gait_blend = 1.0
					visual.sneak_blend = 1.0 if sneak else 0.0
					visual.aim_blend = 1.0
					visual.phase = sample * TAU / 4.0 * visual._motion_direction
					visual.apply_pose()
			await _ticks(2)
			await RenderingServer.frame_post_draw
			assert(stage.get_texture().get_image().save_png("res://artifacts/character_gait_matrix_%s_%d.png" % [gait_name, sample]) == OK)
	stage.queue_free()
	await _ticks(2)
	await _capture_pair(models, [2, 6], "front_back", ["Вниз", "Вверх"])
	for visual in models:
		visual.queue_free()
	await _ticks(2)
	print("Visual captures saved: 64 look/travel combinations, both gaits, four phases and front/back cycles")
	quit()
