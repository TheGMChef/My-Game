class_name TitleScreen
extends Control
## The main menu: the wordmark, one line and the menu, beside a small board motif.

signal start_pressed
signal continue_pressed
signal settings_pressed
signal how_to_pressed
signal quit_pressed

const WIDE := 900.0
const TALL := 620.0
const BUTTON_WIDTH := 260.0

## Set before adding to the tree: Continue shows only when there is a save.
var has_save: bool = false
## Set before adding to the tree: Quit shows only on desktop.
var can_quit: bool = false

var _margin: MarginContainer
var _row: BoxContainer
var _brand: VBoxContainer
var _scroll: ScrollContainer
var _menu: VBoxContainer
var _hero: Control
var _small: Control
var _first: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	resized.connect(_arrange)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_right", UITokens.SPACE_6)
	_margin.add_theme_constant_override("margin_top", UITokens.SPACE_3)
	_margin.add_theme_constant_override("margin_bottom", UITokens.SPACE_3)
	add_child(_margin)
	_row = BoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", UITokens.SPACE_4)
	_margin.add_child(_row)
	_brand = VBoxContainer.new()
	_brand.add_theme_constant_override("separation", UITokens.SPACE_3)
	_brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_brand)
	_hero = TopBar.make_wordmark("LabelWordmarkHero")
	_brand.add_child(_hero)
	_small = TopBar.make_wordmark("LabelWordmark")
	_brand.add_child(_small)
	var tag := Label.new()
	tag.theme_type_variation = "LabelDim"
	tag.text = UIText.t("title.tagline")
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 300
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_brand.add_child(tag)
	_row.add_child(_build_menu())
	_arrange.call_deferred()
	focus_first()


func _build_menu() -> ScrollContainer:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size.x = BUTTON_WIDTH
	_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_menu = VBoxContainer.new()
	_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_menu)
	if has_save:
		_menu.add_child(_item("title.continue", continue_pressed, true))
	_menu.add_child(_item("title.new_battle", start_pressed, not has_save))
	_menu.add_child(_item("title.settings", settings_pressed))
	_menu.add_child(_item("title.how_to_play", how_to_pressed))
	if can_quit:
		_menu.add_child(_item("title.quit", quit_pressed))
	return _scroll


func _item(key: String, event: Signal, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = UIText.t(key)
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if primary:
		b.theme_type_variation = "PrimaryButton"
		b.icon = UIIcons.stripe(UITokens.ON_ACTION)
		_first = b
	b.pressed.connect(func() -> void: event.emit())
	return b


## Give keyboard and gamepad focus to the first choice.
func focus_first() -> void:
	_first.grab_focus.call_deferred()


## Tall windows stack the wordmark over the menu; short ones put them side by side.
func _arrange() -> void:
	if _row == null:
		return
	var stacked: bool = size.y >= TALL or size.x < WIDE * 0.5
	_row.vertical = stacked
	_hero.visible = size.x >= WIDE
	_small.visible = size.x < WIDE
	_margin.add_theme_constant_override("margin_left", UITokens.SPACE_8 * 2 if size.x >= WIDE else UITokens.SPACE_6)
	var room: float = size.y - float(UITokens.SPACE_3) * 2.0
	if stacked:
		room -= _brand.get_combined_minimum_size().y + float(UITokens.SPACE_4)
	_scroll.custom_minimum_size.y = minf(_menu.get_combined_minimum_size().y, maxf(float(UITokens.HIT), room))


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
