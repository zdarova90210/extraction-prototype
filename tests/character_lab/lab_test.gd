extends "res://tests/loot_slots_test.gd"
## Real input/physics/combat regression for the isolated directional rig experiment.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room := load("res://tests/character_lab/character_motion_lab.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await _ticks(4)
	var actor: CharacterBody2D = room.actor
	var visual: Node2D = actor.visual
	var weapon: Node2D = actor.weapon
	visual.direction_override = 0 # Stable east reference for existing gait measurements.
	await _check_foot_contacts(actor)
	_check(is_equal_approx(actor.get_node("CollisionShape2D").shape.radius, 15.0), "Lab keeps ground collision radius")
	var start := actor.position
	Input.action_press("move_right")
	await _ticks(30)
	Input.action_release("move_right")
	_check(actor.position.x > start.x + 40.0, "WASD moves the real CharacterBody2D")
	_check(visual.walking and absf(visual.phase) > 0.01, "Actual travel drives articulated walking")
	actor.position = Vector2(66, 430)
	Input.action_press("move_left")
	await _ticks(45)
	_check(actor.position.x >= 62.9 and actor.position.x < 65.0, "Feet stop against saved wall")
	_check(not visual.walking, "Holding movement into a wall stops gait")
	Input.action_release("move_left")
	actor.input_enabled = false
	visual.set_physics_process(false)
	visual.reset_pose()
	visual.sneaking = true
	visual.sneak_blend = 1.0
	visual.gait_blend = 1.0
	var ground_y: float = visual.get_node("Pixels/Model").global_position.y
	visual.phase = TAU * 0.25
	visual.apply_pose()
	var sneak_knee: float = absf(visual.far_shin.rotation)
	_check(absf(visual.far_shin.rotation) > 0.55, "Returning leg bends at knee rather than swinging as a straight plank")
	_check(_sole_y(visual.near_foot) <= ground_y + 0.05 and _sole_y(visual.near_foot) >= ground_y - 0.05, "Supporting sole stays at ground height")
	_check(_sole_y(visual.far_foot) < ground_y - 2.0, "Returning boot clears ground")
	visual.phase = TAU * 0.75
	visual.apply_pose()
	_check(absf(visual.near_shin.rotation) > 0.55 and _sole_y(visual.near_foot) < ground_y - 2.0, "Other knee and boot exchange swing roles")
	var no_ground_penetration := true
	for sample in 32:
		visual.phase = sample * TAU / 32.0
		visual.apply_pose()
		no_ground_penetration = no_ground_penetration and _sole_y(visual.near_foot) <= ground_y + 0.05 and _sole_y(visual.far_foot) <= ground_y + 0.05
	_check(no_ground_penetration, "Articulated soles do not pass through ground over a full cycle")
	visual.walking = false
	visual.advance(0.2)
	_check(is_zero_approx(visual.gait_blend) and is_zero_approx(visual.near_leg.rotation) and is_zero_approx(visual.near_shin.rotation), "Stopping settles legs back to neutral stance")
	visual.sneaking = false
	visual.reset_pose()
	visual.gait_blend = 1.0
	visual.phase = TAU * 0.25
	visual.apply_pose()
	_check(absf(visual.far_shin.rotation) < sneak_knee - 0.15, "Ordinary walk bends the return knee less than preserved sneak")
	var height_ranges: Array[float] = []
	for sneak in [false, true]:
		visual.sneaking = sneak
		visual.sneak_blend = 1.0 if sneak else 0.0
		var lowest := -INF
		var highest := INF
		var soles_clear := true
		for sample in 32:
			visual.phase = sample * TAU / 32.0
			visual.apply_pose()
			var crown_y: float = visual.rig.get_node("Upper/Crown").global_position.y
			lowest = maxf(lowest, crown_y)
			highest = minf(highest, crown_y)
			soles_clear = soles_clear and _sole_y(visual.near_foot) <= ground_y + 0.05 and _sole_y(visual.far_foot) <= ground_y + 0.05
		height_ranges.append(lowest - highest)
		_check(soles_clear, "Soles remain above ground in gait: " + ("sneak" if sneak else "walk"))
	_check(height_ranges[0] >= 1.8 and height_ranges[1] >= 1.0 and height_ranges[0] > height_ranges[1], "Both gaits visibly change crown height, ordinary walk more")
	visual.sneaking = false
	visual.advance(0.1)
	_check(visual.sneak_blend > 0.0 and visual.sneak_blend < 1.0, "Gait switch passes through a blended pose")
	visual.advance(0.2)
	visual.reset_pose()
	var lowered_rotation: float = visual.grip.rotation
	visual.aim_requested = true
	visual.advance(0.12)
	_check(visual.aim_blend > 0.4 and visual.aim_blend < 0.6, "Weapon raise has an intermediate pose")
	_check(visual.grip.rotation < lowered_rotation and visual.grip.rotation > 0.0, "Raise interpolates weapon angle")
	visual.advance(0.2)
	_check(is_equal_approx(visual.aim_blend, 1.0), "Weapon reaches raised pose")
	for angle in [-12.0, 0.0, 12.0]:
		for blend in [0.0, 0.25, 0.5, 0.75, 1.0]:
			visual.aim_angle = deg_to_rad(angle)
			visual.aim_blend = blend
			visual.apply_pose()
			var trigger_gap: float = visual.wrist_for(visual.trigger_arm).global_position.distance_to(visual.grip.get_node("TriggerWrist").global_position)
			var support_gap: float = visual.wrist_for(visual.support_arm).global_position.distance_to(visual.grip.get_node("SupportWrist").global_position)
			_check(trigger_gap < 0.05 and support_gap < 0.05, "Scene wrist markers remain on separate weapon through transition %.2f / %.0f" % [blend, angle])
	actor.reset_state(Vector2(500, 430))
	visual.aim_blend = 1.0
	visual.aim_angle = 0.0
	visual.apply_pose()
	await _ticks(3)
	var target: StaticBody2D = room.get_node("World/Targets/Target2")
	_check(actor.fire_current_pose(), "Production weapon fires in lab")
	_check(weapon.ammo == 11 and is_equal_approx(target.health, 80.0), "Real hitscan consumes ammo and damages the target")
	_check(visual.recoil > 0.9 and visual.flash.visible, "Successful shot drives recoil and muzzle flash")
	_check(not actor.fire_current_pose() and weapon.ammo == 11, "Existing rate limit prevents duplicate shot")
	visual.advance(0.2)
	_check(is_zero_approx(visual.recoil) and not visual.flash.visible, "Recoil and flash finish")
	weapon.request_reload()
	await _ticks(100)
	_check(weapon.ammo == 12 and not weapon.is_reloading, "Production reload restores magazine")
	# GUI and pause must not turn a held mouse press into a shot after returning.
	actor.input_enabled = true
	actor.input_blocked = false
	actor.suspend_input(true)
	actor.suspend_input(false)
	Input.action_press("shoot")
	await _ticks(30)
	_check(weapon.ammo == 12, "Resume blocks held fire until release")
	Input.action_release("shoot")
	await _ticks(2)
	visual.set_physics_process(true)
	Input.action_press("shoot")
	await _ticks(8)
	_check(weapon.ammo == 12, "Fire waits for weapon raise")
	await _ticks(18)
	_check(weapon.ammo < 12, "Held fire works after raising")
	Input.action_release("shoot")
	await _ticks(45)
	# Owner accepted RMB preparation: LMB must not restart the raise when ready.
	var aim_button := InputEventMouseButton.new()
	aim_button.button_index = MOUSE_BUTTON_RIGHT
	aim_button.pressed = true
	aim_button.position = Vector2(700, 380)
	# Parse through Input as well: Viewport.push_input alone does not update the
	# global mouse-button state read by the real controller.
	Input.parse_input_event(aim_button)
	await _ticks(20)
	_check(visual.aim_blend >= 0.98, "RMB prepares weapon without firing")
	var ready_ammo: int = weapon.ammo
	Input.action_press("shoot")
	await _ticks(2)
	_check(weapon.ammo == ready_ammo - 1, "LMB fires immediately from RMB-ready pose without raising again")
	Input.action_release("shoot")
	aim_button = aim_button.duplicate()
	aim_button.pressed = false
	Input.parse_input_event(aim_button)
	await _key(KEY_C)
	_check(actor.sneaking and room.get_node("UI/Panel/Sneak").button_pressed, "C switches lab actor and visible toggle to sneak")
	await _ticks(16)
	var sneak_start := actor.position
	Input.action_press("move_right")
	await _ticks(20)
	Input.action_release("move_right")
	_check(actor.position.x - sneak_start.x > 18.0 and actor.position.x - sneak_start.x < 30.0, "Sneak preview moves more slowly without changing base move speed")
	await _key(KEY_C)
	_check(not actor.sneaking, "C restores ordinary walk")
	var pause: Control = room.get_node("UI/PauseMenu")
	pause.set_open(true)
	var before := actor.position
	var frozen_blend: float = visual.aim_blend
	Input.action_press("move_right")
	await _ticks(8)
	_check(actor.position == before and is_equal_approx(visual.aim_blend, frozen_blend), "Pause freezes movement and pose")
	Input.action_release("move_right")
	pause.set_open(false)
	room.get_node("UI/Panel/Sneak").button_pressed = true
	await _key(KEY_F2)
	_check(actor.position == Vector2(380, 430) and weapon.ammo == 12, "F2 resets only the lab actor")
	_check(is_equal_approx(target.health, target.max_health), "F2 restores damageable targets")
	_check(actor.sneaking and visual.sneak_blend >= 0.99, "F2 preserves the selected gait for repeated comparisons")
	await _check_directions(room, actor)
	_check_rear_leg_joins(visual)
	_check_projected_gaits(visual)
	room.free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check_directions(room: Node2D, actor: CharacterBody2D) -> void:
	var visual: Node2D = actor.visual
	actor.input_enabled = false
	visual.set_physics_process(false)
	actor.set_sneaking(false)
	var probe: StaticBody2D = load("res://tests/fixtures/target.tscn").instantiate()
	room.get_node("World").add_child(probe)
	for index in 8:
		visual.direction_override = -1
		actor.reset_state(Vector2(460, 430))
		var bearing := index * PI / 4.0
		visual.aim_angle = bearing
		visual.aim_blend = 1.0
		visual.apply_pose()
		_check(visual.direction_index == index and is_zero_approx(visual.rig.rotation), "Saved upright body view selected for direction %d" % index)
		var grips_ok := true
		var barrel_ok := true
		for offset in [-18.0, 0.0, 18.0]:
			for blend in [0.0, 0.5, 1.0]:
				visual.aim_angle = bearing + deg_to_rad(offset)
				visual.aim_blend = blend
				visual.apply_pose()
				grips_ok = grips_ok and visual.wrist_for(visual.trigger_arm).global_position.distance_to(visual.grip.get_node("TriggerWrist").global_position) < 0.05
				grips_ok = grips_ok and visual.wrist_for(visual.support_arm).global_position.distance_to(visual.grip.get_node("SupportWrist").global_position) < 0.05
				if blend == 1.0:
					var muzzle_direction: Vector2 = (visual.model.to_local(visual.muzzle.to_global(Vector2.RIGHT)) - visual.muzzle_offset()).normalized()
					barrel_ok = barrel_ok and muzzle_direction.dot(Vector2.from_angle(visual.aim_angle)) > 0.9999
		_check(grips_ok, "Both hands retain independent weapon grips while raising/aiming in direction %d" % index)
		_check(barrel_ok, "Drawn barrel follows continuous aim inside direction %d" % index)
		visual.aim_angle = bearing
		visual.aim_blend = 1.0
		visual.apply_pose()
		probe.position = actor.position + Vector2.from_angle(bearing) * 150.0
		probe.health = probe.max_health
		await _ticks(3)
		var shot_origin: Vector2 = visual.muzzle_offset()
		_check(actor.fire_current_pose() and is_equal_approx(probe.health, 80.0), "Real hitscan hits the intended ground target in direction %d" % index)
		_check((actor.weapon.position + Vector2.from_angle(bearing) * 32.0).distance_to(shot_origin) < 0.05, "Shot presentation starts at the pre-recoil muzzle in direction %d" % index)
	probe.queue_free()
	visual.direction_override = -1
	var full_circle_grips := true
	var full_circle_barrel := true
	var largest_gap := 0.0
	var largest_gap_pose := ""
	visual.recoil = 0.0
	visual.phase = 1.7
	for degrees in range(0, 360, 3):
		for blend in [0.0, 0.5, 1.0]:
			visual.aim_angle = deg_to_rad(degrees)
			visual.aim_blend = blend
			visual.apply_pose()
			var gap: float = maxf(visual.wrist_for(visual.trigger_arm).global_position.distance_to(visual.grip.get_node("TriggerWrist").global_position), visual.wrist_for(visual.support_arm).global_position.distance_to(visual.grip.get_node("SupportWrist").global_position))
			if gap > largest_gap:
				largest_gap = gap
				largest_gap_pose = "%d degrees, blend %.1f, view %d" % [degrees, blend, visual.direction_index]
			full_circle_grips = full_circle_grips and visual.wrist_for(visual.trigger_arm).global_position.distance_to(visual.grip.get_node("TriggerWrist").global_position) < 0.05
			full_circle_grips = full_circle_grips and visual.wrist_for(visual.support_arm).global_position.distance_to(visual.grip.get_node("SupportWrist").global_position) < 0.05
			if blend == 1.0:
				var muzzle_direction: Vector2 = (visual.model.to_local(visual.muzzle.to_global(Vector2.RIGHT)) - visual.muzzle_offset()).normalized()
				full_circle_barrel = full_circle_barrel and muzzle_direction.dot(Vector2.from_angle(visual.aim_angle)) > 0.9999
	for degrees in range(0, 360, 3):
		for blend in [0.0, 0.5, 1.0]:
			visual.aim_angle = deg_to_rad(degrees)
			visual.aim_blend = blend
			visual.recoil = 1.0
			visual.apply_pose()
			var gap: float = maxf(visual.wrist_for(visual.trigger_arm).global_position.distance_to(visual.grip.get_node("TriggerWrist").global_position), visual.wrist_for(visual.support_arm).global_position.distance_to(visual.grip.get_node("SupportWrist").global_position))
			full_circle_grips = full_circle_grips and gap < 0.05
			if gap > largest_gap:
				largest_gap = gap
				largest_gap_pose = "%d degrees, blend %.1f, view %d, recoil" % [degrees, blend, visual.direction_index]
	visual.recoil = 0.0
	_check(full_circle_grips, "Dense full-circle sweep retains grips through sector boundaries, raises and recoil (max %.3f px at %s)" % [largest_gap, largest_gap_pose])
	_check(full_circle_barrel, "Dense full-circle sweep keeps barrel direction continuous across the angle wrap")
	_check(is_equal_approx(visual.phase, 1.7), "View changes preserve gait phase")
	for index in [5, 7]:
		visual.direction_override = index
		visual.reset_pose()
		_check(visual.trigger_arm.position.x > visual.support_arm.position.x, "Rear-diagonal near arm attaches on the visible shoulder side before mirroring: view %d" % index)
		var torso_layer: int = visual.upper.get_node("Torso").z_index
		var near_forearm_layer: int = visual.trigger_arm.z_index + visual.trigger_arm.get_node("Forearm").z_index
		_check(visual.trigger_arm.z_index > torso_layer and near_forearm_layer < torso_layer and visual.support_arm.z_index < torso_layer, "Rear torso occludes forward forearms while the nearer upper arm covers its shoulder join: view %d" % index)
		var elbows_relaxed := true
		var elbows_continuous := true
		var largest_elbow_step := 0.0
		for offset in [-18.0, 0.0, 18.0]:
			visual.aim_angle = index * PI / 4.0 + deg_to_rad(offset)
			var previous_elbows: Array[Vector2] = []
			for sample in 101:
				visual.aim_blend = sample / 100.0
				visual.apply_pose()
				var current_elbows: Array[Vector2] = []
				for arm in [visual.support_arm, visual.trigger_arm]:
					var elbow: Vector2 = visual.upper.to_local(arm.get_node("Forearm").global_position)
					current_elbows.append(elbow)
					if sample <= 25:
						elbows_relaxed = elbows_relaxed and elbow.y >= arm.position.y + 3.0
				if not previous_elbows.is_empty():
					largest_elbow_step = maxf(largest_elbow_step, maxf(previous_elbows[0].distance_to(current_elbows[0]), previous_elbows[1].distance_to(current_elbows[1])))
					elbows_continuous = elbows_continuous and largest_elbow_step < 1.0
				previous_elbows = current_elbows
		_check(elbows_relaxed, "Lowered rear-diagonal elbows stay below shoulders, including sector edges: view %d" % index)
		_check(elbows_continuous, "Rear-diagonal elbows follow a continuous path while raising: view %d, max step %.3f px" % [index, largest_elbow_step])
	visual.direction_override = -1
	visual.aim_angle = 0.0
	visual.apply_pose()
	for angle in [21.0, 23.0]:
		visual.aim_angle = deg_to_rad(angle)
		visual.apply_pose()
		_check(visual.direction_index == 0, "Small boundary jitter retains east view at %.0f degrees" % angle)
	visual.aim_angle = deg_to_rad(27.0)
	visual.apply_pose()
	_check(visual.direction_index == 1, "Turning beyond hysteresis selects southeast")
	visual.aim_angle = deg_to_rad(23.0)
	visual.apply_pose()
	_check(visual.direction_index == 1, "Returning close to boundary does not flicker views")
	visual.aim_angle = deg_to_rad(18.0)
	visual.apply_pose()
	_check(visual.direction_index == 0, "A deliberate return selects east")
	actor.input_enabled = true
	visual.set_physics_process(true)
	for index in 8:
		var point := actor.position + Vector2(0, -48) + Vector2.from_angle(index * PI / 4.0) * 190.0
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		await _ticks(3)
		_check(visual.direction_index == index, "Actual mouse input can aim through direction %d without the former right-only clamp" % index)
	room._preview_direction(7)
	_check(visual.direction_index == 6, "Inspector preview dropdown can hold the north view")
	actor.reset_state(actor.position)
	_check(visual.direction_index == 6, "Reset preserves selected direction preview")
	room._preview_direction(0)
	var contacts: Array[float] = []
	var footsteps: Node2D = actor.get_node("Footsteps")
	var record := func(_profile: FootstepProfile, _clip: AudioStream): contacts.append(fposmod(visual.phase / TAU - (0.0 if visual._motion_direction > 0.0 else lerpf(visual.walk_gait.stance_fraction, visual.sneak_gait.stance_fraction, visual.sneak_blend)), 0.5))
	footsteps.step_played.connect(record)
	for sneak in [false, true]:
		for index in 8:
			visual.direction_override = index
			actor.set_sneaking(sneak)
			for move_index in 8:
				actor.reset_state(Vector2(460, 430))
				contacts.clear()
				var direction := Vector2.from_angle(move_index * PI / 4.0)
				var actions: Array[String] = []
				if absf(direction.x) > 0.5:
					actions.append("move_right" if direction.x > 0.0 else "move_left")
				if absf(direction.y) > 0.5:
					actions.append("move_down" if direction.y > 0.0 else "move_up")
				for action in actions:
					Input.action_press(action)
				await _ticks(45)
				for action in actions:
					Input.action_release(action)
				await _ticks(2)
				_check(contacts.size() == (1 if sneak else 2) and visual.direction_index == index, "Real %s cadence: look %d, movement %d" % ["sneak" if sneak else "walk", index, move_index])
				_check(contacts.all(func(offset: float): return minf(offset, 0.5 - offset) <= 0.025), "Audio lands on contact phases: look %d, movement %d" % [index, move_index])
	footsteps.step_played.disconnect(record)
	visual.direction_override = -1
	actor.set_sneaking(false)
	actor.reset_state(Vector2(380, 430))

