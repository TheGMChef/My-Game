class_name Battle
extends RefCounted
## One battle: units, turn flow, scores and the commands a player (human or AI) can issue.
##
## All changes to the game go through the cmd_* methods, which check the rules and return
## {"ok": bool, "reason": String, ...}. Every change is also recorded in [member events] as
## plain data, so a UI can show it without owning any game state.

const DEADLY_DEMISE_RANGE := 6.0

var scenario: Dictionary
var units: Array = []
var flow: TurnFlow
var dice: Dice
var vp: Array[int] = [0, 0]
var board: Rect2
var objectives: Array[Vector2] = []
var objective_range: float = 3.0
var terrain: Array = []
var turn_no: int = 0
## Which sides are driven by [SimpleAI].
var ai_sides: Array[bool] = [true, true]
## Plain-data record of everything that happened. Each event has "type", "turn", "side".
var events: Array[Dictionary] = []
var log: Array[String] = []
## "pile_in", "fight" or "consolidate" while in the Fight phase, else "".
var fight_stage: String = ""

var _counter: int = 0
var _moved: Array = []
var _shot: Array = []
var _charge: Dictionary = {}       # unit -> {"roll": int, "targets": Array[UnitState]}
var _charge_done: Array = []
var _advance_roll: Dictionary = {} # unit -> int
var _piled: Array = []
var _consolidated: Array = []
var _eligible_to_fight: Array = []
var _seq: FightSequencer


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


# ---------------------------------------------------------------- setup and queries

func _deploy(side: int, army: Dictionary) -> void:
	var zone_key: String = "attacker" if side == 0 else "defender"
	var r: Array = scenario["deployment_zones"][zone_key]["rect"]
	var x: float = float(r[0]) + (3.0 if side == 0 else float(r[2]) - 9.0)
	var count: int = army["units"].size()
	for i in range(count):
		var y: float = float(r[1]) + 3.0 + float(i) * (board.size.y - 6.0) / float(maxi(count, 1))
		_counter += 1
		units.append(UnitState.from_dict(army["units"][i], "%s_%d" % [zone_key, _counter], side, Vector2(x, y)))


