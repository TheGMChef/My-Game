class_name ActionBar
extends PanelContainer
## The buttons for the current choice. The controller says what is on offer as plain specs:
## {"hint": text} or {"text", "handler", "role", "disabled", "pressed"}, where role is "main",
## "option" or "normal". One main action at most; ending the phase is always a ghost button.

signal next_pressed
signal skip_pressed

var _box: BoxContainer
var _scroll: ScrollContainer
var _options: HFlowContainer
var _main_slot: HBoxContainer
var _skip: Button
var _next: Button
var _phone: bool = false


func _init() -> void:
	theme_type_variation = "BarPanel"
	custom_minimum_size.y = UITokens.BOTTOM_BAR
	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", UITokens.SPACE_2)
	add_child(_box)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(_scroll)
	_options = HFlowContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll.add_child(_options)
	_skip = _make_button(UIText.t("button.skip"), func() -> void: skip_pressed.emit(), "GhostButton")
	_skip.visible = false
	_box.add_child(_skip)
	_next = _make_button("", func() -> void: next_pressed.emit(), "GhostButton")
	_box.add_child(_next)
	_main_slot = HBoxContainer.new()
	_box.add_child(_main_slot)
	set_phone(false)


## Phone layout stacks the bar into the right-hand column, main action above End phase.
func set_phone(on: bool) -> void:
	_phone = on
	_box.vertical = on
	custom_minimum_size.y = 0.0 if on else float(UITokens.BOTTOM_BAR)
	if on:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		remove_theme_stylebox_override("panel")
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if on else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL
	_box.move_child(_main_slot, _box.get_child_count() - 2 if on else _box.get_child_count() - 1)
	for b: Button in [_skip, _next]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL


func set_busy(on: bool) -> void:
	_skip.visible = on


func show_actions(specs: Array[Dictionary], next_text: String, next_disabled: bool) -> void:
	for box: Control in [_options, _main_slot]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_next.text = next_text
	_next.disabled = next_disabled
	for spec in specs:
		if spec.has("hint"):
			_options.add_child(_hint(str(spec["hint"])))
		elif str(spec.get("role", "normal")) == "main":
			_main_slot.add_child(_main_button(spec))
		else:
			_options.add_child(_plain_button(spec))
	_main_slot.visible = _main_slot.get_child_count() > 0


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "LabelDim"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.y = UITokens.HIT
	if _phone:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(UITokens.PHONE_COLUMN - UITokens.SPACE_6, 0)
	return l


func _main_button(spec: Dictionary) -> Button:
	var b := _make_button(str(spec["text"]), spec["handler"], "PrimaryButton")
	b.disabled = bool(spec.get("disabled", false))
	if not b.disabled:
		b.icon = UIIcons.stripe(UITokens.ON_ACTION)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _phone:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT    # keeps the stripe beside the label
	return b


func _plain_button(spec: Dictionary) -> Button:
	var b := _make_button(str(spec["text"]), spec["handler"], "")
	b.disabled = bool(spec.get("disabled", false))
	if str(spec.get("role", "")) == "option":
		b.toggle_mode = true
		b.button_pressed = bool(spec.get("pressed", false))
	if _phone:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _make_button(text: String, handler: Callable, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	b.pressed.connect(handler)
	return b
