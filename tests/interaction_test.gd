extends "res://tests/loot_slots_test.gd"
## Actual GUI transactions and lifecycle events: one sound for a committed action.

var _cues: Dictionary = {}


func _watch(node: Node) -> void:
	if node.get_script() == preload("res://scripts/sound_player.gd"):
		node.cue_played.connect(func(cue: SoundCue): _cues[cue.id] = _count(cue.id) + 1)
	for child in node.get_children():
		_watch(child)


func _count(id: StringName) -> int:
	return int(_cues.get(id, 0))


func _run() -> void:
	var yard := YARD.instantiate() as Node2D
	yard.audio_test_setup = false # Isolate mechanics from the audio-room starting loadout.
	yard.play_start_audio = false
	NavigationServer2D.region_set_use_async_iterations(yard.get_node("Navigation").get_rid(), false)
	root.add_child(yard)
	current_scene = yard
	yard.get_node("Enemy").set_physics_process(false)
	var player: CharacterBody2D = yard.get_node("Player")
	var pack: Inventory = player.get_node("Inventory")
	var box: StaticBody2D = yard.get_node("LootContainers/Supply")
	var menu: Control = yard.get_node("HUD/LootMenu")
	var audio: Node = box.get_node("Audio")
	var actor_audio: Node2D = player.get_node("InteractionAudio")
	var use: Node = player.get_node("ItemUse")
	_watch(yard)
	player.global_position = Vector2(575, 690)
	player.set_physics_process(false)
	player.get_node("Aim").look_at(box.global_position)
	await _ticks(3)
	_check(_cues.is_empty(), "Starting raid produces no false interaction cues")
	await _key(KEY_E)
	_check(menu.visible and _count(&"container_open") == 1, "Actual E opens container with one latch cue")
	_check(audio.get_node("Search").global_position == box.global_position, "Physical container sound originates at the source rather than world origin")
	menu._activate_slot(box.inventory, 0)
	_check(_count(&"move") == 0 and pack.item_count == 0, "Unknown loot refuses transfer without a move sound")
	await _ticks(35)
	_check(_count(&"search") >= 1 and _count(&"reveal") == 0, "Rummaging begins during unrevealed slot search")
	await _key(KEY_ESCAPE)
	await _ticks(4)
	_check(not menu.visible and _count(&"container_close") == 1 and not audio.get_node("Search").is_playing(), "Closing stops search with one container closing sound")
	var searching := _count(&"search")
	await _ticks(100)
	_check(_count(&"search") == searching and _count(&"reveal") == 0, "Closed container never continues rummaging or discovering")
	await _key(KEY_E)
	await _ticks(35)
	var search_player: Node = audio.get_node("Search/A") if audio.get_node("Search/A").playing else audio.get_node("Search/B")
	var search_playback: AudioStreamPlayback = search_player.get_stream_playback()
	var before_discovery := _count(&"search")
	await _ticks(70)
	_check(_count(&"reveal") >= 1 and search_playback.is_playing() and _count(&"search") == before_discovery, "Discovering a slot preserves the ongoing long rummaging recording")
	await _ticks(260)
	_check(_count(&"reveal") == 4 and not box.has_unknown_items, "Each newly discovered item gives exactly one soft reveal cue")
	await _ticks(8)
	_check(not audio.get_node("Search").is_playing(), "Rummaging stops when the last item is found")
	var grid: GridContainer = menu.backpack_panel.get_node("Grid")
	var source: GridContainer = menu.source_panel.get_node("Grid")
	await _click(source.get_child(0))
	_check(_count(&"move") == 1 and pack.get_item(0) != null, "Real click transfer produces one sound after ownership changes")
	await _click(grid.get_child(4))
	_check(_count(&"move") == 1, "Clicking an empty slot is silent")
	var point: Vector2 = grid.get_child(0).get_global_rect().get_center()
	_motion(point, Vector2.ZERO, false)
	_mouse_button(point, true)
	await _ticks(1)
	_motion(point + Vector2(20, 0), Vector2(20, 0), true)
	await _ticks(1)
	_check(_count(&"move") == 1 and root.gui_is_dragging(), "Mouse down and actual drag start are silent")
	_mouse_button(point + Vector2(20, 0), false)
	await _ticks(2)
	_check(_count(&"move") == 1 and pack.get_item(0) != null, "Returning a drag to its original slot is silent")
	await _drag(grid.get_child(0), grid.get_child(5))
	_check(_count(&"move") == 2 and pack.get_item(5) != null and pack.get_item(0) == null, "Successful GUI drag gives one cue without an extra click cue")
	await _click(source.get_child(2))
	var moves := _count(&"move")
	await _drag(grid.get_child(0), grid.get_child(5))
	_check(_count(&"move") == moves + 1 and pack.get_item(0).id == &"metal", "Swapping occupied slots is one committed action and one cue")
	moves = _count(&"move")
	await _click(menu.content.get_node("Actions/TakeAll"))
	_check(pack.item_count == 4 and _count(&"move") == moves + 1, "Take All moves remaining items with one batch cue")
	await _click(menu.content.get_node("Actions/TakeAll"))
	_check(_count(&"move") == moves + 1, "Empty Take All does not replay confirmation")
	searching = _count(&"search")
	await _key(KEY_ESCAPE)
	await _key(KEY_E)
	await _ticks(100)
	_check(_count(&"reveal") == 4 and _count(&"search") == searching, "Reopening searched container never replays search or item discovery")
	_check(not audio.get_node("Search").is_playing(), "Empty or already searched container has no search loop")
	var payload := {"inventory": pack, "slot": 0, "item": pack.get_item(0)}
	moves = _count(&"move")
	menu._discard(payload)
	await _ticks(3)
	_check(_count(&"drop") == 1 and _count(&"move") == moves and pack.get_item(0) == null, "Dropping creates one physical cue without also playing inventory movement")
	menu._discard(payload)
	_check(_count(&"drop") == 1, "Stale discard request is silent")
	var ground: Node2D = get_nodes_in_group("ground_items")[0]
	var drop_point := ground.global_position
	var actor_point := player.global_position
	player.global_position += Vector2(8, 0)
	_check(actor_audio.get_node("Drop").global_position == drop_point, "Drop sound stays at the ground position when the player moves")
	player.global_position = actor_point
	await _key(KEY_ESCAPE)
	player.get_node("Aim").look_at(ground.global_position)
	var other: Inventory = yard.get_node("LootContainers/Service/Inventory")
	for slot in range(3):
		other.transfer_to(pack, slot)
	await _key(KEY_E)
	_check(pack.is_full and _count(&"pickup") == 0 and get_nodes_in_group("ground_items").size() == 1, "Full backpack refuses actual E pickup without a success cue")
	pack.transfer_to(other, 0)
	await _key(KEY_E)
	await _ticks(2)
	_check(_count(&"pickup") == 1 and _count(&"move") == moves and get_nodes_in_group("ground_items").is_empty(), "Actual E pickup plays once after transfer, without a second UI cue")
	await _key(KEY_E)
	_check(_count(&"pickup") == 1, "Repeated E on an already collected item cannot replay pickup")
	menu.close_menu()

	# Keep normal player physics for the same H path used in gameplay.
	player.set_physics_process(true)
	var slots: Array[ItemDefinition] = [preload("res://resources/items/medkit.tres"), null, null, null, null, null]
	pack.replace_slots(slots)
	await _key(KEY_H)
	_check(_count(&"heal_start") == 0, "Rejected full-health application is silent")
	player.take_damage(70)
	await _key(KEY_H)
	_check(_count(&"heal_start") == 1 and use.is_using, "Actual H starts one treatment cue")
	await _ticks(10)
	await _key(KEY_H)
	await _ticks(5)
	_check(not actor_audio.get_node("HealAction").is_playing() and _count(&"heal_process") == 0 and _count(&"heal_finish") == 0 and pack.item_count == 1, "Cancelling during preparation stops it without process or completion")
	await _key(KEY_H)
	for tick in range(48):
		if _count(&"heal_process") > 0:
			break
		await _ticks(1)
	_check(_count(&"heal_process") >= 1 and use.is_using and use.remaining > 2.15, "Main treatment begins within 0.85 seconds, leaving most of the three-second use audible")
	await _key(KEY_H)
	await _ticks(5)
	_check(_count(&"heal_finish") == 0 and not actor_audio.get_node("HealProcess").is_playing() and pack.item_count == 1, "Cancellation fades process without a success cue or consumed item")
	var joins := {"start": false, "loop": false, "completion": false}
	actor_audio.get_node("HealProcess").cue_played.connect(func(_cue):
		joins.start = joins.start or actor_audio.get_node("HealAction").is_playing()
		joins.loop = joins.loop or (actor_audio.get_node("HealProcess/A").playing and actor_audio.get_node("HealProcess/B").playing))
	use.completed.connect(func(_restored): joins.completion = actor_audio.get_node("HealProcess").is_playing() and actor_audio.get_node("HealAction").is_playing())
	await _key(KEY_H)
	await _ticks(185)
	_check(joins.start and joins.loop, "Preparation and repeated treatment overlap voices instead of leaving gaps")
	_check(joins.completion and actor_audio.get_node("HealProcess").is_playing(), "Confirmed success crossfades physical treatment tail under completion instead of cutting it")
	_check(_count(&"heal_finish") == 1 and player.health == 70.0 and pack.item_count == 0, "Only successful consumption and healing produce completion Foley")
	await _ticks(45)
	_check(not actor_audio.get_node("HealProcess").is_playing() and _count(&"heal_finish") == 1, "Completed treatment cannot keep looping or replay completion")
	pack.replace_slots(slots)
	await _key(KEY_H)
	player.take_damage(5)
	await _ticks(190)
	_check(_count(&"heal_finish") == 1 and pack.item_count == 1, "Damage interruption never produces successful treatment sound")
	yard.free()

	# Stash feedback must be gated by a successful write, not by a drag request.
	var progress: Node = root.get_node("RaidProgress")
	progress.reset_progress()
	var stash_slots: Array[ItemDefinition] = []
	stash_slots.resize(20)
	stash_slots[0] = preload("res://resources/items/metal.tres")
	progress.stash.replace_slots(stash_slots)
	var base := load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	_watch(base)
	await _ticks(3)
	moves = _count(&"move")
	progress.save_path = "user://missing_interaction_directory/progress.json"
	await _drag(base.stash_grid.get_child(0), base.stash_grid.get_child(1))
	_check(progress.stash.get_item(0) != null and _count(&"move") == moves, "Failed stash save preserves item and produces no movement cue")
	progress.save_path = ""
	await _drag(base.stash_grid.get_child(0), base.stash_grid.get_child(1))
	_check(progress.stash.get_item(1) != null and _count(&"move") == moves + 1, "Successful saved stash drag uses the same single transfer cue")
	base.free()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
