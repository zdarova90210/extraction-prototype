class_name Inventory
extends Node
## Fixed slot positions, including empty ones. All moves change ownership atomically.

signal changed

@export_range(1, 100, 1) var capacity: int = 6
@export var starting_items: Array[ItemDefinition] = []
var _slots: Array[ItemDefinition] = []
var item_count: int:
	get:
		var count := 0
		for item in _slots:
			if item != null:
				count += 1
		return count
var is_full: bool:
	get: return item_count >= capacity


func _ready() -> void:
	_slots.resize(capacity)
	for index in range(mini(capacity, starting_items.size())):
		_slots[index] = starting_items[index]
	if starting_items.size() > capacity:
		push_warning("Inventory starting items exceed capacity: " + str(get_path()))


func get_items() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _slots:
		if item != null:
			result.append(item)
	return result


func get_item(slot: int) -> ItemDefinition:
	return _slots[slot] if slot >= 0 and slot < _slots.size() else null


func snapshot_slots() -> Array[ItemDefinition]:
	return _slots.duplicate()


func replace_slots(slots: Array[ItemDefinition], notify: bool = true) -> void:
	assert(slots.size() == capacity)
	_slots.assign(slots)
	if notify:
		changed.emit()


func clear(notify: bool = true) -> void:
	_slots.fill(null)
	if notify:
		changed.emit()


func first_empty_slot() -> int:
	for index in range(_slots.size()):
		if _slots[index] == null:
			return index
	return -1


func consume_item(slot: int, expected_item: ItemDefinition) -> bool:
	# A delayed action must never consume whatever happens to occupy its old slot.
	if expected_item == null or get_item(slot) != expected_item:
		return false
	_slots[slot] = null
	changed.emit()
	return true


func find_item_index(item_id: StringName) -> int:
	for index in range(_slots.size()):
		if _slots[index] != null and _slots[index].id == item_id:
			return index
	return -1


func transfer_to(destination: Inventory, index: int, target_slot: int = -1) -> bool:
	if not is_instance_valid(destination) or destination == self or get_item(index) == null:
		return false
	if target_slot == -1:
		target_slot = destination.first_empty_slot()
	if target_slot < 0 or target_slot >= destination._slots.size() or destination.get_item(target_slot) != null:
		return false
	destination._slots[target_slot] = _slots[index]
	_slots[index] = null
	# Listeners always observe the final state, never a duplicated/lost item.
	changed.emit()
	destination.changed.emit()
	return true


func move_slot(source_slot: int, target_slot: int) -> bool:
	if get_item(source_slot) == null or target_slot < 0 or target_slot >= _slots.size() or source_slot == target_slot:
		return false
	var item := _slots[target_slot]
	_slots[target_slot] = _slots[source_slot]
	_slots[source_slot] = item
	changed.emit()
	return true
