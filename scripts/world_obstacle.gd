@tool
class_name WorldObstacle
extends StaticBody2D
## Shared physical rules for covers and loot containers. Artwork and footprint
## remain in their own scenes; neither determines whether a standing shot stops.

const MOVEMENT_MASK := 1
const SHOT_MASK := 16

@export_group("Obstacle Rules")
@export var blocks_movement := true:
	set(value):
		blocks_movement = value
		_sync_obstacle_layers()
@export var blocks_shots := true:
	set(value):
		blocks_shots = value
		_sync_obstacle_layers()

func _ready() -> void:
	_sync_obstacle_layers()

func _sync_obstacle_layers() -> void:
	# Preserve unrelated layers, and keep both rules independent. The same
	# settings are visible immediately in the editor and used by the physics ray.
	set_collision_layer_value(1, blocks_movement)
	set_collision_layer_value(5, blocks_shots)
