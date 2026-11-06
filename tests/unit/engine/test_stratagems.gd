extends GdUnitTestSuite
## Each core stratagem's effect and restrictions, CP accounting, reaction windows and saves.
## Invented fixtures only.

const ME := 0
const FOE := 1
const SIXES: Array[int] = [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]


func _weapons() -> Array:
	return [{"name": "Rifle", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"},
		{"name": "Pike", "range": 0, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}]


func _unit(unit_name: String, models: int = 5, keywords: Array = ["INFANTRY"], wounds: int = 1, toughness: int = 4) -> Dictionary:
	return {"name": unit_name, "models": models, "base_mm": 32, "toughness": toughness, "save": 4, "wounds": wounds,
		"move": 6, "oc": 1, "leadership": 7, "keywords": keywords, "weapons": _weapons()}


func _scenario() -> Dictionary:
	return {"battlefield": {"width_in": 44, "height_in": 30}, "battle_rounds": 5, "objective_range_in": 3,
		"objectives": [{"pos": [22, 15]}],
		"deployment_zones": {"attacker": {"rect": [0, 0, 12, 30]}, "defender": {"rect": [32, 0, 12, 30]}},
		"scoring": {"per_objective_vp": 5, "max_vp_per_turn": 15, "first_scoring_round": 2, "last_scoring_round": 5,
			"score_at": "end_of_command_phase", "round_five_second_player_scores": "end_of_turn"}}


## Two human-style sides, one unit each unless more are given, with 5 CP each.
func _battle(mine: Array = [], theirs: Array = [], seed_value: int = 5) -> Battle:
	var armies: Array = [{"units": mine if not mine.is_empty() else [_unit("Red")]},
		{"units": theirs if not theirs.is_empty() else [_unit("Blue")]}]
	var b := Battle.new(_scenario(), armies, seed_value)
	b.ai_sides = [false, false]
	b.flow.command_points = [5, 5]
	return b


func _put(u: UnitState, at: Vector2) -> void:
	var offset: Vector2 = at - u.models[0]["pos"]
	for m in u.models:
		m["pos"] = m["pos"] + offset


func _mine(b: Battle, i: int = 0) -> UnitState:
	return b.living(ME)[i]


func _foe(b: Battle, i: int = 0) -> UnitState:
	return b.living(FOE)[i]


## Make [param side] the active player, at the start of [param phase_name].
func _at_phase(b: Battle, side: int, phase_name: String) -> void:
	b.flow.active_player = side
	b.flow._phase_index = TurnFlow.PHASES.find(phase_name)
	b._phase_changed()
	b._windows_done.clear()


func _ids(options: Array[Dictionary]) -> Array:
	return options.map(func(o: Dictionary) -> String: return str(o["id"]))


## At the end of side 1's Movement phase, with [param side] 0 able to react.
func _open_end_of_movement(b: Battle) -> void:
	_at_phase(b, FOE, "movement")
	b.prompt_sides[ME] = true
	b.next_phase()


# ---------------------------------------------------------------- general limits

func test_using_a_stratagem_spends_its_cost_and_logs_it() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["INFANTRY", "GRENADES"])])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "explosives", {"unit": _mine(b).id})

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_int(b.command_points(ME)).is_equal(4)
	assert_int(b.command_points(FOE)).is_equal(5)
	var used: Array = b.events.filter(func(e: Dictionary) -> bool: return e["type"] == "stratagem")
	assert_int(used.size()).is_equal(1)
	assert_str(str(used[0]["id"])).is_equal("explosives")
	assert_int(int(used[0]["side"])).is_equal(ME)


func test_a_stratagem_you_cannot_afford_is_refused_and_costs_nothing() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["INFANTRY", "GRENADES"])])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.flow.command_points[ME] = 0

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "explosives")

	# Assert
	assert_bool(r["ok"]).is_false()
	assert_str(str(r["reason"])).is_equal(UIText.t("strat.reason.no_cp"))
	assert_int(b.command_points(ME)).is_equal(0)


func test_the_same_stratagem_cannot_be_used_twice_in_a_phase() -> void:
	# Arrange: two units able to use it
	var kw: Array = ["INFANTRY", "GRENADES"]
	var b: Battle = _battle([_unit("Red", 5, kw), _unit("Pink", 5, kw)])
	_at_phase(b, ME, "shooting")
	_put(_mine(b, 0), Vector2(10, 5))
	_put(_mine(b, 1), Vector2(10, 15))
	_put(_foe(b), Vector2(16, 10))
	b.cmd_stratagem(ME, "explosives", {"unit": _mine(b, 0).id})

	# Act
	var second: Dictionary = b.cmd_stratagem(ME, "explosives", {"unit": _mine(b, 1).id})

	# Assert
	assert_bool(second["ok"]).is_false()
	assert_str(str(second["reason"])).is_equal(UIText.t("strat.reason.used_phase"))


func test_the_limit_on_a_stratagem_ends_with_the_phase() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["INFANTRY", "GRENADES"])])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.cmd_stratagem(ME, "explosives")
	assert_bool(b.used_this_phase(ME, "explosives")).is_true()

	# Act
	b.next_phase()

	# Assert
	assert_bool(b.used_this_phase(ME, "explosives")).is_false()


