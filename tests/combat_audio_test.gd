extends "res://tests/loot_slots_test.gd"
## Real ray hits, damage ownership, world-space voices, range and pause.

var _impacts: Array[Dictionary] = []
var _player_reactions: int = 0
var _enemy_reactions: int = 0


func _on_impact(cue: SoundCue, point: Vector2) -> void:
	_impacts.append({"cue": cue, "point": point})


func _peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _stop_impacts(pool: Node) -> void:
	for voice in pool.get_children():
		voice.stop()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := preload("res://scenes/player.tscn").instantiate()
	player.max_health = 60.0
	world.add_child(player)
	player.set_physics_process(false)
	var enemy := preload("res://scenes/enemy.tscn").instantiate()
	enemy.max_health = 80.0
	enemy.position = Vector2(200, 0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var weapon: Node2D = player.get_node("Aim/Weapon")
	weapon.magazine_size = 100
	weapon.ammo = 100
	var pool: Node2D = weapon.get_node("Audio/Impacts")
	pool.cue_played.connect(_on_impact)
	player.get_node("HitAudio").cue_played.connect(func(_cue): _player_reactions += 1)
	enemy.get_node("HitAudio").cue_played.connect(func(_cue): _enemy_reactions += 1)
	await _ticks(3)
	_check(not player.get_node("HitAudio").is_playing() and not enemy.get_node("HitAudio").is_playing(), "Custom initial HP below 100 never sounds like damage")
	var cover := preload("res://scenes/obstacle.tscn").instantiate()
	cover.position = Vector2(100, 0)
	cover.size = Vector2(40, 60)
	world.add_child(cover)
	await _ticks(3)
	var initial_health: float = enemy.health
	for kind in range(3):
		cover.kind = kind
		weapon._cooldown = 0.0
		var before := _impacts.size()
		_check(weapon.try_fire(enemy.position, player), "Actual ray fires toward occluded actor")
		_check(_impacts.size() == before + 1 and _impacts.back().cue == cover.get_impact_cue(), "Nearest cover selects its material exactly once: " + str(kind))
		_check(_impacts.back().point.is_equal_approx(Vector2(80, 0)) and enemy.health == initial_health, "Impact is at ray contact, not actor or muzzle; cover blocks damage")
	_check(cover.get_impact_cue().id == &"metal", "Container default is metal")
	cover.impact_cue = preload("res://resources/audio/combat/wood.tres")
	_check(cover.get_impact_cue().id == &"wood", "Inspector override separates surface sound from appearance")
	cover.impact_cue = null
	var contact: Vector2 = _impacts.back().point
	player.position = Vector2(0, 35)
	await _ticks(2)
	_check(pool.get_node("C").global_position.is_equal_approx(contact), "Impact voice stays at contact when shooter moves")
	player.position = Vector2.ZERO
	var container := CONTAINER.instantiate()
	_check(container.get_impact_cue().id == &"wood", "Loot box exposes a wooden surface")
	container.free()
	var target := preload("res://scenes/target.tscn").instantiate()
	_check(target.get_impact_cue().id == &"metal", "Training target exposes a metal surface")
	target.free()
	cover.position = Vector2(100, 100)
	await _ticks(3)
	var before := _impacts.size()
	weapon._cooldown = 0.0
	weapon.try_fire(enemy.position, player)
	_check(enemy.health == initial_health - weapon.damage and _enemy_reactions == 1, "Actual actor hit produces one physical damage reaction")
	_check(_impacts.size() == before, "Actor health reaction is not duplicated by surface hit audio")
	weapon.damage = 100.0
	weapon._cooldown = 0.0
	weapon.try_fire(enemy.position, player)
	_check(enemy.is_dead and _enemy_reactions == 2, "Lethal hit gets its ordinary physical impact, without extra kill cue")
	await _ticks(3)
	weapon._cooldown = 0.0
	weapon.try_fire(Vector2(0, -400), player)
	_check(_impacts.size() == before and _enemy_reactions == 2, "Ray miss has no impact confirmation")
	var stranger := StaticBody2D.new()
	pool.play_hit(Vector2.ZERO, stranger)
	stranger.free()
	pool.play_hit(Vector2.ZERO, stranger)
	_check(_impacts.size() == before, "Unknown and freed colliders safely omit an invented material cue")
	player.damage_enabled = false
	player.take_damage(10.0)
	player.damage_enabled = true
	player.take_damage(0.0)
	player.take_damage(-10.0)
	_check(_player_reactions == 0, "Blocked and nonpositive damage remain silent")
	player.take_damage(10.0)
	_check(_player_reactions == 1 and player.get_node("HitAudio").is_playing(), "Player actual HP loss produces one positional physical reaction")
	player.restore_health(5.0)
	_check(_player_reactions == 1, "Healing does not sound like damage")
	for repeat in range(20):
		pool.play_hit(Vector2(70, 0), cover)
	_check(pool.get_child_count() == 4 and _impacts.size() == before + 20, "Repeated hits reuse four bounded positional voices")
	weapon.get_node("Audio/Shot").stop()
	_stop_impacts(pool)
	player.get_node("HitAudio").stop(0.0)
	enemy.get_node("HitAudio").stop(0.0)
	await _ticks(8)
	var bus := AudioServer.get_bus_index(&"SFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	await _ticks(4)
	capture.clear_buffer()
	pool.play_hit(Vector2(70, 0), cover)
	await _ticks(24)
	var near := _peak(capture)
	_check(near > 0.001 and near < 0.5, "Nearby surface impact is audible in SFX without overload")
	_stop_impacts(pool)
	await _ticks(6)
	capture.clear_buffer()
	pool.play_hit(Vector2(1000, 0), cover)
	await _ticks(24)
	_check(_peak(capture) < 0.0001, "Distant impact is inaudible instead of global hit confirmation")
	pool.play_hit(Vector2(70, 0), cover)
	await _ticks(2)
	paused = true
	await _ticks(6)
	capture.clear_buffer()
	await _ticks(10)
	_check(_peak(capture) < 0.0001, "Pause silences active surface impacts")
	paused = false
	world.free()
	await _ticks(8)
	capture.clear_buffer()
	await _ticks(10)
	_check(_peak(capture) < 0.0001, "Scene teardown leaves no orphan hit audio")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
