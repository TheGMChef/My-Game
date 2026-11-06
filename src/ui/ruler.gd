class_name Ruler
extends RefCounted
## The sums behind the board's measuring tool. A measurement runs between two board points in
## plain inches: no base-edge adjustment. A drag that starts on a model starts at its centre.


## The straight-line distance between two board points, in inches.
static func inches(from_point: Vector2, to_point: Vector2) -> float:
	return from_point.distance_to(to_point)


## The distance as shown on the board, to one decimal place.
static func label(from_point: Vector2, to_point: Vector2) -> String:
	return UIText.t("ruler.inches", [inches(from_point, to_point)])


## Where a measurement starts: the centre of the model under [param point], or the point itself.
## [param models] is an Array of {"pos": Vector2, "radius": float}. The nearest centre wins.
static func start_point(point: Vector2, models: Array) -> Vector2:
	var best: Vector2 = point
	var best_d: float = INF
	for m in models:
		var d: float = (m["pos"] as Vector2).distance_to(point)
		if d <= float(m["radius"]) and d < best_d:
			best_d = d
			best = m["pos"]
	return best


## Where the screen label sits: beside the line's midpoint, kept inside [param view].
static func label_rect(a: Vector2, b: Vector2, box: Vector2, gap: float, view: Rect2) -> Rect2:
	var along: Vector2 = (b - a).normalized() if a != b else Vector2.RIGHT
	var side: Vector2 = Vector2(along.y, -along.x)
	if side.y > 0.0:
		side = -side    # above the line where possible
	var offset: float = gap + absf(side.x) * box.x * 0.5 + absf(side.y) * box.y * 0.5
	var centre: Vector2 = (a + b) * 0.5 + side * offset
	var at: Vector2 = centre - box * 0.5
	at.x = clampf(at.x, view.position.x, maxf(view.position.x, view.end.x - box.x))
	at.y = clampf(at.y, view.position.y, maxf(view.position.y, view.end.y - box.y))
	return Rect2(at, box)
