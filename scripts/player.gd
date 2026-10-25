extends CharacterBody2D
## Top-down movement. Only Aim turns, so the camera and body stay upright.

signal health_changed(current: float, maximum: float)
signal damaged
signal died
signal moved(distance: float)

@export_range(20.0, 800.0, 5.0, "suffix:px/s") var move_speed: float = 160.0
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
@export_range(0.3, 0.9, 0.05) var sneak_speed_multiplier := 0.6

var health: float = 100.0
var is_dead: bool = false
var input_enabled: bool = true:
	set(value):
		if input_enabled != value:
			_wait_for_fire_release = true
		input_enabled = value
var sneaking := false
var _wait_for_fire_release := false
var damage_enabled: bool = true
var prevent_death: bool = false

@onready var aim: Node2D = $Aim
@onready var weapon: Node2D = $Aim/Weapon
@onready var item_use: Node = $ItemUse
@onready var body_visual: Node2D = $Aim/BodyVisual


func _ready() -> void:
	health = max_health
	$AudioListener2D.make_current()
	health_changed.emit(health, max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_sneak") and not event.is_echo() and input_enabled and not is_dead:
		sneaking = not sneaking
		body_visual.sneaking = sneaking
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("use_item") and not event.is_echo() and input_enabled and not is_dead:
		if item_use.is_using:
			item_use.cancel()
		else:
			item_use.use_first_healing_item()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if is_dead or not input_enabled:
		item_use.cancel()
		velocity = Vector2.ZERO
		body_visual.set_motion(0.0, 0.0)
		_wait_for_fire_release = true
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed * lerpf(1.0, sneak_speed_multiplier, body_visual.sneak_blend)
	move_and_slide()
	var mouse_position := get_global_mouse_position()
	if aim.global_position.distance_squared_to(mouse_position) > 1.0:
		aim.look_at(mouse_position)
	moved.emit(get_position_delta().length())
	var shoot := Input.is_action_pressed("shoot")
	if _wait_for_fire_release:
		if shoot or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			shoot = false
		else:
			_wait_for_fire_release = false
	body_visual.sync_actor()
	if item_use.is_using:
		if not direction.is_zero_approx():
			item_use.cancel()
		else:
			item_use.advance(delta)
		return
	if shoot:
		# Input is in rendered world coordinates; combat uses the ground plane.
		weapon.try_fire(weapon.aim_from_screen(mouse_position, self), self)
	if Input.is_action_just_pressed("reload"):
		if weapon.is_reloading:
			weapon.try_active_reload()
		else:
			weapon.request_reload()


func take_damage(amount: float) -> void:
	if is_dead or not damage_enabled or amount <= 0.0:
		return
	health = maxf(1.0 if prevent_death else 0.0, health - amount)
	$Aim/BodyVisual.flash_hit()
	health_changed.emit(health, max_health)
	damaged.emit()
	if health <= 0.0:
		is_dead = true
		velocity = Vector2.ZERO
		weapon.stop()
		$Aim/BodyVisual.fallen = true
		$Aim/Weapon.hide()
		died.emit()


func restore_health(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before := health
	health = minf(max_health, health + amount)
	if health > before:
		health_changed.emit(health, max_health)
	return health - before


func restore_state() -> void:
	item_use.cancel("")
	is_dead = false
	damage_enabled = true
	health = max_health
	velocity = Vector2.ZERO
	$Aim/BodyVisual.fallen = false
	body_visual.reset_pose()
	body_visual.sneaking = sneaking
	body_visual.sync_actor()
	_wait_for_fire_release = true
	weapon.show()
	weapon.restore_state()
	health_changed.emit(health, max_health)
