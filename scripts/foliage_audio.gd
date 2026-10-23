extends Node2D
## Movement-only plant contact foley; no collision, slowdown or AI noise event.

signal brush_played(surface: FootstepSurface, cue: SoundCue)

@export_range(20.0, 160.0, 1.0, "suffix:px") var repeat_distance: float = 60.0
@export_range(0.2, 2.0, 0.05, "suffix:s") var minimum_interval: float = 0.65
var _last_patch: FootstepSurface
var _travel: float = 0.0
var _cooldown: float = 0.0
@onready var _actor: CharacterBody2D = get_parent()
@onready var _player: Node2D = $Player


func _ready() -> void:
	_actor.moved.connect(_on_moved)
	_actor.died.connect(stop)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func _on_moved(distance: float) -> void:
	if _actor.is_dead or distance <= 0.0:
		return
	if distance > 160.0:
		_last_patch = null
		_travel = 0.0
		return
	var selected: FootstepSurface
	for node in get_tree().get_nodes_in_group(&"footstep_surfaces"):
		var patch := node as FootstepSurface
		if patch == null or patch.brush_cue == null or patch.get_world_2d() != get_world_2d():
			continue
		if patch.contains_point(global_position) and (selected == null or patch.priority > selected.priority):
			selected = patch
	if selected == null:
		_last_patch = null
		_travel = 0.0
		return
	_travel += distance
	if _cooldown > 0.0 or (selected == _last_patch and _travel < repeat_distance):
		return
	if _player.play(selected.brush_cue):
		_last_patch = selected
		_travel = 0.0
		_cooldown = minimum_interval
		brush_played.emit(selected, selected.brush_cue)


func stop() -> void:
	_player.stop(0.0)
	_last_patch = null
	_travel = 0.0
	_cooldown = 0.0
