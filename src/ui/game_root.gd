class_name GameRoot
extends Control
## The game screen: top bar, board, bottom action bar and side panel.
##
## This script is the interface's controller. It never changes game rules or state itself: it
## asks the [Battle] to do things (cmd_*), shows the answers, and plays back the plain-data
## events the battle records. Anything it keeps (selection, a pending move) is presentation only.

const HUMAN := 0
const COMPACT_BELOW := 960.0
const PHONE_BELOW := 520.0
const TINY_BELOW := 560.0
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
var _log_lines: Array[Dictionary] = []
var _begun_key: String = ""

# Nodes
var _top_bar: TopBar
var _phone_hud: PhoneHud
var _phone_col: PanelContainer
var _phone_box: VBoxContainer
var _action_bar: ActionBar
var _board_col: VBoxContainer
var _side: SidePanel
var _settings_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_vp: Array[Label] = []
var _settings_close: Button
var _play_again: Button
var _scrim: ColorRect
var _zoom_box: VBoxContainer
var _body: BoxContainer
var _portrait: bool = false
var _phone: bool = false
var skip_roster: bool = false    ## tests and tools set this to go straight to the placeholder battle
var skip_title: bool = false     ## tools set this to open on the roster
var battle_seed: int = -1         ## tools set this to repeat a game exactly
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
	elif skip_title:
		_show_roster()
	else:
		_show_title()


func _placeholder_armies() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]


func _show_title() -> void:
	var title := TitleScreen.new()
	add_child(title)
	title.start_pressed.connect(func() -> void:
		title.queue_free()
		_show_roster())


## Army and unit selection comes before the battle, which is built once it is confirmed.
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
	_load_battle(armies, battle_seed if battle_seed >= 0 else int(_args.get("seed", Time.get_ticks_msec() % 100000)))
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

	_top_bar = TopBar.new()
	_top_bar.info_pressed.connect(_toggle_info)
	_top_bar.settings_pressed.connect(func() -> void: _set_settings_visible(true))
	root.add_child(_top_bar)

	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	root.add_child(_body)

	_board_col = VBoxContainer.new()
	_board_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_col.add_theme_constant_override("separation", 0)
	_body.add_child(_board_col)

	var board_holder := Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_col.add_child(board_holder)
	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_holder.add_child(board)
	_zoom_box = _build_zoom_box()
	board_holder.add_child(_zoom_box)

	_action_bar = ActionBar.new()
	_action_bar.next_pressed.connect(_on_next_pressed)
	_action_bar.skip_pressed.connect(func() -> void: _skip = true)
	_board_col.add_child(_action_bar)

	_phone_col = PanelContainer.new()
	_phone_col.custom_minimum_size.x = UITokens.PHONE_COLUMN
	_phone_col.visible = false
	_body.add_child(_phone_col)
	_phone_box = VBoxContainer.new()
	_phone_col.add_child(_phone_box)
	_phone_hud = PhoneHud.new()
	_phone_hud.info_pressed.connect(_toggle_info)
	_phone_hud.settings_pressed.connect(func() -> void: _set_settings_visible(true))
	_phone_box.add_child(_phone_hud)

	_side = SidePanel.new()
	_body.add_child(_side)

	_scrim = ColorRect.new()
	_scrim.color = UITokens.with_alpha(UITokens.VOID, 0.72)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)
	_settings_panel = _build_settings_panel()
	add_child(_settings_panel)
	_over_panel = _build_over_panel()
	add_child(_over_panel)


func _build_zoom_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -UITokens.SPACE_3
	box.offset_bottom = -UITokens.SPACE_3
	box.add_theme_constant_override("separation", UITokens.SPACE_1)
	for spec in [["plus", UIText.t("tip.zoom_in"), func() -> void: board.zoom_by(1.25)],
			["minus", UIText.t("tip.zoom_out"), func() -> void: board.zoom_by(0.8)],
			["fit", UIText.t("tip.zoom_fit"), func() -> void: board.reset_view()]]:
		var b := _button("", spec[2])
		b.icon = UIIcons.get_icon(spec[0], UITokens.INK, 20)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = spec[1]
		box.add_child(b)
	return box


