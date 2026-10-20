extends SceneTree
## Real isolated disk persistence, staging, backup and inventory conservation.

const PROGRESS = preload("res://scripts/raid_progress.gd")
const ITEM = preload("res://resources/items/metal.tres")
var _checks: int = 0
var _failures: int = 0
var _profiles: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _profile(path: String = "") -> Node:
	var profile := PROGRESS.new()
	root.add_child(profile)
	_profiles.append(profile)
	if not path.is_empty():
		profile.load_profile(path)
	return profile


func _bag(count: int) -> Inventory:
	var bag := Inventory.new()
	for index in range(count):
		bag.starting_items.append(ITEM)
	root.add_child(bag)
	return bag


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _run() -> void:
	var path := "user://profile_check.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	var profile := _profile(path)
	_check(profile.stash.capacity == 20 and profile.pending.capacity == 6 and profile.stash.item_count == 0, "New profile has twenty stash slots and no items")
	_check(not FileAccess.file_exists(path), "Loading nonexistent profile does not invent a save")
	var bag := _bag(4)
	_check(not profile.finish_raid(bag) and bag.item_count == 4, "Cannot claim loot without an active raid")
	_check(profile.begin_raid(), "Empty profile can begin raid")
	var atomic := [true]
	profile.stash.changed.connect(func(): atomic[0] = atomic[0] and bag.item_count + profile.stash.item_count + profile.pending.item_count == 4)
	_check(profile.finish_raid(bag), "Successful extraction commits profile")
	_check(bag.item_count == 0 and profile.stash.item_count == 4 and atomic[0], "Extraction emits final ownership without duplicates")
	_check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "Profile is written and temporary file renamed")
	var raw: Dictionary = JSON.parse_string(_read(path))
	_check(raw.version == 2 and raw.stash.size() == 20 and raw.stash[0] == "metal" and raw.stash[19] == "", "JSON records version and stable item IDs including empty slot positions")
	_check(not profile.finish_raid(bag) and profile.stash.item_count == 4, "Extraction reward cannot be claimed twice")
	var reopened := _profile(path)
	_check(reopened.stash.item_count == 4 and reopened.last_result.outcome == "extracted", "Fresh profile instance loads stash and last result from disk")
	_check(reopened.move_item(reopened.stash, 0, 19), "Stash item can move to an explicit distant slot")
	var restored := _profile(path)
	_check(restored.stash.get_item(0) == null and restored.stash.get_item(19) == ITEM, "Empty holes and manually arranged slots survive reload")
	_check(FileAccess.file_exists(path + ".bak"), "Replacing a valid save preserves previous backup")
	var second_bag := _bag(2)
	restored.begin_raid()
	restored.finish_raid(second_bag)
	_check(restored.stash.item_count == 6 and second_bag.item_count == 0, "Second raid adds loot instead of replacing previous stash")
	var death_bag := _bag(3)
	restored.begin_raid()
	restored.record_death(death_bag)
	_check(death_bag.item_count == 0 and restored.stash.item_count == 6 and restored.last_result.outcome == "died", "Death loses only raid items and records result")
	var after_death := _profile(path)
	_check(after_death.stash.item_count == 6 and after_death.last_result.items.size() == 3, "Death preserves saved stash between launches")
	var full := _profile()
	var full_stash: Array[ItemDefinition] = []
	full_stash.resize(20)
	full_stash.fill(ITEM)
	full.stash.replace_slots(full_stash)
	var extra := _bag(6)
	full.begin_raid()
	_check(full.finish_raid(extra) and full.pending.item_count == 6 and full.stash.item_count == 20 and extra.item_count == 0, "Full stash keeps all six extracted items in overflow")
	_check(not full.can_start_raid() and not full.begin_raid(), "Unresolved overflow blocks starting another raid")
	_check(not full.move_item(full.pending, 0, 0), "Overflow cannot overwrite occupied stash slot")
	_check(full.discard(full.stash, 0) and full.move_item(full.pending, 0, 0), "Freeing a stash slot allows placing overflow without loss")
	full.save_path = path
	_check(full.move_item(full.stash, 1, 2), "Overflow profile can be saved along with stash arrangement")
	var overflow_reload := _profile(path)
	_check(overflow_reload.stash.item_count == 20 and overflow_reload.pending.item_count == 5 and not overflow_reload.can_start_raid(), "Overflow survives closing and reopening game")
	var failed := _profile()
	failed.save_path = "user://missing_directory/profile.json"
	var safe_bag := _bag(2)
	failed.begin_raid()
	_check(not failed.finish_raid(safe_bag), "Disk error reports unsuccessful extraction")
	_check(safe_bag.item_count == 2 and failed.stash.item_count == 0 and failed.raid_active and not failed.error_message.is_empty(), "Failed write leaves source ownership and retry available")
	failed.stash.replace_slots(full_stash)
	_check(not failed.move_item(failed.stash, 0, 19) and failed.stash.get_item(0) == ITEM, "Failed stash write does not apply rearrangement")
	_check(not failed.discard(failed.stash, 0) and failed.stash.item_count == 20, "Failed discard write does not delete item")
	var backup_text := _read(path + ".bak")
	_write(path, "{broken")
	var recovery := _profile(path)
	_check(not recovery.read_only and not recovery.notice.is_empty() and recovery.stash.item_count > 0, "Corrupt primary recovers from valid backup")
	_check(_read(path) == "{broken" and _read(path + ".bak") == backup_text, "Loading recovery does not overwrite either source file")
	_check(recovery.move_item(recovery.stash, 2, 19), "Recovered profile can make a fresh saved change")
	_check(_read(path + ".bak") == backup_text, "Bad primary never replaces the valid backup")
	_write(path, "broken")
	_write(path + ".bak", "also broken")
	var damaged := _profile(path)
	_check(damaged.read_only and not damaged.can_start_raid() and not damaged.discard(damaged.stash, 0), "Two corrupt files block writes instead of silently starting empty")
	_check(_read(path) == "broken", "Corrupt profile remains untouched until explicit reset")
	_check(damaged.reset_progress() and damaged.stash.item_count == 0 and damaged.can_start_raid(), "Explicit reset creates a new empty profile")
	var future: Dictionary = JSON.parse_string(_read(path))
	future.version = 999
	_write(path, JSON.stringify(future))
	var incompatible := _profile(path)
	_check(incompatible.read_only and JSON.parse_string(_read(path)).version == 999, "Unsupported version is protected from overwrite or stale backup fallback")
	future.version = 2
	future.stash[0] = "unknown_future_item"
	_write(path, JSON.stringify(future))
	_check(_profile(path).read_only, "Unknown item ID is protected instead of silently discarded")
	future.stash[0] = ""
	future.last_result = {"outcome": "extracted", "items": 42}
	_write(path, JSON.stringify(future))
	_check(_profile(path).read_only, "Malformed result cannot reach and crash stash UI")
	for owned in _profiles:
		owned.free()
	for owned_bag in [bag, second_bag, death_bag, extra, safe_bag]:
		owned_bag.free()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
