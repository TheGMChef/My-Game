extends GdUnitTestSuite
## RosterScreen builds the two army dictionaries Battle needs. Fixtures are invented.

const FIXTURE := '{"armies":[{"name":"Test Host","units":[{"name":"Grunts","models_min":5,"models_max":10,"wounds":1,"toughness":3,"save":5,"move":6,"weapons":[]},{"name":"Boss","models":1,"wounds":6}]}]}'


func _screen() -> RosterScreen:
	var rs: RosterScreen = auto_free(RosterScreen.new())
	add_child(rs)
	rs.setup()
	rs._import_text(FIXTURE, "test.json", false)
	return rs


func test_start_is_disabled_until_both_sides_have_units() -> void:
	var rs := _screen()
	var idx: int = rs._armies.size() - 1
	rs._set_army(0, idx)
	rs._set_army(1, idx)
	assert_bool(rs._start.disabled).is_true()
	rs._add_pick(0, 0)
	assert_bool(rs._start.disabled).is_true()
	rs._add_pick(1, 1)
	assert_bool(rs._start.disabled).is_false()


func test_started_carries_prepared_units() -> void:
	var rs := _screen()
	var idx: int = rs._armies.size() - 1
	rs._set_army(0, idx)
	rs._set_army(1, idx)
	rs._add_pick(0, 0)
	rs._add_pick(1, 1)
	rs._sides[0]["picks"][0]["models"] = 8
	var got: Array = []
	rs.started.connect(func(a: Array) -> void: got.append(a))
	rs._on_start()
	assert_int(got.size()).is_equal(1)
	var mine: Dictionary = got[0][0]["units"][0]
	assert_int(mine["models"]).is_equal(8)
	assert_float(mine["base_mm"]).is_greater(0.0)
	assert_str(got[0][1]["units"][0]["name"]).is_equal("Boss")


func test_unit_cap_per_side() -> void:
	var rs := _screen()
	var idx: int = rs._armies.size() - 1
	rs._set_army(0, idx)
	for i in range(RosterScreen.MAX_UNITS + 3):
		rs._add_pick(0, 1)
	assert_int((rs._sides[0]["picks"] as Array).size()).is_equal(RosterScreen.MAX_UNITS)


func test_bad_file_reports_failure_and_adds_nothing() -> void:
	var rs := _screen()
	var before: int = rs._armies.size()
	rs._import_text("garbage", "bad.json", false)
	assert_int(rs._armies.size()).is_equal(before)
	assert_str(rs._status.text).contains("bad.json")


func test_default_armies_with_only_placeholders_are_distinct_and_valid() -> void:
	var rs: RosterScreen = auto_free(RosterScreen.new())
	rs._armies = [
		{"name": "A", "units": [{"name": "a1"}], "source": "res://assets/data/armies_placeholder.json"},
		{"name": "B", "units": [{"name": "b1"}], "source": "res://assets/data/armies_placeholder.json"}]
	assert_int(rs._default_army_for(0)).is_equal(0)
	assert_int(rs._default_army_for(1)).is_equal(1)


func test_default_armies_prefer_user_files() -> void:
	var rs: RosterScreen = auto_free(RosterScreen.new())
	rs._armies = [
		{"name": "P", "units": [], "source": "res://assets/data/armies_placeholder.json"},
		{"name": "U1", "units": [], "source": "user://armies/a.json"},
		{"name": "U2", "units": [], "source": "user://armies/b.json"}]
	assert_int(rs._default_army_for(0)).is_equal(1)
	assert_int(rs._default_army_for(1)).is_equal(2)
