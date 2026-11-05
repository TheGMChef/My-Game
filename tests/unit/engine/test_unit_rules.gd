extends GdUnitTestSuite

func _unit(owner: int, positions: Array[Vector2], extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"models": positions.size(), "base_mm": 25.4}  # radius 0.5"
	d.merge(extra, true)
	var u := UnitState.from_dict(d, "u%d" % owner, owner, Vector2.ZERO)
	for i in range(positions.size()):
		u.models[i]["pos"] = positions[i]
	return u

# --- coherency (03.03) ---

func test_single_model_unit_is_always_in_coherency() -> void:
	assert_bool(UnitRules.in_coherency([Vector2(5, 5)] as Array[Vector2], 0.5)).is_true()

func test_models_within_two_inches_of_a_neighbour_are_coherent() -> void:
	var pts: Array[Vector2] = [Vector2(0, 0), Vector2(2.5, 0), Vector2(5, 0)]  # edge gaps 1.5"
	assert_bool(UnitRules.in_coherency(pts, 0.5)).is_true()

func test_a_model_more_than_two_inches_from_every_other_breaks_coherency() -> void:
	var pts: Array[Vector2] = [Vector2(0, 0), Vector2(1.2, 0), Vector2(8, 0)]
	assert_bool(UnitRules.in_coherency(pts, 0.5)).is_false()

func test_models_more_than_nine_inches_apart_break_coherency_even_in_a_chain() -> void:
	var pts: Array[Vector2] = []
	for i in range(6):
		pts.append(Vector2(2.5 * i, 0))  # chain of 1.5" gaps, ends 12.5" apart centre to centre
	assert_bool(UnitRules.in_coherency(pts, 0.5)).is_false()

# --- engagement (03.04) ---

func test_enemy_within_two_inches_is_engaged() -> void:
	var a := _unit(0, [Vector2(0, 0)] as Array[Vector2])
	var b := _unit(1, [Vector2(2.5, 0)] as Array[Vector2])  # gap 1.5"
	assert_bool(UnitRules.engaged(a, [a, b])).is_true()

func test_enemy_beyond_two_inches_is_not_engaged() -> void:
	var a := _unit(0, [Vector2(0, 0)] as Array[Vector2])
	var b := _unit(1, [Vector2(3.5, 0)] as Array[Vector2])  # gap 2.5"
	assert_bool(UnitRules.engaged(a, [a, b])).is_false()

func test_friendly_units_never_engage_each_other() -> void:
	var a := _unit(0, [Vector2(0, 0)] as Array[Vector2])
	var b := _unit(0, [Vector2(1.2, 0)] as Array[Vector2])
	assert_bool(UnitRules.engaged(a, [a, b])).is_false()

# --- leadership and battle-shock (01.06, 01.07) ---

func test_leadership_roll_succeeds_on_2d6_equal_to_ld() -> void:
	var u := _unit(0, [Vector2(0, 0)] as Array[Vector2], {"leadership": 7})
	assert_bool(UnitRules.leadership_roll(u, Dice.new(1, [3, 4] as Array[int]))).is_true()
	assert_bool(UnitRules.leadership_roll(u, Dice.new(1, [3, 3] as Array[int]))).is_false()

func test_failed_battle_shock_roll_shocks_the_unit() -> void:
	var u := _unit(0, [Vector2(0, 0)] as Array[Vector2], {"leadership": 8})
	UnitRules.battle_shock_roll(u, Dice.new(1, [1, 2] as Array[int]))
	assert_bool(u.battle_shocked).is_true()

func test_passed_battle_shock_roll_leaves_unit_steady() -> void:
	var u := _unit(0, [Vector2(0, 0)] as Array[Vector2], {"leadership": 6})
	UnitRules.battle_shock_roll(u, Dice.new(1, [3, 3] as Array[int]))
	assert_bool(u.battle_shocked).is_false()

# --- movement (09) ---

const BOARD := Rect2(0, 0, 44, 30)

func test_normal_move_within_m_is_legal() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(15, 10)] as Array[Vector2], "normal", [u], BOARD)
	assert_bool(r["ok"]).is_true()

func test_move_further_than_m_is_illegal() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(17, 10)] as Array[Vector2], "normal", [u], BOARD)
	assert_bool(r["ok"]).is_false()

func test_advance_adds_the_advance_roll_to_m() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(17, 10)] as Array[Vector2], "advance", [u], BOARD, 3)
	assert_bool(r["ok"]).is_true()

func test_move_must_end_unengaged() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var e := _unit(1, [Vector2(16, 10)] as Array[Vector2])
	var r := UnitRules.check_move(u, [Vector2(14, 10)] as Array[Vector2], "normal", [u, e], BOARD)
	assert_bool(r["ok"]).is_false()

func test_engaged_unit_cannot_make_a_normal_move() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var e := _unit(1, [Vector2(11.5, 10)] as Array[Vector2])
	var r := UnitRules.check_move(u, [Vector2(5, 10)] as Array[Vector2], "normal", [u, e], BOARD)
	assert_bool(r["ok"]).is_false()

func test_engaged_unit_can_fall_back_to_an_unengaged_spot() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var e := _unit(1, [Vector2(11.5, 10)] as Array[Vector2])
	var r := UnitRules.check_move(u, [Vector2(5, 10)] as Array[Vector2], "fall_back", [u, e], BOARD)
	assert_bool(r["ok"]).is_true()

func test_unengaged_unit_cannot_fall_back() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(5, 10)] as Array[Vector2], "fall_back", [u], BOARD)
	assert_bool(r["ok"]).is_false()

func test_battle_shocked_unit_cannot_make_an_ordered_retreat() -> void:
	var u := _unit(0, [Vector2(10, 10)] as Array[Vector2], {"move": 6})
	u.battle_shocked = true
	var e := _unit(1, [Vector2(11.5, 10)] as Array[Vector2])
	var r := UnitRules.check_move(u, [Vector2(5, 10)] as Array[Vector2], "fall_back", [u, e], BOARD)
	assert_bool(r["ok"]).is_false()

func test_move_off_the_battlefield_is_illegal() -> void:
	var u := _unit(0, [Vector2(2, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(-2, 10)] as Array[Vector2], "normal", [u], BOARD)
	assert_bool(r["ok"]).is_false()

func test_move_that_breaks_coherency_is_illegal() -> void:
	var u := _unit(0, [Vector2(10, 10), Vector2(11.5, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(10, 10), Vector2(16, 10)] as Array[Vector2], "normal", [u], BOARD)
	assert_bool(r["ok"]).is_false()

func test_new_positions_must_match_model_count() -> void:
	var u := _unit(0, [Vector2(10, 10), Vector2(11.5, 10)] as Array[Vector2], {"move": 6})
	var r := UnitRules.check_move(u, [Vector2(10, 10)] as Array[Vector2], "normal", [u], BOARD)
	assert_bool(r["ok"]).is_false()

func test_coherency_gap_just_over_two_inches_fails() -> void:
	var pts: Array[Vector2] = [Vector2(0, 0), Vector2(3.1, 0)]  # edge gap 2.1"
	assert_bool(UnitRules.in_coherency(pts, 0.5)).is_false()

func test_coherency_gap_of_exactly_two_inches_passes() -> void:
	var pts: Array[Vector2] = [Vector2(0, 0), Vector2(3.0, 0)]  # edge gap 2.0"
	assert_bool(UnitRules.in_coherency(pts, 0.5)).is_true()
