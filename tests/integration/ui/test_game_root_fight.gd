extends GdUnitTestSuite
## Alternating fight picks through GameRoot's own button handlers, on the human's turn.

const AI := 1
const MISSES := 200

## The placeholder battle at the human's Fight phase, with one unit from each side in combat.
## Every die rolls 1, so all attacks miss and both units are still alive after each pick.
func _engaged_game() -> GameRoot:
	var r: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	r.skip_roster = true
	add_child(r)
	r.settings.reduced_motion = true
	while r.battle.phase() != "fight":
		await r._on_next_pressed()
	var ones: Array[int] = []
	ones.resize(MISSES)
	ones.fill(1)
	r.battle.dice = Dice.new(1, ones)
	var me: UnitState = _mine(r)
	var foe: UnitState = _foe(r)
	var off: Vector2 = me.centre() - foe.centre() + Vector2(30, 0)
	for m in foe.models:
		m["pos"] = m["pos"] + off
	while me.gap_to(foe) > 1.0:
		for m in foe.models:
			m["pos"] = m["pos"] + Vector2(-0.25, 0)
	await r._on_next_pressed()  # pile-in -> fight
	return r

func _mine(r: GameRoot) -> UnitState:
	return r.battle.living(GameRoot.HUMAN)[0]

func _foe(r: GameRoot) -> UnitState:
	return r.battle.living(AI)[0]

func test_ai_takes_its_pick_after_the_human_fights_on_the_human_turn() -> void:
	# Arrange
	var r: GameRoot = await _engaged_game()
	assert_int(r.battle.fight_chooser()).is_equal(GameRoot.HUMAN)
	r._on_unit_tapped(_mine(r))
	r._on_unit_tapped(_foe(r))

	# Act
	await r._on_fight_pressed()

	# Assert
	assert_bool(_foe(r).is_destroyed()).is_false()
	assert_int(r.battle.fight_chooser()).is_not_equal(AI)
	assert_bool(r._busy).is_false()

func test_ai_takes_its_pick_after_the_human_skips_on_the_human_turn() -> void:
	# Arrange
	var r: GameRoot = await _engaged_game()
	r._on_unit_tapped(_mine(r))

	# Act
	await r._on_skip_fight_pressed()

	# Assert
	assert_int(r.battle.fight_chooser()).is_not_equal(AI)
	assert_bool(r._busy).is_false()

func test_end_fighting_moves_on_once_the_ai_has_taken_its_pick() -> void:
	# Arrange
	var r: GameRoot = await _engaged_game()
	r._on_unit_tapped(_mine(r))
	r._on_unit_tapped(_foe(r))
	await r._on_fight_pressed()

	# Act
	await r._on_next_pressed()

	# Assert
	assert_str(r.battle.fight_stage).is_equal("consolidate")
