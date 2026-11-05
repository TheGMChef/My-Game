class_name ShapeMark
extends Control
## The small side marker: a circle for the human, a hexagon for the AI.

var side: int = 0


func _init(for_side: int = 0, diameter: float = 12.0) -> void:
	side = for_side
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	var col: Color = UITokens.SIDE_COLOURS[side]
	if side == 0:
		draw_circle(c, r, col)
		return
	var pts := PackedVector2Array()
	for k in range(6):
		var a: float = TAU * float(k) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
