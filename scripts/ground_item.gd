class_name GroundItem
extends Node2D
## A single known item on the floor. Inventory.transfer_to owns every move.

var _highlighted: bool = false
@onready var inventory: Inventory = $Inventory


func _ready() -> void:
	add_to_group("ground_items")
	add_to_group("loot_interactables")
	inventory.changed.connect(_contents_changed)
	queue_redraw()


func pick_up(destination: Inventory) -> bool:
	if inventory.transfer_to(destination, 0):
		return true
	_set_hint("Нет места в рюкзаке")
	return false


func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	var item := inventory.get_item(0)
	_set_hint("E · " + item.display_name if item != null else "")
	$Hint.visible = highlighted and item != null
	queue_redraw()


func _set_hint(value: String) -> void:
	var hint: Label = $Hint
	hint.text = value
	hint.size = hint.get_combined_minimum_size()
	hint.position = Vector2(-hint.size.x * 0.5, -42)


func _contents_changed() -> void:
	if inventory.item_count == 0:
		# Remove from selection immediately, before deferred deletion.
		remove_from_group("loot_interactables")
		remove_from_group("ground_items")
		queue_free()
	set_highlighted(_highlighted)


func _draw() -> void:
	if not is_instance_valid(inventory):
		return
	var item := inventory.get_item(0)
	if item == null:
		return
	draw_circle(Vector2(2, 4), 14, Color(0.01, 0.02, 0.02, 0.5))
	draw_rect(Rect2(-12, -12, 24, 24), Color("26312b"))
	draw_rect(Rect2(-12, -12, 24, 24), Color("eed19a") if _highlighted else Color("7f8d78"), false, 1.0)
	if item.icon != null:
		draw_texture_rect(item.icon, Rect2(-10, -10, 20, 20), false)
