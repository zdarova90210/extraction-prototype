extends "res://scripts/sound_player.gd"
## Transient raid cues survive the return to base, never reconstructed from saves.

@export var start_cue: SoundCue
@export var success_cue: SoundCue
@export var failure_cue: SoundCue
var _owner_id: int = 0


func begin_raid(owner: Node, play_intro: bool = true) -> void:
	stop(0.0)
	_owner_id = owner.get_instance_id()
	if play_intro:
		crossfade(start_cue, 0.02)


func finish_raid(owner: Node, success: bool) -> bool:
	if _owner_id != owner.get_instance_id():
		return false
	_owner_id = 0
	return crossfade(success_cue if success else failure_cue, 0.10)


func abandon_raid(owner: Node) -> void:
	if _owner_id == owner.get_instance_id():
		_owner_id = 0
		stop(0.06)
