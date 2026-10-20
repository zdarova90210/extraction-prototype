extends Control
## Local pause and help screen. Input settings themselves stay in Input Map.

signal toggled(open: bool)

@onready var resume_button: Button = $Center/Panel/Margin/Content/Resume


func _ready() -> void:
	resume_button.pressed.connect(_on_resume)
	var keys: Label = $Center/Panel/Margin/Content/Bindings/Keys
	keys.text = "%s %s %s %s\nМышь\nЛКМ\n%s\n%s ещё раз\n%s\nEsc" % [
		_binding("move_up"), _binding("move_left"), _binding("move_down"), _binding("move_right"),
		_binding("reload"), _binding("reload"), _binding("restart")]


func _binding(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "—"


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if open:
		resume_button.grab_focus()
	else:
		resume_button.release_focus()
		# Closing help must not turn a held/clicked mouse button into a shot.
		Input.action_release("shoot")
	toggled.emit(open)


func _on_resume() -> void:
	set_open(false)
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if visible:
		get_tree().paused = false
