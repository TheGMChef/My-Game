extends GdUnitTestSuite
## Battle.to_save and Battle.from_save, always through JSON text as the save file does.
## Fixtures are invented.

const TURNS_BEFORE_SAVE := 3
const STEP := Vector2(2, 0)


func _armies() -> Array:
	var gun: Dictionary = {"name": "Test Rifle", "range": 24, "attacks": "2", "skill": 3, "strength": 4, "ap": -1, "damage": "1",
		"abilities": ["RAPID FIRE 1", "ANTI-VEHICLE 4+", "LETHAL HITS: VEHICLE"]}
	var blade: Dictionary = {"name": "Test Blade", "range": 0, "attacks": "3", "skill": 3, "strength": 5, "ap": -2, "damage": "D3", "abilities": []}
	var squad: Dictionary = {"name": "Test Squad", "models": 5, "wounds": 2, "toughness": 4, "save": 3, "invuln": 5, "fnp": 6,
		"move": 6, "oc": 2, "leadership": 6, "base_mm": 32, "keywords": ["INFANTRY"], "faction_keywords": ["TESTERS"],
		"abilities": ["STEALTH"], "faction_abilities": ["REANIMATION PROTOCOLS", "SHADOW IN THE WARP"], "weapons": [gun, blade]}
	var hulk: Dictionary = {"name": "Test Hulk", "models": 1, "wounds": 10, "toughness": 9, "save": 2, "move": 8, "oc": 3,
		"leadership": 7, "base_mm": 80, "keywords": ["VEHICLE"], "deadly_demise": "D3", "weapons": [gun]}
	return [{"name": "First", "units": [squad, hulk, squad]}, {"name": "Second", "units": [hulk, squad, squad]}]


func _battle(seed_value: int = 7) -> Battle:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	return Battle.new(sc, _armies(), seed_value)


## The file's trip: stringify with full precision, parse, rebuild.
func _reloaded(b: Battle) -> Battle:
	return Battle.from_save(JSON.parse_string(JSON.stringify(b.to_save(), "", true, true)))


## Save data as JSON would hand it back, so an int and the same float compare equal.
func _normal(b: Battle) -> Dictionary:
	return JSON.parse_string(JSON.stringify(b.to_save(), "", true, true))


