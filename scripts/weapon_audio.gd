extends Node2D
## Optional presentation component: gameplay emits events, audio only listens.

signal cue_played(cue: StringName)

@export var shot_stream: AudioStream
@export var dry_fire_stream: AudioStream
@export var reload_start_stream: AudioStream
@export var reload_finish_stream: AudioStream
@export var timing_success_stream: AudioStream
@export_range(-40.0, 0.0, 1.0, "suffix:dB") var shot_volume_db: float = -6.0
@export_range(-40.0, 0.0, 1.0, "suffix:dB") var action_volume_db: float = -9.0
@export_range(-40.0, 0.0, 1.0, "suffix:dB") var dry_fire_volume_db: float = -3.0
@export_range(-40.0, 0.0, 1.0, "suffix:dB") var timing_success_volume_db: float = -12.0

@onready var weapon: Node2D = get_parent()
@onready var shot_audio: AudioStreamPlayer2D = $Shot
@onready var action_audio: AudioStreamPlayer2D = $Action
@onready var dry_audio: AudioStreamPlayer2D = $DryFire
@onready var timing_audio: AudioStreamPlayer2D = $TimingSuccess


func _ready() -> void:
	shot_audio.volume_db = shot_volume_db
	action_audio.volume_db = action_volume_db
	dry_audio.volume_db = dry_fire_volume_db
	timing_audio.volume_db = timing_success_volume_db
	weapon.shot_fired.connect(_on_shot)
	weapon.empty_triggered.connect(_on_empty)
	weapon.reload_changed.connect(_on_reload)
	weapon.active_reload_resolved.connect(_on_active_reload)


func _play(player: AudioStreamPlayer2D, stream: AudioStream, cue: StringName) -> void:
	if stream == null:
		return
	if player.stream != stream:
		player.stream = stream
	player.play()
	cue_played.emit(cue)


func _on_shot(_from: Vector2, _to: Vector2, _hit: bool) -> void:
	_play(shot_audio, shot_stream, &"shot")


func _on_empty() -> void:
	_play(dry_audio, dry_fire_stream, &"dry_fire")


func _on_active_reload(success: bool) -> void:
	if success:
		_play(timing_audio, timing_success_stream, &"timing_success")


func _on_reload(active: bool) -> void:
	if active:
		dry_audio.stop()
		timing_audio.stop()
		_play(action_audio, reload_start_stream, &"reload_start")
	elif weapon.enabled and weapon.ammo == weapon.magazine_size:
		_play(action_audio, reload_finish_stream, &"reload_finish")
	else:
		# Cancellation/death must not sound like a successful magazine refill.
		action_audio.stop()
		dry_audio.stop()
		timing_audio.stop()
