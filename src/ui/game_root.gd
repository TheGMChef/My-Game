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
const RUN_GUARD := 500    # steps of AI playback before the loop gives the screen back
const PHASES: Array[String] = ["command", "movement", "shooting", "charge", "fight"]

## The game is waiting for an answer on the stratagem prompt.
signal prompt_opened
signal _prompt_closed

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
var _weapon_rings: Dictionary = {}       # unit id -> indices of weapons with a ring on the board
var _pause_pending: bool = false         # the menu was asked for while something was playing
var _playing: int = 0                    # event playbacks in progress
var _run_id: int = 0                     # changes when a battle is left, so a running AI loop stops
var _deploy_base: Array[Vector2] = []    # where the unit being placed sits, before any drag
var _prompt_open: bool = false
var _prompt_options: Array[Dictionary] = []    # one for each row of the open prompt

# Nodes
var _top_bar: TopBar
var _phone_hud: PhoneHud
var _phone_col: PanelContainer
var _phone_box: VBoxContainer
var _action_bar: ActionBar
var _board_col: VBoxContainer
var _side: SidePanel
var _over_panel: DialogBox
var _over_title: Label
var _over_vp: Array[Label] = []
var _play_again: Button
var _toolbar: BoardToolbar
var _tray: DeployTray
var _prompt: ReactionPrompt
var _ui_root: VBoxContainer
var _body: BoxContainer
var _title: TitleScreen
var _pause: PauseMenu
var _portrait: bool = false
var _phone: bool = false
var skip_roster: bool = false    ## tests and tools set this to go straight to the placeholder battle
var skip_title: bool = false     ## tools set this to open on the roster
## skip_roster games start on round 1 with no prompts. This keeps deployment and prompts in them.
var full_flow: bool = false
var battle_seed: int = -1         ## tools set this to repeat a game exactly
var armies_override: Array = []   ## tools set this to play skip_roster games with other armies
## False for tests and tools: no settings or save file is read or written. skip_roster and
## skip_title turn it off too.
var persist: bool = true
var show_continue: bool = false   ## tools set this to show Continue without a save
var save_path: String = SaveFile.PATH    ## tests point this at a throwaway file
var placeholder_only: bool = false    ## tools set this to keep real army names off the roster
var _args: Dictionary = {}
var _armies_in_play: Array = []
var _roster: RosterScreen


func _ready() -> void:
	theme = UIThemeBuilder.build()
	if skip_roster or skip_title:
		persist = false
	if persist:
		settings.load_from_disk()
	_setup_input_actions()
	_args = _parse_args()
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()
	if skip_roster or _args.has("quick"):
		_start_battle(_placeholder_armies() if armies_override.is_empty() else armies_override)
	elif skip_title:
		_show_roster()
	else:
		_show_title()


func _placeholder_armies() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]


func _show_title() -> void:
	_title = TitleScreen.new()
	_title.has_save = show_continue or (persist and SaveFile.usable(save_path))
	_title.can_quit = OS.has_feature("pc") and not OS.has_feature("web")
	add_child(_title)
	_title.start_pressed.connect(func() -> void:
		_close_title()
		_show_roster())
	_title.continue_pressed.connect(_on_continue_pressed)
	_title.settings_pressed.connect(_open_settings)
	_title.how_to_pressed.connect(_open_how_to)
	_title.quit_pressed.connect(func() -> void: get_tree().quit())


func _close_title() -> void:
	_title.queue_free()
	_title = null


func _on_continue_pressed() -> void:
	var data: Dictionary = SaveFile.read(save_path)
	var loaded: Battle = Battle.from_save(data.get("battle", {}))
	if loaded == null:
		SaveFile.erase(save_path)
		_close_title()
		_show_title()
		return
	_close_title()
	_resume_battle(loaded, data["armies"])


## Carry on a saved battle. The save was made after begin_turn, so the turn must not begin again.
func _resume_battle(saved: Battle, armies: Array) -> void:
	_armies_in_play = armies
	battle = saved
	_adopt_battle()
	if not battle.deployment_active:
		_begun_key = _turn_key()
	_enter_battle()


## Army and unit selection comes before the battle, which is built once it is confirmed.
func _show_roster() -> void:
	_roster = RosterScreen.new()
	add_child(_roster)
	_roster.setup(str(_args.get("armies", "")), not placeholder_only)
	_roster.started.connect(func(armies: Array) -> void:
		_roster.queue_free()
		_roster = null
		_start_battle(armies))


func _start_battle(armies: Array) -> void:
	_armies_in_play = armies
	_load_battle(armies, battle_seed if battle_seed >= 0 else int(_args.get("seed", Time.get_ticks_msec() % 100000)))
	_enter_battle()


func _enter_battle() -> void:
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
	_start_playing()


## Hand over to whoever acts first: the AI may have a unit to place, or the first turn.
func _start_playing() -> void:
	if battle.deployment_active:
		_run_ai_deployment()
	elif not battle.pending.is_empty() or battle.active_player() != HUMAN:
		_run_until_human_input()


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
	if full_flow or not (skip_roster or _args.has("quick")):
		battle.start_deployment()
	_adopt_battle()


## Reset everything the interface keeps about a battle for a new or resumed one.
func _adopt_battle() -> void:
	battle.reanimate_models = settings.reanimate_models
	_apply_prompt_setting()
	_names = battle.unit_names.duplicate()
	_event_cursor = 0
	_log_lines.clear()
	_game_over_shown = false
	_begun_key = ""
	_weapon_rings.clear()


