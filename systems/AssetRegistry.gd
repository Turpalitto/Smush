class_name AssetRegistry
extends RefCounted
## Dual-mode asset loader supporting both Editor imported resources (.ctex/.sample)
## and direct buffer decoding from res:// / .pck archives with zero runtime re-allocations.

static var _tex_cache: Dictionary = {}
static var _wav_cache: Dictionary = {}
static var _ui_font: FontFile = null


static func _can_use_imported_resource(res_path: String) -> bool:
	var import_meta := res_path + ".import"
	if FileAccess.file_exists(import_meta):
		var cfg := ConfigFile.new()
		if cfg.load(import_meta) != OK:
			return false
		var remap_path := str(cfg.get_value("remap", "path", ""))
		if remap_path.is_empty():
			return false
		return FileAccess.file_exists(remap_path)
	return ResourceLoader.exists(res_path)


static func get_ui_font() -> Font:
	if _ui_font != null:
		return _ui_font
	var path := "res://resources/fonts/DejaVuSans.ttf"
	if _can_use_imported_resource(path):
		var loaded := ResourceLoader.load(path)
		if loaded is FontFile:
			_ui_font = loaded
			return _ui_font
	if FileAccess.file_exists(path):
		var raw := FileAccess.get_file_as_bytes(path)
		if not raw.is_empty():
			var ff := FontFile.new()
			ff.data = raw
			_ui_font = ff
			return _ui_font
	return ThemeDB.fallback_font


static func get_texture(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]

	# 1. Try standard imported Godot resource when exported via Editor
	if _can_use_imported_resource(res_path):
		var loaded := ResourceLoader.load(res_path)
		if loaded is Texture2D:
			_tex_cache[res_path] = loaded
			return loaded

	# 2. Fallback: decode PNG directly from FileAccess bytes (works in .pck & raw source)
	if FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img := Image.new()
			var err := img.load_png_from_buffer(bytes)
			if err == OK:
				var tex := ImageTexture.create_from_image(img)
				_tex_cache[res_path] = tex
				return tex
	return null


static func get_wav_stream(res_path: String, loop_enabled: bool = false) -> AudioStreamWAV:
	var cache_key := "%s|%s" % [res_path, str(loop_enabled)]
	if _wav_cache.has(cache_key):
		return _wav_cache[cache_key]

	if _can_use_imported_resource(res_path):
		var loaded := ResourceLoader.load(res_path)
		if loaded is AudioStreamWAV:
			var dup := loaded.duplicate() as AudioStreamWAV
			dup.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop_enabled else AudioStreamWAV.LOOP_DISABLED
			if loop_enabled:
				dup.loop_end = int(dup.get_length() * dup.mix_rate)
			_wav_cache[cache_key] = dup
			return dup

	if FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		var wav := _parse_riff_wav(bytes, loop_enabled)
		if wav != null:
			_wav_cache[cache_key] = wav
			return wav
	return null


static func _parse_riff_wav(bytes: PackedByteArray, loop_enabled: bool) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null

	var pos: int = 12
	var channels: int = 1
	var sample_rate: int = 22050
	var bits_per_sample: int = 16
	var pcm_data := PackedByteArray()

	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(pos + 4)
		var data_start := pos + 8
		if data_start + chunk_size > bytes.size():
			break
		if chunk_id == "fmt " and chunk_size >= 16:
			channels = bytes.decode_u16(data_start + 2)
			sample_rate = bytes.decode_u32(data_start + 4)
			bits_per_sample = bytes.decode_u16(data_start + 14)
		elif chunk_id == "data":
			pcm_data = bytes.slice(data_start, data_start + chunk_size)
			break
		pos = data_start + chunk_size + (chunk_size % 2)

	if pcm_data.is_empty():
		return null

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	stream.data = pcm_data
	if loop_enabled:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bytes_per_frame: int = maxi(1, (bits_per_sample / 8) * channels)
		stream.loop_begin = 0
		stream.loop_end = pcm_data.size() / bytes_per_frame
	return stream
