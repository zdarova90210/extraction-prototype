@tool
extends WorldObstacle
## Saved world object; its Inventory owns runtime loot, not shared resources.

@export var display_name: String = "Ящик"
## Visual gaze target, independent of the ground collider used for reach/walls.
@export var interaction_point: Marker2D
@export var impact_cue: SoundCue = preload("res://resources/audio/combat/wood.tres")
@export var size: Vector2 = Vector2(40, 16):
	set(value):
		size = value.max(Vector2(20, 16))
		if is_node_ready():
			_update_shape()
		queue_redraw()
@export_range(0.15, 3.0, 0.05, "suffix:s") var search_item_duration: float = 1.5
signal discovery_changed
signal search_progress_changed
signal opened
signal closed
signal item_discovered(slot: int)
var _highlighted: bool = false
var _discovered: Array[bool] = []
var _search_active: bool = false
var _search_slot: int = -1
var _search_elapsed: float = 0.0
@onready var inventory: Inventory = $Inventory
var search_progress: float:
	get: return clampf(_search_elapsed / search_item_duration, 0.0, 1.0)
var has_unknown_items: bool:
	get: return _next_unknown() >= 0
var current_search_slot: int:
	get:
		if not _search_active:
			return -1
		return _search_slot if _search_slot >= 0 else _next_unknown()
var is_searching: bool:
	get: return _search_active and has_unknown_items


func get_impact_cue() -> SoundCue:
	return impact_cue


func get_interaction_position() -> Vector2:
	return interaction_point.global_position


func _ready() -> void:
	super._ready()
	_update_shape()
	if Engine.is_editor_hint():
		return
	_discovered.resize(inventory.capacity)
	add_to_group("loot_containers")
	add_to_group("loot_interactables")
	inventory.changed.connect(_update_contents)
	_update_contents()


func _update_shape() -> void:
	$CollisionShape2D.shape.size = size


func is_discovered(slot: int) -> bool:
	return slot >= 0 and slot < _discovered.size() and _discovered[slot] and inventory.get_item(slot) != null


func set_searching(active: bool) -> void:
	if active == _search_active:
		return
	_search_active = active
	if active:
		opened.emit()
	else:
		closed.emit()


func reset_test_contents() -> void:
	# Explicit developer action only; opening a container never replenishes it.
	set_searching(false)
	_search_slot = -1
	_search_elapsed = 0.0
	_discovered.fill(false)
	var slots: Array[ItemDefinition] = []
	slots.resize(inventory.capacity)
	for index in range(mini(slots.size(), inventory.starting_items.size())):
		slots[index] = inventory.starting_items[index]
	inventory.replace_slots(slots)
	discovery_changed.emit()
	search_progress_changed.emit()


func _next_unknown() -> int:
	for slot in range(_discovered.size()):
		if inventory.get_item(slot) != null and not _discovered[slot]:
			return slot
	return -1


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _search_active:
		return
	if _search_slot == -1:
		_search_slot = _next_unknown()
	if _search_slot == -1:
		return
	_search_elapsed += delta
	if _search_elapsed >= search_item_duration:
		var discovered_slot := _search_slot
		_discovered[_search_slot] = true
		_search_slot = -1
		_search_elapsed = 0.0
		discovery_changed.emit()
		item_discovered.emit(discovered_slot)
	search_progress_changed.emit()


func take_to(destination: Inventory, slot: int, target_slot: int = -1) -> bool:
	return is_discovered(slot) and inventory.transfer_to(destination, slot, target_slot)


func store_from(source: Inventory, slot: int, target_slot: int = -1) -> bool:
	if target_slot == -1:
		target_slot = inventory.first_empty_slot()
	if target_slot < 0 or target_slot >= _discovered.size() or inventory.get_item(target_slot) != null:
		return false
	var was_known := _discovered[target_slot]
	_discovered[target_slot] = true # The player already knows the item they put here.
	if not source.transfer_to(inventory, slot, target_slot):
		_discovered[target_slot] = was_known
		return false
	return true


func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	$Hint.visible = highlighted
	queue_redraw()


func _update_contents() -> void:
	for slot in range(_discovered.size()):
		if inventory.get_item(slot) == null:
			_discovered[slot] = false
	if _search_slot >= 0 and inventory.get_item(_search_slot) == null:
		_search_slot = -1
		_search_elapsed = 0.0
	$Hint.text = "E · " + ("Пусто" if inventory.item_count == 0 else display_name)
	queue_redraw()


func _draw() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.self_modulate = Color(1.25, 1.25, 1.1) if _highlighted else Color.WHITE