func test_one_unit_cannot_be_the_target_of_two_stratagems_in_a_phase() -> void:
	# Arrange: a tank re-rolls its charge, then makes the charge move
	var b: Battle = _battle([_unit("Tank", 1, ["VEHICLE"], 10, 5)], [_unit("Blue", 5)])
	_at_phase(b, ME, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(16, 15))
	b.dice = Dice.new(1, [1, 1, 6, 6])
	b.cmd_declare_charge(_mine(b))
	assert_bool(b.cmd_stratagem(ME, "command_reroll")["ok"]).is_true()
	var targets: Array[UnitState] = [_foe(b)]
	b.cmd_charge_move(_mine(b), ChargeRules.auto_positions(_mine(b), targets, 12, b.units, b.board), targets)

	# Act
	var crush: Dictionary = b.cmd_stratagem(ME, "crushing_impact")

	# Assert
	assert_bool(crush["ok"]).is_false()
	assert_int(b.command_points(ME)).is_equal(4)


func test_a_heroic_unit_cannot_also_use_a_second_stratagem_in_that_phase() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, FOE, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	_foe(b).charged = true
	(b._targeted_phase[ME] as Array).append(_mine(b).id)
	b.prompt_sides[ME] = true

	# Act
	b.next_phase()

	# Assert: nothing to offer, so the battle moves on
	assert_dict(b.pending).is_empty()
	assert_str(b.phase()).is_equal("fight")


func test_a_battle_shocked_unit_cannot_be_targeted() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_mine(b).battle_shocked = true
	b.prompt_sides[ME] = true

	# Act
	_open_end_of_movement(b)

	# Assert
	assert_dict(b.pending).is_empty()
	assert_str(b.flow.phase()).is_equal("shooting")


func test_universal_updates_on_free_and_repeat_stratagems() -> void:
	# Assert
	assert_int(Stratagems.discounted_cost(1, false)).is_equal(0)
	assert_int(Stratagems.discounted_cost(2, false)).is_equal(1)
	assert_int(Stratagems.discounted_cost(2, true)).is_equal(0)
	assert_bool(Stratagems.may_reuse("fire_overwatch", ["fire_overwatch"])).is_true()
	assert_bool(Stratagems.may_reuse("fire_overwatch", [])).is_false()


func test_rapid_ingress_is_greyed_with_a_reason() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, FOE, "movement")

	# Act
	var row: Dictionary = _row(b, "rapid_ingress")

	# Assert
	assert_array(row["options"]).is_empty()
	assert_str(str(row["reason"])).is_equal("strat.reason.no_reserves")


func test_a_stratagem_the_scenario_bans_is_greyed_with_a_reason() -> void:
	# Arrange
	var sc: Dictionary = _scenario()
	sc["banned_stratagems"] = ["explosives"]
	var b := Battle.new(sc, [{"units": [_unit("Red", 5, ["GRENADES"])]}, {"units": [_unit("Blue")]}], 5)
	b.ai_sides = [false, false]
	b.flow.command_points = [5, 5]
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))

	# Act
	var row: Dictionary = _row(b, "explosives")

	# Assert
	assert_str(str(row["reason"])).is_equal("strat.reason.banned")
	assert_bool(b.cmd_stratagem(ME, "explosives")["ok"]).is_false()


func test_every_stratagem_has_text_for_the_tab() -> void:
	# Assert
	for d in Stratagems.DEFS:
		for part in ["name", "effect", "when"]:
			assert_bool(UIText.has_key("strat.%s.%s" % [d["id"], part])).is_true()


func _row(b: Battle, id: String, side: int = ME) -> Dictionary:
	for row in b.stratagem_overview(side):
		if row["id"] == id:
			return row
	return {}


# ---------------------------------------------------------------- Command Re-roll

func test_command_reroll_changes_an_advance_roll() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, ME, "movement")
	b.dice = Dice.new(1, [1, 5])
	b.cmd_roll_advance(_mine(b))

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "command_reroll")

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_int(b.advance_roll_for(_mine(b))).is_equal(5)


func test_an_advance_roll_is_only_rerolled_once() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, ME, "movement")
	b.cmd_roll_advance(_mine(b))
	b.cmd_stratagem(ME, "command_reroll")

	# Act and assert
	assert_bool(b.cmd_stratagem(ME, "command_reroll")["ok"]).is_false()


func test_command_reroll_rerolls_a_charge_in_full() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, ME, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.dice = Dice.new(1, [1, 1, 6, 5])
	var declared: Dictionary = b.cmd_declare_charge(_mine(b))
	assert_int(int(declared["roll"])).is_equal(2)
	assert_bool(b.charge_finished(_mine(b))).is_true()

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "command_reroll")

	# Assert: the failed charge is live again, with the new roll
	assert_bool(r["ok"]).is_true()
	assert_int(int(b.charge_state(_mine(b))["roll"])).is_equal(11)
	assert_bool(b.charge_finished(_mine(b))).is_false()
	assert_array(b.charge_state(_mine(b))["targets"]).contains([_foe(b)])


