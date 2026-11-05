class_name MeleeMoves
extends RefCounted
## Pile-in and consolidation moves in the Fight phase (core rules 12.02 to 12.08).

const MAX_MOVE := 3.0
const PILE_IN_SEEK_RANGE := 5.0
const CONSOLIDATE_SEEK_RANGE := 3.0


## Enemy units a pile-in move would aim at: every engaged enemy, or else those within 5".
static func pile_in_targets(unit: UnitState, all_units: Array) -> Array[UnitState]:
	var engaged_with: Array[UnitState] = _engaged_enemies(unit, all_units)
	if not engaged_with.is_empty():
		return engaged_with
	var out: Array[UnitState] = []
	for o in all_units:
		if o.owner != unit.owner and not o.is_destroyed() and unit.gap_to(o) <= PILE_IN_SEEK_RANGE:
			out.append(o)
	return out


## A unit may pile in if it is engaged, or made a charge move this turn.
static func can_pile_in(unit: UnitState, all_units: Array) -> bool:
	return UnitRules.engaged(unit, all_units) or unit.charged


static func check_pile_in(unit: UnitState, new_positions: Array[Vector2], all_units: Array, board: Rect2) -> Dictionary:
	if not can_pile_in(unit, all_units):
		return _no("the unit is not eligible to pile in")
	var targets: Array[UnitState] = pile_in_targets(unit, all_units)
	if targets.is_empty():
		return _no("no pile-in target")
	var base: Dictionary = _check_models(unit, new_positions, targets, all_units, board)
	if not base["ok"]:
		return base
	if not _engaged_with_any_enemy(unit, new_positions, all_units):
		return _no("the unit must be engaged after piling in")
	return _check_still_engaged(unit, new_positions, all_units)


## Which consolidation mode applies: "ongoing", "engaging", "objective" or "none" (11.08).
static func consolidation_mode(unit: UnitState, all_units: Array, objectives: Array[Vector2], objective_range: float) -> String:
	if UnitRules.engaged(unit, all_units):
		return "ongoing"
	for o in all_units:
		if o.owner != unit.owner and not o.is_destroyed() and unit.gap_to(o) <= CONSOLIDATE_SEEK_RANGE:
			return "engaging"
	if not _objectives_within(unit, objectives, CONSOLIDATE_SEEK_RANGE).is_empty():
		return "objective"
	return "none"


static func check_consolidation(unit: UnitState, new_positions: Array[Vector2], all_units: Array,
		board: Rect2, objectives: Array[Vector2], objective_range: float) -> Dictionary:
	var mode: String = consolidation_mode(unit, all_units, objectives, objective_range)
	match mode:
		"ongoing":
			var targets: Array[UnitState] = _engaged_enemies(unit, all_units)
			var base: Dictionary = _check_models(unit, new_positions, targets, all_units, board)
			if not base["ok"]:
				return base
			return _check_still_engaged(unit, new_positions, all_units)
		"engaging":
			var near: Array[UnitState] = []
			for o in all_units:
				if o.owner != unit.owner and not o.is_destroyed() and unit.gap_to(o) <= CONSOLIDATE_SEEK_RANGE:
					near.append(o)
			var base2: Dictionary = _check_models(unit, new_positions, near, all_units, board)
			if not base2["ok"]:
				return base2
			for t in near:
				if not UnitRules.positions_engaged_with(new_positions, unit.base_radius, t):
					return _no("the unit must be engaged with every selected enemy unit")
			return {"ok": true, "reason": ""}
		"objective":
			return _check_objective(unit, new_positions, board, _objectives_within(unit, objectives, CONSOLIDATE_SEEK_RANGE)[0], objective_range)
	return _no("no consolidation move is possible")


