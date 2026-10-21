extends "res://tests/loot_slots_test.gd"
## Actual countdown, saved extraction, death, scene handoff and mixer routing.

var _events: Array[StringName] = []
var _pulses: Array[float] = []
var _cancels: int = 0
var _zone: Area2D


func _peak(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _watch_zone(zone: Area2D) -> void:
	_zone = zone
	zone.get_node("Audio/Pulse").cue_played.connect(func(_cue): _pulses.append(zone.elapsed))
	zone.get_node("Audio/Cancel").cue_played.connect(func(_cue): _cancels += 1)


func _fresh() -> Node2D:
	var yard := YARD.instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	yard.set_guards_active(false)
	yard.player.set_physics_process(false)
	_watch_zone(yard.get_node("ExtractionZone"))
	await _ticks(4)
	return yard


func _run() -> void:
	var audio: Node = root.get_node("RaidAudio")
	var profile: Node = root.get_node("RaidProgress")
	audio.cue_played.connect(func(cue: SoundCue): _events.append(cue.id))
	var base := load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	await _ticks(3)
	_check(_events.is_empty() and not audio.is_playing(), "Opening base does not replay a persisted raid result")
	base._open_settings()
	var options: Control = base.get_node("SettingsMenu").audio_options
	options.play_preview(&"interface")
	_check(options.preview.bus == &"Interface" and options.preview.playing and _events.is_empty(), "Interface preview is available without starting or completing a raid")
	base._close_settings()
	base.free()
	var yard := await _fresh()
	_check(_events == [&"raid_start"], "Entering a valid raid plays exactly one intro")
	_check(audio.get_node("A").bus == &"Interface" and _zone.get_node("Audio/Pulse/A").bus == &"Interface" and _zone.get_node("Audio/Cancel/A").bus == &"Interface", "All five signals use Interface rather than weapon, ambience or music volume")
	for name in ["raid_start", "raid_success", "raid_failure", "extraction_pulse", "extraction_cancel"]:
		var cue := load("res://resources/audio/raid/" + name + ".tres") as SoundCue
		var clip := cue.clips[0] as AudioStreamWAV
		_check(clip != null and clip.stereo and clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.mix_rate == 48000 and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and cue.pitch_variation == 0.0, "Primary recording preserves stereo PCM and stable tone: " + name)
	# Inspect the actual bus, including mute and pause, independently of the yard bed.
	var bus := AudioServer.get_bus_index(&"Interface")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	await _ticks(12)
	_check(_peak(capture.get_buffer(capture.get_frames_available())) > 0.0001, "Raid intro reaches the Interface mixer")
	root.get_node("AudioSettings").set_volume(&"interface", 0.0)
	await _ticks(6)
	_check(AudioServer.is_bus_mute(bus), "Interface preference mutes raid signals without changing other categories")
	root.get_node("AudioSettings").set_volume(&"interface", 50.0)
	audio.stop(0.0)
	yard.player.global_position = _zone.global_position
	await _ticks(2)
	_check(_pulses.size() == 1 and _cancels == 0, "Entering extraction gives one immediate pulse")
	yard.get_node("HUD/PauseMenu").set_open(true)
	var elapsed: float = _zone.elapsed
	var pulse_count := _pulses.size()
	var remaining: float = _zone.get_node("Audio")._remaining
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(18)
	_check(_zone.elapsed == elapsed and _pulses.size() == pulse_count and _zone.get_node("Audio")._remaining == remaining and _peak(capture.get_buffer(capture.get_frames_available())) < 0.0001, "Pause silences pulse and freezes countdown and scheduler")
	yard.get_node("HUD/PauseMenu").set_open(false)
	yard.player.global_position -= Vector2(220, 0)
	await _ticks(3)
	_check(_cancels == 1 and _zone.elapsed == 0.0 and not _zone.get_node("Audio")._active, "Leaving an active zone cancels exactly once and stops pulses")
	await _ticks(40)
	_check(_cancels == 1 and _pulses.size() == pulse_count, "Standing outside never repeats cancel or pulse")
	_pulses.clear()
	yard.player.global_position = _zone.global_position
	await _ticks(305)
	_check(current_scene != yard and current_scene.has_method("_start_raid") and _events.count(&"raid_success") == 1, "Full five-second extraction saves loot and plays one success cue")
	_check(_pulses.size() >= 6 and _pulses[1] - _pulses[0] > _pulses[-1] - _pulses[-2], "Pulses accelerate as the actual extraction timer advances")
	_check(audio.is_playing() and profile.last_result.outcome == "extracted", "Success motif survives return to base after saved completion")
	var count_before := _events.size()
	profile.changed.emit()
	await _ticks(3)
	_check(_events.size() == count_before, "Refreshing stash cannot replay success")
	current_scene.free()
	base = load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	await _ticks(2)
	_check(_events.size() == count_before, "Reopening a base with the same saved result does not replay its motif")
	base.free()
	yard = await _fresh()
	_check(_events.back() == &"raid_start", "A new raid replaces the old result with a fresh intro")
	profile.save_path = "user://missing_raid_audio_directory/progress.json"
	_zone.duration = 0.5
	yard.player.global_position = _zone.global_position
	await _ticks(40)
	_check(current_scene == yard and _events.count(&"raid_success") == 1 and not _zone.get_node("Audio")._active and yard.player.get_node("Inventory").item_count == 2, "Save failure never announces success or loses backpack and stops pulse")
	pulse_count = _pulses.size()
	await _ticks(35)
	_check(_pulses.size() == pulse_count and _cancels == 1, "Failed extraction does not automatically retry or emit a misleading cancel cue")
	profile.save_path = ""
	yard.player.global_position -= Vector2(220, 0)
	await _ticks(2)
	yard.player.global_position = _zone.global_position
	await _ticks(40)
	_check(current_scene != yard and _events.count(&"raid_success") == 2, "Leaving and re-entering retries save with exactly one new success")
	current_scene.free()
	yard = await _fresh()
	yard.player.global_position = _zone.global_position
	await _ticks(2)
	yard.player.take_damage(1000.0)
	await _ticks(8)
	_check(_events.count(&"raid_failure") == 1 and _cancels == 1 and not _zone.get_node("Audio")._active, "Death in extraction stops pulse and plays failure without an extra cancel signal")
	yard.player.take_damage(1000.0)
	_check(_events.count(&"raid_failure") == 1 and not audio.finish_raid(yard, false), "Repeated damage and duplicate outcome requests cannot replay failure")
	yard._leave_for_base()
	await _ticks(3)
	_check(current_scene.has_method("_start_raid") and audio.is_playing() and _events.count(&"raid_failure") == 1, "Failure motif continues across the death-screen return to base")
	current_scene.free()
	yard = await _fresh()
	yard.restore_player()
	_check(not audio.is_playing(), "Developer restore clears transient outcome without another intro")
	yard.player.take_damage(1000.0)
	_check(_events.count(&"raid_failure") == 2, "Another death after developer restore has its own single failure cue")
	yard.free()
	audio.stop(0.0)
	await _ticks(12)
	capture.clear_buffer()
	await _ticks(12)
	var final_peak := _peak(capture.get_buffer(capture.get_frames_available()))
	_check(final_peak < 0.0001, "Explicit stop and scene cleanup leave no orphan raid signals")
	var pending_slots: Array[ItemDefinition] = profile.pending.snapshot_slots()
	pending_slots[0] = preload("res://resources/items/metal.tres")
	profile.pending.replace_slots(pending_slots)
	var before_blocked := _events.size()
	yard = YARD.instantiate()
	root.add_child(yard)
	current_scene = yard
	await _ticks(4)
	_check(current_scene.has_method("_start_raid") and _events.size() == before_blocked, "Blocked raid with pending loot returns to base without a false intro")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
