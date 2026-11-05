extends GdUnitTestSuite
## Icons are drawn from vector shapes, so none can fall back to a missing-character box.

const INK := Color.WHITE


func test_every_icon_builds_at_the_size_asked_for() -> void:
	for icon_name in UIIcons.SHAPES:
		# Act
		var tex: Texture2D = UIIcons.get_icon(icon_name, INK, 20)

		# Assert
		assert_vector(tex.get_size()).is_equal(Vector2(20, 20))


func test_stripe_mark_keeps_its_wide_shape() -> void:
	# Act
	var tex: Texture2D = UIIcons.stripe(INK)

	# Assert
	assert_vector(tex.get_size()).is_equal(Vector2(26, 12))


func test_same_icon_and_colour_reuse_one_texture() -> void:
	# Act
	var first: Texture2D = UIIcons.get_icon("plus", INK, 24)
	var second: Texture2D = UIIcons.get_icon("plus", INK, 24)

	# Assert
	assert_object(first).is_same(second)


func test_no_ui_script_uses_a_font_glyph_as_an_icon() -> void:
	# Arrange: the home symbol showed as a missing-character box on tablets
	var banned: Array[String] = ["⌂", "⚙", "✕", "✓", "☰"]

	# Act
	var found: Array[String] = []
	for f in DirAccess.get_files_at("res://src/ui"):
		if f.ends_with(".gd"):
			var text: String = FileAccess.get_file_as_string("res://src/ui".path_join(f))
			for glyph in banned:
				if text.contains(glyph):
					found.append(f + " " + glyph)

	# Assert
	assert_array(found).is_empty()
