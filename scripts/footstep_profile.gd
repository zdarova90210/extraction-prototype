class_name FootstepProfile
extends Resource
## Shared surface recordings; runtime playback never changes this resource.

@export var surface_id: StringName = &"concrete"
@export var clips: Array[AudioStream] = []
@export_range(-30.0, 6.0, 0.5, "suffix:dB") var gain_db: float = 0.0
