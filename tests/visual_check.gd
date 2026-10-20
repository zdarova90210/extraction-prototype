extends SceneTree
## Render real gameplay frames with Compatibility; never run this headless.

func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Aim").look_at(yard.get_node("Target").global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/yard.png")
	await physics_frame
	await process_frame
	player.get_node("Aim/Weapon").try_fire(yard.get_node("Target").global_position, player)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/shot.png")
	print("Visual captures saved to artifacts/yard.png and artifacts/shot.png")
	quit()
