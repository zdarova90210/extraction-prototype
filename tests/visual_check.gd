extends SceneTree
## Render real gameplay frames with Compatibility; never run this headless.

func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
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
	yard.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(2)
	await _save("pause_menu")
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
	print("Visual captures saved: yard, pause_menu, developer_room, guard_turn, aim, shot, ammo_shot, ammo_hidden, empty, reload, health_damage, health_settled, active_reload_window, active_reload_success, active_reload_miss, victory, death")
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
