extends VBoxContainer
## The sliders edit preferences; preview playback never emits gameplay events.

var sliders: Dictionary = {}
var _values: Dictionary = {}
@onready var settings: Node = get_node("/root/AudioSettings")
@onready var preview: AudioStreamPlayer = $Preview


func _ready() -> void:
	for category: Dictionary in settings.CATEGORIES:
		var row := HBoxContainer.new()
		row.name = String(category.id)
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = category.label
		label.tooltip_text = category.hint
		label.custom_minimum_size.x = 220
		label.add_theme_font_size_override("font_size", 15)
		row.add_child(label)
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(220, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.max_value = 100.0
		slider.step = 1.0
		slider.tick_count = 3
		slider.ticks_on_borders = false
		var boost: float = settings.MASTER_BOOST_DB if category.id == &"master" else settings.CATEGORY_BOOST_DB
		slider.tooltip_text = "%s\n50%% — прежний уровень; 100%% — +%.0f дБ." % [category.hint, boost]
		slider.value_changed.connect(_on_volume_changed.bind(category.id))
		row.add_child(slider)
		sliders[category.id] = slider
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 48
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 14)
		row.add_child(value_label)
		_values[category.id] = value_label
		var listen := Button.new()
		listen.text = "Слушать"
		listen.custom_minimum_size.x = 76
		listen.disabled = _preview_spec(category.id).is_empty()
		listen.tooltip_text = "Короткий пример" if not listen.disabled else "В этой категории пока нет записей"
		listen.pressed.connect(play_preview.bind(category.id))
		row.add_child(listen)
		$Scroll/Rows.add_child(row)
		if category.id == &"master":
			$Scroll/Rows.add_child(HSeparator.new())
	$Reset.pressed.connect(func(): settings.reset_defaults())
	$PreviewTimer.timeout.connect(stop_preview)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			stop_preview())
	settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for category in sliders:
		sliders[category].set_value_no_signal(settings.get_volume(category))
		_values[category].text = "%d%%" % roundi(settings.get_volume(category))
		var gain: float = settings.volume_to_gain(category, settings.get_volume(category))
		_values[category].tooltip_text = "Без звука" if gain <= 0.0 else "%+.1f дБ относительно прежнего уровня" % linear_to_db(gain)
	$Error.text = settings.error_message
	$Error.visible = not settings.error_message.is_empty()


func _on_volume_changed(value: float, category: StringName) -> void:
	settings.set_volume(category, value)


func focus_first() -> void:
	sliders[&"master"].grab_focus()


func _preview_spec(category: StringName) -> Dictionary:
	var cues := {
		&"master": "weapons/carbine_shot", &"player_weapons": "weapons/carbine_shot",
		&"enemy_weapons": "weapons/rifle_shot", &"interactions": "interactions/container_open",
		&"impacts": "combat/concrete", &"interface": "raid/raid_start",
	}
	if cues.has(category):
		var cue := load("res://resources/audio/" + cues[category] + ".tres") as SoundCue
		return {"clip": cue.clips[0], "volume_db": cue.volume_db - 6.0}
	if category == &"footsteps":
		var profile := preload("res://resources/audio/footsteps_concrete.tres")
		return {"clip": profile.clips[0], "volume_db": -22.0 + profile.gain_db}
	if category == &"ambience":
		return {"clip": preload("res://assets/audio/ambience/warehouse_bed_loop.ogg"), "volume_db": -4.0}
	return {}


func play_preview(category: StringName) -> void:
	var spec := _preview_spec(category)
	if spec.is_empty():
		return
	stop_preview()
	for entry: Dictionary in settings.CATEGORIES:
		if entry.id == category:
			preview.bus = &"PlayerWeapons" if category == &"master" else entry.bus
			break
	preview.stream = spec.clip
	preview.volume_db = spec.volume_db
	preview.play()
	$PreviewTimer.start()


func stop_preview() -> void:
	preview.stop()
	$PreviewTimer.stop()
