extends Node2D
## Saved view-specific art and attachment points; no movement or weapon logic.

@export var bearing_degrees := 0.0
@export var stride_axis := Vector2.RIGHT
@export var knee_sides := Vector2.ONE
@export var use_profile_tracks := true
@export var foot_tracks := Vector2(-4, 3)
@export var lowered_angle_degrees := 38.0
@export var lowered_shift := Vector2.ZERO
@export var drawn_weapon_angle := 0.0
@export var arm_scale_limits := Vector2(0.65, 1.35)
## Support/trigger bend sides (+/-1). Check lowered elbows as well as wrist contact.
@export var arm_elbow_sides := Vector2(-1, 1)
@export_range(0.5, 1.0, 0.05) var arm_size := 1.0

@onready var near_hip: Vector2 = $NearLeg.position
@onready var far_hip: Vector2 = $FarLeg.position
@onready var near_segments := PackedVector2Array([$NearLeg/Shin.position, $NearLeg/Shin/Foot.position])
@onready var far_segments := PackedVector2Array([$FarLeg/Shin.position, $FarLeg/Shin/Foot.position])
@onready var grip_origin: Vector2 = $Upper/Grip.position
