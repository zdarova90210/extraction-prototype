extends Node2D
## Local scene wiring only; gameplay objects do not depend on this map.

signal guards_changed

const GUARD_SCENE = preload("res://scenes/enemy.tscn")
const MAX_GUARDS: int = 8

@onready var target: StaticBody2D = $Target
@onready var progress: Node = get_node("/root/RaidProgress")
@onready var player: CharacterBody2D = $Player
@onready var weapon: Node2D = $Player/Aim/Weapon
@onready var death_screen: Control = $HUD/DeathScreen

var _hurt_time: float = 0.0
var _guards: Array[CharacterBody2D] = []
var _raid_finished: bool = false


func _ready() -> void:
	if not progress.begin_raid():
		_leave_for_base.call_deferred()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	$HUD/AimCursor.bind(player, weapon)
	$HUD/WeaponReadout.bind(weapon)
	$HUD/PauseMenu.toggled.connect(_on_pause_toggled)
	$HUD/LootMenu.toggled.connect(_on_pause_toggled)
	$HUD/PauseMenu.gameplay_overlay = $HUD/LootMenu
	$HUD/LootMenu.bind(player)
	$ExtractionZone.bind(player)
	$ExtractionZone.completed.connect(_on_extracted)
	$HUD/DeathScreen/ToBase.pressed.connect(_leave_for_base)
	target.destroyed.connect(_on_target_destroyed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	weapon.shot_fired.connect(_on_player_shot)
	for guard in get_tree().get_nodes_in_group("guards"):
		if is_ancestor_of(guard):
			_register_guard(guard)
	$HUD/PauseMenu/DeveloperPanel.bind(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo() and not $HUD/LootMenu.visible and not _raid_finished:
		get_tree().reload_current_scene()


func _on_target_destroyed() -> void:
	$Navigation.rebuild_after_physics()


func _process(delta: float) -> void:
	_hurt_time = maxf(0.0, _hurt_time - delta)
	$HUD/HurtFlash.color.a = _hurt_time * 0.65


func _on_player_damaged() -> void:
	_hurt_time = 0.3


func _on_pause_toggled(_open: bool) -> void:
	var open: bool = $HUD/PauseMenu.visible or $HUD/LootMenu.visible or player.is_dead or _raid_finished
	player.input_enabled = not open
	$HUD/AimCursor.visible = not open
	$HUD/AimCursor.set_process(not open)
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		$HUD/AimCursor.sync_pointer()


func _on_player_died() -> void:
	progress.record_death(player.get_node("Inventory"))
	death_screen.show()
	_on_pause_toggled(false)


func _on_extracted() -> void:
	if player.is_dead or _raid_finished:
		return
	if not progress.finish_raid(player.get_node("Inventory")):
		$ExtractionZone.save_failed(progress.error_message)
		return
	_raid_finished = true
	player.damage_enabled = false
	weapon.stop()
	$HUD/LootMenu.close_menu()
	_on_pause_toggled(false)
	_leave_for_base.call_deferred()


func _leave_for_base() -> void:
	$HUD/PauseMenu.set_open(false)
	Input.action_release("shoot")
	get_tree().change_scene_to_file("res://scenes/base.tscn")


func _on_player_shot(from: Vector2, _to: Vector2, _hit: bool) -> void:
	for guard in get_guards():
		guard.hear_shot(from)


func get_guards() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for guard in _guards:
		if is_instance_valid(guard) and not guard.is_queued_for_deletion():
			result.append(guard)
	return result


func _register_guard(guard: CharacterBody2D) -> void:
	_guards.append(guard)
	guard.died.connect(_on_enemy_died)
	guards_changed.emit()


func _on_enemy_died() -> void:
	guards_changed.emit()


func spawn_guard(marker_index: int) -> String:
	if get_guards().size() >= MAX_GUARDS:
		return "Лимит: 8 охранников. Удалите лишних или погибших."
	var markers := $GuardSpawns.get_children()
	if marker_index < 0 or marker_index >= markers.size():
		return "Точка появления не найдена."
	var point: Vector2 = markers[marker_index].global_position
	var map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return "Навигация ещё загружается. Попробуйте снова."
	if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) > 6.0:
		return "Точка вне прохода. Передвиньте маркер в редакторе."
	var shape := CircleShape2D.new()
	shape.radius = 19.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 15
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "Точка занята персонажем или препятствием."
	# Also inspect transforms: multiple clicks can precede a PhysicsServer sync.
	for guard in get_guards():
		if not guard.is_dead and guard.global_position.distance_to(point) < 40.0:
			return "Точка уже занята охранником."
	if player.global_position.distance_to(point) < 40.0:
		return "Точка занята игроком."
	var guard := GUARD_SCENE.instantiate() as CharacterBody2D
	guard.target = player
	guard.position = $TestEnemies.to_local(point)
	guard.get_node("Aim").rotation = markers[marker_index].global_rotation
	$TestEnemies.add_child(guard)
	_register_guard(guard)
	return "Охранник добавлен: " + markers[marker_index].name


func remove_guard(guard: CharacterBody2D) -> void:
	if not is_instance_valid(guard) or guard not in _guards:
		return
	_guards.erase(guard)
	guard.queue_free()
	guards_changed.emit()


func remove_all_guards() -> void:
	for guard in get_guards():
		remove_guard(guard)


func restore_player() -> void:
	if not progress.raid_active:
		progress.begin_raid()
	player.restore_state()
	death_screen.hide()
	_hurt_time = 0.0
	$HUD/HurtFlash.color.a = 0.0
	$HUD/AimCursor.bind(player, weapon)
	_on_pause_toggled(false)
