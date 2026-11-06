class_name PlateLayout
extends RefCounted
## Places unit name plates so they do not overlap each other or leave the board view.

const GAP := 3.0
const SEARCH_STEP := 12.0


## Each entry is {"size": Vector2, "anchor": Rect2, "first": bool}, where anchor is the unit's
## bounds on screen. Entries marked first (the selected unit) choose their spot before the rest.
## Returns one Rect2 per entry, in the same order. Plates only overlap if no free spot exists.
## [param keep_clear] holds areas no plate should cover, such as the board tools.
static func arrange(entries: Array, bounds: Rect2, keep_clear: Array[Rect2] = []) -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.resize(entries.size())
	var order: Array = range(entries.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var fa: bool = bool(entries[a].get("first", false))
		var fb: bool = bool(entries[b].get("first", false))
		return fa and not fb if fa != fb else a < b)
	var placed: Array[Rect2] = keep_clear.duplicate()
	for i in order:
		var rect: Rect2 = _best_spot(entries[i], entries, placed, bounds)
		placed.append(rect)
		out[i] = rect
	return out


static func _best_spot(entry: Dictionary, entries: Array, placed: Array[Rect2], bounds: Rect2) -> Rect2:
	var best := Rect2()
	var best_cost: float = INF
	for spot in _candidates(entry, bounds):
		var cost: float = _cost(spot, entry, entries, placed)
		if cost < best_cost:
			best_cost = cost
			best = spot
	return best


## Spots around the unit first, then a sweep outward above and below it.
static func _candidates(entry: Dictionary, bounds: Rect2) -> Array[Rect2]:
	var a: Rect2 = entry["anchor"]
	var s: Vector2 = entry["size"]
	var mid_x: float = a.get_center().x - s.x * 0.5
	var mid_y: float = a.get_center().y - s.y * 0.5
	var points: Array[Vector2] = [
		Vector2(mid_x, a.position.y - s.y - GAP),
		Vector2(mid_x, a.end.y + GAP),
		Vector2(a.end.x + GAP, mid_y),
		Vector2(a.position.x - s.x - GAP, mid_y),
	]
	var step: float = SEARCH_STEP
	while step < bounds.size.y:
		points.append(Vector2(mid_x, a.position.y - s.y - GAP - step))
		points.append(Vector2(mid_x, a.end.y + GAP + step))
		points.append(Vector2(mid_x - s.x - GAP, a.position.y - s.y - GAP - step))
		points.append(Vector2(mid_x + s.x + GAP, a.end.y + GAP + step))
		step += SEARCH_STEP
	var out: Array[Rect2] = []
	for p in points:
		out.append(Rect2(_clamped(p, s, bounds), s))
	return out


static func _clamped(p: Vector2, s: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(p.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - s.x)),
			clampf(p.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - s.y)))


## Hitting another plate is far worse than covering a unit; further from home costs a little.
static func _cost(spot: Rect2, entry: Dictionary, entries: Array, placed: Array[Rect2]) -> float:
	var cost: float = spot.get_center().distance_to((entry["anchor"] as Rect2).get_center()) * 0.1
	for p in placed:
		if spot.grow(GAP * 0.5).intersects(p):
			cost += 100000.0
	for other in entries:
		if spot.intersects(other["anchor"]):
			cost += 500.0
	return cost
