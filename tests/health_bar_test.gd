extends SceneTree
## Exercise live actor damage signals and the delayed trail across a burst.

var _checks: int = 0
var _failures: int = 0


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


func _run() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	var enemy: CharacterBody2D = yard.get_node("Enemy")
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	var player_bar: Node2D = player.get_node("HealthBar")
	var enemy_bar: Node2D = enemy.get_node("HealthBar")
	_check(player_bar.current_health == 100.0 and enemy_bar.current_health == 100.0, "Both overhead bars initialize from actors")
	_check(not yard.has_node("HUD/Top/PlayerStats"), "Distant corner stats are removed")
	var offset := player_bar.global_position - player.global_position
	player.position += Vector2(35, 25)
	player.get_node("Aim").rotation = 1.7
	_check(offset.y < -20.0 and player_bar.global_position - player.global_position == offset and is_zero_approx(player_bar.global_rotation), "Health follows actor above body without rotating with aim")
	player.take_damage(14.0)
	enemy.take_damage(25.0)
	_check(player_bar.current_health == 86.0 and enemy_bar.current_health == 75.0, "Actual damage changes foreground immediately for both actors")
	_check(player_bar.trail_health == 100.0 and enemy_bar.trail_health == 100.0, "First impact preserves pre-damage health in trail")
	await _ticks(16)
	_check(player_bar.trail_health == 100.0 and enemy_bar.trail_health == 100.0, "Trail stays still during short pause between impacts")
	player.take_damage(14.0)
	enemy.take_damage(25.0)
	await _ticks(16)
	_check(player_bar.current_health == 72.0 and enemy_bar.current_health == 50.0, "Second impact accumulates real burst damage")
	_check(player_bar.trail_health == 100.0 and enemy_bar.trail_health == 100.0, "Each impact restarts hold and keeps total burst damage visible")
	await _ticks(18)
	_check(player_bar.trail_health > 72.0 and player_bar.trail_health < 100.0, "Player trail catches up gradually after last impact")
	_check(enemy_bar.trail_health > 50.0 and enemy_bar.trail_health < 100.0, "Enemy trail catches up gradually after last impact")
	await _ticks(20)
	_check(is_equal_approx(player_bar.trail_health, 72.0) and is_equal_approx(enemy_bar.trail_health, 50.0), "Both trails settle at actual health without changing gameplay")
	enemy.take_damage(10.0)
	await _ticks(32)
	var prior_trail: float = enemy_bar.trail_health
	enemy.take_damage(10.0)
	_check(is_equal_approx(enemy_bar.trail_health, prior_trail) and enemy_bar.current_health == 30.0, "Hit during catch-up preserves remaining trail without jumping backwards")
	await _ticks(15)
	_check(is_equal_approx(enemy_bar.trail_health, prior_trail), "Hit during catch-up also restarts hold")
	# Future healing uses the same health_changed contract, without a fake lost-HP layer.
	player.health = 90.0
	player.health_changed.emit(player.health, player.max_health)
	_check(player_bar.current_health == 90.0 and player_bar.trail_health == 90.0, "Healing updates both layers immediately")
	enemy.take_damage(1000.0)
	player.take_damage(1000.0)
	_check(not player_bar.visible and not enemy_bar.visible, "Lethal damage hides both overhead bars")
	var fresh := load("res://scenes/player.tscn").instantiate() as CharacterBody2D
	fresh.max_health = 200.0
	fresh.set_physics_process(false)
	yard.add_child(fresh)
	var fresh_bar: Node2D = fresh.get_node("HealthBar")
	_check(fresh_bar.current_health == 200.0 and fresh_bar.trail_health == 200.0 and fresh_bar.maximum_health == 200.0, "Custom Inspector maximum initializes full health without a fake damage trail")
	_check(fresh_bar.visible, "Fresh actor has a visible healthy bar after prior actors die")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
