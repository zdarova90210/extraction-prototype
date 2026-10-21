extends Control
## The stash view owns no items; every change is saved by RaidProgress first.

signal item_moved

@onready var content: VBoxContainer = $Margin/Content
@onready var progress: Node = get_node("/root/RaidProgress")
@onready var stash_grid: GridContainer = $Margin/Content/Columns/Stash/Grid
@onready var pending_grid: GridContainer = $Margin/Content/Columns/Side/PendingScroll/PendingGrid
var _discard_data: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	Input.action_release("shoot")
	progress.changed.connect(_refresh)
	content.get_node("Actions/Start").pressed.connect(_start_raid)
	content.get_node("Actions/Reset").pressed.connect(func(): $ResetConfirm.popup_centered())
	content.get_node("Actions/Quit").pressed.connect(func(): get_tree().quit())
	content.get_node("Actions/Settings").pressed.connect(_open_settings)
	$SettingsMenu.back_requested.connect(_close_settings)
	content.get_node("Columns/Side/DeleteZone").drop_validator = _valid_payload
	content.get_node("Columns/Side/DeleteZone").item_dropped.connect(_request_discard)
	$ResetConfirm.confirmed.connect(func(): progress.reset_progress())
	$DeleteConfirm.confirmed.connect(_confirm_discard)
	_refresh()
	content.get_node("Actions/Start").grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not $DeleteConfirm.visible and not $ResetConfirm.visible:
		if $SettingsMenu.visible:
			_close_settings()
		else:
			_open_settings()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	$Margin.hide()
	$SettingsMenu.open()


func _close_settings() -> void:
	$SettingsMenu.close()
	$Margin.show()
	content.get_node("Actions/Settings").grab_focus()


func _refresh() -> void:
	content.get_node("Columns/Stash/Title").text = "СХРОН · %d / %d" % [progress.stash.item_count, progress.stash.capacity]
	_fill_grid(stash_grid, progress.stash)
	_fill_grid(pending_grid, progress.pending)
	var overflow: bool = progress.pending.item_count > 0
	pending_grid.visible = overflow
	content.get_node("Columns/Side/PendingScroll").visible = overflow
	content.get_node("Columns/Side/PendingTitle").visible = overflow
	var result: Dictionary = progress.last_result
	var summary := "Вынесите добычу из рейда — она останется здесь между запусками игры."
	if result.get("outcome") == "extracted":
		summary = "ЭВАКУАЦИЯ УСПЕШНА · Вынесено предметов: %d. Добыча сохранена." % result.items.size()
	elif result.get("outcome") == "died":
		summary = "РЕЙД ЗАВЕРШЁН · Вы погибли. Потеряно предметов: %d. Схрон сохранён." % result.items.size()
	content.get_node("Result").text = summary
	var status: String = progress.error_message
	if status.is_empty():
		status = "Освободите место и перенесите оставшуюся добычу в схрон перед новым рейдом." if overflow else progress.notice
	if status.is_empty():
		status = "Изменения схрона сохраняются автоматически. В новый рейд вы идёте с пустым рюкзаком."
	content.get_node("Message").text = status
	content.get_node("Actions/Start").disabled = not progress.can_start_raid()


func _fill_grid(grid: GridContainer, inventory: Inventory) -> void:
	if grid.get_child_count() != inventory.capacity:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
		for slot in range(inventory.capacity):
			var cell := InventorySlot.new()
			cell.drop_validator = _can_drop
			cell.dropped.connect(_drop)
			cell.activated.connect(_activate)
			cell.discard_requested.connect(_discard_hovered)
			grid.add_child(cell)
	for slot in range(inventory.capacity):
		grid.get_child(slot).configure(inventory, slot, true)


func _valid_payload(data: Dictionary) -> bool:
	return not progress.read_only and data.has_all(["inventory", "slot", "item"]) \
		and data.inventory in [progress.stash, progress.pending] and data.slot is int \
		and data.inventory.get_item(data.slot) != null and data.inventory.get_item(data.slot) == data.item


func _can_drop(data: Dictionary, destination: Inventory, slot: int) -> bool:
	if not _valid_payload(data) or destination != progress.stash or slot < 0 or slot >= destination.capacity:
		return false
	return data.slot != slot if data.inventory == destination else destination.get_item(slot) == null


func _drop(data: Dictionary, destination: Inventory, slot: int) -> void:
	if _can_drop(data, destination, slot):
		if progress.move_item(data.inventory, data.slot, slot):
			item_moved.emit()


func _activate(inventory: Inventory, slot: int) -> void:
	if inventory == progress.pending and progress.stash.first_empty_slot() >= 0:
		if progress.move_item(inventory, slot, progress.stash.first_empty_slot()):
			item_moved.emit()


func _request_discard(data: Dictionary) -> void:
	if not _valid_payload(data):
		return
	_discard_data = data.duplicate()
	$DeleteConfirm.dialog_text = "Удалить «%s» навсегда?" % data.item.display_name
	$DeleteConfirm.popup_centered()


func _discard_hovered(inventory: Inventory, slot: int) -> void:
	if $DeleteConfirm.visible or $ResetConfirm.visible:
		return
	_request_discard({"inventory": inventory, "slot": slot, "item": inventory.get_item(slot)})


func _confirm_discard() -> void:
	if _valid_payload(_discard_data):
		progress.discard(_discard_data.inventory, _discard_data.slot)
	_discard_data = {}


func _start_raid() -> void:
	if not progress.can_start_raid():
		return
	Input.action_release("shoot")
	get_tree().change_scene_to_file("res://scenes/test_yard.tscn")
