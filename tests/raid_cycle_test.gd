extends "res://tests/loot_slots_test.gd"
## End-to-end scene flow and actual GUI use, including full stash management.


func _wait_for_scene(old: Node, limit: int = 340) -> void:
	for tick in range(limit):
		await _ticks(1)
		if is_instance_valid(current_scene) and (not is_instance_valid(old) or current_scene != old):
			await _ticks(2)
			return


func _dialog_click(dialog: Window, button: Button) -> void:
	# Embedded subwindows receive pointer events through their parent viewport.
	var point := Vector2(dialog.position) + button.get_global_rect().get_center()
	_motion(point, Vector2.ZERO, false)
	_mouse_button(point, true)
	_mouse_button(point, false)
	await _ticks(2)


func _run() -> void:
	var profile: Node = root.get_node("RaidProgress")
	profile.reset_progress()
	var base := load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	await _ticks(3)
	_check(base.stash_grid.columns == 5 and base.stash_grid.get_child_count() == 20, "Base shows twenty slots in five columns and four rows")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and profile.stash.item_count == 0, "Initial base has normal pointer and empty stash")
	await _click(base.content.get_node("Actions/Start"))
	await _ticks(4)
	var yard: Node2D = current_scene
	_check(yard.has_node("ExtractionZone") and profile.raid_active, "New Raid button starts playable yard with extraction")
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	var guard: CharacterBody2D = yard.get_node("Enemy")
	guard.set_physics_process(false)
	var bag: Inventory = player.get_node("Inventory")
	var box: Inventory = yard.get_node("LootContainers/Supply/Inventory")
	for slot in range(3):
		box.transfer_to(bag, slot)
	var zone: Area2D = yard.get_node("ExtractionZone")
	_check(is_equal_approx(zone.duration, 5.0) and zone.collision_layer == 0, "Extraction requires five seconds and is not a physical obstacle")
	player.global_position = zone.global_position
	await _ticks(60)
	_check(zone.elapsed > 0.8 and zone.elapsed < 1.2, "Standing inside advances actual physics countdown")
	await _key(KEY_ESCAPE)
	var elapsed: float = zone.elapsed
	await _ticks(50)
	_check(paused and is_equal_approx(zone.elapsed, elapsed), "Pause stops extraction time")
	await _key(KEY_ESCAPE)
	player.global_position -= Vector2(200, 0)
	await _ticks(2)
	_check(zone.elapsed == 0.0, "Leaving extraction cancels and resets countdown")
	player.global_position = zone.global_position
	await _ticks(45)
	elapsed = zone.elapsed
	player.take_damage(10)
	await _ticks(2)
	_check(zone.elapsed >= elapsed and not player.is_dead, "Nonlethal damage does not silently cancel extraction")
	_check(not guard.is_dead, "Extraction does not require clearing the guard")
	yard.get_node("HUD/LootMenu")._open(null)
	await _wait_for_scene(yard)
	base = current_scene
	_check(base.has_method("_start_raid") and profile.stash.item_count == 3 and not profile.raid_active, "Countdown closes backpack and returns saved loot to base")
	_check("ЭВАКУАЦИЯ УСПЕШНА" in base.content.get_node("Result").text and not paused, "Base displays extraction result without a stuck pause")
	await _drag(base.stash_grid.get_child(0), base.stash_grid.get_child(19))
	_check(profile.stash.get_item(0) == null and profile.stash.get_item(19) != null, "Real stash drag moves item between explicit slots")
	await _click(base.content.get_node("Actions/Start"))
	await _ticks(4)
	yard = current_scene
	player = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	bag = player.get_node("Inventory")
	_check(profile.stash.item_count == 3 and bag.item_count == 0 and player.health == player.max_health, "New raid retains stash and resets only raid state")
	box = yard.get_node("LootContainers/Supply/Inventory")
	box.transfer_to(bag, 0)
	box.transfer_to(bag, 1)
	player.take_damage(1000)
	_check(bag.item_count == 0 and profile.stash.item_count == 3 and yard.death_screen.visible, "Death loses backpack without losing stash")
	_check(not yard.get_node("HUD/AimCursor").visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Death result allows pointer interaction with return button")
	await _click(yard.get_node("HUD/DeathScreen/ToBase"))
	await _ticks(3)
	base = current_scene
	_check(base.has_method("_start_raid") and "Потеряно предметов: 2" in base.content.get_node("Result").text, "Death return button shows correct loss report at base")
	await _click(base.content.get_node("Actions/Start"))
	await _ticks(4)
	yard = current_scene
	player = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	bag = player.get_node("Inventory")
	yard.get_node("LootContainers/Supply/Inventory").transfer_to(bag, 0)
	profile.save_path = "user://missing_cycle_directory/profile.json"
	zone = yard.get_node("ExtractionZone")
	zone.duration = 0.5
	player.global_position = zone.global_position
	await _ticks(40)
	_check(current_scene == yard and bag.item_count == 1 and profile.stash.item_count == 3, "Write failure keeps player and loot in raid")
	_check("Не удалось сохранить" in zone.get_node("Status").text and zone.elapsed == 0.0, "Extraction reports save failure and stops automatic retries")
	profile.save_path = ""
	player.global_position -= Vector2(200, 0)
	await _ticks(2)
	player.global_position = zone.global_position
	await _wait_for_scene(yard, 60)
	base = current_scene
	_check(base.has_method("_start_raid") and profile.stash.item_count == 4, "Re-entering extraction retries successfully without duplicating loot")
	# Full stash must stay playable: confirm removal, then place pending loot.
	var full: Array[ItemDefinition] = []
	full.resize(20)
	full.fill(preload("res://resources/items/metal.tres"))
	profile.stash.replace_slots(full)
	await _click(base.content.get_node("Actions/Start"))
	await _ticks(4)
	yard = current_scene
	player = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	bag = player.get_node("Inventory")
	box = yard.get_node("LootContainers/Supply/Inventory")
	box.transfer_to(bag, 0)
	box.transfer_to(bag, 1)
	zone = yard.get_node("ExtractionZone")
	zone.duration = 0.5
	player.global_position = zone.global_position
	await _wait_for_scene(yard, 60)
	base = current_scene
	_check(profile.stash.item_count == 20 and profile.pending.item_count == 2 and base.pending_grid.visible, "Full stash shows saved overflow after extraction")
	_check(base.content.get_node("Actions/Start").disabled, "New raid button waits for overflow resolution")
	var delete_zone: Control = base.content.get_node("Columns/Side/DeleteZone")
	await _drag(base.stash_grid.get_child(0), delete_zone)
	var dialog: ConfirmationDialog = base.get_node("DeleteConfirm")
	_check(dialog.visible and profile.stash.item_count == 20, "Dragging to delete asks before removing stash item")
	await _dialog_click(dialog, dialog.get_cancel_button())
	_check(profile.stash.item_count == 20 and not dialog.visible, "Cancel keeps selected stash item")
	await _drag(base.stash_grid.get_child(0), delete_zone)
	await _dialog_click(dialog, dialog.get_ok_button())
	_check(profile.stash.item_count == 19, "Confirmed delete frees exactly one slot")
	await _click(base.pending_grid.get_child(0))
	_check(profile.stash.item_count == 20 and profile.pending.item_count == 1, "Clicking overflow uses newly freed stash slot")
	await _drag(base.pending_grid.get_child(1), delete_zone)
	await _dialog_click(dialog, dialog.get_ok_button())
	_check(profile.pending.item_count == 0 and not base.content.get_node("Actions/Start").disabled, "Resolving all overflow enables next raid")
	await _click(base.content.get_node("Actions/Reset"))
	dialog = base.get_node("ResetConfirm")
	_check(dialog.visible and profile.stash.item_count == 20, "Test progress reset requires explicit in-game confirmation")
	await _dialog_click(dialog, dialog.get_ok_button())
	_check(profile.stash.item_count == 0 and profile.pending.item_count == 0, "Confirmed reset clears both saved inventories")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
