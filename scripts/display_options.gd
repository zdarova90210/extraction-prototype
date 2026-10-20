extends VBoxContainer

@onready var settings: Node = get_node("/root/DisplaySettings")
@onready var mode_choice: OptionButton = $Mode/Choice
@onready var size_choice: OptionButton = $Size/Choice
var _sizes: Array[Vector2i] = []


func _ready() -> void:
	mode_choice.add_item("В окне", Window.MODE_WINDOWED)
	mode_choice.add_item("Без рамки на весь экран", Window.MODE_FULLSCREEN)
	mode_choice.add_item("Эксклюзивный полный экран", Window.MODE_EXCLUSIVE_FULLSCREEN)
	mode_choice.item_selected.connect(_on_mode_selected)
	size_choice.item_selected.connect(_on_size_selected)
	settings.changed.connect(_refresh)
	_refresh()


func _on_mode_selected(index: int) -> void:
	settings.set_mode(mode_choice.get_item_id(index))


func _on_size_selected(index: int) -> void:
	settings.set_window_size(_sizes[index])


func _refresh() -> void:
	var embedded := Engine.is_embedded_in_editor()
	mode_choice.disabled = embedded
	mode_choice.select(mode_choice.get_item_index(settings.current_mode()))
	size_choice.disabled = embedded or settings.current_mode() != Window.MODE_WINDOWED
	_sizes.clear()
	size_choice.clear()
	for size: Vector2i in settings.WINDOW_SIZES:
		if settings.fit_window_size(size) == size:
			_sizes.append(size)
	var selected_size: Vector2i = settings.windowed_size
	if not selected_size in _sizes:
		_sizes.append(selected_size)
	for size in _sizes:
		size_choice.add_item("%d × %d" % [size.x, size.y])
	size_choice.select(_sizes.find(selected_size))
	$Hint.text = "Для полного экрана запустите игру отдельным окном." if embedded else "F11 / Alt+Enter · полный экран в разрешении монитора"
