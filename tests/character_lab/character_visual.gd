extends Node2D
## Eight saved views, one animator. Movement, raycasts and ammo live elsewhere.

signal foot_contact

@export var walk_gait: CharacterLabGait
@export var sneak_gait: CharacterLabGait
@export_range(0.1, 0.8, 0.01) var raise_duration: float = 0.24
@export_range(0.1, 0.6, 0.01) var gait_change_duration: float = 0.2
@export_range(0.0, 8.0, 0.5) var direction_hysteresis_degrees := 3.0

var aim_requested := false
var aim_angle := 0.0
var aim_blend := 0.0
var walking := false
var gait_blend := 0.0
var sneaking := false
var sneak_blend := 0.0
var phase := 0.0
var recoil := 0.0
var flash_remaining := 0.0
var direction_index := 0
var direction_override := -1
var motion_vector := Vector2.ZERO
var _motion_direction := 1.0

var rig: Node2D
var upper: Node2D
var grip: Node2D
var near_leg: Node2D
var far_leg: Node2D
var near_shin: Node2D
var far_shin: Node2D
var near_foot: Node2D
var far_foot: Node2D
var trigger_arm: Node2D
var support_arm: Node2D
var muzzle: Marker2D
var flash: Polygon2D
@onready var model: Node2D = $Pixels/Model

func _ready() -> void:
	_bind_rig($Pixels/Model/East)
	apply_pose()

func _bind_rig(next_rig: Node2D) -> void:
	if is_instance_valid(rig):
		rig.hide()
		flash.hide()
	rig = next_rig
	rig.show()
	upper = rig.get_node("Upper")
	grip = upper.get_node("Grip")
	near_leg = rig.get_node("NearLeg")
	far_leg = rig.get_node("FarLeg")
	near_shin = near_leg.get_node("Shin")
	far_shin = far_leg.get_node("Shin")
	near_foot = near_shin.get_node("Foot")
	far_foot = far_shin.get_node("Foot")
	trigger_arm = upper.get_node("TriggerArm")
	support_arm = upper.get_node("SupportArm")
	muzzle = grip.get_node("Muzzle")
	flash = muzzle.get_node("Flash")

func _select_rig() -> void:
	var nearest := posmod(roundi(aim_angle / (PI / 4.0)), 8)
	if direction_override >= 0:
		nearest = direction_override
	elif absf(angle_difference(direction_index * PI / 4.0, aim_angle)) <= PI / 8.0 + deg_to_rad(direction_hysteresis_degrees):
		nearest = direction_index
	direction_index = nearest
	var names := ["East", "SouthEast", "South", "SouthEast", "East", "NorthEast", "North", "NorthEast"]
	var next_rig: Node2D = model.get_node(names[direction_index])
	if rig != next_rig:
		_bind_rig(next_rig)
	rig.scale.x = -1.0 if direction_index in [3, 4, 5] else 1.0

func set_motion(distance: float, forward_velocity: float) -> void:
	var stride_distance := lerpf(walk_gait.stride_distance, sneak_gait.stride_distance, sneak_blend)
	var moving := distance > 0.01 and distance < stride_distance * 2.0
	walking = moving
	if walking:
		if absf(forward_velocity) > 1.0:
			_motion_direction = signf(forward_velocity)
		var previous_cycle := phase / TAU
		var next_cycle := previous_cycle + distance * _motion_direction / stride_distance
		phase = fposmod(next_cycle, 1.0) * TAU
		apply_pose()
		# In reverse, landing occurs at the other end of the planted interval.
		# Keep phase through stops and gait changes; sound follows these contacts,
		# rather than a second distance counter with a different reset policy.
		var landing := 0.0 if _motion_direction > 0.0 else lerpf(walk_gait.stance_fraction, sneak_gait.stance_fraction, sneak_blend)
		for offset in [0.0, 0.5]:
			if floori(next_cycle + offset - landing) != floori(previous_cycle + offset - landing):
				foot_contact.emit()

func notify_shot(_from: Vector2, _to: Vector2, _hit: bool) -> void:
	recoil = 1.0
	flash_remaining = 0.055
	apply_pose()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	aim_blend = move_toward(aim_blend, 1.0 if aim_requested else 0.0, delta / raise_duration)
	recoil = move_toward(recoil, 0.0, delta / 0.12)
	flash_remaining = maxf(0.0, flash_remaining - delta)
	gait_blend = move_toward(gait_blend, 1.0 if walking else 0.0, delta * 8.0)
	sneak_blend = move_toward(sneak_blend, 1.0 if sneaking else 0.0, delta / gait_change_duration)
	apply_pose()

