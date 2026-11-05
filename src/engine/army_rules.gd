class_name ArmyRules
extends RefCounted
## Faction army rules that need more than one line in the attack code. Rule source and
## assumptions: design/rules/keyword-conversion.md.

const SYNAPSE_RANGE := 6.0
const REVIVE_GAP := 0.1


## True while a TYRANIDS unit is within 6" of a friendly SYNAPSE model, itself included.
static func in_synapse(unit: UnitState, units: Array) -> bool:
	return unit.has_keyword("TYRANIDS") and near_synapse_of(unit, units, unit.owner)


## True if [param unit] is within 6" of a SYNAPSE model belonging to [param side].
static func near_synapse_of(unit: UnitState, units: Array, side: int) -> bool:
	for other: UnitState in units:
		if other.owner == side and other.has_keyword("SYNAPSE") and not other.is_destroyed():
			if other == unit or unit.gap_to(other) <= SYNAPSE_RANGE:
				return true
	return false


## Heal up to [param amount] wounds: wounded models first, then destroyed models come back with
## 1 wound, up to the unit's starting strength. Returns the wounds healed.
static func reanimate(unit: UnitState, amount: int, units: Array, board: Rect2) -> int:
	var healed: int = 0
	for m in unit.models:
		var room: int = mini(unit.wounds_per_model - int(m["wounds"]), amount - healed)
		if room > 0:
			m["wounds"] = int(m["wounds"]) + room
			healed += room
	while healed < amount and unit.model_count() < unit.starting_strength and not unit.is_destroyed():
		var spot: Variant = _free_spot(unit, units, board)
		if spot == null:
			break
		unit.models.append({"pos": spot, "wounds": 1, "character": false})
		healed += 1
	return healed


## A place touching the unit's formation, clear of every model and of enemy engagement range.
static func _free_spot(unit: UnitState, units: Array, board: Rect2) -> Variant:
	var step: float = unit.base_radius * 2.0 + REVIVE_GAP
	for m in unit.models:
		for k in range(8):
			var angle: float = TAU * float(k) / 8.0
			var at: Vector2 = (m["pos"] as Vector2) + Vector2(cos(angle), sin(angle)) * step
			if board.has_point(at) and _is_clear(at, unit, units):
				return at
	return null


static func _is_clear(at: Vector2, unit: UnitState, units: Array) -> bool:
	for other: UnitState in units:
		var limit: float = 0.0 if other.owner == unit.owner else UnitRules.ENGAGEMENT_RANGE
		for m in other.models:
			if Geo.edge_distance(at, unit.base_radius, m["pos"], other.base_radius) < limit:
				return false
	return true
