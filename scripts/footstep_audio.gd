extends Node2D
## Listens to actual body travel; never drives movement or AI hearing.

signal step_played(profile: FootstepProfile, clip: AudioStream)

## Disable for a rig that supplies actual foot contacts through play_step().
@export var steps_from_movement := true
@export var default_profile: FootstepProfile
@export_range(16.0, 200.0, 1.0, "suffix:px") var step_distance: float = 80.0
@export_range(-40.0, 0.0, 1.0, "suffix:dB") var volume_db: float = -16.0
@export_range(0.0, 0.08, 0.005) var pitch_variation: float = 0.025

var _distance: float = 0.0
var _bags: Dictionary = {}
var _last_clip: AudioStream
var _next_voice: int = 0
var _rng := RandomNumberGenerator.new()
@onready var _actor: CharacterBody2D = get_parent()
@onready var _voices: Array[AudioStreamPlayer2D] = [$Left, $Right]


func _ready() -> void:
	if steps_from_movement:
		_actor.moved.connect(_on_moved)
	_actor.died.connect(stop)


func profile_at(point: Vector2) -> FootstepProfile:
	var selected: FootstepSurface
	for node in get_tree().get_nodes_in_group(&"footstep_surfaces"):
		var surface := node as FootstepSurface
		if surface == null or surface.profile == null or surface.get_world_2d() != get_world_2d():
			continue
		if surface.contains_point(point) and (selected == null or surface.priority > selected.priority):
			selected = surface
	return selected.profile if selected != null else default_profile


func _on_moved(distance: float) -> void:
	if _actor.is_dead or distance <= 0.0:
		return
	# A discontinuous move must not play a burst of missed footsteps.
	if distance > step_distance * 2.0:
		_distance = 0.0
		return
	_distance += distance
	if _distance < step_distance:
		return
	_distance = fmod(_distance, step_distance)
	play_step()


func play_step() -> void:
	if _actor.is_dead:
		return
	var profile := profile_at(global_position)
	if profile == null or profile.clips.is_empty():
		return
	var clip := _next_clip(profile)
	if clip == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = clip
	voice.volume_db = volume_db + profile.gain_db
	voice.pitch_scale = _rng.randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	voice.play()
	step_played.emit(profile, clip)


func _next_clip(profile: FootstepProfile) -> AudioStream:
	var bag: Array = _bags.get(profile, [])
	if bag.is_empty():
		bag = profile.clips.filter(func(clip: AudioStream): return clip != null)
		if bag.is_empty():
			return null
		bag.shuffle()
		# All variants play before refill; no repeated clip at the bag boundary.
		if bag.size() > 1 and bag.back() == _last_clip:
			var first: AudioStream = bag[0]
			bag[0] = bag.back()
			bag[bag.size() - 1] = first
	var clip: AudioStream = bag.pop_back()
	_bags[profile] = bag
	_last_clip = clip
	return clip


func stop() -> void:
	_distance = 0.0
	for voice in _voices:
		voice.stop()
