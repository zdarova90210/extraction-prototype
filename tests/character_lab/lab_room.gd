extends Node2D
## Owns only the experimental room controls and live magnifier, never raid progress.

@onready var actor: CharacterBody2D = $World/Actor
@onready var status: Label = $UI/Panel/Status
@onready var near_view: TextureRect = $UI/Panel/Closeup

func _ready() -> void:
	var crop := AtlasTexture.new()
	crop.atlas = actor.get_node("Visual/Pixels").get_texture()
	crop.region = Rect2(16, 24, 96, 88)
	near_view.texture = crop
	_update_status()
	actor.weapon.ammo_changed.connect(func(_a: int, _b: int): _update_status())
	actor.weapon.reload_changed.connect(func(_active: bool): _update_status())
	$UI/PauseMenu.toggled.connect(actor.suspend_input)
	$UI/Panel/Reset.pressed.connect(_reset)
	$UI/Panel/Sneak.toggled.connect(actor.set_sneaking)
	var directions: OptionButton = $UI/Panel/Direction
	for label in ["Направление: мышь", "Вправо", "Вниз-вправо", "Вниз", "Вниз-влево", "Влево", "Вверх-влево", "Вверх", "Вверх-вправо"]:
		directions.add_item(label)
	directions.item_selected.connect(_preview_direction)

func _preview_direction(index: int) -> void:
	actor.visual.direction_override = index - 1
	if index > 0:
		actor.visual.aim_angle = (index - 1) * PI / 4.0
	actor.visual.apply_pose()

func _process(_delta: float) -> void:
	actor.input_blocked = get_viewport().gui_get_hovered_control() != null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("developer_tools") and not event.is_echo():
		_reset()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		$UI/Panel/Sneak.button_pressed = not $UI/Panel/Sneak.button_pressed
		get_viewport().set_input_as_handled()

func _reset() -> void:
	actor.reset_state(Vector2(380, 430))
	for target in $World/Targets.get_children():
		target.health = target.max_health
		target.is_destroyed = false
		target.collision_layer = 4
		target.get_node("CollisionShape2D").set_deferred("disabled", false)
		target.queue_redraw()
	_update_status()

func _update_status() -> void:
	status.text = "Карабин: %d / %d%s" % [actor.weapon.ammo, actor.weapon.magazine_size, " • перезарядка" if actor.weapon.is_reloading else ""]
