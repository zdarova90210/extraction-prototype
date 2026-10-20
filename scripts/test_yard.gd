extends Node2D
## Local scene wiring only; gameplay objects do not depend on this map.

@onready var target: StaticBody2D = $Target
@onready var status: Label = $HUD/TargetStatus
@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $Enemy
@onready var weapon: Node2D = $Player/Aim/Weapon
@onready var combat_status: Label = $HUD/CombatStatus
@onready var death_screen: Control = $HUD/DeathScreen

var _hurt_time: float = 0.0


func _ready() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	$HUD/AimCursor.bind(player, weapon)
	$HUD/WeaponReadout.bind(weapon)
	$HUD/PauseMenu.toggled.connect(_on_pause_toggled)
	target.health_changed.connect(_on_target_health_changed)
	target.destroyed.connect(_on_target_destroyed)
	_on_target_health_changed(target.health, target.max_health)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	weapon.shot_fired.connect(_on_player_shot)
	enemy.state_changed.connect(_on_enemy_state_changed)
	enemy.died.connect(_on_enemy_died)
	_on_enemy_state_changed(enemy.get_state_description())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo():
		get_tree().reload_current_scene()


func _on_target_health_changed(current: float, maximum: float) -> void:
	status.text = "МИШЕНЬ  %d / %d" % [ceili(current), ceili(maximum)]


func _on_target_destroyed() -> void:
	status.text = "МИШЕНЬ РАЗРУШЕНА"
	$Navigation.rebuild_after_physics()


func _process(delta: float) -> void:
	_hurt_time = maxf(0.0, _hurt_time - delta)
	$HUD/HurtFlash.color.a = _hurt_time * 0.65


func _on_player_damaged() -> void:
	_hurt_time = 0.3


func _on_pause_toggled(open: bool) -> void:
	$HUD/AimCursor.visible = not open
	if not open:
		$HUD/AimCursor.sync_pointer()


func _on_player_died() -> void:
	death_screen.show()
	combat_status.text = "БОЙ ОКОНЧЕН · Enter — повторить"


func _on_player_shot(from: Vector2, _to: Vector2, _hit: bool) -> void:
	enemy.hear_shot(from)


func _on_enemy_state_changed(description: String) -> void:
	if not player.is_dead:
		combat_status.text = "ОХРАННИК / " + description


func _on_enemy_died() -> void:
	if not player.is_dead:
		combat_status.text = "СЕКТОР ЗАЧИЩЕН · Enter — повторить бой"