func _apply_prompt_setting() -> void:
	battle.prompt_sides[HUMAN] = settings.stratagem_prompts and (full_flow or not skip_roster)


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
	_add_action("ruler", [_key(KEY_R)])


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
	if battle == null or board == null or _dialog_open():
		return
	if _prompt_open:
		if event.is_action_pressed("cancel_order"):
			_on_prompt_pass()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("confirm_order"):
			_on_prompt_use(0)
			get_viewport().set_input_as_handled()
		return
	if _busy:
		if event.is_action_pressed("cancel_order") or event.is_action_pressed("confirm_order"):
			_skip = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next_phase"):
		_request_next()
	elif event.is_action_pressed("confirm_order"):
		_on_confirm_pressed()
	elif event.is_action_pressed("cancel_order"):
		if _selected == null and _target == null and _delta == Vector2.ZERO:
			_request_pause()
		else:
			_on_cancel_pressed()
	elif event.is_action_pressed("ruler"):
		_set_ruler(not board.ruler_on)
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
	_ui_root = VBoxContainer.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_theme_constant_override("separation", 0)
	add_child(_ui_root)

	_top_bar = TopBar.new()
	_top_bar.info_pressed.connect(_toggle_info)
	_top_bar.menu_pressed.connect(_request_pause)
	_ui_root.add_child(_top_bar)

	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	_ui_root.add_child(_body)

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
	_toolbar = BoardToolbar.new()
	_toolbar.ruler_toggled.connect(_set_ruler)
	_toolbar.clear_pressed.connect(func() -> void: board.clear_measurement())
	_toolbar.zoom_in_pressed.connect(func() -> void: board.zoom_by(1.25))
	_toolbar.zoom_out_pressed.connect(func() -> void: board.zoom_by(0.8))
	_toolbar.fit_pressed.connect(func() -> void: board.reset_view())
	board_holder.add_child(_toolbar)
	board.measure_changed.connect(_show_ruler_state)
	_prompt = ReactionPrompt.new()
	_prompt.use_pressed.connect(_on_prompt_use)
	_prompt.pass_pressed.connect(_on_prompt_pass)
	board_holder.add_child(_prompt)
	board_holder.resized.connect(_prompt.refit)

	_tray = DeployTray.new()
	_tray.picked.connect(_on_tray_pressed)
	_board_col.add_child(_tray)

	_action_bar = ActionBar.new()
	_action_bar.next_pressed.connect(_request_next)
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
	_phone_hud.menu_pressed.connect(_request_pause)
	_phone_box.add_child(_phone_hud)

	_side = SidePanel.new()
	_side.rules_pressed.connect(_open_rules)
	_side.unit_row_pressed.connect(_on_unit_row_pressed)
	_side.weapon_pressed.connect(_on_weapon_pressed)
	_side.stratagem_pressed.connect(_on_stratagem_pressed)
	_body.add_child(_side)

	_over_panel = _build_over_panel()
	add_child(_over_panel)


func _build_over_panel() -> DialogBox:
	var p := DialogBox.new("", 460.0)
	p.cancellable = false
	p.keep_alive = true
	var col: VBoxContainer = p.body
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
	_play_again = p.add_button(UIText.t("button.play_again"), _restart, true)
	p.add_button(UIText.t("button.new_armies"), func() -> void:
		_leave_battle()
		_show_roster())
	p.add_button(UIText.t("button.menu"), func() -> void:
		_leave_battle()
		_show_title())
	return p


# ---------------------------------------------------------------- dialogs

func _dialog_open() -> bool:
	if _pause != null:
		return true
	for c in get_children():
		if c is DialogBox and (c as DialogBox).visible:
			return true
	return false


func _focus_back() -> void:
	if _title != null:
		_title.focus_first()
	elif board != null and not _dialog_open():
		board.grab_focus()


## Show a dialog, standing in for the pause menu if that is open. The menu comes back on close.
func _show_dialog(d: DialogBox, first_focus: Control = null) -> void:
	add_child(d)
	if _pause != null:
		_pause.visible = false
	d.closed.connect(func() -> void:
		if _pause != null:
			_pause.open()
		else:
			_focus_back())
	d.open(first_focus)


func _open_settings() -> void:
	var d := SettingsDialog.new(settings)
	d.changed.connect(_settings_changed)
	d.closed.connect(func() -> void:
		if persist:
			settings.save_to_disk())
	_show_dialog(d)


func _open_how_to() -> void:
	_show_dialog(HowToPlay.new())


## The full rules text for the current phase.
func _open_rules() -> void:
	var key: String = _rules_key()
	var d := DialogBox.new(UIText.t("help.title." + key), 460.0)
	d.scroll_with_keys = true
	d.add_text(UIText.t("help.body." + key))
	_show_dialog(d, d.add_button(UIText.t("button.close"), d.close, true))


## Ask before something that cannot be taken back. Keyboard focus starts on the safe choice.
func _ask(title_key: String, body: String, yes_key: String, on_yes: Callable) -> DialogBox:
	var d := DialogBox.new(UIText.t(title_key), 420.0)
	d.add_text(body)
	var no: Button = d.add_button(UIText.t("button.cancel"), d.close)
	d.add_button(UIText.t(yes_key), func() -> void:
		on_yes.call()
		d.close(), true)
	_show_dialog(d, no)
	return d


