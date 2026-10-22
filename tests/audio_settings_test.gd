extends "res://tests/loot_slots_test.gd"
## Exercise real mixer paths, paused GUI, shared base screen and disk preferences.


func _peak(capture: AudioEffectCapture) -> float:
	# Capture effects run before their bus fader/mute; include the final fader
	# when estimating the device-level signal from the captured Master frames.
	var master := AudioServer.get_bus_index(&"Master")
	var frames := capture.get_buffer(capture.get_frames_available())
	if AudioServer.is_bus_mute(master):
		return 0.0
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak * db_to_linear(AudioServer.get_bus_volume_db(master))


func _measure(voice: AudioStreamPlayer, capture: AudioEffectCapture) -> float:
	voice.stop()
	await _ticks(6)
	capture.clear_buffer()
	voice.play()
	await _ticks(18)
	var result := _peak(capture)
	voice.stop()
	return result


func _escape_settings() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _ticks(2)


func _run() -> void:
	var settings: Node = root.get_node("AudioSettings")
	_check(OS.get_environment("EXTRACTION_TEST_AUDIO") == "1", "Audio checks do not load or overwrite the owner's preferences")
	var buses: Dictionary = {}
	for category: Dictionary in settings.CATEGORIES:
		var bus := AudioServer.get_bus_index(category.bus)
		_check(bus >= 0 and not buses.has(bus) and settings.get_volume(category.id) == 50.0 and is_zero_approx(AudioServer.get_bus_volume_db(bus)), "Category starts at neutral 50 percent without changing the authored mix: " + String(category.id))
		buses[bus] = true
	var yard := YARD.instantiate()
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	root.add_child(yard)
	current_scene = yard
	var player: Node2D = yard.get_node("Player")
	var enemy: Node2D = yard.get_node("Enemy")
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	# Measure one routed voice in isolation, including all authored ambience sources.
	yard.get_node("Ambience").stop()
	var weapon_audio: Node2D = player.get_node("Aim/Weapon/Audio")
	var enemy_audio: Node2D = enemy.get_node("Aim/Weapon/Audio")
	_check(weapon_audio.shot_audio.bus == &"PlayerWeapons" and weapon_audio.action_audio.bus == &"PlayerWeapons" and weapon_audio.dry_audio.bus == &"PlayerWeapons" and weapon_audio.timing_audio.bus == &"PlayerWeapons", "All player weapon actions share the player weapon category")
	_check(enemy_audio.shot_audio.bus == &"EnemyWeapons" and enemy_audio.action_audio.bus == &"EnemyWeapons" and enemy.get_node("ReadyAudio").bus == &"EnemyWeapons", "Enemy preparation, shots and reloads share their own category")
	_check(player.get_node("Footsteps/Left").bus == &"Footsteps" and enemy.get_node("Footsteps/Right").bus == &"Footsteps", "Both actors' surface footsteps follow the footstep category")
	_check(player.get_node("HitAudio/A").bus == &"Impacts" and weapon_audio.get_node("Impacts/A").bus == &"Impacts", "Actor and material impacts follow the impact category")
	_check(player.get_node("InteractionAudio/HealAction/A").bus == &"Interactions" and yard.get_node("LootContainers/Supply/Audio/Search/A").bus == &"Interactions" and yard.get_node("HUD/LootMenu/InventoryAudio/Move/A").bus == &"Interactions", "Healing, searching and inventory transfers share interactions even in UI")
	var master := AudioServer.get_bus_index(&"Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(master, capture)
	var voice := AudioStreamPlayer.new()
	voice.stream = weapon_audio.shot_cue.clips[0]
	voice.volume_db = -20.0
	voice.bus = &"PlayerWeapons"
	root.add_child(voice)
	var reference := await _measure(voice, capture)
	settings.set_volume(&"player_weapons", 25)
	var half := await _measure(voice, capture)
	settings.set_volume(&"master", 25)
	var quarter := await _measure(voice, capture)
	_check(reference > 0.001 and absf(half / reference - 0.5) < 0.02 and absf(quarter / reference - 0.25) < 0.02, "Category and master sliders multiply the actual output independently")
	settings.reset_defaults()
	settings.set_volume(&"player_weapons", 75)
	var boosted := await _measure(voice, capture)
	_check(absf(boosted / reference - db_to_linear(6.0)) < 0.04, "Raising a category above 50 percent really amplifies the native signal")
	settings.set_volume(&"player_weapons", 100)
	settings.set_volume(&"master", 100)
	var combined := await _measure(voice, capture)
	_check(absf(combined / reference - db_to_linear(18.0)) < 0.15, "Maximum category and overall headroom combine before output protection")
	var mix := AudioServer.get_bus_index(&"Mix")
	var raw_capture := AudioEffectCapture.new()
	raw_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(mix, raw_capture)
	voice.volume_db = 0.0
	var protected := await _measure(voice, capture)
	var raw := _peak(raw_capture) * db_to_linear(AudioServer.get_bus_volume_db(mix))
	_check(AudioServer.get_bus_send(mix) == &"Master" and is_zero_approx(AudioServer.get_bus_volume_db(master)) and raw > 1.0 and protected > 0.01 and protected <= db_to_linear(-1.0) + 0.001, "Overall amplification precedes the limiter and an actual overload stays below its ceiling")
	AudioServer.remove_bus_effect(mix, AudioServer.get_bus_effect_count(mix) - 1)
	voice.volume_db = -20.0
	settings.reset_defaults()
	for category: Dictionary in settings.CATEGORIES:
		voice.bus = category.bus
		settings.set_volume(category.id, 0)
		_check(await _measure(voice, capture) < 0.000001, "Zero percent truly mutes the mixer path: " + String(category.id))
		settings.set_volume(category.id, 50)
	settings.set_volume(&"master", 0)
	var all_muted := true
	for category: Dictionary in settings.CATEGORIES:
		voice.bus = category.bus
		all_muted = (await _measure(voice, capture) < 0.000001) and all_muted
	_check(all_muted, "Overall mute reaches every category, including future music, voices and interface")
	settings.set_volume(&"master", 50)
	settings.set_volume(&"enemy_weapons", 0)
	voice.bus = &"PlayerWeapons"
	_check(await _measure(voice, capture) > 0.001, "Muting enemies leaves player gunfire audible")
	settings.reset_defaults()
	voice.free()
	var menu: Control = yard.get_node("HUD/PauseMenu")
	menu.set_settings_open(true)
	await _ticks(3)
	var options: Control = menu.get_node("SettingsMenu").audio_options
	_check(paused and options.is_visible_in_tree() and options.sliders.size() == settings.CATEGORIES.size(), "All sound sliders remain usable in the paused settings screen")
	var initial_size := root.size
	for size in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(3440, 1440), Vector2i(3840, 2160)]:
		root.size = size
		await _ticks(3)
		var panel: Control = menu.get_node("SettingsMenu/Center/Panel")
		var bounds := panel.get_global_rect()
		var logical := root.get_visible_rect().size
		_check(bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= logical.x + 1 and bounds.end.y <= logical.y + 1, "Settings and navigation stay inside the viewport: " + str(size))
	root.size = initial_size
	await _ticks(3)
	var slider: HSlider = options.sliders[&"interactions"]
	slider.value = 40
	slider.grab_focus()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	root.push_input(right, true)
	right = right.duplicate()
	right.pressed = false
	root.push_input(right, true)
	await _ticks(2)
	_check(settings.get_volume(&"interactions") == slider.value and slider.value > 40, "Keyboard slider input applies live while the game is paused")
	options.play_preview(&"interactions")
	await _ticks(6)
	capture.clear_buffer()
	# The selected wooden lid has a quiet early gap: capture its actual movement,
	# rather than making the assertion depend on mixer alignment inside that gap.
	await _ticks(45)
	_check(options.preview.bus == &"Interactions" and _peak(capture) > 0.0001 and paused, "Preview uses the selected category and can be heard without resuming combat")
	await _escape_settings()
	_check(paused and menu.visible and not menu.get_node("SettingsMenu").visible and not options.preview.playing, "Escape leaves settings, stops preview and keeps the pause menu open")
	menu.set_settings_open(true)
	options.play_preview(&"ambience")
	menu.set_developer_open(true)
	_check(menu.get_node("DeveloperPanel").visible and not menu.get_node("SettingsMenu").visible and not options.preview.playing, "Developer tools safely replace settings and stop its preview")
	menu.set_open(false)
	yard.free()
	await _ticks(3)
	var base := preload("res://scenes/base.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await _escape_settings()
	_check(base.get_node("SettingsMenu").visible and not base.get_node("Margin").visible and not paused, "Base opens the shared settings screen without changing raid progress or pause")
	var base_options: Control = base.get_node("SettingsMenu").audio_options
	_check(base_options.sliders[&"interactions"].value == settings.get_volume(&"interactions"), "Preferences survive the transition from raid to base")
	await _escape_settings()
	_check(not base.get_node("SettingsMenu").visible and base.get_node("Margin").visible, "Escape returns from base settings to stash")
	base.free()
	await _ticks(2)
	AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	await _test_disk(settings)
	settings.reset_defaults()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_disk(settings: Node) -> void:
	var path := "user://audio_settings_test.cfg"
	settings.set_volume(&"interactions", 63)
	settings.set_volume(&"master", 77)
	_check(settings.save_preferences(path) == OK, "Audio preferences save to an explicit isolated file")
	settings.set_volume(&"interactions", 61)
	_check(settings.save_preferences(path) == OK, "An atomic replacement can update an existing audio settings file")
	var fresh: Node = load("res://scripts/audio_settings.gd").new()
	root.add_child(fresh)
	fresh.load_preferences(path)
	_check(fresh.get_volume(&"interactions") == 61 and fresh.get_volume(&"master") == 77, "A fresh settings instance restores exact saved percentages")
	fresh.free()
	var malformed := ConfigFile.new()
	malformed.set_value("meta", "version", 2)
	malformed.set_value("volume", "master", "bad")
	malformed.set_value("volume", "footsteps", -50)
	malformed.set_value("volume", "music", 999)
	malformed.save(path)
	fresh = load("res://scripts/audio_settings.gd").new()
	root.add_child(fresh)
	fresh.load_preferences(path)
	fresh.set_volume(&"master", NAN)
	_check(fresh.get_volume(&"master") == 50 and fresh.get_volume(&"footsteps") == 0 and fresh.get_volume(&"music") == 100, "Invalid values use neutral defaults, finite percentages are constrained, NaN is ignored")
	fresh.free()
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", 1)
	var legacy_values := [0.0, 10.0, 25.0, 50.0, 63.0, 77.0, 100.0]
	for index in range(settings.CATEGORIES.size()):
		legacy.set_value("volume", settings.CATEGORIES[index].id, legacy_values[index % legacy_values.size()])
	legacy.save(path)
	fresh = load("res://scripts/audio_settings.gd").new()
	root.add_child(fresh)
	fresh.load_preferences(path)
	var preserved := true
	for index in range(settings.CATEGORIES.size()):
		var category: Dictionary = settings.CATEGORIES[index]
		var old: float = legacy_values[index % legacy_values.size()]
		preserved = preserved and is_equal_approx(fresh.get_volume(category.id), old * 0.5)
		preserved = preserved and is_equal_approx(fresh.volume_to_gain(category.id, fresh.get_volume(category.id)), old / 100.0)
	_check(preserved, "Every legacy category migrates from v1 to v2 without changing its gain or mute state")
	_check(fresh.save_preferences(path) == OK, "Migrated preferences can atomically replace their legacy file")
	var migrated := ConfigFile.new()
	migrated.load(path)
	fresh.load_preferences(path)
	_check(migrated.get_value("meta", "version") == 2 and fresh.get_volume(&"player_weapons") == 5.0, "Reloading saved calibration preferences does not migrate them a second time")
	fresh.set_volume(&"player_weapons", 85)
	fresh.set_volume(&"master", 65)
	fresh.save_preferences(path)
	fresh.load_preferences(path)
	_check(fresh.get_volume(&"player_weapons") == 85 and fresh.get_volume(&"master") == 65 and fresh.volume_to_gain(&"player_weapons", 85) > 1.0, "Calibration boosts above neutral survive save and reload")
	fresh.reset_defaults(false)
	_check(fresh.get_volume(&"player_weapons") == 50 and fresh.get_volume(&"master") == 50, "Reset returns calibration to the previous unboosted mix")
	fresh.free()
	malformed.set_value("meta", "version", 999)
	malformed.save(path)
	var protected_text := FileAccess.get_file_as_string(path)
	fresh = load("res://scripts/audio_settings.gd").new()
	root.add_child(fresh)
	fresh.load_preferences(path)
	fresh.set_volume(&"master", 20)
	_check(fresh.save_preferences(path) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(path) == protected_text, "Unknown future schema is not overwritten by slider changes")
	fresh.free()
	settings.load_preferences("user://missing_audio_defaults.cfg")
	settings.set_volume(&"master", 90)
	_check(settings.save_preferences("user://missing_audio_directory/preferences.cfg") != OK and not settings.error_message.is_empty() and settings.get_volume(&"master") == 90, "Write failure is reported while live slider values stay applied")
	settings.load_preferences("user://missing_audio_defaults.cfg")
