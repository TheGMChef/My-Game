extends GdUnitTestSuite

func _load(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _battle(seed_value: int) -> Battle:
	var sc: Dictionary = _load("res://assets/data/scenario_clash_of_patrols.json")
	var armies: Array = _load("res://assets/data/armies_placeholder.json")["armies"]
	return Battle.new(sc, armies, seed_value)

func test_both_armies_deploy_inside_their_zones_and_in_coherency() -> void:
	var b := _battle(1)
	assert_int(b.living(0).size()).is_equal(3)
	assert_int(b.living(1).size()).is_equal(3)
	for u in b.units:
		var positions: Array[Vector2] = []
		for m in u.models:
			positions.append(m["pos"])
			assert_bool(b.board.has_point(m["pos"])).is_true()
		assert_bool(UnitRules.in_coherency(positions, u.base_radius)).is_true()
		var half: float = b.board.size.x / 2.0
		for p in positions:
			assert_bool((p.x < half) == (u.owner == 0)).is_true()

func test_a_full_battle_runs_to_the_end_without_errors() -> void:
	var b := _battle(7)
	var result: Dictionary = b.play_all()
	assert_bool(b.is_over()).is_true()
	assert_int(result["rounds"]).is_between(1, 5)

func test_same_seed_gives_the_same_battle() -> void:
	var r1: Dictionary = _battle(11).play_all()
	var r2: Dictionary = _battle(11).play_all()
	assert_array(r1["vp"]).is_equal(r2["vp"])
	assert_array(r1["survivors"]).is_equal(r2["survivors"])

func test_units_never_end_a_turn_outside_the_battlefield() -> void:
	var b := _battle(3)
	b.play_all()
	for u in b.units:
		for m in u.models:
			assert_bool(b.board.has_point(m["pos"])).is_true()

func test_vp_never_exceeds_the_cap_over_five_rounds() -> void:
	var b := _battle(5)
	var r: Dictionary = b.play_all()
	# 4 scoring rounds x 15 VP is the most a player could score under the placeholder rules
	assert_int(r["vp"][0]).is_less_equal(60)
	assert_int(r["vp"][1]).is_less_equal(60)