func test_a_charge_that_has_moved_cannot_be_rerolled() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, ME, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.dice = Dice.new(1, [6, 6])
	b.cmd_declare_charge(_mine(b))
	var moved: Array[Vector2] = ChargeRules.auto_positions(_mine(b), [_foe(b)] as Array[UnitState], 12, b.units, b.board)
	b.cmd_charge_move(_mine(b), moved, [_foe(b)] as Array[UnitState])

	# Act and assert
	assert_bool(b.cmd_stratagem(ME, "command_reroll")["ok"]).is_false()


func _half_strength_turn(b: Battle, first_dice: Array[int]) -> void:
	var u: UnitState = _mine(b)
	u.models.resize(2)
	u.starting_strength = 5
	b.prompt_sides[ME] = true
	b.dice = Dice.new(1, first_dice)
	b.begin_turn()


func test_a_failed_battle_shock_roll_can_reroll_its_lowest_die() -> void:
	# Arrange: Ld 7, rolls 1 and 2 fail, the 1 becomes a 6 for a pass
	var b: Battle = _battle()
	_half_strength_turn(b, [1, 2, 6])
	b.cmd_pass(ME)    # no Insane Bravery
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_SHOCK_AFTER)

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "command_reroll")

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_bool(_mine(b).battle_shocked).is_false()
	assert_dict(b.pending).is_empty()


func test_passing_on_a_failed_roll_leaves_the_unit_shocked() -> void:
	# Arrange
	var b: Battle = _battle()
	_half_strength_turn(b, [1, 2, 6])
	b.cmd_pass(ME)

	# Act
	b.cmd_pass(ME)

	# Assert
	assert_bool(_mine(b).battle_shocked).is_true()
	assert_str(b.events.back()["type"]).is_equal("turn_start")
	assert_array(b.events.back()["shocked"]).contains([_mine(b).id])


func test_a_passed_battle_shock_roll_asks_nothing_more() -> void:
	# Arrange
	var b: Battle = _battle()
	_half_strength_turn(b, [6, 6])

	# Act
	b.cmd_pass(ME)

	# Assert
	assert_dict(b.pending).is_empty()
	assert_bool(_mine(b).battle_shocked).is_false()


# ---------------------------------------------------------------- Insane Bravery

func test_insane_bravery_passes_the_roll_without_dice() -> void:
	# Arrange: dice that would fail
	var b: Battle = _battle()
	_half_strength_turn(b, [1, 1])
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_SHOCK_BEFORE)

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "insane_bravery")

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_bool(_mine(b).battle_shocked).is_false()
	assert_dict(b.pending).is_empty()


func test_insane_bravery_is_once_per_battle() -> void:
	# Arrange
	var b: Battle = _battle()
	(b._used_battle[ME] as Array).append("insane_bravery")

	# Act
	_half_strength_turn(b, [1, 1])

	# Assert: straight to the roll, so the next question is the re-roll
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_SHOCK_AFTER)
	assert_str(str(_row_now(b, "insane_bravery")["reason"])).is_equal("strat.reason.used_battle")


func _row_now(b: Battle, id: String) -> Dictionary:
	return _row(b, id)


func test_a_unit_already_shocked_gets_no_insane_bravery() -> void:
	# Arrange
	var b: Battle = _battle()
	_mine(b).battle_shocked = true
	b.prompt_sides[ME] = true
	b.dice = Dice.new(1, [1, 1])

	# Act
	b.begin_turn()

	# Assert: no question, and it stays shocked
	assert_dict(b.pending).is_empty()
	assert_bool(_mine(b).battle_shocked).is_true()


func test_a_shocked_unit_that_passes_recovers() -> void:
	# Arrange
	var b: Battle = _battle()
	_mine(b).battle_shocked = true
	b.dice = Dice.new(1, [6, 6])

	# Act
	b.begin_turn()

	# Assert
	assert_bool(_mine(b).battle_shocked).is_false()


# ---------------------------------------------------------------- Epic Challenge

func test_epic_challenge_needs_a_character_and_gives_precision() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Hero", 1, ["INFANTRY", "CHARACTER"])], [_unit("Blue", 2)])
	b.flow.active_player = ME
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(11.5, 15))
	_mine(b).charged = true
	b.flow._phase_index = 3
	b.next_phase()
	b.next_phase()

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "epic_challenge")

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_bool(b.has_epic_challenge(_mine(b))).is_true()
	assert_bool(bool(b.fight_preview(_mine(b), _foe(b))[0]["ctx"]["precision"])).is_true()


func test_epic_challenge_is_not_offered_without_a_character() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 2)], [_unit("Blue", 2)])
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(11.5, 15))
	_mine(b).charged = true
	_at_phase(b, ME, "charge")
	b.next_phase()
	b.next_phase()

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "epic_challenge")

	# Assert
	assert_bool(r["ok"]).is_false()


