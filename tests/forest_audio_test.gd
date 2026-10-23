extends "res://tests/loot_slots_test.gd"
## Actual forest surfaces, movement foley, native loop decoding and mixer lifecycle.

var _steps: Array[StringName] = []
var _brushes: Array[SoundCue] = []


func _walk(player: CharacterBody2D, direction: Vector2, ticks: int) -> void:
	for tick in range(ticks):
		await physics_frame
		player.velocity = direction * 240
		player.move_and_slide()
		player.moved.emit(player.get_position_delta().length())
		await process_frame
	player.velocity = Vector2.ZERO


func _energy(capture: AudioEffectCapture) -> float:
	var energy := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		energy += frame.length_squared()
	return energy


func _run() -> void:
	var room: Node2D = load("res://scenes/forest_dusk.tscn").instantiate()
	room.play_start_audio = false
	root.add_child(room)
	current_scene = room
	room.set_guards_active(false)
	var player: CharacterBody2D = room.get_node("Player")
	player.set_physics_process(false)
	var footsteps: Node2D = player.get_node("Footsteps")
	var foliage: Node2D = player.get_node("FoliageAudio")
	var ambience: Node2D = room.get_node("Ambience")
	footsteps.step_distance = 16.0
	footsteps.step_played.connect(func(profile: FootstepProfile, _clip: AudioStream): _steps.append(profile.surface_id))
	foliage.brush_played.connect(func(_patch: FootstepSurface, cue: SoundCue): _brushes.append(cue))
	await _ticks(5)
	var puddle: Sprite2D = room.get_node("Dressing/GroundDetails/puddle_0")
	var positions := {&"dirt": Vector2(470, 730), &"grass": Vector2(70, 650), &"wet_dirt": puddle.to_global(Vector2(200, 0)), &"puddle": puddle.global_position}
	for id in positions:
		_check(footsteps.profile_at(positions[id]).surface_id == id, "Actual forest ground resolves " + str(id))
		player.global_position = positions[id]
		footsteps.stop()
		_steps.clear()
		await _ticks(2)
		await _walk(player, Vector2.UP, 8)
		_check(_steps.has(id), "Real moved distance plays " + str(id) + " footsteps")
		var profile: FootstepProfile = footsteps.profile_at(positions[id])
		var previous: AudioStream
		var unique: Dictionary = {}
		var repeats := false
		for index in range(profile.clips.size() * 3):
			var clip: AudioStream = footsteps._next_clip(profile)
			repeats = repeats or previous == clip
			previous = clip
			unique[clip] = true
		_check(not repeats and unique.size() == profile.clips.size(), "All " + str(id) + " variants play without adjacent repeats")
	var second: Sprite2D = room.get_node("Dressing/GroundDetails/puddle_1")
	_check(footsteps.profile_at(second.global_position).surface_id == &"puddle", "Mirrored smaller puddle keeps its water profile")
	_check(footsteps.profile_at(puddle.to_global(Vector2(-180, -110))).surface_id == &"wet_dirt", "Transparent water canvas corners do not produce splashes")
	var courtyard: Polygon2D = room.get_node("Ground/Courtyard")
	var surface: FootstepSurface = courtyard.get_node("SoundSurface")
	var saved := courtyard.polygon
	courtyard.polygon = PackedVector2Array([Vector2(10, 10), Vector2(30, 10), Vector2(30, 30), Vector2(10, 30)])
	_check(surface.contains_point(Vector2(20, 20)) and not surface.contains_point(Vector2(470, 730)), "Editing the visible floor polygon updates sound bounds without a duplicate outline")
	courtyard.polygon = saved
	for family in ["dirt", "grass", "wet_dirt", "puddle"]:
		var profile: FootstepProfile = load("res://resources/audio/forest/footsteps_" + family + ".tres")
		_check(profile.clips.all(func(clip): return clip is AudioStreamWAV and clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.mix_rate == 48000 and not clip.stereo and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED), "Native uncompressed PCM imports for " + family)
	var shrub: Node2D = room.get_node("Dressing/Vegetation/Shrub1")
	player.global_position = shrub.global_position
	await _ticks(45)
	_check(_brushes.is_empty(), "Standing or teleporting into plants never starts a rustle")
	player.global_position = shrub.global_position - Vector2(40, 0)
	await _ticks(2)
	await _walk(player, Vector2.RIGHT, 24)
	_check(_brushes.size() == 1 and _brushes[0].id == &"bush_brush", "Walking through the real shrub gives one bounded bush rustle")
	var count := _brushes.size()
	await _ticks(45)
	_check(_brushes.size() == count, "A stationary player does not repeat plant foley")
	var grass: Node2D = room.get_node("Dressing/Vegetation/GrassTall1")
	player.global_position = grass.global_position
	await _ticks(2)
	await _walk(player, Vector2.RIGHT, 2)
	_check(_brushes.size() > count and _brushes.back().id == &"grass_brush", "Tall grass selects its separate rustle")
	_check(foliage.get_node("Player/A").bus == &"Footsteps" and foliage.get_node("Player/B").bus == &"Footsteps", "Plant movement uses the existing footsteps category")
	var before_pause: float = foliage._cooldown
	room.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(20)
	_check(is_equal_approx(foliage._cooldown, before_pause) and foliage.get_node("Player/B").stream_paused, "Pause freezes plant playback and rearming")
	room.get_node("HUD/PauseMenu").set_open(false)
	player.take_damage(1000)
	await _ticks(2)
	_check(not foliage.get_node("Player/A").playing and not foliage.get_node("Player/B").playing, "Death stops both rustle voices")
	room.restore_player()
	var added: String = room.spawn_guard(0)
	_check(added.begins_with("Охранник добавлен") and room.get_node("TestEnemies").get_child(0).has_node("FoliageAudio"), "F2 guards inherit current movement audio")
	var loop := ambience.background_stream as AudioStreamOggVorbis
	_check(loop != null and loop.loop and absf(loop.get_length() - 29.88) < 0.01, "Forest bed imports as the prepared stereo loop")
	var playback := loop.instantiate_playback()
	playback.start(loop.get_length() - 0.05)
	var frames := playback.mix_audio(1.0, ceili(AudioServer.get_mix_rate() * 0.15))
	var before := 0.0
	var after := 0.0
	var edge := int(AudioServer.get_mix_rate() * 0.05)
	for index in range(frames.size()):
		if index < edge:
			before += frames[index].length_squared()
		else:
			after += frames[index].length_squared()
	_check(before > 0.001 and after > 0.001 and (frames[edge] - frames[edge-1]).length() < 0.08, "Native forest decoder crosses the join without silence or a large discontinuity")
	_check(ambience.first_detail_delay.x >= 12 and ambience.detail_interval.x >= 25 and ambience.get_node("Details").get_child_count() == 4, "Animal, wind and wood details remain sparse and separate from the loop")
	# Capture downstream of the category fader, not its pre-fader effects.
	root.get_node("RaidAudio").stop(0.0)
	for category in root.get_node("AudioSettings").CATEGORIES:
		if category.id not in [&"master", &"ambience"]:
			root.get_node("AudioSettings").set_volume(category.id, 0)
	var bus := AudioServer.get_bus_index(&"Mix")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	await _ticks(12)
	_check(_energy(capture) > 0.001 and ambience.bed.bus == &"Ambience", "Forest bed reaches the existing ambience mixer bus")
	root.get_node("AudioSettings").set_volume(&"ambience", 0)
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(10)
	_check(_energy(capture) < 0.00001, "Saved category routing lets ambience mute silence the forest")
	root.get_node("AudioSettings").reset_defaults(false)
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus)-1)
	room.free()
	await _ticks(3)
	_check(not is_instance_valid(ambience) and not is_instance_valid(foliage), "Leaving the forest removes its background and plant voices")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
