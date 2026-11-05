class_name ArmyLoader
extends RefCounted
## Finds and prepares army data for the roster screen. Army files are plain JSON the
## user supplies; the repo only ships invented placeholders.
##
## Search order: the bundled placeholder file, res://data/local/*.json (desktop runs
## from the project folder), user://armies/*.json, then any extra path given.

const PLACEHOLDER := "res://assets/data/armies_placeholder.json"
const LOCAL_DIRS: Array[String] = ["res://data/local", "user://armies"]


## Every army found, as an Array of {name, units, source}.
static func load_all(extra_path: String = "") -> Array:
	var out: Array = []
	out.append_array(parse_file(PLACEHOLDER))
	for dir in LOCAL_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.begins_with("army_") or dir.begins_with("user://"):
				if f.ends_with(".json"):
					out.append_array(parse_file(dir.path_join(f)))
	if extra_path != "":
		if DirAccess.dir_exists_absolute(extra_path):
			for f in DirAccess.get_files_at(extra_path):
				if f.ends_with(".json"):
					out.append_array(parse_file(extra_path.path_join(f)))
		else:
			out.append_array(parse_file(extra_path))
	return out


## Armies in one file; an unreadable or malformed file gives an empty array.
static func parse_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	return parse_text(FileAccess.get_file_as_string(path), path)


static func parse_text(text: String, source: String = "") -> Array:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("armies"):
		return []
	var out: Array = []
	for a in parsed["armies"]:
		if a is Dictionary and a.has("name") and a.get("units") is Array:
			var army: Dictionary = a.duplicate()
			army["source"] = source
			out.append(army)
	return out


## A copy of the unit data ready for Battle: model count set within the unit's range,
## and an estimated base size when the datasheet gives none.
static func prepare_unit(unit: Dictionary, models: int) -> Dictionary:
	var d: Dictionary = unit.duplicate(true)
	d["models"] = clampi(models, min_models(unit), max_models(unit))
	d["base_mm"] = float(d.get("base_mm", 0))
	if d["base_mm"] <= 0.0:
		d["base_mm"] = guess_base_mm(d)
	return d


static func min_models(unit: Dictionary) -> int:
	return maxi(int(unit.get("models_min", unit.get("models", 1))), 1)


static func max_models(unit: Dictionary) -> int:
	return maxi(int(unit.get("models_max", unit.get("models", 1))), min_models(unit))


## Datasheets do not list base sizes, so this is an estimate from wounds and keywords.
static func guess_base_mm(unit: Dictionary) -> float:
	var kws: Array = unit.get("keywords", [])
	var wounds: int = int(unit.get("wounds", 1))
	if kws.has("AIRCRAFT") or wounds >= 30:
		return 120.0
	if kws.has("VEHICLE") or kws.has("MONSTER"):
		if wounds >= 16:
			return 100.0
		return 60.0 if wounds >= 8 else 40.0
	if kws.has("SWARM") or kws.has("BEASTS"):
		return 40.0
	return 40.0 if wounds >= 4 else 32.0
