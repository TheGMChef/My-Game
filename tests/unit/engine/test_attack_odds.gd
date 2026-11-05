extends GdUnitTestSuite

func _target(extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"name": "T", "models": 100, "toughness": 4, "save": 4, "wounds": 20}
	d.merge(extra, true)
	return UnitState.from_dict(d, "t", 1, Vector2.ZERO)

func _weapon(extra: Dictionary = {}) -> Weapon:
	var d: Dictionary = {"name": "w", "range": 24, "attacks": "3", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}
	d.merge(extra, true)
	return Weapon.from_dict(d)

# --- Dice.distribution ---

func test_distribution_of_a_d6_is_uniform() -> void:
	var d := Dice.distribution("D6")
	assert_int(d.size()).is_equal(6)
	assert_float(d[3]).is_equal_approx(1.0 / 6.0, 0.0001)

func test_distribution_of_2d6_peaks_at_seven() -> void:
	assert_float(Dice.distribution("2D6")[7]).is_equal_approx(6.0 / 36.0, 0.0001)

func test_distribution_of_d3_has_three_equal_outcomes() -> void:
	var d := Dice.distribution("D3")
	assert_int(d.size()).is_equal(3)
	assert_float(d[2]).is_equal_approx(1.0 / 3.0, 0.0001)

func test_capped_average_limits_damage_to_model_wounds() -> void:
	assert_float(Dice.average_capped("D6", 2)).is_equal_approx((1 + 2 * 5) / 6.0, 0.0001)

# --- exact numbers ---

func test_simple_weapon_numbers() -> void:
	var o := AttackOdds.compute(_weapon(), _target())
	assert_int(o["hit_target"]).is_equal(3)
	assert_int(o["wound_target"]).is_equal(4)
	assert_float(o["p_hit"]).is_equal_approx(4.0 / 6.0, 0.0001)     # 3,4,5,6
	assert_float(o["p_wound"]).is_equal_approx(3.0 / 6.0, 0.0001)   # 4,5,6
	assert_float(o["p_unsaved"]).is_equal_approx(3.0 / 6.0, 0.0001)  # a 4+ save fails on 1,2,3
	assert_float(o["attacks"]).is_equal(3.0)

func test_cover_makes_the_hit_target_one_worse() -> void:
	assert_int(AttackOdds.compute(_weapon(), _target(), {"cover": true})["hit_target"]).is_equal(4)

func test_torrent_is_an_automatic_hit() -> void:
	var o := AttackOdds.compute(_weapon({"abilities": ["TORRENT"]}), _target())
	assert_bool(o["auto_hit"]).is_true()
	assert_float(o["p_hit"]).is_equal(1.0)

# --- agreement with the dice resolver ---

func _simulate(weapon: Weapon, target_extra: Dictionary, ctx: Dictionary, trials: int) -> float:
	var total: float = 0.0
	var dice := Dice.new(12345)
	for i in range(trials):
		var t := _target(target_extra)
		var r := AttackResolver.resolve(weapon, t, dice, ctx)
		total += float(r["damage"] + r["mortal_wounds"])
	return total / float(trials)

func _check(weapon_extra: Dictionary, target_extra: Dictionary = {}, ctx: Dictionary = {}) -> void:
	var w := _weapon(weapon_extra)
	var expected: float = AttackOdds.compute(w, _target(target_extra), ctx)["expected_damage"]
	var got: float = _simulate(w, target_extra, ctx, 3000)
	assert_float(got).is_equal_approx(expected, maxf(0.06 * expected, 0.05))

func test_odds_match_simulation_for_a_plain_weapon() -> void:
	_check({})

func test_odds_match_simulation_with_ap_and_damage_dice() -> void:
	_check({"ap": 2, "damage": "D6", "attacks": "5"})

func test_odds_match_simulation_with_invulnerable_save_and_fnp() -> void:
	_check({"ap": 3, "strength": 8}, {"save": 3, "invuln": 5, "fnp": 5})

func test_odds_match_simulation_with_lethal_hits() -> void:
	_check({"abilities": ["LETHAL HITS"], "attacks": "6"})

func test_odds_match_simulation_with_sustained_hits() -> void:
	_check({"abilities": ["SUSTAINED HITS 2"], "attacks": "6"})

func test_odds_match_simulation_with_devastating_wounds() -> void:
	_check({"abilities": ["DEVASTATING WOUNDS"], "damage": "2", "attacks": "6"})

func test_odds_match_simulation_with_anti() -> void:
	_check({"abilities": ["ANTI-VEHICLE 3+"], "strength": 3, "attacks": "6"}, {"keywords": ["VEHICLE"]})

func test_odds_match_simulation_with_blast_and_cover() -> void:
	_check({"abilities": ["BLAST"], "attacks": "D6"}, {}, {"cover": true})

func test_odds_match_simulation_with_rapid_fire_and_melta() -> void:
	_check({"abilities": ["RAPID FIRE 1", "MELTA 2"], "damage": "D6"}, {}, {"half_range": true, "models_firing": 3})