func test_precision_puts_the_wound_on_the_character() -> void:
	# Arrange: a mixed fixture, with the character model last
	var target: UnitState = UnitState.from_dict(_unit("Blue", 3, ["INFANTRY"]), "t", FOE, Vector2(10, 10))
	target.models[2]["character"] = true
	var w: Weapon = Weapon.from_dict({"name": "Blade", "range": 0, "attacks": "1", "skill": 2, "strength": 8, "ap": -5, "damage": "1"})

	# Act: hit, wound, failed save
	AttackResolver.resolve(w, target, Dice.new(1, [6, 6, 2]), {"precision": true})

	# Assert: only the character is gone
	assert_int(target.model_count()).is_equal(2)
	assert_bool(target.models.any(func(m: Dictionary) -> bool: return bool(m["character"]))).is_false()


# ---------------------------------------------------------------- Explosives

func test_explosives_inflict_a_mortal_wound_for_each_4_plus() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["GRENADES"])], [_unit("Blue", 5)])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.dice = Dice.new(1, [6, 5, 4, 3, 2, 1])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "explosives")

	# Assert
	assert_int(int(r["result"]["hits"])).is_equal(3)
	assert_int(_foe(b).model_count()).is_equal(2)


func test_explosives_need_the_keyword_range_and_an_unengaged_unit_that_did_not_advance() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["GRENADES"]), _unit("Pink")], [_unit("Blue", 5)])
	_at_phase(b, ME, "shooting")
	_put(_mine(b, 0), Vector2(1, 15))
	_put(_mine(b, 1), Vector2(10, 5))
	_put(_foe(b), Vector2(19, 15))

	# Act and assert: too far for Red, and Pink has no grenades
	assert_array(b.stratagem_options(ME)).is_empty()
	_put(_mine(b, 0), Vector2(10, 15))
	assert_int(b.stratagem_options(ME).size()).is_equal(1)
	_mine(b, 0).advanced = true
	assert_array(b.stratagem_options(ME)).is_empty()


func test_explosives_leave_the_unit_free_to_shoot() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["GRENADES"])], [_unit("Blue", 5)])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.cmd_stratagem(ME, "explosives")

	# Act
	var shot: Dictionary = b.cmd_shoot(_mine(b), _foe(b))

	# Assert
	assert_bool(shot["ok"]).is_true()


# ---------------------------------------------------------------- Crushing Impact

func _charged_in(b: Battle) -> void:
	_at_phase(b, ME, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.dice = Dice.new(1, [6, 6])
	b.cmd_declare_charge(_mine(b))
	var targets: Array[UnitState] = [_foe(b)]
	b.cmd_charge_move(_mine(b), ChargeRules.auto_positions(_mine(b), targets, 12, b.units, b.board), targets)


func test_crushing_impact_hurts_both_sides_by_the_dice() -> void:
	# Arrange: T5 rolls five dice
	var b: Battle = _battle([_unit("Tank", 1, ["VEHICLE"], 10, 5)], [_unit("Blue", 5)])
	_charged_in(b)
	b.dice = Dice.new(1, [1, 1, 5, 6, 3])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "crushing_impact")

	# Assert
	assert_int(int(r["result"]["dealt"])).is_equal(2)
	assert_int(int(r["result"]["taken"])).is_equal(2)
	assert_int(_mine(b).total_wounds_left()).is_equal(8)
	assert_int(_foe(b).model_count()).is_equal(3)


func test_crushing_impact_is_capped_at_six_mortal_wounds() -> void:
	# Arrange: T8 rolls eight dice, all 6s
	var b: Battle = _battle([_unit("Tank", 1, ["MONSTER"], 10, 8)], [_unit("Blue", 10)])
	_charged_in(b)
	b.dice = Dice.new(1, SIXES)

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "crushing_impact")

	# Assert
	assert_int(int(r["result"]["dealt"])).is_equal(6)


func test_crushing_impact_needs_a_monster_or_vehicle_that_just_charged() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5)], [_unit("Blue", 5)])
	_charged_in(b)

	# Act and assert
	assert_bool(b.cmd_stratagem(ME, "crushing_impact")["ok"]).is_false()


# ---------------------------------------------------------------- Fire Overwatch and snap shooting

func test_fire_overwatch_is_offered_at_the_end_of_the_opponents_movement() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))

	# Act
	_open_end_of_movement(b)

	# Assert
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_END_MOVEMENT)
	assert_array(_ids(b.stratagem_options(ME))).contains(["fire_overwatch"])
	assert_str(b.flow.phase()).is_equal("movement")


func test_snap_shooting_only_hits_on_an_unmodified_6() -> void:
	# Arrange: five attacks, one 6 and four 5s
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)
	b.dice = Dice.new(1, [6, 5, 5, 5, 5, 6, 1])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "fire_overwatch")

	# Assert
	var report: Dictionary = r["result"]["reports"][0]
	assert_int(int(report["attacks"])).is_equal(5)
	assert_int(int(report["hits"])).is_equal(1)
	assert_int(int(report["critical_hits"])).is_equal(1)


func test_snap_shooting_rolls_for_torrent_weapons_too() -> void:
	# Arrange
	var target: UnitState = UnitState.from_dict(_unit("Blue", 5), "t", FOE, Vector2(10, 10))
	var w: Weapon = Weapon.from_dict({"name": "Flame", "range": 12, "attacks": "3", "skill": 0, "strength": 4, "ap": 0, "damage": "1", "keywords": ["TORRENT"]})
	var ctx: Dictionary = {"snap": true, "indirect_min": 6}

	# Act: 1 attack made of three dice, none of them a 6
	var report: Dictionary = AttackResolver.resolve(w, target, Dice.new(1, [5, 5, 5]), ctx)

	# Assert
	assert_int(int(report["hits"])).is_equal(0)


