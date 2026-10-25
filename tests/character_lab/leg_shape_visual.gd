extends "res://tests/loot_slots_test.gd"
## Native review of trouser shape and actual rendered colour across directions.

func _run() -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(1024, 896)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(stage.size)
	background.color = Color("20272a")
	stage.add_child(background)
	var models: Array[Node2D] = []
	for actor in 2:
		for view in 8:
			var visual: Node2D = load("res://scenes/characters/" + ("character_visual.tscn" if actor == 0 else "watchman/visual.tscn")).instantiate()
			visual.position = Vector2(-2000, -2000)
			root.add_child(visual)
			visual.set_physics_process(false)
			visual.direction_override = view
			visual.reset_pose()
			models.append(visual)
			if view in [1, 2, 3, 5, 7]:
				_check_leg_paths(visual)
				_check_foot_lanes(visual)
				_check_cloth_volume(visual)
	await _check_palette(models)
	for stance in ["idle", "walk_contact", "walk_return", "sneak_contact", "sneak_return"]:
		for node in stage.get_children():
			if node != background:
				node.free()
		for index in models.size():
			var visual: Node2D = models[index]
			var view: int = visual.direction_override
			visual.gait_blend = 0.0 if stance == "idle" else 1.0
			visual.sneak_blend = 1.0 if stance.begins_with("sneak") else 0.0
			visual.motion_vector = Vector2.from_angle(view * PI / 4.0)
			visual._motion_direction = 1.0
			visual.phase = PI * (1.55 if stance.ends_with("return") else 0.4)
			visual.apply_pose()
			await _ticks(2)
			await RenderingServer.frame_post_draw
			var painted: Image = visual.get_node("Pixels").get_texture().get_image()
			var bounds := painted.get_used_rect()
			_check(bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < 128 and bounds.end.y < 128, "Pose remains inside its viewport: %s, view %d, %s" % ["player" if index < 8 else "watchman", view, stance])
			_add_pose(stage, painted, index % 4, index / 4, ("Игрок" if index < 8 else "Сторож") + " · " + ["→ ориентир", "↘", "↓", "↙", "←", "↖", "↑", "↗"][view])
		await _ticks(2)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png("res://artifacts/diagonal_legs_%s.png" % stance) == OK)
	for visual in models:
		visual.free()
	stage.free()
	await _ticks(2)
	print("Visual captures saved: all eight trouser views, shared front legs, both outfits and gaits")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check_leg_paths(visual: Node2D) -> void:
	var view := "south" if visual.direction_override == 2 else ("southeast" if visual.direction_override in [1, 3] else "northeast")
	for side in ["near", "far"]:
		var leg: Node2D = visual.near_leg if side == "near" else visual.far_leg
		_check(leg.scene_file_path == "res://scenes/characters/legs/%s_%s.tscn" % [view, side] and leg.get_node("Thigh").texture.resource_path == "res://assets/art/characters/legs/work_trousers.png", "Both outfits use shared prepared leg art: %s, view %d, %s" % [visual.scene_file_path, visual.direction_override, side])

func _check_foot_lanes(visual: Node2D) -> void:
	var mirror: float = signf(visual.model.to_local(visual.near_leg.global_position).x - visual.model.to_local(visual.far_leg.global_position).x)
	var minimum_knee := INF
	var minimum_ankle := INF
	for sneak in [0.0, 0.5, 1.0]:
		visual.sneak_blend = sneak
		for gait in [0.0, 0.5, 1.0]:
			visual.gait_blend = gait
			for movement in 8:
				visual.motion_vector = Vector2.from_angle(movement * PI / 4.0)
				visual._motion_direction = -1.0 if visual.motion_vector.dot(Vector2.from_angle(visual.direction_override * PI / 4.0)) < -0.1 else 1.0
				for frame in 64:
					visual.phase = frame * TAU / 64.0
					visual.apply_pose()
					var knee_delta: Vector2 = visual.model.to_local(visual.near_shin.global_position) - visual.model.to_local(visual.far_shin.global_position)
					var ankle_delta: Vector2 = visual.model.to_local(visual.near_foot.global_position) - visual.model.to_local(visual.far_foot.global_position)
					minimum_knee = minf(minimum_knee, knee_delta.x * mirror)
					minimum_ankle = minf(minimum_ankle, ankle_delta.x * mirror)
	_check(minimum_knee > 2.0 and minimum_ankle > 2.0, "Prepared knees and ankles keep their lanes throughout travel, gait changes and stopping: %s, view %d, knee %.2f, ankle %.2f" % [visual.scene_file_path, visual.direction_override, minimum_knee, minimum_ankle])
	visual.reset_pose()

