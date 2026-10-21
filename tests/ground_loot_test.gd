extends "res://tests/loot_slots_test.gd"
## Uses the same real keyboard/mouse helpers; this suite owns a fresh scene.


func _total_items(yard: Node2D) -> int:
	var total: int = yard.get_node("Player/Inventory").item_count
	for box in get_nodes_in_group("loot_containers"):
		total += box.inventory.item_count
	for item in get_nodes_in_group("ground_items"):
		total += item.inventory.item_count
	return total


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
	var other: StaticBody2D = yard.get_node("LootContainers/Service")
	var pack: Inventory = player.get_node("Inventory")
	var interaction: Node = player.get_node("LootInteraction")
	var menu: Control = yard.get_node("HUD/LootMenu")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").look_at(box.global_position)
	await _ticks(3)
	await _key(KEY_E)
	_check(is_equal_approx(box.search_item_duration, 1.5), "Default search takes 1.5 seconds per item")
	await _ticks(45)
	_check(not box.is_discovered(0), "Item remains unknown at the previous fast reveal time")
	await _ticks(45)
	_check(box.is_discovered(0) and not box.is_discovered(1), "First item becomes known at 1.5 seconds without revealing the next")
	await _key(KEY_TAB)
	# Seed six known backpack items; ownership still moves through Inventory.
	for index in range(4):
		box.inventory.transfer_to(pack, index)
	for index in range(2):
		other.inventory.transfer_to(pack, index)
	var conservation := [true]
	var initial_total := _total_items(yard)
	pack.changed.connect(func(): conservation[0] = conservation[0] and _total_items(yard) == initial_total)
	await _key(KEY_TAB)
	var grid: GridContainer = menu.backpack_panel.get_node("Grid")
	var zone: Control = menu.content.get_node("DropZone")
	_check(not zone._can_drop_data(Vector2.ZERO, {}), "Drop zone rejects malformed payloads")
	var foreign := {"inventory": other.inventory, "slot": 2, "item": other.inventory.get_item(2)}
	_check(not zone._can_drop_data(Vector2.ZERO, foreign), "Drop zone accepts backpack items only")
	var stale := {"inventory": pack, "slot": 0, "item": pack.get_item(0)}
	await _drag(grid.get_child(0), zone)
	_check(pack.get_item(0) == null and get_nodes_in_group("ground_items").size() == 1, "Real GUI drag drops exactly one item on the floor")
	_check(not zone._can_drop_data(Vector2.ZERO, stale), "Repeated stale drop cannot duplicate an item")
	for index in range(1, 6):
		await _drag(grid.get_child(index), zone)
	var floor_items := get_nodes_in_group("ground_items")
	_check(pack.item_count == 0 and floor_items.size() == 6, "Six actual drags create six independent world items")
	var spaced := true
	var reachable := true
	for first in range(floor_items.size()):
		reachable = reachable and interaction.can_reach(floor_items[first])
		for second in range(first + 1, floor_items.size()):
			spaced = spaced and floor_items[first].global_position.distance_to(floor_items[second].global_position) >= 27.99
	_check(spaced, "Repeated drops use different positions with 28px spacing")
	_check(reachable, "Dropped items are reachable and not placed through walls")
	_check(floor_items[0].inventory.capacity == 1 and floor_items[0].inventory.item_count == 1 and not floor_items[0] is CollisionObject2D, "Floor item owns one item without blocking movement or navigation")
	_check(conservation[0] and _total_items(yard) == initial_total, "Drop signals always observe conserved item ownership")
	await _key(KEY_TAB)
	var selected: GroundItem = floor_items[0]
	player.get_node("Aim").look_at(selected.global_position)
	player.get_node("Aim").rotation += PI
	_check(not interaction.can_interact(selected), "Floor item behind player cannot be picked up")
	player.get_node("Aim").look_at(selected.global_position)
	await _ticks(2)
	_check(interaction._nearest() == selected and selected.get_node("Hint").visible, "Looking at one nearby item selects and labels that exact item")
	var item_id: StringName = selected.inventory.get_item(0).id
	await _key(KEY_E)
	_check(pack.get_item(0).id == item_id and get_nodes_in_group("ground_items").size() == 5 and not menu.visible, "E picks up selected item immediately without opening container UI")
	# Add the two remaining authored items and pick up until the backpack is full.
	other.inventory.transfer_to(pack, 2)
	other.inventory.transfer_to(pack, 3)
	for index in range(3):
		var item: GroundItem = get_nodes_in_group("ground_items")[0]
		player.get_node("Aim").look_at(item.global_position)
		await _ticks(1)
		await _key(KEY_E)
	_check(pack.is_full and get_nodes_in_group("ground_items").size() == 2, "Picking up repeatedly respects six backpack slots")
	selected = get_nodes_in_group("ground_items")[0]
	player.get_node("Aim").look_at(selected.global_position)
	await _ticks(1)
	await _key(KEY_E)
	_check(pack.item_count == 6 and get_nodes_in_group("ground_items").size() == 2 and selected.inventory.item_count == 1, "Full backpack leaves the floor item intact")
	_check(selected.get_node("Hint").text == "Нет места в рюкзаке", "Failed pickup explains full backpack beside the selected item")
	var old_position := player.global_position
	player.global_position = box.global_position
	await _ticks(2)
	_check(not interaction.drop_item(0) and pack.item_count == 6 and get_nodes_in_group("ground_items").size() == 2, "Blocked drop fails without removing or duplicating inventory contents")
	_check(not interaction.can_reach(selected), "Wall between player and floor item blocks interaction")
	player.global_position = old_position
	await _ticks(2)
	await _key(KEY_TAB)
	await _drag(grid.get_child(0), zone)
	_check(pack.item_count == 5 and get_nodes_in_group("ground_items").size() == 3, "Dropping frees a backpack slot after failed pickup")
	await _key(KEY_TAB)
	player.get_node("Aim").look_at(selected.global_position)
	await _ticks(1)
	await _key(KEY_E)
	_check(pack.item_count == 6 and get_nodes_in_group("ground_items").size() == 2, "Previously rejected floor item can be picked up after freeing space")
	_check(conservation[0] and _total_items(yard) == initial_total, "All drop and pickup operations preserve total items")
	player.take_damage(1000.0)
	_check(not interaction.drop_item(0), "Dead player cannot discard inventory")
	await _key(KEY_ENTER)
	await _ticks(3)
	_check(current_scene != yard and get_nodes_in_group("ground_items").is_empty() and current_scene.get_node("Player/Inventory").item_count == 2, "Restart restores authored scene and two-medkit loadout, clearing floor loot")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
