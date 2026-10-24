extends "res://tests/loot_slots_test.gd"
## Real body motion, surface lookup, variants and lifecycle; no synthetic movement timer.

var _player_steps: Array[AudioStream] = []
var _guard_steps: Array[AudioStream] = []
var _surfaces: Array[StringName] = []
var _travel: float = 0.0


func _run() -> void:
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	guard.set_physics_process(false)
	var footsteps: Node2D = player.get_node("Footsteps")
	var enemy_steps: Node2D = guard.get_node("Footsteps")
	footsteps.step_played.connect(func(profile: FootstepProfile, clip: AudioStream):
		_player_steps.append(clip)
		_surfaces.append(profile.surface_id))
	enemy_steps.step_played.connect(func(_profile: FootstepProfile, clip: AudioStream): _guard_steps.append(clip))
	player.moved.connect(func(distance: float): _travel += distance)
	var deck: FootstepSurface = yard.get_node("Surfaces/MetalDeck")
	await _ticks(3)
	_check(footsteps.default_profile.clips.size() == 3 and deck.profile.clips.size() == 4, "Concrete has three and metal four owner-selected recordings")
	_check(footsteps.default_profile != deck.profile and footsteps.default_profile.surface_id == &"concrete", "Actor fallback profile is concrete without changing shared surface data")
	var floor_query := PhysicsRayQueryParameters2D.create(deck.global_position - Vector2(0, 40), deck.global_position + Vector2(0, 40), 1)
	_check(deck.get_world_2d().direct_space_state.intersect_ray(floor_query).is_empty(), "Metal deck does not block world collision or bullets")
	_check(footsteps.profile_at(deck.global_position) == deck.profile and footsteps.profile_at(Vector2(300, 600)) == footsteps.default_profile, "Material lookup agrees with visible deck bounds")
	_check(footsteps.profile_at(deck.global_position + Vector2(0, 60)) == footsteps.default_profile, "Walking off the deck restores default ground material")
	await _ticks(70)
	_check(_player_steps.is_empty() and _guard_steps.is_empty(), "Stationary actors produce no footsteps")
	player.global_position = Vector2(300, 600)
	Input.action_press("move_right")
	await _ticks(60)
	Input.action_release("move_right")
	await _ticks(1)
	_check(_player_steps.size() == floori(_travel / footsteps.step_distance) and _player_steps.size() >= 3, "Cadence follows actual travelled pixels instead of time or input presses")
	_check(_surfaces.all(func(id: StringName): return id == &"concrete"), "Concrete travel selects concrete recordings")
	var count := _player_steps.size()
	await _ticks(50)
	_check(_player_steps.size() == count, "Stopping does not continue a step loop")
	player.global_position = Vector2(150, 600)
	footsteps.stop()
	Input.action_press("move_left")
	await _ticks(65)
	var wall_count := _player_steps.size()
	await _ticks(45)
	Input.action_release("move_left")
	await _ticks(1)
	_check(_player_steps.size() == wall_count and player.global_position.x >= 114.0, "Holding movement into a wall cannot create footsteps")
	player.global_position = Vector2(390, 700)
	footsteps.stop()
	Input.action_press("move_right")
	await _ticks(40)
	Input.action_release("move_right")
	await _ticks(1)
	_check(_surfaces.back() == &"metal" and _player_steps.size() > wall_count, "Real movement over deck selects metal footsteps")
	count = _player_steps.size()
	player.global_position = Vector2(900, 940)
	await _ticks(10)
	_check(_player_steps.size() == count, "Teleporting a stationary actor does not sound like walking")
	Input.action_press("move_right")
	await _ticks(5)
	await _key(KEY_ESCAPE)
	count = _player_steps.size()
	var pause_position := player.global_position
	await _ticks(90)
	_check(paused and player.global_position == pause_position and _player_steps.size() == count, "Pause freezes movement and step scheduling")
	Input.action_release("move_right")
	await _key(KEY_ESCAPE)
	await _key(KEY_TAB)
	Input.action_press("move_left")
	await _ticks(40)
	Input.action_release("move_left")
	_check(_player_steps.size() == count, "Open backpack blocks player movement and new footsteps")
	await _key(KEY_ESCAPE)

	# Walk a longer route to cross a shuffle refill boundary.
	player.global_position = Vector2(250, 600)
	footsteps.stop()
	_player_steps.clear()
	_surfaces.clear()
	footsteps.step_distance = 24.0
	player.body_visual.stride_distance_override = 48.0
	Input.action_press("move_right")
	await _ticks(130)
	Input.action_release("move_right")
	await _ticks(1)
	var no_repeats := true
	for index in range(1, _player_steps.size()):
		no_repeats = no_repeats and _player_steps[index] != _player_steps[index - 1]
	_check(_player_steps.size() > 16 and no_repeats, "Shuffle bags avoid adjacent repeated recordings even across refill")
	_check(footsteps.default_profile.clips.size() == 3 and deck.profile.clips.size() == 4, "Playing variants does not remove clips from shared resources")
	_check(footsteps.get_node("Left").bus == &"Footsteps" and footsteps.get_node("Right").bus == &"Footsteps" and footsteps.get_node("Right").max_distance == 620.0, "Both overlapping foot voices use their category with bounded audibility")
	_check(footsteps.get_node("Left").pitch_scale >= 0.975 and footsteps.get_node("Left").pitch_scale <= 1.025, "Pitch variation stays subtle")

	guard.set_physics_process(true)
	await _ticks(90)
	guard.set_physics_process(false)
	_check(not _guard_steps.is_empty(), "Normal guard AI emits footsteps while moving along its actual route")
	var initial_guard_count := _guard_steps.size()
	guard.target = null
	guard.global_position = Vector2(480, 700)
	guard.velocity = Vector2(120, 0)
	for index in range(60):
		await physics_frame
		guard.move_and_slide()
		guard.moved.emit(guard.get_position_delta().length())
		await process_frame
	_check(_guard_steps.size() > initial_guard_count, "Enemy instance uses the same travel-based footstep component on metal")
	var guard_count := _guard_steps.size()
	guard.take_damage(1000)
	guard.moved.emit(100.0)
	_check(_guard_steps.size() == guard_count and not enemy_steps.get_node("Left").playing and not enemy_steps.get_node("Right").playing, "Enemy death silences feet and prevents further playback")
	player.take_damage(1000)
	count = _player_steps.size()
	Input.action_press("move_right")
	await _ticks(30)
	Input.action_release("move_right")
	_check(player.is_dead and _player_steps.size() == count and not footsteps.get_node("Left").playing, "Player death stops footsteps without a kill notification sound")
	yard.queue_free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
