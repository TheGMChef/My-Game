extends GdUnitTestSuite
## Unit name plates stay readable: no overlaps, and never off the board.

const BOUNDS := Rect2(0, 0, 400, 300)
const PLATE := Vector2(100, 22)


func _entry(anchor: Rect2, first: bool = false) -> Dictionary:
	return {"size": PLATE, "anchor": anchor, "first": first}


func test_single_plate_sits_above_its_unit() -> void:
	# Arrange
	var unit := Rect2(150, 100, 40, 40)

	# Act
	var spots: Array[Rect2] = PlateLayout.arrange([_entry(unit)], BOUNDS)

	# Assert
	assert_float(spots[0].end.y).is_less_equal(unit.position.y)


func test_plate_for_a_unit_at_the_edge_stays_on_the_board() -> void:
	# Arrange
	var corner_units: Array = [_entry(Rect2(-10, -10, 30, 30)), _entry(Rect2(380, 280, 30, 30))]

	# Act
	var spots: Array[Rect2] = PlateLayout.arrange(corner_units, BOUNDS)

	# Assert
	for s in spots:
		assert_bool(BOUNDS.encloses(s)).is_true()


func test_plates_for_units_side_by_side_do_not_overlap() -> void:
	# Arrange
	var crowd: Array = []
	for i in range(6):
		crowd.append(_entry(Rect2(150 + i * 12, 140, 20, 20)))

	# Act
	var spots: Array[Rect2] = PlateLayout.arrange(crowd, BOUNDS)

	# Assert
	for i in range(spots.size()):
		for j in range(i + 1, spots.size()):
			assert_bool(spots[i].intersects(spots[j])).is_false()


func test_selected_unit_keeps_the_spot_above_it() -> void:
	# Arrange
	var other := _entry(Rect2(150, 100, 40, 40))
	var chosen := _entry(Rect2(160, 100, 40, 40), true)

	# Act
	var spots: Array[Rect2] = PlateLayout.arrange([other, chosen], BOUNDS)

	# Assert
	assert_float(spots[1].end.y).is_less_equal(100.0)
	assert_float(spots[1].position.x).is_equal_approx(130.0, 0.01)


func test_order_of_results_matches_order_of_entries() -> void:
	# Arrange
	var left := _entry(Rect2(40, 100, 20, 20))
	var right := _entry(Rect2(300, 100, 20, 20), true)

	# Act
	var spots: Array[Rect2] = PlateLayout.arrange([left, right], BOUNDS)

	# Assert
	assert_float(spots[0].position.x).is_less(spots[1].position.x)


func test_a_plate_stays_out_of_a_keep_clear_area() -> void:
	# Arrange: the spot above the unit is taken by the board tools
	var bounds := Rect2(0, 0, 400, 400)
	var entry: Dictionary = {"size": Vector2(100, 22), "anchor": Rect2(150, 150, 40, 40), "first": false}
	var tools: Array[Rect2] = [Rect2(100, 100, 150, 50)]

	# Act
	var spot: Rect2 = PlateLayout.arrange([entry], bounds, tools)[0]

	# Assert
	assert_bool(spot.intersects(tools[0])).is_false()
