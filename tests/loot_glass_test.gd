extends "res://tests/loot_slots_test.gd"
## Actual Compatibility renders: live blur, neutral glass, crisp GUI and resize.

const SIZES = [
	[Vector2i(1280, 720), Vector2i(1280, 720)],
	[Vector2i(3440, 1440), Vector2i(1720, 720)],
	[Vector2i(3840, 2160), Vector2i(1280, 720)],
]


func _image(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _range(image: Image, region: Rect2i) -> float:
	var low := 1.0
	var high := 0.0
	for x in range(region.position.x + 16, region.end.x - 16):
		var light := _luminance(image.get_pixel(x, region.get_center().y))
		low = minf(low, light)
		high = maxf(high, light)
	return high - low


func _save(viewport: SubViewport, filename: String) -> void:
	var image := await _image(viewport)
	_check(image.save_png("res://artifacts/" + filename + ".png") == OK, "Glass render saved: " + filename)


func _optical_probe(viewport: SubViewport, room: Node2D, menu: Control) -> void:
	menu._open(null)
	await _ticks(4)
	var panel: Control = menu.get_node("Center/Panel")
	var region := Rect2i(Vector2i(panel.global_position + Vector2(360, 140)), Vector2i(256, 96))
	var fixture := CanvasLayer.new()
	fixture.layer = 0 # World overlay, below the existing HUD layer.
	room.add_child(fixture)
	var stripes: Array[ColorRect] = []
	for index in range(32):
		var stripe := ColorRect.new()
		stripe.position = Vector2(region.position) + Vector2(index * 8, 0)
		stripe.size = Vector2(8, region.size.y)
		stripe.color = Color(0.95, 0.95, 0.95) if index % 2 == 0 else Color(0.03, 0.03, 0.03)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fixture.add_child(stripe)
		stripes.append(stripe)
	menu.close_menu()
	await _ticks(4)
	var before := await _image(viewport)
	menu._open(null)
	await _ticks(4)
	var blurred := await _image(viewport)
	var original_range := _range(before, region)
	var blurred_range := _range(blurred, region)
	_check(original_range > 0.75 and blurred_range < original_range * 0.15, "Glass strongly removes high-frequency world detail")
	_check(before.get_pixel(30, 350).is_equal_approx(blurred.get_pixel(30, 350)), "World outside the window stays sharp and unchanged")
	var right_point := Vector2i(panel.global_position + Vector2(panel.size.x - 24, panel.size.y * 0.5))
	_check(_luminance(blurred.get_pixelv(right_point)) > 0.025, "Backdrop fills the right edge instead of sampling uncopied black pixels")
	for stripe in stripes:
		stripe.color = Color(0.02, 0.02, 0.02)
	await _ticks(4)
	var dark := await _image(viewport)
	var probe_point := region.get_center()
	_check(_luminance(blurred.get_pixelv(probe_point)) - _luminance(dark.get_pixelv(probe_point)) > 0.05, "World changes remain visible through live glass without reopening")
	for stripe in stripes:
		stripe.color = Color.WHITE
	await _ticks(4)
	var bright := await _image(viewport)
	var glass_color := bright.get_pixelv(probe_point)
	_check(_luminance(glass_color) < 0.26, "Very bright backgrounds remain dark enough behind foreground labels")
	_check(absf(glass_color.r - glass_color.g) < 0.01 and absf(glass_color.g - glass_color.b) < 0.01, "Material has no fixed green or biome color cast")
	var slot: Control = menu.backpack_panel.get_node("Grid").get_child(0)
	var motion := InputEventMouseMotion.new()
	motion.position = slot.get_global_rect().get_center()
	viewport.push_input(motion, true)
	await _ticks(2)
	_check(viewport.gui_get_hovered_control() == slot, "Backdrop ignores input so real inventory cells receive hover")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(10, 10)
	viewport.push_input(motion, true)
	fixture.free()
	await _ticks(3)
	await _save(viewport, "loot_glass_backpack")
	menu.close_menu()
	_check(not menu.get_node("Center/Panel/Backdrop/Glass").is_visible_in_tree(), "Closed inventory disables both backdrop passes by visibility")


func _run() -> void:
	for biome in ["forest", "yard"]:
		var viewport := SubViewport.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.size_2d_override_stretch = true
		viewport.size = Vector2i(1280, 720)
		viewport.size_2d_override = Vector2i(1280, 720)
		root.add_child(viewport)
		var path := "res://scenes/forest_dusk.tscn" if biome == "forest" else "res://tests/fixtures/system_yard.tscn"
		var room: Node2D = load(path).instantiate()
		room.play_start_audio = false
		viewport.add_child(room)
		room.set_guards_active(false)
		var player: CharacterBody2D = room.get_node("Player")
		player.set_physics_process(false)
		var camera: Camera2D = player.get_node("Camera2D")
		camera.position_smoothing_enabled = false
		var menu: Control = room.get_node("HUD/LootMenu")
		await _ticks(4)
		if biome == "forest":
			await _optical_probe(viewport, room, menu)
		player.global_position = Vector2(440, 580) if biome == "forest" else Vector2(575, 690)
		var chest: Node2D = room.get_node("LootContainers/HutSupplies" if biome == "forest" else "LootContainers/Supply")
		player.aim.look_at(chest.global_position)
		camera.force_update_scroll()
		await _ticks(3)
		menu.open_container(chest)
		await _ticks(96)
		_check(menu.visible and chest.is_discovered(0), "Real container search remains active in " + biome)
		for sizes in SIZES:
			viewport.size = sizes[0]
			viewport.size_2d_override = sizes[1]
			camera.force_update_scroll()
			await _ticks(5)
			var panel: Control = menu.get_node("Center/Panel")
			_check(Rect2(Vector2.ZERO, Vector2(sizes[1])).encloses(panel.get_global_rect()), "Glass layout fits logical viewport in " + biome)
			var snapshot := await _image(viewport)
			_check(snapshot.get_size() == sizes[0], "Real render uses requested physical resolution")
			await _save(viewport, "loot_glass_%s_%dx%d" % [biome, sizes[0].x, sizes[0].y])
		menu.close_menu()
		room.free()
		viewport.free()
		await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
