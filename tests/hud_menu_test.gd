extends SceneTree
## Persistent weapon information and real GUI pause/resume input.

var _checks: int = 0
var _failures: int = 0
var _shots: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)


func _escape() -> void:
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _ticks(1)


func _record_shot(_from: Vector2, _to: Vector2, _hit: bool) -> void:
	_shots += 1


func _run() -> void:
	var yard := load("res://tests/fixtures/system_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var original_id := yard.get_instance_id()
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	player.set_physics_process(false)
	guard.set_physics_process(false)
	var weapon: Node2D = player.get_node("Aim/Weapon")
	weapon.shot_fired.connect(_record_shot)
	var readout: Control = yard.get_node("HUD/WeaponReadout")
	var menu: Control = yard.get_node("HUD/PauseMenu")
	var cursor: Control = yard.get_node("HUD/AimCursor")
	var has_debug_overlay := false
	for node_name in ["Top", "DeveloperHint", "CombatStatus", "Objective", "TargetStatus", "Bottom"]:
		has_debug_overlay = has_debug_overlay or yard.has_node("HUD/" + node_name)
	_check(not has_debug_overlay and not menu.visible, "Gameplay HUD has no top strip, location name, objective, debug status or controls banner")
	_check(readout.visible and readout.get_node("Name").text == weapon.display_name.to_upper() and readout.get_node("Ammo").text == "12 / 12", "Persistent HUD shows selected weapon and loaded ammo before any shot")
	await _ticks(30)
	_check(_shots == 0 and readout.visible and not player.get_node("AmmoFeedback").visible, "Idle player can inspect ammo silently while transient readout stays hidden")
	weapon.try_fire(Vector2(900, 565), player)
	_check(readout.get_node("Ammo").text == "11 / 12", "Persistent ammo updates immediately on a real shot")
	await _ticks(24)
	_check(readout.visible and not player.get_node("AmmoFeedback").visible and readout.get_node("Ammo").text == "11 / 12", "Bottom count remains available after local shot feedback fades")
	weapon.request_reload()
	await _ticks(12)
	_check(readout.get_node("State").text == "ПЕРЕЗАРЯДКА" and readout.get_node("Ammo").text == "11 / 12", "Reload state keeps actual loaded ammo until completion")
	guard.set_physics_process(true)
	player.set_physics_process(true)
	await _ticks(2)
	await _escape()
	_check(paused and menu.visible and not cursor.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape pauses gameplay, shows help and restores normal menu pointer")
	_check(menu.resume_button.has_focus(), "Pause menu has keyboard focus on Continue")
	var key_text: String = menu.get_node("Center/Panel/Margin/Content/Bindings/Keys").text
	_check("R ещё раз" in key_text and "Enter" in key_text and "Esc" in key_text, "Help includes active reload, restart and pause bindings")
	var player_position: Vector2 = player.position
	var guard_position: Vector2 = guard.position
	var progress: float = weapon.reload_progress
	var health: float = player.health
	Input.action_press("move_right")
	Input.action_press("shoot")
	Input.action_press("reload")
	await _ticks(45)
	_check(player.position == player_position and guard.position == guard_position and player.health == health, "Help pauses movement and guard combat")
	_check(weapon.reload_progress == progress and weapon.ammo == 11 and _shots == 1, "Reload timer and shooting stay frozen while reading help")
	_key(KEY_ESCAPE, true, true)
	_key(KEY_ESCAPE, false)
	_check(menu.visible and paused, "Keyboard auto-repeat cannot toggle pause repeatedly")
	Input.action_release("move_right")
	Input.action_release("reload")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = menu.resume_button.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	root.push_input(click, true)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await _ticks(3)
	_check(not paused and not menu.visible and cursor.visible, "Clicking Continue resumes gameplay and restores aiming cursor")
	_check(current_scene.get_instance_id() == original_id and not Input.is_action_pressed("shoot") and _shots == 1, "Continue neither restarts scene nor fires a stray shot")
	_check(weapon.reload_progress > progress, "Reload continues from saved progress after pause")
	await _ticks(95)
	_check(readout.get_node("Ammo").text == "12 / 12" and readout.get_node("State").text.is_empty(), "Completed reload restores persistent full count and clears state")
	await _escape()
	await _escape()
	_check(not paused and not menu.visible, "Escape also closes help without a button click")
	await _escape()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _ticks(2)
	_check(not paused and not menu.visible and current_scene.get_instance_id() == original_id, "Enter activates focused Continue without restarting the scene")
	var initial_size := root.size
	root.size = Vector2i(2560, 1080)
	await _ticks(2)
	var bounds := readout.get_global_rect()
	_check(absf(root.get_visible_rect().size.y - bounds.end.y - 22.0) < 1.0 and bounds.position.x >= 20.0 and bounds.end.x < root.get_visible_rect().size.x, "Weapon information stays anchored near bottom left at ultrawide window size")
	root.size = initial_size
	await _ticks(2)
	player.set_physics_process(false)
	weapon.ammo = 0
	weapon.ammo_changed.emit(0, weapon.magazine_size)
	_check(readout.get_node("Ammo").text == "0 / 12" and readout.get_node("State").text == "ПУСТО", "Empty magazine is readable without attempting a shot")
	var guard_weapon: Node2D = guard.get_node("Aim/Weapon")
	guard_weapon.display_name = "Проверочный"
	readout.bind(guard_weapon)
	weapon.ammo = 5
	weapon.ammo_changed.emit(5, weapon.magazine_size)
	_check(readout.get_node("Name").text == "ПРОВЕРОЧНЫЙ" and readout.get_node("Ammo").text == "%d / %d" % [guard_weapon.ammo, guard_weapon.magazine_size], "Binding another selected weapon disconnects old ammo signals")
	readout.bind(weapon)
	player.take_damage(1000.0)
	await _escape()
	await _escape()
	_check(player.is_dead and yard.get_node("HUD/DeathScreen").visible and not paused, "Opening help after death does not revive player or trap pause")
	var restart := InputEventAction.new()
	restart.action = "restart"
	restart.pressed = true
	root.push_input(restart, true)
	await _ticks(4)
	_check(current_scene.get_instance_id() != original_id and not paused and not current_scene.get_node("HUD/PauseMenu").visible and current_scene.get_node("HUD/WeaponReadout/Ammo").text == "12 / 12", "Restart creates a clean loaded HUD with help closed")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
