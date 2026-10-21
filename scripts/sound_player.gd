extends Node
## Two small voices preserve tails; callers choose world or UI player scenes.

signal cue_played(cue: SoundCue)
@export var audio_bus: StringName = &"Interactions"
var _last_clip: AudioStream
var _next_voice: int = 0
var _fade: Tween
var _voice_fades: Dictionary = {}
@onready var _voices: Array[Node] = [$A, $B]


func _ready() -> void:
	for voice in _voices:
		voice.bus = audio_bus


func play(cue: SoundCue) -> bool:
	return _play(cue, 0.0)


func crossfade(cue: SoundCue, seconds: float) -> bool:
	return _play(cue, maxf(0.0, seconds))


func _play(cue: SoundCue, fade_seconds: float) -> bool:
	if cue == null:
		return false
	var clip := cue.choose(_last_clip)
	if clip == null:
		return false
	if is_instance_valid(_fade) and _fade.is_running():
		_fade.kill()
		_stop_voices()
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	_cancel_voice_fade(voice)
	if fade_seconds > 0.0:
		for previous in _voices:
			if previous != voice and previous.playing:
				_fade_voice(previous, 0.0, fade_seconds, true)
	voice.stream = clip
	voice.volume_db = -100.0 if fade_seconds > 0.0 else cue.volume_db
	voice.pitch_scale = randf_range(1.0 - cue.pitch_variation, 1.0 + cue.pitch_variation)
	voice.play()
	if fade_seconds > 0.0:
		_fade_voice(voice, db_to_linear(cue.volume_db), fade_seconds, false)
	_last_clip = clip
	cue_played.emit(cue)
	return true


func is_playing() -> bool:
	return _voices[0].playing or _voices[1].playing


func remaining_time() -> float:
	# Schedule overlaps from the actual selected recording and its playback pitch.
	var voice := _voices[(_next_voice + _voices.size() - 1) % _voices.size()]
	if not voice.playing or voice.stream == null:
		return 0.0
	return maxf(0.0, (voice.stream.get_length() - voice.get_playback_position()) / voice.pitch_scale)


func stop(fade_seconds: float = 0.035) -> void:
	if fade_seconds <= 0.0:
		if is_instance_valid(_fade):
			_fade.kill()
		_stop_voices()
		return
	if not is_playing() or (is_instance_valid(_fade) and _fade.is_running()):
		return
	for voice in _voices:
		_cancel_voice_fade(voice)
	_fade = create_tween().set_parallel(true)
	_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for voice in _voices:
		_fade.tween_method(_set_voice_gain.bind(voice), db_to_linear(voice.volume_db), 0.0, fade_seconds)
	_fade.chain().tween_callback(_stop_voices)


func _stop_voices() -> void:
	for voice in _voices:
		_cancel_voice_fade(voice)
		voice.stop()


func _set_voice_gain(gain: float, voice: Node) -> void:
	voice.volume_db = linear_to_db(maxf(gain, 0.00001))


func _cancel_voice_fade(voice: Node) -> void:
	var tween: Tween = _voice_fades.get(voice)
	if is_instance_valid(tween):
		tween.kill()
	_voice_fades.erase(voice)


func _fade_voice(voice: Node, gain: float, seconds: float, stop_after: bool) -> void:
	_cancel_voice_fade(voice)
	var tween := create_tween()
	_voice_fades[voice] = tween
	# Complementary sine/cosine amplitude ramps avoid the steep dip of a dB fade.
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if stop_after else Tween.EASE_OUT)
	tween.tween_method(_set_voice_gain.bind(voice), db_to_linear(voice.volume_db), gain, seconds)
	if stop_after:
		tween.tween_callback(voice.stop)
