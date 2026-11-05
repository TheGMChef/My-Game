extends GdUnitTestSuite

func test_test_framework_runs() -> void:
	assert_int(1 + 1).is_equal(2)
