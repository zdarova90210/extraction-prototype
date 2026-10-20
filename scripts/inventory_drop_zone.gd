extends PanelContainer
## Explicit GUI destination; the menu validates, world interaction performs drop.

signal item_dropped(data: Dictionary)
var drop_validator: Callable


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and drop_validator.is_valid() and drop_validator.call(data)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		item_dropped.emit(data)
