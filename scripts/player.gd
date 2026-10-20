extends CharacterBody2D
## Top-down movement. Only Aim turns, so the camera and body stay upright.

signal health_changed(current: float, maximum: float)
signal damaged
signal died

@export_range(20.0, 800.0, 5.0, "suffix:px/s") var move_speed: float = 250.0
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0

var health: float = 100.0
var is_dead: bool = false

@onready var aim: Node2D = $Aim
@onready var weapon: Node2D = $Aim/Weapon


func _ready() -> void:
	health = max_health
	$AudioListener2D.make_current()
	health_changed.emit(health, max_health)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
	var mouse_position := get_global_mouse_position()
	if global_position.distance_squared_to(mouse_position) > 1.0:
		aim.look_at(mouse_position)
	if Input.is_action_pressed("shoot"):
		weapon.try_fire(mouse_position, self)
	if Input.is_action_just_pressed("reload"):
		if weapon.is_reloading:
			weapon.try_active_reload()
		else:
			weapon.request_reload()


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	$Aim/BodyVisual.flash_hit()
	$HitAudio.play()
	health_changed.emit(health, max_health)
	damaged.emit()
	if health <= 0.0:
		is_dead = true
		velocity = Vector2.ZERO
		weapon.stop()
		$Aim/BodyVisual.fallen = true
		$Aim/Weapon.hide()
		died.emit()


func restore_state() -> void:
	is_dead = false
	health = max_health
	velocity = Vector2.ZERO
	$Aim/BodyVisual.fallen = false
	weapon.show()
	weapon.restore_state()
	health_changed.emit(health, max_health)
