class_name UIThemeBuilder
extends RefCounted
## Builds the Godot Theme from [UITokens]: bordered L1 panels, 48px buttons, visible focus rings.


static func build() -> Theme:
	var th := Theme.new()
	th.set_default_font_size(UITokens.TEXT_SECONDARY)

	th.set_color("font_color", "Label", UITokens.TEXT)
	th.set_font_size("font_size", "Label", UITokens.TEXT_SECONDARY)
	th.set_color("default_color", "RichTextLabel", UITokens.TEXT)
	th.set_font_size("normal_font_size", "RichTextLabel", UITokens.TEXT_SECONDARY)
	th.set_font_size("bold_font_size", "RichTextLabel", UITokens.TEXT_SECONDARY)

	# Buttons
	th.set_stylebox("normal", "Button", _box(UITokens.RAISED, UITokens.BORDER))
	th.set_stylebox("hover", "Button", _box(UITokens.RAISED.lightened(0.06), UITokens.BORDER_STRONG))
	th.set_stylebox("pressed", "Button", _box(UITokens.SURFACE, UITokens.ACCENT))
	th.set_stylebox("disabled", "Button", _box(UITokens.SURFACE, UITokens.BORDER))
	th.set_stylebox("focus", "Button", _focus_box())
	th.set_color("font_color", "Button", UITokens.TEXT)
	th.set_color("font_hover_color", "Button", UITokens.TEXT)
	th.set_color("font_pressed_color", "Button", UITokens.ACCENT)
	th.set_color("font_disabled_color", "Button", UITokens.TEXT_FAINT)
	th.set_font_size("font_size", "Button", UITokens.TEXT_SECONDARY)
	th.set_constant("h_separation", "Button", UITokens.SPACE_2)

	# Primary (accent) button variation
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", _box(UITokens.ACCENT, UITokens.ACCENT))
	th.set_stylebox("hover", "PrimaryButton", _box(UITokens.ACCENT.lightened(0.12), UITokens.ACCENT))
	th.set_stylebox("pressed", "PrimaryButton", _box(UITokens.ACCENT.darkened(0.15), UITokens.ACCENT))
	th.set_stylebox("disabled", "PrimaryButton", _box(UITokens.ACCENT_DIM, UITokens.ACCENT_DIM))
	th.set_stylebox("focus", "PrimaryButton", _focus_box())
	th.set_color("font_color", "PrimaryButton", UITokens.ON_ACCENT)
	th.set_color("font_hover_color", "PrimaryButton", UITokens.ON_ACCENT)
	th.set_color("font_pressed_color", "PrimaryButton", UITokens.ON_ACCENT)
	th.set_color("font_disabled_color", "PrimaryButton", UITokens.TEXT_FAINT)

	# Panels: L1 surface with a hairline border
	th.set_stylebox("panel", "PanelContainer", _box(UITokens.SURFACE, UITokens.BORDER, UITokens.SPACE_4))
	th.set_type_variation("RaisedPanel", "PanelContainer")
	th.set_stylebox("panel", "RaisedPanel", _box(UITokens.RAISED, UITokens.BORDER, UITokens.SPACE_3))
	th.set_type_variation("BarPanel", "PanelContainer")
	th.set_stylebox("panel", "BarPanel", _bar_box())

	th.set_stylebox("panel", "Panel", _box(UITokens.SURFACE, UITokens.BORDER))

	# Checkboxes and toggles share the button look
	th.set_color("font_color", "CheckBox", UITokens.TEXT)
	th.set_font_size("font_size", "CheckBox", UITokens.TEXT_SECONDARY)
	th.set_stylebox("focus", "CheckBox", _focus_box())

	th.set_stylebox("separator", "HSeparator", _line_box())
	th.set_constant("separation", "HSeparator", UITokens.SPACE_2)
	th.set_constant("separation", "VBoxContainer", UITokens.SPACE_2)
	th.set_constant("separation", "HBoxContainer", UITokens.SPACE_2)
	return th


static func _box(fill: Color, border: Color, margin: int = UITokens.SPACE_3) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(1)
	b.set_corner_radius_all(UITokens.RADIUS)
	b.content_margin_left = margin
	b.content_margin_right = margin
	b.content_margin_top = UITokens.SPACE_2 if margin <= UITokens.SPACE_3 else margin
	b.content_margin_bottom = b.content_margin_top
	return b


static func _focus_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.border_color = UITokens.ACCENT
	b.set_border_width_all(2)
	b.set_corner_radius_all(UITokens.RADIUS)
	b.expand_margin_left = 2
	b.expand_margin_right = 2
	b.expand_margin_top = 2
	b.expand_margin_bottom = 2
	return b


static func _bar_box() -> StyleBoxFlat:
	var b := _box(UITokens.SURFACE, UITokens.BORDER, UITokens.SPACE_4)
	b.set_corner_radius_all(0)
	b.content_margin_top = UITokens.SPACE_2
	b.content_margin_bottom = UITokens.SPACE_2
	return b


static func _line_box() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = UITokens.BORDER
	l.thickness = 1
	return l
