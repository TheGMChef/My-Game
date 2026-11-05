extends GdUnitTestSuite
## Whole games played through the real interface must reach a result.

const SEEDS: Array[int] = [11, 12, 13]


func _play(seed_value: int) -> Dictionary:
	var game: GameRoot = auto_free(load("res://scenes/main.tscn").instantiate())
	game.skip_roster = true
	game.battle_seed = seed_value
	add_child(game)
	game.settings.reduced_motion = true
	return await PlaytestBot.new(game, seed_value).play()


func test_full_games_reach_a_result_through_the_interface() -> void:
	for seed_value in SEEDS:
		# Act
		var result: Dictionary = await _play(seed_value)

		# Assert
		assert_str(result["outcome"]).is_equal("finished")


func test_bot_uses_every_phase() -> void:
	# Act
	var result: Dictionary = await _play(SEEDS[0])

	# Assert
	var actions: Dictionary = result["actions"]
	for kind in ["move", "shoot", "charge_roll"]:
		assert_bool(actions.has(kind)).is_true()


func test_same_seed_plays_the_same_game() -> void:
	# Act
	var first: Dictionary = await _play(SEEDS[0])
	var second: Dictionary = await _play(SEEDS[0])

	# Assert
	assert_array(first["vp"]).is_equal(second["vp"])
	assert_int(first["steps"]).is_equal(second["steps"])