## Open the menu now, or as soon as what is playing can stop safely.
func _request_pause() -> void:
	if battle == null or _dialog_open():
		return
	if (_busy or _playing > 0) and not _prompt_open:
		_pause_pending = true
		_skip = true
		return
	_open_pause()


func _open_pause() -> void:
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.rules_pressed.connect(_open_rules)
	_pause.settings_pressed.connect(_open_settings)
	_pause.restart_pressed.connect(func() -> void:
		_ask("confirm.restart.title", UIText.t("confirm.restart.body"), "button.restart", func() -> void:
			_end_pause()
			_restart()))
	_pause.quit_pressed.connect(func() -> void:
		_ask("confirm.quit.title", UIText.t("confirm.quit.body"), "button.quit_to_menu", func() -> void:
			_end_pause()
			_leave_battle()
			_show_title()))
	_pause.closed.connect(func() -> void:
		_pause = null
		_focus_back())
	_pause.open()


func _end_pause() -> void:
	if _pause != null:
		_pause.visible = true
		_pause.close()


## Where a running AI loop or a playback may stop for the menu: nothing is half done here.
func _pause_point() -> void:
	if _pause_pending:
		_pause_pending = false
		_open_pause()
	while _dialog_open():
		await get_tree().process_frame
	_skip = false


## Back to no battle at all. The autosave stays, so Continue can pick it up.
func _leave_battle() -> void:
	_run_id += 1
	_drop_prompt()
	for n: Node in [_ui_root, _over_panel]:
		if n != null:
			n.queue_free()
	_ui_root = null
	_over_panel = null
	_body = null
	board = null
	battle = null
	_busy = false
	_info_open = false
	_clear_selection()
	_over_vp.clear()


func _settings_changed() -> void:
	if battle != null:
		battle.reanimate_models = settings.reanimate_models
		_apply_prompt_setting()
		board.settings = settings
	_apply_scale()


func _set_ruler(on: bool) -> void:
	board.set_ruler(on)
	_show_ruler_state()
	_refresh()


func _show_ruler_state() -> void:
	_toolbar.show_ruler(board.ruler_on, board.has_measurement())


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
	_toolbar.arrange(not _portrait, not _phone)
	_top_bar.set_density(_compact, logical_width < TINY_BELOW, _compact and not _portrait)
	_phone_col.visible = _phone
	var wanted_parent: Control = _phone_box if _phone else _board_col
	if _action_bar.get_parent() != wanted_parent:
		_action_bar.reparent(wanted_parent)
	_action_bar.set_phone(_phone)
	_action_bar.set_narrow(logical_width < TINY_BELOW)
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
	if _busy or _placing():
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


func _on_empty_tapped(world: Vector2) -> void:
	if _placing():
		_shift_placing(world - _middle_of(_deploy_base))
	else:
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


## A row on the Units tab selects its unit, whichever side it is on, and does nothing else.
func _on_unit_row_pressed(unit_id: String) -> void:
	var u: UnitState = battle.unit_by_id(unit_id)
	if u == null or _busy:
		return
	if battle.undeployed.has(u) and u.owner == HUMAN:
		_on_tray_pressed(unit_id)
		return
	_select(u)
	_refresh.call_deferred()


## A weapon row on the Unit tab turns that weapon's range ring on or off.
func _on_weapon_pressed(index: int) -> void:
	if _selected == null:
		return
	var rings: Array = _weapon_rings.get(_selected.id, [])
	if rings.has(index):
		rings.erase(index)
	else:
		rings.append(index)
	_weapon_rings[_selected.id] = rings
	_refresh.call_deferred()


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
	var mine: Array = battle.undeployed_of(HUMAN) if battle.deployment_active else battle.living(HUMAN)
	if mine.is_empty():
		return
	var i: int = mine.find(_selected)
	i = (i + step + mine.size()) % mine.size() if i >= 0 else 0
	if battle.deployment_active:
		_on_tray_pressed((mine[i] as UnitState).id)
		return
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
	if _placing():
		_shift_placing(_delta)
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
	if battle.deployment_active:
		return d
	var limit: float = _allowed_distance(u)
	return d.limit_length(limit)


func _can_drag() -> bool:
	if battle.deployment_active:
		return _placing()
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
	if _placing():
		for p in _deploy_base:
			out.append(p + _delta)
		return out
	for m in _selected.models:
		out.append(m["pos"] + _delta)
	return out


func _update_ghost_verdict() -> void:
	_verdict = {}
	if _placing():
		_verdict = battle.preview_deploy(_selected, _ghost_positions())
		return
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
	if battle.deployment_active:
		if battle.deployment_ready():
			await _on_start_battle_pressed()
		elif _placing():
			await _on_place_pressed()
		return
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


## One step back: a pending move, then a target, then the selection.
func _on_cancel_pressed() -> void:
	var had_move: bool = _delta != Vector2.ZERO
	_delta = Vector2.ZERO
	_verdict = {}
	if had_move:
		pass
	elif _target != null:
		_target = null
	elif _selected != null:
		_selected = null
	_refresh()


func _on_undo_pressed() -> void:
	var r: Dictionary = battle.cmd_undo_move()
	_verdict = {} if r["ok"] else r
	_delta = Vector2.ZERO
	_consume_events()
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


func _on_shadow_pressed() -> void:
	_verdict = battle.cmd_shadow_in_the_warp(HUMAN)
	_consume_events()
	_refresh()


