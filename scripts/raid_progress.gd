extends Node
## Persistent ownership and transactional profile writes; never stores a live raid.

signal changed
const VERSION: int = 2
const STASH_CAPACITY: int = 20
const RAID_CAPACITY: int = 6
const MAX_PENDING_CAPACITY: int = 36 # All excess from the previous 50+6 profile.
const CATALOG: Dictionary = {
	&"metal": preload("res://resources/items/metal.tres"),
	&"wire": preload("res://resources/items/wire.tres"),
	&"electronics": preload("res://resources/items/electronics.tres")
}
var stash: Inventory
var pending: Inventory
var save_path: String = "user://progress.json"
var last_result: Dictionary = {}
var error_message: String = ""
var notice: String = ""
var read_only: bool = false
var raid_active: bool = false


func _ready() -> void:
	stash = Inventory.new()
	stash.name = "Stash"
	stash.capacity = STASH_CAPACITY
	add_child(stash)
	pending = Inventory.new()
	pending.name = "PendingLoot"
	pending.capacity = RAID_CAPACITY
	add_child(pending)
	if OS.get_environment("EXTRACTION_TEST_PROGRESS") == "1":
		save_path = "" # Tests opt in to explicit, isolated files when checking storage.
	else:
		load_profile(save_path)


func can_start_raid() -> bool:
	return not read_only and pending.item_count == 0


func begin_raid() -> bool:
	if not can_start_raid():
		return false
	raid_active = true
	last_result = {}
	notice = ""
	return true


func finish_raid(backpack: Inventory) -> bool:
	if not raid_active or pending.item_count > 0:
		return false
	var next_stash := stash.snapshot_slots()
	var next_pending := pending.snapshot_slots()
	for item in backpack.get_items():
		var free := next_stash.find(null)
		if free >= 0:
			next_stash[free] = item
		else:
			free = next_pending.find(null)
			if free < 0:
				return false
			next_pending[free] = item
	var result := {"outcome": "extracted", "items": _ids(backpack.get_items())}
	if not _commit(next_stash, next_pending, result, backpack):
		return false
	raid_active = false
	return true


func record_death(backpack: Inventory) -> void:
	if not raid_active:
		return
	var result := {"outcome": "died", "items": _ids(backpack.get_items())}
	if not _commit(stash.snapshot_slots(), pending.snapshot_slots(), result, backpack):
		# Death loses the raid contents even if the result could not be written.
		backpack.clear()
		last_result = result
	raid_active = false


func move_item(source: Inventory, from: int, to: int) -> bool:
	if source not in [stash, pending] or source.get_item(from) == null or to < 0 or to >= stash.capacity:
		return false
	var next_stash := stash.snapshot_slots()
	var next_pending := pending.snapshot_slots()
	if source == stash:
		if from == to:
			return false
		var old := next_stash[to]
		next_stash[to] = next_stash[from]
		next_stash[from] = old
	else:
		if next_stash[to] != null:
			return false
		next_stash[to] = next_pending[from]
		next_pending[from] = null
	return _commit(next_stash, next_pending, last_result)


func discard(source: Inventory, slot: int) -> bool:
	if source not in [stash, pending] or source.get_item(slot) == null:
		return false
	var next_stash := stash.snapshot_slots()
	var next_pending := pending.snapshot_slots()
	if source == stash:
		next_stash[slot] = null
	else:
		next_pending[slot] = null
	return _commit(next_stash, next_pending, last_result)


func reset_progress() -> bool:
	var empty_stash: Array[ItemDefinition] = []
	var empty_pending: Array[ItemDefinition] = []
	empty_stash.resize(stash.capacity)
	empty_pending.resize(RAID_CAPACITY)
	# Explicit reset is the only way to replace an incompatible profile.
	var was_read_only := read_only
	read_only = false
	if not _commit(empty_stash, empty_pending, {}):
		read_only = was_read_only
		return false
	raid_active = false
	notice = "Тестовый прогресс сброшен."
	changed.emit()
	return true


func _commit(next_stash: Array[ItemDefinition], next_pending: Array[ItemDefinition], result: Dictionary, backpack: Inventory = null) -> bool:
	if read_only:
		return false
	# Keep occupied positions, but don't retain unused migration-only slots.
	var pending_size := RAID_CAPACITY
	for slot in range(next_pending.size()):
		if next_pending[slot] != null:
			pending_size = maxi(pending_size, slot + 1)
	next_pending.resize(pending_size)
	var data := {"version": VERSION, "stash": _ids(next_stash), "pending": _ids(next_pending), "last_result": result}
	var error := _write_profile(data)
	if error != OK:
		error_message = "Не удалось сохранить прогресс (%s). Изменение не применено." % error_string(error)
		changed.emit()
		return false
	stash.replace_slots(next_stash, false)
	pending.capacity = next_pending.size()
	pending.replace_slots(next_pending, false)
	if backpack != null:
		backpack.clear(false)
	last_result = result.duplicate(true)
	error_message = ""
	stash.changed.emit()
	pending.changed.emit()
	if backpack != null:
		backpack.changed.emit()
	changed.emit()
	return true


