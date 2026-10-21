class_name SoundCue
extends Resource
## Replaceable recordings and mix level for one presentation event.

@export var id: StringName
@export var clips: Array[AudioStream] = []
@export var clip_weights: PackedFloat32Array = PackedFloat32Array()
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = -20.0
@export_range(0.0, 0.05, 0.005) var pitch_variation: float = 0.015


func weight_at(index: int) -> float:
	if index >= 0 and index < clip_weights.size() and is_finite(clip_weights[index]) and clip_weights[index] > 0.0:
		return clip_weights[index]
	return 1.0


func choose(previous: AudioStream) -> AudioStream:
	var choices: Array[int] = []
	for index in range(clips.size()):
		if clips[index] != null and clips[index] != previous:
			choices.append(index)
	if choices.is_empty():
		for index in range(clips.size()):
			if clips[index] != null:
				choices.append(index)
	var total := 0.0
	for index in choices:
		total += weight_at(index)
	var roll := randf() * total
	for index in choices:
		roll -= weight_at(index)
		if roll <= 0.0:
			return clips[index]
	return clips[choices.back()] if not choices.is_empty() else null
