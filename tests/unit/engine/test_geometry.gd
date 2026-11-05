extends GdUnitTestSuite

func test_edge_distance_between_bases() -> void:
	assert_float(Geo.edge_distance(Vector2(0, 0), 0.5, Vector2(5, 0), 0.5)).is_equal(4.0)

func test_edge_distance_never_negative_when_overlapping() -> void:
	assert_float(Geo.edge_distance(Vector2(0, 0), 1.0, Vector2(1, 0), 1.0)).is_equal(0.0)

func test_segment_through_circle_hits() -> void:
	assert_bool(Geo.segment_hits_circle(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0.5), 1.0)).is_true()

func test_segment_beside_circle_misses() -> void:
	assert_bool(Geo.segment_hits_circle(Vector2(0, 0), Vector2(10, 0), Vector2(5, 3), 1.0)).is_false()

func test_segment_crossing_rect_hits_even_with_both_ends_outside() -> void:
	assert_bool(Geo.segment_hits_rect(Vector2(0, 5), Vector2(10, 5), Rect2(4, 0, 2, 10))).is_true()

func test_segment_beside_rect_misses() -> void:
	assert_bool(Geo.segment_hits_rect(Vector2(0, 12), Vector2(10, 12), Rect2(4, 0, 2, 10))).is_false()

func test_circle_overlap_with_rect() -> void:
	assert_bool(Geo.circle_overlaps_rect(Vector2(7, 5), 1.5, Rect2(4, 0, 2, 10))).is_true()
	assert_bool(Geo.circle_overlaps_rect(Vector2(9, 5), 1.5, Rect2(4, 0, 2, 10))).is_false()
