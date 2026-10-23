class_name CharacterLabGait
extends Resource
## Visual tuning only. Does not change collision, damage or AI hearing.

@export_range(24.0, 140.0, 1.0) var stride_distance: float = 84.0
@export_range(2.0, 8.0, 0.25) var step_reach: float = 5.0
@export_range(0.5, 7.0, 0.25) var step_lift: float = 1.75
@export_range(0.45, 0.7, 0.01) var stance_fraction: float = 0.62
@export var foot_tracks := Vector2(-4.0, 3.0)
@export_range(0.0, 4.0, 0.1) var pelvis_lowering: float = 1.0
@export_range(0.0, 2.0, 0.1) var vertical_bob: float = 1.0
