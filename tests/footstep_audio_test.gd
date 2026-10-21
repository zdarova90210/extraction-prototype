extends "res://tests/loot_slots_test.gd"
## Decode actual source recordings, then verify positional output through SFX.


func _levels(frames: PackedVector2Array) -> Vector3:
	var peak := 0.0
	var left := 0.0
	var right := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		left += frame.x * frame.x
		right += frame.y * frame.y
	return Vector3(peak, sqrt(left / maxf(1.0, frames.size())), sqrt(right / maxf(1.0, frames.size())))


func _run() -> void:
	var profiles: Array[FootstepProfile] = [preload("res://resources/audio/footsteps_concrete.tres"), preload("res://resources/audio/footsteps_metal.tres")]
	var measurements: Dictionary = {}
	for profile in profiles:
		var valid := true
		var shortest := 10.0
		var longest := 0.0
		var highest := 0.0
		var lowest_rms := 1.0
		for clip in profile.clips:
			var playback := clip.instantiate_playback()
			playback.start()
			var samples := playback.mix_audio(1.0, ceili(clip.get_length() * AudioServer.get_mix_rate()) + 1024)
			var levels := _levels(samples)
			valid = valid and clip is AudioStreamWAV and clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.mix_rate == 48000 and not clip.stereo and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and clip.get_length() > 0.05 and clip.get_length() < 0.8
			valid = valid and levels.x > 0.01 and levels.x < 1.1 and levels.y > 0.001
			shortest = minf(shortest, clip.get_length())
			longest = maxf(longest, clip.get_length())
			highest = maxf(highest, levels.x)
			lowest_rms = minf(lowest_rms, levels.y)
		_check(valid, "All %s variants decode to short, non-looping, non-silent recordings" % profile.surface_id)
		measurements[profile.surface_id] = {"shortest": shortest, "longest": longest, "raw_peak": highest, "lowest_rms": lowest_rms}
	var file := FileAccess.open("res://artifacts/footstep_levels.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	player.set_physics_process(false)
	guard.set_physics_process(false)
	var footsteps: Node2D = player.get_node("Footsteps")
	var enemy_steps: Node2D = guard.get_node("Footsteps")
	var bus := AudioServer.get_bus_index(&"SFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	player.global_position = Vector2(300, 600)
	await _ticks(5)
	player.moved.emit(footsteps.step_distance)
	await _ticks(25)
	var concrete := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(concrete.x > 0.001 and concrete.x < 0.5, "Concrete footstep reaches SFX mixer at a restrained unclipped level")
	player.global_position = Vector2(480, 700)
	capture.clear_buffer()
	player.moved.emit(footsteps.step_distance)
	await _ticks(25)
	var metal := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(metal.x > 0.001 and metal.x < 0.5, "Metal footstep reaches SFX mixer without overpowering combat")
	capture.clear_buffer()
	player.get_node("Aim/Weapon").try_fire(player.global_position + Vector2(0, -300), player)
	await _ticks(25)
	var shot := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(maxf(concrete.x, metal.x) < shot.x, "Player footstep peaks stay below the current gunshot in the actual mix")
	# Recorded shots have longer natural tails than the old synthesized effect.
	# Isolate footstep distance measurements from that unrelated sound.
	player.get_node("Aim/Weapon/Audio/Shot").stop()
	for voice in player.get_node("Aim/Weapon/Audio/Impacts").get_children():
		voice.stop()
	await _ticks(6)
	guard.global_position = player.global_position + Vector2(70, 0)
	capture.clear_buffer()
	guard.moved.emit(enemy_steps.step_distance)
	await _ticks(25)
	var near := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(near.x > 0.001 and near.z > near.y, "Nearby guard footsteps are audible and pan toward the guard")
	enemy_steps.stop()
	guard.global_position = player.global_position + Vector2(1000, 0)
	# Flush the mix/spatial update after the artificial teleport before measuring.
	await _ticks(6)
	capture.clear_buffer()
	guard.moved.emit(enemy_steps.step_distance)
	await _ticks(25)
	var far := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(far.x < 0.0001, "Distant guard footsteps do not broadcast across the whole map")
	guard.global_position = player.global_position + Vector2(70, 0)
	guard.moved.emit(enemy_steps.step_distance)
	await _ticks(3)
	yard.get_node("HUD/PauseMenu").set_open(true)
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(15)
	var paused_levels := _levels(capture.get_buffer(capture.get_frames_available()))
	_check(paused_levels.x < 0.0001, "Pausing silences in-flight footstep audio")
	yard.get_node("HUD/PauseMenu").set_open(false)
	await _ticks(25)
	footsteps.stop()
	enemy_steps.stop()
	await _ticks(10)
	capture.clear_buffer()
	await _ticks(20)
	_check(_levels(capture.get_buffer(capture.get_frames_available())).x < 0.0001, "Stopped actors leave no continuously playing loop")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	yard.queue_free()
	await _ticks(2)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
