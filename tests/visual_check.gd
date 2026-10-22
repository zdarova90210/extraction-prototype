extends SceneTree
## Render real gameplay frames with Compatibility; never run this headless.

func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var default_room := load("res://tests/fixtures/system_yard.tscn").instantiate() as Node2D
	root.add_child(default_room)
	current_scene = default_room
	default_room.set_guards_active(false)
	await _ticks(5)
	await _save("audio_test_room")
	var overview: Camera2D = default_room.get_node("Player/Camera2D")
	overview.position_smoothing_enabled = false
	overview.position = Vector2(430, -5)
	overview.zoom = Vector2(0.55, 0.55)
	overview.force_update_scroll()
	await _ticks(3)
	await _save("audio_test_overview")
	default_room.free()
	await _ticks(2)
	var yard := load("res://tests/fixtures/system_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var enemy: CharacterBody2D = yard.get_node("Enemy")
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.global_position = Vector2(850, 565)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	camera.force_update_scroll()
	player.get_node("Aim").look_at(yard.get_node("Target").global_position)
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(900, 370)
	root.push_input(pointer, true)
	await _ticks(4)
	await _save("yard")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").look_at(yard.get_node("LootContainers/Supply").global_position)
	await _ticks(3)
	await _save("loot_hint")
	var loot_menu: Control = yard.get_node("HUD/LootMenu")
	loot_menu.open_container(yard.get_node("LootContainers/Supply"))
	await _ticks(2)
	await _save("loot_search")
	await _ticks(ceili(yard.get_node("LootContainers/Supply").search_item_duration * 60.0))
	await _save("loot_first_item")
	while yard.get_node("LootContainers/Supply").has_unknown_items:
		await _ticks(1)
	await _save("loot_container")
	var loot_pointer := InputEventMouseMotion.new()
	loot_pointer.position = loot_menu.source_panel.get_node("Grid").get_child(0).get_global_rect().get_center()
	root.push_input(loot_pointer, true)
	await _ticks(14)
	await _save("loot_tooltip")
	loot_pointer.position = Vector2(40, 80)
	root.push_input(loot_pointer, true)
	loot_menu._take_all()
	await _ticks(2)
	await _save("backpack_loot")
	loot_menu._discard({"inventory": player.get_node("Inventory"), "slot": 0, "item": player.get_node("Inventory").get_item(0)})
	await _ticks(2)
	await _save("backpack_drop")
	for index in range(1, 4):
		loot_menu._discard({"inventory": player.get_node("Inventory"), "slot": index, "item": player.get_node("Inventory").get_item(index)})
	loot_menu.close_menu()
	player.get_node("Aim").look_at(get_nodes_in_group("ground_items")[0].global_position)
	await _ticks(3)
	await _save("ground_loot")
	player.global_position = Vector2(850, 565)
	await _ticks(2)
	yard.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(2)
	await _save("pause_menu")
	yard.get_node("HUD/PauseMenu").set_settings_open(true)
	await _ticks(3)
	await _save("audio_settings")
	yard.get_node("HUD/PauseMenu/SettingsMenu/Center/Panel/Margin/Content/Tabs").current_tab = 1
	await _ticks(2)
	await _save("display_settings")
	yard.get_node("HUD/PauseMenu").set_developer_open(true)
	yard.spawn_guard(1)
	await _ticks(2)
	await _save("developer_room")
	# Keep the later combat captures focused on the original single guard.
	for guard in yard.get_guards():
		if guard != enemy:
			yard.remove_guard(guard)
	yard.get_node("HUD/PauseMenu").set_open(false)
	root.push_input(pointer, true)
	await _ticks(2)
	player.global_position = Vector2(1170, 440)
	enemy.global_position = Vector2(1340, 440)
	enemy.get_node("Aim").global_rotation = PI
	enemy.patrol_start = null
	enemy.patrol_end = null
	player.get_node("Aim").look_at(enemy.global_position)
	enemy.set_physics_process(true)
	await _ticks(8)
	await _save("aim")
	player.global_position = Vector2(1280, 610)
	await _ticks(4)
	enemy.set_physics_process(false)
	await _save("guard_turn")
	player.global_position = Vector2(1170, 440)
	enemy.get_node("Aim").global_rotation = PI
	enemy._desired_angle = PI
	enemy.set_physics_process(false)
	player.get_node("Aim/Weapon").try_fire(enemy.global_position, player)
	await _save("shot")
	await _ticks(3)
	await _save("ammo_shot")
	await _ticks(20)
	await _save("ammo_hidden")
	var weapon: Node2D = player.get_node("Aim/Weapon")
	weapon.ammo = 0
	weapon.ammo_changed.emit(weapon.ammo, weapon.magazine_size)
	weapon.try_fire(enemy.global_position, player)
	await _save("empty")
	player.get_node("Aim/Weapon").request_reload()
	await _ticks(12)
	await _save("reload")
	player.take_damage(14.0)
	await _ticks(12)
	player.take_damage(14.0)
	enemy.take_damage(25.0)
	await _ticks(8)
	await _save("health_damage")
	await _ticks(55)
	await _save("health_settled")
	while weapon.is_reloading:
		await _ticks(1)
	weapon.ammo = 0
	weapon.ammo_changed.emit(0, weapon.magazine_size)
	weapon.request_reload()
	var timing_middle: float = (weapon.active_window_start + weapon.active_window_end) * 0.5
	while weapon.is_reloading and weapon.reload_progress < timing_middle:
		await _ticks(1)
	weapon.set_physics_process(false)
	await _save("active_reload_window")
	if not weapon.try_active_reload():
		push_error("Visual timing fixture did not reach active reload window")
		quit(1)
		return
	await _save("active_reload_success")
	weapon.set_physics_process(true)
	while weapon.is_reloading:
		await _ticks(1)
	weapon.ammo = 0
	weapon.ammo_changed.emit(0, weapon.magazine_size)
	weapon.request_reload()
	weapon.try_active_reload()
	await _ticks(12)
	await _save("active_reload_miss")
	enemy.take_damage(1000.0)
	await _ticks(2)
	await _save("victory")
	player.take_damage(1000.0)
	await _ticks(20)
	await _save("death")
	print("Visual captures saved: yard, loot_hint, loot_search, loot_first_item, loot_container, loot_tooltip, backpack_loot, backpack_drop, ground_loot, pause_menu, audio_settings, display_settings, developer_room, guard_turn, aim, shot, ammo_shot, ammo_hidden, empty, reload, health_damage, health_settled, active_reload_window, active_reload_success, active_reload_miss, victory, death")
	quit()


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/" + name + ".png")
	if error != OK:
		push_error("Could not save visual capture: " + name)
		quit(1)
