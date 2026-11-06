extends GdUnitTestSuite
## The ruler's sums: plain inches between two board points.

const VIEW := Rect2(0, 0, 800, 600)
const BOX := Vector2(60, 28)
const GAP := 10.0


func test_inches_is_the_straight_line_distance() -> void:
	# Act and assert: a 3-4-5 triangle
	assert_float(Ruler.inches(Vector2(1, 1), Vector2(4, 5))).is_equal_approx(5.0, 0.0001)


func test_inches_between_the_same_point_is_zero() -> void:
	assert_float(Ruler.inches(Vector2(3, 3), Vector2(3, 3))).is_equal(0.0)


func test_label_shows_one_decimal_and_the_inch_mark() -> void:
	# Act and assert
	assert_str(Ruler.label(Vector2.ZERO, Vector2(12.34, 0))).is_equal("12.3\"")
	assert_str(Ruler.label(Vector2.ZERO, Vector2(6, 0))).is_equal("6.0\"")


func test_a_start_on_a_model_snaps_to_its_centre() -> void:
	# Arrange
	var models: Array = [{"pos": Vector2(10, 10), "radius": 1.0}]

	# Act and assert
	assert_vector(Ruler.start_point(Vector2(10.5, 10.5), models)).is_equal(Vector2(10, 10))


func test_a_start_off_any_model_stays_where_it_is() -> void:
	# Arrange
	var models: Array = [{"pos": Vector2(10, 10), "radius": 1.0}]

	# Act and assert
	assert_vector(Ruler.start_point(Vector2(20, 20), models)).is_equal(Vector2(20, 20))


func test_overlapping_bases_pick_the_nearest_centre() -> void:
	# Arrange
	var models: Array = [{"pos": Vector2(10, 10), "radius": 2.0}, {"pos": Vector2(12, 10), "radius": 2.0}]

	# Act and assert
	assert_vector(Ruler.start_point(Vector2(11.5, 10), models)).is_equal(Vector2(12, 10))


func test_the_label_sits_near_the_midpoint_without_covering_the_line() -> void:
	# Act
	var rect: Rect2 = Ruler.label_rect(Vector2(100, 300), Vector2(500, 300), BOX, GAP, VIEW)

	# Assert
	assert_float(rect.get_center().x).is_equal_approx(300.0, 0.01)
	assert_bool(rect.end.y < 300.0).is_true()


func test_the_label_stays_on_screen_at_the_edge() -> void:
	# Act
	var rect: Rect2 = Ruler.label_rect(Vector2(0, 2), Vector2(4, 2), BOX, GAP, VIEW)

	# Assert
	assert_bool(VIEW.encloses(rect)).is_true()
