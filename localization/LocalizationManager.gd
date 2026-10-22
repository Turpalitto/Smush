extends Node
## RU/EN Localization Manager (Autoload: Loc). Primary language: Russian ("ru").

const SUPPORTED_LOCALES: PackedStringArray = ["ru", "en"]
const DEFAULT_LOCALE: String = "ru"

var current_locale: String = DEFAULT_LOCALE
var _tables: Dictionary = {}


func _ready() -> void:
	_load_all_tables()


func _load_all_tables() -> void:
	for loc_code in SUPPORTED_LOCALES:
		var path := "res://resources/localization/%s.json" % loc_code
		if FileAccess.file_exists(path):
			var raw := FileAccess.get_file_as_string(path)
			var parsed: Variant = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("strings"):
				_tables[loc_code] = parsed["strings"]


func set_locale(locale_code: String) -> void:
	var normalized := locale_code.to_lower().substr(0, 2)
	if not SUPPORTED_LOCALES.has(normalized):
		normalized = DEFAULT_LOCALE
	if current_locale == normalized and not _tables.is_empty():
		return
	current_locale = normalized
	Events.locale_changed.emit(current_locale)


func t(key: String, params: Dictionary = {}) -> String:
	if _tables.is_empty():
		_load_all_tables()
	var table: Dictionary = _tables.get(current_locale, {})
	var fallback_table: Dictionary = _tables.get(DEFAULT_LOCALE, {})
	var text: String = str(table.get(key, fallback_table.get(key, key)))
	if not params.is_empty():
		for k in params.keys():
			text = text.replace("{%s}" % str(k), str(params[k]))
	return text
