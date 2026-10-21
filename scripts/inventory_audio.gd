extends Node
## One cue after a successful GUI transaction, never on mouse down or drag start.

@export var move_cue: SoundCue


func _ready() -> void:
	get_parent().item_moved.connect(_on_item_moved)


func _on_item_moved() -> void:
	$Move.play(move_cue)
