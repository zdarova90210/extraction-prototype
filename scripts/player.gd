extends CharacterBody2D
## Top-down movement. Only Aim turns, so the camera and body stay upright.

@export_range(20.0, 800.0, 5.0, "suffix:px/s") var move_speed: float = 250.0

@onready var aim: Node2D = $Aim
@onready var weapon: Node2D = $Aim/Weapon


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
	var mouse_position := get_global_mouse_position()
	if global_position.distance_squared_to(mouse_position) > 1.0:
		aim.look_at(mouse_position)
	if Input.is_action_pressed("shoot"):
		weapon.try_fire(mouse_position, self)
