@tool
extends "res://scripts/actor_visual.gd"
## Sprite presentation only; inherits the actor's flash_hit/fallen visual contract.
## Does not read input, move the body, choose targets or alter weapon raycasts.

@export var frames: SpriteFrames
@export_range(16.0, 160.0, 1.0) var stride_distance: float = 64.0
@export var sprite_scale: Vector2 = Vector2(0.25, 0.25)
var _travel: float = 0.0
var _walking: bool = false
var _actor: CharacterBody2D
var _aim: Node2D
@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_actor = get_parent().get_parent() as CharacterBody2D
	_aim = get_parent() as Node2D
	if not Engine.is_editor_hint():
		_actor.moved.connect(_on_moved)
	_sync_visual()


func _on_moved(distance: float) -> void:
	_walking = distance > 0.01 and distance < stride_distance * 2.0
	if not _walking:
		_travel = 0.0
		return
	var facing := Vector2.RIGHT.rotated(_aim.global_rotation)
	var sign_of_motion := -1.0 if _actor.velocity.dot(facing) < -1.0 else 1.0
	_travel = fposmod(_travel + distance * sign_of_motion, stride_distance)


func _process(delta: float) -> void:
	super._process(delta)
	_sync_visual()


func _physics_process(_delta: float) -> void:
	# Parent AI/input has already turned Aim and emitted actual travel this tick.
	_sync_visual()


func _sync_visual() -> void:
	if not is_instance_valid(_actor) or frames == null or not is_instance_valid(sprite):
		return
	# Named BodyVisual remains the shared actor interface; its art stays upright.
	global_position = _actor.global_position
	global_rotation = 0.0
	sprite.scale = sprite_scale
	var facing := Vector2.RIGHT.rotated(_aim.global_rotation)
	var animation := &"side"
	if absf(facing.y) > absf(facing.x):
		animation = &"down" if facing.y > 0.0 else &"up"
	var walking := _walking and not _actor.velocity.is_zero_approx() and not fallen
	var frame := floori(_travel / stride_distance * 4.0) if walking else 0
	sprite.texture = frames.get_frame_texture(animation, frame)
	sprite.flip_h = facing.x < 0.0 and animation == &"side"
	sprite.position = Vector2.ZERO if not fallen else Vector2(0, 6)
	sprite.rotation = PI * 0.5 if fallen else 0.0
	sprite.self_modulate = Color(1.8, 1.8, 1.8) if _hit_time > 0.0 else (Color(0.6, 0.6, 0.6) if fallen else Color.WHITE)


func _draw() -> void:
	# Sprite2D replaces the inherited procedural placeholder.
	pass
