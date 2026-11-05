class_name TerrainArea
extends RefCounted
## A terrain area (13.01): a rectangle containing one or more terrain features.
## Each feature is {"rect": Rect2, "category": "exposed"|"light"|"dense", "height": float}.

var rect: Rect2
var features: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> TerrainArea:
	var t := TerrainArea.new()
	var r: Array = d["rect"]
	t.rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	for f in d.get("features", []):
		var fr: Array = f["rect"]
		t.features.append({
			"rect": Rect2(float(fr[0]), float(fr[1]), float(fr[2]), float(fr[3])),
			"category": str(f.get("category", "dense")),
			"height": float(f.get("height", 3.0)),
		})
	return t


## Areas with a light or dense feature are obscuring (13.10).
func is_obscuring() -> bool:
	for f in features:
		if f["category"] == "light" or f["category"] == "dense":
			return true
	return false


func has_dense() -> bool:
	for f in features:
		if f["category"] == "dense":
			return true
	return false


## A model is within the area if any part of its base overlaps it.
func contains_model(pos: Vector2, radius: float) -> bool:
	return Geo.circle_overlaps_rect(pos, radius, rect)