func test_the_odds_agree_snap_shooting_hits_one_time_in_six() -> void:
	# Arrange
	var target: UnitState = UnitState.from_dict(_unit("Blue", 5), "t", FOE, Vector2(10, 10))
	var w: Weapon = Weapon.from_dict({"name": "Rifle", "range": 24, "attacks": "1", "skill": 2, "strength": 4, "ap": 0, "damage": "1"})

	# Act
	var odds: Dictionary = AttackOdds.compute(w, target, {"snap": true, "indirect_min": 6})

	# Assert
	assert_float(float(odds["p_hit"])).is_equal_approx(1.0 / 6.0, 0.0001)


func test_snap_shooting_reaches_only_24_inches() -> void:
	# Arrange: a long gun, with the enemy at 30"
	var long_arm: Dictionary = _unit("Red")
	long_arm["weapons"] = [{"name": "Long", "range": 60, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}]
	var b: Battle = _battle([long_arm])
	_put(_mine(b), Vector2(2, 15))
	_put(_foe(b), Vector2(36, 15))

	# Act
	_open_end_of_movement(b)

	# Assert
	assert_dict(b.pending).is_empty()


func test_titanic_and_engaged_units_cannot_fire_overwatch() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Giant", 1, ["TITANIC"], 20)], [_unit("Blue"), _unit("Other")])
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b, 0), Vector2(20, 5))
	_put(_foe(b, 1), Vector2(20, 25))
	_open_end_of_movement(b)
	assert_dict(b.pending).is_empty()

	# Arrange again: an infantry unit, engaged
	var c: Battle = _battle()
	_put(_mine(c), Vector2(10, 15))
	_put(_foe(c), Vector2(11.5, 15))
	_open_end_of_movement(c)

	# Assert
	assert_dict(c.pending).is_empty()


func test_overwatch_does_not_use_up_the_units_own_shooting() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)
	b.cmd_stratagem(ME, "fire_overwatch")

	# Assert
	assert_bool(b.has_shot(_mine(b))).is_false()


# ---------------------------------------------------------------- Smokescreen

func test_smokescreen_gives_cover_until_the_phase_ends() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["SMOKE"])])
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_at_phase(b, FOE, "movement")
	b._windows_done.append(Stratagems.W_END_MOVEMENT)
	b.prompt_sides[ME] = true
	b.next_phase()
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_START_SHOOTING)

	# Act
	assert_bool(b.cmd_stratagem(ME, "smokescreen")["ok"]).is_true()

	# Assert
	assert_str(b.flow.phase()).is_equal("shooting")
	assert_bool(bool(b.shoot_preview(_foe(b), _mine(b))[0]["ctx"]["cover"])).is_true()
	b.next_phase()
	assert_bool(b.has_smokescreen(_mine(b))).is_false()


func test_smokescreen_needs_the_keyword() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, FOE, "movement")
	b.prompt_sides[ME] = true

	# Act
	b.next_phase()

	# Assert
	assert_str(b.flow.phase()).is_equal("shooting")
	assert_dict(b.pending).is_empty()


# ---------------------------------------------------------------- Heroic Intervention

## The enemy has charged a friend, with Red nearby and able to step in.
func _after_enemy_charge(b: Battle) -> void:
	_at_phase(b, FOE, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	_foe(b).charged = true
	b.prompt_sides[ME] = true
	b.next_phase()


func test_heroic_intervention_charges_at_the_end_of_the_enemy_charge_phase() -> void:
	# Arrange
	var b: Battle = _battle()
	_after_enemy_charge(b)
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_END_CHARGE)
	b.dice = Dice.new(1, [6, 6])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "heroic_intervention", {"mode": Stratagems.LEAP_TO_DEFEND})

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_bool(bool(r["result"]["charged"])).is_true()
	assert_bool(_mine(b).charged).is_true()
	assert_float(_mine(b).gap_to(_foe(b))).is_less_equal(UnitRules.ENGAGEMENT_RANGE)
	assert_int(b.command_points(ME)).is_equal(4)
	assert_str(b.flow.phase()).is_equal("fight")


