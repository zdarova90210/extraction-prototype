extends Node
## Feedback only. Zone events own countdown and completion; no AI noise events.

@export var pulse_cue: SoundCue
@export var cancel_cue: SoundCue
@export_range(0.5, 2.0, 0.05, "suffix:s") var initial_interval: float = 1.0
@export_range(0.25, 0.8, 0.05, "suffix:s") var final_interval: float = 0.4
var _active: bool = false
var _remaining: float = 0.0
var _progress: float = 0.0
@onready var _zone: Area2D = get_parent()


func _ready() -> void:
	_zone.countdown_started.connect(_on_started)
	_zone.countdown_stopped.connect(_on_stopped)
	_zone.countdown_cancelled.connect(_on_cancelled)
	_zone.countdown_progress.connect(func(value: float): _progress = value)


func _on_started() -> void:
	_active = true
	_progress = 0.0
	$Cancel.stop()
	_pulse()


func _on_stopped() -> void:
	_active = false
	_remaining = 0.0
	$Pulse.stop(0.08)


func _on_cancelled() -> void:
	$Cancel.crossfade(cancel_cue, 0.025)


func _pulse() -> void:
	$Pulse.play(pulse_cue)
	_remaining = lerpf(initial_interval, final_interval, _progress)


func _process(delta: float) -> void:
	if not _active:
		return
	var time_left: float = _zone.duration - _zone.elapsed
	# Leave a soft tail before the scene transition, rather than cutting a fresh pulse.
	if time_left <= 0.12:
		$Pulse.stop(0.10)
		return
	_remaining -= delta
	if _remaining <= 0.0 and time_left > 0.25:
		_pulse()
