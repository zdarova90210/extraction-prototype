extends Node2D
## Scene-owned background and optional positional details, independent of gameplay RNG.

signal detail_played(spot: AmbientSpot, clip: AudioStream)

@export var autoplay: bool = true
@export var background_stream: AudioStream
@export_range(-50.0, 0.0, 1.0, "suffix:dB") var background_volume_db: float = -20.0
@export_range(0.0, 8.0, 0.1, "suffix:s") var fade_in_duration: float = 2.5
@export var first_detail_delay: Vector2 = Vector2(3.0, 6.0)
@export var detail_interval: Vector2 = Vector2(10.0, 22.0)

var _running: bool = false
var _fade_elapsed: float = 0.0
var _detail_remaining: float = 0.0
var _last_spot: AmbientSpot
var _last_clip: AudioStream
var _spots: Array[AmbientSpot] = []
var _rng := RandomNumberGenerator.new()
@onready var bed: AudioStreamPlayer = $Bed


func _ready() -> void:
	_rng.randomize()
	for child in $Details.get_children():
		if child is AmbientSpot:
			_spots.append(child)
	if autoplay:
		start()


func start() -> void:
	if _running:
		return
	_running = true
	_fade_elapsed = 0.0
	_detail_remaining = _delay(first_detail_delay)
	bed.stream = background_stream
	bed.volume_db = -60.0 if fade_in_duration > 0.0 else background_volume_db
	if background_stream != null:
		bed.play(_rng.randf_range(0.0, maxf(0.0, background_stream.get_length() - 0.1)))
	for spot in _spots:
		if is_instance_valid(spot):
			spot.start_ambience()


func stop() -> void:
	_running = false
	bed.stop()
	for spot in _spots:
		if is_instance_valid(spot):
			spot.stop_ambience()


func _delay(bounds: Vector2) -> float:
	var minimum := maxf(0.1, minf(bounds.x, bounds.y))
	return _rng.randf_range(minimum, maxf(minimum, maxf(bounds.x, bounds.y)))


func _process(delta: float) -> void:
	if not _running:
		return
	_fade_elapsed = minf(fade_in_duration, _fade_elapsed + delta)
	var fade := smoothstep(0.0, fade_in_duration, _fade_elapsed) if fade_in_duration > 0.0 else 1.0
	bed.volume_db = lerpf(-60.0, background_volume_db, fade)
	# Wait for the current source to finish, then leave a full quiet interval.
	for spot in _spots:
		if is_instance_valid(spot) and spot.playing:
			return
	_detail_remaining -= delta
	if _detail_remaining <= 0.0:
		_play_random_detail()
		_detail_remaining = _delay(detail_interval)


func _play_random_detail() -> bool:
	var candidates: Array[AmbientSpot] = []
	for spot in _spots:
		if is_instance_valid(spot) and spot.cue != null and spot.cue.clips.any(func(clip): return clip != null):
			candidates.append(spot)
	if candidates.size() > 1:
		candidates.erase(_last_spot)
	if candidates.is_empty():
		return false
	var spot := candidates[_rng.randi_range(0, candidates.size() - 1)]
	# Respect authored priorities without consuming gameplay's global RNG.
	var choices: Array[int] = []
	for index in range(spot.cue.clips.size()):
		if spot.cue.clips[index] != null and spot.cue.clips[index] != _last_clip:
			choices.append(index)
	if choices.is_empty():
		for index in range(spot.cue.clips.size()):
			if spot.cue.clips[index] != null:
				choices.append(index)
	var total := 0.0
	for index in choices:
		total += spot.cue.weight_at(index)
	var roll := _rng.randf() * total
	var selected: int = choices.back()
	for index in choices:
		roll -= spot.cue.weight_at(index)
		if roll <= 0.0:
			selected = index
			break
	var clip := spot.cue.clips[selected]
	spot.stream = clip
	spot.volume_db = spot.cue.volume_db
	spot.pitch_scale = _rng.randf_range(1.0 - spot.cue.pitch_variation, 1.0 + spot.cue.pitch_variation)
	spot.play()
	_last_spot = spot
	_last_clip = clip
	detail_played.emit(spot, clip)
	return true
