class_name SimpleAI
extends RefCounted
## A deliberately simple scripted opponent: advance on objectives, shoot the nearest enemy,
## charge if it can, fight the nearest engaged enemy. No lookahead and no LLM.
## It issues the same commands a human does, through [Battle]. Stratagem choices are simple
## scripted rules that look only at the board as it stands.

const DEPLOY_GRID := 2.0
const DEPLOY_GRID_FINE := 1.0
const DEPLOY_COLUMNS: Array[int] = [5, 3, 2, 10]
const DEPLOY_CROWD := 5.0          ## friendly units this close make a spot less attractive
const DEPLOY_CROWD_COST := 4.0
const NEAR_CHARGER := 12.0         ## an enemy this close may charge next phase
const NEAR_INTERVENTION := 6.0     ## only step in for a fight this close
const WORTH_COUNTERING_MODELS := 3
const WORTH_COUNTERING_WOUNDS := 6
const SPARE_CP := 2                ## CP to hold before spending on a nice-to-have


## Holds the Shadow in the Warp until the second round, when units are close enough to matter.
static func command(b: Battle, side: int) -> void:
	if b.flow.round_no >= 2 and b.can_unleash_shadow(side):
		b.cmd_shadow_in_the_warp(side)


# ---------------------------------------------------------------- deployment

## Place the next unit of [param side]: the one with most models first, so big units get room.
static func next_to_deploy(b: Battle, side: int) -> UnitState:
	var best: UnitState = null
	for u: UnitState in b.undeployed_of(side):
		if best == null or u.model_count() > best.model_count():
			best = u
	return best


## The best legal set-up for this unit, near an objective and away from friends, or an empty
## array if the zone has no room for it. Tries a coarse grid first, then a finer one.
static func deployment_positions(b: Battle, u: UnitState) -> Array[Vector2]:
	for step in [DEPLOY_GRID, DEPLOY_GRID_FINE]:
		for columns in DEPLOY_COLUMNS:
			var found: Array[Vector2] = _best_spot(b, u, columns, step)
			if not found.is_empty():
				return found
	var none: Array[Vector2] = []
	return none


static func _best_spot(b: Battle, u: UnitState, columns: int, step: float) -> Array[Vector2]:
	var zone: Rect2 = b.zone_rect(u.owner)
	var best: Array[Vector2] = []
	var best_score: float = INF
	var x: float = zone.position.x + step / 2.0
	while x < zone.end.x:
		var y: float = zone.position.y + step / 2.0
		while y < zone.end.y:
			var spot: Vector2 = Vector2(x, y)
			var positions: Array[Vector2] = b.formation(u, spot, columns)
			if b.preview_deploy(u, positions)["ok"]:
				var score: float = _spot_score(b, u, spot)
				if score < best_score:
					best_score = score
					best = positions
			y += step
		x += step
	return best


static func _spot_score(b: Battle, u: UnitState, spot: Vector2) -> float:
	var nearest: float = INF
	for o in b.objectives:
		nearest = minf(nearest, spot.distance_to(o))
	var score: float = nearest
	for other in b.living(u.owner):
		if other.centre().distance_to(spot) <= DEPLOY_CROWD:
			score += DEPLOY_CROWD_COST
	return score


# ---------------------------------------------------------------- stratagems

## Use a stratagem in a reaction window, or do nothing to pass.
static func react(b: Battle, side: int, window: String, options: Array[Dictionary]) -> void:
	var pick: Dictionary = {}
	match window:
		Stratagems.W_SHOCK_BEFORE, Stratagems.W_SHOCK_AFTER:
			pick = _first_on_objective(b, options)
		Stratagems.W_END_MOVEMENT:
			pick = _overwatch_pick(b, options)
		Stratagems.W_START_SHOOTING:
			if b.command_points(side) >= SPARE_CP:
				pick = options[0]
		Stratagems.W_END_CHARGE:
			pick = _intervention_pick(b, options)
		Stratagems.W_AFTER_FIGHT:
			pick = _counter_pick(b, options)
	if not pick.is_empty():
		b.cmd_stratagem(side, str(pick["id"]), pick)


## Worth CP only for a unit holding an objective, because its OC is what a failed test would lose.
static func _first_on_objective(b: Battle, options: Array[Dictionary]) -> Dictionary:
	for o in options:
		var u: UnitState = b.unit_by_id(str(o["unit"]))
		for spot in b.objectives:
			if u != null and Missions.control_total(spot, [u], u.owner, b.objective_range) > 0:
				return o
	return {}


