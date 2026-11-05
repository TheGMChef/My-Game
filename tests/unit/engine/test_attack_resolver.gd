extends GdUnitTestSuite

func _target(models: int = 5, wounds: int = 1, sv: int = 4, extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"name": "Target", "models": models, "toughness": 4, "save": sv, "wounds": wounds}
	d.merge(extra, true)
	return UnitState.from_dict(d, "t", 1, Vector2.ZERO)

func _weapon(extra: Dictionary = {}) -> Weapon:
	var d: Dictionary = {"name": "gun", "range": 24, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1"}
	d.merge(extra, true)
	return Weapon.from_dict(d)

func _dice(values: Array[int]) -> Dice:
	return Dice.new(1, values)

# --- wound table (05.02) ---

func test_wound_thresholds_follow_strength_versus_toughness() -> void:
	assert_int(AttackResolver.wound_threshold(8, 4)).is_equal(2)
	assert_int(AttackResolver.wound_threshold(5, 4)).is_equal(3)
	assert_int(AttackResolver.wound_threshold(4, 4)).is_equal(4)
	assert_int(AttackResolver.wound_threshold(3, 4)).is_equal(5)
	assert_int(AttackResolver.wound_threshold(2, 4)).is_equal(6)
	assert_int(AttackResolver.wound_threshold(4, 8)).is_equal(6)

# --- basic sequence ---

func test_one_attack_that_hits_wounds_and_fails_its_save_destroys_a_model() -> void:
	var t := _target()
	var d := _dice([3, 4, 3])  # hit, wound, save
	var r := AttackResolver.resolve(_weapon(), t, d)
	assert_int(r["hits"]).is_equal(1)
	assert_int(r["wounds"]).is_equal(1)
	assert_int(r["unsaved"]).is_equal(1)
	assert_int(t.model_count()).is_equal(4)
	assert_int(d.scripted_left()).is_equal(0)

func test_hit_roll_below_skill_fails_and_no_further_dice_are_rolled() -> void:
	var t := _target()
	var d := _dice([2])
	var r := AttackResolver.resolve(_weapon(), t, d)
	assert_int(r["hits"]).is_equal(0)
	assert_int(t.model_count()).is_equal(5)

func test_unmodified_hit_roll_of_1_fails_even_with_a_big_bonus() -> void:
	var r := AttackResolver.resolve(_weapon(), _target(), _dice([1]), {"hit_mod": 3})
	assert_int(r["hits"]).is_equal(0)

func test_unmodified_6_hits_even_when_cover_makes_the_skill_7_plus() -> void:
	var r := AttackResolver.resolve(_weapon({"skill": 6}), _target(), _dice([6, 1, 1]), {"cover": true})
	assert_int(r["hits"]).is_equal(1)
	assert_int(r["critical_hits"]).is_equal(1)

func test_cover_worsens_the_hit_roll_by_one() -> void:
	var with_cover := AttackResolver.resolve(_weapon(), _target(), _dice([3]), {"cover": true})
	var without := AttackResolver.resolve(_weapon(), _target(), _dice([3, 1]), {})
	assert_int(with_cover["hits"]).is_equal(0)
	assert_int(without["hits"]).is_equal(1)

func test_ignores_cover_weapon_ignores_the_cover_penalty() -> void:
	var r := AttackResolver.resolve(_weapon({"abilities": ["IGNORES COVER"]}), _target(), _dice([3, 1]), {"cover": true})
	assert_int(r["hits"]).is_equal(1)

func test_wound_roll_of_1_always_fails_and_6_always_wounds() -> void:
	var weak := _weapon({"strength": 1})
	var r := AttackResolver.resolve(weak, _target(), _dice([4, 6, 1]))
	assert_int(r["wounds"]).is_equal(1)
	assert_int(r["critical_wounds"]).is_equal(1)

# --- saves ---

func test_ap_lowers_the_save_roll() -> void:
	var saved := AttackResolver.resolve(_weapon(), _target(), _dice([3, 4, 4]))
	var broken := AttackResolver.resolve(_weapon({"ap": 1}), _target(), _dice([3, 4, 4]))
	assert_int(saved["saved"]).is_equal(1)
	assert_int(broken["unsaved"]).is_equal(1)

func test_invulnerable_save_ignores_ap() -> void:
	var t := _target(5, 1, 3, {"invuln": 4})
	var r := AttackResolver.resolve(_weapon({"ap": 3}), t, _dice([3, 4, 4]))
	assert_int(r["saved"]).is_equal(1)

func test_unmodified_save_of_1_always_fails() -> void:
	var t := _target(5, 1, 2, {"invuln": 4})
	var r := AttackResolver.resolve(_weapon(), t, _dice([3, 4, 1]))
	assert_int(r["unsaved"]).is_equal(1)

func test_damage_does_not_spill_over_to_other_models() -> void:
	var t := _target(3, 1)
	var r := AttackResolver.resolve(_weapon({"damage": "3"}), t, _dice([3, 4, 1]))
	assert_int(t.model_count()).is_equal(2)
	assert_int(r["damage"]).is_equal(3)

func test_wounded_model_is_chosen_before_fresh_ones() -> void:
	var t := _target(3, 2)
	t.models[2]["wounds"] = 1
	AttackResolver.resolve(_weapon(), t, _dice([3, 4, 1]))
	assert_int(t.model_count()).is_equal(2)
	for m in t.models:
		assert_int(m["wounds"]).is_equal(2)

func test_feel_no_pain_can_stop_a_wound() -> void:
	var t := _target(5, 1, 4, {"fnp": 5})
	var r := AttackResolver.resolve(_weapon(), t, _dice([3, 4, 1, 5]))
	assert_int(t.model_count()).is_equal(5)
	assert_int(r["fnp_saved"]).is_equal(1)

# --- weapon abilities ---

func test_torrent_hits_automatically() -> void:
	var r := AttackResolver.resolve(_weapon({"attacks": "3", "abilities": ["TORRENT"]}), _target(), _dice([1, 1, 1, 1, 1, 1] as Array[int]))
	assert_int(r["hits"]).is_equal(3)

func test_rapid_fire_adds_attacks_only_at_half_range() -> void:
	var w := _weapon({"abilities": ["RAPID FIRE 2"]})
	assert_int(AttackResolver.gather_attacks(w, _target(), _dice([]), {"half_range": true})).is_equal(3)
	assert_int(AttackResolver.gather_attacks(w, _target(), _dice([]), {"half_range": false})).is_equal(1)

func test_blast_adds_one_attack_per_five_target_models_rounded_down() -> void:
	var w := _weapon({"attacks": "3", "abilities": ["BLAST"]})
	assert_int(AttackResolver.gather_attacks(w, _target(12), _dice([]), {})).is_equal(5)
	assert_int(AttackResolver.gather_attacks(w, _target(4), _dice([]), {})).is_equal(3)

func test_blast_x_adds_x_per_five_models() -> void:
	var w := _weapon({"attacks": "3", "abilities": ["BLAST 2"]})
	assert_int(AttackResolver.gather_attacks(w, _target(12), _dice([]), {})).is_equal(7)

func test_cleave_adds_attacks_per_five_models_when_one_target() -> void:
	var w := _weapon({"attacks": "3", "abilities": ["CLEAVE 1"]})
	assert_int(AttackResolver.gather_attacks(w, _target(16), _dice([]), {})).is_equal(6)

func test_lethal_hits_skips_the_wound_roll_on_a_critical_hit() -> void:
	var d := _dice([6, 1])  # hit crit, save 1
	var r := AttackResolver.resolve(_weapon({"abilities": ["LETHAL HITS"]}), _target(), d)
	assert_int(r["wounds"]).is_equal(1)
	assert_int(r["unsaved"]).is_equal(1)
	assert_int(d.scripted_left()).is_equal(0)

func test_sustained_hits_adds_extra_hits_on_a_critical() -> void:
	var d := _dice([6, 1, 1, 1] as Array[int])  # one crit hit => 2 wound rolls (both fail on 1)
	var r := AttackResolver.resolve(_weapon({"abilities": ["SUSTAINED HITS 1"]}), _target(), d)
	assert_int(r["hits"]).is_equal(2)
	assert_int(d.scripted_left()).is_equal(1)

func test_anti_makes_a_matching_wound_roll_critical() -> void:
	var t := _target(1, 10, 4, {"keywords": ["VEHICLE"]})
	var r := AttackResolver.resolve(_weapon({"strength": 1, "abilities": ["ANTI-VEHICLE 4+"]}), t, _dice([3, 4, 1]))
	assert_int(r["critical_wounds"]).is_equal(1)

func test_anti_does_nothing_against_other_keywords() -> void:
	var r := AttackResolver.resolve(_weapon({"strength": 1, "abilities": ["ANTI-VEHICLE 4+"]}), _target(), _dice([3, 4]))
	assert_int(r["critical_wounds"]).is_equal(0)

func test_devastating_wounds_skip_the_save_and_hit_one_model_only() -> void:
	var t := _target(3, 2)
	var d := _dice([3, 6])  # hit, critical wound; no save dice
	var r := AttackResolver.resolve(_weapon({"damage": "3", "abilities": ["DEVASTATING WOUNDS"]}), t, d)
	assert_int(t.model_count()).is_equal(2)
	assert_int(r["mortal_wounds"]).is_equal(2)
	assert_int(d.scripted_left()).is_equal(0)

func test_lance_adds_one_to_wound_roll_after_a_charge() -> void:
	var w := _weapon({"strength": 3, "abilities": ["LANCE"]})  # needs 5+
	assert_int(AttackResolver.resolve(w, _target(), _dice([3, 4, 1]), {"charged": true})["wounds"]).is_equal(1)
	assert_int(AttackResolver.resolve(w, _target(), _dice([3, 4]), {"charged": false})["wounds"]).is_equal(0)

func test_heavy_gives_plus_one_to_hit_when_stationary() -> void:
	var w := _weapon({"skill": 4, "abilities": ["HEAVY"]})
	assert_int(AttackResolver.resolve(w, _target(), _dice([3, 1]), {"heavy_bonus": true})["hits"]).is_equal(1)
	assert_int(AttackResolver.resolve(w, _target(), _dice([3]), {"heavy_bonus": false})["hits"]).is_equal(0)

func test_melta_adds_to_damage_at_half_range() -> void:
	var t := _target(2, 5)
	var r := AttackResolver.resolve(_weapon({"abilities": ["MELTA 2"]}), t, _dice([3, 4, 1]), {"half_range": true})
	assert_int(r["damage"]).is_equal(3)

# --- mortal wounds and hazard rolls ---

func test_mortal_wounds_finish_a_wounded_model_before_touching_another() -> void:
	var t := _target(3, 2)
	AttackResolver.mortal_wounds(t, 2, _dice([]))
	assert_int(t.model_count()).is_equal(2)

func test_character_models_take_mortal_wounds_last() -> void:
	var t := _target(2, 3)
	t.models[0]["character"] = true
	AttackResolver.mortal_wounds(t, 3, _dice([]))
	assert_int(t.model_count()).is_equal(1)
	assert_bool(t.models[0]["character"]).is_true()

func test_hazard_roll_of_2_costs_one_wound() -> void:
	var t := _target(3, 1)
	assert_int(AttackResolver.hazard_roll(t, _dice([2]))).is_equal(1)

func test_hazard_roll_of_3_is_safe() -> void:
	assert_int(AttackResolver.hazard_roll(_target(3, 1), _dice([3]))).is_equal(0)

func test_hazard_roll_on_a_vehicle_costs_three_wounds() -> void:
	var t := _target(1, 10, 3, {"keywords": ["VEHICLE"]})
	assert_int(AttackResolver.hazard_roll(t, _dice([1]))).is_equal(3)
