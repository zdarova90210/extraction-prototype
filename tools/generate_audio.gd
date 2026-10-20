extends SceneTree
## Author the project's temporary sound effects once, as ordinary editable WAVs.
## No synthesis runs in gameplay. Existing files require an explicit --overwrite.

const RATE: int = 44100
const SOUNDS: Dictionary = {
	"player_shot": 0.22,
	"guard_shot": 0.26,
	"dry_fire": 0.095,
	"reload_start": 0.32,
	"reload_finish": 0.18,
	"guard_ready": 0.30,
	"player_hit": 0.16,
	"active_reload_success": 0.19,
}


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/audio")
	var overwrite := "--overwrite" in OS.get_cmdline_user_args()
	var selected := SOUNDS.keys()
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	if not only.is_empty():
		if not SOUNDS.has(only):
			push_error("Unknown sound: " + only)
			quit(1)
			return
		selected = [only]
	for name: String in selected:
		if FileAccess.file_exists("res://assets/audio/" + name + ".wav") and not overwrite:
			push_error("Existing audio preserved. Use --overwrite only to regenerate the temporary set.")
			quit(1)
			return
	var preview := PackedByteArray()
	var silence := PackedByteArray()
	silence.resize(int(RATE * 0.4) * 2)
	preview.append_array(silence)
	for name: String in selected:
		var stream := _synthesize(name, SOUNDS[name], 91020 + SOUNDS.keys().find(name))
		var error := stream.save_to_wav("res://assets/audio/" + name + ".wav")
		if error != OK:
			push_error("Cannot save " + name)
			quit(1)
			return
		preview.append_array(stream.data)
		preview.append_array(silence)
		print("Generated ", name, ": ", stream.data.size(), " PCM bytes")
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var preview_stream := AudioStreamWAV.new()
	preview_stream.format = AudioStreamWAV.FORMAT_16_BITS
	preview_stream.mix_rate = RATE
	preview_stream.data = preview
	var preview_name := "audio_preview" if only.is_empty() else "audio_preview_" + only
	preview_stream.save_to_wav("res://artifacts/" + preview_name + ".wav")
	quit()


func _synthesize(kind: String, duration: float, seed_value: int) -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var count := int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var smooth := 0.0
	var peak := 0.0001
	for index in range(count):
		var t := float(index) / RATE
		var noise := random.randf_range(-1.0, 1.0)
		smooth = lerpf(smooth, noise, 0.22)
		var sample := 0.0
		match kind:
			"player_shot":
				var phase := TAU * (72.0 * t + 4.0 * (1.0 - exp(-t * 55.0)))
				sample = sin(phase) * exp(-t * 34.0) * 0.8 + noise * exp(-t * 60.0) * 0.32
				sample += (noise - smooth) * exp(-t * 130.0) * 0.22
			"guard_shot":
				var phase := TAU * (42.0 * t + 2.0 * (1.0 - exp(-t * 40.0)))
				sample = sin(phase) * exp(-t * 25.0) * 0.85 + smooth * exp(-t * 40.0) * 0.8
				sample += noise * exp(-t * 150.0) * 0.24
			"dry_fire":
				sample = _clack(t, noise, 1800.0, 190.0) * 0.6
				sample += _clack(t - 0.024, noise, 950.0, 250.0) * 0.25
			"reload_start":
				sample = _clack(t, noise, 700.0, 95.0) * 0.7
				sample += _clack(t - 0.13, noise, 420.0, 70.0) * 0.5
				sample += _clack(t - 0.24, noise, 1100.0, 120.0) * 0.25
			"reload_finish":
				sample = _clack(t, noise, 520.0, 65.0) * 0.8
				sample += _clack(t - 0.045, noise, 1350.0, 110.0) * 0.45
			"guard_ready":
				sample = _tone(t, 520.0, 0.11) + _tone(t - 0.15, 780.0, 0.12)
			"player_hit":
				sample = smooth * exp(-t * 48.0) * 0.8 + sin(TAU * 62.0 * t) * exp(-t * 40.0) * 0.5
			"active_reload_success":
				# Soft overlapping fifth: a brief positive cue with no sharp attack.
				sample = _tone(t, 660.0, 0.12) * 0.7 + _tone(t - 0.035, 990.0, 0.14) * 0.5
				sample += _tone(t, 1320.0, 0.09) * 0.12
		var envelope := minf(t / 0.0015, 1.0) * clampf((duration - t) / 0.008, 0.0, 1.0)
		sample *= envelope
		samples[index] = sample
		peak = maxf(peak, absf(sample))
	var target_peak := 0.68 if kind in ["player_shot", "guard_shot"] else 0.45
	if kind == "active_reload_success":
		target_peak = 0.32
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for index in range(count):
		bytes.encode_s16(index * 2, int(clampf(samples[index] / peak * target_peak, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream


func _clack(t: float, noise: float, frequency: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	return (noise * 0.7 + sin(TAU * frequency * t) * 0.3) * exp(-t * decay) * minf(t / 0.001, 1.0)


func _tone(t: float, frequency: float, duration: float) -> float:
	if t < 0.0 or t > duration:
		return 0.0
	return sin(TAU * frequency * t) * pow(sin(PI * t / duration), 2.0) * 0.5
