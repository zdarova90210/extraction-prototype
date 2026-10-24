extends SceneTree
## Real popup regression: an empty custom Control must never become a tooltip.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for tick in range(count):
		await process_frame


func _hover(control: Control) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(20, 20)
	root.push_input(event, true)
	await _ticks(2)
	event = InputEventMouseMotion.new()
	event.position = control.get_global_rect().get_center()
	root.push_input(event, true)
	# Native tooltips use elapsed time, not a count of rendered frames. Leave
	# margin beyond the engine delay even when startup frame pacing varies.
	var deadline := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _has_popup() -> bool:
	for window in root.get_embedded_subwindows():
		if window.visible:
			return true
	return false


func _run() -> void:
	var yard := load("res://tests/fixtures/system_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var menu: Control = yard.get_node("HUD/LootMenu")
	var box: StaticBody2D = yard.get_node("LootContainers/Supply")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").look_at(box.global_position)
	menu._open(null)
	await _ticks(3)
	var bag_cell: InventorySlot = menu.backpack_panel.get_node("Grid").get_child(0)
	_check(bag_cell._make_custom_tooltip("") == null, "Empty tooltip factory returns no Control")
	await _hover(bag_cell)
	_check(not _has_popup(), "Hovering empty backpack slot creates no popup")
	menu.open_container(box)
	await _ticks(3)
	var cell: InventorySlot = menu.source_panel.get_node("Grid").get_child(0)
	await _hover(cell)
	_check(not _has_popup(), "Unknown container item creates no tooltip popup")
	while not box.is_discovered(0):
		await _ticks(1)
	await _hover(cell)
	_check(_has_popup(), "Discovered item still creates a visible named tooltip")
	box.take_to(player.get_node("Inventory"), 0)
	await _hover(cell)
	_check(not _has_popup(), "Emptied container slot clears previous tooltip popup")
	await _hover(bag_cell)
	_check(_has_popup(), "Known backpack item has its tooltip")
	player.get_node("Inventory").transfer_to(box.inventory, 0)
	await _hover(bag_cell)
	_check(not _has_popup(), "Emptied backpack slot no longer creates tooltip")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/loot_empty_tooltip.png")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
