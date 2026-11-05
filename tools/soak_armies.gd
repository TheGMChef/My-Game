extends SceneTree
## AI-vs-AI soak with random rosters from the local army files (data/local, user://armies).
## Run: godot --headless --path . -s tools/soak_armies.gd -- <games> [<army A> <army B>]
## Prints one line per game and a summary. Any SCRIPT ERROR in the output is a bug to chase.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var games: int = int(args[0]) if args.size() > 0 else 20
	var armies: Array = ArmyLoader.load_all()
	var pool: Array = armies.filter(func(a: Dictionary) -> bool: return not str(a.get("source", "")).ends_with("armies_placeholder.json"))
	if pool.size() < 2:
		print("need at least two local armies in data/local or user://armies")
		quit(1)
		return
	var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/scenario_clash_of_patrols.json"))
	var wins: Array[int] = [0, 0, 0]
	var rounds_total: int = 0
	var rng := RandomNumberGenerator.new()
	for g in range(games):
		rng.seed = 1000 + g
		var a: Dictionary = _find(pool, args[1]) if args.size() > 2 else pool[rng.randi() % pool.size()]
		var b: Dictionary = _find(pool, args[2]) if args.size() > 2 else pool[rng.randi() % pool.size()]
		var rosters: Array = [_roster(a, rng), _roster(b, rng)]
		var battle := Battle.new(sc, rosters, 500 + g)
		var res: Dictionary = battle.play_all()
		var vp: Array = res["vp"]
		var winner: int = 2 if vp[0] == vp[1] else (0 if vp[0] > vp[1] else 1)
		wins[winner] += 1
		rounds_total += battle.flow.round_no if "round_no" in battle.flow else 0
		if args.size() > 1 and args[1] == "log":
			for line in battle.log:
				print("   ", line)
		print("game %d: %s vs %s -> VP %s survivors %s rounds %s" % [g, a["name"], b["name"], vp, res["survivors"], res["rounds"]])
	print("SUMMARY games=%d side0=%d side1=%d draw=%d" % [games, wins[0], wins[1], wins[2]])
	quit()

func _find(pool: Array, name: String) -> Dictionary:
	for a in pool:
		if str(a["name"]).to_lower().replace(" ", "_") == name.to_lower().replace(" ", "_"):
			return a
	return pool[0]

func _roster(army: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var units: Array = (army["units"] as Array).duplicate()
	for i in range(units.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t: Variant = units[i]
		units[i] = units[j]
		units[j] = t
	var picked: Array = []
	for u in units.slice(0, 6):
		picked.append(ArmyLoader.prepare_unit(u, ArmyLoader.max_models(u) if rng.randf() < 0.5 else ArmyLoader.min_models(u)))
	return {"name": army["name"], "units": picked}