func _check_rear_leg_joins(visual: Node2D) -> void:
	visual.set_physics_process(false)
	for index in [5, 7]:
		visual.direction_override = index
		visual.reset_pose()
		var torso: Sprite2D = visual.upper.get_node("Torso")
		var body := torso.texture.get_image()
		var source: Image = visual.near_leg.get_node("Thigh").texture.get_image()
		var ground: float = visual.model.global_position.y
		_check(absf(_sole_y(visual.near_foot) - ground) < 0.05 and absf(_sole_y(visual.far_foot) - ground) < 0.05, "Reanchored rear legs keep their resting soles on the ground: view %d" % index)
		var minimum_coverage := 1.0
		for sneak in [0.0, 0.5, 1.0]:
			visual.sneak_blend = sneak
			for gait in [0.0, 0.5, 1.0]:
				visual.gait_blend = gait
				for direction in 8:
					visual.motion_vector = Vector2.from_angle(direction * PI / 4.0)
					for sample in 32:
						visual.phase = sample * TAU / 32.0
						visual.apply_pose()
						for leg in [visual.near_leg, visual.far_leg]:
							minimum_coverage = minf(minimum_coverage, _waist_hidden_fraction(leg.get_node("Thigh"), torso, source, body))
		_check(minimum_coverage >= 0.7, "Painted rear thigh tops stay tucked into the torso through both gaits, transitions and all movement directions: view %d, min %.0f%%" % [index, minimum_coverage * 100.0])