func _check_cloth_volume(visual: Node2D) -> void:
	# Guard against the previously thin source, not a claim of correct anatomy.
	# These minima belong to the current 27-pixel work trousers, not all enemies.
	for leg: Node2D in [visual.near_leg, visual.far_leg]:
		var mesh: Polygon2D = leg.get_node("Thigh")
		var source: Image = mesh.texture.get_image()
		var start := Vector2i(mesh.uv[0])
		var width := roundi(mesh.uv[1].x - mesh.uv[0].x)
		var thigh := _cloth_width(source, start + Vector2i(0, 7), width, 7)
		var calf := _cloth_width(source, start + Vector2i(0, 18), width, 5)
		_check(thigh >= 7.0 and calf >= 6.0, "Prepared trouser cloth retains readable native width: %s, view %d, %s, thigh %.1f, calf %.1f" % [visual.scene_file_path, visual.direction_override, leg.name, thigh, calf])

func _cloth_width(source: Image, start: Vector2i, width: int, rows: int) -> float:
	var filled := 0
	for y in rows:
		for x in width:
			if source.get_pixelv(start + Vector2i(x, y)).a >= 0.6:
				filled += 1
	return float(filled) / rows

func _check_palette(models: Array[Node2D]) -> void:
	for actor in 2:
		var reference := Vector3.ZERO
		var minimum := INF
		var maximum := 0.0
		for view in 8:
			var tone: Vector3 = await _cloth_tone(models[actor * 8 + view])
			if view == 0:
				reference = tone
			var light := tone.dot(Vector3(0.2126, 0.7152, 0.0722))
			var reference_light := reference.dot(Vector3(0.2126, 0.7152, 0.0722))
			minimum = minf(minimum, light)
			maximum = maxf(maximum, light)
			var chroma_error := (tone / maxf(light, 0.01)).distance_to(reference / maxf(reference_light, 0.01))
			_check(absf(light - reference_light) <= 0.065 and chroma_error <= 0.24, "Rendered cloth keeps the side-view colour family: actor %d, view %d, light %.3f (side %.3f), chroma %.3f" % [actor, view, light, reference_light, chroma_error])
		_check(maximum - minimum <= 0.08, "Turning does not switch between light and dark trousers: actor %d, range %.3f" % [actor, maximum - minimum])

func _cloth_tone(visual: Node2D) -> Vector3:
	visual.reset_pose()
	visual.upper.hide()
	await _ticks(2)
	await RenderingServer.frame_post_draw
	var image: Image = visual.get_node("Pixels").get_texture().get_image()
	visual.upper.show()
	var channels: Array[Array] = [[], [], []]
	for y in range(84, 94):
		for x in range(32, 96):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.7:
				continue
			# Viewport RGB is premultiplied; the final actor shader divides by alpha.
			var tone := Vector3(pixel.r, pixel.g, pixel.b) / pixel.a
			if tone.dot(Vector3(0.2126, 0.7152, 0.0722)) < 0.08:
				continue
			for channel in 3:
				channels[channel].append(tone[channel])
	_check(not channels[0].is_empty(), "Native palette probe contains painted cloth: view %d" % visual.direction_override)
	if channels[0].is_empty():
		return Vector3.ZERO
	var result := Vector3.ZERO
	for channel in 3:
		channels[channel].sort()
		result[channel] = channels[channel][channels[channel].size() / 2]
	return result

func _add_pose(stage: SubViewport, image: Image, column: int, row: int, caption: String) -> void:
	var crop := AtlasTexture.new()
	crop.atlas = ImageTexture.create_from_image(image)
	crop.region = Rect2(16, 24, 96, 88)
	var drawing := TextureRect.new()
	drawing.position = Vector2(column * 256 + 24, row * 224 + 36)
	drawing.size = Vector2(192, 176)
	drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawing.texture = crop
	drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	drawing.material = material
	stage.add_child(drawing)
	var text := Label.new()
	text.position = drawing.position + Vector2(0, -28)
	text.text = caption
	stage.add_child(text)
