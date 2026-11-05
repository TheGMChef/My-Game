class_name Geo
extends RefCounted
## Small 2D helpers for bases, lines of sight and terrain areas. All units are inches.


## Shortest distance from point [param p] to the segment a-b.
static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## True if the segment a-b touches the circle.
static func segment_hits_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	return point_segment_distance(center, a, b) < radius


## True if the segment a-b touches or lies inside the rectangle.
static func segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	var corners: Array[Vector2] = [tl, tr, br, bl]
	for i in range(4):
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4])
		if hit != null:
			return true
	return false


## True if any part of the circle overlaps the rectangle.
static func circle_overlaps_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest: Vector2 = Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_to(nearest) <= radius


## Gap between the edges of two round bases, never below zero.
static func edge_distance(pos_a: Vector2, radius_a: float, pos_b: Vector2, radius_b: float) -> float:
	return maxf(0.0, pos_a.distance_to(pos_b) - radius_a - radius_b)


## Five points on a base: its centre and four points on its edge. Used to sample lines of sight.
static func sample_points(center: Vector2, radius: float) -> Array[Vector2]:
	return [
		center,
		center + Vector2(radius, 0.0),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(0.0, -radius),
	]
