extends GdUnitTestSuite
## Menus, dialogs, tools and resuming, through the real controller. Placeholder armies only, and
## any file goes to a throwaway path.

const TEST_SAVE := "user://test_save_only.json"
const MAX_FRAMES := 600


func after_test() -> void:
	SaveFile.erase(TEST_SAVE)


func _game() -> GameRoot:
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_roster = true
	r.battle_seed = 5
	add_child(r)
	r.settings.reduced_motion = true
	return r


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func _to_phase(r: GameRoot, phase: String) -> void:
	while r.battle.phase() != phase:
		await r._on_next_pressed()


func _texts(specs: Array[Dictionary]) -> Array:
	return specs.map(func(s: Dictionary) -> String: return str(s.get("text", "")))


func _hints(specs: Array[Dictionary]) -> Array:
	return specs.filter(func(s: Dictionary) -> bool: return s.has("hint"))


func _drag(r: GameRoot, u: UnitState, d: Vector2) -> void:
	r._on_unit_tapped(u)
	r._on_drag_moved(u, d)


# --- the pause menu ---

func test_cancel_with_nothing_selected_opens_the_menu() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	r._unhandled_input(_action("cancel_order"))

	# Assert
	assert_object(r._pause).is_not_null()


func test_cancel_with_a_unit_selected_only_clears_the_selection() -> void:
	# Arrange
	var r: GameRoot = _game()
	r._on_unit_tapped(r.battle.living(GameRoot.HUMAN)[0])

	# Act
	r._unhandled_input(_action("cancel_order"))

	# Assert
	assert_object(r._pause).is_null()
	assert_object(r._selected).is_null()


func test_game_keys_do_nothing_behind_a_dialog() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	r._open_pause()

	# Act
	r._unhandled_input(_action("next_phase"))
	r._unhandled_input(_action("ruler"))

	# Assert
	assert_str(r.battle.phase()).is_equal("movement")
	assert_bool(r.board.ruler_on).is_false()


func test_focus_cannot_leave_an_open_dialog() -> void:
	# Arrange
	var r: GameRoot = _game()
	r._open_pause()
	await await_idle_frame()
	await await_idle_frame()

	# Act
	r.board.grab_focus()
	await await_idle_frame()

	# Assert
	assert_bool(r._pause.is_ancestor_of(r.get_viewport().gui_get_focus_owner())).is_true()


func test_rules_replace_the_menu_and_hand_back_to_it() -> void:
	# Arrange
	var r: GameRoot = _game()
	r._open_pause()
	r._open_rules()
	assert_bool(r._pause.visible).is_false()

	# Act
	(r.get_child(-1) as DialogBox).close()

	# Assert
	assert_bool(r._pause.visible).is_true()


func test_restart_asks_first_and_cancelling_keeps_the_battle() -> void:
	# Arrange
	var r: GameRoot = _game()
	var before: Battle = r.battle
	r._open_pause()

	# Act
	r._pause.restart_pressed.emit()
	(r.get_child(-1) as DialogBox).close()

	# Assert
	assert_object(r.battle).is_same(before)
	assert_object(r._pause).is_not_null()


func test_quit_to_menu_leaves_the_battle_and_shows_the_title() -> void:
	# Arrange
	var r: GameRoot = _game()
	r._open_pause()
	r._pause.quit_pressed.emit()
	var ask: DialogBox = r.get_child(-1)

	# Act: the second footer button is the yes
	(ask.footer.get_child(1) as Button).pressed.emit()

	# Assert
	assert_object(r.battle).is_null()
	assert_object(r._pause).is_null()
	assert_object(r._title).is_not_null()


func test_the_menu_waits_for_the_ai_loop_and_restart_stops_it() -> void:
	# Arrange: the human ends the turn, the AI's turn starts playing
	var r: GameRoot = _game()
	r.settings.reduced_motion = false
	r.settings.ai_speed_index = 2
	while r.battle.phase() != "fight":
		await r._on_next_pressed()
	while r.battle.active_player() == GameRoot.HUMAN:
		r._on_next_pressed()
		if r._busy:
			break
		await await_idle_frame()
	assert_bool(r._busy).is_true()

	# Act
	r._request_pause()
	for i in range(MAX_FRAMES):
		if r._pause != null:
			break
		await await_idle_frame()

	# Assert: paused at a safe point, then restart frees the loop
	assert_object(r._pause).is_not_null()
	r._end_pause()
	r._restart()
	for i in range(MAX_FRAMES):
		await await_idle_frame()
		if not r._busy:
			break
	assert_bool(r._busy).is_false()
	assert_int(r.battle.flow.round_no).is_equal(1)
	assert_int(r.battle.active_player()).is_equal(GameRoot.HUMAN)


