extends Node
## Timed item application. Input bindings and presentation belong to the caller.

signal notice(text: String)
signal started
signal completed(restored: float)
signal cancelled

var is_using: bool = false
var progress: float:
	get: return clampf(_elapsed / _item.use_duration, 0.0, 1.0) if is_using else 0.0
var remaining: float:
	get: return maxf(0.0, _item.use_duration - _elapsed) if is_using else 0.0
var _item: ItemDefinition
var _slot: int = -1
var _elapsed: float = 0.0

@onready var _actor: CharacterBody2D = get_parent()
@onready var _inventory: Inventory = get_node("../Inventory")
@onready var _weapon: Node2D = get_node("../Aim/Weapon")


func _ready() -> void:
	_actor.damaged.connect(cancel)
	_inventory.changed.connect(_on_inventory_changed)


func use_first_healing_item() -> bool:
	for slot in range(_inventory.capacity):
		var item := _inventory.get_item(slot)
		if item != null and item.healing_amount > 0.0:
			return request_use(slot)
	notice.emit("Нет аптечки")
	return false


func request_use(slot: int) -> bool:
	if is_using or _actor.is_dead or not _actor.input_enabled or not _weapon.enabled:
		return false
	var item := _inventory.get_item(slot)
	if item == null or item.healing_amount <= 0.0 or item.use_duration <= 0.0:
		return false
	if _actor.health >= _actor.max_health:
		notice.emit("HP полностью")
		return false
	if _weapon.is_reloading:
		notice.emit("Идёт перезарядка")
		return false
	if not _actor.velocity.is_zero_approx():
		notice.emit("Остановитесь для лечения")
		return false
	_item = item
	_slot = slot
	_elapsed = 0.0
	is_using = true
	notice.emit("")
	started.emit()
	return true


func advance(delta: float) -> void:
	if not is_using:
		return
	if _actor.is_dead or not _actor.input_enabled or not _weapon.enabled:
		cancel()
		return
	_elapsed += delta
	if _elapsed < _item.use_duration:
		return
	var item := _item
	var slot := _slot
	_clear()
	# No yield between final validation, consumption and healing.
	if _actor.health >= _actor.max_health or not _inventory.consume_item(slot, item):
		notice.emit("Лечение отменено")
		cancelled.emit()
		return
	var restored: float = _actor.restore_health(item.healing_amount)
	notice.emit("+%d HP" % restored)
	completed.emit(restored)


func cancel(message: String = "Лечение отменено") -> void:
	if not is_using:
		return
	_clear()
	notice.emit(message)
	cancelled.emit()


func _clear() -> void:
	is_using = false
	_item = null
	_slot = -1
	_elapsed = 0.0


func _on_inventory_changed() -> void:
	if is_using and _inventory.get_item(_slot) != _item:
		cancel()
