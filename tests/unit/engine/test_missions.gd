extends GdUnitTestSuite

const SCENARIO_PATH := "res://assets/data/scenario_clash_of_patrols.json"

func _scenario() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SCENARIO_PATH))

func _unit(owner: int, at: Vector2, oc: int = 2, shocked: bool = false) -> UnitState:
	var u := UnitState.from_dict({"models": 1, "oc": oc}, "u", owner, at)
	u.battle_shocked = shocked
	return u

func test_scenario_file_loads_and_lists_five_objectives() -> void:
	var s := _scenario()
	assert_int(s["objectives"].size()).is_equal(5)
	assert_int(int(s["battle_rounds"])).is_equal(5)

func test_scenario_is_flagged_as_unconfirmed_placeholder() -> void:
	assert_str(_scenario()["status"]).is_equal("placeholder")

func test_unit_in_range_controls_an_empty_objective() -> void:
	var units: Array = [_unit(0, Vector2(21, 15))]
	assert_int(Missions.controller(Vector2(22, 15), units, 3.0)).is_equal(0)

func test_higher_total_oc_controls_the_objective() -> void:
	var units: Array = [_unit(0, Vector2(21, 15), 2), _unit(1, Vector2(23, 15), 3)]
	assert_int(Missions.controller(Vector2(22, 15), units, 3.0)).is_equal(1)

func test_tied_oc_leaves_the_objective_contested() -> void:
	var units: Array = [_unit(0, Vector2(21, 15), 2), _unit(1, Vector2(23, 15), 2)]
	assert_int(Missions.controller(Vector2(22, 15), units, 3.0)).is_equal(-1)

func test_battle_shocked_units_have_no_objective_control() -> void:
	var units: Array = [_unit(0, Vector2(21, 15), 5, true)]
	assert_int(Missions.controller(Vector2(22, 15), units, 3.0)).is_equal(-1)

func test_unit_out_of_range_does_not_count() -> void:
	var units: Array = [_unit(0, Vector2(30, 15))]
	assert_int(Missions.controller(Vector2(22, 15), units, 3.0)).is_equal(-1)

func test_no_vp_in_round_one() -> void:
	assert_int(Missions.vp_for_turn(_scenario(), 1, 3, false, "end_of_command_phase")).is_equal(0)

func test_five_vp_per_objective_in_round_two_at_command_phase() -> void:
	assert_int(Missions.vp_for_turn(_scenario(), 2, 2, false, "end_of_command_phase")).is_equal(10)

func test_vp_per_turn_is_capped_at_fifteen() -> void:
	assert_int(Missions.vp_for_turn(_scenario(), 3, 5, true, "end_of_command_phase")).is_equal(15)

func test_round_five_second_player_scores_at_end_of_turn_not_command() -> void:
	var s := _scenario()
	assert_int(Missions.vp_for_turn(s, 5, 2, true, "end_of_command_phase")).is_equal(0)
	assert_int(Missions.vp_for_turn(s, 5, 2, true, "end_of_turn")).is_equal(10)
	assert_int(Missions.vp_for_turn(s, 5, 2, false, "end_of_command_phase")).is_equal(10)