# --- ending a phase ---

func test_ending_a_phase_with_units_left_asks_first() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	r.settings.confirm_end_phase = true

	# Act
	r._request_next()

	# Assert
	assert_str(r.battle.phase()).is_equal("movement")
	assert_bool(r._dialog_open()).is_true()


func test_ending_a_phase_with_every_unit_done_does_not_ask() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	r.settings.confirm_end_phase = true
	for u in r.battle.living(GameRoot.HUMAN):
		r.battle.cmd_hold(u)

	# Act
	await r._request_next()

	# Assert
	assert_str(r.battle.phase()).is_equal("shooting")
	assert_bool(r._dialog_open()).is_false()


func test_with_the_setting_off_ending_a_phase_never_asks() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	r.settings.confirm_end_phase = false

	# Act
	await r._request_next()

	# Assert
	assert_str(r.battle.phase()).is_equal("shooting")


func test_shooting_only_counts_units_that_have_something_to_shoot() -> void:
	# Arrange: at the start, the armies are out of range of each other
	var r: GameRoot = _game()
	await _to_phase(r, "shooting")

	# Act
	var left: int = r._units_left_to_act()

	# Assert
	var able: int = 0
	for u in r.battle.living(GameRoot.HUMAN):
		for e in r.battle.living(1):
			if not r.battle.shoot_preview(u, e).is_empty():
				able += 1
				break
	assert_int(left).is_equal(able)


# --- action bar cleanup ---

func test_hold_shows_only_with_no_pending_move_and_cancel_only_with_one() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	r._on_unit_tapped(u)

	# Act and assert
	assert_array(_texts(r._action_specs())).contains([UIText.t("button.hold")])
	assert_array(_texts(r._action_specs())).not_contains([UIText.t("button.cancel")])
	r._on_drag_moved(u, Vector2(2, 0))
	assert_array(_texts(r._action_specs())).contains([UIText.t("button.cancel")])
	assert_array(_texts(r._action_specs())).not_contains([UIText.t("button.hold")])


func test_cancel_clears_a_pending_move_but_keeps_the_unit() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	_drag(r, u, Vector2(2, 0))

	# Act
	r._on_cancel_pressed()

	# Assert
	assert_object(r._selected).is_same(u)
	assert_vector(r._delta).is_equal(Vector2.ZERO)


func test_each_phase_has_its_own_idle_hint() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act and assert
	assert_str(str(_hints(r._action_specs())[0]["hint"])).is_equal(UIText.t("hint.select.command"))
	await _to_phase(r, "movement")
	assert_str(str(_hints(r._action_specs())[0]["hint"])).is_equal(UIText.t("hint.select.movement"))


func test_orders_show_the_short_line_not_the_rules_text() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")

	# Act
	var line: String = r._instruction(r._rules_key())

	# Assert
	assert_str(line).is_not_equal(UIText.t("help.body.movement"))
	assert_int(line.length()).is_less(70)


func test_a_finished_battle_says_so_and_shows_no_phase() -> void:
	# Arrange
	var r: GameRoot = _game()
	r.battle.flow.finished = true

	# Act
	r._refresh()

	# Assert
	assert_str(r._top_bar._round.text).is_equal(UIText.t("hud.battle_over"))
	for chip in r._top_bar._steps:
		assert_bool(chip.visible).is_false()
	assert_str(r._phone_hud._phase.text).is_equal(UIText.t("hud.battle_over"))


# --- undo through the interface ---

func test_undo_is_offered_after_a_move_and_takes_it_back() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	var start: Vector2 = u.models[0]["pos"]
	_drag(r, u, Vector2(2, 0))
	r._on_confirm_pressed()
	assert_array(_texts(r._action_specs())).contains([UIText.t("button.undo")])

	# Act
	r._on_undo_pressed()

	# Assert
	assert_vector(u.models[0]["pos"]).is_equal(start)
	assert_array(_texts(r._action_specs())).not_contains([UIText.t("button.undo")])
	assert_str(str(r._log_lines[-1]["text"])).contains(u.unit_name)