static func _check_models(unit: UnitState, new_positions: Array[Vector2], targets: Array[UnitState],
		all_units: Array, board: Rect2) -> Dictionary:
	if new_positions.size() != unit.models.size():
		return _no("one new position is needed for each model")
	for i in range(new_positions.size()):
		var start: Vector2 = unit.models[i]["pos"]
		var moved: float = start.distance_to(new_positions[i])
		if moved <= 0.0001:
			continue
		if not board.has_point(new_positions[i]):
			return _no("model %d would leave the battlefield" % i)
		if moved > MAX_MOVE + 0.0001:
			return _no("model %d moves further than 3\"" % i)
		if _in_base_contact(start, unit.base_radius, unit.owner, all_units):
			return _no("model %d is in base contact with an enemy model and cannot move" % i)
		if not (_nearest(new_positions[i], unit.base_radius, targets) < _nearest(start, unit.base_radius, targets) - 0.0001):
			return _no("model %d must end its move closer to the closest target" % i)
	if not UnitRules.in_coherency(new_positions, unit.base_radius):
		return _no("the unit would not be in coherency")
	return {"ok": true, "reason": ""}


## Each model that started engaged with an enemy unit must still be engaged with it.
static func _check_still_engaged(unit: UnitState, new_positions: Array[Vector2], all_units: Array) -> Dictionary:
	for e in _engaged_enemies(unit, all_units):
		for i in range(unit.models.size()):
			var was: bool = false
			for n in e.models:
				if Geo.edge_distance(unit.models[i]["pos"], unit.base_radius, n["pos"], e.base_radius) <= UnitRules.ENGAGEMENT_RANGE:
					was = true
					break
			if was:
				var single: Array[Vector2] = [new_positions[i]]
				if not UnitRules.positions_engaged_with(single, unit.base_radius, e):
					return _no("model %d started engaged with %s and must stay engaged" % [i, e.unit_name])
	return {"ok": true, "reason": ""}


static func _check_objective(unit: UnitState, new_positions: Array[Vector2], board: Rect2, objective: Vector2, objective_range: float) -> Dictionary:
	if new_positions.size() != unit.models.size():
		return _no("one new position is needed for each model")
	var any_in_range: bool = false
	for i in range(new_positions.size()):
		var start: Vector2 = unit.models[i]["pos"]
		var moved: float = start.distance_to(new_positions[i])
		if moved > MAX_MOVE + 0.0001:
			return _no("model %d moves further than 3\"" % i)
		if not board.has_point(new_positions[i]):
			return _no("model %d would leave the battlefield" % i)
		var end_gap: float = Geo.edge_distance(new_positions[i], unit.base_radius, objective, 0.0)
		var start_gap: float = Geo.edge_distance(start, unit.base_radius, objective, 0.0)
		if end_gap <= objective_range:
			any_in_range = true
		elif moved > 0.0001 and end_gap >= start_gap - 0.0001:
			return _no("model %d must end within range of the objective, or closer to it" % i)
	if not UnitRules.in_coherency(new_positions, unit.base_radius):
		return _no("the unit would not be in coherency")
	if not any_in_range:
		return _no("the unit must end within range of the objective")
	return {"ok": true, "reason": ""}


static func _objectives_within(unit: UnitState, objectives: Array[Vector2], within: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for o in objectives:
		for m in unit.models:
			if Geo.edge_distance(m["pos"], unit.base_radius, o, 0.0) <= within:
				out.append(o)
				break
	return out


static func _engaged_enemies(unit: UnitState, all_units: Array) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for o in all_units:
		if o.owner != unit.owner and not o.is_destroyed():
			var positions: Array[Vector2] = []
			for m in unit.models:
				positions.append(m["pos"])
			if UnitRules.positions_engaged_with(positions, unit.base_radius, o):
				out.append(o)
	return out


static func _engaged_with_any_enemy(unit: UnitState, positions: Array[Vector2], all_units: Array) -> bool:
	for o in all_units:
		if o.owner != unit.owner and not o.is_destroyed() and UnitRules.positions_engaged_with(positions, unit.base_radius, o):
			return true
	return false


static func _in_base_contact(pos: Vector2, radius: float, owner_id: int, all_units: Array) -> bool:
	for o in all_units:
		if o.owner == owner_id:
			continue
		for n in o.models:
			if Geo.edge_distance(pos, radius, n["pos"], o.base_radius) <= 0.0001:
				return true
	return false


static func _nearest(p: Vector2, radius: float, targets: Array[UnitState]) -> float:
	var best: float = INF
	for t in targets:
		for n in t.models:
			best = minf(best, Geo.edge_distance(p, radius, n["pos"], t.base_radius))
	return best


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
