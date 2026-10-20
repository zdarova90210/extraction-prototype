extends Node
## Native window preferences survive scene restarts; no gameplay data is saved here.

signal changed

const CONFIG_PATH := "user://display.cfg"
const MIN_WINDOW := Vector2i(960, 540)
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160),
]

var windowed_size := Vector2i(1280, 720)
var _windowed_position := Vector2i.ZERO
var _return_maximized: bool = false
var _last_fullscreen: int = Window.MODE_FULLSCREEN
var _applying: bool = false
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(save_preferences)
	add_child(_save_timer)
	var preferred_mode := Window.MODE_WINDOWED
	if _persistence_enabled():
		var config := ConfigFile.new()
		if config.load(CONFIG_PATH) == OK:
			var size_value: Variant = config.get_value("display", "window_size", windowed_size)
			if size_value is Vector2i:
				windowed_size = size_value
			var mode_value: Variant = config.get_value("display", "mode", 0)
			if mode_value is int and mode_value in [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
				preferred_mode = mode_value
			var last_value: Variant = config.get_value("display", "last_fullscreen", Window.MODE_FULLSCREEN)
			if last_value is int and last_value in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
				_last_fullscreen = last_value
	if not Engine.is_embedded_in_editor():
		var window := get_window()
		window.min_size = MIN_WINDOW
		windowed_size = fit_window_size(windowed_size)
		_windowed_position = _centered_position(windowed_size)
		_applying = true
		window.mode = Window.MODE_WINDOWED
		window.size = windowed_size
		window.position = _windowed_position
		_applying = false
		if preferred_mode != Window.MODE_WINDOWED:
			set_mode(preferred_mode)
	get_window().size_changed.connect(_on_size_changed)


func _persistence_enabled() -> bool:
	return OS.get_environment("EXTRACTION_TEST_DISPLAY") != "1" and not Engine.is_embedded_in_editor()


func usable_area() -> Rect2i:
	var area := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	# Headless validation has no physical monitor.
	return area if area.size.x > 0 and area.size.y > 0 else Rect2i(0, 0, 1920, 1080)


func fit_window_size(size: Vector2i) -> Vector2i:
	var maximum := (usable_area().size - Vector2i(48, 80)).max(MIN_WINDOW)
	return size.clamp(MIN_WINDOW, maximum)


func _centered_position(size: Vector2i) -> Vector2i:
	var area := usable_area()
	return area.position + (area.size - size) / 2


func current_mode() -> int:
	var mode := get_window().mode
	return mode if mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_WINDOWED


func set_mode(mode: int) -> void:
	if Engine.is_embedded_in_editor() or mode not in [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		return
	var window := get_window()
	if current_mode() == mode:
		return
	var restore_size := fit_window_size(windowed_size)
	var restore_position := _windowed_position
	_applying = true
	if mode != Window.MODE_WINDOWED:
		if current_mode() == Window.MODE_WINDOWED:
			_return_maximized = window.mode == Window.MODE_MAXIMIZED
			if not _return_maximized:
				windowed_size = window.size
				_windowed_position = window.position
		_last_fullscreen = mode
		if mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		else:
			window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = restore_size
		var area := usable_area()
		window.position = restore_position.clamp(area.position, area.end - restore_size)
		if _return_maximized:
			window.mode = Window.MODE_MAXIMIZED
	_applying = false
	save_preferences()
	changed.emit()


func set_window_size(size: Vector2i) -> void:
	if Engine.is_embedded_in_editor() or current_mode() != Window.MODE_WINDOWED:
		return
	_applying = true
	_return_maximized = false
	windowed_size = fit_window_size(size)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = windowed_size
	_windowed_position = _centered_position(windowed_size)
	get_window().position = _windowed_position
	_applying = false
	save_preferences()
	changed.emit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		set_mode(_last_fullscreen if current_mode() == Window.MODE_WINDOWED else Window.MODE_WINDOWED)
		get_viewport().set_input_as_handled()


func _on_size_changed() -> void:
	if not _applying and get_window().mode == Window.MODE_WINDOWED:
		windowed_size = get_window().size
		_windowed_position = get_window().position
		_save_timer.start()
	changed.emit()


func save_preferences() -> void:
	if not _persistence_enabled():
		return
	var config := ConfigFile.new()
	config.set_value("display", "mode", current_mode())
	config.set_value("display", "window_size", windowed_size)
	config.set_value("display", "last_fullscreen", _last_fullscreen)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Cannot save display preferences: " + error_string(error))
