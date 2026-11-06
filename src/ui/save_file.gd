class_name SaveFile
extends RefCounted
## The autosave on disk: {"battle": Battle.to_save(), "armies": the armies in play}. Saved with
## full precision so positions come back exact, and written to a side file first so a crash
## cannot leave half a save behind.

const PATH := "user://save.json"


static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


## The save as a dictionary, or an empty one if it is missing or unreadable.
static func read(path: String = PATH) -> Dictionary:
	if not exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).has_all(["battle", "armies"]):
		return parsed
	return {}


## True if there is a save this version of the game can carry on from.
static func usable(path: String = PATH) -> bool:
	var data: Dictionary = read(path)
	if data.is_empty():
		return false
	if not data["battle"] is Dictionary:
		return false
	var version: int = int((data["battle"] as Dictionary).get("version", 0))
	return version >= Battle.OLDEST_SAVE_VERSION and version <= Battle.SAVE_VERSION


static func write(data: Dictionary, path: String = PATH) -> bool:
	var side_path: String = path + ".tmp"
	var f := FileAccess.open(side_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "", true, true))
	f.close()
	if DirAccess.rename_absolute(side_path, path) != OK:
		return false
	var synced := FileAccess.open(path, FileAccess.READ_WRITE)    # closing it syncs browser storage
	if synced != null:
		synced.close()
	return true


## On the web, closing a written file is what syncs browser storage, so the file is emptied
## first: a page reload can then never bring back a save from a finished battle.
static func erase(path: String = PATH) -> void:
	if exists(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.close()
		DirAccess.remove_absolute(path)
