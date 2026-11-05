class_name UIThemeBuilder
extends RefCounted
## Builds the Godot Theme from [UITokens]: notched panels and controls, 48px targets, solid focus
## rings. Type styles are Label variations, so a screen sets a style name, not sizes and fonts.


static func build() -> Theme:
	var th := Theme.new()
	th.default_font = UITokens.FONT_SANS
	th.default_font_size = UITokens.TEXT_SECONDARY
	_labels(th)
	_buttons(th)
	_panels(th)
	_inputs(th)
	_scrollbars(th)
	th.set_stylebox("separator", "HSeparator", _line_box())
	th.set_constant("separation", "HSeparator", UITokens.SPACE_2)
	th.set_constant("separation", "VBoxContainer", UITokens.SPACE_2)
	th.set_constant("separation", "HBoxContainer", UITokens.SPACE_2)
	th.set_constant("h_separation", "HFlowContainer", UITokens.SPACE_2)
	th.set_constant("v_separation", "HFlowContainer", UITokens.SPACE_2)
	return th


## A style box with the Muster notch cut into the top-right and bottom-left corners.
static func notch(fill: Color, border: Color, cut: int = UITokens.NOTCH_MD, margin: int = UITokens.SPACE_3) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(1)
	b.corner_radius_top_right = cut
	b.corner_radius_bottom_left = cut
	b.corner_detail = 1
	b.anti_aliasing = true
	b.anti_aliasing_size = 0.75
	b.content_margin_left = margin
	b.content_margin_right = margin
	b.content_margin_top = UITokens.SPACE_2 if margin <= UITokens.SPACE_3 else margin
	b.content_margin_bottom = b.content_margin_top
	return b


## Display type with one pixel of letter spacing, for labels and buttons.
static func spaced(font: Font, spacing: int = 1) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = spacing
	return f


static func _labels(th: Theme) -> void:
	th.set_color("font_color", "Label", UITokens.INK)
	th.set_font_size("font_size", "Label", UITokens.TEXT_SECONDARY)
	th.set_color("default_color", "RichTextLabel", UITokens.INK)
	th.set_font_size("normal_font_size", "RichTextLabel", UITokens.TEXT_BODY)
	th.set_font_size("bold_font_size", "RichTextLabel", UITokens.TEXT_BODY)
	th.set_color("font_color", "TooltipLabel", UITokens.INK)
	th.set_font_size("font_size", "TooltipLabel", UITokens.TEXT_META)
	th.set_stylebox("panel", "TooltipPanel", notch(UITokens.RAISED, UITokens.EDGE_STRONG, UITokens.NOTCH_SM))

	var display: Font = UITokens.FONT_DISPLAY
	var spaced_display: Font = spaced(display)
	_label(th, "LabelBody", UITokens.FONT_SANS, UITokens.TEXT_BODY, UITokens.INK)
	_label(th, "LabelDim", UITokens.FONT_SANS, UITokens.TEXT_SECONDARY, UITokens.INK_DIM)
	_label(th, "LabelMeta", UITokens.FONT_SANS, UITokens.TEXT_META, UITokens.INK_DIM)
	_label(th, "LabelSection", spaced_display, UITokens.TEXT_LABEL, UITokens.INK_DIM)
	_label(th, "LabelHeading", display, UITokens.TEXT_HEADING, UITokens.INK)
	_label(th, "LabelTitle", display, UITokens.TEXT_TITLE, UITokens.INK)
	_label(th, "LabelWordmarkSmall", spaced(UITokens.FONT_DISPLAY_BOLD, 2), UITokens.TEXT_HEADING, UITokens.INK)
	_label(th, "LabelWordmark", spaced(UITokens.FONT_DISPLAY_BOLD, 3), UITokens.TEXT_WORDMARK, UITokens.INK)
	_label(th, "LabelWordmarkHero", spaced(UITokens.FONT_DISPLAY_BOLD, 4), UITokens.TEXT_WORDMARK_HERO, UITokens.INK)
	_label(th, "LabelRowName", display, UITokens.TEXT_BODY, UITokens.INK)
	_label(th, "LabelStat", UITokens.FONT_MONO, UITokens.TEXT_STAT, UITokens.INK)
	_label(th, "LabelScore", UITokens.FONT_MONO_BOLD, UITokens.TEXT_SCORE, UITokens.INK)
	_label(th, "LabelReadout", UITokens.FONT_MONO_BOLD, UITokens.TEXT_READOUT, UITokens.INK)
	_label(th, "LabelSmallStat", UITokens.FONT_MONO, UITokens.TEXT_META, UITokens.INK_DIM)


