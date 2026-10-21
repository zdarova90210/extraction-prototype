extends Node2D
## Optional presentation component: gameplay emits events, audio only listens.

signal cue_played(cue: StringName)

@export var shot_cue: SoundCue
@export var audio_bus: StringName = &"EnemyWeapons"
@export var dry_fire_cue: SoundCue
@export var reload_start_cue: SoundCue
@export var reload_finish_cue: SoundCue
@export var timing_success_cue: SoundCue

@onready var weapon: Node2D = get_parent()
@onready var shot_audio: AudioStreamPlayer2D = $Shot
@onready var action_audio: AudioStreamPlayer2D = $Action
@onready var dry_audio: AudioStreamPlayer2D = $DryFire
@onready var timing_audio: AudioStreamPlayer2D = $TimingSuccess


func _ready() -> void:
	for player: AudioStreamPlayer2D in [shot_audio, action_audio, dry_audio, timing_audio]:
		player.bus = audio_bus
	_configure(shot_audio, shot_cue)
	_configure(dry_audio, dry_fire_cue)
	_configure(timing_audio, timing_success_cue)
	weapon.hit_registered.connect($Impacts.play_hit)
	weapon.shot_fired.connect(_on_shot)
	weapon.empty_triggered.connect(_on_empty)
	weapon.reload_changed.connect(_on_reload)
	weapon.active_reload_resolved.connect(_on_active_reload)


func _configure(player: AudioStreamPlayer2D, cue: SoundCue) -> void:
	player.stream = null
	if cue == null:
		return
	# Each actor owns its selection state. Keeping the shot stream stable lets
	# native polyphony preserve previous tails when a different variant fires.
	var variants := AudioStreamRandomizer.new()
	variants.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variants.random_pitch = 1.0 + cue.pitch_variation
	for index in range(cue.clips.size()):
		var clip := cue.clips[index]
		if clip != null:
			variants.add_stream(-1, clip, cue.weight_at(index))
	if variants.streams_count > 0:
		player.stream = variants
		player.volume_db = cue.volume_db


func _play(player: AudioStreamPlayer2D, cue: StringName) -> void:
	if player.stream == null:
		return
	player.play()
	cue_played.emit(cue)


func _on_shot(_from: Vector2, _to: Vector2, _hit: bool) -> void:
	_play(shot_audio, &"shot")


func _on_empty() -> void:
	_play(dry_audio, &"dry_fire")


func _on_active_reload(success: bool) -> void:
	if success:
		_play(timing_audio, &"timing_success")


func _on_reload(active: bool) -> void:
	if active:
		dry_audio.stop()
		timing_audio.stop()
		_configure(action_audio, reload_start_cue)
		_play(action_audio, &"reload_start")
	elif weapon.enabled and weapon.ammo == weapon.magazine_size:
		_configure(action_audio, reload_finish_cue)
		_play(action_audio, &"reload_finish")
	else:
		# Cancellation/death must not sound like a successful magazine refill.
		action_audio.stop()
		dry_audio.stop()
		timing_audio.stop()
