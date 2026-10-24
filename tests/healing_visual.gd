extends "res://tests/visual_check.gd"
## Actual Compatibility frames for local treatment and the new loot icon.

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _capture() -> void:
	var yard := load("res://tests/fixtures/system_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	yard.get_node("Enemy").set_physics_process(false)
	var player: CharacterBody2D = yard.get_node("Player")
	player.global_position = Vector2(575, 690)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	camera.force_update_scroll()
	var pack: Inventory = player.get_node("Inventory")
	yard.get_node("LootContainers/Supply/Inventory").transfer_to(pack, 1)
	player.take_damage(65)
	await _ticks(3)
	var use: Node = player.get_node("ItemUse")
	_check(use.request_use(0), "Rendered player starts medkit application")
	await _ticks(75)
	await _save("healing_in_progress")
	_check(player.get_node("ItemUseFeedback").visible and use.progress > 0.3 and use.progress < 0.7, "Mid-use frame shows local progress")
	await _ticks(110)
	await _save("healing_complete")
	_check(not use.is_using and player.health == 75.0 and pack.item_count == 0, "Completion frame has healed bar and consumed item")
	var slots: Array[ItemDefinition] = [preload("res://resources/items/medkit.tres"), null, null, null, null, null]
	pack.replace_slots(slots)
	yard.get_node("HUD/LootMenu")._open(null)
	await _ticks(3)
	await _save("medkit_inventory")
	yard.get_node("HUD/LootMenu").close_menu()
	yard.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(3)
	var panel: Control = yard.get_node("HUD/PauseMenu/Center/Panel")
	var bindings: Control = panel.get_node("Margin/Content/Bindings")
	var keys: PackedStringArray = bindings.get_node("Keys").text.split("\n")
	var actions: PackedStringArray = bindings.get_node("Actions").text.split("\n")
	var heal_row := keys.find("H")
	var sneak_row := keys.find("C")
	var fire_row := keys.find("ЛКМ")
	_check(keys.size() == actions.size() and heal_row >= 0 and sneak_row >= 0 and fire_row >= 0 and not keys.has("ПКМ") and "Аптечка" in actions[heal_row] and "подкрадывание" in actions[sneak_row] and actions[fire_row] == "Стрельба", "Runtime key labels align with healing, sneak and immediate fire")
	var rect := panel.get_global_rect()
	_check(rect.position.y >= 0 and rect.end.y <= root.get_visible_rect().size.y, "Controls including H still fit the screen")
	await _save("healing_controls")
	yard.get_node("HUD/PauseMenu").set_open(false)
	yard.free()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
