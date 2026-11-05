extends GdUnitTestSuite

const BOARD := Rect2(0, 0, 44, 30)

func _unit(owner: int, positions: Array[Vector2], extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"models": positions.size(), "base_mm": 25.4}
	d.merge(extra, true)
	var u := UnitState.from_dict(d, "u%d_%d" % [owner, randi() % 100000], owner, Vector2.ZERO)
	for i in range(positions.size()):
		u.models[i]["pos"] = positions[i]
	return u

func _v(points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in points:
		out.append(p)
	return out

# --- charge eligibility (11.02) ---

func test_unit_within_twelve_inches_of_an_enemy_can_declare_a_charge() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(20, 10)]))
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_true()

func test_unit_more_than_twelve_inches_away_cannot_declare_a_charge() -> void:
	var a := _unit(0, _v([Vector2(5, 10)]))
	var b := _unit(1, _v([Vector2(30, 10)]))
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_false()

func test_engaged_unit_cannot_declare_a_charge() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(11.5, 10)]))
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_false()

func test_unit_that_advanced_or_fell_back_cannot_declare_a_charge() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(20, 10)]))
	a.advanced = true
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_false()
	a.advanced = false
	a.fell_back = true
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_false()

func test_charge_roll_is_2d6() -> void:
	assert_int(ChargeRules.charge_roll(Dice.new(1, [3, 4] as Array[int]))).is_equal(7)

func test_targets_must_be_within_the_roll() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var near := _unit(1, _v([Vector2(17, 10)]))   # gap 6
	var far := _unit(1, _v([Vector2(24, 10)]))    # gap 13
	var t := ChargeRules.possible_targets(a, [a, near, far], 7)
	assert_int(t.size()).is_equal(1)
	assert_bool(t.has(near)).is_true()

# --- charge move (11.04) ---

func test_charge_that_ends_engaged_with_the_target_is_legal() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(17, 10)]))
	var targets: Array[UnitState] = [b]
	var r := ChargeRules.check_move(a, _v([Vector2(15, 10)]), targets, 7, [a, b], BOARD)  # gap 1.0
	assert_bool(r["ok"]).is_true()

func test_charge_that_falls_short_of_engagement_is_illegal() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(17, 10)]))
	var targets: Array[UnitState] = [b]
	var r := ChargeRules.check_move(a, _v([Vector2(13, 10)]), targets, 7, [a, b], BOARD)  # gap 3.0
	assert_bool(r["ok"]).is_false()

func test_charge_further_than_the_roll_is_illegal() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(17, 10)]))
	var targets: Array[UnitState] = [b]
	var r := ChargeRules.check_move(a, _v([Vector2(15, 10)]), targets, 4, [a, b], BOARD)
	assert_bool(r["ok"]).is_false()

func test_charge_may_not_engage_a_non_target_enemy() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(17, 10)]))
	var c := _unit(1, _v([Vector2(15, 12.5)]))  # would be within 2" of the charger
	var targets: Array[UnitState] = [b]
	var r := ChargeRules.check_move(a, _v([Vector2(15, 10)]), targets, 7, [a, b, c], BOARD)
	assert_bool(r["ok"]).is_false()

func test_charge_must_engage_every_target() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(17, 10)]))
	var c := _unit(1, _v([Vector2(10, 18)]))
	var targets: Array[UnitState] = [b, c]
	var r := ChargeRules.check_move(a, _v([Vector2(15, 10)]), targets, 8, [a, b, c], BOARD)
	assert_bool(r["ok"]).is_false()

func test_a_unit_that_charged_is_a_fights_first_unit() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	assert_bool(a.is_fights_first()).is_false()
	ChargeRules.apply_move(a, _v([Vector2(15, 10)]))
	assert_bool(a.is_fights_first()).is_true()

# --- pile-in (12.03) ---

func test_pile_in_moves_closer_and_stays_engaged() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(11.8, 10)]))  # gap 0.8 -> engaged, not in contact
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(10.8, 10)]), [a, b], BOARD)  # gap 0.0? 11.8-10.8-1=0.0
	assert_bool(r["ok"]).is_true()

