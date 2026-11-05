extends GdUnitTestSuite

func _battle(seed_value: int = 1) -> Battle:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	sc["terrain"] = []
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var b := Battle.new(sc, armies, seed_value)
	b.ai_sides = [false, true]
	return b

func _place(u: UnitState, at: Vector2) -> void:
	var shift: Vector2 = at - u.models[0]["pos"]
	for m in u.models:
		m["pos"] += shift

func _unit(b: Battle, side: int, index: int) -> UnitState:
	return b.living(side)[index]

func _to_phase(b: Battle, wanted: String) -> void:
	var guard: int = 0
	while b.phase() != wanted and guard < 10:
		guard += 1
		b.next_phase()

func _v(p: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for x in p:
		out.append(x)
	return out

func _shifted(u: UnitState, d: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"] + d)
	return out

# --- structure ---

func test_turn_starts_in_the_command_phase_with_cp_for_both_players() -> void:
	var b := _battle()
	b.begin_turn()
	assert_str(b.phase()).is_equal("command")
	assert_array(b.flow.command_points).is_equal([1, 1])

func test_phases_advance_in_order() -> void:
	var b := _battle()
	b.begin_turn()
	var seen: Array[String] = [b.phase()]
	for i in range(3):
		b.next_phase()
		seen.append(b.phase())
	assert_array(seen).is_equal(["command", "movement", "shooting", "charge"])

func test_ending_the_turn_passes_play_to_the_other_player() -> void:
	var b := _battle()
	b.begin_turn()
	for i in range(4):
		b.next_phase()   # command -> movement -> shooting -> charge -> fight (pile in)
	assert_str(b.phase()).is_equal("fight")
	assert_str(b.fight_stage).is_equal("pile_in")
	b.next_phase()       # -> fight
	b.next_phase()       # nothing engaged so fighting is finished -> consolidate
	b.next_phase()       # -> end turn
	assert_int(b.active_player()).is_equal(1)
	assert_str(b.phase()).is_equal("command")

func test_fight_step_cannot_end_while_units_are_still_to_fight() -> void:
	var b := _battle()
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 0)
	_place(a, Vector2(20, 10))
	_place(e, Vector2(22.2, 10))
	b.begin_turn()
	_to_phase(b, "fight")
	b.next_phase()  # pile in -> fight
	assert_bool(b.next_phase()["ok"]).is_false()

# --- movement commands ---

func test_moving_in_the_wrong_phase_is_refused() -> void:
	var b := _battle()
	b.begin_turn()
	var u := _unit(b, 0, 0)
	assert_bool(b.cmd_move(u, _shifted(u, Vector2(3, 0)), "normal")["ok"]).is_false()

func test_moving_the_opponents_unit_is_refused() -> void:
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var enemy := _unit(b, 1, 0)
	assert_bool(b.cmd_move(enemy, _shifted(enemy, Vector2(-3, 0)), "normal")["ok"]).is_false()

func test_a_legal_move_changes_positions_and_records_an_event() -> void:
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var u := _unit(b, 0, 0)
	var start: Vector2 = u.models[0]["pos"]
	assert_bool(b.cmd_move(u, _shifted(u, Vector2(3, 0)), "normal")["ok"]).is_true()
	assert_float(u.models[0]["pos"].x).is_equal_approx(start.x + 3.0, 0.001)
	assert_str(b.events[-1]["type"]).is_equal("move")

func test_a_unit_can_only_move_once_per_turn() -> void:
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var u := _unit(b, 0, 0)
	b.cmd_move(u, _shifted(u, Vector2(3, 0)), "normal")
	assert_bool(b.cmd_move(u, _shifted(u, Vector2(1, 0)), "normal")["ok"]).is_false()

func test_an_illegal_move_leaves_the_unit_where_it_was() -> void:
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var u := _unit(b, 0, 0)
	var start: Vector2 = u.models[0]["pos"]
	var r := b.cmd_move(u, _shifted(u, Vector2(30, 0)), "normal")
	assert_bool(r["ok"]).is_false()
	assert_str(r["reason"]).is_not_empty()
	assert_vector(u.models[0]["pos"]).is_equal(start)

func test_advance_needs_the_roll_first_and_uses_it() -> void:
	var b := _battle(5)
	b.begin_turn()
	b.next_phase()
	var u := _unit(b, 0, 0)
	assert_bool(b.preview_move(u, _shifted(u, Vector2(7, 0)), "advance")["ok"]).is_false()
	var roll: int = b.cmd_roll_advance(u)["roll"]
	assert_int(roll).is_between(1, 6)
	assert_int(b.cmd_roll_advance(u)["roll"]).is_equal(roll)  # rolled once only
	var ok: bool = b.preview_move(u, _shifted(u, Vector2(u.move + float(roll), 0)), "advance")["ok"]
	assert_bool(ok).is_true()
	assert_bool(b.preview_move(u, _shifted(u, Vector2(u.move + float(roll) + 0.6, 0)), "advance")["ok"]).is_false()

func test_preview_does_not_change_anything() -> void:
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var u := _unit(b, 0, 0)
	var start: Vector2 = u.models[0]["pos"]
	var events_before: int = b.events.size()
	b.preview_move(u, _shifted(u, Vector2(3, 0)), "normal")
	assert_vector(u.models[0]["pos"]).is_equal(start)
	assert_int(b.events.size()).is_equal(events_before)
	assert_bool(b.has_moved(u)).is_false()

# --- shooting ---

func test_shooting_previews_odds_and_then_resolves_once() -> void:
	var b := _battle(3)
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 2)   # Grove Colossus, too tough to die in one volley
	_place(a, Vector2(10, 10))
	_place(e, Vector2(20, 10))
	b.begin_turn()
	_to_phase(b, "shooting")
	var preview := b.shoot_preview(a, e)
	assert_bool(preview.is_empty()).is_false()
	assert_float(preview[0]["odds"]["attacks"]).is_greater(0.0)
	var wounds_before: int = e.total_wounds_left()
	assert_bool(b.cmd_shoot(a, e)["ok"]).is_true()
	assert_int(e.total_wounds_left()).is_less_equal(wounds_before)
	assert_bool(b.cmd_shoot(a, e)["ok"]).is_false()

