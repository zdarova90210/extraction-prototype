extends SceneTree

const CASES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 800),
	Vector2i(1920, 1200), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(1280, 1024),
]
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


func _run() -> void:
	var settings: Node = root.get_node("DisplaySettings")
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	yard.get_node("Player").set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var menu: Control = yard.get_node("HUD/PauseMenu")
	var readout: Control = yard.get_node("HUD/WeaponReadout")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Canvas rendering expands to aspect ratio without changing base coordinates")
	_check(InputMap.has_action("toggle_fullscreen") and InputMap.action_get_events("toggle_fullscreen").size() == 2, "Fullscreen has F11 and Alt+Enter bindings")
	_check(settings.fit_window_size(Vector2i(-100, 999999)).x >= 960 and settings.fit_window_size(Vector2i(-100, 999999)).y <= settings.usable_area().size.y, "Saved window dimensions are constrained to usable monitor area")
	menu.set_open(true)
	for size in CASES:
		root.size = size
		await _ticks(3)
		var logical: Vector2 = root.get_visible_rect().size
		var scale: Vector2 = root.get_stretch_transform().get_scale()
		_check(absf(scale.x - scale.y) < 0.002 and logical.x >= 1279 and logical.y >= 719, "Uniform scaling and complete base field: %s" % size)
		var bounds := readout.get_global_rect()
		_check(absf(logical.y - bounds.end.y - 22) < 1 and bounds.position.x >= 20 and bounds.end.x < logical.x, "Weapon HUD stays inside bottom corner: %s" % size)
		var panel: Control = menu.get_node("Center/Panel")
		var panel_rect := panel.get_global_rect()
		_check(panel_rect.position.x >= 0 and panel_rect.position.y >= 0 and panel_rect.end.x <= logical.x + 1 and panel_rect.end.y <= logical.y + 1, "Pause and display settings fit entirely: %s" % size)
		var pointer := InputEventMouseMotion.new()
		pointer.position = logical * Vector2(0.65, 0.6)
		root.push_input(pointer, true)
		# Cursor is intentionally paused; resume synchronizes it with the viewport.
		menu.set_open(false)
		await _ticks(1)
		root.push_input(pointer, true)
		_check(yard.get_node("HUD/AimCursor")._cursor_position.distance_to(pointer.position) < 0.1, "Aiming feedback uses viewport coordinates: %s" % size)
		menu.set_open(true)
	root.size = Vector2i(1280, 720)
	await _ticks(2)
	menu.set_open(false)
	# Persist in isolated check.ps1 AppData, then create a fresh settings instance.
	settings.set_window_size(Vector2i(1366, 768))
	OS.set_environment("EXTRACTION_TEST_DISPLAY", "0")
	settings.save_preferences()
	var saved := ConfigFile.new()
	_check(saved.load(settings.CONFIG_PATH) == OK and saved.get_value("display", "window_size") == Vector2i(1366, 768), "Display preferences serialize independently of gameplay")
	var reloaded: Node = load("res://scripts/display_settings.gd").new()
	root.add_child(reloaded)
	_check(reloaded.windowed_size == Vector2i(1366, 768), "Fresh settings instance restores saved window size")
	reloaded.free()
	# Valid config syntax, invalid data types: use defaults rather than breaking startup.
	saved.set_value("display", "window_size", "invalid")
	saved.set_value("display", "mode", "invalid")
	saved.save(settings.CONFIG_PATH)
	var fallback: Node = load("res://scripts/display_settings.gd").new()
	root.add_child(fallback)
	_check(fallback.windowed_size == Vector2i(1280, 720) and fallback.current_mode() == Window.MODE_WINDOWED, "Invalid saved values safely fall back to windowed defaults")
	fallback.free()
	OS.set_environment("EXTRACTION_TEST_DISPLAY", "1")
	settings.set_window_size(Vector2i(1280, 720))
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
