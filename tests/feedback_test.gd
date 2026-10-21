extends SceneTree
## Event integration and actual mixer capture, using real-time Dummy audio.

const YARD = preload("res://scenes/test_yard.tscn")
const SOUND_NAMES = ["weapons/carbine_shot_01", "weapons/carbine_shot_02", "weapons/carbine_shot_03", "weapons/rifle_shot_01", "weapons/rifle_shot_02", "weapons/rifle_shot_03", "weapons/rifle_shot_04", "weapons/dry_trigger", "weapons/carbine_reload_start", "weapons/carbine_reload_finish", "weapons/rifle_reload_start", "weapons/rifle_reload_finish", "combat/weapon_ready", "combat/reload_timing", "combat/concrete_01", "combat/metal_01", "combat/metal_02", "combat/metal_03", "combat/metal_04", "combat/wood_01", "combat/body_01", "combat/body_02", "combat/body_03", "combat/player_damage"]

var _checks: int = 0
var _failures: int = 0
var _empty_count: int = 0
var _cues: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func _record_empty() -> void:
	_empty_count += 1


func _record_cue(cue: StringName) -> void:
	_cues[cue] = int(_cues.get(cue, 0)) + 1


func _capture_peak(capture: AudioEffectCapture) -> float:
	var frames := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _run() -> void:
	_test_weighted_selection()
	for name: String in SOUND_NAMES:
		var stream := load("res://assets/audio/" + name + ".wav") as AudioStreamWAV
		_check(stream != null and stream.get_length() > 0.05 and stream.get_length() < 2.1, "Sound imports with a short valid duration: " + name)
		if stream == null:
			continue
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 48000 and not stream.stereo, "Sound keeps uncompressed mono PCM: " + name)
		var peak := 0
		for offset in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(offset)))
		_check(peak > 500 and peak < 30000, "Sound has a non-silent signal and no clipped peaks: " + name)
	var bus := AudioServer.get_bus_index(&"SFX")
	_check(bus >= 0, "SFX bus exists for independent volume/mute")
	if bus < 0:
		quit(1)
		return
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	var yard := YARD.instantiate()
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	guard.process_mode = Node.PROCESS_MODE_DISABLED
	var weapon: Node2D = player.get_node("Aim/Weapon")
	var audio: Node2D = weapon.get_node("Audio")
	var cursor: Control = yard.get_node("HUD/AimCursor")
	weapon.empty_triggered.connect(_record_empty)
	audio.cue_played.connect(_record_cue)
	await _ticks(4)
	_check(player.get_node("AudioListener2D").is_current(), "Audio listener follows player, including camera edges")
	var guard_audio: Node2D = guard.get_node("Aim/Weapon/Audio")
	var player_bus := AudioServer.get_bus_index(&"PlayerWeapons")
	_check(player_bus >= 0 and AudioServer.get_bus_send(player_bus) == &"SFX" and audio.shot_audio.bus == &"PlayerWeapons" and audio.action_audio.bus == &"PlayerWeapons" and guard_audio.shot_audio.bus == &"EnemyWeapons", "Player and enemy weapons use independent categories under shared SFX")
	_check(audio.shot_cue != guard_audio.shot_cue and audio.reload_start_cue != guard_audio.reload_start_cue and audio.reload_finish_cue != guard_audio.reload_finish_cue, "Carbine and rifle have separate shot and reload profiles")
	var randomizer := audio.shot_audio.stream as AudioStreamRandomizer
	_check(randomizer != null and randomizer.streams_count == 3 and randomizer.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS, "Carbine uses all three new replacement shots without immediate repeats")
	_check(guard_audio.shot_audio.stream is AudioStreamRandomizer and guard_audio.shot_audio.stream.streams_count == 4, "Rifle selects from four owner-selected shots")
	_check(randomizer.get_stream_probability_weight(0) > randomizer.get_stream_probability_weight(1), "Native weapon selector preserves the owner's descending variant priorities")
	var additional := preload("res://scenes/enemy.tscn").instantiate()
	yard.add_child(additional)
	additional.set_physics_process(false)
	var additional_audio: Node2D = additional.get_node("Aim/Weapon/Audio")
	_check(additional_audio.shot_cue == guard_audio.shot_cue and additional_audio.shot_audio.stream != guard_audio.shot_audio.stream, "Actors share immutable source cues but own separate playback selection state")
	additional.free()
	# Exercise every native variant, rather than allowing a random quiet shot to
	# hide behind an impact. Raised footsteps should still stay below gunfire.
	var footsteps: Node2D = player.get_node("Footsteps")
	capture.clear_buffer()
	player.moved.emit(footsteps.step_distance)
	await _ticks(40)
	var step_peak := _capture_peak(capture)
	footsteps.stop()
	var selection_mode := randomizer.playback_mode
	var pitch_variation := randomizer.random_pitch
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_SEQUENTIAL
	randomizer.random_pitch = 1.0
	for index in range(randomizer.streams_count):
		audio.shot_audio.stop()
		await _ticks(6)
		capture.clear_buffer()
		audio._on_shot(Vector2.ZERO, Vector2.RIGHT, false)
		await _ticks(12)
		var variant_peak := _capture_peak(capture)
		_check(step_peak > 0.001 and variant_peak > step_peak and variant_peak < 0.9, "Carbine variant %d remains above the newly raised footsteps without clipping in the actual mixer" % (index + 1))
	audio.shot_audio.stop()
	randomizer.playback_mode = selection_mode
	randomizer.random_pitch = pitch_variation
	audio._on_shot(Vector2.ZERO, Vector2.RIGHT, false)
	await _ticks(4)
	var first_tail: AudioStreamPlayback = audio.shot_audio.get_stream_playback()
	audio._on_shot(Vector2.ZERO, Vector2.RIGHT, false)
	await _ticks(4)
	_check(audio.shot_audio.stream == randomizer and first_tail.is_playing(), "Another shot preserves its predecessor tail without replacing the stream")
	audio.shot_audio.stop()
	_cues.clear()
	capture.clear_buffer()
	var master := AudioServer.get_bus_index(&"Master")
	var output := AudioEffectCapture.new()
	output.buffer_length = 1.2
	AudioServer.add_bus_effect(master, output)
	var simultaneous: Array[Node2D] = []
	for index in range(8):
		var actor := preload("res://scenes/enemy.tscn").instantiate()
		yard.add_child(actor)
		actor.set_physics_process(false)
		actor.global_position = player.global_position + Vector2(80, 0)
		# Align the same recorded transient to exercise worst-case summation.
		actor.get_node("Aim/Weapon/Audio/Shot").stream.playback_mode = AudioStreamRandomizer.PLAYBACK_SEQUENTIAL
		actor.get_node("Aim/Weapon/Audio/Shot").volume_db += 12.0
		simultaneous.append(actor)
	await _ticks(6)
	capture.clear_buffer()
	output.clear_buffer()
	for actor in simultaneous:
		actor.get_node("Aim/Weapon").shot_fired.emit(Vector2.ZERO, Vector2.RIGHT, false)
	await _ticks(55)
	var raw_mix := _capture_peak(capture) * db_to_linear(AudioServer.get_bus_volume_db(bus))
	var limited_mix := _capture_peak(output)
	_check(raw_mix > 1.0, "Eight synchronized boosted rifle shots exercise an actual overload before output protection")
	_check(limited_mix > 0.01 and limited_mix <= db_to_linear(-1.0) + 0.001, "Master limiter keeps simultaneous gunfire audible below its -1 dB ceiling")
	for actor in simultaneous:
		actor.free()
	AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	await _ticks(8)
	capture.clear_buffer()
	_check(not cursor.is_empty_feedback_active, "Loaded gun has no empty-magazine warning")
	weapon.ammo = 1
	capture.clear_buffer()
	_check(weapon.try_fire(Vector2(900, 565), player), "Last loaded round still fires")
	await _ticks(12)
	_check(int(_cues.get(&"shot", 0)) == 1, "Successful shot requests exactly one shot sound")
	var shot_peak := _capture_peak(capture)
	_check(shot_peak > 0.001, "Shot produces non-zero samples in actual SFX mixer")
	_check(_empty_count == 0 and not cursor.is_empty_feedback_active, "Last bullet itself does not falsely report an empty trigger")
	await _ticks(10)
	capture.clear_buffer()
	_check(not weapon.try_fire(Vector2(900, 565), player), "Trying to fire an empty gun produces no shot")
	_check(_empty_count == 1 and int(_cues.get(&"dry_fire", 0)) == 1, "Empty attempt emits one visual/audio event")
	_check(cursor.is_empty_feedback_active, "Empty attempt immediately warns at aiming cursor")
	for attempt in range(20):
		weapon.try_fire(Vector2(900, 565), player)
	_check(_empty_count == 1, "Same-frame repeated attempts cannot spam clicks")
	await _ticks(10)
	_check(_capture_peak(capture) > 0.001, "Dry click reaches actual SFX mixer")
	var previous_count := _empty_count
	Input.action_press("shoot")
	await _ticks(60)
	Input.action_release("shoot")
	var held_clicks := _empty_count - previous_count
	_check(held_clicks >= 2 and held_clicks <= 3, "Holding empty trigger repeats feedback slowly, rather than every physics tick")
	_check(weapon.ammo == 0 and int(_cues.get(&"shot", 0)) == 1, "Empty feedback neither consumes ammo nor plays gunshots")
	await _ticks(55)
	_check(not cursor.is_empty_feedback_active, "Empty hint expires after player releases trigger")
	weapon.try_fire(Vector2(900, 565), player)
	_check(cursor.is_empty_feedback_active, "A later empty attempt can warn again")
	_check(weapon.request_reload(), "Player can start reload after empty attempt")
	_check(not cursor.is_empty_feedback_active and cursor.is_reload_active, "Reload replaces empty hint with progress ring immediately")
	_check(int(_cues.get(&"reload_start", 0)) == 1, "Reload start has one mechanical cue")
	previous_count = _empty_count
	for attempt in range(10):
		weapon.try_fire(Vector2(900, 565), player)
	_check(_empty_count == previous_count, "Shooting during reload does not emit misleading empty feedback")
	await _ticks(95)
	_check(weapon.ammo == weapon.magazine_size and int(_cues.get(&"reload_finish", 0)) == 1, "Completed reload has one completion cue")
	_check(not cursor.is_empty_feedback_active and not cursor.is_reload_active, "Completed reload clears both indicators")
	_check(int(_cues.get(&"timing_success", 0)) == 0, "Ordinary reload has no timing reward sound")
	weapon.ammo = 0
	weapon.request_reload()
	var timing_middle: float = (weapon.active_window_start + weapon.active_window_end) * 0.5
	while weapon.is_reloading and weapon.reload_progress < timing_middle:
		await _ticks(1)
	# Isolate the reward from any remaining mechanical reload tail in this capture.
	audio.action_audio.stop()
	capture.clear_buffer()
	_check(weapon.try_active_reload(), "Live timing success triggers reward at the actual input moment")
	await _ticks(10)
	var timing_peak := _capture_peak(capture)
	_check(int(_cues.get(&"timing_success", 0)) == 1 and timing_peak > 0.001, "One success cue reaches the actual SFX mixer")
	_check(timing_peak < shot_peak * 0.5, "Reward sound peaks well below the player's shot in the mixer")
	for attempt in range(10):
		weapon.try_active_reload()
	_check(int(_cues.get(&"timing_success", 0)) == 1, "Repeated input cannot replay reward sound")
	await _ticks(95)
	_check(int(_cues.get(&"timing_success", 0)) == 1, "Finishing accelerated reload does not replay timing reward")
	weapon.ammo = 0
	weapon.request_reload()
	weapon.try_active_reload()
	_check(int(_cues.get(&"timing_success", 0)) == 1 and not audio.timing_audio.playing, "Miss has no separate timing sound")

	# A new aiming phase has one cue; updating the same state must not repeat it.
	guard.process_mode = Node.PROCESS_MODE_INHERIT
	guard.set_physics_process(false)
	capture.clear_buffer()
	guard._change_state(guard.State.AIM)
	await _ticks(2)
	_check(guard.get_node("ReadyAudio").playing, "Guard aiming starts its positional warning sound")
	guard._change_state(guard.State.AIM)
	await _ticks(6)
	_check(_capture_peak(capture) > 0.0001, "Guard preparation cue reaches actual mixer")
	guard._change_state(guard.State.SEARCH)
	await _ticks(1)
	_check(not guard.get_node("ReadyAudio").playing, "Breaking aiming stops the preparation cue")
	weapon.try_fire(Vector2(900, 565), player)
	weapon.request_reload()
	var completions := int(_cues.get(&"reload_finish", 0))
	player.take_damage(1000.0)
	_check(player.get_node("HitAudio").is_playing(), "Player damage requests its impact sound")
	await _ticks(100)
	_check(int(_cues.get(&"reload_finish", 0)) == completions, "Death during reload never plays a false success cue")
	previous_count = _empty_count
	weapon.try_fire(Vector2(900, 565), player)
	_check(_empty_count == previous_count and not cursor.is_empty_feedback_active, "Dead player cannot create empty feedback")
	AudioServer.remove_bus_effect(bus, 0)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_weighted_selection() -> void:
	var cue := SoundCue.new()
	var first := AudioStreamWAV.new()
	var second := AudioStreamWAV.new()
	var third := AudioStreamWAV.new()
	cue.clips.assign([first, null, second, third])
	cue.clip_weights = PackedFloat32Array([8.0, 100.0, 3.0, 1.0])
	var counts := {first: 0, second: 0, third: 0}
	var previous: AudioStream
	var valid := true
	seed(62419)
	for iteration in range(8000):
		var selected := cue.choose(previous)
		valid = valid and selected != null and selected != previous
		if counts.has(selected):
			counts[selected] += 1
		previous = selected
	_check(valid, "Weighted selection skips empty entries and never immediately repeats a variant")
	_check(counts[first] > counts[second] and counts[second] > counts[third], "Owner's preferred recording occurs more often over repeated weighted selection")
	_check(cue.clips.size() == 4 and cue.clip_weights == PackedFloat32Array([8.0, 100.0, 3.0, 1.0]), "Selection never removes or rewrites shared recordings or weights")
	cue.clip_weights = PackedFloat32Array([NAN, 99.0, -1.0, 0.0])
	_check(cue.weight_at(0) == 1.0 and cue.weight_at(2) == 1.0 and cue.weight_at(3) == 1.0 and cue.weight_at(-1) == 1.0 and cue.weight_at(100) == 1.0, "Missing, invalid and nonpositive priority values use safe equal weights")
	cue.clips.assign([first])
	_check(cue.choose(first) == first, "A single recording can play repeatedly without a missing event")
	cue.clips.assign([null])
	_check(cue.choose(null) == null, "An empty profile safely produces no recording")
