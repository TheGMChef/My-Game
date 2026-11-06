class_name ChargeRules
extends RefCounted
## Declaring and making charge moves (core rules 11).
##
## Not yet enforced: the "must end within 1" / engaged if able" clauses for individual models,
## and moving around terrain (the board is open ground for now).

const DECLARE_RANGE := 12.0


## Can this unit declare a charge? Returns {ok, reason}.
static func eligible(unit: UnitState, all_units: Array) -> Dictionary:
	if unit.is_destroyed():
		return _no("unit is not on the battlefield")
	if UnitRules.engaged(unit, all_units):
		return _no("an engaged unit cannot declare a charge")
	if unit.advanced or unit.fell_back:
		return _no("a unit that advanced or fell back cannot declare a charge")
	for other in all_units:
		if other.owner != unit.owner and not other.is_destroyed() and unit.gap_to(other) <= DECLARE_RANGE:
			return {"ok": true, "reason": ""}
	return _no("no enemy unit within 12\"")


## Make the charge roll: 2D6, the maximum charge distance.
static func charge_roll(dice: Dice) -> int:
	return dice.roll("2D6")


## Enemy units that could be chosen as charge targets: within 12" and within the roll.
static func possible_targets(unit: UnitState, all_units: Array, max_distance: int) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for other in all_units:
		if other.owner == unit.owner or other.is_destroyed():
			continue
		var gap: float = unit.gap_to(other)
		if gap <= DECLARE_RANGE and gap <= float(max_distance):
			out.append(other)
	return out


## Check a proposed charge move against the rules. Returns {ok, reason}.
static func check_move(unit: UnitState, new_positions: Array[Vector2], targets: Array[UnitState],
		max_distance: int, all_units: Array, board: Rect2, terrain: Array = []) -> Dictionary:
	if targets.is_empty():
		return _no("a charge needs at least one target")
	if new_positions.size() != unit.models.size():
		return _no("one new position is needed for each model")
	for i in range(new_positions.size()):
		if not board.has_point(new_positions[i]):
			return _no("model %d would leave the battlefield" % i)
		var start: Vector2 = unit.models[i]["pos"]
		if start.distance_to(new_positions[i]) > float(max_distance) + 0.0001:
			return _no("model %d moves further than the charge roll of %d\"" % [i, max_distance])
		if not _ends_closer(start, new_positions[i], unit.base_radius, targets):
			return _no("model %d must end its move closer to a charge target" % i)
	var blocked: String = UnitRules.terrain_problem(unit, new_positions, terrain)
	if blocked != "":
		return _no(blocked)
	if not UnitRules.in_coherency(new_positions, unit.base_radius):
		return _no("the unit would not be in coherency")
	for t in targets:
		if not UnitRules.positions_engaged_with(new_positions, unit.base_radius, t):
			return _no("the unit must be engaged with every charge target")
	for other in all_units:
		if other.owner == unit.owner or targets.has(other) or other.is_destroyed():
			continue
		if UnitRules.positions_engaged_with(new_positions, unit.base_radius, other):
			return _no("the unit cannot be engaged with an enemy unit that is not a charge target")
	return {"ok": true, "reason": ""}


## A straight-line charge towards the nearest of [param targets] that passes [method check_move],
## longest first, or an empty array if there is none. Used wherever nobody is dragging the unit.
static func auto_positions(unit: UnitState, targets: Array[UnitState], max_distance: int, all_units: Array,
		board: Rect2, terrain: Array = []) -> Array[Vector2]:
	var order: Array = targets.duplicate()
	order.sort_custom(func(a: UnitState, b: UnitState) -> bool: return unit.gap_to(a) < unit.gap_to(b))
	for t: UnitState in order:
		var dir: Vector2 = (t.centre() - unit.centre()).normalized()
		var picked: Array[UnitState] = [t]
		for dist in range(max_distance, 0, -1):
			var moved: Array[Vector2] = []
			for m in unit.models:
				moved.append(m["pos"] + dir * float(dist))
			if check_move(unit, moved, picked, max_distance, all_units, board, terrain)["ok"]:
				return moved
	var empty: Array[Vector2] = []
	return empty


## Apply a legal charge move: moves the models and marks the unit as having charged, which
## makes it a Fights First unit until the end of the turn.
static func apply_move(unit: UnitState, new_positions: Array[Vector2]) -> void:
	for i in range(new_positions.size()):
		unit.models[i]["pos"] = new_positions[i]
	unit.charged = true


static func _ends_closer(from: Vector2, to: Vector2, radius: float, targets: Array[UnitState]) -> bool:
	return _nearest_gap(to, radius, targets) < _nearest_gap(from, radius, targets) - 0.0001


static func _nearest_gap(p: Vector2, radius: float, targets: Array[UnitState]) -> float:
	var best: float = INF
	for t in targets:
		for n in t.models:
			best = minf(best, Geo.edge_distance(p, radius, n["pos"], t.base_radius))
	return best


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
