extends SceneTree
## Live physics timing and real R input, including opt-out, mistakes and death.

var _checks: int = 0
var _failures: int = 0
var _ticks_elapsed: int = 0
var _results: Array[bool] = []
var _completed_cues: int = 0
var _success_cues: int = 0


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
		_ticks_elapsed += 1


func _press_r() -> void:
	Input.action_press("reload")
	await _ticks(1)
	Input.action_release("reload")
	await _ticks(1)


func _at_progress(weapon: Node2D, progress: float) -> void:
	for index in range(300):
		if not weapon.is_reloading or weapon.reload_progress >= progress:
			return
		await _ticks(1)


func _finish(weapon: Node2D) -> void:
	for index in range(300):
		if not weapon.is_reloading:
			return
		await _ticks(1)


func _begin(weapon: Node2D) -> int:
	weapon.ammo = 0
	weapon.ammo_changed.emit(0, weapon.magazine_size)
	weapon.request_reload()
	return _ticks_elapsed


func _record_result(success: bool) -> void:
	_results.append(success)


func _record_cue(cue: StringName) -> void:
	if cue == &"reload_finish":
		_completed_cues += 1
	elif cue == &"timing_success":
		_success_cues += 1


func _run() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var guard: CharacterBody2D = yard.get_node("Enemy")
	guard.set_physics_process(false)
	var weapon: Node2D = player.get_node("Aim/Weapon")
	var base_damage: float = weapon.damage
	var base_capacity: int = weapon.magazine_size
	var cursor: Control = yard.get_node("HUD/AimCursor")
	weapon.active_reload_resolved.connect(_record_result)
	weapon.get_node("Audio").cue_played.connect(_record_cue)
	_check(weapon.active_reload_enabled and not guard.get_node("Aim/Weapon").active_reload_enabled, "Active reload belongs to player, guard keeps ordinary reload")
	_check(not weapon.try_active_reload() and not weapon.request_reload(), "No active attempt or reload on a full idle weapon")
	var started := _begin(weapon)
	_check(weapon.active_window_start >= 0.2 and weapon.active_window_start <= 0.55 and weapon.active_window_end < 1.0, "Timing window is bounded and visible before it arrives")
	_check(is_equal_approx(weapon.active_window_end - weapon.active_window_start, 0.075), "Default timing window is about 112 milliseconds at normal reload speed")
	await _at_progress(weapon, 0.5)
	_check(weapon.ammo == 0 and cursor.is_reload_active, "Ignoring timing window preserves normal ongoing reload and ring")
	await _finish(weapon)
	var normal_ticks := _ticks_elapsed - started
	_check(absi(normal_ticks - 90) <= 2 and weapon.ammo == 12, "Opting out reloads in the original 1.5 seconds")
	_check(_results.is_empty() and _completed_cues == 1 and _success_cues == 0, "Opting out emits no reward sound and one completion sound")

	started = _begin(weapon)
	await _press_r()
	_check(weapon.reload_timing == weapon.ReloadTiming.MISSED and _results == [false] and _success_cues == 0, "Early R input misses without a reward sound")
	var window_middle: float = (weapon.active_window_start + weapon.active_window_end) * 0.5
	await _at_progress(weapon, window_middle)
	_check(not weapon.try_active_reload() and weapon.reload_timing == weapon.ReloadTiming.MISSED and _results.size() == 1, "Repeated input cannot turn an early miss into a success")
	await _finish(weapon)
	_check(absi((_ticks_elapsed - started) - normal_ticks) <= 1 and weapon.ammo == 12, "Miss has no slowdown, reset, ammo loss or refill penalty")

	started = _begin(weapon)
	_check(weapon.reload_timing == weapon.ReloadTiming.AVAILABLE, "New reload gets a new attempt after a prior miss")
	window_middle = (weapon.active_window_start + weapon.active_window_end) * 0.5
	await _at_progress(weapon, window_middle)
	var before_progress: float = weapon.reload_progress
	var elapsed: float = float(_ticks_elapsed - started) / 60.0
	var expected_duration: float = elapsed + weapon.reload_duration * (1.0 - before_progress) / 1.5
	await _press_r()
	_check(weapon.reload_timing == weapon.ReloadTiming.SUCCESS and _results == [false, true] and _success_cues == 1, "R input inside visible window wins and plays one reward sound immediately")
	_check(weapon.is_reloading and weapon.ammo == 0, "Success speeds remaining work rather than instantly refilling ammo")
	_check(weapon.reload_progress > before_progress and weapon.reload_progress - before_progress < 0.06, "Successful ring continues smoothly without jumping to the end")
	for index in range(10):
		weapon.try_active_reload()
	_check(_results.size() == 2 and _success_cues == 1, "Spamming R cannot stack success or repeat its sound")
	_check(not weapon.try_fire(Vector2(900, 565), player), "Accelerated reload still blocks shooting until completion")
	await _finish(weapon)
	var actual_duration := float(_ticks_elapsed - started) / 60.0
	_check(absf(actual_duration - expected_duration) < 0.06 and actual_duration < 1.4, "Only remaining reload time runs 1.5 times faster")
	_check(weapon.ammo == 12 and _completed_cues == 3 and not cursor.is_reload_active, "Successful completion refills once, sounds once and hides ring")
	_check(weapon.damage == base_damage and weapon.magazine_size == base_capacity, "Timing success adds no damage buff or extra rounds")

	started = _begin(weapon)
	await _at_progress(weapon, weapon.active_window_end + 0.05)
	_check(not weapon.try_active_reload() and weapon.reload_timing == weapon.ReloadTiming.MISSED and _success_cues == 1, "Late miss has no additional reward sound")
	await _finish(weapon)
	_check(absi((_ticks_elapsed - started) - normal_ticks) <= 1, "Late miss also preserves baseline duration")
	var guard_weapon: Node2D = guard.get_node("Aim/Weapon")
	guard_weapon.ammo = 0
	guard_weapon.request_reload()
	_check(guard_weapon.reload_timing == guard_weapon.ReloadTiming.INACTIVE and not guard_weapon.try_active_reload(), "Guard cannot acquire a timing bonus")
	await _finish(guard_weapon)
	_check(guard_weapon.ammo == guard_weapon.magazine_size, "Ordinary guard reload still completes")

	weapon.active_reload_enabled = false
	started = _begin(weapon)
	_check(not weapon.try_active_reload(), "Inspector can disable optional timing mechanic")
	await _finish(weapon)
	_check(absi((_ticks_elapsed - started) - normal_ticks) <= 1, "Disabled mechanic preserves original duration")
	weapon.active_reload_enabled = true
	_begin(weapon)
	await _at_progress(weapon, (weapon.active_window_start + weapon.active_window_end) * 0.5)
	weapon.try_active_reload()
	var cues_before := _completed_cues
	var success_cues_before := _success_cues
	var results_before := _results.size()
	player.take_damage(1000.0)
	await _ticks(100)
	_check(not weapon.is_reloading and weapon.reload_timing == weapon.ReloadTiming.INACTIVE and weapon.ammo == 0, "Death cancels accelerated reload without refilling")
	_check(not cursor.is_reload_active and not weapon.try_active_reload() and _results.size() == results_before and _completed_cues == cues_before and _success_cues == success_cues_before and not weapon.get_node("Audio/TimingSuccess").playing, "Death hides timing UI and stops reward audio without an extra cue")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