func living(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u.owner == side and not u.is_destroyed():
			out.append(u)
	return out


func remove_destroyed() -> void:
	var fallen: Array = units.filter(func(u: UnitState) -> bool: return u.is_destroyed())
	for u in fallen:
		_emit("destroyed", u.owner, {"unit": u.id})
	units = units.filter(func(u: UnitState) -> bool: return not u.is_destroyed())
	for u in fallen:
		_deadly_demise(u)


## Deadly Demise X (24): on a 6, every unit within 6" takes X mortal wounds. Rolled once per
## unit, not per model. A blast can destroy another unit with the ability, which rolls in turn.
func _deadly_demise(u: UnitState) -> void:
	if u.deadly_demise == "" or dice.d6() < 6:
		return
	var wounds: int = dice.roll(u.deadly_demise)
	_emit("deadly_demise", u.owner, {"unit": u.id, "wounds": wounds})
	for other in units:
		if other.is_destroyed():
			continue
		for m in other.models:
			if Geo.edge_distance(u.last_position, u.base_radius, m["pos"], other.base_radius) <= DEADLY_DEMISE_RANGE:
				AttackResolver.mortal_wounds(other, wounds, dice)
				break
	remove_destroyed()


func unit_by_id(unit_id: String) -> UnitState:
	for u in units:
		if u.id == unit_id:
			return u
	return null


func objectives_held(side: int) -> int:
	var n: int = 0
	for o in objectives:
		if Missions.controller(o, units, objective_range) == side:
			n += 1
	return n


func phase() -> String:
	return flow.phase()


func active_player() -> int:
	return flow.active_player


func is_over() -> bool:
	return flow.finished or living(0).is_empty() or living(1).is_empty()


func has_moved(u: UnitState) -> bool:
	return _moved.has(u)


func has_shot(u: UnitState) -> bool:
	return _shot.has(u)


func charge_state(u: UnitState) -> Dictionary:
	return _charge.get(u, {})


func charge_finished(u: UnitState) -> bool:
	return _charge_done.has(u)


func advance_roll_for(u: UnitState) -> int:
	return int(_advance_roll.get(u, -1))


func has_piled_in(u: UnitState) -> bool:
	return _piled.has(u)


func has_consolidated(u: UnitState) -> bool:
	return _consolidated.has(u)


# ---------------------------------------------------------------- turn structure

## Start the active player's turn: the Command phase happens now (CP, battle-shock, scoring).
func begin_turn() -> void:
	turn_no += 1
	_moved.clear()
	_shot.clear()
	_charge.clear()
	_charge_done.clear()
	_advance_roll.clear()
	_piled.clear()
	_consolidated.clear()
	_eligible_to_fight.clear()
	fight_stage = ""
	var side: int = flow.active_player
	var before: Array = []
	for u in units:
		if u.owner == side and (u.battle_shocked or u.at_or_below_half_strength()):
			before.append(u)
	flow.start_command_phase(units, dice)
	var shocked_now: Array[String] = []
	for u in before:
		if u.battle_shocked:
			shocked_now.append(u.id)
	_emit("turn_start", side, {"round": flow.round_no, "cp": flow.command_points.duplicate(), "shocked": shocked_now})
	_score("end_of_command_phase")


## Move to the next phase (or sub-step of the Fight phase). Returns {ok, reason}.
func next_phase() -> Dictionary:
	if is_over():
		return _no("the battle is over")
	var p: String = flow.phase()
	if p == "charge":
		flow.advance()
		fight_stage = "pile_in"
		_start_fight_phase()
		_emit("phase", flow.active_player, {"phase": "fight", "stage": fight_stage})
		return _yes()
	if p == "fight":
		return _next_fight_stage()
	flow.advance()
	remove_destroyed()
	_emit("phase", flow.active_player, {"phase": flow.phase()})
	return _yes()


func _end_turn() -> void:
	var side: int = flow.active_player
	_score("end_of_turn")
	for u in units:
		if u.owner == side:
			u.reset_turn_flags()
	log.append("round %d player %d done: VP %d-%d" % [flow.round_no, side, vp[0], vp[1]])
	_emit("turn_end", side, {"vp": vp.duplicate()})
	fight_stage = ""
	flow.advance()


func _score(moment: String) -> void:
	var side: int = flow.active_player
	var held: int = objectives_held(side)
	var gained: int = Missions.vp_for_turn(scenario, flow.round_no, held, side == 1, moment)
	vp[side] += gained
	if gained > 0:
		_emit("score", side, {"vp": gained, "objectives": held, "moment": moment})


# ---------------------------------------------------------------- movement phase

func cmd_roll_advance(u: UnitState) -> Dictionary:
	var check: Dictionary = _own_unit_in_phase(u, "movement")
	if not check["ok"]:
		return check
	if _moved.has(u):
		return _no("this unit has already moved")
	if UnitRules.engaged(u, units):
		return _no("an engaged unit cannot advance")
	if not _advance_roll.has(u):
		_advance_roll[u] = dice.d6()
		_emit("advance_roll", u.owner, {"unit": u.id, "roll": _advance_roll[u]})
	return {"ok": true, "reason": "", "roll": _advance_roll[u]}


## Check a move without making it. Same rules as [method cmd_move].
func preview_move(u: UnitState, positions: Array[Vector2], mode: String) -> Dictionary:
	var check: Dictionary = _own_unit_in_phase(u, "movement")
	if not check["ok"]:
		return check
	if _moved.has(u):
		return _no("this unit has already moved")
	var roll: int = 0
	if mode == "advance":
		if not _advance_roll.has(u):
			return _no("roll the advance die first")
		roll = int(_advance_roll[u])
	return UnitRules.check_move(u, positions, mode, units, board, roll, terrain)


func cmd_move(u: UnitState, positions: Array[Vector2], mode: String) -> Dictionary:
	var r: Dictionary = preview_move(u, positions, mode)
	if not r["ok"]:
		return r
	var before: Array[Vector2] = _positions(u)
	UnitRules.apply_move(u, positions, mode)
	_moved.append(u)
	_emit("move", u.owner, {"unit": u.id, "mode": mode, "from": before, "to": positions.duplicate()})
	return r


func cmd_hold(u: UnitState) -> Dictionary:
	var check: Dictionary = _own_unit_in_phase(u, "movement")
	if not check["ok"]:
		return check
	_moved.append(u)
	_emit("hold", u.owner, {"unit": u.id})
	return _yes()


# ---------------------------------------------------------------- shooting phase

func _shoot_ctx() -> Dictionary:
	return {"terrain": terrain, "turn_no": turn_no}


## What shooting would involve, with exact odds per weapon. Does not roll.
func shoot_preview(u: UnitState, target: UnitState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in Combat.shoot_plan(u, target, units, _shoot_ctx()):
		out.append({"weapon": entry["weapon"], "models": entry["models"], "ctx": entry["ctx"],
			"odds": AttackOdds.compute(entry["weapon"], target, entry["ctx"])})
	return out


func cmd_shoot(u: UnitState, target: UnitState) -> Dictionary:
	var check: Dictionary = _own_unit_in_phase(u, "shooting")
	if not check["ok"]:
		return check
	if _shot.has(u):
		return _no("this unit has already shot")
	if target.owner == u.owner or target.is_destroyed():
		return _no("choose an enemy unit")
	if shoot_preview(u, target).is_empty():
		return _no("no weapon can reach and see that unit")
	var result: Dictionary = Combat.shoot(u, target, units, dice, _shoot_ctx())
	_shot.append(u)
	_emit("shoot", u.owner, {"unit": u.id, "target": target.id, "reports": result["reports"],
		"hazard_wounds": result["hazard_wounds"]})
	remove_destroyed()
	return {"ok": true, "reason": "", "result": result}


# ---------------------------------------------------------------- charge phase

func cmd_declare_charge(u: UnitState) -> Dictionary:
	var check: Dictionary = _own_unit_in_phase(u, "charge")
	if not check["ok"]:
		return check
	if _charge.has(u):
		return _no("this unit has already declared a charge")
	var eligible: Dictionary = ChargeRules.eligible(u, units)
	if not eligible["ok"]:
		return eligible
	var roll: int = ChargeRules.charge_roll(dice)
	var targets: Array[UnitState] = ChargeRules.possible_targets(u, units, roll)
	_charge[u] = {"roll": roll, "targets": targets}
	_emit("charge_roll", u.owner, {"unit": u.id, "roll": roll, "targets": targets.map(func(t: UnitState) -> String: return t.id)})
	if targets.is_empty():
		_charge_done.append(u)
	return {"ok": true, "reason": "", "roll": roll, "targets": targets}


func preview_charge(u: UnitState, positions: Array[Vector2], targets: Array[UnitState]) -> Dictionary:
	if not _charge.has(u) or _charge_done.has(u):
		return _no("declare a charge first")
	return ChargeRules.check_move(u, positions, targets, int(_charge[u]["roll"]), units, board, terrain)


func cmd_charge_move(u: UnitState, positions: Array[Vector2], targets: Array[UnitState]) -> Dictionary:
	var r: Dictionary = preview_charge(u, positions, targets)
	if not r["ok"]:
		return r
	var before: Array[Vector2] = _positions(u)
	ChargeRules.apply_move(u, positions)
	_charge_done.append(u)
	_emit("charge_move", u.owner, {"unit": u.id, "from": before, "to": positions.duplicate()})
	return r


## Give up on a declared charge: the unit does not move.
func cmd_charge_fail(u: UnitState) -> Dictionary:
	if not _charge.has(u) or _charge_done.has(u):
		return _no("no charge to give up")
	_charge_done.append(u)
	_emit("charge_failed", u.owner, {"unit": u.id})
	return _yes()


# ---------------------------------------------------------------- fight phase

func _start_fight_phase() -> void:
	_piled.clear()
	_consolidated.clear()
	_eligible_to_fight.clear()
	_seq = null


func _next_fight_stage() -> Dictionary:
	match fight_stage:
		"pile_in":
			fight_stage = "fight"
			_seq = FightSequencer.new()
			_seq.begin(units, flow.active_player)
			_eligible_to_fight = units.filter(func(x: UnitState) -> bool: return UnitRules.engaged(x, units) or x.charged)
			_emit("phase", flow.active_player, {"phase": "fight", "stage": fight_stage})
			return _yes()
		"fight":
			if _seq != null and not _seq.finished:
				return _no("units are still to fight")
			fight_stage = "consolidate"
			_emit("phase", flow.active_player, {"phase": "fight", "stage": fight_stage})
			return _yes()
		"consolidate":
			remove_destroyed()
			_end_turn()
			return _yes()
	return _no("not in the Fight phase")


func fight_chooser() -> int:
	return _seq.chooser if _seq != null and not _seq.finished else -1


func fight_options() -> Array[UnitState]:
	if _seq == null or _seq.finished:
		return []
	return _seq.options()


func fighting_first() -> bool:
	return _seq != null and _seq.in_fights_first_step()


func fight_finished() -> bool:
	return _seq != null and _seq.finished


func can_pile_in(u: UnitState) -> bool:
	return fight_stage == "pile_in" and not _piled.has(u) and MeleeMoves.can_pile_in(u, units)


func preview_pile_in(u: UnitState, positions: Array[Vector2]) -> Dictionary:
	if fight_stage != "pile_in":
		return _no("it is not the pile-in step")
	if _piled.has(u):
		return _no("this unit has already piled in")
	return MeleeMoves.check_pile_in(u, positions, units, board, terrain)


func cmd_pile_in(u: UnitState, positions: Array[Vector2]) -> Dictionary:
	var r: Dictionary = preview_pile_in(u, positions)
	if not r["ok"]:
		return r
	var before: Array[Vector2] = _positions(u)
	for i in range(positions.size()):
		u.models[i]["pos"] = positions[i]
	_piled.append(u)
	_emit("pile_in", u.owner, {"unit": u.id, "from": before, "to": positions.duplicate()})
	return r


func fight_preview(u: UnitState, target: UnitState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in Combat.fight_plan(u, target, {}):
		out.append({"weapon": entry["weapon"], "models": entry["models"], "ctx": entry["ctx"],
			"odds": AttackOdds.compute(entry["weapon"], target, entry["ctx"])})
	return out


func cmd_fight(u: UnitState, target: UnitState) -> Dictionary:
	if fight_stage != "fight" or _seq == null:
		return _no("it is not the fight step")
	if not fight_options().has(u):
		return _no("this unit cannot be chosen to fight right now")
	if target.owner == u.owner or target.is_destroyed() or fight_preview(u, target).is_empty():
		return _no("choose an enemy unit this unit is engaged with")
	_seq.select(u)
	var result: Dictionary = Combat.fight(u, target, dice, {})
	_emit("fight", u.owner, {"unit": u.id, "target": target.id, "reports": result["reports"],
		"hazard_wounds": result["hazard_wounds"]})
	remove_destroyed()
	_seq.refresh()
	return {"ok": true, "reason": "", "result": result}


## A unit with no enemy to hit still has to be selected, so the sequence can move on.
func cmd_fight_skip(u: UnitState) -> Dictionary:
	if fight_stage != "fight" or _seq == null or not fight_options().has(u):
		return _no("this unit cannot be chosen to fight right now")
	_seq.select(u)
	_emit("fight_skipped", u.owner, {"unit": u.id})
	_seq.refresh()
	return _yes()


func can_consolidate(u: UnitState) -> bool:
	return fight_stage == "consolidate" and not _consolidated.has(u) and _eligible_to_fight.has(u) and not u.is_destroyed()


func preview_consolidate(u: UnitState, positions: Array[Vector2]) -> Dictionary:
	if not can_consolidate(u):
		return _no("this unit cannot consolidate")
	return MeleeMoves.check_consolidation(u, positions, units, board, objectives, objective_range, terrain)


func cmd_consolidate(u: UnitState, positions: Array[Vector2]) -> Dictionary:
	var r: Dictionary = preview_consolidate(u, positions)
	if not r["ok"]:
		return r
	var before: Array[Vector2] = _positions(u)
	for i in range(positions.size()):
		u.models[i]["pos"] = positions[i]
	_consolidated.append(u)
	_emit("consolidate", u.owner, {"unit": u.id, "from": before, "to": positions.duplicate()})
	return r


# ---------------------------------------------------------------- AI and whole-battle helpers

## Let [SimpleAI] act for the current phase of the active player (movement, shooting, charge).
func ai_run_phase() -> void:
	match flow.phase():
		"movement":
			SimpleAI.movement(self, flow.active_player)
		"shooting":
			SimpleAI.shooting(self, flow.active_player)
		"charge":
			SimpleAI.charging(self, flow.active_player)


## If the fight chooser is an AI side, pick and resolve one fight. Returns true if it acted.
func ai_fight_step() -> bool:
	var who: int = fight_chooser()
	if who < 0 or not ai_sides[who]:
		return false
	SimpleAI.fight_one(self, who)
	return true


## Play the whole current turn for AI sides. A human side in the Fight phase must be handled by the caller.
func play_turn() -> void:
	begin_turn()
	for p in ["command", "movement", "shooting", "charge"]:
		if p != "command":
			ai_run_phase()
		next_phase()
	# now in the fight phase, pile-in stage
	next_phase()
	var guard: int = 0
	while fight_chooser() >= 0 and guard < 60:
		guard += 1
		if not ai_fight_step():
			break
	next_phase()  # fight -> consolidate
	next_phase()  # consolidate -> end turn


## Play the whole battle with both sides driven by AI. Returns {"vp", "survivors", "rounds"}.
func play_all() -> Dictionary:
	var guard: int = 0
	while not is_over() and guard < 40:
		play_turn()
		guard += 1
	return {"vp": vp.duplicate(), "survivors": [living(0).size(), living(1).size()], "rounds": flow.round_no}


# ---------------------------------------------------------------- helpers

func _own_unit_in_phase(u: UnitState, wanted_phase: String) -> Dictionary:
	if is_over():
		return _no("the battle is over")
	if flow.phase() != wanted_phase:
		return _no("it is the %s phase" % flow.phase())
	if u.owner != flow.active_player:
		return _no("it is not that player's turn")
	if u.is_destroyed():
		return _no("that unit is destroyed")
	return _yes()


func _positions(u: UnitState) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"])
	return out


func _emit(type: String, side: int, data: Dictionary) -> void:
	var e: Dictionary = {"type": type, "turn": turn_no, "side": side}
	e.merge(data)
	events.append(e)


static func _yes() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
