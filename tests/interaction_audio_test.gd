extends "res://tests/loot_slots_test.gd"
## Real source decoding, SFX capture, cancellation and pause with Dummy audio.

const CUE_NAMES = ["heal_start", "heal_process", "heal_finish", "container_open", "container_close", "search", "reveal", "move", "drop", "pickup"]


func _peak(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _capture_peak(capture: AudioEffectCapture) -> float:
	return _peak(capture.get_buffer(capture.get_frames_available()))


func _strongest_rms(frames: PackedVector2Array) -> float:
	# Compare 100 ms of energy, not a single lid impact against a gunshot sample.
	var window := mini(frames.size(), ceili(AudioServer.get_mix_rate() * 0.1))
	if window == 0:
		return 0.0
	var energy := 0.0
	var strongest := 0.0
	for index in range(frames.size()):
		energy += frames[index].length_squared() * 0.5
		if index >= window:
			energy -= frames[index - window].length_squared() * 0.5
		if index >= window - 1:
			strongest = maxf(strongest, energy)
	return sqrt(strongest / window)


func _wait_playing(sound: Node) -> bool:
	for tick in range(90):
		if sound.is_playing():
			return true
		await _ticks(1)
	return false


func _valid_recording(clip: AudioStream) -> bool:
	if clip is AudioStreamWAV:
		return clip.format == AudioStreamWAV.FORMAT_16_BITS and not clip.stereo and clip.mix_rate == 48000 and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED
	return false


func _run() -> void:
	var cues: Array[SoundCue] = []
	var recordings: Dictionary = {}
	for cue_name: String in CUE_NAMES:
		var cue := load("res://resources/audio/interactions/" + cue_name + ".tres") as SoundCue
		cues.append(cue)
		var valid := cue != null and not cue.clips.is_empty()
		for clip in cue.clips:
			var playback := clip.instantiate_playback()
			playback.start()
			var frames := playback.mix_audio(1.0, ceili(clip.get_length() * AudioServer.get_mix_rate()) + 1024)
			var peak := _peak(frames)
			valid = valid and _valid_recording(clip) and clip.get_length() > 0.03 and clip.get_length() < 5.0
			valid = valid and is_finite(peak) and peak > 0.01 and peak * db_to_linear(cue.volume_db) < 0.9
			recordings[clip.resource_path] = {"duration": clip.get_length(), "peak": peak}
		_check(valid, "Cue has valid recorded, non-looping source clips: " + cue_name)
	_check(recordings.size() == 19, "Nineteen owner-selected recordings serve all ten interaction cues")
	var start_budget := cues[0].clips[0].get_length() / (1.0 - cues[0].pitch_variation)
	var process_budget := 0.0
	for clip in cues[1].clips:
		process_budget = maxf(process_budget, clip.get_length() / (1.0 - cues[1].pitch_variation))
	_check(start_budget <= 0.6 and start_budget + process_budget < preload("res://resources/items/medkit.tres").use_duration, "Even slowest pitch leaves room for preparation and a full treatment variant within three seconds")
	_check(cues[1].clips.size() == 3 and cues[1].weight_at(0) > cues[1].weight_at(1) and cues[5].clips.size() == 2 and cues[7].clips.size() == 4, "Treatment, searching and movement retain prioritized variants from the owner's bank")
	var file := FileAccess.open("res://artifacts/interaction_levels.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(recordings, "\t"))
	file.close()
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").process_mode = Node.PROCESS_MODE_DISABLED
	var actor_audio: Node2D = player.get_node("InteractionAudio")
	var sound: Node = actor_audio.get_node("HealAction")
	var move_sound: Node = yard.get_node("HUD/LootMenu/InventoryAudio/Move")
	var bus := AudioServer.get_bus_index(&"SFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 6.0
	AudioServer.add_bus_effect(bus, capture)
	await _ticks(4)
	var loudest := 0.0
	var quietest := INF
	var mix_levels: Dictionary = {}
	for cue in cues:
		sound.stop(0.0)
		move_sound.stop(0.0)
		capture.clear_buffer()
		var cue_sound: Node = move_sound if cue.id == &"move" else sound
		cue_sound.play(cue)
		var longest := 0.0
		for clip in cue.clips:
			longest = maxf(longest, clip.get_length())
		await _ticks(ceili(longest * 60.0 / (1.0 - cue.pitch_variation)) + 8)
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := _peak(frames)
		var rms := _strongest_rms(frames)
		loudest = maxf(loudest, rms)
		quietest = minf(quietest, rms)
		mix_levels[cue.id] = {"peak": peak, "strongest_100ms_rms": rms}
		_check(peak > 0.0005 and peak < 0.8, "Cue reaches SFX mixer at an unclipped level: " + str(cue.id))
	_check(quietest > 0.001 and loudest / quietest < 2.5, "Actual world and inventory cues remain within a compact active-energy range")
	sound.stop(0.0)
	move_sound.stop(0.0)
	var shot: AudioStreamPlayer2D = player.get_node("Aim/Weapon/Audio/Shot")
	var variants := shot.stream as AudioStreamRandomizer
	var selection_mode := variants.playback_mode
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_SEQUENTIAL
	for index in range(variants.streams_count):
		shot.stop()
		await _ticks(6)
		capture.clear_buffer()
		shot.play()
		await _ticks(25)
		var shot_frames := capture.get_buffer(capture.get_frames_available())
		mix_levels["gunshot_%d" % index] = {"peak": _peak(shot_frames), "strongest_100ms_rms": _strongest_rms(shot_frames)}
		_check(loudest < _strongest_rms(shot_frames), "Interaction energy stays below carbine variant %d in the actual mixer" % (index + 1))
	shot.stop()
	variants.playback_mode = selection_mode
	file = FileAccess.open("res://artifacts/interaction_mix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(mix_levels, "\t"))
	file.close()
	var empty := SoundCue.new()
	_check(not sound.play(empty), "Unconfigured cue is safely silent")
	sound.play(cues[1])
	await _ticks(6)
	var previous: Node = sound.get_node("A") if sound.get_node("A").playing else sound.get_node("B")
	_check(sound.remaining_time() > 2.0, "Overlap scheduling follows the selected voice playback rather than a guessed interval")
	sound.crossfade(cues[2], 0.24)
	await _ticks(5)
	var incoming: Node = sound.get_node("B") if previous.name == &"A" else sound.get_node("A")
	_check(previous.playing and incoming.playing and previous.volume_db > -20.0 and incoming.volume_db > -20.0, "Both recorded phases have audible gain inside the crossfade")
	var held_gains := Vector2(previous.volume_db, incoming.volume_db)
	paused = true
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(10)
	_check(held_gains.is_equal_approx(Vector2(previous.volume_db, incoming.volume_db)) and _capture_peak(capture) < 0.0001, "Pause freezes overlap envelopes and silences their voices")
	paused = false
	await _ticks(15)
	_check(not previous.playing and incoming.playing, "Outgoing voice stops only after its fade; incoming completion continues")
	# Reusing a voice must cancel its old fade callback before that callback can stop it.
	sound.crossfade(cues[1], 0.24)
	await _ticks(3)
	sound.crossfade(cues[2], 0.24)
	await _ticks(3)
	sound.crossfade(cues[1], 0.24)
	await _ticks(20)
	_check(sound.is_playing() and sound.remaining_time() > 1.7 and sound.get_child_count() == 2, "Rapid phase changes reuse two voices without stale fade callbacks stopping the newest sound")
	sound.stop()
	await _ticks(5)
	_check(not sound.is_playing(), "Cancellation stops incoming and outgoing voices even during crossfades")
	var menu: Control = yard.get_node("HUD/LootMenu")
	_check(menu.get_node("InventoryAudio/Move/A") is AudioStreamPlayer and sound.get_node("A") is AudioStreamPlayer2D, "Inventory feedback is nonpositional while physical actions are positional")
	player.global_position = Vector2(575, 690)
	player.get_node("Aim").global_rotation = 0.0
	var box: StaticBody2D = yard.get_node("LootContainers/Supply")
	var searching: Node = box.get_node("Audio/Search")
	menu.open_container(box)
	await _ticks(35)
	_check(await _wait_playing(searching), "Open unknown container runs recorded search Foley")
	yard.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(15)
	_check(_capture_peak(capture) < 0.0001, "Pause silences container and other interaction voices")
	yard.get_node("HUD/PauseMenu").set_open(false)
	box.get_node("Audio/Action").stop(0.0)
	box.get_node("Audio/Reveal").stop(0.0)
	await _ticks(8)
	_check(not searching.is_playing(), "Closed source stops search after its short fade")
	var slots: Array[ItemDefinition] = [preload("res://resources/items/medkit.tres"), null, null, null, null, null]
	player.get_node("Inventory").replace_slots(slots)
	player.take_damage(40.0)
	await _ticks(35)
	var use: Node = player.get_node("ItemUse")
	use.request_use(0)
	await _ticks(70)
	_check(await _wait_playing(actor_audio.get_node("HealProcess")), "Ongoing application plays physical treatment recordings")
	use.cancel()
	await _ticks(8)
	capture.clear_buffer()
	await _ticks(12)
	_check(not actor_audio.get_node("HealProcess").is_playing() and _capture_peak(capture) < 0.0001, "Cancelled treatment fades to silence without a completion signal")
	yard.free()
	await _ticks(10)
	capture.clear_buffer()
	await _ticks(12)
	_check(_capture_peak(capture) < 0.0001, "Leaving scene does not leave orphan interaction sounds")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