func reset_pose() -> void:
	walking = false
	gait_blend = 0.0
	sneak_blend = 1.0 if sneaking else 0.0
	phase = 0.0
	motion_vector = Vector2.ZERO
	_motion_direction = 1.0
	aim_requested = false
	aim_angle = direction_override * PI / 4.0 if direction_override >= 0 else 0.0
	aim_blend = 0.0
	recoil = 0.0
	flash_remaining = 0.0
	apply_pose()

func apply_pose() -> void:
	_select_rig()
	# Follow a foot path, then solve thigh + shin. A planted leg and a lifted,
	# bent return leg must not behave like two straight, opposite pendulums.
	var lowering := lerpf(walk_gait.pelvis_lowering, sneak_gait.pelvis_lowering, sneak_blend)
	var bob := lerpf(walk_gait.vertical_bob, sneak_gait.vertical_bob, sneak_blend)
	var pelvis_drop := gait_blend * (lowering + cos(phase * 2.0) * bob)
	var tracks := walk_gait.foot_tracks.lerp(sneak_gait.foot_tracks, sneak_blend)
	if not rig.use_profile_tracks:
		tracks = rig.foot_tracks
	_pose_leg(near_leg, near_shin, near_foot, rig.near_hip, tracks.x, phase, pelvis_drop, rig.knee_sides.x, rig.near_segments)
	_pose_leg(far_leg, far_shin, far_foot, rig.far_hip, tracks.y, phase + PI, pelvis_drop, rig.knee_sides.y, rig.far_segments)
	upper.position.y = pelvis_drop
	var eased := smoothstep(0.0, 1.0, aim_blend)
	var local_direction := Vector2.from_angle(aim_angle)
	local_direction.x *= rig.scale.x
	var relative_angle := angle_difference(deg_to_rad(rig.bearing_degrees), local_direction.angle())
	var raised_angle: float = deg_to_rad(rig.bearing_degrees) - rig.drawn_weapon_angle + relative_angle
	grip.rotation = raised_angle + deg_to_rad(rig.lowered_angle_degrees) * (1.0 - eased) - recoil * 0.025
	grip.position = rig.grip_origin + rig.lowered_shift * (1.0 - eased) - local_direction * recoil * 1.4
	_fit_arm(trigger_arm, grip.get_node("TriggerWrist"))
	_fit_arm(support_arm, grip.get_node("SupportWrist"))
	flash.visible = flash_remaining > 0.0