func test_pile_in_further_than_three_inches_is_illegal() -> void:
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 11.2)]))
	var b := _unit(1, _v([Vector2(11.8, 10)]))
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(10.8, 10), Vector2(10, 15)]), [a, b], BOARD)
	assert_bool(r["ok"]).is_false()

func test_model_in_base_contact_cannot_pile_in() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(11, 10)]))  # touching
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(10, 10.5)]), [a, b], BOARD)
	assert_bool(r["ok"]).is_false()

func test_unengaged_unit_that_did_not_charge_cannot_pile_in() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(14, 10)]))
	assert_bool(MeleeMoves.can_pile_in(a, [a, b])).is_false()

func test_pile_in_move_that_moves_away_is_illegal() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(11.8, 10)]))
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(9, 10)]), [a, b], BOARD)
	assert_bool(r["ok"]).is_false()

# --- consolidation (12.08) ---

func test_consolidation_mode_follows_the_priority_order() -> void:
	var objs: Array[Vector2] = [Vector2(10, 14)]
	var engaged_unit := _unit(0, _v([Vector2(10, 10)]))
	var enemy := _unit(1, _v([Vector2(11.8, 10)]))
	assert_str(MeleeMoves.consolidation_mode(engaged_unit, [engaged_unit, enemy], objs, 3.0)).is_equal("ongoing")
	var near := _unit(0, _v([Vector2(10, 10)]))
	var enemy2 := _unit(1, _v([Vector2(13.5, 10)]))  # gap 2.5 -> within 3", not engaged
	assert_str(MeleeMoves.consolidation_mode(near, [near, enemy2], objs, 3.0)).is_equal("engaging")
	var alone := _unit(0, _v([Vector2(10, 12)]))
	assert_str(MeleeMoves.consolidation_mode(alone, [alone], objs, 3.0)).is_equal("objective")
	var nowhere := _unit(0, _v([Vector2(30, 25)]))
	assert_str(MeleeMoves.consolidation_mode(nowhere, [nowhere], objs, 3.0)).is_equal("none")

func test_engaging_consolidation_must_end_engaged_with_the_enemy() -> void:
	var objs: Array[Vector2] = []
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(13.5, 10)]))
	assert_bool(MeleeMoves.check_consolidation(a, _v([Vector2(11.5, 10)]), [a, b], BOARD, objs, 3.0)["ok"]).is_true()
	assert_bool(MeleeMoves.check_consolidation(a, _v([Vector2(10.2, 10)]), [a, b], BOARD, objs, 3.0)["ok"]).is_false()

func test_objective_consolidation_must_end_in_range_of_the_objective() -> void:
	var objs: Array[Vector2] = [Vector2(10, 16)]
	var a := _unit(0, _v([Vector2(10, 13)]))   # edge gap 2.5" -> within 3"
	assert_bool(MeleeMoves.check_consolidation(a, _v([Vector2(10, 14.5)]), [a], BOARD, objs, 3.0)["ok"]).is_true()
	assert_bool(MeleeMoves.check_consolidation(a, _v([Vector2(10, 12)]), [a], BOARD, objs, 3.0)["ok"]).is_false()

# --- fight order (12.04) ---

func _scenario_two_engaged_pairs() -> Array:
	var a1 := _unit(0, _v([Vector2(10, 10)]))
	var a2 := _unit(0, _v([Vector2(10, 20)]))
	var b1 := _unit(1, _v([Vector2(11.5, 10)]))
	var b2 := _unit(1, _v([Vector2(11.5, 20)]))
	return [a1, a2, b1, b2]

