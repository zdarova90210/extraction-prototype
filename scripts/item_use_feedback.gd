extends Node2D
## Local, non-rotating feedback; never applies an item or changes health.

@export var bar_width: float = 64.0
@export var message_duration: float = 1.1
var _message: String = ""
var _message_remaining: float = 0.0
@onready var _use: Node = get_node("../ItemUse")
@onready var _label: Label = $Readout


func _ready() -> void:
	_use.notice.connect(_show_message)
	hide()


func _show_message(text: String) -> void:
	_message = text
	_message_remaining = message_duration if not text.is_empty() else 0.0


func _process(delta: float) -> void:
	_message_remaining = maxf(0.0, _message_remaining - delta)
	visible = _use.is_using or _message_remaining > 0.0
	if not visible:
		return
	_label.text = "Лечение · %.1f с" % _use.remaining if _use.is_using else _message
	modulate.a = 1.0 if _use.is_using else minf(1.0, _message_remaining / 0.2)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_use) or not _use.is_using:
		return
	var rect := Rect2(-bar_width * 0.5, 0, bar_width, 4)
	draw_rect(rect.grow(1), Color(0.025, 0.04, 0.04, 0.9))
	draw_rect(rect, Color(0.2, 0.3, 0.28, 0.9))
	rect.size.x *= _use.progress
	draw_rect(rect, Color(0.64, 0.88, 0.73))
