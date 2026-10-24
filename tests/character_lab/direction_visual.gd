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
		var visual: Node2D = load("res://scenes/characters/character_visual.tscn").instantiate()
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
	for pose in ["hold", "walk", "sneak", "shot"]:
		for visual in models:
			visual.sneaking = pose == "sneak"
			visual.reset_pose()
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
		_check(_north_sleeves_in_lane(models[6]), "Rendered north sleeve silhouette stays close to the torso: " + pose)
	await _capture_sectors(stage, models)
	var directory := "res://artifacts/character_direction_frames/"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	for frame in 56:
		for visual in models:
			visual.aim_angle = visual.direction_override * PI / 4.0
			visual.sneaking = false
			visual.sneak_blend = 0.0
			visual.gait_blend = 1.0
			visual.recoil = 0.0
			visual.flash_remaining = 0.0
			visual.phase = frame * TAU / 14.0
			visual.apply_pose()
		await _ticks(1)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	await _capture_views(models, [5, 6, 7], "rear", ["Вверх-влево", "Вверх", "Вверх-вправо"])
	await _capture_views(models, [3, 1], "front_diagonal", ["Вниз-влево", "Вниз-вправо"])
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
	room.actor.visual.apply_pose()
	await _ticks(2)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://artifacts/character_lab_direction_room.png") == OK)
	room.free()
	await _ticks(2)
	print("Visual captures saved: eight character directions, holding, gaits, shot and timed frames")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _capture_sectors(stage: SubViewport, models: Array[Node2D]) -> void:
	for degrees in [-22, 0, 22]:
		for visual in models:
			visual.reset_pose()
			visual.aim_angle = visual.direction_override * PI / 4.0 + deg_to_rad(degrees)
			visual.apply_pose()
		await _ticks(2)
		await RenderingServer.frame_post_draw
		assert(stage.get_texture().get_image().save_png("res://artifacts/character_sector_%+d.png" % degrees) == OK)
		await _check_visible_barrels(models, degrees)
		await _check_visible_rear_forearms(models, degrees)
	var directory := "res://artifacts/character_sector_frames/"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var sleeves_in_lane := true
	for frame in 72:
		for visual in models:
			visual.aim_angle = visual.direction_override * PI / 4.0 + deg_to_rad(22.0) * sin(frame * TAU / 72.0)
			visual.apply_pose()
		await _ticks(1)
		await RenderingServer.frame_post_draw
		sleeves_in_lane = sleeves_in_lane and _north_sleeves_in_lane(models[6])
		assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	_check(sleeves_in_lane, "Rendered north sleeves do not flare into wings through a continuous sector sweep")

func _north_sleeves_in_lane(visual: Node2D) -> bool:
	var image: Image = visual.get_node("Pixels").get_texture().get_image()
	# Current rear torso is 25 px wide. A natural bent sleeve adds at most
	# 6.5 px on each side below the shoulder, including the visible elbow turn;
	# the old stretched elbow tails
	# reached far outside this band even with both wrist markers attached.
	for y in range(54, 80):
		for x in range(128):
			if absf(x + 0.5 - 64.0) > 19.0 and image.get_pixel(x, y).a > 0.7:
				return false
	return true

func _check_visible_rear_forearms(models: Array[Node2D], degrees: int) -> void:
	for probe in [[5, "TriggerArm"], [6, "SupportArm"], [6, "TriggerArm"], [7, "TriggerArm"]]:
		var visual: Node2D = models[probe[0]]
		var full: Image = visual.get_node("Pixels").get_texture().get_image()
		var arm: Node2D = visual.upper.get_node(probe[1])
		var whole := arm.has_method("fit_to_grip")
		var forearm: Polygon2D = arm.get_node("Image" if whole else "Forearm/Image")
		var hidden: Array[CanvasItem] = []
		var drawings: Array[Node] = visual.rig.find_children("*", "Polygon2D", true, false)
		drawings.append_array(visual.rig.find_children("*", "Sprite2D", true, false))
		for drawing: CanvasItem in drawings:
			if drawing.visible and drawing != forearm and not drawing.is_ancestor_of(forearm):
				drawing.hide()
				hidden.append(drawing)
		await _ticks(2)
		await RenderingServer.frame_post_draw
		var isolated: Image = visual.get_node("Pixels").get_texture().get_image()
		var total := 0
		var visible := 0
		for y in isolated.get_height():
			for x in isolated.get_width():
				var pixel := isolated.get_pixel(x,y)
				if pixel.a < 0.98:
					continue
				if whole:
					var world: Vector2 = visual.model.to_global(Vector2(x+0.5,y+0.5) - visual.model.position)
					if world.distance_to(arm.get_node("Elbow").global_position) > 4.0:
						continue
				total += 1
				var actual := full.get_pixel(x,y)
				if absf(pixel.r-actual.r) + absf(pixel.g-actual.g) + absf(pixel.b-actual.b) < 0.04:
					visible += 1
		var exposed := visible >= 6 if whole else (total >= 3 and visible >= total * 0.65)
		_check(exposed, "Rear elbow/forearm remains visibly joined beyond the shoulder: view %d, %s, offset %+d, %d/%d texels" % [probe[0], probe[1], degrees, visible, total])
		for drawing in hidden:
			drawing.show()
		await _ticks(2)

