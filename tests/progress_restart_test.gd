extends SceneTree
## check.ps1 runs writer and reader in separate Godot processes.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Node = root.get_node("RaidProgress")
	var path := "user://process_restart_profile.json"
	var failures := 0
	var checks := 0
	if "--write-profile" in OS.get_cmdline_user_args():
		profile.save_path = path
		profile.reset_progress()
		var bag := Inventory.new()
		bag.starting_items = [preload("res://resources/items/wire.tres"), preload("res://resources/items/electronics.tres")]
		root.add_child(bag)
		profile.begin_raid()
		var results := [profile.finish_raid(bag), profile.move_item(profile.stash, 0, 19), FileAccess.file_exists(path)]
		checks = results.size()
		for result in results:
			if not result:
				failures += 1
		bag.free()
	else:
		var results := [profile.load_profile(path), profile.stash.item_count == 2, profile.stash.get_item(0) == null, profile.stash.get_item(19) != null and profile.stash.get_item(19).id == &"wire"]
		checks = results.size()
		for result in results:
			if not result:
				failures += 1
	if failures > 0:
		push_error("FAIL: separate process persistence")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
