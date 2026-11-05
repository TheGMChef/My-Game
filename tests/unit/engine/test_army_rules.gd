extends GdUnitTestSuite
## Reanimation Protocols, Synapse, Shadow in the Warp and For the Greater Good. Fixtures are invented.

const FAR := Vector2(40, 28)


func _unit(owner: int, extra: Dictionary, pos: Vector2 = Vector2(10, 10)) -> UnitState:
	var d: Dictionary = {"name": "Unit", "models": 1, "wounds": 1, "leadership": 7, "base_mm": 25.4}
	d.merge(extra, true)
	return UnitState.from_dict(d, "u%d_%d" % [owner, randi() % 100000], owner, pos)


func _battle(dice_rolls: Array[int]) -> Battle:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	sc["terrain"] = []
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var b := Battle.new(sc, armies, 1)
	b.units = []
	if not dice_rolls.is_empty():
		b.dice = Dice.new(1, dice_rolls)
	return b


func _gun() -> Dictionary:
	return {"name": "gun", "range": 24, "attacks": "1", "skill": 4, "strength": 4, "ap": 0, "damage": "1", "abilities": []}


func _to_shooting(b: Battle) -> void:
	var guard: int = 0
	while b.phase() != "shooting" and guard < 6:
		guard += 1
		b.next_phase()


# --- Reanimation Protocols ---

func test_reanimation_heals_wounded_models() -> void:
	# Arrange
	var u := _unit(0, {"wounds": 4, "models": 1, "faction_abilities": ["REANIMATION PROTOCOLS"]})
	u.models[0]["wounds"] = 1

	# Act
	var healed: int = ArmyRules.reanimate(u, 2, [u], Rect2(0, 0, 44, 30))

	# Assert
	assert_int(healed).is_equal(2)
	assert_int(u.models[0]["wounds"]).is_equal(3)


func test_reanimation_never_passes_full_wounds() -> void:
	# Arrange
	var u := _unit(0, {"wounds": 4})
	u.models[0]["wounds"] = 3

	# Act
	var healed: int = ArmyRules.reanimate(u, 3, [u], Rect2(0, 0, 44, 30))

	# Assert
	assert_int(healed).is_equal(1)
	assert_int(u.models[0]["wounds"]).is_equal(4)


func test_reanimation_brings_back_destroyed_models_up_to_starting_strength() -> void:
	# Arrange
	var u := _unit(0, {"models": 5})
	u.models.resize(3)

	# Act
	var healed: int = ArmyRules.reanimate(u, 3, [u], Rect2(0, 0, 44, 30))

	# Assert
	assert_int(healed).is_equal(2)
	assert_int(u.model_count()).is_equal(5)


func test_returned_models_do_not_stand_on_other_models() -> void:
	# Arrange
	var u := _unit(0, {"models": 3})
	u.models.resize(2)

	# Act
	ArmyRules.reanimate(u, 1, [u], Rect2(0, 0, 44, 30))

	# Assert
	var gap: float = Geo.edge_distance(u.models[0]["pos"], u.base_radius, u.models[2]["pos"], u.base_radius)
	assert_float(gap).is_greater_equal(0.0)


func test_battle_runs_reanimation_at_the_end_of_your_command_phase() -> void:
	# Arrange: scripted D3 from a roll of 6 is 3
	var b := _battle([6])
	var u := _unit(b.flow.active_player, {"wounds": 5, "faction_abilities": ["REANIMATION PROTOCOLS"]})
	u.models[0]["wounds"] = 1
	b.units = [u]

	# Act
	b.begin_turn()

	# Assert
	assert_int(u.models[0]["wounds"]).is_equal(4)


# --- Synapse ---

func test_tyranids_within_six_inches_of_synapse_are_in_range() -> void:
	# Arrange
	var bug := _unit(0, {"keywords": ["TYRANIDS"]})
	var brain := _unit(0, {"keywords": ["TYRANIDS", "SYNAPSE"]}, Vector2(15, 10))

	# Assert
	assert_bool(ArmyRules.in_synapse(bug, [bug, brain])).is_true()


func test_out_of_range_or_other_factions_are_not_in_synapse() -> void:
	# Arrange
	var far := _unit(0, {"keywords": ["TYRANIDS"]}, FAR)
	var other := _unit(0, {"keywords": ["NECRONS"]}, Vector2(11, 10))
	var brain := _unit(0, {"keywords": ["TYRANIDS", "SYNAPSE"]})
	var enemy_brain := _unit(1, {"keywords": ["TYRANIDS", "SYNAPSE"]}, FAR)

	# Assert
	assert_bool(ArmyRules.in_synapse(far, [far, brain])).is_false()
	assert_bool(ArmyRules.in_synapse(other, [other, brain])).is_false()
	assert_bool(ArmyRules.in_synapse(far, [far, enemy_brain])).is_false()


func test_faction_keywords_count_as_keywords() -> void:
	# Arrange
	var u := _unit(0, {"faction_keywords": ["Tyranids"]})

	# Assert
	assert_bool(u.has_keyword("TYRANIDS")).is_true()


func test_battle_shock_takes_three_dice_in_synapse() -> void:
	# Arrange: 3, 3 fails leadership 7 on 2D6, but three dice pass
	var u := _unit(0, {"keywords": ["TYRANIDS", "SYNAPSE"]})

	# Act
	var passed: bool = UnitRules.battle_shock_roll(u, Dice.new(1, [3, 3, 3] as Array[int]), [u])

	# Assert
	assert_bool(passed).is_true()


func test_battle_shock_takes_two_dice_outside_synapse() -> void:
	# Arrange
	var u := _unit(0, {})

	# Act
	var passed: bool = UnitRules.battle_shock_roll(u, Dice.new(1, [3, 3] as Array[int]), [u])

	# Assert
	assert_bool(passed).is_false()


