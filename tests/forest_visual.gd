extends "res://tests/loot_slots_test.gd"
## Render the actual scene, including doorway, behind-house fade and pixel actors.


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room := load("res://scenes/forest_post.tscn").instantiate() as Node2D
	room.play_start_audio = false
	root.add_child(room)
	current_scene = room
	room.set_guards_active(false)
	var player: CharacterBody2D = room.get_node("Player")
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	player.aim.rotation = -0.4
	camera.force_update_scroll()
	await _ticks(10)
	await _save_forest("forest_post")
	root.size = Vector2i(3440, 1440)
	camera.force_update_scroll()
	await _ticks(5)
	await _save_forest("forest_wide")
	root.size = Vector2i(1280, 720)
	camera.force_update_scroll()
	await _ticks(5)
	player.global_position = Vector2(350, 315)
	camera.force_update_scroll()
	await _ticks(30)
	await _save_forest("forest_behind_hut")
	player.global_position = Vector2(520, 440)
	player.aim.look_at(room.get_node("Enemy").global_position)
	camera.force_update_scroll()
	await _ticks(5)
	await _save_forest("forest_cover")
	player.global_position = Vector2(440, 580)
	player.aim.rotation = -PI / 2
	room.get_node("HUD/LootMenu").open_container(room.get_node("LootContainers/HutSupplies"))
	await _ticks(96)
	await _save_forest("forest_loot")
	room.get_node("HUD/LootMenu").close_menu()
	room.free()
	await _ticks(3)
	var base: Control = load("res://scenes/base.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await _ticks(3)
	await _save_forest("forest_base_entry")
	print("Visual captures saved: forest_post, forest_wide, forest_behind_hut, forest_cover, forest_loot, forest_base_entry")
	quit()


func _save_forest(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + filename + ".png")