func test_undo_is_not_offered_after_an_advance() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	r._on_unit_tapped(u)
	r._set_mode("advance")
	r._on_drag_moved(u, Vector2(2, 0))
	r._on_confirm_pressed()

	# Act and assert
	assert_bool(r.battle.has_moved(u)).is_true()
	assert_array(_texts(r._action_specs())).not_contains([UIText.t("button.undo")])


# --- the ruler ---

func _drag_board(r: GameRoot, from_px: Vector2, to_px: Vector2) -> void:
	r.board._on_press(from_px, false)
	r.board._on_motion(to_px, to_px - from_px)
	r.board._on_release(to_px)


func test_a_ruler_drag_measures_and_never_moves_or_pans() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	await await_idle_frame()
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	r._on_unit_tapped(u)
	r._set_ruler(true)
	var a: Vector2 = r.board.world_to_screen(u.models[0]["pos"])
	var b: Vector2 = r.board.world_to_screen(u.models[0]["pos"] + Vector2(10, 0))
	var pan: Vector2 = r.board._pan

	# Act
	_drag_board(r, a, b)

	# Assert
	assert_bool(r.board.has_measurement()).is_true()
	assert_float(Ruler.inches(r.board.measurement()[0], r.board.measurement()[1])).is_equal_approx(10.0, 0.01)
	assert_vector(r._delta).is_equal(Vector2.ZERO)
	assert_vector(r.board._pan).is_equal(pan)


func test_a_new_measurement_replaces_the_last_and_turning_off_clears_it() -> void:
	# Arrange
	var r: GameRoot = _game()
	await await_idle_frame()
	r._set_ruler(true)
	_drag_board(r, r.board.world_to_screen(Vector2(10, 10)), r.board.world_to_screen(Vector2(20, 10)))
	var first: Array[Vector2] = r.board.measurement().duplicate()

	# Act
	_drag_board(r, r.board.world_to_screen(Vector2(10, 20)), r.board.world_to_screen(Vector2(20, 20)))

	# Assert
	assert_array(r.board.measurement()).is_not_equal(first)
	r._set_ruler(false)
	assert_bool(r.board.has_measurement()).is_false()


func test_a_second_finger_keeps_the_previous_measurement() -> void:
	# Arrange
	var r: GameRoot = _game()
	await await_idle_frame()
	r._set_ruler(true)
	_drag_board(r, Vector2(300, 200), Vector2(400, 200))
	var kept: Array[Vector2] = r.board.measurement().duplicate()

	# Act: a new drag starts, then a pinch takes over
	r.board._on_press(Vector2(100, 100), false)
	r.board._on_motion(Vector2(150, 100), Vector2(50, 0))
	r.board._cancel_press()

	# Assert
	assert_array(r.board.measurement()).is_equal(kept)


func test_clear_removes_the_measurement_but_leaves_the_ruler_on() -> void:
	# Arrange
	var r: GameRoot = _game()
	await await_idle_frame()
	r._set_ruler(true)
	_drag_board(r, Vector2(300, 200), Vector2(400, 200))
	assert_bool(r._toolbar.clear.visible).is_true()

	# Act
	r._toolbar.clear_pressed.emit()

	# Assert
	assert_bool(r.board.has_measurement()).is_false()
	assert_bool(r.board.ruler_on).is_true()
	assert_bool(r._toolbar.clear.visible).is_false()


func test_the_r_key_toggles_the_ruler_and_the_toolbar_follows() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	r._unhandled_input(_action("ruler"))

	# Assert
	assert_bool(r.board.ruler_on).is_true()
	assert_bool(r._toolbar.ruler.button_pressed).is_true()


# --- side panel ---

func test_the_units_tab_lists_your_units_then_the_enemy() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	var rows: Array = r._units_view()

	# Assert
	assert_int(rows.size()).is_equal(r.battle.units.size())
	assert_int(int(rows[0]["side"])).is_equal(GameRoot.HUMAN)
	assert_int(int(rows[-1]["side"])).is_equal(1)


func test_a_unit_row_selects_that_unit_and_does_not_move_the_view() -> void:
	# Arrange
	var r: GameRoot = _game()
	var foe: UnitState = r.battle.living(1)[1]
	var pan: Vector2 = r.board._pan

	# Act
	r._on_unit_row_pressed(foe.id)

	# Assert
	assert_object(r._selected).is_same(foe)
	assert_vector(r.board._pan).is_equal(pan)