func _button(text: String, handler: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	if primary:
		b.theme_type_variation = "PrimaryButton"
		b.icon = UIIcons.stripe(UITokens.ON_ACTION)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(handler)
	return b


func _build_dialog(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Dialog"
	p.visible = false
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(width, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITokens.SPACE_3)
	p.add_child(col)
	return p


func _build_settings_panel() -> PanelContainer:
	var p := _build_dialog(420.0)
	var col: VBoxContainer = p.get_child(0)
	var title := Label.new()
	title.text = UIText.t("settings.title")
	title.theme_type_variation = "LabelHeading"
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
	_settings_close = _button(UIText.t("button.close"), func() -> void: _set_settings_visible(false), true)
	col.add_child(_settings_close)
	return p


func _check(text: String, value: bool, handler: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size.y = UITokens.HIT
	c.toggled.connect(handler)
	return c


func _build_over_panel() -> PanelContainer:
	var p := _build_dialog(460.0)
	var col: VBoxContainer = p.get_child(0)
	col.add_child(TopBar.make_wordmark("LabelWordmarkSmall"))
	_over_title = Label.new()
	_over_title.theme_type_variation = "LabelTitle"
	col.add_child(_over_title)
	var scores := HBoxContainer.new()
	scores.add_theme_constant_override("separation", UITokens.SPACE_6)
	col.add_child(scores)
	for side in range(2):
		var box := HBoxContainer.new()
		box.add_child(ShapeMark.new(side, 16.0))
		var who := Label.new()
		who.theme_type_variation = "LabelSection"
		who.uppercase = true
		who.text = UIText.t("side.you") if side == HUMAN else UIText.t("side.ai")
		box.add_child(who)
		var vp := Label.new()
		vp.theme_type_variation = "LabelReadout"
		box.add_child(vp)
		_over_vp.append(vp)
		scores.add_child(box)
	_play_again = _button(UIText.t("button.play_again"), _restart, true)
	col.add_child(_play_again)
	return p


func _set_settings_visible(on: bool) -> void:
	_settings_panel.visible = on
	_scrim.visible = on or _over_panel.visible
	if on:
		_settings_close.grab_focus()
	else:
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


## Scale the whole interface with the window and the player's text size, then pick a layout:
## wide (side panel beside the board), portrait (panel under the board), compact (panel behind a
## button) or phone (everything in a narrow right-hand column, so the board gets the height).
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
	_phone = not _portrait and logical_height < PHONE_BELOW
	if _body == null:
		return    # still on the title or roster screen
	_body.vertical = _portrait
	_top_bar.visible = not _phone
	_top_bar.set_density(_compact, logical_width < TINY_BELOW, _compact and not _portrait)
	_phone_col.visible = _phone
	_zoom_box.visible = not _phone
	var wanted_parent: Control = _phone_box if _phone else _board_col
	if _action_bar.get_parent() != wanted_parent:
		_action_bar.reparent(wanted_parent)
	_action_bar.set_phone(_phone)
	if _portrait:
		# Portrait: the board on top, the tabbed panel docked below it.
		_side.visible = true
		_side.custom_minimum_size = Vector2(0, logical_height * 0.36)
		_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_side.visible = (not _compact and not _phone) or _info_open
		_side.size_flags_horizontal = Control.SIZE_FILL
		_side.custom_minimum_size = Vector2(minf(UITokens.SIDE_PANEL, logical_width * 0.5) if (_compact or _phone) else UITokens.SIDE_PANEL, 0)
	if battle != null:
		_refresh()
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
	_scrim.visible = false
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


## Fight picks alternate, so the AI can have the next pick during the human's own turn.
func _ai_has_fight_pick() -> bool:
	return battle.phase() == "fight" and battle.fight_stage == "fight" \
			and battle.fight_chooser() >= 0 and battle.fight_chooser() != HUMAN


## Run AI steps until the human has something to do (their turn, or a choice in the AI's turn).
func _run_until_human_input() -> void:
	var guard: int = 0
	while guard < 200 and not battle.is_over():
		guard += 1
		if battle.active_player() == HUMAN and not _ai_has_fight_pick():
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
	_action_bar.set_busy(on)
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
			line = UIText.t("log.score_one" if int(e["objectives"]) == 1 else "log.score", [side_word, int(e["vp"]), int(e["objectives"])])
		"turn_end":
			line = ""
	if line != "":
		_log_lines.append({"text": line, "side": int(e["side"])})
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
	_over_title.text = UIText.t(key)
	_over_vp[HUMAN].text = str(mine)
	_over_vp[1 - HUMAN].text = str(theirs)
	_over_panel.visible = true
	_scrim.visible = true
	_play_again.grab_focus()


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	var total_rounds: int = int(battle.scenario.get("battle_rounds", 5))
	var round_no: int = battle.flow.round_no
	_top_bar.refresh(round_no, total_rounds, battle.active_player() == HUMAN, battle.phase(), battle.flow.command_points, battle.vp)
	_phone_hud.refresh(round_no, total_rounds, battle.phase(), battle.vp)
	_refresh_action_bar()
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
	match battle.phase():
		"shooting":
			for e in battle.living(1 - HUMAN):
				if not battle.shoot_preview(_selected, e).is_empty():
					board.highlights[e] = BoardView.MARK_IN_RANGE
			if _target != null:
				board.highlights[_target] = BoardView.MARK_TARGET
				board.los_line = [_selected.centre(), _target.centre()]
				board.los_blocked = battle.shoot_preview(_selected, _target).is_empty()
		"charge":
			var cs: Dictionary = battle.charge_state(_selected)
			for t in cs.get("targets", []):
				board.highlights[t] = BoardView.MARK_TARGET if _charge_targets.has(t) else BoardView.MARK_IN_RANGE
		"fight":
			if battle.fight_stage == "fight":
				for e in battle.living(1 - HUMAN):
					if _selected.gap_to(e) <= UnitRules.ENGAGEMENT_RANGE:
						board.highlights[e] = BoardView.MARK_TARGET if e == _target else BoardView.MARK_IN_RANGE


func _refresh_action_bar() -> void:
	var can_end: bool = battle.active_player() == HUMAN or _human_can_act_in_ai_turn()
	_action_bar.show_actions(_action_specs(), _next_label(), _busy or battle.is_over() or not can_end)


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


## What the action bar offers right now, as plain specs. See [ActionBar].
func _action_specs() -> Array[Dictionary]:
	if _busy or battle.is_over():
		return []
	if _selected == null or _selected.owner != HUMAN:
		if battle.phase() == "fight" and battle.fight_stage == "fight" and battle.fight_finished():
			return [_hint("hint.fights_done")]
		return [_hint("hint.select_unit")]
	match battle.phase():
		"movement":
			return _movement_actions()
		"shooting":
			return _shooting_actions()
		"charge":
			return _charge_actions()
		"fight":
			return _fight_actions()
	return []


func _hint(key: String) -> Dictionary:
	return {"hint": UIText.t(key)}


func _act(key: String, handler: Callable) -> Dictionary:
	return {"text": UIText.t(key), "handler": handler, "role": "normal"}


func _main(key: String, handler: Callable, disabled: bool) -> Dictionary:
	return {"text": UIText.t(key), "handler": handler, "role": "main", "disabled": disabled}


func _no_valid_move() -> bool:
	return not bool(_verdict.get("ok", false)) or _delta.length() < 0.01


func _mode(key: String, mode: String) -> Dictionary:
	return {"text": UIText.t(key), "handler": func() -> void: _set_mode(mode), "role": "option", "pressed": _move_mode == mode}


func _movement_actions() -> Array[Dictionary]:
	if battle.has_moved(_selected):
		return [_hint("hint.already_moved")]
	var out: Array[Dictionary] = []
	if UnitRules.engaged(_selected, battle.units):
		out.append(_mode("mode.fall_back", "fall_back"))
	else:
		out.append(_mode("mode.normal", "normal"))
		out.append(_mode("mode.advance", "advance"))
	out.append(_act("button.hold", _on_hold_pressed))
	out.append(_act("button.cancel", _on_cancel_pressed))
	out.append(_main("button.confirm_move", _on_confirm_pressed, _no_valid_move()))
	return out


func _shooting_actions() -> Array[Dictionary]:
	if battle.has_shot(_selected):
		return [_hint("hint.already_shot")]
	if _target == null:
		return [_hint("hint.pick_target")]
	return [_act("button.cancel", _on_cancel_pressed),
		_main("button.fire", _on_fire_pressed, battle.shoot_preview(_selected, _target).is_empty())]


func _charge_actions() -> Array[Dictionary]:
	var cs: Dictionary = battle.charge_state(_selected)
	if cs.is_empty():
		return [_main("button.declare_charge", _on_declare_pressed, not ChargeRules.eligible(_selected, battle.units)["ok"])]
	if battle.charge_finished(_selected):
		return [_hint("hint.charge_done")]
	return [_act("button.suggest", _on_suggest_pressed), _act("button.give_up", _on_give_up_pressed),
		_main("button.confirm_charge", _on_confirm_pressed, _no_valid_move())]


func _fight_actions() -> Array[Dictionary]:
	match battle.fight_stage:
		"pile_in":
			if not battle.can_pile_in(_selected):
				return [_hint("hint.no_pile_in")]
			return [_act("button.suggest", _on_suggest_pressed),
				_main("button.confirm_pile_in", _on_confirm_pressed, _no_valid_move())]
		"fight":
			if battle.fight_chooser() != HUMAN:
				return [_hint("hint.opponent_picks")]
			if not battle.fight_options().has(_selected):
				return [_hint("hint.cannot_pick_yet")]
			if _target == null:
				return [_hint("hint.pick_fight_target"), _act("button.skip_fight", _on_skip_fight_pressed)]
			return [_main("button.fight", _on_fight_pressed, battle.fight_preview(_selected, _target).is_empty())]
		"consolidate":
			if not battle.can_consolidate(_selected):
				return [_hint("hint.no_consolidate")]
			return [_act("button.suggest", _on_suggest_pressed),
				_main("button.confirm_consolidate", _on_confirm_pressed, _no_valid_move())]
	return []


# ---------------------------------------------------------------- side panel data

func _refresh_side_panel() -> void:
	var phase: String = battle.phase()
	var key: String = phase if phase != "fight" else "fight_" + battle.fight_stage
	var odds: Dictionary = _odds_view()
	var body: String = "" if not odds.is_empty() else UIText.t("help.body." + key)
	if _busy:
		body = UIText.t("help.ai_playing")
	_side.show_orders(UIText.t("help.title." + key), body, _orders_detail())
	_side.show_odds(odds)
	_side.show_unit(_unit_view(_selected) if _selected != null else {})
	_side.show_log(_log_lines)


func _orders_detail() -> String:
	var out: String = ""
	if not _verdict.is_empty() and _delta.length() >= 0.01 or (not _verdict.is_empty() and not _verdict.get("ok", true)):
		if bool(_verdict.get("ok", false)):
			out += "[color=#%s]%s[/color]" % [UITokens.legal(settings.colour_blind).to_html(false), UIText.t("verdict.legal")]
		else:
			out += "[color=#%s]%s[/color] %s" % [UITokens.illegal(settings.colour_blind).to_html(false), UIText.t("verdict.illegal"), str(_verdict.get("reason", ""))]
	if _selected != null and _selected.owner == HUMAN:
		match battle.phase():
			"movement":
				if _can_drag():
					out += ("\n" if out != "" else "") + UIText.t("detail.move_range", [_allowed_distance(_selected)])
					if _move_mode == "advance" and battle.advance_roll_for(_selected) > 0:
						out += "\n" + UIText.t("detail.advance_roll", [battle.advance_roll_for(_selected)])
			"charge":
				var cs: Dictionary = battle.charge_state(_selected)
				if cs.has("roll"):
					out += ("\n" if out != "" else "") + UIText.t("detail.charge_roll", [int(cs["roll"]), (cs["targets"] as Array).size()])
	return out


## The numbers for the odds card, or an empty dictionary when no attack is being lined up.
func _odds_view() -> Dictionary:
	if _selected == null or _selected.owner != HUMAN or _target == null:
		return {}
	var preview: Array[Dictionary] = []
	if battle.phase() == "shooting":
		preview = battle.shoot_preview(_selected, _target)
	elif battle.phase() == "fight" and battle.fight_stage == "fight":
		preview = battle.fight_preview(_selected, _target)
	else:
		return {}
	if preview.is_empty():
		return {"none": UIText.t("odds.none")}
	var total: float = 0.0
	var lost: float = 0.0
	var rows: Array = []
	for p in preview:
		var o: Dictionary = p["odds"]
		var w: Weapon = p["weapon"]
		total += float(o["expected_damage"])
		lost += float(o["expected_models_destroyed"])
		var hit: String = UIText.t("odds.auto") if bool(o["auto_hit"]) else UIText.t("odds.target", [int(o["hit_target"])])
		rows.append({"title": w.weapon_name if preview.size() > 1 else "",
			"tiles": [[UIText.t("odds.tile_attacks"), _number(float(o["attacks"]))], [UIText.t("odds.tile_hit"), hit],
				[UIText.t("odds.tile_wound"), UIText.t("odds.target", [int(o["wound_target"])])],
				[UIText.t("odds.tile_save"), _save_text(_target, w)]],
			"note": UIText.t("odds.firing", [int(p["models"]), _selected.model_count()]) + _ability_note(w)})
	var heading: String = _target.unit_name if preview.size() > 1 else UIText.t("odds.heading", [(preview[0]["weapon"] as Weapon).weapon_name, _target.unit_name])
	return {"heading": heading, "total": total, "lost": lost, "fraction": total / float(maxi(1, _target.total_wounds_left())), "rows": rows}


func _number(v: float) -> String:
	return "%d" % int(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _save_text(target: UnitState, w: Weapon) -> String:
	var modified: int = target.save - w.ap
	var best: String = UIText.t("odds.target", [clampi(modified, 2, 7)]) if modified <= 6 else UIText.t("odds.no_save")
	if target.invuln > 0 and (modified > target.invuln or modified > 6):
		return UIText.t("odds.invuln", [target.invuln])
	return best


func _ability_note(w: Weapon) -> String:
	var names: Array[String] = _ability_names(w)
	return "" if names.is_empty() else " " + ", ".join(names) + "."


func _ability_names(w: Weapon) -> Array[String]:
	var names: Array[String] = []
	for a in w.abilities:
		var n: String = str(a["name"]).capitalize()
		if int(a["value"]) > 0:
			n += " %d" % int(a["value"])
		names.append(n)
	return names


func _unit_view(u: UnitState) -> Dictionary:
	var extras: Array = []
	if u.invuln > 0:
		extras.append(UIText.t("card.invuln", [u.invuln]))
	if u.fnp > 0:
		extras.append(UIText.t("card.fnp", [u.fnp]))
	if u.battle_shocked:
		extras.append(UIText.t("chip.shocked"))
	var weapons: Array = []
	for w in u.weapons:
		weapons.append([w.weapon_name, _weapon_line(w)])
	return {"side": u.owner, "name": u.unit_name,
		"note": UIText.t("card.models", [u.model_count(), u.starting_strength]),
		"tiles": [[UIText.t("stat.move"), "%d\"" % int(u.move)], [UIText.t("stat.toughness"), str(u.toughness)],
			[UIText.t("stat.save"), UIText.t("odds.target", [u.save])], [UIText.t("stat.wounds"), str(u.wounds_per_model)],
			[UIText.t("stat.leadership"), UIText.t("odds.target", [u.leadership])], [UIText.t("stat.oc"), str(u.objective_control)]],
		"extras": extras, "weapons": weapons}


func _weapon_line(w: Weapon) -> String:
	var rng: String = UIText.t("card.melee") if w.is_melee() else "%d\"" % int(w.range_in)
	var line: String = UIText.t("card.weapon", [rng, w.attacks, w.skill, w.strength, -w.ap, w.damage])
	var names: Array[String] = _ability_names(w)
	if not names.is_empty():
		line += " · " + ", ".join(names)
	return line
