class_name UnitRules
extends RefCounted
## Coherency, engagement, leadership and movement legality (core rules 01, 03, 09).
##
## Not yet checked: moving through enemy models, terrain costs, flying, desperate escape,
## vertical distances (the board is flat 2D, so the 5" vertical limits always pass).

const COHERENCY_NEAR := 2.0
const COHERENCY_FAR := 9.0
const ENGAGEMENT_RANGE := 2.0
const SETUP_MARGIN := 0.001


## True if every model is within 2" of another model and within 9" of all the others.
static func in_coherency(positions: Array[Vector2], radius: float) -> bool:
	if positions.size() <= 1:
		return true
	for i in range(positions.size()):
		var near: bool = false
		for j in range(positions.size()):
			if i == j:
				continue
			var gap: float = Geo.edge_distance(positions[i], radius, positions[j], radius)
			if gap > COHERENCY_FAR:
				return false
			if gap <= COHERENCY_NEAR:
				near = true
		if not near:
			return false
	return true


## True if any model of [param unit] is within engagement range of an enemy model.
static func engaged(unit: UnitState, all_units: Array) -> bool:
	for other in all_units:
		if other.owner == unit.owner:
			continue
		for m in unit.models:
			for n in other.models:
				if Geo.edge_distance(m["pos"], unit.base_radius, n["pos"], other.base_radius) <= ENGAGEMENT_RANGE:
					return true
	return false


## Leadership roll (01.06): 2D6 equal to or above the unit's Ld.
static func leadership_roll(unit: UnitState, dice: Dice) -> bool:
	return dice.roll("2D6") >= unit.leadership


## Battle-shock roll (01.07): a failed roll battle-shocks the unit. Returns true if it passed.
## A passed roll does not clear an existing shock here; the Command phase does that.
## In Synapse range the test is on 3D6. [param modifier] changes the total, as Shadow in the Warp does.
static func battle_shock_roll(unit: UnitState, dice: Dice, units: Array = [], modifier: int = 0) -> bool:
	var roll: int = dice.roll("3D6" if ArmyRules.in_synapse(unit, units) else "2D6")
	var passed: bool = roll + modifier >= unit.leadership
	if not passed:
		unit.battle_shocked = true
	return passed


## How many dice a battle-shock roll uses for this unit: 3 in Synapse range, otherwise 2.
static func shock_dice_count(unit: UnitState, units: Array) -> int:
	return 3 if ArmyRules.in_synapse(unit, units) else 2


## Check a set-up during deployment (03.02): inside the zone, in coherency, on no other model,
## out of dense terrain and unengaged. Returns {"ok": bool, "reason": String}.
static func check_deploy(unit: UnitState, positions: Array[Vector2], zone: Rect2, all_units: Array,
		board: Rect2, terrain: Array = []) -> Dictionary:
	if positions.size() != unit.models.size():
		return _no("one position is needed for each model")
	var r: float = unit.base_radius
	var inside: Rect2 = zone.intersection(board).grow(-r + SETUP_MARGIN)
	for i in range(positions.size()):
		if not inside.has_point(positions[i]):
			return _no("every model must be wholly inside your deployment zone")
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < r * 2.0 - SETUP_MARGIN:
				return _no("models cannot overlap")
		for area in terrain:
			for f in area.features:
				if f["category"] == "dense" and Geo.circle_overlaps_rect(positions[i], r, f["rect"]):
					return _no("models cannot be set up inside dense terrain")
		for other in all_units:
			for n in other.models:
				if positions[i].distance_to(n["pos"]) < r + other.base_radius - SETUP_MARGIN:
					return _no("models cannot overlap")
	if not in_coherency(positions, r):
		return _no("the unit would not be in coherency")
	for other in all_units:
		if other.owner != unit.owner and positions_engaged_with(positions, r, other):
			return _no("the unit must be set up unengaged")
	return {"ok": true, "reason": ""}


