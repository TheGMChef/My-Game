extends GdUnitTestSuite

func test_parses_ability_with_number() -> void:
	var a := WeaponAbility.parse("RAPID FIRE 2")
	assert_str(a["name"]).is_equal("RAPID FIRE")
	assert_int(a["value"]).is_equal(2)

func test_parses_anti_keyword_and_threshold() -> void:
	var a := WeaponAbility.parse("ANTI-VEHICLE 4+")
	assert_str(a["name"]).is_equal("ANTI")
	assert_int(a["threshold"]).is_equal(4)
	assert_array(a["keywords"]).is_equal(["VEHICLE"])

func test_parses_keyword_restriction() -> void:
	var a := WeaponAbility.parse("lethal hits: vehicle / monster")
	assert_str(a["name"]).is_equal("LETHAL HITS")
	assert_array(a["keywords"]).is_equal(["VEHICLE", "MONSTER"])

func test_pistol_is_treated_as_close_quarters() -> void:
	assert_str(WeaponAbility.parse("PISTOL")["name"]).is_equal("CLOSE-QUARTERS")

func test_keyword_restricted_ability_only_applies_to_matching_target() -> void:
	var w := Weapon.from_dict({"name": "x", "range": 24, "abilities": ["LETHAL HITS: VEHICLE"]})
	assert_bool(w.has("LETHAL HITS", ["VEHICLE"])).is_true()
	assert_bool(w.has("LETHAL HITS", ["INFANTRY"])).is_false()

func test_duplicate_abilities_use_highest_value() -> void:
	var w := Weapon.from_dict({"name": "x", "range": 24, "abilities": ["RAPID FIRE 1", "RAPID FIRE 2"]})
	assert_int(w.ability("RAPID FIRE")["value"]).is_equal(2)

func test_ap_is_stored_as_negative_and_zero_range_is_melee() -> void:
	var w := Weapon.from_dict({"name": "blade", "range": 0, "ap": 2})
	assert_int(w.ap).is_equal(-2)
	assert_bool(w.is_melee()).is_true()
