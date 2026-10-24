extends "res://scripts/pause_menu.gd"
## Reuse the real pause/settings owner; this lab has no raid developer tools.

func _ready() -> void:
	super._ready()
	var content := $Center/Panel/Margin/Content
	content.get_node("Developer").hide()
	content.get_node("Bindings").hide()
	content.get_node("Note").text = "WASD — движение · мышь — поворот на 360°\nЛКМ — огонь без подготовки · R — перезарядка\nC — ходьба / подкрадывание · F2 — сброс."

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("developer_tools"):
		return
	super._input(event)
