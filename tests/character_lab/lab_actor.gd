extends CharacterBody2D
## Test-only input adapter. Uses the production Weapon, WeaponAudio and FootstepAudio.

signal moved(distance: float)
signal died

@export var move_speed := 120.0
@export_range(0.3, 0.9, 0.05) var sneak_speed_multiplier := 0.6
var is_dead := false
var input_enabled := true
var input_blocked := false
var sneaking := false
var _wait_for_release := false

@onready var visual: Node2D = $Visual
@onready var weapon: Node2D = $Weapon

func _ready() -> void:
	weapon.shot_fired.connect(visual.notify_shot)
	visual.foot_contact.connect($Footsteps.play_step)
	$AudioListener2D.make_current()

func _physics_process(_delta: float) -> void:
	if not input_enabled:
		return
	if input_blocked:
		velocity = Vector2.ZERO
		visual.set_motion(0.0, 0.0)
		_wait_for_release = true
		return
	var speed := move_speed * lerpf(1.0, sneak_speed_multiplier, visual.sneak_blend)
	velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * speed
	move_and_slide()
	var distance := get_position_delta().length()
	moved.emit(distance)
	var direction := (get_global_mouse_position() - (global_position + Vector2(0, -48))).angle()
	visual.aim_angle = direction if visual.direction_override < 0 else visual.direction_override * PI / 4.0
	visual.motion_vector = get_position_delta().normalized()
	visual.set_motion(distance, velocity.dot(Vector2.from_angle(visual.aim_angle)))
	var shoot := Input.is_action_pressed("shoot")
	if _wait_for_release:
		if shoot or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			shoot = false
		else:
			_wait_for_release = false
	visual.apply_pose()
	if Input.is_action_just_pressed("reload"):
		weapon.request_reload()
	if shoot:
		fire_current_pose()

func fire_current_pose() -> bool:
	var direction := Vector2.RIGHT.rotated(visual.aim_angle)
	weapon.rotation = visual.aim_angle
	return weapon.try_fire(global_position + direction * weapon.max_range, self)

func reset_state(spawn: Vector2) -> void:
	global_position = spawn
	velocity = Vector2.ZERO
	visual.reset_pose()
	$Footsteps.stop()
	weapon.restore_state()
	_wait_for_release = true

func suspend_input(open: bool) -> void:
	input_enabled = not open
	_wait_for_release = true

func set_sneaking(enabled: bool) -> void:
	sneaking = enabled
	visual.sneaking = enabled