func _check_projected_gaits(visual: Node2D) -> void:
	for index in 8:
		visual.direction_override = index
		visual.reset_pose()
		for sneak in [0.0, 0.5, 1.0]:
			visual.sneak_blend = sneak
			var joints_continuous := true
			var knees_in_lane := true
			var feet_in_lane := true
			var minimum_projection := 1.0
			var maximum_step := 0.0
			for movement in 8:
				visual.motion_vector = Vector2.from_angle(movement * PI / 4.0)
				for gait in [0.25, 0.5, 1.0]:
					visual.gait_blend = gait
					var previous: Array[Vector2] = []
					for frame in 65:
						visual.phase = frame * TAU / 64.0
						visual.apply_pose()
						var current: Array[Vector2] = []
						for leg in [visual.near_leg, visual.far_leg]:
							var shin: Node2D = leg.get_node("Shin")
							var foot: Node2D = shin.get_node("Foot")
							var hip: Vector2 = visual.model.to_local(leg.global_position)
							var knee: Vector2 = visual.model.to_local(shin.global_position)
							var ankle: Vector2 = visual.model.to_local(foot.global_position)
							current.append(knee)
							current.append(ankle)
							minimum_projection = minf(minimum_projection, minf(leg.get_node("Thigh").transform.determinant(), shin.get_node("Image").transform.determinant()))
							if index in [2, 6]:
								knees_in_lane = knees_in_lane and knee.x >= minf(hip.x, ankle.x) - 1.0 and knee.x <= maxf(hip.x, ankle.x) + 1.0
						if index in [2, 6]:
							feet_in_lane = feet_in_lane and current[1].x + 1.0 < current[3].x
						if not previous.is_empty():
							for point in current.size():
								maximum_step = maxf(maximum_step, current[point].distance_to(previous[point]))
						previous = current
			joints_continuous = maximum_step < 2.0 and minimum_projection > 0.35
			_check(joints_continuous, "Full gait stays continuous without collapsed segments: look %d, sneak %.1f, max step %.2f px, min length %.2f" % [index, sneak, maximum_step, minimum_projection])
			if index in [2, 6]:
				_check(knees_in_lane and feet_in_lane, "Front/back knees stay in hip/foot lanes without bowing or crossing through all movement directions: look %d, sneak %.1f" % [index, sneak])
		visual.reset_pose()
		_check(visual.near_shin.position.is_equal_approx(visual.rig.near_segments[0]) and visual.far_shin.position.is_equal_approx(visual.rig.far_segments[0]) and visual.near_foot.position.is_equal_approx(visual.rig.near_segments[1]) and visual.far_foot.position.is_equal_approx(visual.rig.far_segments[1]), "Stopping restores saved segment geometry without accumulated stretching: look %d" % index)

