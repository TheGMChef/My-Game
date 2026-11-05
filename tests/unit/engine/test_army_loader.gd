extends GdUnitTestSuite
## ArmyLoader reads user-supplied army JSON; fixtures here are invented.

const JSON_OK := '{"armies":[{"name":"Test Host","units":[{"name":"Grunts","models_min":5,"models_max":10,"wounds":1,"keywords":["INFANTRY"]}]}]}'


func test_parses_armies() -> void:
	var armies := ArmyLoader.parse_text(JSON_OK, "fixture")
	assert_int(armies.size()).is_equal(1)
	assert_str(armies[0]["name"]).is_equal("Test Host")
	assert_str(armies[0]["source"]).is_equal("fixture")


func test_bad_json_gives_nothing() -> void:
	assert_array(ArmyLoader.parse_text("not json")).is_empty()
	assert_array(ArmyLoader.parse_text('{"armies":[{"name":"x"}]}')).is_empty()


func test_prepare_clamps_models_and_guesses_base() -> void:
	var unit: Dictionary = ArmyLoader.parse_text(JSON_OK)[0]["units"][0]
	assert_int(ArmyLoader.prepare_unit(unit, 99)["models"]).is_equal(10)
	assert_int(ArmyLoader.prepare_unit(unit, 1)["models"]).is_equal(5)
	assert_float(ArmyLoader.prepare_unit(unit, 5)["base_mm"]).is_equal(32.0)


func test_prepare_keeps_explicit_base() -> void:
	var u := {"name": "x", "models": 1, "base_mm": 50}
	assert_float(ArmyLoader.prepare_unit(u, 1)["base_mm"]).is_equal(50.0)


func test_big_vehicle_gets_big_base() -> void:
	assert_float(ArmyLoader.guess_base_mm({"keywords": ["VEHICLE"], "wounds": 18})).is_equal(100.0)
	assert_float(ArmyLoader.guess_base_mm({"keywords": ["VEHICLE"], "wounds": 10})).is_equal(60.0)
