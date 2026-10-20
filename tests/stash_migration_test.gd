extends "res://tests/progress_test.gd"
## A full legacy 50+6 profile must shrink to 20 without losing a single item.


func _run() -> void:
	var path := "user://legacy_stash_check.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	var old_stash: Array[String] = []
	var old_pending: Array[String] = []
	for slot in range(50):
		old_stash.append(["metal", "wire", "electronics"][slot % 3])
	old_pending.resize(6)
	old_pending.fill("wire")
	var legacy := {"version": 1, "stash": old_stash, "pending": old_pending, "last_result": {"outcome": "extracted", "items": ["wire"]}}
	var original := JSON.stringify(legacy)
	_write(path, original)
	var profile := _profile(path)
	_check(not profile.read_only and profile.stash.capacity == 20 and profile.stash.item_count == 20, "Legacy profile opens with twenty occupied stash slots")
	_check(profile.pending.capacity == 36 and profile.pending.item_count == 36, "All thirty-six excess items remain in overflow")
	_check(_read(path) == original and not profile.notice.is_empty(), "Migration reports conversion without overwriting old file on load")
	_check(not profile.can_start_raid(), "Migration overflow blocks new raid until resolved")
	var kept_positions := true
	for slot in range(20):
		kept_positions = kept_positions and String(profile.stash.get_item(slot).id) == old_stash[slot]
	_check(kept_positions, "First twenty occupied positions are preserved")
	var actual: Array[String] = []
	for item in profile.stash.get_items() + profile.pending.get_items():
		actual.append(String(item.id))
	var expected := old_stash + old_pending
	actual.sort()
	expected.sort()
	_check(actual == expected, "Every item identity and duplicate count survives migration")
	_check(profile.discard(profile.pending, 35), "Migrated overflow supports saved removal from last slot")
	var saved: Dictionary = JSON.parse_string(_read(path))
	_check(saved.version == 2 and saved.stash.size() == 20 and saved.pending.size() == 35, "First change writes v2 with occupied overflow positions intact")
	_check(_read(path + ".bak") == original, "Successful migration keeps exact legacy backup")
	var reopened := _profile(path)
	_check(reopened.stash.item_count == 20 and reopened.pending.item_count == 35, "Expanded overflow reloads from version two")
	var base := load("res://scenes/base.tscn").instantiate() as Control
	# The real base uses the autoload; give it the decoded migration state.
	var live: Node = root.get_node("RaidProgress")
	live.load_profile(path)
	root.add_child(base)
	current_scene = base
	for tick in range(3):
		await process_frame
	_check(base.pending_grid.get_child_count() == 35 and base.content.get_node("Columns/Side/PendingScroll").visible, "Base builds all overflow cells inside a scroll view")
	var scroll: ScrollContainer = base.content.get_node("Columns/Side/PendingScroll")
	scroll.ensure_control_visible(base.pending_grid.get_child(34))
	for tick in range(2):
		await process_frame
	_check(scroll.scroll_vertical > 0, "Last migrated item can be reached by scrolling")
	_check(live.reset_progress() and live.pending.capacity == 6 and base.pending_grid.get_child_count() == 6, "Confirmed reset returns overflow capacity and UI to normal six slots")
	base.free()
	# Sparse legacy layouts should fill holes instead of forcing unnecessary overflow.
	old_stash.fill("")
	old_stash[3] = "metal"
	old_stash[49] = "electronics"
	old_pending.fill("")
	old_pending[0] = "wire"
	legacy.stash = old_stash
	legacy.pending = old_pending
	_write(path, JSON.stringify(legacy))
	var sparse := _profile(path)
	_check(sparse.stash.get_item(3).id == &"metal" and sparse.stash.item_count == 3 and sparse.pending.item_count == 0, "Sparse legacy tail fills free stash slots while preserving existing positions")
	_check(sparse.can_start_raid(), "Sparse migration needs no forced overflow resolution")
	for owned in _profiles:
		owned.free()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
