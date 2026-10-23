extends SceneTree
## Facing selection, incremental discovery, fixed slots and actual GUI dragging.

const YARD = preload("res://tests/fixtures/system_yard.tscn")
const CONTAINER = preload("res://scenes/loot_container.tscn")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	NavigationServer2D.map_set_use_async_iterations(root.get_world_2d().navigation_map, false)
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _ticks(1)


func _mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)


func _motion(point: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)


func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	_mouse_button(point, true)
	_mouse_button(point, false)
	await _ticks(1)


func _drag(source: Control, destination: Control) -> void:
	var from := source.get_global_rect().get_center()
	var to := destination.get_global_rect().get_center()
	_motion(from, Vector2.ZERO, false)
	await _ticks(1)
	_mouse_button(from, true)
	await _ticks(1)
	_motion(from + Vector2(16, 0), Vector2(16, 0), true)
	await _ticks(1)
	_motion(to, to - from - Vector2(16, 0), true)
	await _ticks(1)
	_mouse_button(to, false)
	await _ticks(2)


func _run() -> void:
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var box: StaticBody2D = yard.get_node("LootContainers/Supply")
	var other_box: StaticBody2D = yard.get_node("LootContainers/Service")
	var interaction: Node = player.get_node("LootInteraction")
	var menu: Control = yard.get_node("HUD/LootMenu")
	var pack: Inventory = player.get_node("Inventory")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").global_rotation = PI
	await _ticks(5)
	_check(box.size == Vector2(40, 16) and box.get_node("CollisionShape2D").shape.size == box.size, "Compact ground footprint matches the crate collider")
	box.size = Vector2(44, 30)
	_check(other_box.get_node("CollisionShape2D").shape.size == Vector2(40, 16), "Editing one crate size does not alter another instance")
	box.size = Vector2(40, 16)
	_check(interaction.can_reach(box) and not interaction.can_interact(box) and not box.get_node("Hint").visible, "Container behind player is reachable but cannot be interacted with")
	await _key(KEY_E)
	_check(not menu.visible, "Pressing E with back turned does not open a crate")
	var near := CONTAINER.instantiate() as StaticBody2D
	near.position = Vector2(650, 735)
	yard.add_child(near)
	player.get_node("Aim").look_at(near.global_position)
	await _ticks(3)
	_check(interaction._nearest() == near and near.get_node("Hint").visible and not box.get_node("Hint").visible, "Facing selects the intended nearby crate even when another is closer")
	await _key(KEY_E)
	_check(menu._container == near, "E opens exactly the highlighted crate")
	await _key(KEY_TAB)
	near.queue_free()
	player.get_node("Aim").look_at(box.global_position)
	await _ticks(3)
	await _key(KEY_E)
	var pack_grid: GridContainer = menu.backpack_panel.get_node("Grid")
	var source_grid: GridContainer = menu.source_panel.get_node("Grid")
	_check(menu.backpack_panel.get_global_rect().position.x < menu.source_panel.get_global_rect().position.x, "Backpack is on left, searched container on right")
	_check(pack_grid.get_child_count() == 6 and pack_grid.columns == 3, "Six empty backpack slots remain visible in a fixed grid")
	var unknown: InventorySlot = source_grid.get_child(0)
	_check(unknown.text.is_empty() and unknown.icon == null and unknown.tooltip_text.is_empty() and unknown.get_meta("item_id") == &"", "Animated unknown item exposes neither icon, name nor tooltip")
	_check(not menu.source_panel.has_node("Progress") and not menu.source_panel.has_node("SearchLabel"), "Search has no separate lower bar or status row")
	_check(unknown._get_drag_data(Vector2.ZERO) == null and not box.take_to(pack, 0), "Unknown loot cannot be dragged or taken through container API")
	menu._take_all()
	_check(pack.item_count == 0 and box.inventory.item_count == 4, "Take All never bypasses discovery")
	await _ticks(ceili(box.search_item_duration * 60.0 * 0.4))
	_check(not box.is_discovered(0) and box.search_progress > 0.25 and box.search_progress < 0.75, "First reveal is delayed while search visibly progresses")
	_check(unknown.searching and is_equal_approx(unknown.search_progress, box.search_progress) and not source_grid.get_child(1).searching, "Only the current unknown cell displays real search progress")
	await _key(KEY_TAB)
	var progress: float = box.search_progress
	await _ticks(50)
	_check(not box.is_discovered(0) and is_equal_approx(progress, box.search_progress), "Closing menu pauses discovery and preserves partial progress")
	_check(not unknown.is_processing(), "Hidden cells stop cosmetic animation")
	await _key(KEY_E)
	await _ticks(ceili(box.search_item_duration * 60.0 * 0.6))
	_check(box.is_discovered(0) and not box.is_discovered(1), "Reopening resumes search and reveals one item before the next")
	_check(unknown == source_grid.get_child(0) and unknown.icon != null and unknown.text.is_empty(), "Discovery updates existing square slot without recreating its control")
	_check(not unknown.searching and source_grid.get_child(1).searching and source_grid.get_child(2).icon == null, "Discovery moves the sweep to the next cell without revealing later icons")
	_check(unknown.tooltip_text.begins_with("Металлолом") and is_equal_approx(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec"), 0.12), "Known item uses named tooltip with short hover delay")
	var tooltip := unknown._make_custom_tooltip(unknown.tooltip_text) as Label
	_check(tooltip.get_theme_font_size("font_size") == 12, "Tooltip text is compact and readable")
	tooltip.free()
	await _click(unknown)
	_check(pack.get_item(0) != null and box.inventory.get_item(0) == null and box.inventory.get_item(1) != null, "Taking an item leaves a hole rather than shifting source slots")
	await _drag(pack_grid.get_child(0), pack_grid.get_child(5))
	_check(pack.get_item(0) == null and pack.get_item(5) != null and pack.item_count == 1 and box.inventory.item_count == 3, "Real mouse drag moves backpack item to chosen empty slot without quick-transfer click")
	await _ticks(ceili(box.search_item_duration * 60.0 * 3.0) + 20)
	_check(not box.has_unknown_items and box.is_discovered(1) and box.is_discovered(2) and box.is_discovered(3), "Remaining items are revealed in order and search completes")
	_check(not source_grid.get_child(3).is_processing() and not source_grid.get_child(4).is_processing(), "Revealed and empty cells do not keep animation running")
	await _click(source_grid.get_child(2))
	_check(pack.get_item(0).id == &"wire" and pack.get_item(5).id == &"metal", "New loot fills a free slot without disturbing manually arranged items")
	await _drag(pack_grid.get_child(0), pack_grid.get_child(5))
	_check(pack.get_item(0).id == &"metal" and pack.get_item(5).id == &"wire" and pack.item_count == 2, "Dragging onto occupied backpack slot swaps the two items")
	await _drag(source_grid.get_child(3), pack_grid.get_child(4))
	_check(pack.get_item(4) != null and pack.get_item(4).id == &"electronics" and box.inventory.get_item(3) == null, "Discovered loot can be dragged into a particular backpack slot")
	await _drag(pack_grid.get_child(4), source_grid.get_child(6))
	_check(pack.get_item(4) == null and box.inventory.get_item(6) != null and box.is_discovered(6), "Returned item uses chosen container slot and stays known without re-search")
	var payload := {"inventory": pack, "slot": 0, "item": pack.get_item(0)}
	_check(not menu._can_drop(payload, box.inventory, 1), "Cross-inventory drop onto occupied slot cannot overwrite loot")
	await _key(KEY_TAB)
	await _key(KEY_E)
	_check(box.is_discovered(1) and box.is_discovered(6), "Reopening preserves discovered identities and chosen container positions")
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	await _drag(pack_grid.get_child(5), pack_grid.get_child(2))
	_check(pack.get_item(5) == null and pack.get_item(2).id == &"wire" and pack.item_count == 2, "Backpack can be rearranged while viewing it without a container")
	payload = {"inventory": pack, "slot": 2, "item": pack.get_item(2)}
	pack.move_slot(2, 4)
	_check(not menu._can_drop(payload, pack, 3), "Stale drag cannot duplicate or move an item from a changed source slot")
	_check(pack.get_item(0).id == &"metal" and pack.get_item(4).id == &"wire" and pack.item_count + box.inventory.item_count == 4, "All moves conserve items and preserve explicit slot positions")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
