@tool
extends Node2D
## Sprite presentation and contact shadow; exposes flash_hit/fallen to the actor.
## Does not read input, move the body, choose targets or alter weapon raycasts.

@export var frames: SpriteFrames
@export_range(16.0, 160.0, 1.0) var stride_distance: float = 64.0
@export var sprite_scale: Vector2 = Vector2(0.25, 0.25)
## Optional unit-ellipse shadow. Unassigned variants keep their saved shadow.
@export var contact_shadow: Polygon2D
@export var actor: CharacterBody2D
var fallen: bool = false
var _hit_time: float = 0.0
var _travel: float = 0.0
var _walking: bool = false
var _aim: Node2D
@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_aim = get_parent() as Node2D
	if not Engine.is_editor_hint():
		actor.moved.connect(_on_moved)
	_sync_visual()


func _on_moved(distance: float) -> void:
	_walking = distance > 0.01 and distance < stride_distance * 2.0
	if not _walking:
		_travel = 0.0
		return
	var facing := Vector2.RIGHT.rotated(_aim.global_rotation)
	var sign_of_motion := -1.0 if actor.velocity.dot(facing) < -1.0 else 1.0
	_travel = fposmod(_travel + distance * sign_of_motion, stride_distance)


func flash_hit() -> void:
	_hit_time = 0.15


func _process(delta: float) -> void:
	_hit_time = maxf(0.0, _hit_time - delta)
	_sync_visual()


func _physics_process(_delta: float) -> void:
	# Parent AI/input has already turned Aim and emitted actual travel this tick.
	_sync_visual()


func _sync_visual() -> void:
	if not is_instance_valid(actor) or frames == null or not is_instance_valid(sprite):
		return
	# Named BodyVisual remains the shared actor interface; its art stays upright.
	global_position = _aim.global_position
	global_rotation = 0.0
	sprite.scale = sprite_scale
	var facing := Vector2.RIGHT.rotated(_aim.global_rotation)
	var animation := &"side"
	if absf(facing.y) > absf(facing.x):
		animation = &"down" if facing.y > 0.0 else &"up"
	var walking := _walking and not actor.velocity.is_zero_approx() and not fallen
	var frame := floori(_travel / stride_distance * 4.0) if walking else 0
	sprite.texture = frames.get_frame_texture(animation, frame)
	sprite.flip_h = facing.x < 0.0 and animation == &"side"
	# Standing art is above the ground origin. A fallen body lies ON that origin.
	sprite.position = Vector2.ZERO if not fallen else -_aim.position
	sprite.rotation = PI * 0.5 if fallen else 0.0
	sprite.self_modulate = Color(1.8, 1.8, 1.8) if _hit_time > 0.0 else (Color(0.6, 0.6, 0.6) if fallen else Color.WHITE)
	_sync_contact_shadow()


func _sync_contact_shadow() -> void:
	if not is_instance_valid(contact_shadow):
		return
	# Atlas margins align animation frames but are not part of the visible body.
	var visible_rect := sprite.get_rect()
	if sprite.texture is AtlasTexture:
		var atlas := sprite.texture as AtlasTexture
		visible_rect = Rect2(visible_rect.position + atlas.margin.position, atlas.region.size)
	if sprite.flip_h:
		visible_rect.position.x = -visible_rect.end.x
	if sprite.flip_v:
		visible_rect.position.y = -visible_rect.end.y
	var shadow_parent := contact_shadow.get_parent() as Node2D
	var sprite_to_parent := shadow_parent.global_transform.affine_inverse() * sprite.global_transform
	var body_bounds: Rect2 = sprite_to_parent * visible_rect
	contact_shadow.rotation = 0.0
	if fallen:
		contact_shadow.position = body_bounds.get_center() + Vector2(0, 1)
		contact_shadow.scale = Vector2(body_bounds.size.x * 0.48, maxf(3.0, body_bounds.size.y * 0.36))
	else:
		contact_shadow.position = Vector2(body_bounds.get_center().x, body_bounds.end.y - 1.5)
		contact_shadow.scale = Vector2(maxf(6.0, body_bounds.size.x * 0.42), 3.0)
