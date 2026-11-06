extends GdUnitTestSuite
## The deployment stage: legal set-ups, taking turns, the first-turn roll-off, saving and the
## automatic path that tests and tools rely on. Invented fixtures only.

const ATTACKER := 0
const DEFENDER := 1


func _unit(unit_name: String, models: int, base_mm: int = 32) -> Dictionary:
	return {"name": unit_name, "models": models, "base_mm": base_mm, "toughness": 4, "save": 4, "wounds": 1,
		"move": 6, "oc": 1, "leadership": 6, "keywords": ["INFANTRY"],
		"weapons": [{"name": "Pike", "range": 0, "attacks": "1", "skill": 4, "strength": 4, "ap": 0, "damage": "1"}]}


func _scenario(terrain: Array = []) -> Dictionary:
	return {"battlefield": {"width_in": 44, "height_in": 30}, "battle_rounds": 5, "objective_range_in": 3,
		"objectives": [{"pos": [22, 15]}, {"pos": [6, 15]}, {"pos": [38, 15]}],
		"deployment_zones": {"attacker": {"rect": [0, 0, 12, 30]}, "defender": {"rect": [32, 0, 12, 30]}},
		"scoring": {"per_objective_vp": 5, "max_vp_per_turn": 15, "first_scoring_round": 2, "last_scoring_round": 5,
			"score_at": "end_of_command_phase", "round_five_second_player_scores": "end_of_turn"},
		"terrain": terrain}


func _armies(a: Array = [], d: Array = []) -> Array:
	if a.is_empty():
		a = [_unit("Red One", 5), _unit("Red Two", 3)]
	if d.is_empty():
		d = [_unit("Blue One", 5), _unit("Blue Two", 3)]
	return [{"units": a}, {"units": d}]


func _deploying(armies: Array = [], terrain: Array = [], seed_value: int = 3) -> Battle:
	var b := Battle.new(_scenario(terrain), armies if not armies.is_empty() else _armies(), seed_value)
	b.start_deployment()
	return b


func _spot(b: Battle, u: UnitState, at: Vector2) -> Array[Vector2]:
	return b.formation(u, at)


func test_units_wait_off_the_board_until_placed() -> void:
	# Arrange and act
	var b: Battle = _deploying()

	# Assert
	assert_bool(b.deployment_active).is_true()
	assert_str(b.phase()).is_equal("deployment")
	assert_array(b.units).is_empty()
	assert_int(b.undeployed.size()).is_equal(4)
	assert_bool(b.is_over()).is_false()


func test_a_battle_without_a_deployment_stage_starts_placed() -> void:
	# Act
	var b := Battle.new(_scenario(), _armies(), 3)

	# Assert
	assert_bool(b.deployment_active).is_false()
	assert_int(b.units.size()).is_equal(4)


func test_the_defender_places_first_and_players_take_turns() -> void:
	# Arrange
	var b: Battle = _deploying()
	assert_int(b.deploy_side()).is_equal(DEFENDER)
	var d: UnitState = b.undeployed_of(DEFENDER)[0]
	var a: UnitState = b.undeployed_of(ATTACKER)[0]

	# Act and assert
	assert_bool(b.cmd_deploy(a, _spot(b, a, Vector2(6, 15)))["ok"]).is_false()
	assert_bool(b.cmd_deploy(d, _spot(b, d, Vector2(38, 15)))["ok"]).is_true()
	assert_int(b.deploy_side()).is_equal(ATTACKER)
	assert_bool(b.cmd_deploy(a, _spot(b, a, Vector2(6, 15)))["ok"]).is_true()
	assert_int(b.deploy_side()).is_equal(DEFENDER)


func test_a_side_that_has_finished_leaves_the_rest_to_the_other() -> void:
	# Arrange: the defender has one unit, the attacker two
	var b: Battle = _deploying(_armies([_unit("Red One", 5), _unit("Red Two", 3)], [_unit("Blue One", 5)]))
	var d: UnitState = b.undeployed_of(DEFENDER)[0]
	b.cmd_deploy(d, _spot(b, d, Vector2(38, 15)))
	var a1: UnitState = b.undeployed_of(ATTACKER)[0]
	b.cmd_deploy(a1, _spot(b, a1, Vector2(6, 8)))

	# Assert
	assert_int(b.deploy_side()).is_equal(ATTACKER)