func test_acted_and_shocked_units_are_marked() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "movement")
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	r.battle.cmd_hold(u)
	u.battle_shocked = true

	# Act
	var marks: Array = r._units_view()[0]["marks"]

	# Assert
	assert_str(str(marks[0][0])).is_equal(UIText.t("chip.shocked_short"))
	assert_str(str(marks[1][0])).is_equal(UIText.t("chip.acted"))


func test_a_single_large_model_shows_wounds_and_a_squad_shows_models() -> void:
	# Arrange
	var r: GameRoot = _game()
	var squad: UnitState = null
	var large: UnitState = null
	for u in r.battle.living(GameRoot.HUMAN):
		if u.starting_strength == 1 and u.wounds_per_model > 1:
			large = u
		elif u.starting_strength > 1:
			squad = u

	# Act
	var rows: Dictionary = {}
	for row in r._units_view():
		rows[row["id"]] = row

	# Assert
	assert_str(str(rows[squad.id]["count"])).is_equal("%d/%d" % [squad.model_count(), squad.starting_strength])
	assert_str(str(rows[large.id]["count"])).is_equal("%d/%d W" % [large.total_wounds_left(), large.wounds_per_model])


func test_tapping_a_ranged_weapon_toggles_a_ring_at_its_range() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = null
	var index: int = -1
	for candidate in r.battle.living(GameRoot.HUMAN):
		for i in range(candidate.weapons.size()):
			if index < 0 and not candidate.weapons[i].is_melee():
				u = candidate
				index = i
	r._on_unit_tapped(u)

	# Act and assert
	r._on_weapon_pressed(index)
	r._refresh()
	assert_float(r.board.weapon_rings[0]).is_equal_approx(u.weapons[index].range_in + u.base_radius, 0.001)
	r._on_weapon_pressed(index)
	r._refresh()
	assert_array(r.board.weapon_rings).is_empty()


func test_a_melee_weapon_offers_no_ring() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	var melee := Weapon.new()
	u.weapons.append(melee)

	# Act
	var rows: Array = r._unit_view(u)["weapons"]

	# Assert
	assert_int(int(rows[-1][2])).is_equal(-1)


func test_orders_show_no_unit_card_and_the_unit_tab_does() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	r._on_unit_tapped(r.battle.living(GameRoot.HUMAN)[0])

	# Assert
	var orders: Control = r._side._pages[0].get_child(0)
	for c in orders.get_children():
		assert_bool(c is PanelContainer).is_false()
	assert_int(r._side._unit_box.get_child_count()).is_equal(1)


func test_a_drag_on_a_list_row_reaches_the_scrolling_list() -> void:
	# Act
	var row: TapRow = auto_free(TapRow.new("a"))

	# Assert
	assert_int(row.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)


# --- saving and carrying on ---

func test_tool_and_test_games_never_touch_the_save_or_settings() -> void:
	# Act
	var r: GameRoot = _game()

	# Assert
	assert_bool(r.persist).is_false()


func _saving_game() -> GameRoot:
	var r: GameRoot = _game()
	r.persist = true
	r.save_path = TEST_SAVE
	return r


func test_the_human_turn_start_writes_the_autosave() -> void:
	# Arrange
	var r: GameRoot = _saving_game()
	r._begun_key = ""

	# Act: a fresh turn key makes the battle begin a turn
	r._begin_turn_once()

	# Assert
	assert_bool(SaveFile.usable(TEST_SAVE)).is_true()


func test_the_ai_turn_start_does_not_save() -> void:
	# Arrange
	var r: GameRoot = _saving_game()
	while r.battle.active_player() == GameRoot.HUMAN:
		r.battle.flow.advance()

	# Act
	r._begin_turn_once()

	# Assert
	assert_bool(SaveFile.exists(TEST_SAVE)).is_false()


func test_continue_from_the_menu_picks_up_the_saved_battle() -> void:
	# Arrange: save a battle, then leave for the menu
	var r: GameRoot = _saving_game()
	var vp_marker: int = 7
	r.battle.vp[0] = vp_marker
	r._autosave()
	r._leave_battle()
	r._show_title()
	assert_bool(r._title.has_save).is_true()

	# Act
	r._on_continue_pressed()

	# Assert
	assert_int(r.battle.vp[0]).is_equal(vp_marker)
	assert_str(r._begun_key).is_equal(r._turn_key())
	assert_object(r._title).is_null()


func test_a_finished_battle_deletes_the_save() -> void:
	# Arrange
	var r: GameRoot = _saving_game()
	r._autosave()
	r.battle.flow.finished = true

	# Act
	r._show_game_over()

	# Assert
	assert_bool(SaveFile.exists(TEST_SAVE)).is_false()
	assert_bool(r._over_panel.visible).is_true()