static func _label(th: Theme, type_name: String, font: Font, size: int, colour: Color) -> void:
	th.set_type_variation(type_name, "Label")
	th.set_font("font", type_name, font)
	th.set_font_size("font_size", type_name, size)
	th.set_color("font_color", type_name, colour)


static func _buttons(th: Theme) -> void:
	var font: Font = UITokens.FONT_DISPLAY
	th.set_font("font", "Button", font)
	th.set_font_size("font_size", "Button", UITokens.TEXT_SECONDARY)
	th.set_constant("h_separation", "Button", UITokens.SPACE_2)
	_button_set(th, "Button", UITokens.RAISED, UITokens.EDGE_STRONG, UITokens.INK)

	# The one main action on screen
	th.set_type_variation("PrimaryButton", "Button")
	_button_set(th, "PrimaryButton", UITokens.ACTION, UITokens.ACTION, UITokens.ON_ACTION)
	th.set_stylebox("hover", "PrimaryButton", notch(UITokens.ACTION_HOVER, UITokens.ACTION_HOVER))
	th.set_stylebox("pressed", "PrimaryButton", notch(UITokens.ACTION_HOVER, UITokens.ACTION))
	th.set_color("font_pressed_color", "PrimaryButton", UITokens.ON_ACTION)

	# Ending a phase: visible, but never competes with the main action
	th.set_type_variation("GhostButton", "Button")
	_button_set(th, "GhostButton", UITokens.HULL, UITokens.EDGE_STRONG, UITokens.INK)

	# A pressed option, such as the current move mode
	th.set_stylebox("pressed", "Button", notch(UITokens.RAISED, UITokens.ACTION))
	th.set_color("font_pressed_color", "Button", UITokens.ACTION)
	th.set_color("font_hover_pressed_color", "Button", UITokens.ACTION)

	# Side panel tabs
	th.set_type_variation("TabButton", "Button")
	var tab := StyleBoxFlat.new()
	tab.bg_color = UITokens.PLATE
	tab.content_margin_left = UITokens.SPACE_2
	tab.content_margin_right = UITokens.SPACE_2
	var tab_on: StyleBoxFlat = tab.duplicate()
	tab_on.bg_color = UITokens.RAISED
	tab_on.border_color = UITokens.ACTION
	tab_on.border_width_bottom = 2
	var tab_hover: StyleBoxFlat = tab.duplicate()
	tab_hover.bg_color = UITokens.RAISED
	th.set_stylebox("normal", "TabButton", tab)
	th.set_stylebox("hover", "TabButton", tab_hover)
	th.set_stylebox("pressed", "TabButton", tab_on)
	th.set_stylebox("hover_pressed", "TabButton", tab_on)
	th.set_stylebox("focus", "TabButton", _focus_box(0))
	th.set_font("font", "TabButton", spaced(font))
	th.set_font_size("font_size", "TabButton", UITokens.TEXT_LABEL)
	th.set_color("font_color", "TabButton", UITokens.INK_DIM)
	th.set_color("font_hover_color", "TabButton", UITokens.INK)
	th.set_color("font_pressed_color", "TabButton", UITokens.INK)
	th.set_color("font_hover_pressed_color", "TabButton", UITokens.INK)

	# Roster rows
	th.set_type_variation("RowButton", "Button")
	_button_set(th, "RowButton", UITokens.PLATE, UITokens.EDGE, UITokens.INK)
	th.set_stylebox("hover", "RowButton", notch(UITokens.RAISED, UITokens.EDGE_STRONG))
	th.set_type_variation("RowButtonOn", "Button")
	_button_set(th, "RowButtonOn", UITokens.RAISED, UITokens.ACTION, UITokens.INK)
	th.set_stylebox("hover", "RowButtonOn", notch(UITokens.RAISED, UITokens.ACTION_HOVER))


