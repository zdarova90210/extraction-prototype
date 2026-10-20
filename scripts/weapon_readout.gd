extends Control
## Always available weapon information; no gameplay rules live in the HUD.

var _weapon: Node2D


func bind(weapon: Node2D) -> void:
	if is_instance_valid(_weapon):
		_weapon.ammo_changed.disconnect(_on_ammo_changed)
		_weapon.reload_changed.disconnect(_on_reload_changed)
	_weapon = weapon
	_weapon.ammo_changed.connect(_on_ammo_changed)
	_weapon.reload_changed.connect(_on_reload_changed)
	_refresh()


func _on_ammo_changed(_loaded: int, _capacity: int) -> void:
	_refresh()


func _on_reload_changed(_active: bool) -> void:
	_refresh()


func _refresh() -> void:
	$Name.text = _weapon.display_name.to_upper()
	$Ammo.text = "%d / %d" % [_weapon.ammo, _weapon.magazine_size]
	$Ammo.modulate = Color("efb37b") if _weapon.ammo == 0 else Color("dce7dc")
	$State.text = "ПЕРЕЗАРЯДКА" if _weapon.is_reloading else ("ПУСТО" if _weapon.ammo == 0 else "")
