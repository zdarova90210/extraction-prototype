extends Control
## Shared settings content; its caller owns pause and navigation.

signal back_requested

@onready var audio_options: VBoxContainer = $Center/Panel/Margin/Content/Tabs/AudioOptions


func _ready() -> void:
	var tabs: TabContainer = $Center/Panel/Margin/Content/Tabs
	tabs.set_tab_title(0, "Звук")
	tabs.set_tab_title(1, "Экран")
	tabs.tab_changed.connect(func(_tab: int): audio_options.stop_preview())
	$Center/Panel/Margin/Content/Back.pressed.connect(func(): back_requested.emit())


func open() -> void:
	show()
	$Center/Panel/Margin/Content/Tabs.current_tab = 0
	audio_options.focus_first()


func close() -> void:
	audio_options.stop_preview()
	get_node("/root/AudioSettings").save_preferences()
	hide()
