extends GdUnitTestSuite
## Stealth, Lone Operative and Deadly Demise (core rules 24). Fixtures are invented.


func _shooter() -> UnitState:
	var gun: Dictionary = {"name": "gun", "range": 36, "attacks": "1", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": []}
	return UnitState.from_dict({"name": "Shooter", "models": 1, "base_mm": 25.4, "weapons": [gun]}, "s", 0, Vector2(5, 10))


func _target(abilities: Array, distance: float) -> UnitState:
	var d: Dictionary = {"name": "Target", "models": 1, "base_mm": 25.4, "abilities": abilities}
	return UnitState.from_dict(d, "t", 1, Vector2(5.0 + 1.0 + distance, 10))


func _battle(dice: Dice) -> Battle:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	sc["terrain"] = []
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var b := Battle.new(sc, armies, 1)
	b.dice = dice
	return b


func _bomb(b: Battle, amount: String) -> UnitState:
	var u: UnitState = b.living(1)[0]
	u.deadly_demise = amount
	return u


func _place(u: UnitState, at: Vector2) -> void:
	var shift: Vector2 = at - u.models[0]["pos"]
	for m in u.models:
		m["pos"] += shift


## Kill the unit the way the rules code does, one model at a time.
func _destroy(u: UnitState) -> void:
	while not u.is_destroyed():
		AttackResolver.mortal_wounds(u, 1, Dice.new(1))


func test_stealth_gives_cover_against_ranged_attacks() -> void:
	# Act
	var plan: Array[Dictionary] = Combat.shoot_plan(_shooter(), _target(["STEALTH"], 10.0), [])

	# Assert
	assert_bool(bool(plan[0]["ctx"].get("cover", false))).is_true()


func test_no_stealth_gives_no_cover_on_open_ground() -> void:
	# Act
	var plan: Array[Dictionary] = Combat.shoot_plan(_shooter(), _target([], 10.0), [])

	# Assert
	assert_bool(bool(plan[0]["ctx"].get("cover", false))).is_false()


func test_lone_operative_cannot_be_shot_beyond_twelve_inches() -> void:
	# Act
	var plan: Array[Dictionary] = Combat.shoot_plan(_shooter(), _target(["LONE OPERATIVE"], 13.0), [])

	# Assert
	assert_array(plan).is_empty()


func test_lone_operative_can_be_shot_within_twelve_inches() -> void:
	# Act
	var plan: Array[Dictionary] = Combat.shoot_plan(_shooter(), _target(["LONE OPERATIVE"], 11.0), [])

	# Assert
	assert_int(plan.size()).is_equal(1)


func test_deadly_demise_on_a_six_hurts_units_within_six_inches() -> void:
	# Arrange: scripted roll of 6 for the explosion
	var b: Battle = _battle(Dice.new(1, [6] as Array[int]))
	var bomb: UnitState = _bomb(b, "2")
	var near: UnitState = b.living(0)[2]
	var far: UnitState = b.living(0)[0]
	_place(bomb, Vector2(20, 15))
	_place(near, Vector2(24, 15))
	_place(far, Vector2(2, 2))
	var near_before: int = near.total_wounds_left()
	var far_before: int = far.total_wounds_left()
	_destroy(bomb)

	# Act
	b.remove_destroyed()

	# Assert
	assert_int(near.total_wounds_left()).is_equal(near_before - 2)
	assert_int(far.total_wounds_left()).is_equal(far_before)


func test_deadly_demise_does_nothing_below_a_six() -> void:
	# Arrange
	var b: Battle = _battle(Dice.new(1, [5] as Array[int]))
	var bomb: UnitState = _bomb(b, "2")
	var near: UnitState = b.living(0)[2]
	_place(bomb, Vector2(20, 15))
	_place(near, Vector2(24, 15))
	var before: int = near.total_wounds_left()
	_destroy(bomb)

	# Act
	b.remove_destroyed()

	# Assert
	assert_int(near.total_wounds_left()).is_equal(before)


func test_an_explosion_that_destroys_a_unit_can_set_off_another() -> void:
	# Arrange: both roll a 6, and the first blast kills the second bomb
	var b: Battle = _battle(Dice.new(1, [6, 6] as Array[int]))
	var first: UnitState = _bomb(b, "1")
	var second: UnitState = b.living(1)[1]
	second.deadly_demise = "1"
	var near: UnitState = b.living(0)[2]
	_place(first, Vector2(20, 15))
	_place(second, Vector2(24, 15))
	_place(near, Vector2(32, 15))  # beyond the first blast, within the second
	first.models.resize(1)
	second.models.resize(1)
	second.models[0]["wounds"] = 1
	var before: int = near.total_wounds_left()
	_destroy(first)

	# Act
	b.remove_destroyed()

	# Assert
	assert_bool(second.is_destroyed()).is_true()
	assert_int(near.total_wounds_left()).is_equal(before - 1)
