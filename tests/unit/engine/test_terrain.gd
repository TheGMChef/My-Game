extends GdUnitTestSuite

const BOARD := Rect2(0, 0, 44, 30)

func _area(rect: Array, features: Array) -> TerrainArea:
	return TerrainArea.from_dict({"rect": rect, "features": features})

func _ruin(x: float, y: float, w: float, h: float, height: float = 5.0) -> TerrainArea:
	return _area([x, y, w, h], [{"rect": [x + 1, y + 1, w - 2, h - 2], "category": "dense", "height": height}])

func _unit(owner: int, pos: Vector2, extra: Dictionary = {}) -> UnitState:
	var d: Dictionary = {"models": 1, "base_mm": 25.4, "keywords": ["INFANTRY"]}
	d.merge(extra, true)
	var u := UnitState.from_dict(d, "u", owner, pos)
	return u

# --- visibility ---

func test_open_ground_is_visible() -> void:
	assert_bool(Visibility.model_sees(Vector2(5, 15), 0.5, Vector2(30, 15), 0.5, [])).is_true()

func test_obscuring_area_between_models_blocks_sight() -> void:
	var wall := _ruin(15, 5, 6, 20)
	assert_bool(Visibility.model_sees(Vector2(5, 15), 0.5, Vector2(30, 15), 0.5, [wall])).is_false()

func test_light_terrain_area_is_also_obscuring() -> void:
	var low := _area([15, 5, 4, 20], [{"rect": [16, 5, 2, 20], "category": "light", "height": 1.0}])
	assert_bool(Visibility.model_sees(Vector2(5, 15), 0.5, Vector2(30, 15), 0.5, [low])).is_false()

func test_exposed_terrain_does_not_block_sight() -> void:
	var craters := _area([15, 5, 4, 20], [{"rect": [16, 5, 2, 20], "category": "exposed", "height": 0.0}])
	assert_bool(Visibility.model_sees(Vector2(5, 15), 0.5, Vector2(30, 15), 0.5, [craters])).is_true()

func test_a_line_that_goes_around_the_terrain_is_visible() -> void:
	var wall := _ruin(15, 10, 6, 6)
	assert_bool(Visibility.model_sees(Vector2(5, 3), 0.5, Vector2(30, 3), 0.5, [wall])).is_true()

func test_obscuring_area_a_model_stands_in_does_not_block_its_own_sight_out() -> void:
	var light := _area([15, 5, 8, 20], [{"rect": [16, 6, 1, 18], "category": "light", "height": 1.0}])
	assert_bool(Visibility.model_sees(Vector2(19, 15), 0.5, Vector2(35, 15), 0.5, [light])).is_true()

# --- cover ---

func test_infantry_inside_a_terrain_area_has_cover() -> void:
	var area := _area([20, 10, 6, 10], [{"rect": [24, 10, 1, 10], "category": "light", "height": 1.0}])
	var target := _unit(1, Vector2(22, 15))
	assert_bool(Visibility.has_cover(Vector2(5, 15), 0.5, target, [area])).is_true()

func test_vehicle_inside_an_area_but_fully_visible_has_no_cover() -> void:
	var area := _area([20, 10, 6, 10], [{"rect": [24, 10, 1, 10], "category": "exposed", "height": 0.0}])
	var target := _unit(1, Vector2(22, 15), {"keywords": ["VEHICLE"]})
	assert_bool(Visibility.has_cover(Vector2(5, 15), 0.5, target, [area])).is_false()

func test_infantry_in_the_open_has_no_cover() -> void:
	assert_bool(Visibility.has_cover(Vector2(5, 15), 0.5, _unit(1, Vector2(30, 15)), [])).is_false()

func test_target_partly_hidden_behind_light_terrain_has_cover() -> void:
	var low := _area([15, 5, 2, 20], [{"rect": [15, 5, 2, 20], "category": "light", "height": 1.0}])
	var target := _unit(1, Vector2(30, 15), {"keywords": ["VEHICLE"]})
	assert_bool(Visibility.has_cover(Vector2(5, 15), 0.5, target, [low])).is_true()

# --- hidden ---

func test_infantry_in_dense_terrain_that_has_not_fired_is_hidden() -> void:
	var ruin := _ruin(20, 10, 6, 10)
	assert_bool(Visibility.is_hidden(_unit(1, Vector2(23, 15)), 10, [ruin])).is_true()

func test_unit_that_fired_this_turn_or_last_turn_is_not_hidden() -> void:
	var ruin := _ruin(20, 10, 6, 10)
	var u := _unit(1, Vector2(23, 15))
	u.last_fired_turn = 9
	assert_bool(Visibility.is_hidden(u, 10, [ruin])).is_false()
	u.last_fired_turn = 8
	assert_bool(Visibility.is_hidden(u, 10, [ruin])).is_true()

func test_vehicles_are_never_hidden() -> void:
	var ruin := _ruin(20, 10, 6, 10)
	assert_bool(Visibility.is_hidden(_unit(1, Vector2(23, 15), {"keywords": ["VEHICLE"]}), 10, [ruin])).is_false()

