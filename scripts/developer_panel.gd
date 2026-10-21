extends Control
## Training tools only. The yard owns spawning and the list of combatants.

signal back_requested

var _yard: Node2D
var _refresh_time: float = 0.0
@onready var content: VBoxContainer = $Center/Panel/Margin/Content
@onready var guards: ItemList = $Center/Panel/Margin/Content/Guards
@onready var spawn_point: OptionButton = $Center/Panel/Margin/Content/SpawnRow/Point
@onready var message: Label = $Center/Panel/Margin/Content/Message


func _ready() -> void:
	content.get_node("SpawnRow/Add").pressed.connect(_add_guard)
	content.get_node("Actions/Remove").pressed.connect(_remove_guard)
	content.get_node("Actions/Clear").pressed.connect(_clear_guards)
	content.get_node("Actions/Restore").pressed.connect(_restore_player)
	content.get_node("Actions/Restart").pressed.connect(_restart)
	content.get_node("Actions/HealTest").pressed.connect(func(): message.text = _yard.prepare_healing_test())
	content.get_node("Actions/LootTest").pressed.connect(func(): message.text = _yard.restore_test_loot())
	content.get_node("Toggles/GuardsActive").toggled.connect(_toggle_guards)
	content.get_node("Toggles/Immortal").toggled.connect(_toggle_immortality)
	content.get_node("Back").pressed.connect(func(): back_requested.emit())


func bind(yard: Node2D) -> void:
	_yard = yard
	_yard.guards_changed.connect(refresh)
	spawn_point.clear()
	for marker in _yard.get_node("GuardSpawns").get_children():
		spawn_point.add_item(String(marker.name).replace("_", " "))
	refresh()


func focus_tools() -> void:
	refresh()
	content.get_node("SpawnRow/Add").grab_focus()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_yard):
		return
	_refresh_time -= delta
	if _refresh_time <= 0.0:
		_refresh_time = 0.25
		refresh()


func selected_guard() -> CharacterBody2D:
	var selected := guards.get_selected_items()
	if selected.is_empty():
		return null
	var identity: int = guards.get_item_metadata(selected[0])
	for guard in _yard.get_guards():
		if guard.get_instance_id() == identity:
			return guard
	return null


func refresh() -> void:
	content.get_node("Toggles/GuardsActive").set_pressed_no_signal(_yard.guards_active)
	content.get_node("Toggles/Immortal").set_pressed_no_signal(_yard.player.prevent_death)
	var selected := selected_guard() if guards.item_count > 0 else null
	guards.clear()
	var living := 0
	var all_guards: Array[CharacterBody2D] = _yard.get_guards()
	for index in range(all_guards.size()):
		var guard: CharacterBody2D = all_guards[index]
		if not guard.is_dead:
			living += 1
		guards.add_item("Охранник %d · %s · %d / %d HP" % [index + 1, guard.get_state_description(), ceili(guard.health), ceili(guard.max_health)])
		guards.set_item_metadata(index, guard.get_instance_id())
		if guard == selected:
			guards.select(index)
	if not all_guards.is_empty() and guards.get_selected_items().is_empty():
		guards.select(0)
	content.get_node("Count").text = "Охранники: %d / %d · живы: %d" % [all_guards.size(), _yard.MAX_GUARDS, living]
	content.get_node("SpawnRow/Add").disabled = all_guards.size() >= _yard.MAX_GUARDS
	content.get_node("Actions/Remove").disabled = all_guards.is_empty()
	content.get_node("Actions/Clear").disabled = all_guards.is_empty()


func _add_guard() -> void:
	message.text = _yard.spawn_guard(spawn_point.selected)
	refresh()


func _remove_guard() -> void:
	var guard := selected_guard()
	if is_instance_valid(guard):
		_yard.remove_guard(guard)
		message.text = "Выбранный охранник удалён."


func _clear_guards() -> void:
	_yard.remove_all_guards()
	message.text = "Все охранники удалены."


func _restore_player() -> void:
	_yard.restore_player()
	message.text = "Здоровье и магазин игрока восстановлены."


func _toggle_guards(active: bool) -> void:
	_yard.set_guards_active(active)
	message.text = "Охранники активны." if active else "Охранники остановлены, включая оружие и звуки."


func _toggle_immortality(active: bool) -> void:
	_yard.set_immortality(active)
	message.text = "Бессмертие: попадания работают, здоровье не ниже 1 HP." if active else "Бессмертие выключено: игрок может погибнуть."


func _restart() -> void:
	get_viewport().set_input_as_handled()
	get_tree().paused = false
	get_tree().reload_current_scene()