static func _button_set(th: Theme, type_name: String, fill: Color, border: Color, ink: Color) -> void:
	th.set_stylebox("normal", type_name, notch(fill, border))
	th.set_stylebox("hover", type_name, notch(fill.lightened(0.07), border))
	th.set_stylebox("pressed", type_name, notch(fill.darkened(0.15), border))
	th.set_stylebox("disabled", type_name, notch(UITokens.HULL, UITokens.EDGE))
	th.set_stylebox("focus", type_name, _focus_box())
	th.set_color("font_color", type_name, ink)
	th.set_color("font_hover_color", type_name, ink)
	th.set_color("font_focus_color", type_name, ink)
	th.set_color("font_pressed_color", type_name, ink)
	th.set_color("font_disabled_color", type_name, UITokens.INK_FAINT)


static func _panels(th: Theme) -> void:
	# Bars and side panels sit flush, so only cards are notched.
	th.set_stylebox("panel", "PanelContainer", _flat(UITokens.HULL, UITokens.SPACE_3))
	th.set_type_variation("BarPanel", "PanelContainer")
	var bar := _flat(UITokens.HULL, UITokens.SPACE_3)
	bar.content_margin_top = UITokens.SPACE_2
	bar.content_margin_bottom = UITokens.SPACE_2
	bar.border_color = UITokens.EDGE
	th.set_stylebox("panel", "BarPanel", bar)
	th.set_type_variation("Screen", "PanelContainer")
	th.set_stylebox("panel", "Screen", _flat(UITokens.VOID, 0))
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", notch(UITokens.PLATE, UITokens.EDGE, UITokens.NOTCH_LG, UITokens.SPACE_4))
	th.set_type_variation("Dialog", "PanelContainer")
	th.set_stylebox("panel", "Dialog", notch(UITokens.HULL, UITokens.EDGE_STRONG, UITokens.NOTCH_LG, UITokens.SPACE_6))
	th.set_type_variation("Tile", "PanelContainer")
	var tile := _flat(UITokens.RAISED, UITokens.SPACE_1)
	tile.content_margin_top = UITokens.SPACE_1
	tile.content_margin_bottom = UITokens.SPACE_1
	th.set_stylebox("panel", "Tile", tile)
	th.set_type_variation("StepOn", "PanelContainer")
	th.set_stylebox("panel", "StepOn", _step(UITokens.ACTION))
	th.set_type_variation("StepOff", "PanelContainer")
	th.set_stylebox("panel", "StepOff", _step(UITokens.PLATE))
	th.set_stylebox("panel", "Panel", _flat(UITokens.HULL, 0))


