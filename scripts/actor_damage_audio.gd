extends "res://scripts/sound_player.gd"
## Accepted damage owns one reaction, including hits at the developer immortality floor.

@export var damage_cue: SoundCue


func _ready() -> void:
	super._ready()
	get_parent().damaged.connect(_on_damaged)


func _on_damaged() -> void:
	play(damage_cue)
