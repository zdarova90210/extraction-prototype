extends Control
## Live-world inventory UI. No pauses, item ownership or combat rules live here.

signal toggled(open: bool)

var _player: CharacterBody2D
var _backpack: Inventory
var _interaction: Node
var _container: StaticBody2D
@onready var content: VBoxContainer = $Center/Panel/Margin/Content
@onready var source_panel: VBoxContainer = $Center/Panel/Margin/Content/Columns/Source
@onready var backpack_panel: VBoxContainer = $Center/Panel/Margin/Content/Columns/Backpack
@onready var message: Label = $Center/Panel/Margin/Content/Message


func _ready() -> void:
	content.get_node("Actions/Close").pressed.connect(_on_close_pressed)
	content.get_node("Actions/TakeAll").pressed.connect(_take_all)
	content.get_node("DropZone").drop_validator = _can_discard
	content.get_node("DropZone").item_dropped.connect(_discard)


func bind(player: CharacterBody2D) -> void:
	_player = player
	_backpack = player.get_node("Inventory")
	_interaction = player.get_node("LootInteraction")
	_backpack.changed.connect(_on_changed)
	_interaction.interacted.connect(open_container)
	_player.died.connect(close_menu)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_player) or _player.is_dead:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("inventory"):
		if visible:
			close_menu()
		else:
			_open(null)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("interact"):
		close_menu()
		get_viewport().set_input_as_handled()


func open_container(container: StaticBody2D) -> void:
	if _interaction.can_interact(container):
		_open(container)


func _open(container: StaticBody2D) -> void:
	close_menu()
	_container = container
	if is_instance_valid(_container):
		_container.inventory.changed.connect(_on_changed)
		_container.discovery_changed.connect(_on_changed)
		_container.search_progress_changed.connect(_update_search)
		_container.set_searching(true)
	visible = true
	message.text = "Мир не остановлен. Закройте окно, чтобы двигаться и стрелять."
	_refresh()
	Input.action_release("shoot")
	toggled.emit(true)
	content.get_node("Actions/Close").grab_focus()


func close_menu() -> void:
	if is_instance_valid(_container) and _container.inventory.changed.is_connected(_on_changed):
		_container.inventory.changed.disconnect(_on_changed)
		_container.discovery_changed.disconnect(_on_changed)
		_container.search_progress_changed.disconnect(_update_search)
		_container.set_searching(false)
	_container = null
	if not visible:
		return
	visible = false
	Input.action_release("shoot")
	toggled.emit(false)


func _on_close_pressed() -> void:
	close_menu()
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if visible and source_panel.visible and not _source_available():
		close_menu()


func _on_changed() -> void:
	if visible:
		_refresh()


func _source_available() -> bool:
	return is_instance_valid(_container) and _interaction.can_reach(_container)


func _refresh() -> void:
	source_panel.visible = is_instance_valid(_container)
	content.get_node("Title").text = "ДОБЫЧА" if source_panel.visible else "РЮКЗАК"
	backpack_panel.get_node("Title").text = "РЮКЗАК · %d / %d" % [_backpack.item_count, _backpack.capacity]
	backpack_panel.get_node("Hint").text = "Перетащите для смены слота"
	_fill_grid(backpack_panel.get_node("Grid"), _backpack, false)
	var take_all: Button = content.get_node("Actions/TakeAll")
	take_all.visible = source_panel.visible
	if source_panel.visible:
		source_panel.get_node("Title").text = _container.display_name.to_upper()
		_fill_grid(source_panel.get_node("Grid"), _container.inventory, true)
		var found := false
		for slot in range(_container.inventory.capacity):
			found = found or _container.is_discovered(slot)
		take_all.disabled = _backpack.is_full or not found
		_update_search()


func _update_search() -> void:
	if not is_instance_valid(_container):
		return
	var grid: GridContainer = source_panel.get_node("Grid")
	for index in range(grid.get_child_count()):
		grid.get_child(index).set_search_state(index == _container.current_search_slot, _container.search_progress)


func _fill_grid(grid: GridContainer, inventory: Inventory, taking: bool) -> void:
	if grid.get_child_count() != inventory.capacity:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
		for index in range(inventory.capacity):
			var cell := InventorySlot.new()
			cell.drop_validator = _can_drop
			cell.activated.connect(_activate_slot)
			cell.dropped.connect(_drop_slot)
			grid.add_child(cell)
	for index in range(inventory.capacity):
		grid.get_child(index).configure(inventory, index, not taking or _container.is_discovered(index))


func _activate_slot(inventory: Inventory, slot: int) -> void:
	if inventory.get_item(slot) == null:
		return
	if not _source_available():
		message.text = "Перетащите предмет в нужный слот рюкзака."
		return
	var success: bool
	if inventory == _backpack:
		success = _container.store_from(_backpack, slot)
	else:
		success = _container.take_to(_backpack, slot)
	message.text = "Предмет перемещён." if success else "Нет свободного места или предмет ещё не найден."


func _can_drop(data: Dictionary, destination: Inventory, target_slot: int) -> bool:
	if not visible or _player.is_dead or not data.has_all(["inventory", "slot", "item"]):
		return false
	var source: Inventory = data.inventory if data.inventory is Inventory else null
	if not is_instance_valid(source) or not data.slot is int or source.get_item(data.slot) == null or source.get_item(data.slot) != data.item:
		return false
	if destination == _backpack and source == _backpack:
		return target_slot >= 0 and target_slot < _backpack.capacity and data.slot != target_slot
	if not _source_available() or destination.get_item(target_slot) != null or target_slot < 0 or target_slot >= destination.capacity:
		return false
	if source == _container.inventory and destination == _backpack:
		return _container.is_discovered(data.slot)
	return source == _backpack and destination == _container.inventory


func _drop_slot(data: Dictionary, destination: Inventory, target_slot: int) -> void:
	if not _can_drop(data, destination, target_slot):
		return
	var source: Inventory = data.inventory
	if source == destination:
		source.move_slot(data.slot, target_slot)
	elif source == _backpack:
		_container.store_from(_backpack, data.slot, target_slot)
	else:
		_container.take_to(_backpack, data.slot, target_slot)
	message.text = "Предмет перемещён."


func _take_all() -> void:
	if not _source_available():
		close_menu()
		return
	for slot in range(_container.inventory.capacity):
		if _backpack.is_full:
			break
		_container.take_to(_backpack, slot)
	message.text = "Рюкзак заполнен." if _backpack.is_full else "Найденные предметы забраны."


func _can_discard(data: Dictionary) -> bool:
	return visible and not _player.is_dead and data.has_all(["inventory", "slot", "item"]) \
		and data.inventory == _backpack and data.slot is int \
		and _backpack.get_item(data.slot) != null and _backpack.get_item(data.slot) == data.item


func _discard(data: Dictionary) -> void:
	if not _can_discard(data):
		return
	if _interaction.drop_item(data.slot):
		message.text = "Предмет на полу. Закройте окно, повернитесь к нему и нажмите E."
	else:
		message.text = "Рядом нет свободного места. Предмет остался в рюкзаке."
