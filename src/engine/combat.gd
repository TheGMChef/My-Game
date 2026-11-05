class_name Combat
extends RefCounted
## Unit-level shooting and melee: picks weapons, counts attacking models, builds the context
## and calls [AttackResolver] for each weapon profile.
##
## Not yet modelled: per-model weapon choice, targeting restrictions beyond visibility,
## weapon choice per model, shooting types (assault, close-quarters, indirect), [ONE SHOT],
## [PRECISION], allocation of attacks across several target units.


## Shoot at [param target] with every ranged weapon of [param attacker] that has a model in
## range. Returns {"reports": Array[Dictionary], "hazard_wounds": int}.
## [param ctx] may hold "terrain" (Array of TerrainArea), "turn_no" (int, for hidden),
## "cover" (bool, overrides the automatic check) and "hit_mod" / "wound_mod" (int).
static func shoot(attacker: UnitState, target: UnitState, all_units: Array, dice: Dice, ctx: Dictionary = {}) -> Dictionary:
	var reports: Array[Dictionary] = []
	var terrain: Array = ctx.get("terrain", [])
	var turn_no: int = int(ctx.get("turn_no", 0))
	var hazardous_used: int = 0
	var stationary: bool = attacker.max_model_move <= 3.0 and not attacker.advanced
	var unengaged: bool = not UnitRules.engaged(attacker, all_units)
	for w in attacker.weapons:
		if w.is_melee() or target.is_destroyed():
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
		attacker.last_fired_turn = turn_no
		var c: Dictionary = ctx.duplicate()
		if not terrain.is_empty() and not c.has("cover"):
			c["cover"] = Visibility.has_cover(nearest_pos, attacker.base_radius, target, terrain)
		c["models_firing"] = in_range
		c["half_range"] = in_half == in_range
		c["heavy_bonus"] = stationary and unengaged
		reports.append(AttackResolver.resolve(w, target, dice, c))
		if w.has("HAZARDOUS"):
			hazardous_used += 1
	var hazard: int = 0
	for i in range(hazardous_used):
		hazard += AttackResolver.hazard_roll(attacker, dice)
	return {"reports": reports, "hazard_wounds": hazard}


## Fight [param target] in melee. All [EXTRA ATTACKS] weapons are used, plus the first other
## melee weapon (12.05 and 24.11). Only models within engagement range of the target attack.
static func fight(attacker: UnitState, target: UnitState, dice: Dice, ctx: Dictionary = {}) -> Dictionary:
	var reports: Array[Dictionary] = []
	var fighting: int = 0
	for m in attacker.models:
		for n in target.models:
			if Geo.edge_distance(m["pos"], attacker.base_radius, n["pos"], target.base_radius) <= UnitRules.ENGAGEMENT_RANGE:
				fighting += 1
				break
	var chosen: Array[Weapon] = []
	var main_picked: bool = false
	for w in attacker.weapons:
		if not w.is_melee():
			continue
		if w.has("EXTRA ATTACKS"):
			chosen.append(w)
		elif not main_picked:
			chosen.append(w)
			main_picked = true
	var hazardous_used: int = 0
	for w in chosen:
		if fighting == 0 or target.is_destroyed():
			break
		var c: Dictionary = ctx.duplicate()
		c["models_firing"] = fighting
		c["charged"] = attacker.charged
		c["single_target"] = true
		reports.append(AttackResolver.resolve(w, target, dice, c))
		if w.has("HAZARDOUS"):
			hazardous_used += 1
	var hazard: int = 0
	for i in range(hazardous_used):
		hazard += AttackResolver.hazard_roll(attacker, dice)
	return {"reports": reports, "hazard_wounds": hazard}