func test_shooting_a_unit_out_of_range_is_refused_with_a_reason() -> void:
	var b := _battle()
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 0)
	_place(a, Vector2(2, 2))
	_place(e, Vector2(42, 28))
	b.begin_turn()
	_to_phase(b, "shooting")
	var r := b.cmd_shoot(a, e)
	assert_bool(r["ok"]).is_false()
	assert_str(r["reason"]).contains("reach")

func test_shooting_your_own_unit_is_refused() -> void:
	var b := _battle()
	b.begin_turn()
	_to_phase(b, "shooting")
	assert_bool(b.cmd_shoot(_unit(b, 0, 0), _unit(b, 0, 1))["ok"]).is_false()

# --- charge ---

func test_declaring_a_charge_rolls_once_and_lists_targets() -> void:
	var b := _battle(2)
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 0)
	_place(a, Vector2(10, 10))
	_place(e, Vector2(22, 10))
	b.begin_turn()
	_to_phase(b, "charge")
	var r := b.cmd_declare_charge(a)
	assert_str(r["reason"]).is_empty()
	assert_bool(r["ok"]).is_true()
	assert_int(r["roll"]).is_between(2, 12)
	assert_bool(b.cmd_declare_charge(a)["ok"]).is_false()

func test_a_successful_charge_makes_the_unit_fights_first_and_eligible_to_fight() -> void:
	var b := _battle(2)
	var a := _unit(b, 0, 1)   # Assault Squad
	var e := _unit(b, 1, 0)
	_place(a, Vector2(10, 10))
	_place(e, Vector2(22, 10))
	b.begin_turn()
	_to_phase(b, "charge")
	b.dice = Dice.new(1, [6, 6] as Array[int])  # charge roll of 12
	var declared := b.cmd_declare_charge(a)
	assert_bool(declared["ok"]).is_true()
	assert_int(declared["roll"]).is_equal(12)
	var targets: Array[UnitState] = [e]
	var r := b.cmd_charge_move(a, _shifted(a, Vector2(4.5, 0)), targets)
	assert_str(r["reason"]).is_empty()
	assert_bool(a.is_fights_first()).is_true()
	assert_bool(b.charge_finished(a)).is_true()

func test_a_charge_that_does_not_reach_is_refused_and_can_be_given_up() -> void:
	var b := _battle(2)
	var a := _unit(b, 0, 1)
	var e := _unit(b, 1, 0)
	_place(a, Vector2(10, 10))
	_place(e, Vector2(22, 10))
	b.begin_turn()
	_to_phase(b, "charge")
	b.dice = Dice.new(1, [6, 6] as Array[int])
	b.cmd_declare_charge(a)
	var targets: Array[UnitState] = [e]
	assert_bool(b.cmd_charge_move(a, _shifted(a, Vector2(1.0, 0)), targets)["ok"]).is_false()
	assert_bool(b.cmd_charge_fail(a)["ok"]).is_true()
	assert_bool(a.is_fights_first()).is_false()

func test_charge_move_before_declaring_is_refused() -> void:
	var b := _battle()
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 0)
	b.begin_turn()
	_to_phase(b, "charge")
	var targets: Array[UnitState] = [e]
	assert_bool(b.cmd_charge_move(a, _shifted(a, Vector2(1, 0)), targets)["ok"]).is_false()

# --- fight ---

func _engaged_battle() -> Array:
	var b := _battle(4)
	var a := _unit(b, 0, 0)
	var e := _unit(b, 1, 0)
	_place(a, Vector2(20, 10))
	_place(e, Vector2(23.1, 10))
	for m in e.models:
		m["pos"].y += 0.0
	b.begin_turn()
	_to_phase(b, "fight")
	return [b, a, e]

func test_fight_sequence_lets_each_engaged_unit_fight_once() -> void:
	var s := _engaged_battle()
	var b: Battle = s[0]
	var a: UnitState = s[1]
	var e: UnitState = s[2]
	b.next_phase()  # to fight stage
	assert_int(b.fight_chooser()).is_equal(0)
	assert_bool(b.cmd_fight(a, e)["ok"]).is_true()
	assert_bool(b.cmd_fight(a, e)["ok"]).is_false()
	assert_int(b.fight_chooser()).is_equal(1)

func test_the_wrong_player_cannot_pick_a_fighter() -> void:
	var s := _engaged_battle()
	var b: Battle = s[0]
	b.next_phase()
	assert_bool(b.cmd_fight(s[2], s[1])["ok"]).is_false()

func test_pile_in_step_is_only_available_before_the_fight_step() -> void:
	var s := _engaged_battle()
	var b: Battle = s[0]
	var a: UnitState = s[1]
	assert_bool(b.can_pile_in(a)).is_true()
	b.next_phase()
	assert_bool(b.can_pile_in(a)).is_false()

func test_ai_vs_ai_turn_helper_still_plays_whole_battle() -> void:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var r: Dictionary = Battle.new(sc, armies, 8).play_all()
	assert_int(r["rounds"]).is_between(1, 5)