static func _inputs(th: Theme) -> void:
	var field: StyleBoxFlat = notch(UITokens.RAISED, UITokens.EDGE_STRONG)
	field.content_margin_left = UITokens.SPACE_3
	var field_focus: StyleBoxFlat = notch(UITokens.RAISED, UITokens.ACTION)
	field_focus.set_border_width_all(2)
	field_focus.bg_color = Color(0, 0, 0, 0)
	th.set_stylebox("normal", "LineEdit", field)
	th.set_stylebox("focus", "LineEdit", field_focus)
	th.set_stylebox("read_only", "LineEdit", notch(UITokens.HULL, UITokens.EDGE))
	th.set_color("font_color", "LineEdit", UITokens.INK)
	th.set_color("font_placeholder_color", "LineEdit", UITokens.INK_DIM)
	th.set_color("caret_color", "LineEdit", UITokens.ACTION)
	th.set_color("selection_color", "LineEdit", UITokens.with_alpha(UITokens.ACTION, 0.3))
	th.set_font_size("font_size", "LineEdit", UITokens.TEXT_SECONDARY)
	th.set_icon("clear", "LineEdit", UIIcons.get_icon("close", UITokens.INK_DIM, 18))

	th.set_font("font", "OptionButton", UITokens.FONT_SANS)
	th.set_font_size("font_size", "OptionButton", UITokens.TEXT_SECONDARY)
	_button_set(th, "OptionButton", UITokens.RAISED, UITokens.EDGE_STRONG, UITokens.INK)
	th.set_icon("arrow", "OptionButton", UIIcons.get_icon("chevron", UITokens.INK_DIM, 18))

	var popup := _flat(UITokens.RAISED, UITokens.SPACE_2)
	popup.border_color = UITokens.EDGE_STRONG
	popup.set_border_width_all(1)
	th.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := _flat(UITokens.ACTION, UITokens.SPACE_2)
	th.set_stylebox("hover", "PopupMenu", popup_hover)
	th.set_color("font_color", "PopupMenu", UITokens.INK)
	th.set_color("font_hover_color", "PopupMenu", UITokens.ON_ACTION)
	th.set_font_size("font_size", "PopupMenu", UITokens.TEXT_SECONDARY)
	th.set_constant("v_separation", "PopupMenu", UITokens.SPACE_3)

	th.set_stylebox("normal", "SpinBox", field)
	th.set_icon("up", "SpinBox", UIIcons.get_icon("chevron_up", UITokens.INK_DIM, 16))
	th.set_icon("down", "SpinBox", UIIcons.get_icon("chevron", UITokens.INK_DIM, 16))

	th.set_color("font_color", "CheckBox", UITokens.INK)
	th.set_color("font_hover_color", "CheckBox", UITokens.INK)
	th.set_color("font_pressed_color", "CheckBox", UITokens.INK)
	th.set_color("font_hover_pressed_color", "CheckBox", UITokens.INK)
	th.set_font_size("font_size", "CheckBox", UITokens.TEXT_SECONDARY)
	th.set_stylebox("focus", "CheckBox", _focus_box())
	th.set_icon("checked", "CheckBox", UIIcons.get_icon("box_on", UITokens.ACTION, 24))
	th.set_icon("unchecked", "CheckBox", UIIcons.get_icon("box", UITokens.EDGE_STRONG, 24))


static func _scrollbars(th: Theme) -> void:
	for type_name in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = UITokens.VOID
		track.content_margin_left = 2
		track.content_margin_right = 2
		track.content_margin_top = 2
		track.content_margin_bottom = 2
		var grab := StyleBoxFlat.new()
		grab.bg_color = UITokens.EDGE
		var grab_hot := StyleBoxFlat.new()
		grab_hot.bg_color = UITokens.EDGE_STRONG
		th.set_stylebox("scroll", type_name, track)
		th.set_stylebox("scroll_focus", type_name, track)
		th.set_stylebox("grabber", type_name, grab)
		th.set_stylebox("grabber_highlight", type_name, grab_hot)
		th.set_stylebox("grabber_pressed", type_name, grab_hot)


static func _flat(fill: Color, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.content_margin_left = margin
	b.content_margin_right = margin
	b.content_margin_top = margin
	b.content_margin_bottom = margin
	return b


static func _step(fill: Color) -> StyleBoxFlat:
	var b := _flat(fill, UITokens.SPACE_3)
	b.content_margin_top = UITokens.SPACE_2
	b.content_margin_bottom = UITokens.SPACE_2
	return b


static func _focus_box(cut: int = UITokens.NOTCH_MD) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.border_color = UITokens.ACTION
	b.set_border_width_all(2)
	b.corner_radius_top_right = cut
	b.corner_radius_bottom_left = cut
	b.corner_detail = 1
	b.set_expand_margin_all(3)
	return b


static func _line_box() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = UITokens.EDGE
	l.thickness = 1
	return l