func test_a_heroic_unit_fights_first_and_then_loses_it_at_the_end_of_the_turn() -> void:
	# Arrange: it charged in
	var b: Battle = _battle()
	_after_enemy_charge(b)
	b.dice = Dice.new(1, [6, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	b.cmd_stratagem(ME, "heroic_intervention", {"mode": Stratagems.LEAP_TO_DEFEND})
	var me: UnitState = _mine(b)

	# Act and assert: the sequencer offers it in the Fights First step
	assert_bool(me.is_fights_first()).is_true()
	assert_bool(b.can_pile_in(me)).is_true()
	b.next_phase()
	assert_bool(b.fighting_first()).is_true()
	assert_array(b.fight_candidates(ME)).contains([me])
	b._end_turn()
	assert_bool(me.charged).is_false()
	assert_bool(me.is_fights_first()).is_false()


func test_a_failed_heroic_roll_stays_put() -> void:
	# Arrange
	var b: Battle = _battle()
	_after_enemy_charge(b)
	var before: Vector2 = _mine(b).centre()
	b.dice = Dice.new(1, [1, 1])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "heroic_intervention", {"mode": Stratagems.LEAP_TO_DEFEND})

	# Assert
	assert_bool(bool(r["result"]["charged"])).is_false()
	assert_vector(_mine(b).centre()).is_equal(before)
	assert_bool(_mine(b).charged).is_false()


func test_leap_to_defend_needs_an_enemy_that_charged() -> void:
	# Arrange: an enemy 7" away that did not charge
	var b: Battle = _battle()
	_at_phase(b, FOE, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(24, 15))
	b.prompt_sides[ME] = true

	# Act
	b.next_phase()

	# Assert
	assert_dict(b.pending).is_empty()


func test_into_the_fray_costs_two_and_caps_the_roll_at_six() -> void:
	# Arrange: an enemy 4" away that did not charge
	var b: Battle = _battle()
	_at_phase(b, FOE, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.prompt_sides[ME] = true
	b.next_phase()
	var fray: Array[Dictionary] = b.stratagem_options(ME).filter(func(o: Dictionary) -> bool: return o["mode"] == Stratagems.INTO_THE_FRAY)
	assert_int(fray.size()).is_equal(1)
	assert_int(int(fray[0]["cost"])).is_equal(2)
	b.dice = Dice.new(1, [6, 6])

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "heroic_intervention", {"mode": Stratagems.INTO_THE_FRAY})

	# Assert
	assert_int(int(r["result"]["roll"])).is_equal(6)
	assert_int(b.command_points(ME)).is_equal(3)


func test_into_the_fray_needs_two_cp() -> void:
	# Arrange
	var b: Battle = _battle()
	_at_phase(b, FOE, "charge")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.prompt_sides[ME] = true
	b.flow.command_points[ME] = 1

	# Act
	b.next_phase()

	# Assert: the enemy did not charge, so only the 2CP mode could apply, and that is too dear
	assert_dict(b.pending).is_empty()


func test_a_plain_vehicle_cannot_intervene_but_a_walker_can() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Tank", 1, ["VEHICLE"], 10)])
	_after_enemy_charge(b)
	assert_dict(b.pending).is_empty()
	var c: Battle = _battle([_unit("Strider", 1, ["VEHICLE", "WALKER"], 10)])

	# Act
	_after_enemy_charge(c)

	# Assert
	assert_str(str(c.pending["window"])).is_equal(Stratagems.W_END_CHARGE)


# ---------------------------------------------------------------- Counteroffensive

## Two combats. It is side 1's turn, in the fight step, and it is about to pick.
func _two_combats() -> Battle:
	var b: Battle = _battle([_unit("Red"), _unit("Pink")], [_unit("Blue"), _unit("Grey")])
	_put(_mine(b, 0), Vector2(10, 5))
	_put(_foe(b, 0), Vector2(11.5, 5))
	_put(_mine(b, 1), Vector2(10, 20))
	_put(_foe(b, 1), Vector2(11.5, 20))
	_at_phase(b, FOE, "charge")
	b._windows_done.append(Stratagems.W_END_CHARGE)
	b.next_phase()
	b.next_phase()
	b.prompt_sides[ME] = true
	b.dice = Dice.new(1, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	return b


func test_counteroffensive_is_offered_after_an_enemy_unit_fights() -> void:
	# Arrange
	var b: Battle = _two_combats()

	# Act
	b.cmd_fight(_foe(b, 0), _mine(b, 0))

	# Assert
	assert_str(str(b.pending["window"])).is_equal(Stratagems.W_AFTER_FIGHT)
	assert_array(_ids(b.stratagem_options(ME))).contains(["counteroffensive"])


func test_counteroffensive_makes_the_unit_fight_next() -> void:
	# Arrange
	var b: Battle = _two_combats()
	b.cmd_fight(_foe(b, 0), _mine(b, 0))
	var pink: UnitState = _mine(b, 1)

	# Act
	var r: Dictionary = b.cmd_stratagem(ME, "counteroffensive", {"unit": pink.id})

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_int(b.command_points(ME)).is_equal(3)
	assert_int(b.fight_chooser()).is_equal(ME)
	assert_array(b.fight_options()).contains_exactly([pink])
	assert_bool(pink.is_fights_first()).is_true()
	assert_bool(b.cmd_fight(_mine(b, 0), _foe(b, 0))["ok"]).is_false()
	assert_bool(b.cmd_fight(pink, _foe(b, 1))["ok"]).is_true()
	assert_int(b.fight_chooser()).is_equal(FOE)


func test_counteroffensive_costs_two_so_one_cp_gets_no_prompt() -> void:
	# Arrange
	var b: Battle = _two_combats()
	b.flow.command_points[ME] = 1

	# Act
	b.cmd_fight(_foe(b, 0), _mine(b, 0))

	# Assert
	assert_dict(b.pending).is_empty()


func test_counteroffensive_is_only_for_the_opponents_fight_phase() -> void:
	# Arrange: side 1 is not the one being reacted to, because it is side 0's own unit that fought
	var b: Battle = _battle([_unit("Red"), _unit("Pink")], [_unit("Blue"), _unit("Grey")])
	_put(_mine(b, 0), Vector2(10, 5))
	_put(_foe(b, 0), Vector2(11.5, 5))
	_at_phase(b, ME, "charge")
	b._windows_done.append(Stratagems.W_END_CHARGE)
	b.next_phase()
	b.next_phase()
	b.prompt_sides[ME] = true
	b.dice = Dice.new(1, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])

	# Act
	b.cmd_fight(_mine(b, 0), _foe(b, 0))

	# Assert
	assert_dict(b.pending).is_empty()


func test_a_forced_fighter_comes_back_from_a_save() -> void:
	# Arrange
	var b: Battle = _two_combats()
	b.cmd_fight(_foe(b, 0), _mine(b, 0))
	var pink: UnitState = _mine(b, 1)
	b.cmd_stratagem(ME, "counteroffensive", {"unit": pink.id})

	# Act
	var loaded: Battle = _reloaded(b)

	# Assert
	assert_int(loaded.fight_options().size()).is_equal(1)
	assert_str(loaded.fight_options()[0].id).is_equal(pink.id)
	assert_bool(loaded.unit_by_id(pink.id).is_fights_first()).is_true()


func _reloaded(b: Battle) -> Battle:
	return Battle.from_save(JSON.parse_string(JSON.stringify(b.to_save(), "", true, true)))


# ---------------------------------------------------------------- prompts and deadlocks

func test_a_waiting_window_blocks_everything_else() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)

	# Act and assert
	assert_bool(b.next_phase()["ok"]).is_false()
	assert_bool(b.cmd_hold(_foe(b))["ok"]).is_false()


