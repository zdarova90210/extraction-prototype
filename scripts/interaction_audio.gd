extends Node2D
## Player actions announce results; audio never spends items or restores health.

@export var heal_start_cue: SoundCue
@export var heal_process_cue: SoundCue
@export var heal_finish_cue: SoundCue
@export var drop_cue: SoundCue
@export var pickup_cue: SoundCue
@export_range(0.03, 0.4, 0.01, "suffix:s") var heal_phase_crossfade: float = 0.14
@export_range(0.05, 0.5, 0.01, "suffix:s") var heal_finish_crossfade: float = 0.24
var _heal_process_started: bool = false
@onready var _use: Node = get_node("../ItemUse")


func _ready() -> void:
	_use.started.connect(_on_heal_started)
	_use.completed.connect(_on_heal_completed)
	_use.cancelled.connect(_on_heal_cancelled)
	get_node("../LootInteraction").item_dropped.connect(_on_dropped)
	get_node("../LootInteraction").item_picked_up.connect(_on_picked_up)
	get_parent().died.connect(_on_heal_cancelled)


func _on_heal_started() -> void:
	_heal_process_started = false
	$HealProcess.stop()
	$HealAction.crossfade(heal_start_cue, 0.04)


func _on_heal_completed(_restored: float) -> void:
	_heal_process_started = false
	# Completion is confirmed before its cue; only the physical tail crosses the boundary.
	$HealProcess.stop(heal_finish_crossfade)
	$HealAction.crossfade(heal_finish_cue, heal_finish_crossfade)


func _on_heal_cancelled() -> void:
	_heal_process_started = false
	$HealAction.stop()
	$HealProcess.stop()


func _process(_delta: float) -> void:
	if not _use.is_using:
		return
	if not _heal_process_started:
		if $HealAction.remaining_time() <= heal_phase_crossfade:
			$HealAction.stop(heal_phase_crossfade)
			$HealProcess.crossfade(heal_process_cue, heal_phase_crossfade)
			_heal_process_started = true
	elif $HealProcess.remaining_time() <= heal_phase_crossfade:
		$HealProcess.crossfade(heal_process_cue, heal_phase_crossfade)


func _on_dropped(point: Vector2) -> void:
	$Drop.global_position = point
	$Drop.play(drop_cue)


func _on_picked_up(point: Vector2) -> void:
	$Pickup.global_position = point
	$Pickup.play(pickup_cue)
