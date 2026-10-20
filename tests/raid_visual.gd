extends "res://tests/visual_check.gd"
## Real renderer captures for base/results and the world extraction marker.

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _fits(control: Control, bounds: Vector2) -> bool:
	var area := control.get_global_rect()
	return area.position.x >= 0 and area.position.y >= 0 and area.end.x <= bounds.x + 1 and area.end.y <= bounds.y + 1


func _capture() -> void:
	var profile: Node = root.get_node("RaidProgress")
	profile.reset_progress()
	var base := load("res://scenes/base.tscn").instantiate() as Control
	root.add_child(base)
	current_scene = base
	await _ticks(3)
	await _save("base_empty")
	var bag := Inventory.new()
	bag.starting_items = [preload("res://resources/items/metal.tres"), preload("res://resources/items/wire.tres"), preload("res://resources/items/electronics.tres")]
	root.add_child(bag)
	profile.begin_raid()
	profile.finish_raid(bag)
	await _ticks(3)
	await _save("base_extracted")
	var full_stash: Array[ItemDefinition] = []
	full_stash.resize(20)
	full_stash.fill(preload("res://resources/items/metal.tres"))
	profile.stash.replace_slots(full_stash)
	var extras: Array[ItemDefinition] = []
	extras.resize(6)
	extras.fill(preload("res://resources/items/electronics.tres"))
	bag.replace_slots(extras)
	profile.begin_raid()
	profile.finish_raid(bag)
	await _ticks(3)
	await _save("base_overflow")
	var logical := root.get_visible_rect().size
	_check(_fits(base.content, logical), "Full stash and overflow fit base viewport")
	_check(_fits(base.content.get_node("Actions"), logical), "Base actions stay visible with all overflow slots")
	_check(base.stash_grid.get_child_count() == 20 and base.stash_grid.columns == 5, "Rendered stash has four rows of five")
	_check(_fits(base.content.get_node("Columns/Side/DeleteZone"), logical), "Overflow delete destination remains reachable")
	var legacy_excess: Array[ItemDefinition] = []
	legacy_excess.resize(36)
	legacy_excess.fill(preload("res://resources/items/electronics.tres"))
	profile.pending.capacity = legacy_excess.size()
	profile.pending.replace_slots(legacy_excess)
	profile.changed.emit()
	await _ticks(3)
	await _save("base_migrated")
	var pending_scroll: ScrollContainer = base.content.get_node("Columns/Side/PendingScroll")
	pending_scroll.ensure_control_visible(base.pending_grid.get_child(35))
	await _ticks(2)
	await _save("base_migrated_scroll")
	_check(pending_scroll.scroll_vertical > 0, "Maximum legacy overflow can scroll to its last item")
	_check(_fits(base.content, logical), "Maximum migration overflow stays inside the compact base")
	base.get_node("ResetConfirm").popup_centered()
	await _ticks(3)
	await _save("base_reset_confirm")
	base.get_node("ResetConfirm").hide()
	base.free()
	# Full-resolution offscreen cases keep this independent of monitor dimensions.
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size_2d_override_stretch = true
	root.add_child(viewport)
	var wide_base := load("res://scenes/base.tscn").instantiate() as Control
	viewport.add_child(wide_base)
	for entry in [[Vector2i(1280, 800), Vector2i(1280, 800)], [Vector2i(3440, 1440), Vector2i(1720, 720)], [Vector2i(3840, 2160), Vector2i(1280, 720)]]:
		viewport.size = entry[0]
		viewport.size_2d_override = entry[1]
		await _ticks(3)
		_check(_fits(wide_base.content, Vector2(entry[1])), "Overflow stash fits logical viewport: %s" % entry[0])
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://artifacts/base_%dx%d.png" % [entry[0].x, entry[0].y])
	viewport.free()
	bag.free()
	profile.reset_progress()
	var yard := load("res://scenes/test_yard.tscn").instantiate() as Node2D
	root.add_child(yard)
	current_scene = yard
	var player: CharacterBody2D = yard.get_node("Player")
	player.set_physics_process(false)
	yard.get_node("Enemy").set_physics_process(false)
	player.global_position = Vector2(1430, 930)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _ticks(3)
	await _save("extraction_zone")
	player.global_position = yard.get_node("ExtractionZone").global_position
	await _ticks(150)
	yard.get_node("ExtractionZone").set_physics_process(false)
	await _save("extraction_countdown")
	_check(yard.get_node("ExtractionZone").elapsed > 2.4 and yard.get_node("ExtractionZone").elapsed < 2.7, "World countdown advances without a service HUD strip")
	player.take_damage(1000)
	await _ticks(3)
	await _save("raid_death")
	_check(_fits(yard.get_node("HUD/DeathScreen/ToBase"), root.get_visible_rect().size), "Death return button fits viewport")
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	print("Raid captures saved: base_empty, base_extracted, base_overflow, base_reset_confirm, extraction_zone, extraction_countdown, raid_death")
	quit(0 if _failures == 0 else 1)
