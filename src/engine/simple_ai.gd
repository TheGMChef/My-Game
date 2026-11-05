class_name SimpleAI
extends RefCounted
## A deliberately simple scripted opponent: advance on objectives, shoot the nearest enemy,
## charge if it can, fight the nearest engaged enemy. No lookahead and no LLM.


static func movement(b: Battle, side: int) -> void:
	for u in b.living(side):
		if UnitRules.engaged(u, b.units):
			continue
		var goal: Vector2 = _goal(b, u)
		_try_translate(b, u, goal, u.move, "normal")


static func shooting(b: Battle, side: int) -> void:
	for u in b.living(side):
		var target: UnitState = _nearest_enemy(b, u)
		if target == null:
			continue
		Combat.shoot(u, target, b.units, b.dice, {"terrain": b.terrain, "turn_no": b.turn_no})
		b.remove_destroyed()


static func charging(b: Battle, side: int) -> void:
	for u in b.living(side):
		if not ChargeRules.eligible(u, b.units)["ok"]:
			continue
		var roll: int = ChargeRules.charge_roll(b.dice)
		var options: Array[UnitState] = ChargeRules.possible_targets(u, b.units, roll)
		if options.is_empty():
			continue
		var target: UnitState = options[0]
		for dist in range(roll, 0, -1):
			var dest: Array[Vector2] = _translated(u, target.centre(), float(dist))
			var targets: Array[UnitState] = [target]
			if ChargeRules.check_move(u, dest, targets, roll, b.units, b.board, b.terrain)["ok"]:
				ChargeRules.apply_move(u, dest)
				break


static func fighting(b: Battle, side: int) -> void:
	var seq := FightSequencer.new()
	seq.begin(b.units, side)
	var guard: int = 0
	while not seq.finished and guard < 40:
		guard += 1
		var opts: Array[UnitState] = seq.options()
		if opts.is_empty():
			break
		var u: UnitState = opts[0]
		seq.select(u)
		var foe: UnitState = _nearest_enemy(b, u)
		if foe != null and u.gap_to(foe) <= UnitRules.ENGAGEMENT_RANGE:
			Combat.fight(u, foe, b.dice)
		b.remove_destroyed()
		seq.refresh()


static func _goal(b: Battle, u: UnitState) -> Vector2:
	var best: Vector2 = u.centre()
	var best_d: float = INF
	for o in b.objectives:
		if Missions.controller(o, b.units, b.objective_range) == u.owner:
			continue
		var d: float = u.centre().distance_to(o)
		if d < best_d:
			best_d = d
			best = o
	if best_d == INF:
		var foe: UnitState = _nearest_enemy(b, u)
		if foe != null:
			return foe.centre()
	return best


static func _nearest_enemy(b: Battle, u: UnitState) -> UnitState:
	var best: UnitState = null
	var best_d: float = INF
	for o in b.units:
		if o.owner != u.owner and not o.is_destroyed():
			var d: float = u.gap_to(o)
			if d < best_d:
				best_d = d
				best = o
	return best


## Move every model by the same vector towards [param goal]; shorten the step until it is legal.
static func _try_translate(b: Battle, u: UnitState, goal: Vector2, max_dist: float, mode: String) -> void:
	var dist: float = minf(max_dist, u.centre().distance_to(goal))
	while dist > 0.25:
		var dest: Array[Vector2] = _translated(u, goal, dist)
		if UnitRules.check_move(u, dest, mode, b.units, b.board, 0, b.terrain)["ok"]:
			UnitRules.apply_move(u, dest, mode)
			return
		dist -= 0.5


static func _translated(u: UnitState, goal: Vector2, dist: float) -> Array[Vector2]:
	var dir: Vector2 = (goal - u.centre()).normalized()
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"] + dir * dist)
	return out