func test_without_fights_first_players_alternate_starting_with_the_active_player() -> void:
	var u := _scenario_two_engaged_pairs()
	var s := FightSequencer.new()
	s.begin(u, 0)
	assert_bool(s.in_fights_first_step()).is_false()
	assert_int(s.chooser).is_equal(0)
	assert_bool(s.select(u[0])).is_true()
	assert_int(s.chooser).is_equal(1)
	assert_bool(s.select(u[2])).is_true()
	assert_int(s.chooser).is_equal(0)
	s.select(u[1])
	s.select(u[3])
	assert_bool(s.finished).is_true()

func test_fights_first_units_fight_before_normal_units_even_for_the_other_player() -> void:
	var u := _scenario_two_engaged_pairs()
	u[2].abilities.append("FIGHTS FIRST")  # opponent's unit
	var s := FightSequencer.new()
	s.begin(u, 0)
	assert_bool(s.in_fights_first_step()).is_true()
	assert_int(s.chooser).is_equal(1)  # active player has no Fights First unit
	assert_bool(s.select(u[0])).is_false()  # not a legal pick
	assert_bool(s.select(u[2])).is_true()

func test_a_unit_cannot_be_selected_twice() -> void:
	var u := _scenario_two_engaged_pairs()
	var s := FightSequencer.new()
	s.begin(u, 0)
	s.select(u[0])
	s.select(u[2])
	assert_bool(s.select(u[0])).is_false()

func test_unit_with_nothing_engaged_finishes_immediately() -> void:
	var a := _unit(0, _v([Vector2(5, 5)]))
	var b := _unit(1, _v([Vector2(30, 25)]))
	var s := FightSequencer.new()
	s.begin([a, b], 0)
	assert_bool(s.finished).is_true()

func test_charging_unit_fights_even_though_the_enemy_was_not_engaged_at_start() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(11.5, 10)]))
	a.charged = true
	var s := FightSequencer.new()
	s.begin([a, b], 0)
	assert_bool(s.in_fights_first_step()).is_true()
	assert_bool(s.select(a)).is_true()
	assert_int(s.chooser).is_equal(1)

# --- unit-level combat ---

func test_shooting_counts_only_models_in_range_and_marks_half_range_for_rapid_fire() -> void:
	var gun := {"name": "gun", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "damage": "1", "abilities": ["RAPID FIRE 1"]}
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 11.2)]), {"weapons": [gun]})
	var b := _unit(1, _v([Vector2(20, 10)]), {"toughness": 4, "save": 4, "wounds": 5})
	var d := Dice.new(1, [1, 1, 1, 1] as Array[int])  # 2 models x (1+1 rapid fire) = 4 attacks, all miss
	var out := Combat.shoot(a, b, [a, b], d)
	assert_int(out["reports"][0]["attacks"]).is_equal(4)  # both models within 12" (half of 24)

func test_shooting_out_of_range_makes_no_attacks() -> void:
	var gun := {"name": "gun", "range": 12, "attacks": "1", "skill": 3, "strength": 4, "damage": "1"}
	var a := _unit(0, _v([Vector2(5, 10)]), {"weapons": [gun]})
	var b := _unit(1, _v([Vector2(30, 10)]))
	assert_int(Combat.shoot(a, b, [a, b], Dice.new(1))["reports"].size()).is_equal(0)

func test_hazardous_weapon_triggers_a_hazard_roll_after_shooting() -> void:
	var gun := {"name": "gun", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "damage": "1", "abilities": ["HAZARDOUS"]}
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 11.2)]), {"weapons": [gun], "wounds": 1})
	var b := _unit(1, _v([Vector2(20, 10)]))
	var d := Dice.new(1, [1, 1, 1] as Array[int])  # two misses, then hazard roll of 1 fails
	var out := Combat.shoot(a, b, [a, b], d)
	assert_int(out["hazard_wounds"]).is_equal(1)
	assert_int(a.model_count()).is_equal(1)

