class_name Missions
extends RefCounted
## Objective control and victory-point scoring, driven by a scenario dictionary.


## Total OC of a player's units with a model within [param range_in] of the objective
## (battle-shocked units contribute 0).
static func control_total(objective_pos: Vector2, units: Array, player: int, range_in: float) -> int:
	var total: int = 0
	for u in units:
		if u.owner != player or u.battle_shocked:
			continue
		for m in u.models:
			if Geo.edge_distance(m["pos"], u.base_radius, objective_pos, 0.0) <= range_in:
				total += u.objective_control
				break
	return total


## Who controls the objective: player id, or -1 if tied or empty (contested).
static func controller(objective_pos: Vector2, units: Array, range_in: float) -> int:
	var a: int = control_total(objective_pos, units, 0, range_in)
	var b: int = control_total(objective_pos, units, 1, range_in)
	if a > b:
		return 0
	if b > a:
		return 1
	return -1


## VP the player scores now, given how many objectives they control.
## [param moment] is "end_of_command_phase" or "end_of_turn".
static func vp_for_turn(scenario: Dictionary, round_no: int, objectives_held: int, is_second_player: bool, moment: String) -> int:
	var s: Dictionary = scenario["scoring"]
	if round_no < int(s["first_scoring_round"]) or round_no > int(s["last_scoring_round"]):
		return 0
	var due: String = str(s["score_at"])
	if round_no == int(s["last_scoring_round"]) and is_second_player:
		due = "end_of_turn"
	if moment != due:
		return 0
	return mini(objectives_held * int(s["per_objective_vp"]), int(s["max_vp_per_turn"]))
