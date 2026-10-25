extends SceneTree
## Explicit offline preparation of shared trouser parts and their saved tint.

const MANIFEST := "res://assets/art/characters/legs/SOURCES.json"
const ATLAS := "res://assets/art/characters/legs/work_trousers.png"
const DESTINATION := "res://scenes/characters/legs/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and args[0] in ["--prepare", "--build"])
	if args[0] == "--prepare":
		var atlas := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		for index in data.parts.size():
			var part: Dictionary = data.parts[index]
			var source_path: String = part.get("source", data.source)
			var source := Image.load_from_file(source_path)
			assert(source != null)
			var roi: Array = part.search
			var region := Rect2i(roundi(roi[0] * source.get_width()), roundi(roi[1] * source.get_height()), roundi(roi[2] * source.get_width()), roundi(roi[3] * source.get_height()))
			region = region.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
			var first := region.end
			var last := region.position
			for y in range(region.position.y, region.end.y):
				for x in range(region.position.x, region.end.x):
					if source.get_pixel(x, y).a >= 0.5:
						first = first.min(Vector2i(x, y))
						last = last.max(Vector2i(x + 1, y + 1))
			var rect := Rect2i(first, last - first)
			assert(rect.has_area())
			var piece := source.get_region(rect)
			# Four pixels overlap the coat above the hip; hip-to-ground remains 27.
			piece.resize(roundi(float(piece.get_width()) * 31.0 / piece.get_height()), 31, Image.INTERPOLATE_LANCZOS)
			var slot := Vector2i((index % 4) * 24, (index / 4) * 40)
			atlas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), slot)
			part.master_rect = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			part.rect = [slot.x, slot.y, piece.get_width(), piece.get_height()]
			part.source_sha256 = FileAccess.get_sha256(source_path)
		assert(atlas.save_png(ATLAS) == OK)
		data.master_sha256 = FileAccess.get_sha256(data.source)
		data.atlas_sha256 = FileAccess.get_sha256(ATLAS)
		var output := FileAccess.open(MANIFEST, FileAccess.WRITE)
		output.store_string(JSON.stringify(data, "\t") + "\n")
		output.close()
	else:
		assert(DirAccess.make_dir_recursive_absolute(DESTINATION) == OK)
		for part: Dictionary in data.parts:
			_build(part)
	print("Character leg preparation complete: ", args[0])
	quit()

func _build(part: Dictionary) -> void:
	var texture: Texture2D = load(ATLAS)
	var region: Array = part.rect
	var slot := Vector2(region[0], region[1])
	var size := Vector2(region[2], region[3])
	var hip := Vector2(part.hip[0], part.hip[1])
	var knee := Vector2(part.knee[0], part.knee[1])
	var ankle := Vector2(part.ankle[0], part.ankle[1])
	var leg := Node2D.new()
	leg.name = "NearLeg" if part.name.ends_with("near") else "FarLeg"
	leg.position = Vector2(part.origin[0], part.origin[1])
	var tint: Array = part.get("render_tint", [1.0, 1.0, 1.0])
	leg.modulate = Color(tint[0], tint[1], tint[2], 1.0)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/characters/leg_shadows.gdshader")
	material.set_shader_parameter("shadow_lift", 0.035)
	_add_patch(leg, "Thigh", Rect2(0, 0, size.x, 19), hip, slot, texture, material, leg)
	var shin := Node2D.new()
	shin.name = "Shin"
	leg.add_child(shin)
	shin.owner = leg
	shin.position = knee - hip
	_add_patch(shin, "Image", Rect2(0, 14, size.x, 15), knee, slot, texture, material, leg)
	var foot := Node2D.new()
	foot.name = "Foot"
	shin.add_child(foot)
	foot.owner = leg
	foot.position = ankle - knee
	_add_patch(foot, "Image", Rect2(0, 25, size.x, 6), ankle, slot, texture, material, leg)
	for index in 2:
		var marker := Marker2D.new()
		marker.name = "Heel" if index == 0 else "Toe"
		marker.position = Vector2(-3 if index == 0 else 4, 4)
		foot.add_child(marker)
		marker.owner = leg
	var packed := PackedScene.new()
	assert(packed.pack(leg) == OK)
	assert(ResourceSaver.save(packed, DESTINATION + part.name + ".tscn") == OK)
	leg.free()

func _add_patch(parent: Node2D, title: String, region: Rect2, origin: Vector2, slot: Vector2, texture: Texture2D, material: Material, owner_node: Node) -> void:
	var image := Polygon2D.new()
	image.name = title
	image.texture = texture
	image.material = material
	var points := PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)])
	var polygon := PackedVector2Array()
	var uv := PackedVector2Array()
	for point in points:
		polygon.append(point - origin)
		uv.append(point + slot)
	image.polygon = polygon
	image.uv = uv
	parent.add_child(image)
	image.owner = owner_node
