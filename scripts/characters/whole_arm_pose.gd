@tool
extends Node2D
## Three authored anchors project one uncut painted arm. There is no elbow seam.

@export var grip_target: Marker2D
@export var source_elbow := Vector2(0,12)
@export var source_wrist := Vector2(12,0)
@export var elbow_offset := Vector2(0,11)
@export var source_shoulder_uv := Vector2.ZERO
@export_range(0.5, 1.2, 0.05) var sleeve_width := 0.75

var _neutral_wrist := Vector2.ZERO
var _points := PackedVector2Array()

func _ready() -> void:
	var rig: Node2D = get_parent().get_parent()
	var grip: Node2D = grip_target.get_parent()
	_neutral_wrist = grip.position + grip_target.position.rotated(deg_to_rad(rig.bearing_degrees) - rig.drawn_weapon_angle) - position
	_points = $Image.uv
	for index in _points.size():
		_points[index] -= source_shoulder_uv

func fit_to_grip(wrist: Marker2D) -> void:
	var hand: Vector2 = get_parent().to_local(wrist.global_position) - position
	var elbow: Vector2 = elbow_offset + (hand - _neutral_wrist) * 0.45
	var points := PackedVector2Array()
	var bend_axis := source_wrist.normalized()
	for point in _points:
		var upper := _project(point, Vector2.ZERO, source_elbow, Vector2.ZERO, elbow)
		var lower := _project(point, source_elbow, source_wrist, elbow, hand)
		var weight := smoothstep(-1.5, 1.5, (point - source_elbow).dot(bend_axis))
		points.append(upper.lerp(lower, weight))
	$Image.polygon = points
	$Elbow.position = elbow
	$Wrist.position = hand

func _project(point: Vector2, source_start: Vector2, source_end: Vector2, target_start: Vector2, target_end: Vector2) -> Vector2:
	var original := source_end - source_start
	var projected := target_end - target_start
	var axis := original.normalized()
	var toward := projected.normalized()
	var offset := point - source_start
	return target_start + toward * offset.dot(axis) * projected.length() / original.length() + toward.orthogonal() * offset.dot(axis.orthogonal()) * sleeve_width
