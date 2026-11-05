class_name Visibility
extends RefCounted
## Line of sight, cover and hidden models on a flat 2D board (core rules 13.07 to 13.11).
##
## Approximations: lines are drawn between five sample points on each base; a model is
## "fully visible" if all sample points of the target can be seen from the attacker's centre;
## terrain height is only used for movement. Dense features are treated as solid blockers
## (13.11) at every height.

const DETECTION_RANGE := 15.0
const HIDDEN_KEYWORDS: Array[String] = ["INFANTRY", "BEASTS", "SWARM"]


static func _has_any(unit: UnitState, words: Array[String]) -> bool:
	for w in words:
		if unit.has_keyword(w):
			return true
	return false


## True if a line from [param a] to [param b] is blocked by an obscuring area (ignoring
## [param ignored_areas]) or by a solid dense feature.
static func line_blocked(a: Vector2, b: Vector2, areas: Array, ignored_areas: Array) -> bool:
	for area in areas:
		if area.has_dense():
			for f in area.features:
				if f["category"] == "dense" and Geo.segment_hits_rect(a, b, f["rect"]):
					return true
		if area.is_obscuring() and not ignored_areas.has(area) and Geo.segment_hits_rect(a, b, area.rect):
			return true
	return false


static func areas_containing(pos: Vector2, radius: float, areas: Array) -> Array:
	var out: Array = []
	for area in areas:
		if area.contains_model(pos, radius):
			out.append(area)
	return out


## Can the model at [param from] see any part of the model at [param to]?
static func model_sees(from: Vector2, from_r: float, to: Vector2, to_r: float, areas: Array) -> bool:
	var ignored: Array = areas_containing(from, from_r, areas) + areas_containing(to, to_r, areas)
	for a in Geo.sample_points(from, from_r):
		for b in Geo.sample_points(to, to_r):
			if not line_blocked(a, b, areas, ignored):
				return true
	return false


## Can the attacker see every part of the target model (13.08, "fully visible")?
static func model_fully_sees(from: Vector2, from_r: float, to: Vector2, to_r: float, areas: Array) -> bool:
	var ignored: Array = areas_containing(from, from_r, areas) + areas_containing(to, to_r, areas)
	for b in Geo.sample_points(to, to_r):
		if line_blocked(from, b, areas, ignored):
			return false
	return true


## Is the unit hidden (13.09)? Needs INFANTRY/BEASTS/SWARM in an area with dense terrain, and
## no ranged attacks this turn or the previous turn. [param turn_no] counts every player turn.
static func is_hidden(unit: UnitState, turn_no: int, areas: Array) -> bool:
	if not _has_any(unit, HIDDEN_KEYWORDS):
		return false
	if turn_no - unit.last_fired_turn <= 1:
		return false
	for m in unit.models:
		var in_dense: bool = false
		for area in areas_containing(m["pos"], unit.base_radius, areas):
			if area.has_dense():
				in_dense = true
		if not in_dense:
			return false
	return true


## Can this attacking model target/see any model of the unit, taking hidden into account?
static func unit_visible_to_model(from: Vector2, from_r: float, target: UnitState, turn_no: int, areas: Array) -> bool:
	var hidden: bool = is_hidden(target, turn_no, areas)
	for n in target.models:
		if hidden and Geo.edge_distance(from, from_r, n["pos"], target.base_radius) > DETECTION_RANGE:
			continue
		if model_sees(from, from_r, n["pos"], target.base_radius, areas):
			return true
	return false


## Benefit of cover against attacks from an attacking model at [param from] (13.08): every
## model in the target must be INFANTRY/BEASTS/SWARM within a terrain area, or not fully visible.
static func has_cover(from: Vector2, from_r: float, target: UnitState, areas: Array) -> bool:
	var infantry_like: bool = _has_any(target, HIDDEN_KEYWORDS)
	for n in target.models:
		var in_area: bool = not areas_containing(n["pos"], target.base_radius, areas).is_empty()
		if infantry_like and in_area:
			continue
		if not model_fully_sees(from, from_r, n["pos"], target.base_radius, areas):
			continue
		return false
	return true