func test_strength_bonus_changes_the_wound_roll() -> void:
	# Arrange: S4 into T5 wounds on 5+, S5 wounds on 4+; hit 3, wound 4, save 1 fails
	var w := Weapon.from_dict({"name": "claw", "range": 0, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": []})
	var target := _unit(1, {"toughness": 5, "save": 6})

	# Act
	var r: Dictionary = AttackResolver.resolve(w, target, Dice.new(1, [3, 4, 1] as Array[int]), {"strength_bonus": 1})

	# Assert
	assert_int(r["wounds"]).is_equal(1)


func test_odds_use_the_strength_bonus() -> void:
	# Arrange
	var w := Weapon.from_dict({"name": "claw", "range": 0, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": []})
	var target := _unit(1, {"toughness": 5})

	# Act
	var o: Dictionary = AttackOdds.compute(w, target, {"strength_bonus": 1})

	# Assert
	assert_int(o["wound_target"]).is_equal(4)


# --- Shadow in the Warp ---

func test_shadow_tests_every_enemy_with_minus_one_near_synapse() -> void:
	# Arrange: 3 + 4 = 7 passes at leadership 7, but not at -1 near Synapse
	var b := _battle([3, 4, 3, 4])
	var side: int = b.flow.active_player
	var bug := _unit(side, {"keywords": ["TYRANIDS", "SYNAPSE"], "faction_abilities": ["SHADOW IN THE WARP"]})
	var near := _unit(1 - side, {}, Vector2(14, 10))
	var far := _unit(1 - side, {}, FAR)
	b.units = [bug, near, far]

	# Act
	var r: Dictionary = b.cmd_shadow_in_the_warp(side)

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_bool(near.battle_shocked).is_true()
	assert_bool(far.battle_shocked).is_false()


func test_shadow_can_only_be_used_once_per_battle() -> void:
	# Arrange
	var b := _battle([])
	var side: int = b.flow.active_player
	b.units = [_unit(side, {"faction_abilities": ["SHADOW IN THE WARP"]})]
	b.cmd_shadow_in_the_warp(side)

	# Act
	var again: Dictionary = b.cmd_shadow_in_the_warp(side)

	# Assert
	assert_bool(again["ok"]).is_false()


func test_shadow_needs_a_unit_with_the_ability() -> void:
	# Arrange
	var b := _battle([])
	b.units = [_unit(b.flow.active_player, {})]

	# Assert
	assert_bool(b.can_unleash_shadow(b.flow.active_player)).is_false()


# --- For the Greater Good ---

func _tau_battle(markerlight: bool = false) -> Dictionary:
	var b := _battle([])
	var side: int = b.flow.active_player
	var keys: Array = ["MARKERLIGHT"] if markerlight else []
	var observer := _unit(side, {"keywords": keys, "faction_abilities": ["FOR THE GREATER GOOD"], "weapons": [_gun()]})
	var shooter := _unit(side, {"faction_abilities": ["FOR THE GREATER GOOD"], "weapons": [_gun()]}, Vector2(10, 14))
	var enemy := _unit(1 - side, {}, Vector2(20, 12))
	b.units = [observer, shooter, enemy]
	_to_shooting(b)
	return {"b": b, "observer": observer, "shooter": shooter, "enemy": enemy}


func test_guided_unit_improves_ballistic_skill_against_a_spotted_unit() -> void:
	# Arrange
	var t: Dictionary = _tau_battle()
	var b: Battle = t["b"]

	# Act
	var r: Dictionary = b.cmd_mark_spotted(t["observer"], t["enemy"])

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_int(b.shoot_preview(t["shooter"], t["enemy"])[0]["odds"]["hit_target"]).is_equal(3)


func test_observer_is_not_guided() -> void:
	# Arrange
	var t: Dictionary = _tau_battle()
	var b: Battle = t["b"]
	b.cmd_mark_spotted(t["observer"], t["enemy"])

	# Assert
	assert_int(b.shoot_preview(t["observer"], t["enemy"])[0]["odds"]["hit_target"]).is_equal(4)


func test_an_enemy_can_only_be_spotted_once_a_phase() -> void:
	# Arrange
	var t: Dictionary = _tau_battle()
	var b: Battle = t["b"]
	b.cmd_mark_spotted(t["observer"], t["enemy"])

	# Act
	var r: Dictionary = b.cmd_mark_spotted(t["shooter"], t["enemy"])

	# Assert
	assert_bool(r["ok"]).is_false()


func test_a_unit_that_has_shot_cannot_observe() -> void:
	# Arrange
	var t: Dictionary = _tau_battle()
	var b: Battle = t["b"]
	b.cmd_shoot(t["observer"], t["enemy"])

	# Assert
	assert_bool(b.can_observe(t["observer"])).is_false()


func test_battle_shocked_units_cannot_observe() -> void:
	# Arrange
	var t: Dictionary = _tau_battle()
	(t["observer"] as UnitState).battle_shocked = true

	# Assert
	assert_bool((t["b"] as Battle).can_observe(t["observer"])).is_false()


func test_markerlight_observer_gives_ignores_cover() -> void:
	# Arrange
	var t: Dictionary = _tau_battle(true)
	var b: Battle = t["b"]
	b.cmd_mark_spotted(t["observer"], t["enemy"])

	# Act
	var ctx: Dictionary = b.shoot_preview(t["shooter"], t["enemy"])[0]["ctx"]
	ctx["cover"] = true

	# Assert: guided 3+, and cover adds nothing
	assert_int(int(AttackResolver.hit_numbers((t["shooter"] as UnitState).weapons[0], ctx)["skill"])).is_equal(3)