func test_hidden_unit_is_only_visible_inside_detection_range() -> void:
	var ruin := _area([20, 10, 6, 10], [{"rect": [21, 10, 0.1, 0.1], "category": "dense", "height": 5.0}])
	var target := _unit(1, Vector2(23, 15))
	assert_bool(Visibility.unit_visible_to_model(Vector2(5, 15), 0.5, target, 10, [ruin])).is_false()   # 17" away
	assert_bool(Visibility.unit_visible_to_model(Vector2(10, 15), 0.5, target, 10, [ruin])).is_true()    # 12" away

# --- movement ---

func test_infantry_can_move_through_dense_terrain() -> void:
	var ruin := _ruin(15, 5, 6, 20)
	var u := _unit(0, Vector2(10, 15), {"move": 12})
	var dest: Array[Vector2] = [Vector2(22, 15)]
	assert_bool(UnitRules.check_move(u, dest, "normal", [u], BOARD, 0, [ruin])["ok"]).is_true()

func test_vehicle_cannot_move_through_tall_dense_terrain() -> void:
	var ruin := _ruin(15, 5, 6, 20)
	var u := _unit(0, Vector2(10, 15), {"move": 12, "keywords": ["VEHICLE"]})
	var dest: Array[Vector2] = [Vector2(22, 15)]
	assert_bool(UnitRules.check_move(u, dest, "normal", [u], BOARD, 0, [ruin])["ok"]).is_false()

func test_vehicle_can_move_through_dense_terrain_two_inches_or_lower() -> void:
	var ruin := _ruin(15, 5, 6, 20, 2.0)
	var u := _unit(0, Vector2(10, 15), {"move": 12, "keywords": ["VEHICLE"]})
	var dest: Array[Vector2] = [Vector2(22, 15)]
	assert_bool(UnitRules.check_move(u, dest, "normal", [u], BOARD, 0, [ruin])["ok"]).is_true()

func test_no_model_may_end_a_move_inside_a_dense_feature() -> void:
	var ruin := _ruin(15, 5, 6, 20)
	var u := _unit(0, Vector2(10, 15), {"move": 12})
	var dest: Array[Vector2] = [Vector2(18, 15)]
	assert_bool(UnitRules.check_move(u, dest, "normal", [u], BOARD, 0, [ruin])["ok"]).is_false()

# --- shooting with terrain ---

func _gun() -> Dictionary:
	return {"name": "gun", "range": 36, "attacks": "1", "skill": 3, "strength": 4, "damage": "1"}

func test_shooting_through_an_obscuring_area_makes_no_attacks() -> void:
	var wall := _ruin(15, 5, 6, 20)
	var a := _unit(0, Vector2(5, 15), {"weapons": [_gun()]})
	var b := _unit(1, Vector2(30, 15))
	var out := Combat.shoot(a, b, [a, b], Dice.new(1), {"terrain": [wall], "turn_no": 1})
	assert_int(out["reports"].size()).is_equal(0)

func test_cover_from_terrain_worsens_the_hit_roll() -> void:
	var area := _area([20, 10, 6, 10], [{"rect": [24.5, 10, 0.2, 10], "category": "light", "height": 1.0}])
	var a := _unit(0, Vector2(5, 15), {"weapons": [_gun()]})
	var b := _unit(1, Vector2(22, 15), {"wounds": 3})
	# skill 3+ becomes 4+ in cover: a roll of 3 misses
	var out := Combat.shoot(a, b, [a, b], Dice.new(1, [3] as Array[int]), {"terrain": [area], "turn_no": 1})
	assert_int(out["reports"][0]["hits"]).is_equal(0)

func test_firing_a_ranged_weapon_records_the_turn_for_hidden() -> void:
	var a := _unit(0, Vector2(5, 15), {"weapons": [_gun()]})
	var b := _unit(1, Vector2(30, 15))
	Combat.shoot(a, b, [a, b], Dice.new(1, [1] as Array[int]), {"turn_no": 4})
	assert_int(a.last_fired_turn).is_equal(4)

func test_charge_cannot_end_inside_a_dense_feature() -> void:
	var ruin := _ruin(15, 5, 6, 20)
	var a := _unit(0, Vector2(10, 15))
	var b := _unit(1, Vector2(19, 15))
	var targets: Array[UnitState] = [b]
	var dest: Array[Vector2] = [Vector2(17.5, 15)]
	assert_bool(ChargeRules.check_move(a, dest, targets, 12, [a, b], BOARD, [ruin])["ok"]).is_false()
	assert_str(ChargeRules.check_move(a, dest, targets, 12, [a, b], BOARD, [ruin])["reason"]).contains("dense")

func test_pile_in_cannot_end_inside_a_dense_feature() -> void:
	var ruin := _ruin(15, 5, 6, 20)
	var a := _unit(0, Vector2(14, 15))
	var b := _unit(1, Vector2(16.8, 15))
	var dest: Array[Vector2] = [Vector2(15.8, 15)]
	assert_bool(MeleeMoves.check_pile_in(a, dest, [a, b], BOARD, [ruin])["ok"]).is_false()
