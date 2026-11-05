class_name GameRoot
extends Control
## The game screen: top bar, board, bottom action bar and side panel.
##
## This script is the interface's controller. It never changes game rules or state itself: it
## asks the [Battle] to do things (cmd_*), shows the answers, and plays back the plain-data
## events the battle records. Anything it keeps (selection, a pending move) is presentation only.

const HUMAN := 0
const COMPACT_BELOW := 960.0
const PHASES: Array[String] = ["command", "movement", "shooting", "charge", "fight"]

var battle: Battle
var settings := UISettings.new()
var board: BoardView

# Presentation state
var _selected: UnitState
var _move_mode: String = "normal"
var _delta: Vector2 = Vector2.ZERO
var _target: UnitState
var _charge_targets: Array[UnitState] = []
var _verdict: Dictionary = {}
var _names: Dictionary = {}
var _event_cursor: int = 0
var _busy: bool = false
var _skip: bool = false
var _compact: bool = false
var _info_open: bool = false
var _game_over_shown: bool = false
var _log_lines: Array[String] = []
var _begun_key: String = ""

# Nodes
var _top_title: Label
var _phase_chips: Array[PanelContainer] = []
var _phase_labels: Array[Label] = []
var _score_you: Label
var _score_ai: Label
var _bottom_actions: HBoxContainer
var _next_button: Button
var _skip_button: Button
var _side: PanelContainer
var _orders_title: Label
var _orders_text: RichTextLabel
var _unit_text: RichTextLabel
var _log_text: RichTextLabel
var _info_button: Button
var _settings_panel: PanelContainer
var _over_panel: PanelContainer
var _over_text: Label
var _zoom_box: VBoxContainer
var _body: BoxContainer
var _portrait: bool = false
var skip_roster: bool = false    ## tests and tools set this to go straight to the placeholder battle
var _args: Dictionary = {}
var _armies_in_play: Array = []
var _roster: RosterScreen


func _ready() -> void:
	theme = UIThemeBuilder.build()
	settings.load_from_disk()
	_setup_input_actions()
	_args = _parse_args()
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()
	if skip_roster or _args.has("quick"):
		_start_battle(_placeholder_armies())
	else:
		_show_roster()


func _placeholder_armies() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]


## Army and unit selection comes first; the battle is built once it is confirmed.
func _show_roster() -> void:
	_roster = RosterScreen.new()
	add_child(_roster)
	_roster.setup(str(_args.get("armies", "")))
	_roster.started.connect(func(armies: Array) -> void:
		_roster.queue_free()
		_roster = null
		_start_battle(armies))


func _start_battle(armies: Array) -> void:
	_armies_in_play = armies
	_load_battle(armies, int(_args.get("seed", Time.get_ticks_msec() % 100000)))
	_build_ui()
	_apply_scale()
	board.battle = battle
	board.settings = settings
	board.unit_tapped.connect(_on_unit_tapped)
	board.empty_tapped.connect(_on_empty_tapped)
	board.drag_moved.connect(_on_drag_moved)
	board.drag_ended.connect(_on_drag_ended)
	board.drag_cancelled.connect(_on_drag_cancelled)
	_begin_turn_once()
	_consume_events()
	_refresh()
	board.grab_focus()


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < user_args.size():
		if user_args[i].begins_with("--") and i + 1 < user_args.size() and not user_args[i + 1].begins_with("--"):
			out[user_args[i].substr(2)] = user_args[i + 1]
			i += 2
		else:
			out[user_args[i].substr(2)] = "1"
			i += 1
	return out


func _load_battle(armies: Array, seed_value: int) -> void:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	battle = Battle.new(sc, armies, seed_value)
	battle.ai_sides = [false, true]
	_names.clear()
	for u in battle.units:
		_names[u.id] = u.unit_name
	_event_cursor = 0
	_log_lines.clear()
	_game_over_shown = false


# ---------------------------------------------------------------- input actions

