class_name TitleScreen
extends Control
## The opening screen: the wordmark, one line and one action, beside a small board motif.

signal start_pressed

const WIDE := 900.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITokens.SPACE_8 * 2)
	margin.add_theme_constant_override("margin_right", UITokens.SPACE_6)
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UITokens.SPACE_4)
	margin.add_child(col)
	col.add_child(TopBar.make_wordmark("LabelWordmarkHero" if get_viewport_rect().size.x >= WIDE else "LabelWordmark"))
	var tag := Label.new()
	tag.theme_type_variation = "LabelDim"
	tag.text = UIText.t("title.tagline")
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 320
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tag)
	var start := Button.new()
	start.text = UIText.t("title.start")
	start.theme_type_variation = "PrimaryButton"
	start.icon = UIIcons.stripe(UITokens.ON_ACTION)
	start.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.pressed.connect(func() -> void: start_pressed.emit())
	col.add_child(start)
	start.grab_focus.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITokens.VOID)
	if size.x < WIDE:
		return
	var s: float = minf(size.x / 1280.0, size.y / 800.0)
	var left: float = size.x * 0.55
	var step: float = 120.0 * s
	var x: float = left
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), UITokens.BOARD_GRID, 1.0)
		x += step
	var y: float = step
	while y < size.y:
		draw_line(Vector2(left, y), Vector2(size.x, y), UITokens.BOARD_GRID, 1.0)
		y += step
	var centre := Vector2(size.x * 0.78, size.y * 0.45)
	draw_circle(centre, 180.0 * s, UITokens.with_alpha(UITokens.RELAY, 0.08))
	draw_arc(centre, 180.0 * s, 0.0, TAU, 96, UITokens.RELAY, 2.0, true)
	_diamond(centre, 48.0 * s, UITokens.VOID, UITokens.RELAY, 5.0)
	_diamond(centre, 18.0 * s, UITokens.RELAY, UITokens.RELAY, 0.0)
	for p: Vector2 in [Vector2(-180, -150), Vector2(-132, -150), Vector2(-84, -150), Vector2(-156, -104), Vector2(-108, -104)]:
		draw_circle(centre + p * s, 22.0 * s, UITokens.PLAYER)
	for p: Vector2 in [Vector2(120, 160), Vector2(40, 206), Vector2(200, 206)]:
		_hexagon(centre + p * s, 48.0 * s, UITokens.ENEMY)


func _diamond(c: Vector2, r: float, fill: Color, line: Color, width: float) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	if width > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, line, width, true)


func _hexagon(c: Vector2, r: float, fill: Color) -> void:
	var pts := PackedVector2Array()
	for k in range(6):
		var a: float = TAU * float(k) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
