extends Node2D
## Brief local ammo readout; only presentation, driven by weapon events.

@export_range(0.15, 1.0, 0.05, "suffix:s") var display_duration: float = 0.3
@export_range(0.01, 0.1, 0.005, "suffix:s") var fade_in: float = 0.035
@export_range(0.05, 0.2, 0.01, "suffix:s") var fade_out: float = 0.12
@export_range(0.3, 1.0, 0.05) var peak_opacity: float = 0.85

var _remaining: float = 0.0
@onready var actor: CharacterBody2D = get_parent()
@onready var weapon: Node2D = actor.get_node("Aim/Weapon")
@onready var readout: Label = $Readout


func _ready() -> void:
	_hide_feedback()
	_update_count(weapon.ammo, weapon.magazine_size)
	weapon.ammo_changed.connect(_update_count)
	weapon.shot_fired.connect(_on_shot)
	weapon.empty_triggered.connect(_show_feedback)
	weapon.reload_changed.connect(_on_reload)
	actor.died.connect(_hide_feedback)


func _update_count(loaded: int, capacity: int) -> void:
	readout.text = "%d / %d" % [loaded, capacity]
	readout.modulate = Color("f0ac62") if loaded == 0 else Color("dce7dc")


func _on_shot(_from: Vector2, _to: Vector2, _hit: bool) -> void:
	_show_feedback()


func _show_feedback() -> void:
	if actor.is_dead or not weapon.enabled or weapon.is_reloading:
		return
	_remaining = display_duration
	visible = true
	# Preserve current opacity while firing a burst, avoiding a flash on every shot.


func _on_reload(active: bool) -> void:
	if active:
		_hide_feedback()
	elif weapon.enabled and not actor.is_dead and weapon.ammo == weapon.magazine_size:
		_show_feedback()


func _hide_feedback() -> void:
	_remaining = 0.0
	modulate.a = 0.0
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	# Slow weapons can have a cooldown longer than the brief single-shot display.
	# Once shown, keep the count stable during held fire; release still fades it.
	if Input.is_action_pressed("shoot") and weapon.enabled and weapon.ammo > 0 and not weapon.is_reloading:
		_remaining = display_duration
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0:
		_hide_feedback()
		return
	var target_alpha := peak_opacity * smoothstep(0.0, minf(fade_out, display_duration), _remaining)
	modulate.a = move_toward(modulate.a, target_alpha, peak_opacity * delta / fade_in)