func _on_mark_spotted_pressed() -> void:
	_verdict = battle.cmd_mark_spotted(_selected, _target)
	_consume_events()
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


## The end-phase button and key: asks first if the setting is on and units can still act.
func _request_next() -> void:
	if _busy or battle.is_over():
		return
	if battle.deployment_active:
		_on_auto_deploy_pressed()
		return
	if battle.active_player() != HUMAN and not _human_can_act_in_ai_turn():
		return
	var left: int = _units_left_to_act()
	if settings.confirm_end_phase and left > 0:
		var body: String = UIText.t("confirm.end_phase.body_one") if left == 1 else UIText.t("confirm.end_phase.body", [left])
		_ask("confirm.end_phase.title", body, "button.yes_end", _on_next_pressed)
		return
	_on_next_pressed()


## How many of the human's units could still do something in this phase or step.
func _units_left_to_act() -> int:
	return battle.living(HUMAN).filter(_can_still_act).size()


func _can_still_act(u: UnitState) -> bool:
	match battle.phase():
		"movement":
			return not battle.has_moved(u)
		"shooting":
			if battle.has_shot(u):
				return false
			return battle.living(1 - HUMAN).any(func(e: UnitState) -> bool: return not battle.shoot_preview(u, e).is_empty())
		"charge":
			if battle.charge_finished(u):
				return false
			return not battle.charge_state(u).is_empty() or ChargeRules.eligible(u, battle.units)["ok"]
		"fight":
			return battle.can_pile_in(u) or battle.can_consolidate(u)
	return false


func _on_next_pressed() -> void:
	if _busy or battle.is_over() or battle.deployment_active:
		return
	if battle.active_player() != HUMAN and not _human_can_act_in_ai_turn():
		return
	var r: Dictionary = battle.next_phase()
	_verdict = r
	_clear_selection()
	if battle.events.slice(_event_cursor).any(func(e: Dictionary) -> bool: return e["type"] == "stratagem"):
		await _play_new_events()    # the AI answered: show it rather than only log it
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
	_over_panel.close()
	_run_id += 1
	_drop_prompt()
	_busy = false
	_skip = false
	_action_bar.set_busy(false)
	_load_battle(_armies_in_play, Time.get_ticks_msec() % 100000)
	board.battle = battle
	_clear_selection()
	_set_ruler(false)
	_begin_turn_once()
	_consume_events()
	_refresh()
	board.grab_focus()
	_start_playing()


# ---------------------------------------------------------------- deployment

## A unit of the human's is on its way to the board. Presentation only until it is placed.
func _placing() -> bool:
	return battle != null and battle.deployment_active and _selected != null and _selected.owner == HUMAN \
			and battle.undeployed.has(_selected)


## Pick up a unit from the tray: it starts at a legal spot if there is one, ready to be dragged.
func _on_tray_pressed(unit_id: String) -> void:
	var u: UnitState = battle.unit_by_id(unit_id)
	if _busy or u == null or battle.deploy_side() != HUMAN or not battle.undeployed.has(u):
		return
	_select(u)
	_deploy_base = SimpleAI.deployment_positions(battle, u)
	if _deploy_base.is_empty():
		_deploy_base = battle.formation(u, battle.zone_rect(HUMAN).get_center())
	_update_ghost_verdict()
	_refresh()


func _shift_placing(by: Vector2) -> void:
	for i in range(_deploy_base.size()):
		_deploy_base[i] += by
	_delta = Vector2.ZERO
	_update_ghost_verdict()


