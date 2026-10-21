extends Node2D
## Bounded world-space voices for static surfaces. Actors own their damage reaction.

signal cue_played(cue: SoundCue, point: Vector2)

var _next_voice: int = 0
var _last_clips: Dictionary = {}
@onready var _voices: Array[AudioStreamPlayer2D] = [$A, $B, $C, $D]


func play_hit(point: Vector2, collider: Variant) -> void:
	if typeof(collider) != TYPE_OBJECT or not is_instance_valid(collider) or not collider.has_method("get_impact_cue"):
		return
	var cue := collider.call("get_impact_cue") as SoundCue
	if cue == null:
		return
	var clip := cue.choose(_last_clips.get(cue))
	if clip == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = clip
	voice.volume_db = cue.volume_db
	voice.pitch_scale = randf_range(1.0 - cue.pitch_variation, 1.0 + cue.pitch_variation)
	voice.global_position = point
	voice.play()
	_last_clips[cue] = clip
	cue_played.emit(cue, point)
