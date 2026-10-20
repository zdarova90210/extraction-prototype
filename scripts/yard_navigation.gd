extends NavigationRegion2D
## Bake from the saved static colliders at startup, preserving editor map edits.

@export var walkable_bounds: Rect2 = Rect2(100, 100, 1560, 920)
@export_range(1.0, 64.0, 1.0) var clearance: float = 18.0


func _ready() -> void:
	rebuild.call_deferred()


func rebuild_after_physics() -> void:
	# Collision disabling is deferred during damage. Parse after that physics update.
	await get_tree().physics_frame
	await get_tree().process_frame
	rebuild()


func rebuild() -> void:
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = clearance
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.parsed_collision_mask = 1 | 4 # World and the stationary target.
	var corner := walkable_bounds.position
	var end := walkable_bounds.end
	polygon.add_outline(PackedVector2Array([
		corner, Vector2(end.x, corner.y), end, Vector2(corner.x, end.y)
	]))
	var geometry := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(polygon, geometry, get_parent())
	NavigationServer2D.bake_from_source_geometry_data(polygon, geometry)
	navigation_polygon = polygon
