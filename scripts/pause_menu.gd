extends Control
## Local pause and help screen. Input settings themselves stay in Input Map.

signal toggled(open: bool)
var gameplay_overlay: Control

@onready var resume_button: Button = $Center/Panel/Margin/Content/Resume


func _ready() -> void:
	resume_button.pressed.connect(_on_resume)
	$Center/Panel/Margin/Content/Settings.pressed.connect(func(): set_settings_open(true))
	$SettingsMenu.back_requested.connect(func(): set_settings_open(false))
	$Center/Panel/Margin/Content/Developer.pressed.connect(func(): set_developer_open(true))
	$DeveloperPanel.back_requested.connect(func(): set_developer_open(false))
	var keys: Label = $Center/Panel/Margin/Content/Bindings/Keys
	keys.text = "%s %s %s %s\nМышь\nЛКМ\n%s\n%s\n%s ещё раз\n%s\n%s\n%s\n%s\nEsc" % [
		_binding("move_up"), _binding("move_left"), _binding("move_down"), _binding("move_right"),
		_binding("toggle_sneak"), _binding("reload"), _binding("reload"), _binding("use_item"), _binding("interact"), _binding("inventory"), _binding("restart")]
	$Center/Panel/Margin/Content/Note.text += "\n%s над вещью в рюкзаке — выбросить на пол." % _binding("discard_item")


func _binding(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "—"


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("developer_tools") and not event.is_echo():
		if visible and $DeveloperPanel.visible:
			set_open(false)
		else:
			set_developer_open(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if visible and $SettingsMenu.visible:
			set_settings_open(false)
		elif not visible and is_instance_valid(gameplay_overlay) and gameplay_overlay.visible:
			gameplay_overlay.close_menu()
		else:
			set_open(not visible)
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	if open and is_instance_valid(gameplay_overlay):
		gameplay_overlay.close_menu()
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if open:
		$Center.show()
		$DeveloperPanel.hide()
		resume_button.grab_focus()
	else:
		$SettingsMenu.close()
		resume_button.release_focus()
		# Closing help must not turn a held/clicked mouse button into a shot.
		Input.action_release("shoot")
	toggled.emit(open)


func set_developer_open(open: bool) -> void:
	if not visible:
		set_open(true)
	$SettingsMenu.close()
	$Center.visible = not open
	$DeveloperPanel.visible = open
	if open:
		$DeveloperPanel.focus_tools()
	else:
		resume_button.grab_focus()


func set_settings_open(open: bool) -> void:
	if not visible:
		set_open(true)
	$Center.visible = not open
	$DeveloperPanel.hide()
	if open:
		$SettingsMenu.open()
	else:
		$SettingsMenu.close()
		$Center/Panel/Margin/Content/Settings.grab_focus()


func _on_resume() -> void:
	set_open(false)
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if visible:
		get_tree().paused = false
