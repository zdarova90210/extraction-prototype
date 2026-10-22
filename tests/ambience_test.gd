extends "res://tests/loot_slots_test.gd"
## Actual loop decoding, separate mixer bus, sparse scheduling and scene lifetime.

var _details: Array[Dictionary] = []


func _record_detail(spot: AmbientSpot, clip: AudioStream) -> void:
	_details.append({"spot": spot, "clip": clip})


func _peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _detail_fixture() -> AmbientSpot:
	# Synthetic test-only clips keep scheduler coverage independent of shipped art.
	var cue := SoundCue.new()
	cue.volume_db = -18.0
	for frequency in [180.0, 260.0]:
		var bytes := PackedByteArray()
		bytes.resize(44100 * 2 * 2)
		for frame in range(44100 * 2):
			var edge := minf(1.0, minf(frame / 882.0, (88200 - frame) / 882.0))
			bytes.encode_s16(frame * 2, roundi(sin(TAU * frequency * frame / 44100.0) * edge * 4000.0))
		var clip := AudioStreamWAV.new()
		clip.format = AudioStreamWAV.FORMAT_16_BITS
		clip.mix_rate = 44100
		clip.data = bytes
		cue.clips.append(clip)
	var spot := AmbientSpot.new()
	spot.cue = cue
	spot.bus = &"Ambience"
	spot.position = Vector2(1215, 220)
	spot.max_distance = 1300.0
	spot.attenuation = 1.3
	return spot


