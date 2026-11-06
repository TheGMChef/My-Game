extends GdUnitTestSuite
## Deployment, stratagem prompts and the Stratagems tab through GameRoot's own handlers. The
## armies are the invented placeholder ones.

const AI := 1
const HUMAN := GameRoot.HUMAN
const FRAME_LIMIT := 300


func _game(prompts: bool = true) -> GameRoot:
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_roster = true
	r.full_flow = true
	r.battle_seed = 7
	r.settings.reduced_motion = true
	r.settings.stratagem_prompts = prompts
	add_child(r)
	return r


## All units placed, the human won the roll-off, and it is the human's Command phase.
func _started(prompts: bool = true) -> GameRoot:
	var r: GameRoot = _game(prompts)
	r.battle.cmd_auto_deploy()
	r.battle.dice = Dice.new(1, [6, 1])
	await r._on_start_battle_pressed()
	r.battle.dice = Dice.new(3)
	r.battle.flow.command_points = [5, 5]
	return r


## End the human's phases until the game stops on a prompt or comes back to the human's next turn.
## The AI loop is not awaited, because it is what waits on the prompt.
func _play_until_prompt(r: GameRoot) -> void:
	var start_round: int = r.battle.flow.round_no
	_bring_the_enemy_close(r)
	for i in range(FRAME_LIMIT):
		if r.prompt_open():
			return
		if not r._busy and r.battle.active_player() == HUMAN and r.battle.flow.round_no > start_round:
			return
		if not r._busy and r.battle.fight_chooser() == HUMAN:
			r._on_unit_tapped(r.battle.fight_options()[0])
			r._on_skip_fight_pressed()
		elif not r._busy:
			r._on_next_pressed()
		await get_tree().process_frame


## Enemy units just out of engagement range of the human's first unit, so it has a shot.
func _bring_the_enemy_close(r: GameRoot) -> void:
	var mine: UnitState = r.battle.living(HUMAN)[0]
	var y: float = 3.0
	for e: UnitState in r.battle.living(AI):
		var offset: Vector2 = Vector2(mine.centre().x + 14.0, y) - e.centre()
		for m in e.models:
			m["pos"] = m["pos"] + offset
		y += 9.0


func _spec_text(r: GameRoot, key: String) -> Dictionary:
	for s in r._action_specs():
		if str(s.get("text", "")) == UIText.t(key):
			return s
	return {}


# ---------------------------------------------------------------- deployment

func test_a_full_game_opens_on_deployment_with_the_ai_placed_first() -> void:
	# Arrange and act
	var r: GameRoot = _game()
	await get_tree().process_frame

	# Assert
	assert_bool(r.battle.deployment_active).is_true()
	assert_str(r.battle.phase()).is_equal("deployment")
	assert_int(r.battle.units.size()).is_equal(1)
	assert_int(r.battle.units[0].owner).is_equal(AI)
	assert_bool(r._tray.visible).is_true()
	assert_str(r._next_label()).is_equal(UIText.t("next.auto_deploy"))


func test_a_skip_roster_game_keeps_its_automatic_start() -> void:
	# Arrange
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_roster = true

	# Act
	add_child(r)

	# Assert
	assert_bool(r.battle.deployment_active).is_false()
	assert_str(r.battle.phase()).is_equal("command")
	assert_bool(r.battle.prompt_sides[HUMAN]).is_false()


func test_tapping_a_tray_unit_shows_a_legal_ghost_and_placing_passes_the_turn() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = r.battle.undeployed_of(HUMAN)[0]

	# Act
	r._on_tray_pressed(u.id)

	# Assert
	assert_bool(r._placing()).is_true()
	assert_bool(r.board.ghost.is_empty()).is_false()
	assert_bool(r.board.deploy_drag).is_true()
	var place: Dictionary = _spec_text(r, "button.place_unit")
	assert_bool(bool(place["disabled"])).is_false()

	# Act
	await r._on_place_pressed()

	# Assert: placed, and the AI has answered with its next unit
	assert_bool(r.battle.units.has(u)).is_true()
	assert_bool(r._placing()).is_false()
	assert_int(r.battle.units.filter(func(x: UnitState) -> bool: return x.owner == AI).size()).is_equal(2)


