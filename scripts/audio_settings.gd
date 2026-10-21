extends Node
## Temporary calibration gains are separate from the authored per-cue mix.

signal changed

const CONFIG_PATH := "user://audio.cfg"
const SCHEMA_VERSION := 2
const NEUTRAL_PERCENT := 50.0
const CATEGORY_BOOST_DB := 12.0
const MASTER_BOOST_DB := 6.0
const CATEGORIES: Array[Dictionary] = [
	{"id": &"master", "bus": &"Mix", "label": "Общая громкость", "hint": "Все звуки игры"},
	{"id": &"player_weapons", "bus": &"PlayerWeapons", "label": "Оружие игрока", "hint": "Выстрелы, перезарядка, пустой спуск и активная перезарядка"},
	{"id": &"enemy_weapons", "bus": &"EnemyWeapons", "label": "Оружие противников", "hint": "Выстрелы, подготовка и перезарядка противников"},
	{"id": &"footsteps", "bus": &"Footsteps", "label": "Шаги", "hint": "Шаги игрока и других персонажей по всем поверхностям"},
	{"id": &"interactions", "bus": &"Interactions", "label": "Взаимодействия", "hint": "Контейнеры, поиск, предметы, лечение; в будущем — двери, крафт и ремонт"},
	{"id": &"impacts", "bus": &"Impacts", "label": "Попадания и урон", "hint": "Попадания в поверхности, получение урона и разрушения"},
	{"id": &"ambience", "bus": &"Ambience", "label": "Окружение", "hint": "Фон локации, ветер, погода, электричество и механизмы"},
	{"id": &"interface", "bus": &"Interface", "label": "Интерфейс и сигналы", "hint": "Меню, уведомления, редкая добыча и сигналы рейда и эвакуации"},
	{"id": &"voices", "bus": &"Voices", "label": "Голоса и рация", "hint": "Речь, реплики персонажей и радиопереговоры"},
	{"id": &"music", "bus": &"Music", "label": "Музыка", "hint": "Музыка меню и локаций; короткие сигналы результата — в интерфейсе"},
]

var error_message: String = ""
var _volumes: Dictionary = {}
var _dirty: bool = false
var _read_only: bool = false
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(save_preferences)
	add_child(_save_timer)
	reset_defaults(false)
	if _persistence_enabled():
		load_preferences()


func _persistence_enabled() -> bool:
	return OS.get_environment("EXTRACTION_TEST_AUDIO") != "1"


func get_volume(category: StringName) -> float:
	return float(_volumes.get(category, NEUTRAL_PERCENT))


func volume_to_gain(category: StringName, percent: float) -> float:
	var value := clampf(percent, 0.0, 100.0)
	if value <= NEUTRAL_PERCENT:
		return value / NEUTRAL_PERCENT
	var boost := MASTER_BOOST_DB if category == &"master" else CATEGORY_BOOST_DB
	return db_to_linear(boost * (value - NEUTRAL_PERCENT) / (100.0 - NEUTRAL_PERCENT))


func set_volume(category: StringName, percent: float) -> void:
	if not _volumes.has(category) or not is_finite(percent):
		return
	var value := clampf(percent, 0.0, 100.0)
	if is_equal_approx(value, get_volume(category)):
		return
	_volumes[category] = value
	_apply()
	_schedule_save()
	changed.emit()


func reset_defaults(persist: bool = true) -> void:
	for category in CATEGORIES:
		_volumes[category.id] = NEUTRAL_PERCENT
	_apply()
	if persist:
		_schedule_save()
	changed.emit()


func _apply() -> void:
	for category in CATEGORIES:
		var bus := AudioServer.get_bus_index(category.bus)
		if bus < 0:
			continue
		var level := volume_to_gain(category.id, get_volume(category.id))
		AudioServer.set_bus_mute(bus, level <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(level) if level > 0.0 else -80.0)


func _schedule_save() -> void:
	_dirty = true
	if _persistence_enabled() and not _read_only:
		_save_timer.start()


func load_preferences(path: String = CONFIG_PATH) -> void:
	var config := ConfigFile.new()
	_save_timer.stop()
	_read_only = false
	error_message = ""
	for category in CATEGORIES:
		_volumes[category.id] = NEUTRAL_PERCENT
	var migrated := false
	var error := config.load(path)
	if error == OK:
		var version: Variant = config.get_value("meta", "version", 1)
		if not version is int or version not in [1, SCHEMA_VERSION]:
			_read_only = true
			error_message = "Настройки звука из другой версии: сохранённый файл не изменяется."
		else:
			migrated = version == 1
			for category in CATEGORIES:
				var fallback := 100.0 if migrated else NEUTRAL_PERCENT
				var value: Variant = config.get_value("volume", category.id, fallback)
				if (value is float or value is int) and is_finite(float(value)):
					var percent := clampf(float(value), 0.0, 100.0)
					# Old p/100 and new (p/2)/50 have exactly the same gain.
					_volumes[category.id] = percent * 0.5 if migrated else percent
	elif error != ERR_FILE_NOT_FOUND:
		error_message = "Не удалось прочитать настройки звука. Применены стандартные уровни."
	_dirty = migrated
	if migrated and path == CONFIG_PATH and _persistence_enabled():
		_save_timer.start()
	_apply()
	changed.emit()


func save_preferences(path: String = CONFIG_PATH) -> Error:
	if path == CONFIG_PATH and (not _persistence_enabled() or not _dirty):
		return OK
	if _read_only:
		return ERR_UNAVAILABLE
	_save_timer.stop()
	var config := ConfigFile.new()
	config.set_value("meta", "version", SCHEMA_VERSION)
	for category in CATEGORIES:
		config.set_value("volume", category.id, get_volume(category.id))
	# Write and flush before replacing the previous settings file.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	var error := FileAccess.get_open_error()
	if file != null:
		file.store_string(config.encode_to_text())
		file.flush()
		error = file.get_error()
		file.close()
		if error == OK:
			error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		error_message = "Не удалось сохранить звук. Выбранные уровни действуют до выхода из игры."
		changed.emit()
		return error
	_dirty = false
	error_message = ""
	changed.emit()
	return OK


func _exit_tree() -> void:
	if _dirty:
		save_preferences()
