extends GdUnitTestSuite
## [TWIN-LINKED], [PSYCHIC], [INDIRECT FIRE], [PRECISION], [ONE SHOT] and [ASSAULT].
## Fixtures are invented. Dice are scripted: hit, wound, save, ...

func _target(models: int = 5, extra: Dictionary = {}, pos: Vector2 = Vector2(20, 10)) -> UnitState:
	var d: Dictionary = {"name": "Target", "models": models, "toughness": 4, "save": 4, "wounds": 1, "base_mm": 25.4}
	d.merge(extra, true)
	return UnitState.from_dict(d, "t", 1, pos)

func _weapon(abilities: Array = [], extra: Dictionary = {}) -> Weapon:
	var d: Dictionary = {"name": "gun", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": abilities}
	d.merge(extra, true)
	return Weapon.from_dict(d)

func _dice(values: Array[int]) -> Dice:
	return Dice.new(1, values)

func _shooter(weapons: Array, extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"name": "Shooter", "models": 1, "toughness": 4, "save": 4, "wounds": 2, "base_mm": 25.4, "weapons": weapons}
	d.merge(extra, true)
	return UnitState.from_dict(d, "s", 0, Vector2(5, 10))

# --- TWIN-LINKED: re-roll a failed wound roll ---

func test_twin_linked_rerolls_a_failed_wound_roll() -> void:
	var d := _dice([3, 2, 5, 3])  # hit, wound fails, re-roll wounds, save fails
	var r := AttackResolver.resolve(_weapon(["TWIN-LINKED"]), _target(), d)
	assert_int(r["wounds"]).is_equal(1)
	assert_int(r["unsaved"]).is_equal(1)
	assert_int(d.scripted_left()).is_equal(0)

func test_twin_linked_reroll_can_fail_too() -> void:
	var d := _dice([3, 2, 2])
	var r := AttackResolver.resolve(_weapon(["TWIN-LINKED"]), _target(), d)
	assert_int(r["wounds"]).is_equal(0)
	assert_int(d.scripted_left()).is_equal(0)

func test_twin_linked_does_not_reroll_a_successful_wound() -> void:
	var d := _dice([3, 4, 3])
	var r := AttackResolver.resolve(_weapon(["TWIN-LINKED"]), _target(), d)
	assert_int(r["wounds"]).is_equal(1)
	assert_int(d.scripted_left()).is_equal(0)

func test_without_twin_linked_a_failed_wound_stands() -> void:
	var d := _dice([3, 2])
	var r := AttackResolver.resolve(_weapon(), _target(), d)
	assert_int(r["wounds"]).is_equal(0)

func test_twin_linked_odds_match_the_formula() -> void:
	# S4 v T4 wounds on 4+ (p = 0.5); with a re-roll 1 - 0.5 * 0.5 = 0.75
	var o := AttackOdds.compute(_weapon(["TWIN-LINKED"]), _target())
	assert_float(o["p_wound"]).is_equal_approx(0.75, 0.0001)

# --- PSYCHIC: ignore modifiers to the hit roll and BS ---

func test_psychic_ignores_the_cover_penalty() -> void:
	var d := _dice([3, 4, 3])
	var r := AttackResolver.resolve(_weapon(["PSYCHIC"]), _target(), d, {"cover": true})
	assert_int(r["hits"]).is_equal(1)

func test_non_psychic_weapon_misses_with_the_same_roll_in_cover() -> void:
	var d := _dice([3])
	var r := AttackResolver.resolve(_weapon(), _target(), d, {"cover": true})
	assert_int(r["hits"]).is_equal(0)

func test_psychic_keeps_a_helpful_modifier() -> void:
	var d := _dice([2, 4, 3])  # skill 3, +1 to hit makes a 2 into a 3
	var r := AttackResolver.resolve(_weapon(["PSYCHIC"]), _target(), d, {"hit_mod": 1})
	assert_int(r["hits"]).is_equal(1)

func test_psychic_ignores_a_hit_penalty() -> void:
	var d := _dice([3, 4, 3])
	var r := AttackResolver.resolve(_weapon(["PSYCHIC"]), _target(), d, {"hit_mod": -1})
	assert_int(r["hits"]).is_equal(1)

# --- INDIRECT FIRE hit threshold ---

func test_indirect_attack_hits_only_on_a_6_by_default() -> void:
	var d := _dice([5])
	var r := AttackResolver.resolve(_weapon(["INDIRECT FIRE"]), _target(), d, {"cover": true, "indirect_min": 6})
	assert_int(r["hits"]).is_equal(0)
	var d2 := _dice([6, 4, 3])
	var r2 := AttackResolver.resolve(_weapon(["INDIRECT FIRE"]), _target(), d2, {"cover": true, "indirect_min": 6})
	assert_int(r2["hits"]).is_equal(1)

func test_indirect_attack_hits_on_4_when_stationary_and_seen_by_a_friend() -> void:
	var d := _dice([4, 4, 3])  # cover makes skill 4+, so a 4 hits
	var r := AttackResolver.resolve(_weapon(["INDIRECT FIRE"]), _target(), d, {"cover": true, "indirect_min": 4})
	assert_int(r["hits"]).is_equal(1)
	var d2 := _dice([3])
	assert_int(AttackResolver.resolve(_weapon(["INDIRECT FIRE"]), _target(), d2, {"cover": true, "indirect_min": 4})["hits"]).is_equal(0)

func test_indirect_odds_match_the_resolver_threshold() -> void:
	var o := AttackOdds.compute(_weapon(["INDIRECT FIRE"]), _target(), {"cover": true, "indirect_min": 6})
	assert_float(o["p_hit"]).is_equal_approx(1.0 / 6.0, 0.0001)

# --- PRECISION: wounds go to a visible CHARACTER first ---

func _with_character() -> UnitState:
	var t := _target(3)
	t.models[2]["character"] = true
	return t

func test_without_precision_a_bodyguard_takes_the_wound() -> void:
	var t := _with_character()
	AttackResolver.resolve(_weapon(), t, _dice([3, 4, 1]))
	assert_int(t.model_count()).is_equal(2)
	assert_bool(t.models.any(func(m: Dictionary) -> bool: return bool(m["character"]))).is_true()

func test_precision_lets_the_character_take_the_wound() -> void:
	var t := _with_character()
	AttackResolver.resolve(_weapon(["PRECISION"]), t, _dice([3, 4, 1]))
	assert_int(t.model_count()).is_equal(2)
	assert_bool(t.models.any(func(m: Dictionary) -> bool: return bool(m["character"]))).is_false()

# --- ONE SHOT: once per battle ---

func test_one_shot_weapon_fires_once_then_is_gone() -> void:
	var s := _shooter([{"name": "Missile", "range": 48, "attacks": "1", "skill": 3, "strength": 8, "ap": 0, "damage": "1", "abilities": ["ONE SHOT"]}])
	var t := _target()
	assert_int(Combat.shoot_plan(s, t, [s, t], {}).size()).is_equal(1)
	Combat.shoot(s, t, [s, t], Dice.new(7), {})
	assert_int(Combat.shoot_plan(s, t, [s, t], {}).size()).is_equal(0)

# --- ASSAULT: the only weapons usable after an Advance ---

func test_after_advancing_only_assault_weapons_can_shoot() -> void:
	var s := _shooter([
		{"name": "Rifle", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"},
		{"name": "Carbine", "range": 18, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["ASSAULT"]}])
	var t := _target()
	s.advanced = true
	var plan := Combat.shoot_plan(s, t, [s, t], {})
	assert_int(plan.size()).is_equal(1)
	assert_str(plan[0]["weapon"].weapon_name).is_equal("Carbine")
	s.advanced = false
	assert_int(Combat.shoot_plan(s, t, [s, t], {}).size()).is_equal(2)

# --- INDIRECT FIRE targeting ---

func _wall() -> TerrainArea:
	return TerrainArea.from_dict({"rect": [10, 0, 6, 20], "features": [{"rect": [11, 1, 4, 18], "category": "dense", "height": 5.0}]})

func test_indirect_weapon_can_target_a_unit_it_cannot_see() -> void:
	var s := _shooter([
		{"name": "Rifle", "range": 40, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"},
		{"name": "Mortar", "range": 40, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["INDIRECT FIRE"]}])
	var t := _target(5, {}, Vector2(30, 10))
	var plan := Combat.shoot_plan(s, t, [s, t], {"terrain": [_wall()], "turn_no": 1})
	assert_int(plan.size()).is_equal(1)
	assert_str(plan[0]["weapon"].weapon_name).is_equal("Mortar")
	assert_bool(bool(plan[0]["ctx"]["cover"])).is_true()
	assert_int(int(plan[0]["ctx"]["indirect_min"])).is_equal(6)

func test_indirect_improves_to_4_when_stationary_and_a_friend_sees_the_target() -> void:
	var s := _shooter([{"name": "Mortar", "range": 40, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["INDIRECT FIRE"]}])
	var spotter := _shooter([], {"name": "Spotter"})
	spotter.id = "sp"
	spotter.models[0]["pos"] = Vector2(30, 2)  # beside the target, no wall between
	var t := _target(5, {}, Vector2(30, 10))
	var plan := Combat.shoot_plan(s, t, [s, spotter, t], {"terrain": [_wall()], "turn_no": 1})
	assert_int(int(plan[0]["ctx"]["indirect_min"])).is_equal(4)

func test_no_indirect_after_advancing() -> void:
	var s := _shooter([{"name": "Mortar", "range": 40, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["INDIRECT FIRE"]}])
	s.advanced = true
	var t := _target(5, {}, Vector2(30, 10))
	assert_int(Combat.shoot_plan(s, t, [s, t], {"terrain": [_wall()], "turn_no": 1}).size()).is_equal(0)

func test_indirect_weapon_aimed_at_a_visible_target_shoots_normally() -> void:
	var s := _shooter([{"name": "Mortar", "range": 40, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["INDIRECT FIRE"]}])
	var t := _target(5, {}, Vector2(8, 10))
	var plan := Combat.shoot_plan(s, t, [s, t], {"terrain": [_wall()], "turn_no": 1})
	assert_int(plan.size()).is_equal(1)
	assert_bool(plan[0]["ctx"].has("indirect_min")).is_false()
