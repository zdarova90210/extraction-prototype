extends SceneTree
## Actual menu input plus spawning, multiple guards, removal and recovery.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	NavigationServer2D.map_set_use_async_iterations(root.get_world_2d().navigation_map, false)
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


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _ticks(1)


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _ticks(1)


func _run() -> void:
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	await _ticks(5)
	var menu: Control = yard.get_node("HUD/PauseMenu")
	var panel: Control = menu.get_node("DeveloperPanel")
	var player: CharacterBody2D = yard.get_node("Player")
	var weapon: Node2D = player.get_node("Aim/Weapon")
	var identity := yard.get_instance_id()
	_check(yard.get_guards().size() == 1 and not menu.visible, "Room opens with its saved original guard and tools closed")
	await _key(KEY_F2)
	_check(paused and menu.visible and panel.visible and not menu.get_node("Center").visible, "F2 opens developer tools with one shared pause owner")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not yard.get_node("HUD/AimCursor").visible, "Tools use normal pointer and hide gameplay reticle")
	var content: VBoxContainer = panel.content
	await _click(content.get_node("SpawnRow/Add"))
	_check(yard.get_guards().size() == 2 and panel.guards.item_count == 2, "Clicking Add spawns a second guard and updates selectable list")
	var added: CharacterBody2D = yard.get_guards()[1]
	_check(added.target == player and added.health == 150.0 and added.weapon.ammo == 4, "Spawned guard has real player target and current combat profile")
	yard.spawn_guard(0)
	_check(yard.get_guards().size() == 2, "Repeated add at occupied marker cannot stack guards")
	panel.guards.select(0)
	await _click(content.get_node("Actions/Remove"))
	_check(yard.get_guards().size() == 1 and not yard.has_node("Enemy"), "Removing original guard works without a permanently required Enemy node")
	weapon.try_fire(Vector2(900, 565), player)
	_check(added.state == added.State.INVESTIGATE, "Successful player shot reaches dynamically added guard after original removal")
	panel.spawn_point.select(1)
	await _click(content.get_node("SpawnRow/Add"))
	var second: CharacterBody2D = yard.get_guards()[-1]
	panel.guards.select(1)
	added.take_damage(1000.0)
	_check(panel.selected_guard() == second and content.get_node("Count").text.ends_with("живы: 1"), "List preserves selection and tracks living guards after another guard dies")
	await _click(content.get_node("Actions/Clear"))
	_check(yard.get_guards().is_empty() and panel.guards.item_count == 0 and content.get_node("Count").text.ends_with("живы: 0"), "Clear removes living guards and corpses and updates developer count")
	player.take_damage(1000.0)
	await _click(content.get_node("Actions/Restore"))
	_check(not player.is_dead and player.health == player.max_health and player.get_node("HealthBar").visible, "Restore revives player and synchronizes overhead health")
	_check(weapon.enabled and weapon.ammo == weapon.magazine_size and weapon.visible and not weapon.is_reloading, "Restore resets a dead weapon and supplies a loaded magazine")
	_check(not yard.death_screen.visible and not player.get_node("Aim/BodyVisual").fallen, "Restore clears death screen and fallen presentation")
	_check(weapon.try_fire(Vector2(900, 565), player), "Player can really fire after recovery, even when no guards remain")
	var marker: Marker2D = yard.get_node("GuardSpawns").get_child(0)
	var saved := marker.position
	marker.position = Vector2(80, 560)
	yard.spawn_guard(0)
	_check(yard.get_guards().is_empty(), "Spawn rejects a marker inside a wall or outside navigation")
	marker.position = player.position
	yard.spawn_guard(0)
	_check(yard.get_guards().is_empty(), "Spawn rejects a marker overlapping player")
	var points := [Vector2(300, 600), Vector2(400, 600), Vector2(500, 600), Vector2(600, 600), Vector2(700, 600), Vector2(800, 600), Vector2(900, 600), Vector2(1100, 700)]
	for point in points:
		marker.position = point
		yard.spawn_guard(0)
	_check(yard.get_guards().size() == 8 and content.get_node("SpawnRow/Add").disabled, "Room reaches its explicit eight-guard cap and disables Add")
	marker.position = Vector2(1200, 700)
	yard.spawn_guard(0)
	_check(yard.get_guards().size() == 8, "API also rejects spawning beyond cap")
	marker.position = saved
	await _key(KEY_F2)
	_check(not paused and not menu.visible and not Input.is_action_pressed("shoot") and yard.get_instance_id() == identity, "F2 resumes same room without a stray shot or restart")
	await _key(KEY_ESCAPE)
	await _click(menu.get_node("Center/Panel/Margin/Content/Developer"))
	_check(paused and panel.visible, "Developer tools are also reachable through Escape menu")
	await _key(KEY_ESCAPE)
	_check(not paused and not menu.visible, "Escape closes developer tools without opening a second menu")
	await _key(KEY_F2)
	await _click(content.get_node("Actions/Restart"))
	await _ticks(4)
	_check(current_scene.get_instance_id() != identity and not paused and current_scene.get_guards().size() == 1 and not current_scene.get_node("HUD/PauseMenu").visible, "Restart restores saved scene, original guard and clean pause state")
	current_scene.queue_free()
	await _ticks(2)
	var blank := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	blank.get_node("Enemy").free()
	root.add_child(blank)
	current_scene = blank
	await _ticks(4)
	_check(blank.get_guards().is_empty() and not blank.has_node("HUD/CombatStatus"), "Empty room loads without a gameplay status banner")
	blank.queue_free()
	await _ticks(2)
	var multiple := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	var placed := load("res://scenes/enemy.tscn").instantiate() as CharacterBody2D
	placed.position = Vector2(1340, 740)
	placed.target = multiple.get_node("Player")
	multiple.add_child(placed)
	root.add_child(multiple)
	current_scene = multiple
	await _ticks(4)
	_check(multiple.get_guards().size() == 2 and multiple.get_node("HUD/PauseMenu/DeveloperPanel").guards.item_count == 2, "Guards placed manually in editor register with room tools")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
