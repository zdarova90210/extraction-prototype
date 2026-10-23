extends Node2D
## Authored projected elbow positions for a rear view. Depth foreshortening
## changes each segment's visible length; the shoulder stays on the torso.

var _rest: Dictionary = {}

func _ready() -> void:
	for name in ["SupportArm", "TriggerArm"]:
		var arm: Node2D = get_parent().get_node(name)
		var forearm: Node2D = arm.get_node("Forearm")
		_rest[arm] = [forearm.position, forearm.get_node("Wrist").position]

func pose(arm: Node2D, wrist: Marker2D, blend: float) -> void:
	var prefix := "Support" if arm.name == "SupportArm" else "Trigger"
	var lower: Marker2D = get_node(prefix + "Lowered")
	var raised: Marker2D = get_node(prefix + "Raised")
	var elbow := lower.position.lerp(raised.position, blend)
	var goal: Vector2 = get_parent().to_local(wrist.global_position)
	var upper_span := elbow - arm.position
	var lower_span := goal - elbow
	var rest_upper: Vector2 = _rest[arm][0]
	var rest_lower: Vector2 = _rest[arm][1]
	var upper_scale := upper_span.length() / rest_upper.length()
	var lower_scale := lower_span.length() / rest_lower.length()
	arm.scale = Vector2.ONE
	arm.rotation = rest_upper.angle_to(upper_span)
	arm.get_node("Image").transform = _project_segment(rest_upper, upper_scale)
	var forearm: Node2D = arm.get_node("Forearm")
	forearm.position = rest_upper * upper_scale
	forearm.rotation = rest_lower.angle_to(lower_span) - arm.rotation
	forearm.get_node("Image").transform = _project_segment(rest_lower, lower_scale)
	forearm.get_node("Wrist").position = rest_lower * lower_scale

func _project_segment(rest: Vector2, ratio: float) -> Transform2D:
	var axis := rest.normalized()
	var basis := Transform2D(axis, axis.orthogonal(), Vector2.ZERO)
	var stretch := Transform2D(Vector2(ratio, 0), Vector2(0, 1), Vector2.ZERO)
	return basis * stretch * basis.affine_inverse()
