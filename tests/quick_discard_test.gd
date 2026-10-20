extends "res://tests/loot_slots_test.gd"
## Keyboard discard follows real hover, shares drag behavior, and respects dialogs.


func _hover(control: Control) -> void:
	_motion(control.get_global_rect().get_center(), Vector2.ZERO, false)
	await _ticks(2)


func _dialog_click(dialog: Window, button: Button) -> void:
	var point := Vector2(dialog.position) + button.get_global_rect().get_center()
	_motion(point, Vector2.ZERO, false)
	_mouse_button(point, true)
	_mouse_button(point, false)
	await _ticks(2)


func _run() -> void:
	var yard := YARD.instantiate() as Node2D
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var pack: Inventory = player.get_node("Inventory")
	var box: StaticBody2D = yard.get_node("LootContainers/Supply")
	var menu: Control = yard.get_node("HUD/LootMenu")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").look_at(box.global_position)
	for slot in [0, 2, 3]:
		box.inventory.transfer_to(pack, slot)
	await _key(KEY_TAB)
	var grid: GridContainer = menu.backpack_panel.get_node("Grid")
	_check(InputMap.action_get_events("discard_item")[0].physical_keycode == KEY_Q, "Discard uses physical Q binding")
	grid.get_child(0).grab_focus()
	await _hover(grid.get_child(1))
	await _key(KEY_Q)
	_check(pack.get_item(0).id == &"metal" and pack.get_item(1) == null and pack.get_item(2).id == &"electronics", "Q targets hovered item rather than keyboard-focused slot")
	_check(get_nodes_in_group("ground_items").size() == 1 and get_nodes_in_group("ground_items")[0].inventory.get_item(0).id == &"wire", "Q places exactly the selected item on the floor")
	await _key(KEY_Q)
	_check(pack.item_count == 2 and get_nodes_in_group("ground_items").size() == 1, "Q on newly empty slot does nothing")
	await _hover(grid.get_child(0))
	var echo_event := InputEventKey.new()
	echo_event.physical_keycode = KEY_Q
	echo_event.keycode = KEY_Q
	echo_event.pressed = true
	echo_event.echo = true
	root.push_input(echo_event, true)
	await _ticks(1)
	_check(pack.item_count == 2, "Keyboard autorepeat does not discard items")
	var point: Vector2 = grid.get_child(0).get_global_rect().get_center()
	_mouse_button(point, true)
	_motion(point + Vector2(18, 0), Vector2(18, 0), true)
	await _ticks(2)
	_check(root.gui_is_dragging(), "Fixture uses a real active drag")
	await _key(KEY_Q)
	_check(pack.item_count == 2 and get_nodes_in_group("ground_items").size() == 1, "Q cannot discard while a GUI drag is active")
	_mouse_button(point + Vector2(18, 0), false)
	await _ticks(2)
	_motion(Vector2(20, 20), Vector2.ZERO, false)
	await _key(KEY_Q)
	_check(pack.item_count == 2, "Q outside item slots has no effect")
	await _key(KEY_TAB)
	await _key(KEY_Q)
	_check(pack.item_count == 2 and not menu.visible, "Closed inventory cannot discard from a remembered hover")
	box.search_item_duration = 0.15
	# Approach from another angle: the dropped wire otherwise sits directly
	# between the player and crate and correctly wins gaze selection on E.
	player.global_position = Vector2(650, 615)
	player.get_node("Aim").look_at(box.global_position)
	await _key(KEY_E)
	var source: InventorySlot = menu.source_panel.get_node("Grid").get_child(1)
	await _hover(source)
	await _key(KEY_Q)
	_check(box.inventory.item_count == 1 and get_nodes_in_group("ground_items").size() == 1, "Q cannot discard unknown container loot")
	await _ticks(12)
	await _key(KEY_Q)
	_check(box.is_discovered(1) and box.inventory.item_count == 1 and pack.item_count == 2, "Container slot does not discard a backpack item even when known")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _key(KEY_Q)
	_check(paused and pack.item_count == 2, "Pause blocks keyboard discard")
	await _key(KEY_ESCAPE)
	var profile: Node = root.get_node("RaidProgress")
	profile.finish_raid(pack)
	yard.queue_free()
	await _ticks(2)
	var base := load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	await _ticks(2)
	base.stash_grid.get_child(0).grab_focus()
	await _hover(base.stash_grid.get_child(1))
	await _key(KEY_Q)
	var dialog: ConfirmationDialog = base.get_node("DeleteConfirm")
	_check(dialog.visible and "Электроника" in dialog.dialog_text and profile.stash.item_count == 2, "Base Q opens confirmation for hovered stash item without deleting it")
	await _dialog_click(dialog, dialog.get_cancel_button())
	_check(profile.stash.item_count == 2 and not dialog.visible, "Cancelling keyboard deletion preserves saved item")
	await _hover(base.stash_grid.get_child(1))
	await _key(KEY_Q)
	await _dialog_click(dialog, dialog.get_ok_button())
	_check(profile.stash.item_count == 1 and profile.stash.get_item(0).id == &"metal", "Confirmed keyboard deletion removes only hovered saved item")
	await _hover(base.stash_grid.get_child(1))
	await _key(KEY_Q)
	_check(not dialog.visible and profile.stash.item_count == 1, "Empty stash slot cannot open deletion dialog")
	var pending: Array[ItemDefinition] = []
	pending.resize(6)
	pending[0] = preload("res://resources/items/wire.tres")
	profile.pending.replace_slots(pending)
	profile.changed.emit()
	await _ticks(2)
	await _hover(base.pending_grid.get_child(0))
	await _key(KEY_Q)
	_check(dialog.visible and "Провод" in dialog.dialog_text and profile.pending.item_count == 1, "Overflow Q also requires confirmation for the correct item")
	await _dialog_click(dialog, dialog.get_ok_button())
	_check(profile.pending.item_count == 0 and profile.stash.item_count == 1, "Confirmed overflow deletion leaves stash unchanged")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