func test_resume_does_not_start_the_turn_again() -> void:
	# Arrange: a save made at the start of the human's turn
	var r: GameRoot = _game()
	var cp: Array = r.battle.flow.command_points.duplicate()
	var armies: Array = r._armies_in_play
	var data: Dictionary = {"battle": r.battle.to_save(), "armies": armies}
	assert_bool(SaveFile.write(data, TEST_SAVE)).is_true()
	var read: Dictionary = SaveFile.read(TEST_SAVE)

	# Act
	r._resume_battle(Battle.from_save(read["battle"]), read["armies"])

	# Assert
	assert_array(r.battle.flow.command_points).is_equal(cp)
	assert_int(r._event_cursor).is_equal(r.battle.events.size())
	assert_int(r._log_lines.size()).is_greater(0)


func test_the_log_keeps_the_names_of_destroyed_units_after_resuming() -> void:
	# Arrange
	var r: GameRoot = _game()
	var gone: UnitState = r.battle.living(1)[0]
	gone.models.clear()
	r.battle.remove_destroyed()
	var data: Dictionary = {"battle": r.battle.to_save(), "armies": r._armies_in_play}
	SaveFile.write(data, TEST_SAVE)
	var read: Dictionary = SaveFile.read(TEST_SAVE)

	# Act
	r._resume_battle(Battle.from_save(read["battle"]), read["armies"])

	# Assert
	assert_str(str(r._names[gone.id])).is_equal(gone.unit_name)
	var texts: Array = r._log_lines.map(func(l: Dictionary) -> String: return str(l["text"]))
	assert_str(" ".join(texts)).contains(gone.unit_name)


func test_save_file_round_trip_and_erase() -> void:
	# Arrange
	var data: Dictionary = {"battle": {"version": Battle.SAVE_VERSION}, "armies": []}

	# Act
	SaveFile.write(data, TEST_SAVE)

	# Assert
	assert_bool(SaveFile.usable(TEST_SAVE)).is_true()
	SaveFile.erase(TEST_SAVE)
	assert_bool(SaveFile.exists(TEST_SAVE)).is_false()


func test_a_new_save_replaces_the_old_one() -> void:
	# Arrange
	SaveFile.write({"battle": {"version": 1}, "armies": [], "marker": "first"}, TEST_SAVE)

	# Act
	var wrote: bool = SaveFile.write({"battle": {"version": 1}, "armies": [], "marker": "second"}, TEST_SAVE)

	# Assert
	assert_bool(wrote).is_true()
	assert_str(str(SaveFile.read(TEST_SAVE)["marker"])).is_equal("second")


func test_a_damaged_save_is_not_offered() -> void:
	# Arrange
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()

	# Act and assert
	assert_bool(SaveFile.usable(TEST_SAVE)).is_false()
	assert_dict(SaveFile.read(TEST_SAVE)).is_empty()


func test_the_reanimation_setting_reaches_the_battle() -> void:
	# Arrange
	var r: GameRoot = _game()
	r.settings.reanimate_models = false

	# Act
	r._settings_changed()

	# Assert
	assert_bool(r.battle.reanimate_models).is_false()


# --- menus outside a battle ---

func _title_game() -> GameRoot:
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.persist = false
	r.placeholder_only = true
	return r


func test_continue_shows_only_when_a_save_exists() -> void:
	# Arrange
	var without: GameRoot = _title_game()
	add_child(without)
	var with_save: GameRoot = _title_game()
	with_save.show_continue = true
	add_child(with_save)

	# Assert
	var count_without: int = without._title._menu.get_child_count()
	assert_int(with_save._title._menu.get_child_count()).is_equal(count_without + 1)


func test_settings_open_from_the_title_and_close_back_to_it() -> void:
	# Arrange
	var r: GameRoot = _title_game()
	add_child(r)

	# Act
	r._open_settings()
	assert_bool(r._dialog_open()).is_true()
	(r.get_child(-1) as DialogBox).close()

	# Assert
	assert_bool(r._dialog_open()).is_false()
	assert_object(r._title).is_not_null()


func test_game_keys_on_the_title_do_nothing() -> void:
	# Arrange
	var r: GameRoot = _title_game()
	add_child(r)

	# Act and assert: no battle, so this must not crash
	r._unhandled_input(_action("next_phase"))
	assert_object(r.battle).is_null()
