class_name AmbientSpot
extends AudioStreamPlayer2D
## Authored environmental source; no collision, movement or AI noise event.

@export var cue: SoundCue


func start_ambience() -> void:
	pass


func stop_ambience() -> void:
	stop()
