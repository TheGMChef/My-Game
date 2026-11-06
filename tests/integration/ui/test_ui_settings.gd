extends GdUnitTestSuite
## UISettings on disk, in a throwaway file. The player's own settings are never touched.

const PATH := "user://test_settings_only.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(PATH)


func test_every_setting_survives_a_save_and_load() -> void:
	# Arrange
	var a := UISettings.new()
	a.text_scale_index = 3
	a.colour_blind = true
	a.reduced_motion = true
	a.show_engagement = false
	a.show_coherency = true
	a.show_objectives = false
	a.show_plates = false
	a.ai_speed_index = 3
	a.confirm_end_phase = false
	a.reanimate_models = false

	# Act
	a.save_to_disk(PATH)
	var b := UISettings.new()
	b.load_from_disk(PATH)

	# Assert
	assert_int(b.text_scale_index).is_equal(3)
	assert_bool(b.colour_blind).is_true()
	assert_bool(b.reduced_motion).is_true()
	assert_bool(b.show_engagement).is_false()
	assert_bool(b.show_coherency).is_true()
	assert_bool(b.show_objectives).is_false()
	assert_bool(b.show_plates).is_false()
	assert_int(b.ai_speed_index).is_equal(3)
	assert_bool(b.confirm_end_phase).is_false()
	assert_bool(b.reanimate_models).is_false()


func test_an_older_settings_file_still_loads_with_defaults_for_new_settings() -> void:
	# Arrange: exactly what the first version wrote
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", 2)
	cfg.set_value("ui", "colour_blind", true)
	cfg.set_value("ui", "reduced_motion", false)
	cfg.set_value("overlays", "engagement", false)
	cfg.set_value("overlays", "coherency", true)
	cfg.set_value("overlays", "objectives", true)
	cfg.save(PATH)

	# Act
	var s := UISettings.new()
	s.load_from_disk(PATH)

	# Assert: old values kept, new ones at their defaults
	assert_int(s.text_scale_index).is_equal(2)
	assert_bool(s.colour_blind).is_true()
	assert_bool(s.show_engagement).is_false()
	assert_bool(s.show_coherency).is_true()
	assert_bool(s.show_plates).is_true()
	assert_int(s.ai_speed_index).is_equal(UISettings.AI_SPEED_NORMAL)
	assert_bool(s.confirm_end_phase).is_true()
	assert_bool(s.reanimate_models).is_true()


func test_the_older_keys_keep_their_names_for_older_builds() -> void:
	# Arrange
	var s := UISettings.new()
	s.show_coherency = true

	# Act
	s.save_to_disk(PATH)
	var cfg := ConfigFile.new()
	cfg.load(PATH)

	# Assert
	assert_bool(bool(cfg.get_value("overlays", "coherency", false))).is_true()
	assert_int(int(cfg.get_value("ui", "text_scale_index", -1))).is_equal(1)


func test_values_out_of_range_are_pulled_back() -> void:
	# Arrange
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", 99)
	cfg.set_value("gameplay", "ai_speed", -4)
	cfg.save(PATH)

	# Act
	var s := UISettings.new()
	s.load_from_disk(PATH)

	# Assert
	assert_int(s.text_scale_index).is_equal(UISettings.TEXT_SCALES.size() - 1)
	assert_int(s.ai_speed_index).is_equal(0)


func test_a_missing_file_keeps_the_defaults() -> void:
	# Act
	var s := UISettings.new()
	s.load_from_disk(PATH)

	# Assert
	assert_bool(s.reanimate_models).is_true()
	assert_int(s.ai_speed_index).is_equal(UISettings.AI_SPEED_NORMAL)


func test_instant_ai_speed_means_no_animation_time() -> void:
	# Arrange
	var s := UISettings.new()
	s.ai_speed_index = UISettings.AI_SPEED_NAMES.find("instant")

	# Act and assert
	assert_float(s.ai_speed()).is_equal(0.0)