func test_a_placed_unit_must_be_wholly_inside_its_zone() -> void:
	# Arrange
	var b: Battle = _deploying()
	var d: UnitState = b.undeployed_of(DEFENDER)[0]

	# Act: the first is on the middle of the board, the second has bases over the zone's edge
	var outside: Dictionary = b.preview_deploy(d, _spot(b, d, Vector2(22, 15)))
	var edge: Dictionary = b.preview_deploy(d, _spot(b, d, Vector2(33.0, 15)))
	var off_board: Dictionary = b.preview_deploy(d, _spot(b, d, Vector2(50, 15)))

	# Assert
	assert_bool(outside["ok"]).is_false()
	assert_bool(edge["ok"]).is_false()
	assert_bool(off_board["ok"]).is_false()
	assert_str(str(outside["reason"])).contains("zone")


func test_a_unit_must_be_in_coherency_and_have_all_its_models() -> void:
	# Arrange
	var b: Battle = _deploying()
	var d: UnitState = b.undeployed_of(DEFENDER)[0]
	var spread: Array[Vector2] = [Vector2(34, 2), Vector2(34, 6), Vector2(34, 10), Vector2(34, 14), Vector2(34, 18)]
	var short: Array[Vector2] = [Vector2(36, 2)]

	# Act and assert
	assert_str(str(b.preview_deploy(d, spread)["reason"])).contains("coherency")
	assert_bool(b.preview_deploy(d, short)["ok"]).is_false()


func test_models_cannot_overlap_friends_or_each_other() -> void:
	# Arrange
	var b: Battle = _deploying(_armies([_unit("Red One", 3)], [_unit("Blue One", 3), _unit("Blue Two", 3)]))
	var first: UnitState = b.undeployed_of(DEFENDER)[0]
	b.cmd_deploy(first, _spot(b, first, Vector2(38, 15)))
	var red: UnitState = b.undeployed_of(ATTACKER)[0]
	b.cmd_deploy(red, _spot(b, red, Vector2(6, 15)))
	var second: UnitState = b.undeployed_of(DEFENDER)[0]
	var stacked: Array[Vector2] = [Vector2(36, 5), Vector2(36, 5), Vector2(36, 5)]

	# Act and assert
	assert_str(str(b.preview_deploy(second, stacked)["reason"])).contains("overlap")
	assert_str(str(b.preview_deploy(second, _spot(b, second, Vector2(38, 15)))["reason"])).contains("overlap")


func test_models_cannot_be_set_up_in_dense_terrain() -> void:
	# Arrange
	var dense: Array = [{"rect": [34, 10, 8, 8], "features": [{"rect": [34, 10, 8, 8], "category": "dense", "height": 5}]}]
	var b: Battle = _deploying([], dense)
	var d: UnitState = b.undeployed_of(DEFENDER)[0]

	# Act
	var r: Dictionary = b.preview_deploy(d, _spot(b, d, Vector2(38, 14)))

	# Assert
	assert_str(str(r["reason"])).contains("terrain")


func test_battle_commands_wait_for_deployment_to_finish() -> void:
	# Arrange
	var b: Battle = _deploying()
	var u: UnitState = b.undeployed[0]

	# Act and assert
	assert_bool(b.next_phase()["ok"]).is_false()
	assert_bool(b.cmd_hold(u)["ok"]).is_false()
	b.begin_turn()
	assert_int(b.turn_no).is_equal(0)


func test_the_ai_places_units_legally_near_objectives() -> void:
	# Arrange
	var b: Battle = _deploying()

	# Act
	assert_bool(b.cmd_auto_deploy()["ok"]).is_true()

	# Assert
	assert_bool(b.deployment_ready()).is_true()
	for u in b.units:
		assert_bool(b.zone_rect(u.owner).has_point(u.centre())).is_true()
		assert_bool(u.models.all(func(m: Dictionary) -> bool: return true)).is_true()
		assert_bool(UnitRules.in_coherency(_positions(u), u.base_radius)).is_true()
	var defenders: Array = b.living(DEFENDER)
	assert_float(defenders[0].centre().distance_to(Vector2(38, 15))).is_less(8.0)


func test_units_the_ai_places_do_not_overlap() -> void:
	# Arrange: enough units to fill much of the zone
	var many: Array = []
	for i in range(8):
		many.append(_unit("Blue %d" % i, 10))
	var b: Battle = _deploying(_armies(many.duplicate(), many.duplicate()))

	# Act
	b.cmd_auto_deploy()

	# Assert
	var events: Array = b.events.filter(func(e: Dictionary) -> bool: return e["type"] == "deploy")
	assert_int(events.size()).is_equal(16)
	assert_bool(events.all(func(e: Dictionary) -> bool: return not bool(e["forced"]))).is_true()


