class_name InventorySlot
extends Button
## A persistent square cell. The menu validates transfers and search visibility.

signal activated(inventory: Inventory, slot: int)
signal dropped(data: Dictionary, inventory: Inventory, slot: int)

var inventory: Inventory
var slot_index: int = -1
var known: bool = true
var drop_validator: Callable
var searching: bool = false
var search_progress: float = 0.0
var _unknown: bool = false
var _shown_item: ItemDefinition
var _animation_time: float = 0.0
var _reveal_remaining: float = 0.0
const REVEAL_DURATION: float = 0.18


func _init() -> void:
	custom_minimum_size = Vector2(64, 64)
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_constant_override("icon_max_width", 40)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("172622")
	normal.border_color = Color("526258")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color("e2c58d")
	hover.bg_color = Color("293a31")
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	pressed.connect(func(): activated.emit(inventory, slot_index))
	visibility_changed.connect(_sync_animation)
	set_process(false)


func configure(owner_inventory: Inventory, index: int, discovered: bool) -> void:
	var item := owner_inventory.get_item(index)
	var same_item := inventory == owner_inventory and slot_index == index and _shown_item == item
	var revealed := same_item and _unknown and discovered and item != null
	inventory = owner_inventory
	slot_index = index
	known = discovered
	_shown_item = item
	_unknown = item != null and not known
	if revealed:
		_reveal_remaining = REVEAL_DURATION
	elif not same_item or _unknown:
		_reveal_remaining = 0.0
	if not _unknown:
		searching = false
		search_progress = 0.0
	set_meta("slot_index", index)
	icon = item.icon if item != null and known else null
	text = ""
	tooltip_text = item.display_name + "\n" + item.description if item != null and known else ""
	# Metadata exposed to UI tests must not reveal unknown item identities either.
	set_meta("item_id", item.id if item != null and known else &"")
	_sync_animation()
	queue_redraw()


func set_search_state(active: bool, progress: float) -> void:
	searching = active and _unknown
	search_progress = clampf(progress, 0.0, 1.0) if searching else 0.0
	queue_redraw()


func _sync_animation() -> void:
	if not is_visible_in_tree():
		_reveal_remaining = 0.0
	set_process(is_visible_in_tree() and (_unknown or _reveal_remaining > 0.0))


func _process(delta: float) -> void:
	_animation_time += delta
	_reveal_remaining = maxf(0.0, _reveal_remaining - delta)
	_sync_animation()
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	if _unknown:
		draw_rect(area, Color("101917"))
		# Low-contrast moving texture conceals every unknown item; only the
		# currently searched cell has the brighter sweep tied to real progress.
		for row in range(7):
			var y := area.position.y + fmod(row * 9.0 + _animation_time * 9.0, area.size.y)
			draw_line(Vector2(area.position.x + 3, y), Vector2(area.end.x - 3, y), Color(0.35, 0.43, 0.39, 0.12), 1.0)
		for dot in range(3):
			var pulse := 0.25 + 0.2 * (sin(_animation_time * 3.0 - dot * 0.8) + 1.0) * 0.5
			draw_circle(size * 0.5 + Vector2((dot - 1) * 8, 0), 1.7, Color(0.67, 0.73, 0.66, pulse))
		if searching:
			var scan_y := lerpf(area.position.y + 5, area.end.y - 5, search_progress)
			draw_rect(Rect2(area.position.x + 2, scan_y - 4, area.size.x - 4, 8), Color(0.88, 0.77, 0.54, 0.10))
			draw_line(Vector2(area.position.x + 3, scan_y), Vector2(area.end.x - 3, scan_y), Color(0.88, 0.77, 0.54, 0.8), 1.5, true)
			draw_rect(area.grow(1), Color(0.88, 0.77, 0.54, 0.6), false, 1.0)
	elif _reveal_remaining > 0.0:
		var fade := _reveal_remaining / REVEAL_DURATION
		draw_rect(area, Color(0.06, 0.10, 0.09, fade))
		draw_rect(area.grow(1), Color(0.88, 0.77, 0.54, fade * 0.7), false, 1.0)


func _make_custom_tooltip(for_text: String) -> Object:
	# Godot also calls this factory for empty text. An empty Control still
	# creates a themed popup; null leaves tooltip absence to the engine.
	if for_text.is_empty():
		return null
	var label := Label.new()
	label.text = for_text
	label.custom_minimum_size.x = 210.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	return label


func _get_drag_data(_position: Vector2) -> Variant:
	var item := inventory.get_item(slot_index)
	if not known or item == null:
		return null
	var preview := TextureRect.new()
	preview.texture = item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(44, 44)
	preview.size = Vector2(44, 44)
	preview.position = Vector2(-22, -22)
	set_drag_preview(preview)
	return {"inventory": inventory, "slot": slot_index, "item": item}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and drop_validator.is_valid() and drop_validator.call(data, inventory, slot_index)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		dropped.emit(data, inventory, slot_index)