func _waist_hidden_fraction(mesh: Polygon2D, torso: Sprite2D, source: Image, body: Image) -> float:
	# Sample the actual opaque waist texels, not just a mathematically attached
	# bone. A joint at the texture centre previously left the painted hip outside.
	var count := 0
	var covered := 0
	var uvs := mesh.uv
	for x in range(roundi(uvs[0].x), roundi(uvs[1].x)):
		var uv := Vector2(x + 0.5, uvs[0].y + 1.5)
		if source.get_pixelv(Vector2i(uv)).a < 0.6:
			continue
		var fraction := (uv - uvs[0]) / (uvs[2] - uvs[0])
		var point := mesh.polygon[0] + (mesh.polygon[1] - mesh.polygon[0]) * fraction.x + (mesh.polygon[3] - mesh.polygon[0]) * fraction.y
		var body_point := Vector2i(torso.to_local(mesh.to_global(point)).floor())
		count += 1
		if Rect2i(Vector2i.ZERO, body.get_size()).has_point(body_point) and body.get_pixelv(body_point).a >= 0.6:
			covered += 1
	return float(covered) / maxi(count, 1)

func _sole_y(foot: Node2D) -> float:
	return maxf(foot.get_node("Heel").global_position.y, foot.get_node("Toe").global_position.y)

