class_name Battle
extends RefCounted
## Holds one battle: the units, the turn flow, scores. The scenario and armies come from data
## files; [method play_turn] runs one player turn using [SimpleAI].

var scenario: Dictionary
var units: Array = []
var flow: TurnFlow
var dice: Dice
var vp: Array[int] = [0, 0]
var board: Rect2
var objectives: Array[Vector2] = []
var objective_range: float = 3.0
var log: Array[String] = []
var terrain: Array = []
var turn_no: int = 0

var _counter: int = 0


func _init(scenario_data: Dictionary, armies: Array, seed_value: int) -> void:
	scenario = scenario_data
	dice = Dice.new(seed_value)
	flow = TurnFlow.new(int(scenario["battle_rounds"]))
	board = Rect2(0, 0, float(scenario["battlefield"]["width_in"]), float(scenario["battlefield"]["height_in"]))
	objective_range = float(scenario["objective_range_in"])
	for o in scenario["objectives"]:
		objectives.append(Vector2(float(o["pos"][0]), float(o["pos"][1])))
	for t in scenario.get("terrain", []):
		terrain.append(TerrainArea.from_dict(t))
	for side in range(2):
		_deploy(side, armies[side])


## Place a side's units in a column inside its deployment zone.
func _deploy(side: int, army: Dictionary) -> void:
	var zone_key: String = "attacker" if side == 0 else "defender"
	var r: Array = scenario["deployment_zones"][zone_key]["rect"]
	var x: float = float(r[0]) + (3.0 if side == 0 else float(r[2]) - 9.0)
	var count: int = army["units"].size()
	for i in range(count):
		var y: float = float(r[1]) + 3.0 + float(i) * (board.size.y - 6.0) / float(maxi(count, 1))
		_counter += 1
		var u: UnitState = UnitState.from_dict(army["units"][i], "%s_%d" % [zone_key, _counter], side, Vector2(x, y))
		units.append(u)


func living(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u.owner == side and not u.is_destroyed():
			out.append(u)
	return out


func remove_destroyed() -> void:
	units = units.filter(func(u: UnitState) -> bool: return not u.is_destroyed())


func objectives_held(side: int) -> int:
	var n: int = 0
	for o in objectives:
		if Missions.controller(o, units, objective_range) == side:
			n += 1
	return n


func score(moment: String) -> void:
	var side: int = flow.active_player
	var gained: int = Missions.vp_for_turn(scenario, flow.round_no, objectives_held(side), side == 1, moment)
	vp[side] += gained


func is_over() -> bool:
	return flow.finished or living(0).is_empty() or living(1).is_empty()


## Play every phase of the current player turn with the built-in AI.
func play_turn() -> void:
	turn_no += 1
	var side: int = flow.active_player
	var rnd: int = flow.round_no
	# Command
	flow.start_command_phase(units, dice)
	score("end_of_command_phase")
	flow.advance()
	# Movement
	SimpleAI.movement(self, side)
	flow.advance()
	# Shooting
	SimpleAI.shooting(self, side)
	remove_destroyed()
	flow.advance()
	# Charge
	SimpleAI.charging(self, side)
	flow.advance()
	# Fight
	SimpleAI.fighting(self, side)
	remove_destroyed()
	# End of turn
	score("end_of_turn")
	for u in units:
		if u.owner == side:
			u.reset_turn_flags()
	log.append("round %d player %d done: VP %d-%d" % [rnd, side, vp[0], vp[1]])
	flow.advance()


## Play the whole battle. Returns {"vp": [a, b], "survivors": [a, b], "rounds": n}.
func play_all() -> Dictionary:
	var guard: int = 0
	while not is_over() and guard < 40:
		play_turn()
		guard += 1
	return {"vp": vp.duplicate(), "survivors": [living(0).size(), living(1).size()], "rounds": flow.round_no}
