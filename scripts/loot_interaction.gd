extends Node
## Shared gaze selection for containers and floor loot, plus safe world drops.

signal interacted(container: StaticBody2D)
signal item_dropped(point: Vector2)
signal item_picked_up(point: Vector2)
const GROUND_ITEM = preload("res://scenes/ground_item.tscn")

@export_range(48.0, 160.0, 4.0, "suffix:px") var reach: float = 96.0
@export_range(30.0, 180.0, 5.0, "suffix:deg") var facing_angle: float = 120.0
var _highlighted: Node2D
@onready var player: CharacterBody2D = get_parent()
@onready var aim: Node2D = player.get_node("Aim")


func can_reach(container: Node2D) -> bool:
	if not is_instance_valid(container) or player.is_dead or player.global_position.distance_to(container.global_position) > reach:
		return false
	var excluded: Array[RID] = []
	if container is CollisionObject2D:
		excluded.append(container.get_rid())
	var query := PhysicsRayQueryParameters2D.create(player.global_position, container.global_position, 1 | 4, excluded)
	query.hit_from_inside = true
	return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func can_interact(container: Node2D) -> bool:
	if not can_reach(container):
		return false
	if container is GroundItem and container.inventory.item_count == 0:
		return false
	return _alignment(container) >= cos(deg_to_rad(facing_angle * 0.5))


func _alignment(container: Node2D) -> float:
	# Both ends of gaze live in rendered coordinates. The object's root remains
	# its ground origin, which may lie below the player aim even when art is above.
	var target: Vector2 = container.get_interaction_position()
	var offset := target - aim.global_position
	if offset.length_squared() < 1.0:
		return 1.0 # No meaningful facing angle when the two visual points coincide.
	return Vector2.RIGHT.rotated(aim.global_rotation).dot(offset.normalized())


func _nearest() -> Node2D:
	var nearest: Node2D
	var distance := reach + 1.0
	var best_alignment := -2.0
	for candidate in get_tree().get_nodes_in_group("loot_interactables"):
		var candidate_distance: float = player.global_position.distance_to(candidate.global_position)
		var alignment := _alignment(candidate)
		if can_interact(candidate) and (alignment > best_alignment + 0.001 or (absf(alignment - best_alignment) <= 0.001 and candidate_distance < distance)):
			nearest = candidate
			distance = candidate_distance
			best_alignment = alignment
	return nearest


func drop_item(slot: int) -> bool:
	var backpack: Inventory = player.get_node("Inventory")
	if player.is_dead or backpack.get_item(slot) == null:
		return false
	var spot: Variant = _find_drop_position()
	if spot == null:
		return false
	var ground := GROUND_ITEM.instantiate() as GroundItem
	get_tree().current_scene.add_child(ground)
	ground.global_position = spot
	if not backpack.transfer_to(ground.inventory, slot):
		ground.free()
		return false
	item_dropped.emit(ground.global_position)
	return true


func _find_drop_position() -> Variant:
	var space := player.get_world_2d().direct_space_state
	var forward: float = aim.global_rotation
	var clearance := CircleShape2D.new()
	clearance.radius = 14.0
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = clearance
	shape_query.collision_mask = 1 | 4 | 8
	for ring in range(3):
		var radius := 36.0 + ring * 28.0
		var samples := floori(TAU * radius / 28.0)
		for index in range(samples):
			var point := player.global_position + Vector2.from_angle(forward + TAU * index / samples) * radius
			var occupied := false
			for other in get_tree().get_nodes_in_group("ground_items"):
				if point.distance_to(other.global_position) < 28.0:
					occupied = true
					break
			if occupied:
				continue
			shape_query.transform = Transform2D(0, point)
			if not space.intersect_shape(shape_query, 1).is_empty():
				continue
			var ray := PhysicsRayQueryParameters2D.create(player.global_position, point, 1 | 4)
			ray.hit_from_inside = true
			if space.intersect_ray(ray).is_empty():
				return point
	return null


func _physics_process(_delta: float) -> void:
	var nearest := _nearest() if player.input_enabled and not player.is_dead else null
	if nearest == _highlighted:
		return
	if is_instance_valid(_highlighted):
		_highlighted.set_highlighted(false)
	_highlighted = nearest
	if is_instance_valid(_highlighted):
		_highlighted.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and player.input_enabled and not player.is_dead:
		var container := _nearest()
		if is_instance_valid(container):
			get_viewport().set_input_as_handled()
			if container is GroundItem:
				var point := container.global_position
				if container.pick_up(player.get_node("Inventory")):
					item_picked_up.emit(point)
			else:
				interacted.emit(container)
