extends GdUnitTestSuite
## Battle.cmd_undo_move. Armies are the invented placeholders.

const STEP := Vector2(2, 0)


func _battle() -> Battle:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	sc["terrain"] = []
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var b := Battle.new(sc, armies, 1)
	b.ai_sides = [false, true]
	b.begin_turn()
	b.next_phase()
	return b


func _shifted(u: UnitState, d: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"] + d)
	return out


func _where(u: UnitState) -> Array[Vector2]:
	return _shifted(u, Vector2.ZERO)


func test_undo_puts_a_confirmed_move_back() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	var start: Array[Vector2] = _where(u)
	assert_bool(b.cmd_move(u, _shifted(u, STEP), "normal")["ok"]).is_true()

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_array(_where(u)).is_equal(start)
	assert_bool(b.has_moved(u)).is_false()
	assert_float(u.max_model_move).is_equal(0.0)


func test_undo_lets_the_unit_move_again() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	b.cmd_undo_move()

	# Act
	var r: Dictionary = b.cmd_move(u, _shifted(u, STEP * 0.5), "normal")

	# Assert
	assert_bool(r["ok"]).is_true()


func test_undo_clears_the_fall_back_flag() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	var foe: UnitState = b.living(1)[0]
	var off: Vector2 = u.centre() + Vector2(0, -1.5) - foe.centre()
	for m in foe.models:
		m["pos"] += off
	while u.gap_to(foe) > 1.0:
		for m in foe.models:
			m["pos"] += Vector2(0, 0.1)
	var away: Vector2 = Vector2(-1, 1) * 0.2
	var moved: Dictionary = {}
	for i in range(30):
		moved = b.preview_move(u, _shifted(u, away * (i + 1)), "fall_back")
		if moved["ok"]:
			b.cmd_move(u, _shifted(u, away * (i + 1)), "fall_back")
			break
	assert_bool(u.fell_back).is_true()

	# Act
	b.cmd_undo_move()

	# Assert
	assert_bool(u.fell_back).is_false()


func test_undo_is_recorded_as_a_new_event_after_the_move() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	var count: int = b.events.size()

	# Act
	b.cmd_undo_move()

	# Assert
	assert_int(b.events.size()).is_equal(count + 1)
	assert_str(str(b.events[count - 1]["type"])).is_equal("move")
	assert_str(str(b.events[count]["type"])).is_equal("undo_move")


func test_undo_works_only_once() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	b.cmd_undo_move()

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()
	assert_bool(b.can_undo_move()).is_false()


func test_undo_with_no_move_is_refused() -> void:
	# Act
	var r: Dictionary = _battle().cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()


func test_only_the_last_unit_moved_can_be_undone() -> void:
	# Arrange
	var b := _battle()
	var first: UnitState = b.living(0)[0]
	var second: UnitState = b.living(0)[1]
	var first_end: Array[Vector2] = _shifted(first, STEP)
	b.cmd_move(first, first_end, "normal")
	b.cmd_move(second, _shifted(second, STEP), "normal")

	# Act
	b.cmd_undo_move()

	# Assert
	assert_array(_where(first)).is_equal(first_end)
	assert_bool(b.has_moved(first)).is_true()
	assert_bool(b.has_moved(second)).is_false()
	assert_bool(b.can_undo_move()).is_false()


func test_undo_is_refused_after_another_unit_holds() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	b.cmd_hold(b.living(0)[1])

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()
	assert_bool(b.has_moved(u)).is_true()


func test_undo_is_refused_after_another_unit_rolls_to_advance() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	b.cmd_roll_advance(b.living(0)[1])

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()


func test_undo_is_refused_for_an_advance() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_roll_advance(u)
	b.cmd_move(u, _shifted(u, STEP), "advance")

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()
	assert_bool(u.advanced).is_true()


func test_undo_is_refused_when_a_roll_was_made_before_a_normal_move() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_roll_advance(u)
	b.cmd_move(u, _shifted(u, STEP), "normal")

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()


func test_undo_is_refused_after_the_phase_ends() -> void:
	# Arrange
	var b := _battle()
	var u: UnitState = b.living(0)[0]
	b.cmd_move(u, _shifted(u, STEP), "normal")
	b.next_phase()

	# Act
	var r: Dictionary = b.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_false()
	assert_bool(b.has_moved(u)).is_true()