func test_melee_uses_extra_attacks_weapon_plus_one_other_weapon() -> void:
	var blade := {"name": "blade", "range": 0, "attacks": "2", "skill": 3, "strength": 4}
	var spare := {"name": "fist", "range": 0, "attacks": "5", "skill": 3, "strength": 4}
	var extra := {"name": "claws", "range": 0, "attacks": "1", "skill": 3, "strength": 4, "abilities": ["EXTRA ATTACKS"]}
	var a := _unit(0, _v([Vector2(10, 10)]), {"weapons": [blade, spare, extra]})
	var b := _unit(1, _v([Vector2(11.5, 10)]), {"wounds": 10})
	var out := Combat.fight(a, b, Dice.new(1, [1, 1, 1] as Array[int]))
	assert_int(out["reports"].size()).is_equal(2)
	assert_int(out["reports"][0]["attacks"] + out["reports"][1]["attacks"]).is_equal(3)

func test_only_models_in_engagement_range_make_melee_attacks() -> void:
	var blade := {"name": "blade", "range": 0, "attacks": "1", "skill": 3, "strength": 4}
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 20)]), {"weapons": [blade]})
	var b := _unit(1, _v([Vector2(11.5, 10)]), {"wounds": 10})
	var out := Combat.fight(a, b, Dice.new(1, [1] as Array[int]))
	assert_int(out["reports"][0]["attacks"]).is_equal(1)

func test_enemy_thirteen_inches_away_is_out_of_declare_range() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(24, 10)]))  # edge gap 13"
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_false()

func test_enemy_just_inside_twelve_inches_is_in_declare_range() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var b := _unit(1, _v([Vector2(22.9, 10)]))  # edge gap 11.9"
	assert_bool(ChargeRules.eligible(a, [a, b])["ok"]).is_true()

func test_charge_targets_are_capped_at_twelve_inches_whatever_the_roll() -> void:
	var a := _unit(0, _v([Vector2(10, 10)]))
	var far := _unit(1, _v([Vector2(24, 10)]))
	assert_int(ChargeRules.possible_targets(a, [a, far], 20).size()).is_equal(0)

func test_pile_in_by_a_model_that_moves_just_over_three_inches_is_illegal() -> void:
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 12.2)]))
	var b := _unit(1, _v([Vector2(11.8, 10)]))
	# model 0 moves 0.8", model 1 moves about 3.08" but is otherwise legal
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(10.8, 10), Vector2(13.0, 11.5)]), [a, b], BOARD)
	assert_bool(r["ok"]).is_false()
	assert_str(r["reason"]).contains("3")

func test_pile_in_of_just_under_three_inches_is_legal() -> void:
	var a := _unit(0, _v([Vector2(10, 10), Vector2(10, 12.2)]))
	var b := _unit(1, _v([Vector2(11.8, 10)]))
	var r := MeleeMoves.check_pile_in(a, _v([Vector2(10.8, 10), Vector2(12.9, 11.5)]), [a, b], BOARD)  # ~3.0"
	assert_bool(r["ok"]).is_true()


func test_ai_skips_a_unit_that_cannot_attack_so_the_fight_phase_still_ends() -> void:
	# A unit with no melee weapon, in contact with an enemy, used to stall the Fight phase forever.
	var armies: Array = [
		{"name": "A", "units": [{"name": "Gunner", "models": 1, "toughness": 4, "save": 4, "wounds": 3, "weapons": [
			{"name": "Rifle", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}]}]},
		{"name": "B", "units": [{"name": "Brute", "models": 1, "toughness": 4, "save": 4, "wounds": 3, "weapons": [
			{"name": "Claws", "range": 0, "attacks": "2", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}]}]}]
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	var b := Battle.new(sc, armies, 5)
	var a: UnitState = b.units[0]
	var o: UnitState = b.units[1]
	o.models[0]["pos"] = a.models[0]["pos"] + Vector2(1.0, 0.0)
	b.begin_turn()
	for i in range(4):
		b.next_phase()
	b.next_phase()  # pile in -> fight
	var guard: int = 0
	while b.fight_chooser() >= 0 and guard < 10:
		guard += 1
		b.ai_fight_step()
	assert_int(b.fight_chooser()).is_equal(-1)
