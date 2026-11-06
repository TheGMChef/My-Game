extends GdUnitTestSuite
## The battle screen's action specs and side panel data, read from the real controller.


func _game() -> GameRoot:
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_roster = true
	add_child(r)
	r.settings.reduced_motion = true
	return r


func _to_phase(r: GameRoot, phase: String) -> void:
	while r.battle.phase() != phase:
		await r._on_next_pressed()


func _mains(specs: Array[Dictionary]) -> Array[Dictionary]:
	return specs.filter(func(s: Dictionary) -> bool: return s.get("role", "") == "main")


func test_no_action_is_offered_as_main_before_a_unit_is_selected() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	var specs: Array[Dictionary] = r._action_specs()

	# Assert
	assert_int(_mains(specs).size()).is_equal(0)


func test_each_phase_offers_at_most_one_main_action() -> void:
	# Arrange
	var r: GameRoot = _game()
	var me: UnitState = r.battle.living(GameRoot.HUMAN)[0]

	for phase in ["movement", "shooting", "charge"]:
		await _to_phase(r, phase)
		r._on_unit_tapped(me)

		# Act
		var specs: Array[Dictionary] = r._action_specs()

		# Assert
		assert_int(_mains(specs).size()).is_less_equal(1)


func test_odds_card_shows_nothing_until_a_target_is_chosen() -> void:
	# Arrange
	var r: GameRoot = _game()
	await _to_phase(r, "shooting")
	r._on_unit_tapped(r.battle.living(GameRoot.HUMAN)[0])

	# Act
	var view: Dictionary = r._odds_view()

	# Assert
	assert_dict(view).is_empty()


func test_odds_card_totals_match_the_battle_preview() -> void:
	# Arrange: put an enemy where the first unit can see and reach it
	var r: GameRoot = _game()
	await _to_phase(r, "shooting")
	var me: UnitState = r.battle.living(GameRoot.HUMAN)[0]
	var foe: UnitState = r.battle.living(1)[0]
	var off: Vector2 = me.centre() + Vector2(10, 0) - foe.centre()
	for m in foe.models:
		m["pos"] = m["pos"] + off
	r._on_unit_tapped(me)
	r._on_unit_tapped(foe)
	var expected: float = 0.0
	for p in r.battle.shoot_preview(me, foe):
		expected += float(p["odds"]["expected_damage"])

	# Act
	var view: Dictionary = r._odds_view()

	# Assert
	assert_float(float(view["total"])).is_equal_approx(expected, 0.001)
	assert_int((view["rows"] as Array).size()).is_greater(0)


func test_unit_view_carries_the_six_datasheet_stats() -> void:
	# Arrange
	var r: GameRoot = _game()

	# Act
	var view: Dictionary = r._unit_view(r.battle.living(GameRoot.HUMAN)[0])

	# Assert
	assert_int((view["tiles"] as Array).size()).is_equal(6)


func test_title_screen_comes_first_and_leads_to_the_roster() -> void:
	# Arrange
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.persist = false
	r.placeholder_only = true
	add_child(r)
	var title: TitleScreen = null
	for c in r.get_children():
		if c is TitleScreen:
			title = c

	# Act
	title.start_pressed.emit()

	# Assert
	assert_object(r._roster).is_not_null()