func test_dragging_out_of_the_zone_disables_placing_and_says_why() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = r.battle.undeployed_of(HUMAN)[0]
	r._on_tray_pressed(u.id)

	# Act
	r._on_drag_moved(u, Vector2(25, 0))

	# Assert
	assert_bool(bool(_spec_text(r, "button.place_unit")["disabled"])).is_true()
	assert_str(r._orders_detail()).contains("zone")
	assert_str(str(r._action_specs()[0]["hint"]).to_lower()).contains("zone")


func test_a_finished_drag_stays_where_it_was_dropped() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = r.battle.undeployed_of(HUMAN)[0]
	r._on_tray_pressed(u.id)
	var start: Vector2 = r._middle_of(r._ghost_positions())

	# Act
	r._on_drag_moved(u, Vector2(1, 1))
	r._on_drag_ended(u, Vector2(1, 1))

	# Assert
	assert_vector(r._middle_of(r._ghost_positions())).is_equal_approx(start + Vector2(1, 1), Vector2(0.01, 0.01))


func test_tapping_the_board_moves_the_unit_being_placed_there() -> void:
	# Arrange
	var r: GameRoot = _game()
	var u: UnitState = r.battle.undeployed_of(HUMAN)[0]
	r._on_tray_pressed(u.id)

	# Act
	r._on_empty_tapped(Vector2(6, 20))

	# Assert
	assert_bool(r._placing()).is_true()
	assert_vector(r._middle_of(r._ghost_positions())).is_equal_approx(Vector2(6, 20), Vector2(0.01, 0.01))


func test_auto_deploy_then_start_battle_reaches_a_turn() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	r._request_next()
	assert_bool(r.battle.deployment_ready()).is_true()
	assert_bool(bool(_spec_text(r, "button.start_battle")["disabled"])).is_false()
	await r._on_confirm_pressed()

	# Assert
	assert_bool(r.battle.deployment_active).is_false()
	assert_int(r.battle.active_player()).is_equal(HUMAN)
	assert_int(r.battle.turn_no).is_greater(0)
	assert_bool(r._log_lines.any(func(l: Dictionary) -> bool: return str(l["text"]).contains("Roll-off"))).is_true()


func test_a_saved_deployment_resumes_on_the_deployment_screen() -> void:
	# Arrange
	var first: GameRoot = _game()
	var data: Dictionary = JSON.parse_string(JSON.stringify(first.battle.to_save(), "", true, true))
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_title = true
	add_child(r)
	r._roster.queue_free()
	r._roster = null

	# Act
	r._resume_battle(Battle.from_save(data), first._armies_in_play)

	# Assert
	assert_bool(r.battle.deployment_active).is_true()
	assert_bool(r._tray.visible).is_true()
	assert_int(r.battle.deploy_side()).is_equal(HUMAN)


func test_cp_stay_on_show_in_the_phone_layout() -> void:
	# Arrange
	var r: GameRoot = await _started()

	# Act
	r._refresh()

	# Assert
	assert_str(r._phone_hud._cp.text).is_equal(UIText.t("hud.cp_both", [5, 5]))


# ---------------------------------------------------------------- prompts

func test_the_ai_turn_stops_for_a_prompt_and_stays_stopped() -> void:
	# Arrange
	var r: GameRoot = await _started()

	# Act
	await _play_until_prompt(r)
	var events_then: int = r.battle.events.size()
	for i in range(30):
		await get_tree().process_frame

	# Assert
	assert_bool(r.prompt_open()).is_true()
	assert_bool(r._prompt.visible).is_true()
	assert_int(r.battle.active_player()).is_equal(AI)
	assert_int(r.battle.events.size()).is_equal(events_then)
	assert_array(r._action_specs()).is_empty()
	r._on_prompt_pass()


