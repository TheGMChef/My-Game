extends GdUnitTestSuite
## Every UIText.t("key") used in src/ui must exist in the string table.

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


func test_all_used_keys_exist() -> void:
	var rx := RegEx.new()
	rx.compile("UIText\\.t\\(\"([a-z_.]+)\"")
	var missing: Array[String] = []
	for path in _scripts("res://src/ui"):
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			var k: String = m.get_string(1)
			if not k.ends_with(".") and not UIText.has_key(k):
				missing.append(k)
	assert_array(missing).is_empty()


func test_dynamic_prefix_keys_exist() -> void:
	for p in ["command", "movement", "shooting", "charge", "fight"]:
		assert_bool(UIText.has_key("phase." + p)).is_true()
		assert_bool(UIText.has_key("next." + p)).is_true()
	for s in ["command", "movement", "shooting", "charge", "fight_pile_in", "fight_fight", "fight_consolidate"]:
		assert_bool(UIText.has_key("help.title." + s)).is_true()
		assert_bool(UIText.has_key("help.body." + s)).is_true()
	for m in ["normal", "advance", "fall_back"]:
		assert_bool(UIText.has_key("log.move." + m)).is_true()
