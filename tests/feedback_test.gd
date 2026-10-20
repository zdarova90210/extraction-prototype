extends SceneTree
## Event integration and actual mixer capture, using real-time Dummy audio.

const YARD = preload("res://scenes/test_yard.tscn")
const SOUND_NAMES = ["player_shot", "guard_shot", "dry_fire", "reload_start", "reload_finish", "guard_ready", "player_hit", "active_reload_success"]

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
	for name: String in SOUND_NAMES:
		var stream := load("res://assets/audio/" + name + ".wav") as AudioStreamWAV
		_check(stream != null and stream.get_length() > 0.05 and stream.get_length() < 0.5, "Sound imports with a short valid duration: " + name)
		if stream == null:
			continue
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100 and not stream.stereo, "Sound keeps uncompressed mono PCM: " + name)
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
	_check(audio.shot_stream != guard.get_node("Aim/Weapon/Audio").shot_stream, "Player and guard use different shot sounds")
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
	_check(player.get_node("HitAudio").playing, "Player damage requests its impact sound")
	await _ticks(100)
	_check(int(_cues.get(&"reload_finish", 0)) == completions, "Death during reload never plays a false success cue")
	previous_count = _empty_count
	weapon.try_fire(Vector2(900, 565), player)
	_check(_empty_count == previous_count and not cursor.is_empty_feedback_active, "Dead player cannot create empty feedback")
	AudioServer.remove_bus_effect(bus, 0)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
