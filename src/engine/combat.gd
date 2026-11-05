class_name Combat
extends RefCounted
## Unit-level shooting and melee: picks weapons, counts attacking models, builds the context
## and calls [AttackResolver] for each weapon profile.
##
## [method shoot_plan] and [method fight_plan] describe what would be rolled without rolling,
## so the odds panel and the real attack always agree.
##
## Shooting types are chosen automatically: a unit that Advanced can only use [ASSAULT]
## weapons (10.05); an [INDIRECT FIRE] weapon whose models cannot see the target shoots
## indirectly (10.07) when the unit did not Advance and is unengaged; otherwise normal.
##
## Not yet modelled: per-model weapon choice, close-quarters shooting, and splitting attacks
## across several target units. [ONE SHOT] is tracked per unit, not per model.


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
	var spotted: bool = false
	var spotted_checked: bool = false
	for w in attacker.weapons:
		if w.is_melee():
			continue
		if attacker.advanced and not w.has("ASSAULT"):
			continue
		if w.has("ONE SHOT") and attacker.one_shot_used.has(w.weapon_name):
			continue
		var indirect_ok: bool = w.has("INDIRECT FIRE") and not attacker.advanced and unengaged
		# Two groups of models: those that see the target (normal) and those that fire blind.
		var groups: Dictionary = {
			"seen": {"n": 0, "half": 0, "pos": Vector2.ZERO, "gap": INF},
			"unseen": {"n": 0, "half": 0, "pos": Vector2.ZERO, "gap": INF}}
		for m in attacker.models:
			var best: float = INF
			for n in target.models:
				best = minf(best, Geo.edge_distance(m["pos"], attacker.base_radius, n["pos"], target.base_radius))
			if best > w.range_in:
				continue
			var key: String = "seen"
			if not terrain.is_empty() and not Visibility.unit_visible_to_model(m["pos"], attacker.base_radius, target, turn_no, terrain):
				if not indirect_ok:
					continue
				key = "unseen"
			var g: Dictionary = groups[key]
			g["n"] += 1
			if best <= w.range_in / 2.0:
				g["half"] += 1
			if best < g["gap"]:
				g["gap"] = best
				g["pos"] = m["pos"]
		for key in ["seen", "unseen"]:
			var g: Dictionary = groups[key]
			if g["n"] == 0:
				continue
			var c: Dictionary = ctx.duplicate()
			if key == "unseen":
				# Indirect fire (10.07): target has cover, only a 6 hits, or 4+ when the unit
				# stood still and a friendly unit can see the target.
				if not spotted_checked:
					spotted = _seen_by_a_friend(attacker, target, all_units, terrain, turn_no)
					spotted_checked = true
				c["cover"] = true
				c["indirect_min"] = 4 if (stationary and spotted) else 6
			elif not terrain.is_empty() and not c.has("cover"):
				c["cover"] = Visibility.has_cover(g["pos"], attacker.base_radius, target, terrain)
			c["models_firing"] = g["n"]
			c["half_range"] = g["half"] == g["n"]
			c["heavy_bonus"] = stationary and unengaged
			plan.append({"weapon": w, "ctx": c, "models": g["n"]})
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
		if w.has("ONE SHOT"):
			if attacker.one_shot_used.has(w.weapon_name):
				continue    # already fired in this very action (second group of models)
			attacker.one_shot_used.append(w.weapon_name)
		reports.append(AttackResolver.resolve(w, target, dice, entry["ctx"]))
		if w.has("HAZARDOUS"):
			hazardous_used += 1
	return {"reports": reports, "hazard_wounds": _hazard(attacker, hazardous_used, dice)}


## True if a friendly unit other than the shooter can see the target (10.07).
static func _seen_by_a_friend(attacker: UnitState, target: UnitState, all_units: Array, terrain: Array, turn_no: int) -> bool:
	for u in all_units:
		if u == attacker or u.owner != attacker.owner or u.is_destroyed():
			continue
		for m in u.models:
			if Visibility.unit_visible_to_model(m["pos"], u.base_radius, target, turn_no, terrain):
				return true
	return false


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