## Check a proposed move. [param mode] is "normal", "advance" or "fall_back".
## Returns {"ok": bool, "reason": String}.
static func check_move(unit: UnitState, new_positions: Array[Vector2], mode: String,
		all_units: Array, board: Rect2, advance_roll: int = 0, terrain: Array = []) -> Dictionary:
	if new_positions.size() != unit.models.size():
		return _no("one new position is needed for each model")
	var is_engaged: bool = engaged(unit, all_units)
	var allowed: float = unit.move
	match mode:
		"normal":
			if is_engaged:
				return _no("an engaged unit cannot make a normal move")
		"advance":
			if is_engaged:
				return _no("an engaged unit cannot advance")
			allowed += float(advance_roll)
		"fall_back":
			if not is_engaged:
				return _no("only an engaged unit can fall back")
			if unit.battle_shocked:
				return _no("a battle-shocked unit cannot make an ordered retreat (desperate escape is not implemented)")
		_:
			return _no("unknown move mode")
	for i in range(new_positions.size()):
		if not board.has_point(new_positions[i]):
			return _no("model %d would leave the battlefield" % i)
		if unit.models[i]["pos"].distance_to(new_positions[i]) > allowed + 0.0001:
			return _no("model %d moves further than %.1f\"" % [i, allowed])
	var terrain_problem: String = terrain_problem(unit, new_positions, terrain)
	if terrain_problem != "":
		return _no(terrain_problem)
	if not in_coherency(new_positions, unit.base_radius):
		return _no("the unit would not be in coherency")
	var moved := UnitState.new()
	moved.owner = unit.owner
	moved.base_radius = unit.base_radius
	for p in new_positions:
		moved.models.append({"pos": p})
	var others: Array = []
	for u in all_units:
		if u != unit:
			others.append(u)
	others.append(moved)
	if engaged(moved, others):
		return _no("the unit must end its move unengaged")
	return {"ok": true, "reason": ""}


## Terrain rules for a move (13.06, 13.11). INFANTRY, BEASTS, SWARM and MOBILE models can
## move through dense terrain. Other models cannot cross dense features taller than 2" (climbing
## is not modelled). No model may end a move inside a dense feature (Solid).
## Returns a reason string if the move breaks a terrain rule, or an empty string.
static func terrain_problem(unit: UnitState, new_positions: Array[Vector2], terrain: Array) -> String:
	var walker: bool = unit.has_keyword("INFANTRY") or unit.has_keyword("BEASTS") \
			or unit.has_keyword("SWARM") or unit.has_keyword("MOBILE")
	for i in range(new_positions.size()):
		var start: Vector2 = unit.models[i]["pos"]
		for area in terrain:
			for f in area.features:
				if f["category"] != "dense":
					continue
				var r: Rect2 = f["rect"]
				if Geo.circle_overlaps_rect(new_positions[i], unit.base_radius, r):
					return "model %d cannot end its move inside a dense terrain feature" % i
				if not walker and float(f["height"]) > 2.0 and Geo.segment_hits_rect(start, new_positions[i], r):
					return "model %d cannot move through a dense terrain feature taller than 2\"" % i
	return ""


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## True if models at [param positions] would be within engagement range of [param other].
static func positions_engaged_with(positions: Array[Vector2], radius: float, other: UnitState) -> bool:
	for p in positions:
		for n in other.models:
			if Geo.edge_distance(p, radius, n["pos"], other.base_radius) <= ENGAGEMENT_RANGE:
				return true
	return false


## Move the models and record the turn flags. Call only after [method check_move] said ok.
static func apply_move(unit: UnitState, new_positions: Array[Vector2], mode: String) -> void:
	for i in range(new_positions.size()):
		var d: float = unit.models[i]["pos"].distance_to(new_positions[i])
		unit.max_model_move = maxf(unit.max_model_move, d)
		unit.models[i]["pos"] = new_positions[i]
	if mode == "advance":
		unit.advanced = true
	elif mode == "fall_back":
		unit.fell_back = true
