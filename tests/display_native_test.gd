extends SceneTree
## Actual Windows fullscreen transitions. Run with Compatibility, not headless.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _shortcut(code: Key, alt: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.alt_pressed = alt
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _run() -> void:
	var settings: Node = root.get_node("DisplaySettings")
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	var scene_id := yard.get_instance_id()
	yard.get_node("Player").set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	await _ticks(5)
	var original_size := root.size
	var original_position := root.position
	_shortcut(KEY_F11)
	await _ticks(10)
	_check(root.mode == Window.MODE_FULLSCREEN, "F11 enters native borderless fullscreen")
	var screen := DisplayServer.screen_get_size(root.current_screen)
	_check(absi(root.size.x - screen.x) <= 1 and absi(root.size.y - screen.y) <= 1, "Fullscreen adopts native monitor pixels without changing video mode")
	var menu: Control = yard.get_node("HUD/PauseMenu")
	menu.set_open(true)
	await _ticks(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png("res://artifacts/fullscreen_native.png") == OK, "Native fullscreen capture saved")
	_shortcut(KEY_ENTER, true)
	await _ticks(10)
	_check(root.mode == Window.MODE_WINDOWED and paused and menu.visible and current_scene.get_instance_id() == scene_id, "Alt+Enter works in pause without restarting or closing help")
	_check(root.size == original_size, "Leaving fullscreen restores prior window size")
	settings.set_mode(Window.MODE_EXCLUSIVE_FULLSCREEN)
	await _ticks(10)
	_check(root.mode == Window.MODE_EXCLUSIVE_FULLSCREEN, "Exclusive fullscreen mode is available")
	settings.set_mode(Window.MODE_WINDOWED)
	await _ticks(10)
	_check(root.mode == Window.MODE_WINDOWED and root.size == original_size, "Leaving exclusive mode also restores window")
	root.mode = Window.MODE_MAXIMIZED
	await _ticks(6)
	_shortcut(KEY_F11)
	await _ticks(8)
	_shortcut(KEY_F11)
	await _ticks(8)
	_check(root.mode == Window.MODE_MAXIMIZED, "Toggle restores a previously maximized window")
	settings.set_window_size(original_size)
	root.position = original_position
	menu.set_open(false)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
