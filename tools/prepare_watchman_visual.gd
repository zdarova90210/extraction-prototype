extends SceneTree
## Explicit offline preparation of the watchman's outfit. Never run by the game.

const ARM_SCRIPT = preload("res://scripts/characters/whole_arm_pose.gd")
var manifest: Dictionary
var manifest_path: String
var art_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 2, "Expected --prepare/--build and a manifest path")
	manifest_path = args[1]
	manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	assert(not manifest.is_empty())
	art_directory = manifest.get("art_dir", manifest.output_dir)
	assert(DirAccess.make_dir_recursive_absolute(manifest.output_dir) == OK)
	assert(DirAccess.make_dir_recursive_absolute(art_directory) == OK)
	if args[0] == "--prepare":
		for entry: Dictionary in manifest.views:
			_prepare(entry)
		var output := FileAccess.open(manifest_path, FileAccess.WRITE)
		output.store_string(JSON.stringify(manifest, "\t") + "\n")
		output.close()
	else:
		assert(args[0] == "--build")
		for entry: Dictionary in manifest.views:
			_build(entry)
		_build_visual()
	print("Watchman preparation complete: ", args[0])
	quit()

func _prepare(entry: Dictionary) -> void:
	var source := Image.load_from_file(entry.source)
	assert(source != null)
	var atlas := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var parts: Array = []
	var regions: Array = entry.regions
	for index in 3:
		var bounds: Array = regions[index]
		var search := Rect2i(roundi(bounds[0] * source.get_width()), roundi(bounds[1] * source.get_height()), roundi(bounds[2] * source.get_width()), roundi(bounds[3] * source.get_height()))
		search = search.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
		var crop_rect := _visible_bounds(source, search)
		assert(crop_rect.has_area())
		var part := source.get_region(crop_rect)
		var target_height: int = 40 if index == 0 else 24
		var target_width := roundi(float(part.get_width()) * target_height / part.get_height())
		part.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
		var slot := Vector2i.ZERO if index == 0 else Vector2i((index - 1) * 36, 48)
		assert(slot.x + target_width <= 128 and slot.y + target_height <= 128)
		atlas.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), slot)
		parts.append({"master_rect": [crop_rect.position.x, crop_rect.position.y, crop_rect.size.x, crop_rect.size.y], "rect": [slot.x, slot.y, target_width, target_height]})
	entry.parts = parts
	entry.master_sha256 = FileAccess.get_sha256(entry.source)
	var path: String = art_directory + "/" + entry.name + ".png"
	assert(atlas.save_png(path) == OK)
	entry.atlas_sha256 = FileAccess.get_sha256(path)

func _visible_bounds(source: Image, region: Rect2i) -> Rect2i:
	var minimum := region.end
	var maximum := region.position
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if source.get_pixel(x, y).a >= 0.5:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x + 1, y + 1))
	return Rect2i(minimum, maximum - minimum)

func _build(entry: Dictionary) -> void:
	var base: PackedScene = load("res://scenes/characters/rigs/" + entry.name + ".tscn")
	var rig: Node2D = base.instantiate()
	var atlas_path: String = art_directory + "/" + entry.name + ".png"
	var atlas: Texture2D
	if atlas_path.begins_with("res://artifacts/"):
		atlas = ImageTexture.create_from_image(Image.load_from_file(atlas_path))
	else:
		atlas = load(atlas_path)
	assert(atlas != null)
	var torso: Sprite2D = rig.get_node("Upper/Torso")
	var body_rect: Array = entry.parts[0].rect
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(body_rect[0], body_rect[1], body_rect[2], body_rect[3])
	torso.texture = texture
	torso.centered = false
	torso.position = Vector2(-body_rect[2] * 0.5, -64)
	var guides: Node2D = rig.get_node_or_null("Upper/ElbowGuides")
	var names := ["SupportArm", "TriggerArm"]
	var default_elbows := [Vector2(-3, 11), Vector2(3, 11)]
	for index in 2:
		var previous: Node2D = rig.get_node("Upper/" + names[index])
		var shoulder := previous.position
		var elbow: Vector2 = default_elbows[index]
		if guides != null:
			elbow = guides.get_node("Support" if index == 0 else "Trigger").position - shoulder
		elif entry.name == "east":
			elbow = Vector2(2, 9) if index == 0 else Vector2(3, 10)
		var depth := previous.z_index
		previous.get_parent().remove_child(previous)
		previous.free()
		var arm := Node2D.new()
		arm.name = names[index]
		rig.get_node("Upper").add_child(arm)
		arm.owner = rig
		arm.position = shoulder
		arm.z_index = depth
		arm.set_script(ARM_SCRIPT)
		arm.grip_target = rig.get_node("Upper/Grip/" + ("SupportWrist" if index == 0 else "TriggerWrist"))
		var rect: Array = entry.parts[index + 1].rect
		var joints: Array = entry.joints[index]
		var size := Vector2(rect[2], rect[3])
		var source_shoulder := Vector2(joints[0][0], joints[0][1]) * size
		arm.source_elbow = Vector2(joints[1][0], joints[1][1]) * size - source_shoulder
		arm.source_wrist = Vector2(joints[2][0], joints[2][1]) * size - source_shoulder
		arm.source_shoulder_uv = Vector2(rect[0], rect[1]) + source_shoulder
		arm.elbow_offset = elbow
		arm.sleeve_width = 0.8
		var image := Polygon2D.new()
		image.name = "Image"
		image.texture = atlas
		arm.add_child(image)
		image.owner = rig
		_mesh(image, Rect2(rect[0], rect[1], rect[2], rect[3]), arm.source_shoulder_uv)
		for marker_name in ["Elbow", "Wrist"]:
			var marker := Marker2D.new()
			marker.name = marker_name
			arm.add_child(marker)
			marker.owner = rig
		arm.get_node("Elbow").position = elbow
		arm.get_node("Wrist").position = arm.grip_target.get_parent().position + arm.grip_target.position - shoulder
	if guides != null:
		guides.get_parent().remove_child(guides)
		guides.free()
	# Clear instance state: these are authored outfit poses using the same animator.
	rig.scene_file_path = ""
	var packed := PackedScene.new()
	assert(packed.pack(rig) == OK)
	assert(ResourceSaver.save(packed, manifest.output_dir + "/" + entry.name + ".tscn") == OK)
	rig.free()

func _mesh(image: Polygon2D, rect: Rect2, shoulder: Vector2) -> void:
	var columns := ceili(rect.size.x / 2.0) + 1
	var rows := ceili(rect.size.y / 2.0) + 1
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	for y in rows:
		for x in columns:
			var texel := rect.position + Vector2(minf(x * 2.0, rect.size.x), minf(y * 2.0, rect.size.y))
			uv.append(texel)
			points.append(texel - shoulder)
	for y in rows - 1:
		for x in columns - 1:
			var start := y * columns + x
			triangles.append(PackedInt32Array([start, start + 1, start + columns]))
			triangles.append(PackedInt32Array([start + 1, start + columns + 1, start + columns]))
	image.polygon = points
	image.uv = uv
	image.polygons = triangles

func _build_visual() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/character_visual.tscn")
	for entry: Dictionary in manifest.views:
		source = source.replace("res://scenes/characters/rigs/" + entry.name + ".tscn", manifest.output_dir + "/" + entry.name + ".tscn")
	var output := FileAccess.open(manifest.output_dir + "/visual.tscn", FileAccess.WRITE)
	output.store_string(source)
	output.close()