func _middle_of(points: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / maxf(1.0, float(points.size()))


func _on_place_pressed() -> void:
	if not _placing():
		return
	var r: Dictionary = battle.cmd_deploy(_selected, _ghost_positions())
	_verdict = r
	if r["ok"]:
		_clear_selection()
		_consume_events()
		_autosave()
		await _run_ai_deployment()
	_refresh()


func _on_auto_deploy_pressed() -> void:
	battle.cmd_auto_deploy()
	_clear_selection()
	_consume_events()
	_autosave()
	_refresh()


func _on_start_battle_pressed() -> void:
	if battle.cmd_finish_deployment()["ok"]:
		_consume_events()
		await _run_until_human_input()
	_refresh()


## Let the AI place its units until it is the human's turn to place one.
func _run_ai_deployment() -> void:
	var run: int = _run_id
	_set_busy(true)
	while battle.ai_deploy_step():
		await _play_new_events()
		if run != _run_id:
			return
	_set_busy(false)


# ---------------------------------------------------------------- stratagems

## True while the game is stopped on a stratagem question.
func prompt_open() -> bool:
	return _prompt_open


## The Stratagems tab's view of the moment, playable ones first.
func _stratagem_view() -> Dictionary:
	var live: Array = []
	var greyed: Array = []
	for row in battle.stratagem_overview(HUMAN):
		var id: String = row["id"]
		var pick: Dictionary = _preferred_option(row["options"])
		var line: Dictionary = {"id": id, "name": UIText.t("strat.%s.name" % id), "effect": UIText.t("strat.%s.effect" % id),
			"cost": UIText.t("strat.cost", [int(row["cost"])]), "button": _option_button(pick),
			"reason": "" if str(row["reason"]) == "" else UIText.t(str(row["reason"]))}
		(greyed if pick.is_empty() else live).append(line)
	return {"cp": UIText.t("strat.cp_line", [battle.command_points(HUMAN), battle.command_points(1 - HUMAN)]), "rows": live + greyed}


## The option that fits the current selection, or else the first.
func _preferred_option(options: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -1
	for o: Dictionary in options:
		var score: int = 0
		if _selected != null and o["unit"] == _selected.id:
			score += 2
		if _target != null and o["target"] == _target.id:
			score += 1
		if score > best_score:
			best_score = score
			best = o
	return best


func _option_text(o: Dictionary) -> String:
	var who: String = str(_names.get(o["unit"], ""))
	if str(o["target"]) != "":
		return UIText.t("strat.use_target", [who, str(_names.get(o["target"], ""))])
	if str(o["mode"]) != "":
		return "%s: %s" % [who, UIText.t("strat.mode." + str(o["mode"]))]
	return who


func _option_button(o: Dictionary) -> String:
	return "" if o.is_empty() else UIText.t("strat.use_on", [_option_text(o)])


func _on_stratagem_pressed(id: String) -> void:
	if battle == null or (_busy and not _prompt_open):
		return
	var options: Array = battle.stratagem_options(HUMAN).filter(func(o: Dictionary) -> bool: return o["id"] == id)
	if options.is_empty():
		return
	var pick: Dictionary = _preferred_option(options)
	var r: Dictionary = battle.cmd_stratagem(HUMAN, id, pick)
	if not r["ok"]:
		_verdict = r
		_refresh()
		return
	_verdict = {}
	_close_prompt()
	var charge: Dictionary = {} if _selected == null else battle.charge_state(_selected)
	if id == "command_reroll" and charge.has("targets"):
		_charge_targets.assign(charge["targets"])
	await _play_new_events()
	if battle != null:
		_update_ghost_verdict()
		_refresh()


## Rows for the prompt: one for each unit and mode. Options run nearest enemy first, so a unit's
## first option is its best target.
func _prompt_rows() -> Array[Dictionary]:
	var seen: Dictionary = {}
	var out: Array[Dictionary] = []
	for o in battle.stratagem_options(HUMAN):
		var key: String = "%s/%s/%s" % [o["id"], o["unit"], o["mode"]]
		if not seen.has(key):
			seen[key] = true
			out.append(o)
	return out


## Stop for a stratagem question until it is answered. The AI loop waits here. Leaving the battle
## also ends the wait, and an empty question passes by itself, so this can't hold a game up.
func _answer_pending() -> void:
	_prompt_options = _prompt_rows()
	if _prompt_options.is_empty():
		battle.cmd_pass(HUMAN)
		return
	var run: int = _run_id
	_autosave()
	_prompt_open = true
	_set_busy(true)
	var first: Dictionary = _prompt_options[0]
	var id: String = first["id"]
	var rows: Array = []
	for o in _prompt_options:
		rows.append(_option_button(o) if int(o["cost"]) == int(first["cost"]) else UIText.t("prompt.title", [_option_button(o), int(o["cost"])]))
	_prompt.ask({"title": UIText.t("prompt.title", [UIText.t("strat.%s.name" % id), int(first["cost"])]),
		"effect": UIText.t("strat.%s.effect" % id), "cp": UIText.t("prompt.cp", [battle.command_points(HUMAN)]), "rows": rows})
	_mark_prompt_target(first)
	prompt_opened.emit()
	await _prompt_closed
	if run == _run_id:
		board.grab_focus()


func _mark_prompt_target(o: Dictionary) -> void:
	var u: UnitState = battle.unit_by_id(str(o["unit"]))
	var foe: UnitState = battle.unit_by_id(str(o["target"]))
	board.selected = u
	board.highlights = {} if foe == null else {foe: BoardView.MARK_TARGET}
	board.queue_redraw()


func _on_prompt_use(index: int) -> void:
	if not _prompt_open or index >= _prompt_options.size():
		return
	var o: Dictionary = _prompt_options[index]
	battle.cmd_stratagem(HUMAN, str(o["id"]), o)
	_close_prompt()


func _on_prompt_pass() -> void:
	if not _prompt_open:
		return
	battle.cmd_pass(HUMAN)
	_close_prompt()


func _close_prompt() -> void:
	if not _prompt_open:
		return
	_prompt_open = false
	_prompt.close()
	_prompt_closed.emit()


## The battle is going away: let go of anything waiting on the prompt.
func _drop_prompt() -> void:
	_close_prompt()


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
	var run: int = _run_id
	while guard < RUN_GUARD and not battle.is_over():
		guard += 1
		await _pause_point()
		if run != _run_id:
			return
		if not battle.pending.is_empty():
			await _answer_pending()
			if run != _run_id:
				return
			await _play_new_events()
			_refresh_board_only()
			continue
		if battle.active_player() == HUMAN and not _ai_has_fight_pick():
			if battle.phase() == "command":
				_begin_turn_once()
				_consume_events()
				if not battle.pending.is_empty():
					continue
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
	var key: String = _turn_key()
	if key == _begun_key or battle.is_over() or battle.deployment_active:
		return
	_begun_key = key
	battle.begin_turn()
	if battle.active_player() == HUMAN:
		_autosave()


func _turn_key() -> String:
	return "%d_%d" % [battle.flow.round_no, battle.active_player()]


func _autosave() -> void:
	if persist:
		SaveFile.write({"battle": battle.to_save(), "armies": _armies_in_play}, save_path)


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
	if _action_bar == null or battle == null:
		return
	_action_bar.set_busy(on and not _prompt_open)
	_refresh()
	if not on and _pause_pending:
		_pause_pending = false
		_open_pause()


func _consume_events() -> void:
	## Take new events into the log without playing them (human actions are shown directly).
	while _event_cursor < battle.events.size():
		_log_event(battle.events[_event_cursor])
		_event_cursor += 1


func _play_new_events() -> void:
	_playing += 1
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
	_playing -= 1
	if _pause_pending and not _busy and _playing == 0:
		_pause_pending = false
		_open_pause()


func _animate(e: Dictionary) -> void:
	var pace: float = settings.ai_speed() if _busy else 1.0    # the AI speed setting: 0 skips animation
	var instant: bool = _skip or settings.reduced_motion or pace <= 0.0
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
			tw.tween_method(step, 0.0, 1.0, 0.35 * pace)
			await tw.finished
		"shoot", "fight":
			var a: UnitState = battle.unit_by_id(e["unit"])
			var d: UnitState = battle.unit_by_id(e["target"])
			if a != null and d != null:
				board.flash(a.centre(), d.centre(), UITokens.SIDE_COLOURS[a.owner], 0.0 if instant else 0.7 * pace)
			if not instant:
				await get_tree().create_timer(0.55 * pace).timeout
		"turn_start", "score", "charge_roll", "advance_roll", "deploy", "stratagem":
			if not instant:
				await get_tree().create_timer(0.25 * pace).timeout


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
		"undo_move":
			line = UIText.t("log.undo_move", [side_word, who])
		"hold":
			line = UIText.t("log.hold", [side_word, who])
		"advance_roll":
			line = UIText.t("log.reroll_advance" if e.has("reroll") else "log.advance_roll", [who, int(e["roll"])])
		"shoot":
			line = UIText.t("log.shoot_snap" if e.has("snap") else "log.shoot", [side_word, who, str(_names.get(e["target"], "?")), _damage_of(e), _models_of(e)])
		"fight":
			line = UIText.t("log.fight", [side_word, who, str(_names.get(e["target"], "?")), _damage_of(e), _models_of(e)])
		"fight_skipped":
			line = UIText.t("log.fight_skipped", [who])
		"charge_roll":
			line = UIText.t("log.reroll_charge" if e.has("reroll") else "log.charge_roll", [who, int(e["roll"])])
		"deploy":
			line = UIText.t("log.deploy_forced" if bool(e["forced"]) else "log.deploy", [side_word, who])
		"first_turn":
			line = UIText.t("log.first_turn", [int(e["rolls"][0]), int(e["rolls"][1]), UIText.t("log.first_turn.you" if int(e["side"]) == HUMAN else "log.first_turn.ai")])
		"stratagem":
			line = _stratagem_line(e, side_word)
		"explosives":
			line = UIText.t("log.explosives", [str(_names.get(e["target"], "?")), int(e["wounds"])])
		"crushing_impact":
			line = UIText.t("log.crushing_impact", [who, int(e["taken"]), str(_names.get(e["target"], "?")), int(e["dealt"])])
		"shock_reroll":
			line = UIText.t("log.shock_reroll", [who, UIText.t("log.shock_reroll.passed" if bool(e["passed"]) else "log.shock_reroll.failed")])
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
		"deadly_demise":
			line = UIText.t("log.deadly_demise", [who, int(e["wounds"])])
		"reanimated":
			line = UIText.t("log.reanimated", [who, int(e["wounds"])])
		"shadow_in_the_warp":
			line = UIText.t("log.shadow", [(e["shocked"] as Array).size()])
		"spotted":
			line = UIText.t("log.spotted", [who, str(_names.get(e["target"], "?"))])
		"score":
			line = UIText.t("log.score_one" if int(e["objectives"]) == 1 else "log.score", [side_word, int(e["vp"]), int(e["objectives"])])
		"turn_end":
			line = ""
	if line != "":
		_log_lines.append({"text": line, "side": int(e["side"])})
		if _log_lines.size() > 60:
			_log_lines.pop_front()


func _stratagem_line(e: Dictionary, side_word: String) -> String:
	var strat: String = UIText.t("strat.%s.name" % str(e["id"]))
	var who: String = str(_names.get(e["unit"], "?"))
	if str(e["mode"]) == Stratagems.INTO_THE_FRAY:
		return UIText.t("log.strat_mode", [side_word, strat, UIText.t("strat.mode.into_the_fray"), who])
	return UIText.t("log.strat", [side_word, strat, who])


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
	if persist:
		SaveFile.erase(save_path)
	var mine: int = battle.vp[HUMAN]
	var theirs: int = battle.vp[1 - HUMAN]
	var key: String = "over.win" if mine > theirs else ("over.lose" if mine < theirs else "over.draw")
	_over_title.text = UIText.t(key)
	_over_vp[HUMAN].text = str(mine)
	_over_vp[1 - HUMAN].text = str(theirs)
	_over_panel.open(_play_again)


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	if battle == null or _top_bar == null or not is_instance_valid(_top_bar):
		return
	var total_rounds: int = int(battle.scenario.get("battle_rounds", 5))
	var round_no: int = battle.flow.round_no
	var over: bool = battle.is_over()
	_top_bar.refresh(round_no, total_rounds, battle.active_player() == HUMAN, battle.phase(), battle.flow.command_points, battle.vp, over)
	_phone_hud.refresh(round_no, total_rounds, battle.phase(), battle.vp, battle.flow.command_points, over)
	_refresh_action_bar()
	_refresh_side_panel()
	_refresh_board_only()
	if battle.is_over() and not _busy:
		_show_game_over()


func _refresh_board_only() -> void:
	if board == null:
		return
	board.selected = _selected
	board.weapon_rings = _ring_radii(_selected)
	var tools: Array[Rect2] = [_toolbar.get_rect()]
	board.keep_clear = tools
	board.ghost = _ghost_positions() if _delta.length() >= 0.01 or _placing() else ([] as Array[Vector2])
	board.ghost_ok = bool(_verdict.get("ok", true))
	board.drag_enabled = _can_drag()
	board.deploy_drag = _placing()
	board.ring_radius = 0.0
	board.highlights = {}
	board.los_line = []
	board.acted = _acted_units()
	if _selected != null and _selected.owner == HUMAN and _can_drag() and not battle.deployment_active:
		board.ring_centre = _selected.centre()
		board.ring_radius = _allowed_distance(_selected)
	if _selected != null and _selected.owner == HUMAN:
		_mark_highlights()
	board.queue_redraw()


## Ring sizes for a unit's switched-on weapons. Range runs edge to edge, so a ring around the
## unit's centre sits one base radius further out than the weapon's range.
func _ring_radii(u: UnitState) -> Array[float]:
	var out: Array[float] = []
	if u == null or battle.deployment_active:
		return out
	for i in _weapon_rings.get(u.id, []):
		out.append((u.weapons[i] as Weapon).range_in + u.base_radius)
	return out


func _acted_units() -> Array:
	return battle.living(HUMAN).filter(_has_acted)


func _has_acted(u: UnitState) -> bool:
	match battle.phase():
		"movement":
			return battle.has_moved(u)
		"shooting":
			return battle.has_shot(u)
		"charge":
			return battle.charge_finished(u)
	return false


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
	if battle.deployment_active:
		can_end = not battle.undeployed.is_empty()
	_action_bar.show_actions(_action_specs(), _next_label(), _busy or battle.is_over() or not can_end)


func _next_label() -> String:
	if battle.is_over():
		return UIText.t("next.over")
	if battle.deployment_active:
		return UIText.t("next.all_placed" if battle.undeployed.is_empty() else "next.auto_deploy")
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
	if battle.deployment_active:
		return _deployment_actions()
	if battle.can_unleash_shadow(HUMAN) and battle.active_player() == HUMAN:
		return [_act("button.shadow", _on_shadow_pressed)]
	if _selected == null or _selected.owner != HUMAN:
		if battle.phase() == "fight" and battle.fight_stage == "fight" and battle.fight_finished():
			return [_hint("hint.fights_done")]
		return _with_undo([_hint(_idle_hint_key())])
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


func _deployment_actions() -> Array[Dictionary]:
	if battle.deployment_ready():
		return [_hint("hint.deploy_ready"), _main("button.start_battle", _on_start_battle_pressed, false)]
	if battle.deploy_side() != HUMAN:
		return [_hint("hint.deploy_wait")]
	if _placing():
		var problem: String = "" if bool(_verdict.get("ok", true)) else str(_verdict.get("reason", ""))
		var specs: Array[Dictionary] = [{"hint": UIText.t("hint.deploy_drag", [_selected.unit_name]) if problem == "" else problem[0].to_upper() + problem.substr(1)}]
		if not _phone:    # the narrow column has no room, and tapping another unit changes the choice
			specs.append(_act("button.cancel", _on_cancel_pressed))
		specs.append(_main("button.place_unit", _on_place_pressed, not bool(_verdict.get("ok", false))))
		return specs
	var left: int = battle.undeployed_of(HUMAN).size()
	return [{"hint": UIText.t("hint.deploy_count_one") if left == 1 else UIText.t("hint.deploy_count", [left])}]


## Buttons for the stratagems the selected unit can use right now in these windows.
func _strat_buttons(windows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for o in battle.stratagem_options(HUMAN):
		if seen.has(o["id"]) or not windows.has(o["window"]) or o["unit"] != _selected.id:
			continue
		if _target != null and str(o["target"]) != "" and o["target"] != _target.id:
			continue
		seen[o["id"]] = true
		var id: String = o["id"]
		var text: String = UIText.t("button.reroll", [int(o["cost"])]) if id == "command_reroll" \
				else UIText.t("button.strat", [UIText.t("strat.%s.name" % id), int(o["cost"])])
		out.append({"text": text, "handler": _on_stratagem_pressed.bind(id), "role": "normal"})
	return out


## What to do next with nothing selected, as one line for this phase.
func _idle_hint_key() -> String:
	if battle.active_player() != HUMAN and not _human_can_act_in_ai_turn():
		return "hint.wait"
	return "hint.select." + _rules_key()


## The phase, or the step within the Fight phase. Rules and hint strings are named after it.
func _rules_key() -> String:
	return battle.phase() if battle.phase() != "fight" else "fight_" + battle.fight_stage


## Add Undo move to these specs while there is a move to take back.
func _with_undo(specs: Array[Dictionary]) -> Array[Dictionary]:
	if battle.active_player() == HUMAN and battle.can_undo_move():
		specs.append(_act("button.undo", _on_undo_pressed))
	return specs


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
		return _with_undo([_hint("hint.already_moved")])
	var pending: bool = _delta.length() >= 0.01
	var out: Array[Dictionary] = []
	if UnitRules.engaged(_selected, battle.units):
		out.append(_mode("mode.fall_back", "fall_back"))
	else:
		out.append(_mode("mode.normal", "normal"))
		out.append(_mode("mode.advance", "advance"))
		if _move_mode == "advance":
			out.append_array(_strat_buttons([Stratagems.W_ADVANCE]))
	if pending:
		out.append(_act("button.cancel", _on_cancel_pressed))
	else:
		out.append(_act("button.hold", _on_hold_pressed))
		_with_undo(out)
	out.append(_main("button.confirm_move", _on_confirm_pressed, _no_valid_move()))
	return out


func _shooting_actions() -> Array[Dictionary]:
	if battle.has_shot(_selected):
		return [_hint("hint.already_shot")]
	if _target == null:
		return [_hint("hint.pick_target")]
	var specs: Array[Dictionary] = [_act("button.cancel", _on_cancel_pressed)]
	if battle.can_observe(_selected) and battle.can_be_spotted(_target):
		specs.append(_act("button.mark_spotted", _on_mark_spotted_pressed))
	specs.append_array(_strat_buttons([Stratagems.W_SHOOTING]))
	specs.append(_main("button.fire", _on_fire_pressed, battle.shoot_preview(_selected, _target).is_empty()))
	return specs


func _charge_actions() -> Array[Dictionary]:
	var cs: Dictionary = battle.charge_state(_selected)
	if cs.is_empty():
		return [_main("button.declare_charge", _on_declare_pressed, not ChargeRules.eligible(_selected, battle.units)["ok"])]
	if battle.charge_finished(_selected):
		var done: Array[Dictionary] = [_hint("hint.charge_done")]
		done.append_array(_strat_buttons([Stratagems.W_CHARGE, Stratagems.W_CHARGE_MOVED]))
		return done
	var specs: Array[Dictionary] = [_act("button.suggest", _on_suggest_pressed), _act("button.give_up", _on_give_up_pressed)]
	specs.append_array(_strat_buttons([Stratagems.W_CHARGE]))
	specs.append(_main("button.confirm_charge", _on_confirm_pressed, _no_valid_move()))
	return specs


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
			var epic: Array[Dictionary] = _strat_buttons([Stratagems.W_FIGHT_SELECTED])
			if _target == null:
				var waiting: Array[Dictionary] = [_hint("hint.pick_fight_target"), _act("button.skip_fight", _on_skip_fight_pressed)]
				waiting.append_array(epic)
				return waiting
			epic.append(_main("button.fight", _on_fight_pressed, battle.fight_preview(_selected, _target).is_empty()))
			return epic
		"consolidate":
			if not battle.can_consolidate(_selected):
				return [_hint("hint.no_consolidate")]
			return [_act("button.suggest", _on_suggest_pressed),
				_main("button.confirm_consolidate", _on_confirm_pressed, _no_valid_move())]
	return []


# ---------------------------------------------------------------- side panel data

func _refresh_side_panel() -> void:
	var over: bool = battle.is_over()
	var key: String = _rules_key()
	var odds: Dictionary = _odds_view()
	var title: String = UIText.t("hud.battle_over") if over else UIText.t("help.title." + key)
	_side.show_orders(title, "" if not odds.is_empty() else _instruction(key), _orders_detail(), not over)
	_side.show_odds(odds)
	_side.show_unit(_unit_view(_selected) if _selected != null else {})
	_side.show_units(_units_view())
	_side.show_log(_log_lines)
	_side.show_stratagems(_stratagem_view())
	_tray.visible = battle.deployment_active and not battle.undeployed_of(HUMAN).is_empty()
	if _tray.visible:
		_tray.show_units(_tray_view())


## The one short line on the Orders tab: the action bar's hint if it has one.
func _instruction(key: String) -> String:
	if battle.is_over():
		return UIText.t("help.over")
	if _busy:
		return UIText.t("help.ai_playing")
	if board.ruler_on:
		return UIText.t("ruler.hint")
	for s in _action_specs():
		if s.has("hint"):
			return str(s["hint"])
	return UIText.t("help.short." + key)


func _tray_view() -> Array:
	var rows: Array = []
	for u: UnitState in battle.undeployed_of(HUMAN):
		rows.append({"id": u.id, "name": u.unit_name, "count": str(u.model_count()), "selected": u == _selected})
	return rows


## Rows for the Units tab: your units, then the enemy's.
func _units_view() -> Array:
	var rows: Array = []
	for side: int in [HUMAN, 1 - HUMAN]:
		for u: UnitState in battle.living(side) + battle.undeployed_of(side):
			var marks: Array = []
			if u.battle_shocked:
				marks.append([UIText.t("chip.shocked_short"), UITokens.illegal(settings.colour_blind)])
			if _has_acted(u):
				marks.append([UIText.t("chip.acted"), UITokens.INK_DIM])
			var single: bool = u.starting_strength == 1 and u.wounds_per_model > 1
			var count: String = UIText.t("units.wounds", [u.total_wounds_left(), u.wounds_per_model]) if single \
					else UIText.t("units.models", [u.model_count(), u.starting_strength])
			rows.append({"id": u.id, "side": u.owner, "name": u.unit_name, "count": count,
				"selected": u == _selected, "marks": marks})
	return rows


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
	var rings: Array = _weapon_rings.get(u.id, [])
	for i in range(u.weapons.size()):
		var w: Weapon = u.weapons[i]
		weapons.append([w.weapon_name, _weapon_line(w), -1 if w.is_melee() else i, rings.has(i)])
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