func _shifted(u: UnitState, d: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"] + d)
	return out


func _to_phase(b: Battle, wanted: String) -> void:
	var guard: int = 0
	while b.phase() != wanted and guard < 10:
		guard += 1
		b.next_phase()


func test_a_fresh_battle_survives_the_round_trip_unchanged() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_dict(_normal(copy)).is_equal(_normal(b))


func test_mid_battle_state_survives_the_round_trip_unchanged() -> void:
	# Arrange
	var b := _battle()
	for i in range(TURNS_BEFORE_SAVE):
		b.play_turn()
	b.begin_turn()

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_dict(_normal(copy)).is_equal(_normal(b))


func test_a_resumed_game_plays_on_exactly_like_the_original() -> void:
	# Arrange: both sides AI, part way through
	var b := _battle()
	for i in range(TURNS_BEFORE_SAVE):
		b.play_turn()
	var copy: Battle = _reloaded(b)

	# Act
	b.play_all()
	copy.play_all()

	# Assert
	assert_array(copy.vp).is_equal(b.vp)
	assert_int(copy.events.size()).is_equal(b.events.size())
	assert_dict(_normal(copy)).is_equal(_normal(b))


func test_dice_carry_on_with_the_same_rolls() -> void:
	# Arrange
	var dice := Dice.new(1234)
	dice.roll_many(5)
	var copy: Dice = Dice.from_save(JSON.parse_string(JSON.stringify(dice.to_save())))

	# Act and assert
	assert_array(copy.roll_many(20)).is_equal(dice.roll_many(20))
	assert_int(copy.rolls_made).is_equal(dice.rolls_made)


func test_scripted_dice_carry_on_from_where_they_were() -> void:
	# Arrange
	var scripted: Array[int] = [1, 2, 3]
	var dice := Dice.new(1, scripted)
	dice.d6()

	# Act
	var copy: Dice = Dice.from_save(dice.to_save())

	# Assert
	assert_int(copy.scripted_left()).is_equal(2)
	assert_int(copy.d6()).is_equal(2)


func test_model_state_and_flags_are_kept() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	var u: UnitState = b.living(0)[0]
	u.models.remove_at(1)
	u.models[0]["wounds"] = 1
	u.models[1]["pos"] = Vector2(10.123456, 7.654321)
	u.battle_shocked = true
	u.advanced = true
	u.fell_back = true
	u.charged = true
	u.last_fired_turn = 3
	u.max_model_move = 4.5
	u.last_position = Vector2(3, 4)
	var names: Array[String] = ["Test Rifle"]
	u.one_shot_used = names

	# Act
	var v: UnitState = _reloaded(b).unit_by_id(u.id)

	# Assert
	assert_int(v.model_count()).is_equal(4)
	assert_int(v.models[0]["wounds"]).is_equal(1)
	assert_vector(v.models[1]["pos"]).is_equal(u.models[1]["pos"])
	assert_bool(v.battle_shocked and v.advanced and v.fell_back and v.charged).is_true()
	assert_int(v.last_fired_turn).is_equal(3)
	assert_float(v.max_model_move).is_equal(4.5)
	assert_vector(v.last_position).is_equal(Vector2(3, 4))
	assert_array(v.one_shot_used).is_equal(names)
	assert_int(v.starting_strength).is_equal(5)


func test_parsed_weapon_abilities_are_kept() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	var w: Weapon = b.living(0)[0].weapons[0]

	# Act
	var v: Weapon = _reloaded(b).living(0)[0].weapons[0]

	# Assert
	assert_str(v.weapon_name).is_equal("Test Rifle")
	assert_int(v.ability("RAPID FIRE")["value"]).is_equal(1)
	assert_int(v.ability("ANTI", ["VEHICLE"])["threshold"]).is_equal(4)
	assert_bool(v.has("LETHAL HITS", ["VEHICLE"])).is_true()
	assert_bool(v.has("LETHAL HITS", ["INFANTRY"])).is_false()
	assert_int(v.ap).is_equal(w.ap)


func test_scores_points_and_flow_are_kept() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	b.vp = [4, 9]
	b.flow.command_points = [2, 5]

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_array(copy.vp).is_equal([4, 9])
	assert_array(copy.flow.command_points).is_equal([2, 5])
	assert_str(copy.phase()).is_equal("movement")
	assert_int(copy.active_player()).is_equal(b.active_player())
	assert_int(copy.turn_no).is_equal(b.turn_no)


func test_units_that_acted_this_phase_stay_marked() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var mover: UnitState = b.living(0)[0]
	var holder: UnitState = b.living(0)[1]
	b.cmd_move(mover, _shifted(mover, STEP), "normal")
	b.cmd_hold(holder)

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_bool(copy.has_moved(copy.unit_by_id(mover.id))).is_true()
	assert_bool(copy.has_moved(copy.unit_by_id(holder.id))).is_true()
	assert_bool(copy.has_moved(copy.living(0)[2])).is_false()


func test_a_pending_undo_survives_the_round_trip() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var mover: UnitState = b.living(0)[0]
	var start: Vector2 = mover.models[0]["pos"]
	b.cmd_move(mover, _shifted(mover, STEP), "normal")

	# Act
	var copy: Battle = _reloaded(b)
	var r: Dictionary = copy.cmd_undo_move()

	# Assert
	assert_bool(r["ok"]).is_true()
	assert_vector(copy.unit_by_id(mover.id).models[0]["pos"]).is_equal(start)


func test_army_rule_state_is_kept() -> void:
	# Arrange
	var b := _battle()
	b.ai_sides = [false, true]
	b.begin_turn()
	b.cmd_shadow_in_the_warp(0)
	b.reanimate_models = false

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_bool(copy.can_unleash_shadow(0)).is_false()
	assert_bool(copy.can_unleash_shadow(1)).is_true()
	assert_bool(copy.reanimate_models).is_false()
	assert_array(copy.ai_sides).is_equal([false, true])


func test_a_fight_in_progress_is_kept() -> void:
	# Arrange: two units in combat, part way through the fight step
	var b := _battle()
	b.ai_sides = [false, false]
	b.begin_turn()
	_to_phase(b, "fight")
	var mine: UnitState = b.living(0)[0]
	var foe: UnitState = b.living(1)[1]
	var off: Vector2 = mine.centre() + Vector2(4, 0) - foe.centre()
	for m in foe.models:
		m["pos"] += off
	while mine.gap_to(foe) > 1.0:
		for m in foe.models:
			m["pos"] += Vector2(-0.1, 0)
	b.next_phase()    # pile-in -> fight
	assert_int(b.fight_chooser()).is_equal(0)
	b.cmd_fight_skip(mine)

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_int(copy.fight_chooser()).is_equal(b.fight_chooser())
	assert_array(copy.fight_options().map(func(u: UnitState) -> String: return u.id)) \
			.is_equal(b.fight_options().map(func(u: UnitState) -> String: return u.id))
	assert_str(copy.fight_stage).is_equal("fight")
	assert_dict(_normal(copy)).is_equal(_normal(b))


func test_names_of_destroyed_units_stay_for_the_log() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	var gone: UnitState = b.living(0)[0]
	gone.models.clear()
	b.remove_destroyed()

	# Act
	var copy: Battle = _reloaded(b)

	# Assert
	assert_object(copy.unit_by_id(gone.id)).is_null()
	assert_str(str(copy.unit_names[gone.id])).is_equal("Test Squad")


func test_moves_in_the_event_list_come_back_as_vectors() -> void:
	# Arrange
	var b := _battle()
	b.begin_turn()
	b.next_phase()
	var u: UnitState = b.living(0)[0]
	var dest: Array[Vector2] = _shifted(u, STEP)
	b.cmd_move(u, dest, "normal")

	# Act
	var moved: Dictionary = _reloaded(b).events.filter(func(e: Dictionary) -> bool: return e["type"] == "move")[0]

	# Assert
	assert_array(moved["to"]).is_equal(dest)
	assert_int(moved["side"]).is_equal(0)


func test_an_unknown_save_version_is_refused() -> void:
	# Arrange
	var data: Dictionary = _battle().to_save()
	data["version"] = Battle.SAVE_VERSION + 1

	# Act and assert
	assert_object(Battle.from_save(data)).is_null()


func test_a_save_with_missing_parts_is_refused() -> void:
	# Arrange
	var data: Dictionary = _battle().to_save()
	data.erase("units")

	# Act and assert
	assert_object(Battle.from_save(data)).is_null()
