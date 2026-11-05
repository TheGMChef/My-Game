class_name SimpleAI
extends RefCounted
## A deliberately simple scripted opponent: advance on objectives, shoot the nearest enemy,
## charge if it can, fight the nearest engaged enemy. No lookahead and no LLM.
## It issues the same commands a human does, through [Battle].


static func movement(b: Battle, side: int) -> void:
	for u in b.living(side):
		if UnitRules.engaged(u, b.units):
			continue
		var goal: Vector2 = _goal(b, u)
		var dist: float = minf(u.move, u.centre().distance_to(goal))
		var done: bool = false
		while dist > 0.25 and not done:
			var dest: Array[Vector2] = _translated(u, goal, dist)
			done = b.cmd_move(u, dest, "normal")["ok"]
			dist -= 0.5
		if not done:
			b.cmd_hold(u)


static func shooting(b: Battle, side: int) -> void:
	for u in b.living(side):
		var target: UnitState = _nearest_enemy(b, u)
		if target != null:
			b.cmd_shoot(u, target)


static func charging(b: Battle, side: int) -> void:
	for u in b.living(side):
		var declared: Dictionary = b.cmd_declare_charge(u)
		if not declared["ok"] or declared["targets"].is_empty():
			continue
		var target: UnitState = declared["targets"][0]
		var targets: Array[UnitState] = [target]
		var moved: bool = false
		for dist in range(int(declared["roll"]), 0, -1):
			if b.cmd_charge_move(u, _translated(u, target.centre(), float(dist)), targets)["ok"]:
				moved = true
				break
		if not moved:
			b.cmd_charge_fail(u)


## Pick the first available unit for [param side] and fight the nearest engaged enemy.
static func fight_one(b: Battle, side: int) -> void:
	for u in b.fight_options():
		if u.owner != side:
			continue
		var foe: UnitState = _nearest_enemy(b, u)
		var fought: bool = false
		if foe != null and u.gap_to(foe) <= UnitRules.ENGAGEMENT_RANGE:
			fought = bool(b.cmd_fight(u, foe)["ok"])
		if not fought:
			# A unit that cannot attack (for example, it has no melee weapon) must still be
			# selected or the Fight phase never ends.
			b.cmd_fight_skip(u)
		return


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


static func _translated(u: UnitState, goal: Vector2, dist: float) -> Array[Vector2]:
	var dir: Vector2 = (goal - u.centre()).normalized()
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"] + dir * dist)
	return out
