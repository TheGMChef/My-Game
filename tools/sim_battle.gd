extends SceneTree
## Headless sample: godot --headless --path . -s tools/sim_battle.gd -- <seed> [<seed> ...]

func _init() -> void:
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	var armies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/armies_placeholder.json"))["armies"]
	var seeds: PackedStringArray = OS.get_cmdline_user_args()
	if seeds.is_empty():
		seeds = PackedStringArray(["1", "2", "3"])
	for s in seeds:
		var b := Battle.new(sc, armies, int(s))
		var r: Dictionary = b.play_all()
		print("seed %s -> VP %s survivors %s" % [s, r["vp"], r["survivors"]])
		if seeds.size() == 1:
			for line in b.log:
				print("  ", line)
			for u in b.units:
				print("  ", u.unit_name, " side ", u.owner, " models ", u.model_count(), " at ", u.centre())
	quit()
