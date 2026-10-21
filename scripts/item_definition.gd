class_name ItemDefinition
extends Resource
## Shared, immutable description. Inventories own individual item entries.

@export var id: StringName
@export var display_name: String = "Предмет"
@export_multiline var description: String
@export var icon: Texture2D

@export_group("Применение")
@export_range(0.0, 1000.0, 1.0) var healing_amount: float = 0.0
@export_range(0.1, 30.0, 0.1, "suffix:s") var use_duration: float = 3.0
