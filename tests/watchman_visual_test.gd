extends "res://tests/loot_slots_test.gd"
## Exercise the actual new outfit, not the player's old set of textures.

func _run() -> void:
	var player: Node2D = load("res://scenes/characters/character_visual.tscn").instantiate()
	var visual: Node2D = load("res://scenes/characters/watchman/visual.tscn").instantiate()
	root.add_child(player)
	root.add_child(visual)
	player.set_physics_process(false)
	visual.set_physics_process(false)
	_check(visual.get_script() == player.get_script() and visual.get_node("Pixels").get_texture() != player.get_node("Pixels").get_texture(), "Watchman reuses animator but owns its rendered pose")
	for view in 8:
		visual.direction_override = view
		visual.reset_pose()
		var torso: Sprite2D = visual.rig.get_node("Upper/Torso")
		_check(torso.texture is AtlasTexture and torso.texture.atlas.resource_path.begins_with("res://assets/art/characters/watchman/"), "Watchman outfit is selected in view %d" % view)
		for arm: Node2D in [visual.support_arm, visual.trigger_arm]:
			var image: Image = arm.get_node("Image").texture.get_image()
			_check(image.get_pixelv(Vector2i(arm.source_shoulder_uv.round())).a > 0.5, "Authored shoulder lies in painted sleeve: view %d, %s" % [view, arm.name])
			_check(image.get_pixelv(Vector2i((arm.source_shoulder_uv + arm.source_wrist).round())).a > 0.5, "Authored wrist lies in painted hand: view %d, %s" % [view, arm.name])
		var grips_ok := true
		var points_ok := true
		var stock_ok := true
		for edge in [-22.0, 0.0, 22.0]:
			for gait in 2:
				for frame in 8:
					for kick in [0.0, 1.0]:
						visual.aim_angle = view * PI / 4.0 + deg_to_rad(edge)
						visual.gait_blend = 1.0
						visual.sneak_blend = float(gait)
						visual.motion_vector = Vector2.from_angle(frame * TAU / 8.0)
						visual.phase = frame * TAU / 8.0
						visual.recoil = kick
						visual.apply_pose()
						for arm: Node2D in [visual.support_arm, visual.trigger_arm]:
							grips_ok = grips_ok and arm.get_node("Wrist").global_position.distance_to(arm.grip_target.global_position) < 0.05
							for point: Vector2 in arm.get_node("Image").polygon:
								points_ok = points_ok and point.is_finite() and point.length() < 80
						if visual.rig.stock_socket != null:
							stock_ok = stock_ok and visual.rig.stock_socket.global_position.distance_to(visual.rig.stock_anchor.global_position) <= 1.5
		_check(grips_ok and points_ok and stock_ok, "Complete sleeves, hand grips and stock remain stable across sector, gaits and recoil: view %d" % view)
		for look in 8:
			visual.aim_angle = view * PI / 4.0
			visual.motion_vector = Vector2.from_angle(look * PI / 4.0)
			visual.phase = look * TAU / 8.0
			visual.apply_pose()
			_check(visual.near_leg.position.is_finite() and visual.far_leg.position.is_finite() and is_zero_approx(visual.global_rotation), "Independent movement direction preserves upright grounded watchman: view %d, movement %d" % [view, look])
	visual.fallen = true
	_check(not visual.grip.visible and is_equal_approx(visual.get_node("Sprite").rotation, PI * 0.5), "Watchman corpse uses the shared grounded death presentation")
	visual.fallen = false
	visual.reset_pose()
	_check(visual.grip.visible and not player.fallen and is_zero_approx(player.recoil), "Recovery and outfit changes do not mutate the player")
	player.free()
	visual.free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
