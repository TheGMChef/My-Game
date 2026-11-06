class_name SettingsDialog
extends DialogBox
## Tabbed settings, used from the main menu and the pause menu. Changes apply as they are made;
## the owner saves on [signal DialogBox.closed], so tools can leave the file alone.

signal changed

const TABS: Array[String] = ["display", "gameplay", "accessibility", "controls"]
const WIDTH := 480.0
const BODY_HEIGHT := 300.0
const TABS_IN_ONE_ROW_FROM := 400.0
const TITLE_FROM_HEIGHT := 420.0
const CONTROLS_PAGE := 3
const CONTROL_ROWS: Array[String] = ["select", "move", "confirm", "cancel", "menu", "next", "ruler", "zoom", "pan"]

var settings: UISettings
var close_button: Button

var _tab_grid: GridContainer
var _tabs: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _size_value: Label


func _init(target: UISettings) -> void:
	super(UIText.t("settings.title"), WIDTH)
	settings = target
	min_body_height = BODY_HEIGHT
	_tab_grid = GridContainer.new()
	_tab_grid.columns = TABS.size()
	_tab_grid.add_theme_constant_override("h_separation", 2)
	_tab_grid.add_theme_constant_override("v_separation", 2)
	header.add_child(_tab_grid)
	var group := ButtonGroup.new()
	for i in range(TABS.size()):
		var tab := Button.new()
		tab.theme_type_variation = "TabButton"
		tab.text = UIText.t("settings.tab." + TABS[i]).to_upper()
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size.y = UITokens.HIT
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_page.bind(i))
		_tab_grid.add_child(tab)
		_tabs.append(tab)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", UITokens.SPACE_2)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(page)
		_pages.append(page)
	_build_display(_pages[0])
	_build_gameplay(_pages[1])
	_build_accessibility(_pages[2])
	_build_controls(_pages[3])
	close_button = add_button(UIText.t("button.close"), close, true)
	_tabs[0].button_pressed = true
	show_page(0)


func _ready() -> void:
	super()
	_first_focus = _tabs[0]


func show_page(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index
	_tabs[index].button_pressed = true
	scroll_with_keys = index == CONTROLS_PAGE
	scroll.scroll_vertical = 0
	_queue_fit()


func _before_fit(inner_width: float) -> void:
	_tab_grid.columns = TABS.size() if inner_width >= TABS_IN_ONE_ROW_FROM else 2
	_title.visible = size.y >= TITLE_FROM_HEIGHT


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cycle_next"):
		_cycle(1)
	elif visible and event.is_action_pressed("cycle_prev"):
		_cycle(-1)
	super(event)


func _cycle(step: int) -> void:
	for i in range(_tabs.size()):
		if _tabs[i].button_pressed:
			var next: int = (i + step + _tabs.size()) % _tabs.size()
			show_page(next)
			_tabs[next].grab_focus()
			return


func _build_display(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = UIText.t("settings.text_size")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_size_value = Label.new()
	_size_value.theme_type_variation = "LabelStat"
	row.add_child(_size_value)
	row.add_child(DialogBox.make_button(UIText.t("settings.smaller"), _change_text_size.bind(-1)))
	row.add_child(DialogBox.make_button(UIText.t("settings.larger"), _change_text_size.bind(1)))
	page.add_child(row)
	_show_text_size()
	page.add_child(_check("settings.plates", "show_plates"))
	page.add_child(_check("settings.objectives", "show_objectives"))
	page.add_child(_check("settings.engagement", "show_engagement"))
	page.add_child(_check("settings.coherency", "show_coherency"))


func _build_gameplay(page: VBoxContainer) -> void:
	var label := Label.new()
	label.text = UIText.t("settings.ai_speed")
	page.add_child(label)
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for i in range(UISettings.AI_SPEED_NAMES.size()):
		var b := Button.new()
		b.text = UIText.t("settings.ai_speed." + UISettings.AI_SPEED_NAMES[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = settings.ai_speed_index == i
		b.custom_minimum_size.y = UITokens.HIT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_ai_speed.bind(i))
		row.add_child(b)
	page.add_child(row)
	page.add_child(_check("settings.confirm_end_phase", "confirm_end_phase"))
	page.add_child(_check("settings.stratagem_prompts", "stratagem_prompts"))
	page.add_child(_check("settings.reanimate_models", "reanimate_models"))


func _build_accessibility(page: VBoxContainer) -> void:
	page.add_child(_check("settings.colour_blind", "colour_blind"))
	page.add_child(_check("settings.reduced_motion", "reduced_motion"))


func _build_controls(page: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	page.add_child(head)
	for key in ["controls.action", "controls.keyboard", "controls.gamepad"]:
		var title := _cell(UIText.t(key), "LabelSection")
		title.uppercase = true
		head.add_child(title)
	for row_name in CONTROL_ROWS:
		var row := HBoxContainer.new()
		page.add_child(row)
		row.add_child(_cell(UIText.t("controls.%s.action" % row_name), "LabelBody"))
		row.add_child(_cell(UIText.t("controls.%s.keyboard" % row_name), "LabelDim"))
		row.add_child(_cell(UIText.t("controls.%s.gamepad" % row_name), "LabelDim"))


func _cell(text: String, style: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = style
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = 1.0
	return l


## A checkbox bound to one yes-or-no setting.
func _check(key: String, property: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = UIText.t(key)
	c.button_pressed = settings.get(property)
	c.custom_minimum_size.y = UITokens.HIT
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.toggled.connect(_set_flag.bind(property))
	return c


func _set_flag(on: bool, property: String) -> void:
	settings.set(property, on)
	changed.emit()


func _set_ai_speed(index: int) -> void:
	settings.ai_speed_index = index
	changed.emit()


func _change_text_size(step: int) -> void:
	settings.text_scale_index = clampi(settings.text_scale_index + step, 0, UISettings.TEXT_SCALES.size() - 1)
	_show_text_size()
	changed.emit()


func _show_text_size() -> void:
	_size_value.text = UIText.t("settings.text_percent", [roundi(settings.text_scale() * 100.0)])
