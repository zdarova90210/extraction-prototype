extends SceneTree
## Real container interactions, atomic ownership, capacity and live-world GUI.

const YARD = preload("res://scenes/test_yard.tscn")
const COVER = preload("res://scenes/obstacle.tscn")
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


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _ticks(1)


func _item_button(list: Node, item_id: StringName) -> Button:
	for child in list.get_children():
		if child is Button and child.get_meta("item_id", &"") == item_id:
			return child
	return null


func _finish_search(container: StaticBody2D) -> void:
	for tick in range(ceili(container.inventory.capacity * container.search_item_duration * 60.0) + 5):
		if not container.has_unknown_items:
			return
		await _ticks(1)


func _run() -> void:
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	var backpack: Inventory = player.get_node("Inventory")
	var interaction: Node = player.get_node("LootInteraction")
	var first: StaticBody2D = yard.get_node("LootContainers/Supply")
	var second: StaticBody2D = yard.get_node("LootContainers/Service")
	var menu: Control = yard.get_node("HUD/LootMenu")
	var pause: Control = yard.get_node("HUD/PauseMenu")
	var cursor: Control = yard.get_node("HUD/AimCursor")
	guard.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").look_at(first.global_position)
	await _ticks(5)
	_check(backpack.item_count == 0 and backpack.capacity == 6, "Player starts with six empty backpack slots")
	_check(first.inventory.item_count == 4 and second.inventory.item_count == 4, "Two containers initialize independent runtime contents")
	var ids: Dictionary = {}
	for container in [first, second]:
		for item in container.inventory.get_items():
			ids[item.id] = true
	_check(ids.size() == 4 and ids.has(&"medkit"), "Loot uses four shared item definitions including the medkit")
	_check(first.get_node("Hint").visible and interaction.can_reach(first), "Nearest reachable box shows a local E hint")
	var cover := COVER.instantiate() as StaticBody2D
	cover.position = Vector2(603, 690)
	cover.size = Vector2(16, 90)
	yard.add_child(cover)
	await _ticks(2)
	await _key(KEY_E)
	_check(not menu.visible and not interaction.can_reach(first), "Wall prevents opening container even within reach")
	cover.queue_free()
	await _ticks(3)
	player.global_position = Vector2(450, 690)
	await _ticks(2)
	await _key(KEY_E)
	_check(not menu.visible, "Container cannot be opened from outside interaction range")
	player.global_position = Vector2(575, 690)
	await _ticks(2)
	var path := NavigationServer2D.map_get_path(yard.get_world_2d().navigation_map, Vector2(575, 690), Vector2(725, 690), true)
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	_check(path.size() >= 3 and length > 160.0, "Existing navigation bakes around smaller loot container collider")
	var endpoints: Array[Vector2] = []
	player.weapon.shot_fired.connect(func(_from: Vector2, to: Vector2, _hit: bool): endpoints.append(to))
	player.weapon.try_fire(Vector2(900, 690), player)
	_check(endpoints.size() == 1 and absf(endpoints[0].x - 630.0) < 1.0 and first.inventory.item_count == 4, "Container stops bullets without consuming or damaging loot")
	await _key(KEY_E)
	_check(menu.visible and not paused and not player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not cursor.visible, "E opens live-world loot UI with safe controls and normal pointer")
	var source_list: Node = menu.source_panel.get_node("Grid")
	var pack_list: Node = menu.backpack_panel.get_node("Grid")
	await _finish_search(first)
	await _click(_item_button(source_list, &"metal"))
	_check(backpack.item_count == 1 and first.inventory.item_count == 3, "Actual GUI click transfers one item, not the whole displayed stack")
	_check(second.inventory.item_count == 4 and first.inventory.starting_items.size() == 4, "Loot transfer does not mutate other containers or starting resources")
	var observer := {"atomic": true}
	first.inventory.changed.connect(func(): observer.atomic = observer.atomic and first.inventory.item_count + backpack.item_count == 4)
	await _click(menu.content.get_node("Actions/TakeAll"))
	_check(first.inventory.item_count == 0 and backpack.item_count == 4 and observer.atomic, "Take All transfers atomically and empties source without duplication")
	await _key(KEY_TAB)
	_check(not menu.visible and not paused and player.input_enabled and not Input.is_action_pressed("shoot"), "Tab closes focused loot UI without firing or pausing")
	await _key(KEY_E)
	_check(menu.visible and first.inventory.item_count == 0, "Reopening searched container does not regenerate items")
	player.global_position = Vector2(450, 690)
	await _ticks(2)
	_check(not menu.visible and player.input_enabled, "Moving container out of reach closes loot and restores controls")
	player.global_position = Vector2(575, 690)
	await _ticks(2)
	await _key(KEY_E)
	await _key(KEY_ESCAPE)
	_check(not menu.visible and not pause.visible and not paused, "First Escape closes loot only")
	await _key(KEY_ESCAPE)
	_check(pause.visible and paused, "Next Escape opens normal pause menu")
	await _key(KEY_TAB)
	_check(pause.visible and not menu.visible, "Backpack cannot open over paused menus")
	await _key(KEY_ESCAPE)
	player.global_position = second.global_position + Vector2(-80, 0)
	player.get_node("Aim").look_at(second.global_position)
	await _ticks(2)
	await _key(KEY_E)
	await _finish_search(second)
	await _click(menu.content.get_node("Actions/TakeAll"))
	_check(backpack.item_count == 6 and second.inventory.item_count == 2 and backpack.is_full, "Full backpack leaves excess items in the container")
	_check(menu.content.get_node("Actions/TakeAll").disabled, "Take All is unavailable when backpack is full")
	_check(not second.inventory.transfer_to(backpack, second.inventory.find_item_index(&"wire")) and backpack.item_count == 6 and second.inventory.item_count == 2, "Inventory API also rejects overflow without losing items")
	var exported := backpack.get_items()
	exported.clear()
	_check(backpack.item_count == 6, "Reading inventory cannot mutate item ownership through a returned array")
	_check(not backpack.transfer_to(backpack, 0) and not backpack.transfer_to(second.inventory, -1), "Self-transfer and invalid index cannot change ownership")
	await _click(_item_button(pack_list, &"metal"))
	_check(backpack.item_count == 5 and second.inventory.item_count == 3, "Clicking backpack item returns one item to current container")
	await _click(_item_button(source_list, &"wire"))
	_check(backpack.item_count == 6 and second.inventory.item_count == 2 and backpack.find_item_index(&"medkit") >= 0, "Freed slot can be used to choose different loot without losing the medkit")
	await _key(KEY_F2)
	_check(paused and pause.visible and pause.get_node("DeveloperPanel").visible and not menu.visible, "F2 replaces loot with developer tools using a single pause owner")
	await _key(KEY_F2)
	await _key(KEY_TAB)
	_check(menu.visible and not menu.source_panel.visible and menu.backpack_panel.get_node("Title").text.contains("6 / 6"), "Tab inspects backpack anywhere without a container")
	await _key(KEY_ENTER)
	_check(not menu.visible and current_scene == yard, "Enter on Close does not restart the raid")
	# Opening loot must not make a safe pause during combat.
	player.global_position = Vector2(1170, 440)
	guard.global_position = Vector2(1340, 440)
	guard.patrol_start = null
	guard.patrol_end = null
	guard.get_node("Aim").global_rotation = PI
	guard._desired_angle = PI
	guard.set_physics_process(true)
	player.set_physics_process(true)
	await _ticks(2)
	await _key(KEY_TAB)
	var player_position := player.global_position
	var ammunition: int = player.weapon.ammo
	Input.action_press("shoot")
	Input.action_press("move_right")
	await _ticks(80)
	_check(player.health < player.max_health and guard.weapon.ammo < guard.weapon.magazine_size and not paused, "Guard can shoot and hurt player while backpack is open")
	_check(player.global_position == player_position and player.weapon.ammo == ammunition, "Clicks and movement input do not leak through inventory UI")
	Input.action_release("move_right")
	guard.set_physics_process(false)
	player.take_damage(1000.0)
	await _ticks(1)
	_check(not menu.visible and player.is_dead and yard.death_screen.visible, "Death closes loot and presents normal death screen")
	await _key(KEY_TAB)
	_check(not menu.visible, "Dead player cannot reopen backpack")
	await _key(KEY_ENTER)
	await _ticks(4)
	var fresh := current_scene
	_check(fresh != yard and fresh.get_node("Player/Inventory").item_count == 2 and fresh.get_node("LootContainers/Supply/Inventory").item_count == 4, "Restart creates starting test backpack and restores saved container contents")
	_check(not fresh.has_node("HUD/Top") and not fresh.has_node("HUD/TargetStatus"), "Loot does not reintroduce a service panel at top of gameplay")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
