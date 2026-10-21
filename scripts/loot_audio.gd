extends Node
## Container Foley follows the source, including discovery and interrupted search.

@export var open_cue: SoundCue
@export var close_cue: SoundCue
@export var search_cue: SoundCue
@export var reveal_cue: SoundCue
var _gap: float = 0.0
@onready var _source: StaticBody2D = get_parent()


func _ready() -> void:
	_source.opened.connect(_on_opened)
	_source.closed.connect(_on_closed)
	_source.item_discovered.connect(_on_discovered)


func _on_opened() -> void:
	$Action.stop(0.0)
	$Action.play(open_cue)
	_gap = 0.18


func _on_closed() -> void:
	$Search.stop()
	$Reveal.stop()
	$Action.stop(0.0)
	$Action.play(close_cue)


func _on_discovered(_slot: int) -> void:
	# Long rummaging recordings continue underneath individual discoveries.
	# Only exhausting unknown items (or closing the source) ends the search.
	if not _source.is_searching:
		$Search.stop()
	$Reveal.play(reveal_cue)
	_gap = 0.18


func _process(delta: float) -> void:
	if not _source.is_searching:
		$Search.stop()
		return
	if $Search.is_playing():
		return
	_gap = maxf(0.0, _gap - delta)
	if _gap <= 0.0:
		$Search.play(search_cue)
		_gap = randf_range(0.08, 0.18)
