@tool
extends Control
## Reusable backdrop only. Two panel-sized passes; foreground controls stay crisp.

@export_range(0.0, 40.0, 1.0) var blur_radius: float = 24.0:
	set(value):
		blur_radius = value
		_sync_materials()
@export_range(0.0, 24.0, 1.0) var corner_radius: float = 8.0:
	set(value):
		corner_radius = value
		_sync_materials()
@export_range(0.0, 1.0, 0.01) var darkening: float = 0.48:
	set(value):
		darkening = value
		_sync_materials()
@export_range(0.0, 1.0, 0.01) var saturation: float = 0.32:
	set(value):
		saturation = value
		_sync_materials()


func _ready() -> void:
	resized.connect(_sync_materials)
	_sync_materials()


func _sync_materials() -> void:
	if not is_node_ready():
		return
	for node in [$HorizontalBlur, $Glass]:
		var shader_material := node.material as ShaderMaterial
		shader_material.set_shader_parameter("panel_size", size.max(Vector2.ONE))
		shader_material.set_shader_parameter("blur_radius", blur_radius)
		shader_material.set_shader_parameter("corner_radius", corner_radius)
		shader_material.set_shader_parameter("darkening", darkening)
		shader_material.set_shader_parameter("saturation", saturation)
