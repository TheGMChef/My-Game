class_name BoardToolbar
extends BoxContainer
## Board tools in one place: Ruler, its Clear, and zoom. Display only: it reports presses.

signal ruler_toggled(on: bool)
signal clear_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal fit_pressed

const ICON_SIZE := 20

var ruler: Button
var clear: Button
var _zooms: Array[Button] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -UITokens.SPACE_3
	offset_bottom = -UITokens.SPACE_3
	add_theme_constant_override("separation", UITokens.SPACE_1)
	ruler = _tool("ruler", "tip.ruler", func() -> void: pass)
	ruler.toggle_mode = true
	ruler.toggled.connect(func(on: bool) -> void: ruler_toggled.emit(on))
	clear = _tool("close", "tip.ruler_clear", func() -> void: clear_pressed.emit())
	clear.visible = false
	_zooms.append(_tool("plus", "tip.zoom_in", func() -> void: zoom_in_pressed.emit()))
	_zooms.append(_tool("minus", "tip.zoom_out", func() -> void: zoom_out_pressed.emit()))
	_zooms.append(_tool("fit", "tip.zoom_fit", func() -> void: fit_pressed.emit()))


## Columns beside the board in landscape, a row under it in portrait. Phones keep only the Ruler.
func arrange(column: bool, show_zoom: bool) -> void:
	vertical = column
	for b in _zooms:
		b.visible = show_zoom


## Show the Ruler's state without announcing it again.
func show_ruler(on: bool, measured: bool) -> void:
	ruler.set_pressed_no_signal(on)
	clear.visible = measured


func _tool(icon_name: String, tip_key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.icon = UIIcons.get_icon(icon_name, UITokens.INK, ICON_SIZE)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = UIText.t(tip_key)
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	b.pressed.connect(handler)
	add_child(b)
	return b
