extends SceneTree
## Explicit offline atlas preparation, never called by the game or editor preview.
## Run with masters copied to artifacts/character_direction_sources; see SOURCES.json.

func _initialize() -> void:
	var manifest_path := "res://assets/art/characters/directions/SOURCES.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var slots := [Vector2i(0, 0), Vector2i(44, 0), Vector2i(66, 0), Vector2i(0, 48), Vector2i(36, 48), Vector2i(80, 48)]
	for source: Dictionary in manifest.sources:
		var path := "res://assets/art/characters/directions/%s.png" % source.direction
		_prepare_atlas(source, slots, path)
	if manifest.has("north_whole"):
		_prepare_atlas(manifest.north_whole, [Vector2i(0,0), Vector2i(0,48), Vector2i(36,48)], "res://assets/art/characters/directions/north_whole.png")
	var output := FileAccess.open(manifest_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(manifest, "\t") + "\n")
	output.close()
	print("Prepared character direction atlases")
	quit()

func _prepare_atlas(source: Dictionary, slots: Array, path: String) -> void:
	var original := Image.load_from_file(source.source_copy)
	assert(original != null and not original.is_empty())
	source.master_sha256 = FileAccess.get_sha256(source.source_copy)
	var atlas := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var prepared: Array = []
	for index in source.rects.size():
		var rect: Array = source.rects[index]
		var region := Rect2i(rect[0], rect[1], rect[2], rect[3])
		var part := original.get_region(region)
		var height: int = source.heights[index]
		var width := roundi(float(region.size.x) * height / region.size.y)
		part.resize(width, height, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), slots[index])
		prepared.append([slots[index].x, slots[index].y, width, height])
	assert(atlas.save_png(path) == OK)
	source.prepared_regions = prepared
	source.atlas_sha256 = FileAccess.get_sha256(path)