func test_use_spends_the_cp_logs_it_and_the_turn_carries_on() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)
	var cp: int = r.battle.command_points(HUMAN)
	var id: String = r._prompt_options[0]["id"]

	# Act
	r._on_prompt_use(0)
	for i in range(5):
		await get_tree().process_frame

	# Assert
	assert_int(r.battle.command_points(HUMAN)).is_less(cp)
	var name_text: String = UIText.t("strat.%s.name" % id)
	assert_bool(r._log_lines.any(func(l: Dictionary) -> bool: return str(l["text"]).contains(name_text))).is_true()


func test_pass_spends_nothing_and_the_turn_carries_on() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)
	var cp: int = r.battle.command_points(HUMAN)
	var window: String = r.battle.pending["window"]

	# Act
	r._on_prompt_pass()
	await get_tree().process_frame

	# Assert
	assert_bool(r._prompt.visible and str(r.battle.pending.get("window", "")) == window).is_false()
	assert_int(r.battle.command_points(HUMAN)).is_equal(cp)


func test_prompts_off_never_stops_the_ai_turn() -> void:
	# Arrange
	var r: GameRoot = await _started(false)

	# Act
	await _play_until_prompt(r)

	# Assert: straight through to the human's next turn
	assert_bool(r.prompt_open()).is_false()
	assert_int(r.battle.flow.round_no).is_equal(2)
	assert_int(r.battle.active_player()).is_equal(HUMAN)


func test_no_cp_means_no_prompt() -> void:
	# Arrange: CP are gained in every Command phase, so spend them as they come
	var r: GameRoot = await _started()
	r.battle.flow.command_points = [-3, 5]

	# Act
	await _play_until_prompt(r)

	# Assert
	assert_bool(r.prompt_open()).is_false()


func test_turning_the_setting_off_mid_battle_applies_at_once() -> void:
	# Arrange
	var r: GameRoot = await _started()

	# Act
	r.settings.stratagem_prompts = false
	r._settings_changed()

	# Assert
	assert_bool(r.battle.prompt_sides[HUMAN]).is_false()


func test_leaving_the_battle_during_a_prompt_ends_the_wait() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)
	assert_bool(r.prompt_open()).is_true()

	# Act
	r._leave_battle()
	for i in range(5):
		await get_tree().process_frame

	# Assert
	assert_bool(r.prompt_open()).is_false()
	assert_object(r.battle).is_null()
	assert_bool(r._busy).is_false()


func test_restarting_during_a_prompt_starts_clean() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)

	# Act
	r._restart()
	await get_tree().process_frame

	# Assert
	assert_bool(r.prompt_open()).is_false()
	assert_bool(r._prompt.visible).is_false()
	assert_bool(r.battle.deployment_active).is_true()
	assert_bool(r._busy).is_false()


func test_a_save_taken_at_a_prompt_asks_again_on_resume() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)
	var data: Dictionary = JSON.parse_string(JSON.stringify(r.battle.to_save(), "", true, true))
	var again: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	again.skip_title = true
	again.settings.reduced_motion = true
	add_child(again)
	again._roster.queue_free()
	again._roster = null

	# Act
	again._resume_battle(Battle.from_save(data), r._armies_in_play)
	await get_tree().process_frame

	# Assert
	assert_bool(again.prompt_open()).is_true()
	again._on_prompt_pass()
	r._on_prompt_pass()


func test_the_pause_menu_opens_over_a_prompt() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await _play_until_prompt(r)

	# Act
	r._request_pause()

	# Assert
	assert_object(r._pause).is_not_null()
	r._pause.close()
	r._on_prompt_pass()


