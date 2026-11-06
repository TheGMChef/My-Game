extends SceneTree
## Plays whole games through the real interface and reports any that go wrong.
## Run: godot --headless --path . -s tools/playtest.gd -- [games] [first_seed] [real]
## With real, each game uses a random 6-unit roster from two different data/local armies.
## Exits 1 if any game fails, so CI can use it. Each failure prints its seed and last actions.

var last_rosters: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var games: int = int(args[0]) if args.size() > 0 else 20
	var first: int = int(args[1]) if args.size() > 1 else 1
	var failures: int = 0
	var counts: Dictionary = {}
	var totals: Array[int] = [0, 0]
	var wins: Array[int] = [0, 0, 0]
	var actions: Dictionary = {}
	var stratagems: Dictionary = {}
	var prompts: int = 0
	var started: int = Time.get_ticks_msec()
	for i in range(games):
		var seed_value: int = first + i
		var r: Dictionary = await _play_one(seed_value)
		counts[r["outcome"]] = int(counts.get(r["outcome"], 0)) + 1
		for k in r["actions"]:
			actions[k] = int(actions.get(k, 0)) + int(r["actions"][k])
		for k in r["stratagems"]:
			stratagems[k] = int(stratagems.get(k, 0)) + int(r["stratagems"][k])
		prompts += int(r["prompts"])
		totals[0] += int(r["vp"][0])
		totals[1] += int(r["vp"][1])
		wins[0 if r["vp"][0] > r["vp"][1] else (1 if r["vp"][1] > r["vp"][0] else 2)] += 1
		if r["outcome"] != "finished":
			failures += 1
			print("FAIL seed %d: %s at step %d, round %d, vp %s, chooser %d" % [seed_value, r["outcome"], r["steps"], r["round"], r["vp"], r["chooser"]])
			if not last_rosters.is_empty():
				print("    units: ", ", ".join(last_rosters))
			for line in r["trail"]:
				print("    ", line)
	print("played %d games in %.1fs: %s" % [games, (Time.get_ticks_msec() - started) / 1000.0, counts])
	print("average VP: you %.1f, AI %.1f | wins: you %d, AI %d, draws %d" % [float(totals[0]) / games, float(totals[1]) / games, wins[0], wins[1], wins[2]])
	print("your actions: ", actions)
	print("stratagems used: ", stratagems)
	print("prompts answered: ", prompts)
	quit(1 if failures > 0 else 0)


func _real_rosters(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = ArmyLoader.load_all().filter(func(a: Dictionary) -> bool:
		return not str(a.get("source", "")).ends_with("armies_placeholder.json"))
	var first: int = rng.randi_range(0, pool.size() - 1)
	var second: int = (first + rng.randi_range(1, pool.size() - 1)) % pool.size()
	var names: Array[String] = []
	var rosters: Array = []
	for index in [first, second]:
		var units: Array = pool[index]["units"]
		var picked: Array = []
		for j in range(6):
			var u: Dictionary = units[rng.randi_range(0, units.size() - 1)]
			picked.append(ArmyLoader.prepare_unit(u, ArmyLoader.min_models(u)))
			names.append(str(u["name"]))
		rosters.append({"name": pool[index]["name"], "units": picked})
	last_rosters = names
	return rosters


func _play_one(seed_value: int) -> Dictionary:
	var game: GameRoot = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.skip_roster = true
	game.full_flow = true
	game.battle_seed = seed_value
	if OS.get_cmdline_user_args().has("real"):
		game.armies_override = _real_rosters(seed_value)
	game.settings.reduced_motion = true
	root.add_child(game)
	await process_frame
	var result: Dictionary = await PlaytestBot.new(game, seed_value).play()
	game.queue_free()
	await process_frame
	return result