func test_passing_a_window_lets_the_phase_end() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)

	# Act
	var r: Dictionary = b.cmd_pass(ME)

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_dict(b.pending).is_empty()
	assert_str(b.flow.phase()).is_equal("shooting")


func test_only_the_asked_side_can_pass() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)

	# Act and assert
	assert_bool(b.cmd_pass(FOE)["ok"]).is_false()
	assert_dict(b.pending).is_not_empty()


func test_no_prompt_when_the_cp_are_not_there() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	b.flow.command_points[ME] = 0

	# Act
	_open_end_of_movement(b)

	# Assert
	assert_dict(b.pending).is_empty()
	assert_str(b.flow.phase()).is_equal("shooting")


func test_no_prompt_when_prompts_are_off() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_at_phase(b, FOE, "movement")
	b.prompt_sides[ME] = false

	# Act
	b.next_phase()

	# Assert
	assert_dict(b.pending).is_empty()
	assert_str(b.flow.phase()).is_equal("shooting")


func test_each_window_opens_only_once() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)

	# Act
	b.cmd_stratagem(ME, "fire_overwatch")

	# Assert
	assert_dict(b.pending).is_empty()
	assert_str(b.flow.phase()).is_equal("shooting")


func test_a_played_out_turn_never_sits_on_a_prompt() -> void:
	# Arrange: side 0 wants prompts, nobody is there to answer them
	var armies: Array = [{"units": [_unit("Red"), _unit("Pink")]}, {"units": [_unit("Blue"), _unit("Grey")]}]
	var b := Battle.new(_scenario(), armies, 12)
	b.ai_sides = [false, true]
	b.prompt_sides = [true, false]
	b.flow.command_points = [9, 9]

	# Act and assert
	for i in range(4):
		b.play_turn()
		assert_dict(b.pending).is_empty()


func test_ai_games_finish_with_every_seed_tried() -> void:
	# Act and assert
	for seed_value in range(1, 21):
		var b := Battle.new(_scenario(), [{"units": [_unit("Red", 5, ["GRENADES", "SMOKE"]), _unit("Tank", 1, ["VEHICLE"], 12, 8)]},
			{"units": [_unit("Blue", 5, ["GRENADES", "SMOKE"]), _unit("Beast", 1, ["MONSTER", "CHARACTER"], 12, 8)]}], seed_value)
		b.start_deployment()
		b.play_all()
		assert_bool(b.is_over()).is_true()
		assert_dict(b.pending).is_empty()


# ---------------------------------------------------------------- the AI's choices

func test_the_ai_fires_overwatch_at_a_near_charger() -> void:
	# Arrange: side 1 is the AI, side 0 ends its movement close by
	var b: Battle = _battle()
	b.ai_sides = [false, true]
	_at_phase(b, ME, "movement")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(24, 15))

	# Act
	b.next_phase()

	# Assert
	assert_int(b.command_points(FOE)).is_equal(4)
	assert_bool(b.events.any(func(e: Dictionary) -> bool: return e["type"] == "shoot" and bool(e.get("snap", false)))).is_true()


