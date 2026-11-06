class_name DialogBox
extends Control
## A modal dialog: a scrim over the whole screen and a notched panel that always fits the window,
## with its body scrolling when there is not enough height. While open it takes the keyboard and
## gamepad, keeps focus inside itself, and Esc or gamepad cancel closes it if [member cancellable].

signal closed

const GAP := UITokens.SPACE_2
const KEY_SCROLL := 48

## Fixed content above the scrolling body, such as tabs.
var header: VBoxContainer
var body: VBoxContainer
var footer: HFlowContainer
var scroll: ScrollContainer
var panel: PanelContainer
var cancellable: bool = true
## Hide on close rather than freeing, for a dialog built once and shown again.
var keep_alive: bool = false
## Up and down scroll the body. For dialogs with nothing to focus inside the body.
var scroll_with_keys: bool = false
var min_body_height: float = 0.0

var _width: float
var _col: VBoxContainer
var _first_focus: Control
var _title: Label


func _init(title_text: String = "", width: float = 420.0) -> void:
	_width = width
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UITokens.with_alpha(UITokens.VOID, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	panel = PanelContainer.new()
	panel.theme_type_variation = "Dialog"
	centre.add_child(panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", UITokens.SPACE_3)
	panel.add_child(_col)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", UITokens.SPACE_3)
	_col.add_child(header)
	if title_text != "":
		_title = Label.new()
		_title.text = title_text
		_title.theme_type_variation = "LabelHeading"
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(_title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_col.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UITokens.SPACE_2)
	body.minimum_size_changed.connect(_queue_fit)
	scroll.add_child(body)
	footer = HFlowContainer.new()
	footer.alignment = FlowContainer.ALIGNMENT_END
	_col.add_child(footer)
	resized.connect(_queue_fit)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_queue_fit()


## Show the dialog, on top of everything, with keyboard focus on [param first_focus].
func open(first_focus: Control = null) -> void:
	if first_focus != null:
		_first_focus = first_focus
	visible = true
	move_to_front()
	_fit()
	_queue_fit()
	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	if not keep_alive:
		queue_free()


## Wrapped text in the scrolling body.
func add_text(text: String, style: String = "LabelBody") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = style
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(l)
	return l


## A button in the footer. [param primary] marks the one main action on the dialog.
func add_button(text: String, handler: Callable, primary: bool = false) -> Button:
	var b := DialogBox.make_button(text, handler, primary)
	footer.add_child(b)
	return b


static func make_button(text: String, handler: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	if primary:
		b.theme_type_variation = "PrimaryButton"
		b.icon = UIIcons.stripe(UITokens.ON_ACTION)
	b.pressed.connect(handler)
	return b


func _input(event: InputEvent) -> void:
	if not visible or not scroll_with_keys:
		return
	var step: int = 0
	if event.is_action_pressed("ui_down", true):
		step = KEY_SCROLL
	elif event.is_action_pressed("ui_up", true):
		step = -KEY_SCROLL
	if step != 0:
		scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and cancellable:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()    # nothing reaches the game behind a dialog


func _on_focus_changed(control: Control) -> void:
	if visible and control != null and not is_ancestor_of(control) and is_instance_valid(_first_focus):
		_first_focus.grab_focus.call_deferred()


func _queue_fit() -> void:
	_fit.call_deferred()


## Dialogs that change shape with the window use this to rearrange before the height is worked out.
func _before_fit(_inner_width: float) -> void:
	pass


## Keep the panel inside the window: the body takes what height is left over.
func _fit() -> void:
	if not is_inside_tree():
		return
	var box: StyleBox = panel.get_theme_stylebox("panel")
	var margins: Vector2 = box.get_minimum_size()
	var inner_width: float = minf(_width, size.x - float(GAP) * 2.0) - margins.x
	_before_fit(inner_width)
	scroll.custom_minimum_size.x = inner_width
	header.custom_minimum_size.x = inner_width
	var sep: float = float(_col.get_theme_constant("separation"))
	footer.visible = footer.get_child_count() > 0
	var chrome: float = margins.y
	if footer.visible:
		chrome += footer.get_combined_minimum_size().y + sep
	if header.get_child_count() > 0:
		chrome += header.get_combined_minimum_size().y + sep
	header.visible = header.get_child_count() > 0
	var room: float = maxf(float(UITokens.HIT), size.y - float(GAP) * 2.0 - chrome)
	var wanted: float = maxf(body.get_combined_minimum_size().y, min_body_height)
	scroll.custom_minimum_size.y = minf(wanted, room)