func _setup_input_actions() -> void:
	_add_action("cycle_next", [_key(KEY_BRACKETRIGHT), _pad_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("cycle_prev", [_key(KEY_BRACKETLEFT), _pad_button(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("confirm_order", [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad_button(JOY_BUTTON_X)])
	_add_action("cancel_order", [_key(KEY_ESCAPE), _pad_button(JOY_BUTTON_B)])
	_add_action("next_phase", [_key(KEY_N), _pad_button(JOY_BUTTON_Y)])
	_add_action("nudge_left", [_key(KEY_LEFT), _pad_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("nudge_right", [_key(KEY_RIGHT), _pad_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("nudge_up", [_key(KEY_UP), _pad_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("nudge_down", [_key(KEY_DOWN), _pad_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("zoom_in", [_key(KEY_EQUAL), _key(KEY_KP_ADD)])
	_add_action("zoom_out", [_key(KEY_MINUS), _key(KEY_KP_SUBTRACT)])


func _add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


func _pad_button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		if event.is_action_pressed("cancel_order") or event.is_action_pressed("confirm_order"):
			_skip = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next_phase"):
		_on_next_pressed()
	elif event.is_action_pressed("confirm_order"):
		_on_confirm_pressed()
	elif event.is_action_pressed("cancel_order"):
		if _settings_panel.visible:
			_set_settings_visible(false)
		else:
			_on_cancel_pressed()
	elif event.is_action_pressed("cycle_next"):
		_cycle_unit(1)
	elif event.is_action_pressed("cycle_prev"):
		_cycle_unit(-1)
	elif event.is_action_pressed("zoom_in"):
		board.zoom_by(1.25)
	elif event.is_action_pressed("zoom_out"):
		board.zoom_by(0.8)
	else:
		for pair in [["nudge_left", Vector2(-1, 0)], ["nudge_right", Vector2(1, 0)], ["nudge_up", Vector2(0, -1)], ["nudge_down", Vector2(0, 1)]]:
			if event.is_action_pressed(pair[0]):
				_nudge(pair[1] * 0.25)
				return


# ---------------------------------------------------------------- layout

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_top_bar())

	var body := BoxContainer.new()
	_body = body
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	var board_col := VBoxContainer.new()
	board_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_col.add_theme_constant_override("separation", 0)
	body.add_child(board_col)

	var board_holder := Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_col.add_child(board_holder)
	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_holder.add_child(board)
	_zoom_box = _build_zoom_box()
	board_holder.add_child(_zoom_box)

	board_col.add_child(_build_bottom_bar())

	_side = _build_side_panel()
	body.add_child(_side)

	_settings_panel = _build_settings_panel()
	add_child(_settings_panel)
	_over_panel = _build_over_panel()
	add_child(_over_panel)


func _build_top_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	bar.custom_minimum_size.y = UITokens.TOP_BAR
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SPACE_4)
	bar.add_child(row)

	_top_title = Label.new()
	_top_title.add_theme_font_size_override("font_size", UITokens.TEXT_BODY)
	_top_title.custom_minimum_size.x = 160
	row.add_child(_top_title)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", UITokens.SPACE_1)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chips)
	for p in PHASES:
		var chip := PanelContainer.new()
		var lab := Label.new()
		lab.text = UIText.t("phase." + p)
		lab.add_theme_font_size_override("font_size", UITokens.TEXT_SECONDARY)
		chip.add_child(lab)
		chips.add_child(chip)
		_phase_chips.append(chip)
		_phase_labels.append(lab)

	_score_you = Label.new()
	_score_ai = Label.new()
	row.add_child(_score_block(_score_you, 0))
	row.add_child(_score_block(_score_ai, 1))

	_info_button = _button(UIText.t("button.info"), _toggle_info)
	row.add_child(_info_button)
	row.add_child(_button(UIText.t("button.settings"), func() -> void: _set_settings_visible(true)))
	return bar


func _score_block(label: Label, side: int) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITokens.RAISED
	style.border_color = UITokens.SIDE_COLOURS[side]
	style.border_width_left = 4
	style.set_corner_radius_all(UITokens.RADIUS)
	style.content_margin_left = UITokens.SPACE_3
	style.content_margin_right = UITokens.SPACE_3
	style.content_margin_top = UITokens.SPACE_1
	style.content_margin_bottom = UITokens.SPACE_1
	box.add_theme_stylebox_override("panel", style)
	label.add_theme_font_size_override("font_size", UITokens.TEXT_SECONDARY)
	box.add_child(label)
	return box


func _build_bottom_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	bar.custom_minimum_size.y = UITokens.BOTTOM_BAR
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SPACE_2)
	bar.add_child(row)
	_bottom_actions = HBoxContainer.new()
	_bottom_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_actions.add_theme_constant_override("separation", UITokens.SPACE_2)
	row.add_child(_bottom_actions)
	_skip_button = _button(UIText.t("button.skip"), func() -> void: _skip = true)
	_skip_button.visible = false
	row.add_child(_skip_button)
	_next_button = _button("", _on_next_pressed, true)
	row.add_child(_next_button)
	return bar


func _build_zoom_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -UITokens.SPACE_3
	box.offset_bottom = -UITokens.SPACE_3
	box.add_theme_constant_override("separation", UITokens.SPACE_1)
	for spec in [["+", UIText.t("tip.zoom_in"), func() -> void: board.zoom_by(1.25)],
			["−", UIText.t("tip.zoom_out"), func() -> void: board.zoom_by(0.8)],
			["⌂", UIText.t("tip.zoom_fit"), func() -> void: board.reset_view()]]:
		var b := _button(spec[0], spec[2])
		b.tooltip_text = spec[1]
		b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
		box.add_child(b)
	return box


func _build_side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = UITokens.SIDE_PANEL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UITokens.SPACE_3)
	scroll.add_child(col)

	_orders_title = Label.new()
	_orders_title.add_theme_font_size_override("font_size", UITokens.TEXT_HEADING)
	_orders_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_orders_title)
	_orders_text = _rich()
	col.add_child(_orders_text)
	col.add_child(HSeparator.new())

	var unit_title := Label.new()
	unit_title.text = UIText.t("panel.unit")
	unit_title.add_theme_font_size_override("font_size", UITokens.TEXT_BODY)
	col.add_child(unit_title)
	_unit_text = _rich()
	col.add_child(_unit_text)
	col.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = UIText.t("panel.log")
	log_title.add_theme_font_size_override("font_size", UITokens.TEXT_BODY)
	col.add_child(log_title)
	_log_text = _rich()
	_log_text.custom_minimum_size.y = 160
	col.add_child(_log_text)
	return panel


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _button(text: String, handler: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(handler)
	return b


func _build_settings_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(400, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITokens.SPACE_3)
	p.add_child(col)
	var title := Label.new()
	title.text = UIText.t("settings.title")
	title.add_theme_font_size_override("font_size", UITokens.TEXT_HEADING)
	col.add_child(title)

	var size_row := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = UIText.t("settings.text_size")
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_label)
	size_row.add_child(_button("A−", func() -> void: _change_text_size(-1)))
	size_row.add_child(_button("A+", func() -> void: _change_text_size(1)))
	col.add_child(size_row)

	col.add_child(_check(UIText.t("settings.colour_blind"), settings.colour_blind, func(on: bool) -> void:
		settings.colour_blind = on
		_settings_changed()))
	col.add_child(_check(UIText.t("settings.reduced_motion"), settings.reduced_motion, func(on: bool) -> void:
		settings.reduced_motion = on
		_settings_changed()))
	col.add_child(_check(UIText.t("settings.engagement"), settings.show_engagement, func(on: bool) -> void:
		settings.show_engagement = on
		_settings_changed()))
	col.add_child(_check(UIText.t("settings.coherency"), settings.show_coherency, func(on: bool) -> void:
		settings.show_coherency = on
		_settings_changed()))
	col.add_child(_check(UIText.t("settings.objectives"), settings.show_objectives, func(on: bool) -> void:
		settings.show_objectives = on
		_settings_changed()))
	col.add_child(_button(UIText.t("button.close"), func() -> void: _set_settings_visible(false), true))
	return p


func _check(text: String, value: bool, handler: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size.y = UITokens.HIT
	c.toggled.connect(handler)
	return c


func _build_over_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(420, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITokens.SPACE_3)
	p.add_child(col)
	var title := Label.new()
	title.text = UIText.t("over.title")
	title.add_theme_font_size_override("font_size", UITokens.TEXT_TITLE)
	col.add_child(title)
	_over_text = Label.new()
	_over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_text.add_theme_font_size_override("font_size", UITokens.TEXT_BODY)
	col.add_child(_over_text)
	col.add_child(_button(UIText.t("button.play_again"), _restart, true))
	return p


func _set_settings_visible(on: bool) -> void:
	_settings_panel.visible = on
	if not on:
		settings.save_to_disk()
		board.grab_focus()


func _change_text_size(step: int) -> void:
	settings.text_scale_index = clampi(settings.text_scale_index + step, 0, UISettings.TEXT_SCALES.size() - 1)
	_settings_changed()


func _settings_changed() -> void:
	board.settings = settings
	_apply_scale()
	_refresh()


func _toggle_info() -> void:
	_info_open = not _info_open
	_apply_scale()


## Scale the whole interface with the window and the player's text size, and switch to the
## compact layout (side panel behind a button) when the logical width is small.
func _apply_scale() -> void:
	var win: Window = get_window()
	# The window is measured in device pixels. Work out the size in CSS/point units first, so a
	# 48-unit button stays about 48 points across on a 2x tablet as well as a 1x monitor.
	var dpr: float = maxf(1.0, DisplayServer.screen_get_scale())
	var css_w: float = float(win.size.x) / dpr
	var css_h: float = float(win.size.y) / dpr
	var base: float = clampf(minf(css_w / 1280.0, css_h / 800.0), 1.0, 2.0)
	var factor: float = base * dpr * settings.text_scale()
	# Make the stretch base equal to the window so only our own factor scales the interface.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if win.content_scale_size != win.size:
		win.content_scale_size = win.size
	win.content_scale_factor = factor
	var logical_width: float = float(win.size.x) / factor
	var logical_height: float = float(win.size.y) / factor
	_portrait = logical_height > logical_width * 1.1
	_compact = logical_width < COMPACT_BELOW
	if _body == null:
		return    # still on the roster screen
	_body.vertical = _portrait
	if _portrait:
		# Portrait tablet: the board on top, the explanation panel docked below it.
		_info_button.visible = false
		_side.visible = true
		_side.custom_minimum_size = Vector2(0, logical_height * 0.36)
		_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_info_button.visible = _compact
		_side.visible = (not _compact) or _info_open
		_side.size_flags_horizontal = Control.SIZE_FILL
		_side.custom_minimum_size = Vector2(minf(UITokens.SIDE_PANEL, logical_width * 0.5) if _compact else UITokens.SIDE_PANEL, 0)
	board.queue_redraw()


# ---------------------------------------------------------------- selection and input handlers

func _own_active() -> bool:
	return battle.active_player() == HUMAN and not _busy and not battle.is_over()


func _on_unit_tapped(u: UnitState) -> void:
	if _busy:
		return
	var phase: String = battle.phase()
	if u.owner == HUMAN:
		if phase == "fight" and battle.fight_stage == "fight" and battle.fight_chooser() == HUMAN \
				and not battle.fight_options().has(u):
			_selected = u
		else:
			_select(u)
	else:
		_on_enemy_tapped(u)
	_refresh()


func _on_empty_tapped(_world: Vector2) -> void:
	_clear_selection()
	_refresh()


func _select(u: UnitState) -> void:
	_selected = u
	_delta = Vector2.ZERO
	_target = null
	_verdict = {}
	_charge_targets.clear()
	_move_mode = "fall_back" if UnitRules.engaged(u, battle.units) else "normal"


func _clear_selection() -> void:
	_selected = null
	_delta = Vector2.ZERO
	_target = null
	_verdict = {}
	_charge_targets.clear()


func _on_enemy_tapped(e: UnitState) -> void:
	if _selected == null:
		_selected = e
		return
	match battle.phase():
		"shooting", "fight":
			if _selected.owner == HUMAN:
				_target = e
		"charge":
			if _selected.owner == HUMAN and battle.charge_state(_selected).has("targets"):
				if _charge_targets.has(e):
					_charge_targets.erase(e)
				elif (battle.charge_state(_selected)["targets"] as Array).has(e):
					_charge_targets.append(e)
				_update_ghost_verdict()
		_:
			_selected = e


func _cycle_unit(step: int) -> void:
	var mine: Array = battle.living(HUMAN)
	if mine.is_empty():
		return
	var i: int = mine.find(_selected)
	i = (i + step + mine.size()) % mine.size() if i >= 0 else 0
	_select(mine[i])
	_refresh()


func _on_drag_moved(u: UnitState, delta: Vector2) -> void:
	_delta = _clamped(u, delta)
	_update_ghost_verdict()
	_refresh()


func _on_drag_cancelled() -> void:
	_delta = Vector2.ZERO
	_verdict = {}
	_refresh()


func _on_drag_ended(_u: UnitState, _delta_in: Vector2) -> void:
	_refresh()


func _nudge(step: Vector2) -> void:
	if _selected == null or _selected.owner != HUMAN or not _can_drag():
		return
	_delta = _clamped(_selected, _delta + step)
	_update_ghost_verdict()
	_refresh()


## The longest move allowed for the current order, in inches.
func _allowed_distance(u: UnitState) -> float:
	match battle.phase():
		"movement":
			var roll: int = battle.advance_roll_for(u)
			return u.move + (float(roll) if _move_mode == "advance" and roll > 0 else 0.0)
		"charge":
			return float(battle.charge_state(u).get("roll", 0))
		"fight":
			return MeleeMoves.MAX_MOVE
	return 0.0


func _clamped(u: UnitState, d: Vector2) -> Vector2:
	var limit: float = _allowed_distance(u)
	return d.limit_length(limit)


func _can_drag() -> bool:
	if _selected == null or _selected.owner != HUMAN or not _own_stage_active():
		return false
	match battle.phase():
		"movement":
			return not battle.has_moved(_selected)
		"charge":
			return battle.charge_state(_selected).has("roll") and not battle.charge_finished(_selected)
		"fight":
			if battle.fight_stage == "pile_in":
				return battle.can_pile_in(_selected)
			if battle.fight_stage == "consolidate":
				return battle.can_consolidate(_selected)
	return false


func _own_stage_active() -> bool:
	if battle.phase() == "fight":
		return not _busy and not battle.is_over()
	return _own_active()


func _ghost_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _selected == null:
		return out
	for m in _selected.models:
		out.append(m["pos"] + _delta)
	return out


func _update_ghost_verdict() -> void:
	_verdict = {}
	if _selected == null or _delta.length() < 0.01:
		return
	var ghost: Array[Vector2] = _ghost_positions()
	match battle.phase():
		"movement":
			_verdict = battle.preview_move(_selected, ghost, _move_mode)
		"charge":
			var targets: Array[UnitState] = _charge_targets.duplicate()
			if targets.is_empty():
				_verdict = {"ok": false, "reason": UIText.t("hint.pick_charge_target")}
			else:
				_verdict = battle.preview_charge(_selected, ghost, targets)
		"fight":
			if battle.fight_stage == "pile_in":
				_verdict = battle.preview_pile_in(_selected, ghost)
			elif battle.fight_stage == "consolidate":
				_verdict = battle.preview_consolidate(_selected, ghost)


# ---------------------------------------------------------------- buttons

func _on_confirm_pressed() -> void:
	if _selected == null or not _own_stage_active():
		return
	var ghost: Array[Vector2] = _ghost_positions()
	var r: Dictionary = {}
	match battle.phase():
		"movement":
			r = battle.cmd_move(_selected, ghost, _move_mode)
		"charge":
			var targets: Array[UnitState] = _charge_targets.duplicate()
			r = battle.cmd_charge_move(_selected, ghost, targets)
		"fight":
			if battle.fight_stage == "pile_in":
				r = battle.cmd_pile_in(_selected, ghost)
			elif battle.fight_stage == "consolidate":
				r = battle.cmd_consolidate(_selected, ghost)
	if r.is_empty():
		return
	_verdict = r
	if r["ok"]:
		_delta = Vector2.ZERO
		_consume_events()
	_refresh()


func _on_cancel_pressed() -> void:
	_delta = Vector2.ZERO
	_verdict = {}
	if _target != null:
		_target = null
	elif _selected != null and _delta == Vector2.ZERO:
		_selected = null
	_refresh()


func _set_mode(mode: String) -> void:
	_move_mode = mode
	if mode == "advance" and _selected != null and battle.advance_roll_for(_selected) < 0:
		battle.cmd_roll_advance(_selected)
		_consume_events()
	_delta = _clamped(_selected, _delta) if _selected != null else Vector2.ZERO
	_update_ghost_verdict()
	_refresh()


func _on_hold_pressed() -> void:
	if _selected != null:
		battle.cmd_hold(_selected)
		_delta = Vector2.ZERO
		_consume_events()
		_refresh()


func _on_fire_pressed() -> void:
	if _selected == null or _target == null:
		return
	var r: Dictionary = battle.cmd_shoot(_selected, _target)
	_verdict = r
	if r["ok"]:
		await _play_new_events()
		_target = null
	_refresh()


func _on_declare_pressed() -> void:
	if _selected == null:
		return
	var r: Dictionary = battle.cmd_declare_charge(_selected)
	_verdict = r
	_charge_targets.clear()
	if r["ok"]:
		for t in r["targets"]:
			_charge_targets.append(t)
		_consume_events()
	_refresh()


func _on_give_up_pressed() -> void:
	if _selected != null:
		battle.cmd_charge_fail(_selected)
		_delta = Vector2.ZERO
		_consume_events()
		_refresh()


func _on_suggest_pressed() -> void:
	if _selected == null:
		return
	var best: float = 0.0
	var goal: Vector2 = _nearest_enemy_centre(_selected)
	var dir: Vector2 = (goal - _selected.centre()).normalized()
	var limit: float = _allowed_distance(_selected)
	var d: float = limit
	while d > 0.2:
		_delta = dir * d
		_update_ghost_verdict()
		if _verdict.get("ok", false):
			best = d
			break
		d -= 0.25
	if best == 0.0:
		_delta = dir * limit
		_update_ghost_verdict()
	_refresh()


func _nearest_enemy_centre(u: UnitState) -> Vector2:
	var best: Vector2 = u.centre()
	var best_d: float = INF
	for o in battle.units:
		if o.owner != u.owner:
			var d: float = u.gap_to(o)
			if d < best_d:
				best_d = d
				best = o.centre()
	return best


func _on_fight_pressed() -> void:
	if _selected == null or _target == null:
		return
	var r: Dictionary = battle.cmd_fight(_selected, _target)
	_verdict = r
	if r["ok"]:
		await _play_new_events()
		_target = null
		_selected = null
		await _continue_after_human_action()
	_refresh()


func _on_skip_fight_pressed() -> void:
	if _selected == null:
		return
	var r: Dictionary = battle.cmd_fight_skip(_selected)
	_verdict = r
	if r["ok"]:
		_selected = null
		_consume_events()
		await _continue_after_human_action()
	_refresh()


func _on_next_pressed() -> void:
	if _busy or battle.is_over():
		return
	if battle.active_player() != HUMAN and not _human_can_act_in_ai_turn():
		return
	var r: Dictionary = battle.next_phase()
	_verdict = r
	_clear_selection()
	_consume_events()
	if r["ok"]:
		await _after_human_phase_change()
	_refresh()


## After the human ends a phase (or the step in the AI's turn), carry on until input is needed.
func _after_human_phase_change() -> void:
	await _run_until_human_input()


func _continue_after_human_action() -> void:
	await _run_until_human_input()


func _restart() -> void:
	_over_panel.visible = false
	_load_battle(_armies_in_play, Time.get_ticks_msec() % 100000)
	board.battle = battle
	_clear_selection()
	_begun_key = ""
	_begin_turn_once()
	_consume_events()
	_refresh()


# ---------------------------------------------------------------- AI turns and event playback

func _human_can_act_in_ai_turn() -> bool:
	if battle.phase() != "fight":
		return false
	if battle.fight_stage == "fight":
		return battle.fight_chooser() == HUMAN
	return true


## Run AI steps until the human has something to do (their turn, or a choice in the AI's turn).
func _run_until_human_input() -> void:
	var guard: int = 0
	while guard < 200 and not battle.is_over():
		guard += 1
		if battle.active_player() == HUMAN:
			if battle.phase() == "command":
				_begin_turn_once()
				_consume_events()
			_set_busy(false)
			return
		# AI's turn
		_set_busy(true)
		var p: String = battle.phase()
		if p == "command":
			_begin_turn_once()
			await _play_new_events()
			battle.next_phase()
		elif p == "movement" or p == "shooting" or p == "charge":
			battle.ai_run_phase()
			await _play_new_events()
			battle.next_phase()
			await _play_new_events()
		elif p == "fight":
			if battle.fight_stage == "pile_in":
				if _has_human_piles():
					_set_busy(false)
					return
				battle.next_phase()
			elif battle.fight_stage == "fight":
				if battle.fight_chooser() == HUMAN:
					_set_busy(false)
					return
				if battle.fight_chooser() < 0 or battle.fight_finished():
					var nxt: Dictionary = battle.next_phase()
					if not nxt["ok"]:
						break
				else:
					battle.ai_fight_step()
					await _play_new_events()
			elif battle.fight_stage == "consolidate":
				if _has_human_consolidations():
					_set_busy(false)
					return
				battle.next_phase()
				await _play_new_events()
		_refresh_board_only()
	_set_busy(false)
	if battle.is_over():
		_show_game_over()


## Resolve the command phase once per player turn (the battle does not do it on its own).
func _begin_turn_once() -> void:
	var key: String = "%d_%d" % [battle.flow.round_no, battle.active_player()]
	if key == _begun_key or battle.is_over():
		return
	_begun_key = key
	battle.begin_turn()


func _has_human_piles() -> bool:
	for u in battle.living(HUMAN):
		if battle.can_pile_in(u):
			return true
	return false


func _has_human_consolidations() -> bool:
	for u in battle.living(HUMAN):
		if battle.can_consolidate(u):
			return true
	return false


func _set_busy(on: bool) -> void:
	_busy = on
	_skip = false
	_skip_button.visible = on
	_refresh()


func _consume_events() -> void:
	## Take new events into the log without playing them (human actions are shown directly).
	while _event_cursor < battle.events.size():
		_log_event(battle.events[_event_cursor])
		_event_cursor += 1


func _play_new_events() -> void:
	var batch: Array[Dictionary] = []
	while _event_cursor < battle.events.size():
		batch.append(battle.events[_event_cursor])
		_event_cursor += 1
	# Hold units that move in this batch at their starting positions until their move plays.
	for e in batch:
		if e.has("from") and not board.anim_positions.has(e["unit"]):
			board.anim_positions[e["unit"]] = e["from"]
	board.queue_redraw()
	for e in batch:
		_log_event(e)
		await _animate(e)
	board.anim_positions.clear()
	board.queue_redraw()


func _animate(e: Dictionary) -> void:
	var instant: bool = _skip or settings.reduced_motion
	match str(e["type"]):
		"move", "charge_move", "pile_in", "consolidate":
			var from: Array = e["from"]
			var to: Array = e["to"]
			if instant:
				board.anim_positions[e["unit"]] = to
				board.queue_redraw()
				return
			var tw: Tween = create_tween()
			var step := func(t: float) -> void:
				var cur: Array[Vector2] = []
				for i in range(from.size()):
					cur.append((from[i] as Vector2).lerp(to[i], t))
				board.anim_positions[e["unit"]] = cur
				board.queue_redraw()
			tw.tween_method(step, 0.0, 1.0, 0.35)
			await tw.finished
		"shoot", "fight":
			var a: UnitState = battle.unit_by_id(e["unit"])
			var d: UnitState = battle.unit_by_id(e["target"])
			if a != null and d != null:
				board.flash(a.centre(), d.centre(), UITokens.SIDE_COLOURS[a.owner], 0.0 if instant else 0.7)
			if not instant:
				await get_tree().create_timer(0.55).timeout
		"turn_start", "score", "charge_roll", "advance_roll":
			if not instant:
				await get_tree().create_timer(0.25).timeout


func _log_event(e: Dictionary) -> void:
	var line: String = ""
	var side_word: String = UIText.t("side.you") if int(e["side"]) == HUMAN else UIText.t("side.ai")
	var who: String = str(_names.get(e.get("unit", ""), ""))
	match str(e["type"]):
		"turn_start":
			line = UIText.t("log.turn_start", [UIText.t("side.you_turn") if int(e["side"]) == HUMAN else UIText.t("side.ai_turn"), int(e["round"])])
			for sid in e["shocked"]:
				line += "\n" + UIText.t("log.shocked", [str(_names.get(sid, sid))])
		"phase":
			line = ""
		"move":
			line = UIText.t("log.move." + str(e["mode"]), [side_word, who])
		"hold":
			line = UIText.t("log.hold", [side_word, who])
		"advance_roll":
			line = UIText.t("log.advance_roll", [who, int(e["roll"])])
		"shoot":
			line = UIText.t("log.shoot", [side_word, who, str(_names.get(e["target"], "?")), _damage_of(e), _models_of(e)])
		"fight":
			line = UIText.t("log.fight", [side_word, who, str(_names.get(e["target"], "?")), _damage_of(e), _models_of(e)])
		"fight_skipped":
			line = UIText.t("log.fight_skipped", [who])
		"charge_roll":
			line = UIText.t("log.charge_roll", [who, int(e["roll"])])
		"charge_move":
			line = UIText.t("log.charge_move", [who])
		"charge_failed":
			line = UIText.t("log.charge_failed", [who])
		"pile_in":
			line = UIText.t("log.pile_in", [who])
		"consolidate":
			line = UIText.t("log.consolidate", [who])
		"destroyed":
			line = UIText.t("log.destroyed", [str(_names.get(e["unit"], "?"))])
		"score":
			line = UIText.t("log.score", [side_word, int(e["vp"]), int(e["objectives"])])
		"turn_end":
			line = ""
	if line != "":
		_log_lines.append(line)
		if _log_lines.size() > 60:
			_log_lines.pop_front()


func _damage_of(e: Dictionary) -> int:
	var total: int = 0
	for r in e["reports"]:
		total += int(r["damage"]) + int(r["mortal_wounds"])
	return total


func _models_of(e: Dictionary) -> int:
	var total: int = 0
	for r in e["reports"]:
		total += int(r["models_destroyed"])
	return total


func _show_game_over() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	var mine: int = battle.vp[HUMAN]
	var theirs: int = battle.vp[1 - HUMAN]
	var key: String = "over.win" if mine > theirs else ("over.lose" if mine < theirs else "over.draw")
	_over_text.text = UIText.t(key, [mine, theirs])
	_over_panel.visible = true


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	_refresh_top_bar()
	_refresh_bottom_bar()
	_refresh_side_panel()
	_refresh_board_only()
	if battle.is_over() and not _busy:
		_show_game_over()


func _refresh_board_only() -> void:
	board.selected = _selected
	board.ghost = _ghost_positions() if _delta.length() >= 0.01 else ([] as Array[Vector2])
	board.ghost_ok = bool(_verdict.get("ok", true))
	board.drag_enabled = _can_drag()
	board.ring_radius = 0.0
	board.highlights = {}
	board.los_line = []
	board.acted = _acted_units()
	if _selected != null and _selected.owner == HUMAN and _can_drag():
		board.ring_centre = _selected.centre()
		board.ring_radius = _allowed_distance(_selected)
	if _selected != null and _selected.owner == HUMAN:
		_mark_highlights()
	board.queue_redraw()


func _acted_units() -> Array:
	var out: Array = []
	for u in battle.living(HUMAN):
		match battle.phase():
			"movement":
				if battle.has_moved(u):
					out.append(u)
			"shooting":
				if battle.has_shot(u):
					out.append(u)
			"charge":
				if battle.charge_finished(u):
					out.append(u)
	return out


func _mark_highlights() -> void:
	var good: Color = UITokens.ACCENT
	match battle.phase():
		"shooting":
			for e in battle.living(1 - HUMAN):
				if not battle.shoot_preview(_selected, e).is_empty():
					board.highlights[e] = good
			if _target != null:
				board.highlights[_target] = UITokens.TEXT
				board.los_line = [_selected.centre(), _target.centre()]
				board.los_blocked = battle.shoot_preview(_selected, _target).is_empty()
		"charge":
			var cs: Dictionary = battle.charge_state(_selected)
			for t in cs.get("targets", []):
				board.highlights[t] = good if not _charge_targets.has(t) else UITokens.TEXT
		"fight":
			if battle.fight_stage == "fight":
				for e in battle.living(1 - HUMAN):
					if _selected.gap_to(e) <= UnitRules.ENGAGEMENT_RANGE:
						board.highlights[e] = good if e != _target else UITokens.TEXT


func _refresh_top_bar() -> void:
	var round_no: int = battle.flow.round_no
	var who: String = UIText.t("side.you_turn") if battle.active_player() == HUMAN else UIText.t("side.ai_turn")
	_top_title.text = UIText.t("hud.round_turn", [round_no, who])
	var current: int = PHASES.find(battle.phase())
	for i in range(PHASES.size()):
		var on: bool = i == current
		var style := StyleBoxFlat.new()
		style.bg_color = UITokens.ACCENT_DIM if on else Color(0, 0, 0, 0)
		style.border_color = UITokens.ACCENT if on else Color(0, 0, 0, 0)
		style.set_border_width_all(1)
		style.set_corner_radius_all(UITokens.RADIUS)
		style.content_margin_left = UITokens.SPACE_2
		style.content_margin_right = UITokens.SPACE_2
		style.content_margin_top = UITokens.SPACE_1
		style.content_margin_bottom = UITokens.SPACE_1
		_phase_chips[i].add_theme_stylebox_override("panel", style)
		_phase_labels[i].add_theme_color_override("font_color", UITokens.TEXT if on else UITokens.TEXT_FAINT)
		_phase_labels[i].visible = (not _compact) or on
	_score_you.text = UIText.t("hud.score", [UIText.t("side.you"), battle.flow.command_points[HUMAN], battle.vp[HUMAN]])
	_score_ai.text = UIText.t("hud.score", [UIText.t("side.ai"), battle.flow.command_points[1 - HUMAN], battle.vp[1 - HUMAN]])


func _refresh_bottom_bar() -> void:
	for c in _bottom_actions.get_children():
		c.queue_free()
	_next_button.text = _next_label()
	_next_button.disabled = _busy or battle.is_over() or not (battle.active_player() == HUMAN or _human_can_act_in_ai_turn())
	if _busy or battle.is_over():
		return
	if _selected == null or _selected.owner != HUMAN:
		var hint := Label.new()
		hint.text = UIText.t("hint.select_unit")
		hint.add_theme_color_override("font_color", UITokens.TEXT_DIM)
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bottom_actions.add_child(hint)
		return
	match battle.phase():
		"movement":
			_build_movement_actions()
		"shooting":
			_build_shooting_actions()
		"charge":
			_build_charge_actions()
		"fight":
			_build_fight_actions()


func _next_label() -> String:
	if battle.is_over():
		return UIText.t("next.over")
	if battle.phase() == "fight":
		match battle.fight_stage:
			"pile_in":
				return UIText.t("next.begin_fights")
			"fight":
				return UIText.t("next.consolidate")
			_:
				return UIText.t("next.end_turn")
	var i: int = PHASES.find(battle.phase())
	return UIText.t("next." + PHASES[mini(i + 1, PHASES.size() - 1)])


func _build_movement_actions() -> void:
	if battle.has_moved(_selected):
		_bottom_actions.add_child(_dim_label(UIText.t("hint.already_moved")))
		return
	var engaged: bool = UnitRules.engaged(_selected, battle.units)
	if engaged:
		_bottom_actions.add_child(_mode_button(UIText.t("mode.fall_back"), "fall_back"))
	else:
		_bottom_actions.add_child(_mode_button(UIText.t("mode.normal"), "normal"))
		_bottom_actions.add_child(_mode_button(UIText.t("mode.advance"), "advance"))
	_bottom_actions.add_child(_button(UIText.t("button.hold"), _on_hold_pressed))
	var confirm: Button = _button(UIText.t("button.confirm_move"), _on_confirm_pressed, true)
	confirm.disabled = not bool(_verdict.get("ok", false)) or _delta.length() < 0.01
	_bottom_actions.add_child(confirm)
	_bottom_actions.add_child(_button(UIText.t("button.cancel"), _on_cancel_pressed))


func _mode_button(text: String, mode: String) -> Button:
	var b := _button(text, func() -> void: _set_mode(mode))
	b.toggle_mode = true
	b.button_pressed = _move_mode == mode
	return b


func _build_shooting_actions() -> void:
	if battle.has_shot(_selected):
		_bottom_actions.add_child(_dim_label(UIText.t("hint.already_shot")))
		return
	if _target == null:
		_bottom_actions.add_child(_dim_label(UIText.t("hint.pick_target")))
		return
	var fire: Button = _button(UIText.t("button.fire"), _on_fire_pressed, true)
	fire.disabled = battle.shoot_preview(_selected, _target).is_empty()
	_bottom_actions.add_child(fire)
	_bottom_actions.add_child(_button(UIText.t("button.cancel"), _on_cancel_pressed))


func _build_charge_actions() -> void:
	var cs: Dictionary = battle.charge_state(_selected)
	if cs.is_empty():
		var declare: Button = _button(UIText.t("button.declare_charge"), _on_declare_pressed, true)
		declare.disabled = not ChargeRules.eligible(_selected, battle.units)["ok"]
		_bottom_actions.add_child(declare)
		return
	if battle.charge_finished(_selected):
		_bottom_actions.add_child(_dim_label(UIText.t("hint.charge_done")))
		return
	_bottom_actions.add_child(_button(UIText.t("button.suggest"), _on_suggest_pressed))
	var confirm: Button = _button(UIText.t("button.confirm_charge"), _on_confirm_pressed, true)
	confirm.disabled = not bool(_verdict.get("ok", false)) or _delta.length() < 0.01
	_bottom_actions.add_child(confirm)
	_bottom_actions.add_child(_button(UIText.t("button.give_up"), _on_give_up_pressed))


func _build_fight_actions() -> void:
	match battle.fight_stage:
		"pile_in":
			if not battle.can_pile_in(_selected):
				_bottom_actions.add_child(_dim_label(UIText.t("hint.no_pile_in")))
				return
			_bottom_actions.add_child(_button(UIText.t("button.suggest"), _on_suggest_pressed))
			var c: Button = _button(UIText.t("button.confirm_pile_in"), _on_confirm_pressed, true)
			c.disabled = not bool(_verdict.get("ok", false)) or _delta.length() < 0.01
			_bottom_actions.add_child(c)
		"fight":
			if battle.fight_chooser() != HUMAN:
				_bottom_actions.add_child(_dim_label(UIText.t("hint.opponent_picks")))
				return
			if not battle.fight_options().has(_selected):
				_bottom_actions.add_child(_dim_label(UIText.t("hint.cannot_pick_yet")))
				return
			if _target == null:
				_bottom_actions.add_child(_dim_label(UIText.t("hint.pick_fight_target")))
				_bottom_actions.add_child(_button(UIText.t("button.skip_fight"), _on_skip_fight_pressed))
				return
			var f: Button = _button(UIText.t("button.fight"), _on_fight_pressed, true)
			f.disabled = battle.fight_preview(_selected, _target).is_empty()
			_bottom_actions.add_child(f)
		"consolidate":
			if not battle.can_consolidate(_selected):
				_bottom_actions.add_child(_dim_label(UIText.t("hint.no_consolidate")))
				return
			_bottom_actions.add_child(_button(UIText.t("button.suggest"), _on_suggest_pressed))
			var cc: Button = _button(UIText.t("button.confirm_consolidate"), _on_confirm_pressed, true)
			cc.disabled = not bool(_verdict.get("ok", false)) or _delta.length() < 0.01
			_bottom_actions.add_child(cc)


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITokens.TEXT_DIM)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ---------------------------------------------------------------- side panel text

func _refresh_side_panel() -> void:
	var phase: String = battle.phase()
	var key: String = phase if phase != "fight" else "fight_" + battle.fight_stage
	_orders_title.text = UIText.t("help.title." + key)
	var text: String = UIText.t("help.body." + key)
	if _busy:
		text = UIText.t("help.ai_playing")
	var extra: String = _orders_detail()
	if extra != "":
		text += "\n\n" + extra
	_orders_text.text = text
	_unit_text.text = _unit_card(_selected) if _selected != null else "[color=#a3acb9]" + UIText.t("hint.no_unit") + "[/color]"
	_log_text.text = "\n".join(_log_lines.slice(maxi(0, _log_lines.size() - 14)))


func _orders_detail() -> String:
	var out: String = ""
	if not _verdict.is_empty() and _delta.length() >= 0.01 or (not _verdict.is_empty() and not _verdict.get("ok", true)):
		if bool(_verdict.get("ok", false)):
			out += "[color=%s]%s[/color]" % [UITokens.legal(settings.colour_blind).to_html(false), UIText.t("verdict.legal")]
		else:
			out += "[color=%s]%s[/color] %s" % [UITokens.illegal(settings.colour_blind).to_html(false), UIText.t("verdict.illegal"), str(_verdict.get("reason", ""))]
	if _selected != null and _selected.owner == HUMAN:
		match battle.phase():
			"movement":
				if _can_drag():
					out += ("\n" if out != "" else "") + UIText.t("detail.move_range", [_allowed_distance(_selected)])
					if _move_mode == "advance" and battle.advance_roll_for(_selected) > 0:
						out += "\n" + UIText.t("detail.advance_roll", [battle.advance_roll_for(_selected)])
			"shooting":
				if _target != null:
					out += ("\n" if out != "" else "") + _odds_table(battle.shoot_preview(_selected, _target), _target)
			"charge":
				var cs: Dictionary = battle.charge_state(_selected)
				if cs.has("roll"):
					out += ("\n" if out != "" else "") + UIText.t("detail.charge_roll", [int(cs["roll"]), (cs["targets"] as Array).size()])
			"fight":
				if _target != null and battle.fight_stage == "fight":
					out += ("\n" if out != "" else "") + _odds_table(battle.fight_preview(_selected, _target), _target)
	return out


func _odds_table(preview: Array[Dictionary], target: UnitState) -> String:
	if preview.is_empty():
		return UIText.t("odds.none")
	var out: String = "[b]%s[/b] %s\n" % [UIText.t("odds.against"), target.unit_name]
	var total: float = 0.0
	for p in preview:
		var o: Dictionary = p["odds"]
		var w: Weapon = p["weapon"]
		var hit: String = UIText.t("odds.auto_hit") if bool(o["auto_hit"]) else UIText.t("odds.target", [int(o["hit_target"])])
		var save: String = _save_text(target, w)
		out += "[color=#e6e9ef]%s[/color] · %s\n" % [w.weapon_name, UIText.t("odds.models", [int(p["models"])])]
		out += "  %s  %s\n" % [UIText.t("odds.attacks", [o["attacks"]]), UIText.t("odds.hit", [hit])]
		out += "  %s  %s\n" % [UIText.t("odds.wound", [int(o["wound_target"])]), save]
		out += "  %s\n" % UIText.t("odds.expected", [o["expected_damage"], o["expected_models_destroyed"]])
		total += float(o["expected_damage"])
	if preview.size() > 1:
		out += UIText.t("odds.total", [total])
	return out


func _save_text(target: UnitState, w: Weapon) -> String:
	var modified: int = target.save - w.ap
	var best: String = UIText.t("odds.save", [clampi(modified, 2, 7)]) if modified <= 6 else UIText.t("odds.no_save")
	if target.invuln > 0 and (modified > target.invuln or modified > 6):
		return UIText.t("odds.invuln", [target.invuln])
	return best


func _unit_card(u: UnitState) -> String:
	var side: String = UIText.t("side.you") if u.owner == HUMAN else UIText.t("side.ai")
	var out: String = "[color=%s]%s[/color]  %s\n" % [UITokens.SIDE_COLOURS[u.owner].to_html(false), u.unit_name, side]
	out += "[color=#a3acb9]M[/color] %d\"  [color=#a3acb9]T[/color] %d  [color=#a3acb9]Sv[/color] %d+  [color=#a3acb9]W[/color] %d  [color=#a3acb9]Ld[/color] %d+  [color=#a3acb9]OC[/color] %d\n" % [
			int(u.move), u.toughness, u.save, u.wounds_per_model, u.leadership, u.objective_control]
	var extras: Array[String] = []
	if u.invuln > 0:
		extras.append(UIText.t("card.invuln", [u.invuln]))
	if u.fnp > 0:
		extras.append(UIText.t("card.fnp", [u.fnp]))
	if u.battle_shocked:
		extras.append(UIText.t("chip.shocked"))
	if not extras.is_empty():
		out += ", ".join(extras) + "\n"
	out += UIText.t("card.models", [u.model_count(), u.starting_strength]) + "\n"
	for w in u.weapons:
		out += "[color=#a3acb9]•[/color] %s: %s\n" % [w.weapon_name, _weapon_line(w)]
	return out


func _weapon_line(w: Weapon) -> String:
	var rng: String = UIText.t("card.melee") if w.is_melee() else "%d\"" % int(w.range_in)
	var line: String = UIText.t("card.weapon", [rng, w.attacks, w.skill, w.strength, -w.ap, w.damage])
	var names: Array[String] = []
	for a in w.abilities:
		var n: String = str(a["name"]).capitalize()
		if int(a["value"]) > 0:
			n += " %d" % int(a["value"])
		names.append(n)
	if not names.is_empty():
		line += " · " + ", ".join(names)
	return line