func _check_foot_contacts(actor: CharacterBody2D) -> void:
	var visual: Node2D = actor.visual
	var footsteps: Node2D = actor.get_node("Footsteps")
	var contacts: Array[Dictionary] = []
	var record := func(_profile: FootstepProfile, _clip: AudioStream) -> void:
		var landing := 0.0 if actor.velocity.x >= 0.0 else lerpf(visual.walk_gait.stance_fraction, visual.sneak_gait.stance_fraction, visual.sneak_blend)
		var offset := fposmod(visual.phase / TAU - landing, 0.5)
		var ground: float = visual.get_node("Pixels/Model").global_position.y
		contacts.append({"phase_error": minf(offset, 0.5 - offset), "sole_error": minf(absf(_sole_y(visual.near_foot) - ground), absf(_sole_y(visual.far_foot) - ground))})
	footsteps.step_played.connect(record)
	for direction in ["move_right", "move_left"]:
		actor.reset_state(Vector2(380, 430))
		contacts.clear()
		Input.action_press(direction)
		await _ticks(75)
		Input.action_release(direction)
		await _ticks(2)
		var paused_contacts := contacts.size()
		await _ticks(20)
		_check(contacts.size() == paused_contacts, "Standing produces no extra foot contacts: " + direction)
		Input.action_press(direction)
		await _ticks(45)
		Input.action_release(direction)
		await _ticks(2)
		_check(contacts.size() == 5, "Slower walking cadence survives stop/resume without extra distance-driven sounds: " + direction)
		_check(contacts.all(func(contact: Dictionary): return contact.phase_error <= 0.025 and contact.sole_error <= 0.06), "Every sound starts at a rendered foot landing: " + direction)
	actor.set_sneaking(true)
	actor.reset_state(Vector2(380, 430))
	contacts.clear()
	Input.action_press("move_right")
	await _ticks(120)
	Input.action_release("move_right")
	await _ticks(2)
	_check(contacts.size() == 3, "Sneaking uses the same contact-driven audio at its slower travel speed")
	_check(contacts.all(func(contact: Dictionary): return contact.phase_error <= 0.025 and contact.sole_error <= 0.06), "Sneak sounds also coincide with grounded soles")
	actor.input_enabled = false
	var before := contacts.size()
	visual.set_motion(1000.0, 120.0)
	visual.set_motion(0.0, 120.0)
	_check(contacts.size() == before, "Teleport or pushing into a wall cannot trigger contact sounds")
	footsteps.step_played.disconnect(record)
	actor.set_sneaking(false)
	actor.reset_state(Vector2(380, 430))
	actor.input_enabled = true
	await _ticks(2)