func test_a_prompt_nobody_answers_is_reported_by_the_bot() -> void:
	# Arrange: a game certain to reach a prompt
	var r: GameRoot = await _started()
	await _play_until_prompt(r)
	var bot := PlaytestBot.new(r, 3)
	bot.answer_prompts = false

	# Act
	var result: Dictionary = await bot.play()

	# Assert
	assert_str(result["outcome"]).is_equal("prompt_blocked")
	r._on_prompt_pass()


# ---------------------------------------------------------------- the Stratagems tab

func _row(r: GameRoot, id: String) -> Dictionary:
	for row in r._stratagem_view()["rows"]:
		if row["id"] == id:
			return row
	return {}


func test_the_tab_lists_every_stratagem_with_a_cost_and_an_effect() -> void:
	# Arrange
	var r: GameRoot = await _started()

	# Act
	var view: Dictionary = r._stratagem_view()

	# Assert
	assert_int((view["rows"] as Array).size()).is_equal(Stratagems.DEFS.size())
	assert_str(str(view["cp"])).is_equal(UIText.t("strat.cp_line", [5, 5]))
	for row in view["rows"]:
		assert_str(str(row["effect"])).is_not_empty()
		assert_bool(str(row["button"]) != "" or str(row["reason"]) != "").is_true()


func test_rapid_ingress_is_greyed_because_reserves_do_not_exist() -> void:
	# Arrange
	var r: GameRoot = await _started()

	# Act
	var row: Dictionary = _row(r, "rapid_ingress")

	# Assert
	assert_str(str(row["button"])).is_empty()
	assert_str(str(row["reason"])).is_equal(UIText.t("strat.reason.no_reserves"))


func test_a_playable_stratagem_rises_to_the_top_of_the_tab_and_works() -> void:
	# Arrange: in shooting, with grenades in range
	var r: GameRoot = await _started()
	await r._on_next_pressed()
	await r._on_next_pressed()
	assert_str(r.battle.phase()).is_equal("shooting")
	var mine: UnitState = r.battle.living(HUMAN).filter(func(u: UnitState) -> bool: return u.has_keyword("GRENADES"))[0]
	var foe: UnitState = r.battle.living(AI)[0]
	var offset: Vector2 = Vector2(mine.centre().x + 13.0, mine.centre().y) - foe.centre()
	for m in foe.models:
		m["pos"] = m["pos"] + offset
	r._refresh()

	# Act
	var first: Dictionary = r._stratagem_view()["rows"][0]
	await r._on_stratagem_pressed("explosives")

	# Assert
	assert_str(str(first["id"])).is_equal("explosives")
	assert_int(r.battle.command_points(HUMAN)).is_equal(4)
	assert_str(str(_row(r, "explosives")["reason"])).is_equal(UIText.t("strat.reason.used_phase"))


func test_the_action_bar_offers_a_reroll_after_an_advance() -> void:
	# Arrange
	var r: GameRoot = await _started()
	await r._on_next_pressed()
	var u: UnitState = r.battle.living(HUMAN)[0]
	r._on_unit_tapped(u)

	# Act
	r._set_mode("advance")

	# Assert
	var text: String = UIText.t("button.reroll", [1])
	var found: Array = r._action_specs().filter(func(s: Dictionary) -> bool: return str(s.get("text", "")) == text)
	assert_int(found.size()).is_equal(1)


func test_bot_full_games_deploy_and_use_stratagems() -> void:
	# Arrange
	var used: Dictionary = {}

	# Act
	for seed_value in [21, 22, 23]:
		var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
		r.skip_roster = true
		r.full_flow = true
		r.battle_seed = seed_value
		r.settings.reduced_motion = true
		add_child(r)
		var result: Dictionary = await PlaytestBot.new(r, seed_value).play()
		assert_str(result["outcome"]).is_equal("finished")
		used.merge(result["stratagems"])
		assert_bool((result["actions"] as Dictionary).has("deploy") or r.battle.events.any(func(e: Dictionary) -> bool: return e["type"] == "deploy")).is_true()

	# Assert
	assert_dict(used).is_not_empty()