func _check_visible_barrels(models: Array[Node2D], degrees: int) -> void:
	# Compare the full rendered actor with an otherwise identical gun-only pass.
	# This catches a barrel hidden by oversized forearms despite correct markers.
	var full: Dictionary = {}
	var hidden: Array[CanvasItem] = []
	for index in [0, 1, 2, 3, 4, 5, 7]:
		var visual: Node2D = models[index]
		full[visual] = visual.get_node("Pixels").get_texture().get_image()
		for part: CanvasItem in [visual.near_leg, visual.far_leg, visual.trigger_arm, visual.support_arm, visual.upper.get_node("Torso")]:
			part.hide()
			hidden.append(part)
		for name in ["TriggerHand", "SupportHand"]:
			var hand: CanvasItem = visual.grip.get_node_or_null(name)
			if hand != null:
				hand.hide()
				hidden.append(hand)
	await _ticks(2)
	await RenderingServer.frame_post_draw
	for index in [0, 1, 2, 3, 4, 5, 7]:
		var visual: Node2D = models[index]
		var isolated: Image = visual.get_node("Pixels").get_texture().get_image()
		var facing := Vector2.from_angle(visual.rig.drawn_weapon_angle)
		# The original side view has separate hand overlays and a one-pixel barrel
		# with partial alpha. Probe beyond the whole hand, including its fingers.
		var side_view: bool = index in [0, 4]
		var threshold: float = visual.grip.get_node("SupportWrist").position.dot(facing) + (8.0 if side_view else 2.0)
		var total := 0
		var visible := 0
		for y in isolated.get_height():
			for x in isolated.get_width():
				var pixel := isolated.get_pixel(x, y)
				if pixel.a < (0.4 if side_view else 0.98):
					continue
				var world: Vector2 = visual.model.to_global(Vector2(x + 0.5, y + 0.5) - visual.model.position)
				if visual.grip.to_local(world).dot(facing) < threshold:
					continue
				total += 1
				var actual: Color = full[visual].get_pixel(x, y)
				if absf(pixel.r - actual.r) + absf(pixel.g - actual.g) + absf(pixel.b - actual.b) < 0.04:
					visible += 1
		_check(total >= 4 and visible >= total * 0.85, "Rendered barrel remains visible beyond hands: view %d, offset %+d, %d/%d texels" % [index, degrees, visible, total])
	for part in hidden:
		part.show()
	await _ticks(2)

func _capture_views(models: Array[Node2D], indices: Array[int], prefix: String, names: Array[String]) -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(indices.size() * 384, 400)
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(stage.size)
	background.color = Color("20272a")
	stage.add_child(background)
	var views: Array[Node2D] = []
	for index in indices.size():
		var visual: Node2D = models[indices[index]]
		views.append(visual)
		visual.reset_pose()
		var crop := AtlasTexture.new()
		crop.atlas = visual.get_node("Pixels").get_texture()
		crop.region = Rect2(16, 24, 96, 88)
		var drawing := TextureRect.new()
		drawing.position = Vector2(index * 384, 40)
		drawing.size = Vector2(384, 352)
		drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drawing.texture = crop
		drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		drawing.material = material
		stage.add_child(drawing)
		var caption := Label.new()
		caption.position = Vector2(18 + index * 384, 12)
		caption.text = names[index]
		caption.add_theme_font_size_override("font_size", 18)
		stage.add_child(caption)
	var directory := "res://artifacts/character_%s_arms_frames/" % prefix
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	for frame in 72:
		for visual: Node2D in views:
			visual.aim_angle = visual.direction_override * PI / 4.0 + deg_to_rad(22.0) * sin(frame * TAU / 72.0)
			visual.advance(1.0 / 30.0)
		await _ticks(1)
		await RenderingServer.frame_post_draw
		var captured := stage.get_texture().get_image()
		assert(captured.save_png(directory + "%03d.png" % frame) == OK)
		if frame in [11, 36]:
			assert(captured.save_png("res://artifacts/character_%s_arms_%s.png" % [prefix, "edge_a" if frame == 11 else "center"]) == OK)
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
				visual.motion_vector = Vector2.from_angle(visual.aim_angle)
				visual.phase = frame * TAU / 14.0 * (0.6 if sneak else 1.0)
				visual.apply_pose()
			await _ticks(1)
			await RenderingServer.frame_post_draw
			assert(stage.get_texture().get_image().save_png(directory + "%03d.png" % frame) == OK)
	stage.queue_free()
	await _ticks(2)