func _ids(slots: Array[ItemDefinition]) -> Array[String]:
	var result: Array[String] = []
	for item in slots:
		result.append(String(item.id) if item != null else "")
	return result


func _write_profile(data: Dictionary) -> Error:
	if save_path.is_empty():
		return OK
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	# Never replace a good backup with a damaged primary file.
	if FileAccess.file_exists(save_path) and not _read_profile(save_path).has("error"):
		error = DirAccess.copy_absolute(save_path, save_path + ".bak")
		if error != OK:
			return error
	return DirAccess.rename_absolute(temporary, save_path)


func load_profile(path: String) -> bool:
	save_path = path
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return true
	var loaded := _read_profile(path)
	if loaded.has("error") and not loaded.get("incompatible", false):
		var backup := _read_profile(path + ".bak")
		if not backup.has("error"):
			loaded = backup
			notice = "Прогресс восстановлен из резервной копии."
	if loaded.has("error"):
		error_message = loaded.error + " Файл сохранён без изменений; сброс доступен отдельной командой."
		read_only = true
		changed.emit()
		return false
	stash.replace_slots(loaded.stash, false)
	pending.capacity = loaded.pending.size()
	pending.replace_slots(loaded.pending, false)
	if loaded.get("migrated", false):
		notice += (" " if not notice.is_empty() else "") + "Схрон уменьшен до 20 ячеек. Все вещи сохранены; лишнее — в области разбора."
	last_result = loaded.last_result
	read_only = false
	error_message = ""
	changed.emit()
	return true


func _read_profile(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Сохранение недоступно."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "Сохранение повреждено."}
	var data: Variant = parser.data
	if not data is Dictionary or not data.has_all(["version", "stash", "pending", "last_result"]):
		return {"error": "Сохранение повреждено."}
	if typeof(data.version) not in [TYPE_INT, TYPE_FLOAT] or (data.version != 1 and data.version != VERSION):
		return {"error": "Версия сохранения не поддерживается.", "incompatible": true}
	var result := {}
	for key in ["stash", "pending"]:
		var raw: Variant = data[key]
		if not raw is Array:
			return {"error": "Неверный размер инвентаря в сохранении."}
		var valid_size: bool
		if data.version == 1:
			valid_size = raw.size() == (50 if key == "stash" else RAID_CAPACITY)
		elif key == "stash":
			valid_size = raw.size() == STASH_CAPACITY
		else:
			valid_size = raw.size() >= RAID_CAPACITY and raw.size() <= MAX_PENDING_CAPACITY
		if not valid_size:
			return {"error": "Неверный размер инвентаря в сохранении."}
		var decoded: Array[ItemDefinition] = []
		for id in raw:
			if not id is String:
				return {"error": "Неверный предмет в сохранении."}
			if not id.is_empty() and not CATALOG.has(StringName(id)):
				return {"error": "В сохранении есть неизвестный предмет.", "incompatible": true}
			decoded.append(CATALOG.get(StringName(id)))
		result[key] = decoded
	if not data.last_result is Dictionary:
		return {"error": "Неверный результат рейда в сохранении."}
	if not data.last_result.is_empty():
		var report: Dictionary = data.last_result
		if not report.has_all(["outcome", "items"]) or report.outcome not in ["extracted", "died"] or not report.items is Array or report.items.size() > RAID_CAPACITY:
			return {"error": "Неверный результат рейда в сохранении."}
		for id in report.items:
			if not id is String or not CATALOG.has(StringName(id)):
				return {"error": "Неизвестный предмет в результате рейда.", "incompatible": true}
	result.last_result = data.last_result
	if data.version == 1:
		var smaller: Array[ItemDefinition] = []
		smaller.assign(result.stash.slice(0, STASH_CAPACITY))
		var excess: Array[ItemDefinition] = []
		for item in result.stash.slice(STASH_CAPACITY) + result.pending:
			if item != null:
				var free := smaller.find(null)
				if free >= 0:
					smaller[free] = item
				else:
					excess.append(item)
		excess.resize(maxi(RAID_CAPACITY, excess.size()))
		result.stash = smaller
		result.pending = excess
		result.migrated = true
	return result
