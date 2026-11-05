class_name UIText
extends RefCounted
## All user-facing text comes from assets/data/strings_en.json through [method t], so the
## interface can be translated later. A missing key shows as [key] and fails a test.

const PATH := "res://assets/data/strings_en.json"

static var _table: Dictionary = {}
static var _loaded: bool = false


static func t(key: String, args: Array = []) -> String:
	if not _loaded:
		_load()
	if not _table.has(key):
		return "[%s]" % key
	var text: String = str(_table[key])
	if args.is_empty():
		return text
	return text % args


static func has_key(key: String) -> bool:
	if not _loaded:
		_load()
	return _table.has(key)


static func _load() -> void:
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_table = parsed
