extends GdUnitTestSuite

func _flow() -> TurnFlow:
	return TurnFlow.new(5)

func test_battle_starts_in_round_one_with_first_player_in_command_phase() -> void:
	var f := _flow()
	assert_int(f.round_no).is_equal(1)
	assert_int(f.active_player).is_equal(0)
	assert_str(f.phase()).is_equal("command")

func test_phases_run_in_order_then_pass_the_turn() -> void:
	var f := _flow()
	var seen: Array[String] = [f.phase()]
	for i in range(4):
		f.advance()
		seen.append(f.phase())
	assert_array(seen).is_equal(["command", "movement", "shooting", "charge", "fight"])
	f.advance()
	assert_int(f.active_player).is_equal(1)
	assert_str(f.phase()).is_equal("command")
	assert_int(f.round_no).is_equal(1)

func test_round_increments_after_both_players_have_played() -> void:
	var f := _flow()
	for i in range(10):
		f.advance()
	assert_int(f.round_no).is_equal(2)
	assert_int(f.active_player).is_equal(0)

func test_game_ends_after_the_last_round() -> void:
	var f := TurnFlow.new(1)
	for i in range(10):
		f.advance()
	assert_bool(f.finished).is_true()

func test_command_phase_gives_both_players_one_cp() -> void:
	var f := _flow()
	f.start_command_phase([], Dice.new(1))
	assert_array(f.command_points).is_equal([1, 1])

func test_command_phase_rolls_battle_shock_for_half_strength_units_of_active_player_only() -> void:
	var f := _flow()
	var weak := UnitState.from_dict({"models": 4, "leadership": 12}, "w", 0, Vector2.ZERO)
	weak.models.remove_at(3)
	weak.models.remove_at(2)  # 2 of 4 left = half strength
	var healthy := UnitState.from_dict({"models": 4, "leadership": 12}, "h", 0, Vector2.ZERO)
	var enemy_weak := UnitState.from_dict({"models": 4, "leadership": 12}, "e", 1, Vector2.ZERO)
	enemy_weak.models.remove_at(3)
	enemy_weak.models.remove_at(2)
	var d := Dice.new(1, [1, 1] as Array[int])  # one roll only: fails vs Ld 12
	f.start_command_phase([weak, healthy, enemy_weak], d)
	assert_bool(weak.battle_shocked).is_true()
	assert_bool(healthy.battle_shocked).is_false()
	assert_bool(enemy_weak.battle_shocked).is_false()
	assert_int(d.scripted_left()).is_equal(0)

func test_shocked_unit_that_passes_its_roll_recovers() -> void:
	var f := _flow()
	var u := UnitState.from_dict({"models": 4, "leadership": 6}, "u", 0, Vector2.ZERO)
	u.battle_shocked = true
	f.start_command_phase([u], Dice.new(1, [3, 3] as Array[int]))
	assert_bool(u.battle_shocked).is_false()