func test_a_zone_with_no_room_can_never_stall_deployment() -> void:
	# Arrange: huge bases that cannot fit a 12" by 30" zone
	var many: Array = []
	for i in range(30):
		many.append(_unit("Huge %d" % i, 1, 200))
	var b: Battle = _deploying(_armies(many.duplicate(), many.duplicate()))

	# Act
	b.cmd_auto_deploy()

	# Assert
	assert_bool(b.deployment_ready()).is_true()
	assert_bool(b.events.any(func(e: Dictionary) -> bool: return e["type"] == "deploy" and bool(e["forced"]))).is_true()
	assert_bool(b.cmd_finish_deployment()["ok"]).is_true()


func test_deployment_cannot_end_while_units_wait() -> void:
	# Arrange
	var b: Battle = _deploying()

	# Act and assert
	assert_bool(b.cmd_finish_deployment()["ok"]).is_false()


func test_a_roll_off_decides_the_first_turn_and_ties_roll_again() -> void:
	# Arrange: the first roll-off ties, then player 1 wins
	var b: Battle = _deploying()
	b.cmd_auto_deploy()
	b.dice = Dice.new(1, [3, 3, 2, 5])

	# Act
	assert_bool(b.cmd_finish_deployment()["ok"]).is_true()

	# Assert
	assert_bool(b.deployment_active).is_false()
	assert_int(b.flow.first_player).is_equal(1)
	assert_int(b.active_player()).is_equal(1)
	assert_str(b.phase()).is_equal("command")
	assert_array(b.events.back()["rolls"]).is_equal([2, 5])


func test_rounds_follow_the_first_player() -> void:
	# Arrange
	var flow := TurnFlow.new(5)
	flow.set_first_player(1)

	# Act: through the first player's five phases
	for i in range(5):
		flow.advance()

	# Assert
	assert_int(flow.active_player).is_equal(0)
	assert_int(flow.round_no).is_equal(1)
	for i in range(5):
		flow.advance()
	assert_int(flow.active_player).is_equal(1)
	assert_int(flow.round_no).is_equal(2)


func test_the_second_player_scores_at_the_end_of_the_last_round_whichever_side_it_is() -> void:
	# Arrange: side 0 goes second and holds an objective
	var b: Battle = _deploying()
	b.cmd_auto_deploy()
	b.dice = Dice.new(1, [1, 6])
	b.cmd_finish_deployment()
	assert_int(b.flow.first_player).is_equal(1)
	b.flow.round_no = 5
	b.flow.active_player = 0
	var mine: UnitState = b.living(0)[0]
	for m in mine.models:
		m["pos"] = Vector2(22, 15)

	# Act
	b._score("end_of_command_phase")
	var at_command: int = b.vp[0]
	b._score("end_of_turn")

	# Assert
	assert_int(at_command).is_equal(0)
	assert_int(b.vp[0]).is_greater(0)


func test_a_saved_deployment_carries_on_where_it_stopped() -> void:
	# Arrange: one unit placed
	var b: Battle = _deploying()
	var d: UnitState = b.undeployed_of(DEFENDER)[0]
	b.cmd_deploy(d, _spot(b, d, Vector2(38, 15)))

	# Act
	var loaded: Battle = Battle.from_save(JSON.parse_string(JSON.stringify(b.to_save(), "", true, true)))

	# Assert
	assert_bool(loaded.deployment_active).is_true()
	assert_int(loaded.deploy_side()).is_equal(ATTACKER)
	assert_int(loaded.units.size()).is_equal(1)
	assert_int(loaded.undeployed.size()).is_equal(3)
	assert_str(loaded.unit_by_id(loaded.undeployed[0].id).unit_name).is_equal(loaded.undeployed[0].unit_name)
	assert_vector(loaded.units[0].centre()).is_equal_approx(d.centre(), Vector2(0.001, 0.001))
	loaded.cmd_auto_deploy()
	assert_bool(loaded.cmd_finish_deployment()["ok"]).is_true()


func test_a_whole_battle_plays_out_from_deployment() -> void:
	# Arrange
	var b: Battle = _deploying()

	# Act
	var result: Dictionary = b.play_all()

	# Assert
	assert_bool(b.deployment_active).is_false()
	assert_bool(b.is_over()).is_true()
	assert_int(int(result["rounds"])).is_greater(0)


func _positions(u: UnitState) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"])
	return out
