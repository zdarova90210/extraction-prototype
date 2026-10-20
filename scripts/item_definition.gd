class_name ItemDefinition
extends Resource
## Shared, immutable description. Inventories own individual item entries.

@export var id: StringName
@export var display_name: String = "Предмет"
@export_multiline var description: String
@export var icon: Texture2D
