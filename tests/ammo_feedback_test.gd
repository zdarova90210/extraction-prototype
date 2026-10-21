extends SceneTree

var _checks: int = 0
var _failures: int = 0


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


func _run() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	yard.get_node("Enemy").set_physics_process(false)
	player.set_physics_process(false)
	var weapon: Node2D = player.get_node("Aim/Weapon")
	var feedback: Node2D = player.get_node("AmmoFeedback")
	var readout: Label = feedback.get_node("Readout")
	_check(not yard.has_node("HUD/Top/PlayerStats") and not feedback.visible, "No corner ammo display or idle readout at spawn")
	_check(player.get_node("HealthBar").bar_height == 4.0 and yard.get_node("Enemy/HealthBar").bar_height == 4.0, "Both health bars have their original four-pixel thickness")
	weapon.try_fire(Vector2(900, 565), player)
	_check(feedback.visible and readout.text == "11 / 12", "Successful shot shows actual remaining ammo without a heading")
	await _ticks(3)
	_check(feedback.modulate.a > 0.7 and feedback.modulate.a <= feedback.peak_opacity + 0.001, "Ammo quickly fades in to a translucent readable level")
	weapon.try_fire(Vector2(900, 565), player)
	_check(readout.text == "11 / 12", "Blocked cooldown attempt does not change displayed ammo")
	await _ticks(10)
	_check(feedback.visible and feedback.modulate.a > 0.0 and feedback.modulate.a < feedback.peak_opacity, "Readout fades out near end of its short display")
	await _ticks(10)
	_check(not feedback.visible and is_zero_approx(feedback.modulate.a), "Readout disappears after roughly 300 milliseconds")
	Input.action_press("shoot")
	player.set_physics_process(true)
	await _ticks(3)
	var stayed_readable := true
	for frame in range(60):
		await _ticks(1)
		stayed_readable = stayed_readable and feedback.visible and feedback.modulate.a > 0.7
	_check(stayed_readable, "Readout remains readable throughout slow-fire cooldowns, not only after each shot")
	Input.action_release("shoot")
	player.set_physics_process(false)
	_check(weapon.ammo < 11 and feedback.visible and feedback.modulate.a > 0.7, "Holding fire keeps count readable between shots without restarting fade-in")
	_check(readout.text == "%d / 12" % weapon.ammo, "Held-fire readout stays synchronized with actual magazine")
	var offset := feedback.global_position - player.global_position
	player.position += Vector2(30, 20)
	player.get_node("Aim").rotation += 1.0
	_check(feedback.global_position - player.global_position == offset and is_zero_approx(feedback.global_rotation), "Readout follows movement beside actor without rotating with weapon")
	await _ticks(24)
	_check(not feedback.visible, "Releasing held fire lets readout disappear normally")
	weapon.request_reload()
	_check(not feedback.visible, "Reload leaves progress to existing aiming ring")
	await _ticks(95)
	_check(readout.text == "12 / 12" and feedback.visible, "Reload completion briefly confirms a full magazine")
	await _ticks(24)
	weapon.ammo = 0
	weapon.ammo_changed.emit(0, weapon.magazine_size)
	weapon.try_fire(Vector2(900, 565), player)
	_check(feedback.visible and readout.text == "0 / 12" and yard.get_node("HUD/AimCursor").is_empty_feedback_active, "Empty attempt shows zero ammo alongside existing cursor hint")
	weapon.request_reload()
	player.take_damage(1000.0)
	await _ticks(100)
	_check(not feedback.visible and weapon.ammo == 0, "Death during reload hides readout and never confirms a false refill")
	var fresh := load("res://scenes/player.tscn").instantiate() as CharacterBody2D
	fresh.get_node("Aim/Weapon").magazine_size = 5
	fresh.set_physics_process(false)
	yard.add_child(fresh)
	_check(fresh.get_node("AmmoFeedback/Readout").text == "5 / 5" and not fresh.get_node("AmmoFeedback").visible, "Custom magazine capacity initializes correctly without idle clutter")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
