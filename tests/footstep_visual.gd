extends "res://tests/visual_check.gd"


func _capture() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	player.global_position = Vector2(480, 700)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _ticks(3)
	await _save("footstep_metal_deck")
	player.global_position = Vector2(480, 795)
	player.get_node("Aim").rotation = -PI * 0.5
	camera.position = Vector2(120, -20)
	camera.zoom = Vector2(1.6, 1.6)
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _ticks(3)
	await _save("surface_height_readability")
	yard.free()
	print("Visual captures saved: footstep_metal_deck, surface_height_readability")
	quit()
