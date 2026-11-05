extends GdUnitTestSuite

func test_scripted_dice_return_values_in_order() -> void:
	var d := Dice.new(1, [3, 5, 2] as Array[int])
	assert_int(d.d6()).is_equal(3)
	assert_int(d.d6()).is_equal(5)
	assert_int(d.scripted_left()).is_equal(1)

func test_same_seed_gives_same_rolls() -> void:
	var a := Dice.new(42)
	var b := Dice.new(42)
	for i in range(20):
		assert_int(a.d6()).is_equal(b.d6())

func test_random_rolls_stay_within_one_to_six() -> void:
	var d := Dice.new(7)
	for i in range(500):
		assert_int(d.d6()).is_between(1, 6)

func test_expression_2d6_plus_1_adds_dice_and_bonus() -> void:
	var d := Dice.new(1, [4, 5] as Array[int])
	assert_int(d.roll("2D6+1")).is_equal(10)

func test_d3_is_a_halved_d6_rounded_up() -> void:
	var d := Dice.new(1, [1, 2, 3, 4, 5, 6] as Array[int])
	var got: Array[int] = []
	for i in range(6):
		got.append(d.roll("D3"))
	assert_array(got).is_equal([1, 1, 2, 2, 3, 3])

func test_plain_number_rolls_no_dice() -> void:
	var d := Dice.new(1)
	assert_int(d.roll("3")).is_equal(3)
	assert_int(d.rolls_made).is_equal(0)

func test_validity_and_average() -> void:
	assert_bool(Dice.is_valid("D6+1")).is_true()
	assert_bool(Dice.is_valid("D4")).is_false()
	assert_bool(Dice.is_valid("")).is_false()
	assert_float(Dice.average("D6")).is_equal(3.5)
	assert_float(Dice.average("D3")).is_equal(2.0)
	assert_float(Dice.average("2D6+1")).is_equal(8.0)
