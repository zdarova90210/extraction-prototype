@tool
extends Node2D
## Authored projected elbows. Depth foreshortening
## changes each segment's visible length; the shoulder stays on the torso.

## Width in this view's projection: upper sleeve / forearm. Length is fitted
## separately, so a foreshortened rear sleeve need not become a wide wedge.
@export var segment_widths := Vector2.ONE

var _rest: Dictionary = {}
var _wrists: Dictionary = {}

func _ready() -> void:
	for name in ["SupportArm", "TriggerArm"]:
		var arm: Node2D = get_parent().get_node(name)
		var forearm: Node2D = arm.get_node("Forearm")
		_rest[arm] = [forearm.position, forearm.get_node("Wrist").position]
		var rig: Node2D = get_parent().get_parent()
		var grip: Node2D = get_parent().get_node("Grip")
		var wrist: Marker2D = grip.get_node("SupportWrist" if name == "SupportArm" else "TriggerWrist")
		_wrists[arm] = grip.position + wrist.position.rotated(deg_to_rad(rig.bearing_degrees) - rig.drawn_weapon_angle)

func pose(arm: Node2D, wrist: Marker2D) -> void:
	var prefix := "Support" if arm.name == "SupportArm" else "Trigger"
	var reference: Marker2D = get_node(prefix)
	var goal: Vector2 = get_parent().to_local(wrist.global_position)
	# The elbow accompanies the hand inside a view's sector. Keeping it fixed
	# makes a rotating gun appear disconnected even when wrist markers coincide.
	var elbow: Vector2 = reference.position + (goal - _wrists[arm]) * 0.45
	var upper_span := elbow - arm.position
	var lower_span := goal - elbow
	var rest_upper: Vector2 = _rest[arm][0]
	var rest_lower: Vector2 = _rest[arm][1]
	var upper_scale := upper_span.length() / rest_upper.length()
	var lower_scale := lower_span.length() / rest_lower.length()
	arm.scale = Vector2.ONE
	arm.rotation = rest_upper.angle_to(upper_span)
	arm.get_node("Image").transform = _project_segment(rest_upper, upper_scale, segment_widths.x)
	var forearm: Node2D = arm.get_node("Forearm")
	forearm.position = rest_upper * upper_scale
	forearm.rotation = rest_lower.angle_to(lower_span) - arm.rotation
	# A rear Image can contain a distal polygon on a lower drawing layer.
	# Both parts inherit this projection, preserving a continuous elbow bend.
	forearm.get_node("Image").transform = _project_segment(rest_lower, lower_scale, segment_widths.y)
	forearm.get_node("Wrist").position = rest_lower * lower_scale

func _project_segment(rest: Vector2, ratio: float, width: float) -> Transform2D:
	var axis := rest.normalized()
	var basis := Transform2D(axis, axis.orthogonal(), Vector2.ZERO)
	var stretch := Transform2D(Vector2(ratio, 0), Vector2(0, width), Vector2.ZERO)
	return basis * stretch * basis.affine_inverse()
