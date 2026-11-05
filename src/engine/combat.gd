class_name Combat
extends RefCounted
## Unit-level shooting and melee: picks weapons, counts attacking models, builds the context
## and calls [AttackResolver] for each weapon profile.
##
## [method shoot_plan] and [method fight_plan] describe what would be rolled without rolling,
## so the odds panel and the real attack always agree.
##
## Not yet modelled: per-model weapon choice, targeting restrictions beyond visibility,
## shooting types (assault, close-quarters, indirect), [ONE SHOT], [PRECISION], and splitting
## attacks across several target units.


## What shooting [param target] would involve: one entry per ranged weapon that has a model
## in range with the target visible, each {"weapon", "ctx", "models"}.
## [param ctx] may hold "terrain" (Array of TerrainArea), "turn_no" (int, for hidden),
## "cover" (bool, overrides the automatic check) and "hit_mod" / "wound_mod" (int).
static func shoot_plan(attacker: UnitState, target: UnitState, all_units: Array, ctx: Dictionary = {}) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if target.is_destroyed():
		return plan
	var terrain: Array = ctx.get("terrain", [])
	var turn_no: int = int(ctx.get("turn_no", 0))
	var stationary: bool = attacker.max_model_move <= 3.0 and not attacker.advanced
	var unengaged: bool = not UnitRules.engaged(attacker, all_units)
	for w in attacker.weapons:
		if w.is_melee():
			continue
		var in_range: int = 0
		var in_half: int = 0
		var nearest_pos: Vector2 = Vector2.ZERO
		var nearest_gap: float = INF
		for m in attacker.models:
			var best: float = INF
			for n in target.models:
				best = minf(best, Geo.edge_distance(m["pos"], attacker.base_radius, n["pos"], target.base_radius))
			if best > w.range_in:
				continue
			if not terrain.is_empty() and not Visibility.unit_visible_to_model(m["pos"], attacker.base_radius, target, turn_no, terrain):
				continue
			in_range += 1
			if best <= w.range_in / 2.0:
				in_half += 1
			if best < nearest_gap:
				nearest_gap = best
				nearest_pos = m["pos"]
		if in_range == 0:
			continue
		var c: Dictionary = ctx.duplicate()
		if not terrain.is_empty() and not c.has("cover"):
			c["cover"] = Visibility.has_cover(nearest_pos, attacker.base_radius, target, terrain)
		c["models_firing"] = in_range
		c["half_range"] = in_half == in_range
		c["heavy_bonus"] = stationary and unengaged
		plan.append({"weapon": w, "ctx": c, "models": in_range})
	return plan


## Shoot at [param target]. Returns {"reports": Array[Dictionary], "hazard_wounds": int}.
static func shoot(attacker: UnitState, target: UnitState, all_units: Array, dice: Dice, ctx: Dictionary = {}) -> Dictionary:
	var reports: Array[Dictionary] = []
	var plan: Array[Dictionary] = shoot_plan(attacker, target, all_units, ctx)
	var hazardous_used: int = 0
	if not plan.is_empty():
		attacker.last_fired_turn = int(ctx.get("turn_no", 0))
	for entry in plan:
		if target.is_destroyed():
			break
		var w: Weapon = entry["weapon"]
		reports.append(AttackResolver.resolve(w, target, dice, entry["ctx"]))
		if w.has("HAZARDOUS"):
			hazardous_used += 1
	return {"reports": reports, "hazard_wounds": _hazard(attacker, hazardous_used, dice)}


## What fighting [param target] would involve. All [EXTRA ATTACKS] weapons are used, plus the
## first other melee weapon (12.05 and 24.11). Only models within engagement range attack.
static func fight_plan(attacker: UnitState, target: UnitState, ctx: Dictionary = {}) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var fighting: int = 0
	for m in attacker.models:
		for n in target.models:
			if Geo.edge_distance(m["pos"], attacker.base_radius, n["pos"], target.base_radius) <= UnitRules.ENGAGEMENT_RANGE:
				fighting += 1
				break
	if fighting == 0:
		return plan
	var main_picked: bool = false
	for w in attacker.weapons:
		if not w.is_melee():
			continue
		if not w.has("EXTRA ATTACKS"):
			if main_picked:
				continue
			main_picked = true
		var c: Dictionary = ctx.duplicate()
		c["models_firing"] = fighting
		c["charged"] = attacker.charged
		c["single_target"] = true
		plan.append({"weapon": w, "ctx": c, "models": fighting})
	return plan


## Fight [param target] in melee. Returns {"reports": Array[Dictionary], "hazard_wounds": int}.
static func fight(attacker: UnitState, target: UnitState, dice: Dice, ctx: Dictionary = {}) -> Dictionary:
	var reports: Array[Dictionary] = []
	var hazardous_used: int = 0
	for entry in fight_plan(attacker, target, ctx):
		if target.is_destroyed():
			break
		var w: Weapon = entry["weapon"]
		reports.append(AttackResolver.resolve(w, target, dice, entry["ctx"]))
		if w.has("HAZARDOUS"):
			hazardous_used += 1
	return {"reports": reports, "hazard_wounds": _hazard(attacker, hazardous_used, dice)}


static func _hazard(attacker: UnitState, count: int, dice: Dice) -> int:
	var lost: int = 0
	for i in range(count):
		lost += AttackResolver.hazard_roll(attacker, dice)
	return lost
