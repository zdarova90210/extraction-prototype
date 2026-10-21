extends SceneTree
## Full-resolution offscreen renders avoid depending on the host monitor's size.

const CASES = [
	[Vector2i(1280, 800), Vector2i(1280, 800)],
	[Vector2i(3440, 1440), Vector2i(1720, 720)],
	[Vector2i(3840, 2160), Vector2i(1280, 720)],
]


func _initialize() -> void:
	_run.call_deferred()


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _save(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png("res://artifacts/" + name + ".png")
	if error != OK:
		push_error("Cannot save resolution capture: " + name)
		quit(1)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size_2d_override_stretch = true
	root.add_child(viewport)
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	viewport.add_child(yard)
	yard.get_node("Player").set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var camera: Camera2D = yard.get_node("Player/Camera2D")
	camera.position_smoothing_enabled = false
	for entry in CASES:
		viewport.size = entry[0]
		viewport.size_2d_override = entry[1]
		camera.reset_smoothing()
		camera.force_update_scroll()
		await _ticks(4)
		var tag := "%dx%d" % [entry[0].x, entry[0].y]
		await _save(viewport, "display_" + tag)
		yard.get_node("HUD/PauseMenu").set_open(true)
		await _ticks(2)
		await _save(viewport, "display_menu_" + tag)
		yard.get_node("HUD/PauseMenu").set_open(false)
	print("Display captures saved: 1280x800, 3440x1440, 3840x2160, including menus")
	quit()
