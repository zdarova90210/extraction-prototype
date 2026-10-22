@tool
extends StaticBody2D
## Saved sprite cover with an independently editable ground footprint/material.

@export var size: Vector2 = Vector2(160, 64):
	set(value):
		size = value.max(Vector2(8, 8))
		_sync_shape()
@export var impact_cue: SoundCue = preload("res://resources/audio/combat/wood.tres")


func _ready() -> void:
	_sync_shape()


func _sync_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle


func get_impact_cue() -> SoundCue:
	return impact_cue