func _run() -> void:
	var loop := preload("res://assets/audio/ambience/warehouse_bed_loop.ogg") as AudioStreamOggVorbis
	_check(loop.loop and is_equal_approx(loop.get_length(), 30.0), "Selected warehouse background imports as a full 30-second looping OGG")
	var playback := loop.instantiate_playback()
	playback.start(loop.get_length() - 0.05)
	var samples := playback.mix_audio(1.0, ceili(AudioServer.get_mix_rate() * 0.1))
	var middle := samples.size() >> 1
	var left_energy := 0.0
	var right_energy := 0.0
	for index in range(samples.size()):
		if index < middle:
			left_energy += samples[index].length_squared()
		else:
			right_energy += samples[index].length_squared()
	_check(left_energy > 0.001 and right_energy > 0.001, "Native decoder crosses the loop boundary without an empty gap")
	_check((samples[middle] - samples[middle - 1]).length() < 0.05, "Encoded loop boundary has no large sample discontinuity")
	# A continuous background has no scripted gust/silence pattern or audio dropouts.
	playback.start()
	var frames_per_second := int(AudioServer.get_mix_rate())
	var background_frames := playback.mix_audio(1.0, frames_per_second * int(loop.get_length()))
	var seconds_energy: Array[float] = []
	for second in range(int(loop.get_length())):
		var energy := 0.0
		for frame in range(second * frames_per_second, (second + 1) * frames_per_second):
			energy += background_frames[frame].length_squared()
		seconds_energy.append(energy)
	var loudest := seconds_energy.max() as float
	_check(loudest > 0.001 and seconds_energy.min() > loudest * 0.1, "Selected continuous background decodes without long fades or silent gaps")
	var yard := YARD.instantiate()
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: Node2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	var ambience: Node2D = yard.get_node("Ambience")
	var lamp: AmbientSpot = ambience.get_node("Details/DepotLamp")
	_check(ambience._spots == [lamp], "Only the visible depot lamp is registered; rejected creaks and leaves stay absent")
	# Isolate the bed/scheduler fixture from the authored lamp, tested separately.
	lamp.stop_ambience()
	ambience._spots.clear()
	_check(not ambience._play_random_detail(), "Background works safely without any authored incidental sources")
	ambience.detail_played.connect(_record_detail)
	ambience._detail_remaining = 100.0
	_check(ambience.bed.playing and ambience.bed.volume_db < -50.0, "Raid owns one background bed that starts quietly")
	await _ticks(25)
	_check(ambience.bed.volume_db > -60.0 and ambience.bed.volume_db < ambience.background_volume_db, "Background fades in without immediately jumping to full level")
	var ambient_bus := AudioServer.get_bus_index(&"Ambience")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_check(ambient_bus >= 0 and ambient_bus != sfx_bus and AudioServer.get_bus_send(ambient_bus) == &"Mix", "Ambience has its own volume bus routed through overall gain before the Master limiter")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var sfx_capture := AudioEffectCapture.new()
	sfx_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(ambient_bus, capture)
	AudioServer.add_bus_effect(sfx_bus, sfx_capture)
	await _ticks(145)
	capture.clear_buffer()
	sfx_capture.clear_buffer()
	await _ticks(35)
	var bed_peak := _peak(capture) * db_to_linear(AudioServer.get_bus_volume_db(ambient_bus))
	_check(bed_peak > 0.0001 and bed_peak < 0.05, "Background reaches the actual mixer at a quiet unclipped level")
	_check(_peak(sfx_capture) < 0.0001 and _details.is_empty(), "Quiet interval has no incidental detail or leaked ambience in SFX")
	player.moved.emit(player.get_node("Footsteps").step_distance)
	await _ticks(25)
	var step_peak := _peak(sfx_capture) * db_to_linear(AudioServer.get_bus_volume_db(sfx_bus))
	_check(step_peak > bed_peak, "Current background peak stays below an actual player footstep in the mix")
	var spot := _detail_fixture()
	ambience.get_node("Details").add_child(spot)
	var original_position := spot.global_position
	# Attach a test-only source for the retained optional detail scheduler.
	ambience._spots.assign([spot])
	player.global_position = spot.global_position + Vector2(-60, 0)
	await _ticks(4)
	seed(941)
	var expected_random := randf()
	seed(941)
	ambience._detail_remaining = 0.0
	await _ticks(1)
	_check(randf() == expected_random, "Ambience selection does not consume gameplay's global random sequence")
	_check(_details.size() == 1 and spot.playing and _details.back().spot == spot, "Elapsed delay starts one positional detail at its authored source")
	var quiet_time: float = ambience._detail_remaining
	await _ticks(12)
	_check(_details.size() == 1 and is_equal_approx(ambience._detail_remaining, quiet_time), "Detail playback does not overlap another detail or consume the following quiet interval")
	player.global_position += Vector2(100, 40)
	await _ticks(2)
	_check(spot.global_position == original_position, "Environmental source does not follow the listener")
	spot.stop()
	ambience._detail_remaining = 5.0
	paused = true
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(12)
	_check(_peak(capture) < 0.0001 and ambience._detail_remaining == 5.0, "Pause silences the bed and freezes environmental scheduling")
	paused = false
	await _ticks(12)
	_check(ambience.bed.playing and ambience._detail_remaining < 5.0 and _peak(capture) > 0.0001, "Resume restores the background and continues the remaining delay")
	ambience.bed.stop()
	player.global_position = spot.global_position + Vector2(-60, 0)
	await _ticks(6)
	capture.clear_buffer()
	var first_clip: AudioStream = _details.back().clip
	ambience._detail_remaining = 0.0
	await _ticks(55)
	_check(_details.size() == 2 and _details.back().clip != first_clip and _peak(capture) > 0.0001, "Nearby detail is audible and changes recording on the next play")
	spot.stop()
	player.global_position = spot.global_position + Vector2(2000, 0)
	await _ticks(6)
	capture.clear_buffer()
	ambience._detail_remaining = 0.0
	await _ticks(25)
	_check(_peak(capture) < 0.0001, "Distant environmental detail attenuates to silence")
	_check(yard.get_node("Enemy").state == yard.get_node("Enemy").State.PATROL, "Ambient playback does not notify guards of a gameplay noise")
	ambience.stop()
	await _ticks(8)
	capture.clear_buffer()
	await _ticks(10)
	_check(not ambience.bed.playing and not spot.playing and _peak(capture) < 0.0001, "Stopping ambience silences all its voices")
	ambience.start()
	await _ticks(8)
	var fade_before: float = ambience._fade_elapsed
	ambience.start()
	_check(ambience._fade_elapsed == fade_before, "Repeated start does not restart or stack the background bed")
	yard.free()
	await _ticks(8)
	var base := preload("res://scenes/base.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	capture.clear_buffer()
	await _ticks(12)
	_check(not base.has_node("Ambience") and _peak(capture) < 0.0001, "Returning to base leaves no raid background or orphan environmental voices")
	base.free()
	AudioServer.remove_bus_effect(ambient_bus, AudioServer.get_bus_effect_count(ambient_bus) - 1)
	AudioServer.remove_bus_effect(sfx_bus, AudioServer.get_bus_effect_count(sfx_bus) - 1)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