func _pose_leg(thigh: Node2D, shin: Node2D, foot: Node2D, hip: Vector2, track_x: float, leg_phase: float, pelvis_drop: float, knee_side: float, segments: PackedVector2Array) -> void:
	var rest_upper := segments[0]
	var rest_lower := segments[1]
	var thigh_image: Polygon2D = thigh.get_node("Thigh")
	var shin_image: Polygon2D = shin.get_node("Image")
	thigh.position = hip + Vector2(0, pelvis_drop)
	if gait_blend <= 0.0001:
		shin.position = rest_upper
		foot.position = rest_lower
		thigh_image.transform = Transform2D.IDENTITY
		shin_image.transform = Transform2D.IDENTITY
		thigh.rotation = 0.0
		shin.rotation = 0.0
		foot.rotation = 0.0
		return
	var cycle := fposmod(leg_phase / TAU, 1.0)
	var step_reach := lerpf(walk_gait.step_reach, sneak_gait.step_reach, sneak_blend)
	var step_lift := lerpf(walk_gait.step_lift, sneak_gait.step_lift, sneak_blend)
	var stance_fraction := lerpf(walk_gait.stance_fraction, sneak_gait.stance_fraction, sneak_blend)
	var foot_x: float
	var lift := 0.0
	var roll: float
	if cycle < stance_fraction:
		var contact := cycle / stance_fraction
		foot_x = lerpf(step_reach, -step_reach, contact)
		roll = -0.12 * (1.0 - smoothstep(0.0, 0.18, contact)) + 0.20 * smoothstep(0.78, 1.0, contact)
	else:
		var returning := (cycle - stance_fraction) / (1.0 - stance_fraction)
		foot_x = lerpf(-step_reach, step_reach, smoothstep(0.0, 1.0, returning))
		lift = sin(returning * PI) * step_lift
		roll = lerpf(0.20, -0.12, smoothstep(0.0, 1.0, returning)) - sin(returning * PI) * 0.16
	var bearing := deg_to_rad(rig.bearing_degrees)
	var side_view := absf(cos(bearing))
	# Heel-to-toe roll is seen in profile. Front/back feet must not tilt sideways.
	roll *= side_view
	# Roll on heel/toe without driving the sole through the ground. During the
	# return stroke the same sole is lifted; the knee bends to make that space.
	var heel: Vector2 = foot.get_node("Heel").position
	var toe: Vector2 = foot.get_node("Toe").position
	var sole_y := maxf(heel.rotated(roll).y, toe.rotated(roll).y)
	var rest_ankle := hip + rest_upper + rest_lower
	var step_axis: Vector2 = rig.stride_axis
	if not motion_vector.is_zero_approx():
		step_axis = Vector2(motion_vector.x * rig.scale.x, motion_vector.y * 0.45) * _motion_direction
	# Short lateral steps in a front/back view keep each foot in its own lane.
	step_axis.x *= lerpf(0.55, 1.0, side_view)
	var ankle := rest_ankle.lerp(Vector2(track_x, -sole_y - lift) + step_axis * foot_x, gait_blend)
	var upper_length := rest_upper.length()
	var lower_length := rest_lower.length()
	var reach := ankle - thigh.position
	var distance := clampf(reach.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var direction := reach.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	# A softly bent knee avoids the square-root snap at a fully locked joint.
	var soft_bend := 1.5 * gait_blend
	var bend := sqrt(maxf(0.0, upper_length * upper_length - along * along) + soft_bend * soft_bend)
	# Project the sagittal bend instead of forcing a full sideways IK bend into
	# every view. Depth flexion changes visible segment lengths, not their width.
	var knee := direction * along + Vector2(direction.y, -direction.x) * bend * knee_side * side_view
	knee.y += sin(bearing) * bend * (1.0 - side_view) * 0.25
	knee = rest_upper.lerp(knee, gait_blend)
	var lower_span := direction * distance - knee
	var upper_ratio := knee.length() / upper_length
	var lower_ratio := lower_span.length() / lower_length
	thigh.rotation = rest_upper.angle_to(knee)
	shin.position = rest_upper * upper_ratio
	shin.rotation = rest_lower.angle_to(lower_span) - thigh.rotation
	foot.position = rest_lower * lower_ratio
	thigh_image.transform = _project_leg_segment(rest_upper, upper_ratio)
	shin_image.transform = _project_leg_segment(rest_lower, lower_ratio)
	foot.rotation = roll * gait_blend - thigh.rotation - shin.rotation

func _project_leg_segment(rest: Vector2, ratio: float) -> Transform2D:
	var axis := rest.normalized()
	var basis := Transform2D(axis, axis.orthogonal(), Vector2.ZERO)
	return basis * Transform2D(Vector2(ratio, 0), Vector2(0, 1), Vector2.ZERO) * basis.affine_inverse()

func _fit_arm(arm: Node2D, wrist: Marker2D) -> void:
	var guides: Node2D = upper.get_node_or_null("ElbowGuides")
	if guides != null:
		guides.pose(arm, wrist, smoothstep(0.0, 1.0, aim_blend))
		return
	var span := upper.to_local(wrist.global_position) - arm.position
	if arm.has_node("Forearm"):
		var forearm: Node2D = arm.get_node("Forearm")
		var hand: Marker2D = forearm.get_node("Wrist")
		var upper_length := forearm.position.length()
		var lower_length := hand.position.length()
		var scale_factor := maxf(rig.arm_size, span.length() / (upper_length + lower_length - 0.01))
		arm.scale = Vector2.ONE * scale_factor
		span /= scale_factor
		var distance := clampf(span.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
		var direction := span.normalized()
		var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
		var bend := sqrt(maxf(0.0, upper_length * upper_length - along * along))
		var elbow_side: float = rig.arm_elbow_sides.x if arm == support_arm else rig.arm_elbow_sides.y
		var elbow := direction * along + Vector2(direction.y, -direction.x) * bend * elbow_side
		arm.rotation = forearm.position.angle_to(elbow)
		forearm.rotation = hand.position.angle_to(direction * distance - elbow) - arm.rotation
		return
	var original_span: Vector2 = arm.get_node("Wrist").position
	arm.rotation = span.angle() - original_span.angle()
	# Uniform scaling keeps the painted elbow shape; this is a limited pose study.
	arm.scale = Vector2.ONE * clampf(span.length() / original_span.length(), rig.arm_scale_limits.x, rig.arm_scale_limits.y)

func wrist_for(arm: Node2D) -> Marker2D:
	return arm.get_node("Forearm/Wrist") if arm.has_node("Forearm") else arm.get_node("Wrist")

func muzzle_offset() -> Vector2:
	# Model uses a fixed ground pivot; exclude the SubViewport from world coordinates.
	return model.to_local(muzzle.global_position)