## Fire at something close enough to charge. Options run nearest enemy first for each unit.
static func _overwatch_pick(b: Battle, options: Array[Dictionary]) -> Dictionary:
	for o in options:
		if str(o["id"]) != "fire_overwatch":
			continue
		var u: UnitState = b.unit_by_id(str(o["unit"]))
		var foe: UnitState = b.unit_by_id(str(o["target"]))
		if u.gap_to(foe) <= NEAR_CHARGER:
			return o
	return {}


static func _intervention_pick(b: Battle, options: Array[Dictionary]) -> Dictionary:
	for o in options:
		var u: UnitState = b.unit_by_id(str(o["unit"]))
		if str(o["mode"]) != Stratagems.LEAP_TO_DEFEND:
			continue
		for e in b.living(1 - u.owner):
			if e.charged and u.gap_to(e) <= NEAR_INTERVENTION:
				return o
	return {}


## Strike back with a unit big enough to matter, before it gets hit again.
static func _counter_pick(b: Battle, options: Array[Dictionary]) -> Dictionary:
	for o in options:
		var u: UnitState = b.unit_by_id(str(o["unit"]))
		if u.model_count() >= WORTH_COUNTERING_MODELS or u.total_wounds_left() >= WORTH_COUNTERING_WOUNDS:
			return o
	return {}


## Throw explosives at an enemy that is holding an objective.
static func _explosives(b: Battle, side: int) -> void:
	for o in b.stratagem_options(side, Stratagems.W_SHOOTING):
		var foe: UnitState = b.unit_by_id(str(o["target"]))
		for spot in b.objectives:
			if Missions.control_total(spot, [foe], foe.owner, b.objective_range) > 0:
				b.cmd_stratagem(side, str(o["id"]), o)
				return


## A charge with nothing in reach is worth one more try while CP are spare.
static func _reroll_charge(b: Battle, side: int, u: UnitState) -> Dictionary:
	if b.command_points(side) >= SPARE_CP:
		for o in b.stratagem_options(side, Stratagems.W_CHARGE):
			if str(o["unit"]) == u.id and b.cmd_stratagem(side, str(o["id"]), o)["ok"]:
				return b.charge_state(u)
	return {}


static func _crush(b: Battle, side: int) -> void:
	var options: Array[Dictionary] = b.stratagem_options(side, Stratagems.W_CHARGE_MOVED)
	if not options.is_empty() and b.command_points(side) >= SPARE_CP:
		b.cmd_stratagem(side, str(options[0]["id"]), options[0])


static func _epic(b: Battle, side: int, u: UnitState, foe: UnitState) -> void:
	if not foe.models.any(func(m: Dictionary) -> bool: return bool(m["character"])):
		return
	for o in b.stratagem_options(side, Stratagems.W_FIGHT_SELECTED):
		if str(o["unit"]) == u.id:
			b.cmd_stratagem(side, str(o["id"]), o)
			return


# ---------------------------------------------------------------- phases

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


## The first unit able to observe marks the nearest enemy for the rest of the army.
static func _mark_target(b: Battle, side: int) -> void:
	for u in b.living(side):
		var target: UnitState = _nearest_enemy(b, u)
		if target != null and b.can_observe(u) and b.cmd_mark_spotted(u, target)["ok"]:
			return


static func shooting(b: Battle, side: int) -> void:
	_mark_target(b, side)
	_explosives(b, side)
	for u in b.living(side):
		var target: UnitState = _nearest_enemy(b, u)
		if target != null:
			b.cmd_shoot(u, target)


static func charging(b: Battle, side: int) -> void:
	for u in b.living(side):
		var declared: Dictionary = b.cmd_declare_charge(u)
		if not declared["ok"]:
			continue
		if declared["targets"].is_empty():
			declared = _reroll_charge(b, side, u)
			if declared.is_empty() or declared["targets"].is_empty():
				continue
		var target: UnitState = declared["targets"][0]
		var targets: Array[UnitState] = [target]
		var moved: Array[Vector2] = ChargeRules.auto_positions(u, targets, int(declared["roll"]), b.units, b.board, b.terrain)
		if moved.is_empty() or not b.cmd_charge_move(u, moved, targets)["ok"]:
			b.cmd_charge_fail(u)
		else:
			_crush(b, side)


## Pick the first available unit for [param side] and fight the nearest engaged enemy.
static func fight_one(b: Battle, side: int) -> void:
	for u in b.fight_options():
		if u.owner != side:
			continue
		var foe: UnitState = _nearest_enemy(b, u)
		var fought: bool = false
		if foe != null and u.gap_to(foe) <= UnitRules.ENGAGEMENT_RANGE:
			_epic(b, side, u, foe)
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
