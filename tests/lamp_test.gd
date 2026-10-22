extends "res://tests/loot_slots_test.gd"
## The actual lamp recordings, positional mix, light response, pause and lifetime.


func _peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _run() -> void:
	var yard := YARD.instantiate()
	yard.audio_test_setup = false
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	yard.set_guards_active(false)
	var player: Node2D = yard.get_node("Player")
	player.set_physics_process(false)
	var ambience: Node2D = yard.get_node("Ambience")
	var lamp: AmbientSpot = ambience.get_node("Details/DepotLamp")
	player.global_position = lamp.global_position + Vector2(0, 65)
	ambience.bed.stop()
	ambience._detail_remaining = 100.0
	_check(lamp.bus == &"Ambience" and lamp.hum.bus == &"Ambience", "Both lamp voices obey the existing environmental category")
	_check(lamp.hum_stream is AudioStreamWAV and lamp.hum_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and lamp.hum_stream.format == AudioStreamWAV.FORMAT_16_BITS, "Local hum imports as a looping uncompressed WAV")
	_check(is_equal_approx(lamp.hum_stream.get_length(), 9.88), "Hum has only the documented seam overlap removed")
	_check(lamp.cue.clips.size() == 3 and lamp.cue.pitch_variation == 0.0, "All three owner-selected sputters retain natural pitch")
	var hum_stream := lamp.hum_stream as AudioStreamWAV
	var boundary := hum_stream.instantiate_playback()
	boundary.start(hum_stream.get_length() - 0.05)
	var samples := boundary.mix_audio(1.0, ceili(AudioServer.get_mix_rate() * 0.1))
	var middle := samples.size() >> 1
	_check((samples[middle] - samples[middle - 1]).length() < 0.02, "Loop wrap does not introduce a large sample discontinuity")
	_check(lamp.find_children("*", "CollisionObject2D", true, false).is_empty(), "Decoration introduces no collision or navigation obstacle")
	var ambient_bus := AudioServer.get_bus_index(&"Ambience")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var sfx_capture := AudioEffectCapture.new()
	sfx_capture.buffer_length = 1.0
	# Bus effects capture before their own fader/mute; verify mute downstream.
	var master_bus := AudioServer.get_bus_index(&"Master")
	var master_capture := AudioEffectCapture.new()
	master_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(ambient_bus, capture)
	AudioServer.add_bus_effect(sfx_bus, sfx_capture)
	AudioServer.add_bus_effect(master_bus, master_capture)
	await _ticks(100)
	capture.clear_buffer()
	sfx_capture.clear_buffer()
	await _ticks(20)
	var hum_peak := _peak(capture)
	_check(hum_peak > 0.0001 and hum_peak < 0.15, "Nearby steady hum reaches the mix without becoming a loud effect")
	seed(117)
	var expected := randf()
	seed(117)
	_check(ambience._play_random_detail(), "Scheduler can play the authored visible source")
	await _ticks(35)
	_check(randf() == expected, "Lamp scheduling and flicker leave gameplay RNG untouched")
	_check(lamp.playing and lamp.stream in lamp.cue.clips and lamp.stream.get_length() == 3.0, "Sputter plays a full three-second recording at the fixture")
	_check(lamp.pool.energy < lamp.light_energy and lamp.pool.energy >= lamp.light_energy * (1.0 - lamp.flicker_depth) * 0.98, "Audible disturbance softly dims the lamp without a blackout")
	_check(_peak(capture) > hum_peak and _peak(sfx_capture) < 0.0001, "Sputter is distinct from hum and neither lamp voice leaks into SFX")
	var phase_before: float = lamp._phase
	var delay_before: float = ambience._detail_remaining
	paused = true
	await _ticks(8)
	capture.clear_buffer()
	await _ticks(15)
	_check(_peak(capture) < 0.0001 and lamp._phase == phase_before and ambience._detail_remaining == delay_before, "Pause silences both voices and freezes light and scheduler")
	paused = false
	await _ticks(15)
	_check(_peak(capture) > 0.0001 and lamp._phase > phase_before, "Resume continues the source and light together")
	AudioServer.set_bus_mute(ambient_bus, true)
	await _ticks(6)
	master_capture.clear_buffer()
	await _ticks(10)
	_check(_peak(master_capture) < 0.0001, "Environmental mute silences the new lamp at final output")
	AudioServer.set_bus_mute(ambient_bus, false)
	var first: AudioStream = lamp.stream
	lamp.stop()
	ambience._play_random_detail()
	_check(lamp.stream != first, "Successive disturbances do not repeat the same recording")
	player.global_position = lamp.global_position + Vector2(1000, 0)
	# Drain already-mixed near-source buffers before sampling the new listener position.
	await _ticks(30)
	capture.clear_buffer()
	await _ticks(15)
	var far_peak := _peak(capture)
	_check(far_peak < 0.0001, "Both environmental voices disappear beyond their local range (peak %.6f)" % far_peak)
	_check(yard.get_node("Enemy").state == yard.get_node("Enemy").State.PATROL, "Lamp does not create an AI hearing event")
	ambience.stop()
	_check(not lamp.playing and not lamp.hum.playing, "Stopping ambience includes the fixture's continuous hum")
	ambience.start()
	_check(lamp.hum.playing, "Restart restores exactly one continuous hum")
	ambience.stop()
	yard.free()
	await _ticks(12)
	capture.clear_buffer()
	await _ticks(12)
	_check(_peak(capture) < 0.0001, "Leaving the room leaves no orphan lamp voices")
	AudioServer.remove_bus_effect(ambient_bus, AudioServer.get_bus_effect_count(ambient_bus) - 1)
	AudioServer.remove_bus_effect(sfx_bus, AudioServer.get_bus_effect_count(sfx_bus) - 1)
	AudioServer.remove_bus_effect(master_bus, AudioServer.get_bus_effect_count(master_bus) - 1)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