func test_the_ai_saves_its_cp_when_nothing_is_near() -> void:
	# Arrange
	var b: Battle = _battle()
	b.ai_sides = [false, true]
	_at_phase(b, ME, "movement")
	_put(_mine(b), Vector2(4, 15))
	_put(_foe(b), Vector2(24, 15))

	# Act
	b.next_phase()

	# Assert
	assert_int(b.command_points(FOE)).is_equal(5)


func test_the_ai_uses_insane_bravery_on_an_objective_only() -> void:
	# Arrange: its unit is at half strength, testing on dice that would fail
	var b: Battle = _battle()
	b.ai_sides = [false, true]
	var foe: UnitState = _foe(b)
	foe.models.resize(2)
	foe.starting_strength = 5
	_put(foe, Vector2(22, 15))
	b.flow.active_player = FOE
	b.dice = Dice.new(1, [1, 1])

	# Act
	b.begin_turn()

	# Assert
	assert_bool(foe.battle_shocked).is_false()
	assert_bool(b.used_this_battle(FOE, "insane_bravery")).is_true()


func test_the_ai_keeps_its_cp_for_a_test_away_from_objectives() -> void:
	# Arrange
	var b: Battle = _battle()
	b.ai_sides = [false, true]
	var foe: UnitState = _foe(b)
	foe.models.resize(2)
	foe.starting_strength = 5
	_put(foe, Vector2(40, 2))
	b.flow.active_player = FOE
	b.dice = Dice.new(1, [1, 1])

	# Act
	b.begin_turn()

	# Assert
	assert_bool(foe.battle_shocked).is_true()
	assert_bool(b.used_this_battle(FOE, "insane_bravery")).is_false()


func test_the_ai_uses_counteroffensive_with_a_unit_worth_it() -> void:
	# Arrange: a human turn, with the AI's second unit waiting to fight
	var b: Battle = _battle([_unit("Red"), _unit("Pink")], [_unit("Blue"), _unit("Grey")])
	b.ai_sides = [false, true]
	_put(_mine(b, 0), Vector2(10, 5))
	_put(_foe(b, 0), Vector2(11.5, 5))
	_put(_mine(b, 1), Vector2(10, 20))
	_put(_foe(b, 1), Vector2(11.5, 20))
	_at_phase(b, ME, "charge")
	b.next_phase()
	b.next_phase()
	b.dice = Dice.new(1, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])

	# Act
	b.cmd_fight(_mine(b, 0), _foe(b, 0))

	# Assert
	assert_int(b.command_points(FOE)).is_equal(3)
	assert_int(b.fight_chooser()).is_equal(FOE)


# ---------------------------------------------------------------- saves

func test_cp_and_stratagem_use_survive_a_save() -> void:
	# Arrange
	var b: Battle = _battle([_unit("Red", 5, ["GRENADES"])], [_unit("Blue", 5)])
	_at_phase(b, ME, "shooting")
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(19, 15))
	b.cmd_stratagem(ME, "explosives")
	(b._used_battle[FOE] as Array).append("insane_bravery")

	# Act
	var loaded: Battle = _reloaded(b)

	# Assert
	assert_int(loaded.command_points(ME)).is_equal(4)
	assert_bool(loaded.used_this_phase(ME, "explosives")).is_true()
	assert_bool(loaded.targeted_this_phase(ME, loaded.living(ME)[0])).is_true()
	assert_bool(loaded.used_this_battle(FOE, "insane_bravery")).is_true()


func test_a_waiting_window_survives_a_save_and_can_still_be_answered() -> void:
	# Arrange
	var b: Battle = _battle()
	_put(_mine(b), Vector2(10, 15))
	_put(_foe(b), Vector2(20, 15))
	_open_end_of_movement(b)

	# Act
	var loaded: Battle = _reloaded(b)

	# Assert
	assert_str(str(loaded.pending["window"])).is_equal(Stratagems.W_END_MOVEMENT)
	assert_array(_ids(loaded.stratagem_options(ME))).contains(["fire_overwatch"])
	assert_bool(loaded.cmd_stratagem(ME, "fire_overwatch")["ok"]).is_true()
	assert_str(loaded.flow.phase()).is_equal("shooting")


func test_a_battle_shock_test_in_progress_survives_a_save() -> void:
	# Arrange: the roll has failed and the re-roll question is open
	var b: Battle = _battle()
	_half_strength_turn(b, [1, 2, 6])
	b.cmd_pass(ME)

	# Act
	var loaded: Battle = _reloaded(b)
	loaded.dice = Dice.new(1, [6])
	loaded.cmd_stratagem(ME, "command_reroll")

	# Assert
	assert_bool(loaded.living(ME)[0].battle_shocked).is_false()
	assert_dict(loaded.pending).is_empty()
	assert_str(loaded.events.back()["type"]).is_equal("turn_start")


func test_a_save_from_before_stratagems_still_loads() -> void:
	# Arrange
	var data: Dictionary = _battle().to_save()
	data["version"] = 1
	for key in ["pending", "used_phase", "used_battle", "deployment_active", "undeployed", "shock"]:
		data.erase(key)

	# Act
	var loaded: Battle = Battle.from_save(data)

	# Assert
	assert_object(loaded).is_not_null()
	assert_dict(loaded.pending).is_empty()
