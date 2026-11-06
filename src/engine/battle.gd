class_name Battle
extends RefCounted
## One battle: units, turn flow, scores and the commands a player (human or AI) can issue.
##
## All changes to the game go through the cmd_* methods, which check the rules and return
## {"ok": bool, "reason": String, ...}. Every change is also recorded in [member events] as
## plain data, so a UI can show it without owning any game state.

const DEADLY_DEMISE_RANGE := 6.0
const REANIMATION_DICE := "D3"
const SAVE_VERSION := 1
const SAVE_KEYS: Array[String] = ["version", "scenario", "units", "unit_names", "flow", "dice", "vp", "turn_no",
	"ai_sides", "events", "log", "fight_stage", "counter", "reanimate_models", "moved", "shot", "charge", "charge_done",
	"advance_roll", "piled", "consolidated", "eligible_to_fight", "shadow_used", "observers", "spotted", "fight_seq", "undo"]

var _shadow_used: Array[int] = []
var _observers: Array = []
var _spotted: Dictionary = {}            # target -> the Observer that marked it

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
## Reanimation Protocols brings destroyed models back. False means it heals wounds only.
var reanimate_models: bool = true
## Unit id -> name for every unit in the battle, destroyed ones included.
var unit_names: Dictionary = {}

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
var _undo: Dictionary = {}         # the last confirmed move, see cmd_undo_move


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
		var u: UnitState = UnitState.from_dict(army["units"][i], "%s_%d" % [zone_key, _counter], side, Vector2(x, y))
		units.append(u)
		unit_names[u.id] = u.unit_name


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


## Reanimation Protocols: at the end of your Command phase, each unit with the rule heals D3 wounds.
func _reanimation(side: int) -> void:
	for u in living(side):
		if u.faction_abilities.has("REANIMATION PROTOCOLS"):
			var healed: int = ArmyRules.reanimate(u, dice.roll(REANIMATION_DICE), units, board, reanimate_models)
			if healed > 0:
				_emit("reanimated", side, {"unit": u.id, "wounds": healed})


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
	_undo = {}
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
	_observers.clear()
	_spotted.clear()
	_reanimation(side)
	_score("end_of_command_phase")
	if ai_sides[side]:
		SimpleAI.command(self, side)


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
	var flags: Dictionary = {"advanced": u.advanced, "fell_back": u.fell_back, "max_model_move": u.max_model_move}
	UnitRules.apply_move(u, positions, mode)
	_moved.append(u)
	_emit("move", u.owner, {"unit": u.id, "mode": mode, "from": before, "to": positions.duplicate()})
	_undo = {"unit": u, "from": before, "flags": flags, "events": events.size()}
	return r


## Why the last move cannot be undone, or "" if it can.
func _undo_problem() -> String:
	if is_over():
		return "the battle is over"
	if flow.phase() != "movement":
		return "moves can only be undone in the Movement phase"
	if _undo.is_empty():
		return "there is no move to undo"
	if events.size() != int(_undo["events"]):
		return "something else has happened since that move"
	if _advance_roll.has(_undo["unit"]):
		return "a move with a dice roll cannot be undone"
	return ""


func can_undo_move() -> bool:
	return _undo_problem() == ""


## Take back the last confirmed move, if nothing has happened since and no roll was involved.
## The move stays in [member events], followed by an "undo_move" event, so a log reads in order.
func cmd_undo_move() -> Dictionary:
	var problem: String = _undo_problem()
	if problem != "":
		return _no(problem)
	var u: UnitState = _undo["unit"]
	var before: Array[Vector2] = _undo["from"]
	var moved_to: Array[Vector2] = _positions(u)
	for i in range(before.size()):
		u.models[i]["pos"] = before[i]
	u.advanced = bool(_undo["flags"]["advanced"])
	u.fell_back = bool(_undo["flags"]["fell_back"])
	u.max_model_move = float(_undo["flags"]["max_model_move"])
	_moved.erase(u)
	_undo = {}
	_emit("undo_move", u.owner, {"unit": u.id, "from": moved_to, "to": before.duplicate()})
	return _yes()


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
	for entry in Combat.shoot_plan(u, target, units, _shoot_ctx_for(u, target)):
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
	var result: Dictionary = Combat.shoot(u, target, units, dice, _shoot_ctx_for(u, target))
	_shot.append(u)
	_emit("shoot", u.owner, {"unit": u.id, "target": target.id, "reports": result["reports"],
		"hazard_wounds": result["hazard_wounds"]})
	remove_destroyed()
	return {"ok": true, "reason": "", "result": result}


# ---------------------------------------------------------------- army rules

## Shadow in the Warp: once per battle, in a Command phase, with a unit that has the rule alive.
func can_unleash_shadow(side: int) -> bool:
	if _shadow_used.has(side) or is_over() or flow.phase() != "command":
		return false
	return living(side).any(func(u: UnitState) -> bool: return u.faction_abilities.has("SHADOW IN THE WARP"))


## Every enemy unit tests Battle-shock, at -1 if within 6" of one of your SYNAPSE units.
func cmd_shadow_in_the_warp(side: int) -> Dictionary:
	if not can_unleash_shadow(side):
		return _no("the Shadow in the Warp is not available")
	_shadow_used.append(side)
	var shocked: Array[String] = []
	for u in living(1 - side):
		var modifier: int = -1 if ArmyRules.near_synapse_of(u, units, side) else 0
		if not UnitRules.battle_shock_roll(u, dice, units, modifier):
			shocked.append(u.id)
	_emit("shadow_in_the_warp", side, {"shocked": shocked})
	return _yes()


## For the Greater Good: a unit with the rule that has not shot can become an Observer.
func can_observe(u: UnitState) -> bool:
	return flow.phase() == "shooting" and u.owner == flow.active_player and not is_over() \
			and u.faction_abilities.has("FOR THE GREATER GOOD") and not _observers.has(u) and not _shot.has(u) \
			and not u.battle_shocked and not u.has_keyword("FORTIFICATION")


func can_be_spotted(target: UnitState) -> bool:
	return not _spotted.has(target) and not target.is_destroyed()


## Mark a visible enemy as this Observer's Spotted unit until the end of the phase.
func cmd_mark_spotted(observer: UnitState, target: UnitState) -> Dictionary:
	if not can_observe(observer):
		return _no("this unit cannot be an Observer now")
	if target.owner == observer.owner or not can_be_spotted(target):
		return _no("that unit cannot be marked")
	var seen: bool = terrain.is_empty()
	for m in observer.models:
		seen = seen or Visibility.unit_visible_to_model(m["pos"], observer.base_radius, target, turn_no, terrain)
	if not seen:
		return _no("that unit is not visible")
	_observers.append(observer)
	_spotted[target] = observer
	_emit("spotted", observer.owner, {"unit": observer.id, "target": target.id})
	return _yes()


## The context for this unit shooting this target, including Guided bonuses.
func _shoot_ctx_for(u: UnitState, target: UnitState) -> Dictionary:
	var ctx: Dictionary = _shoot_ctx()
	if _spotted.has(target) and u.faction_abilities.has("FOR THE GREATER GOOD") and not _observers.has(u):
		ctx["guided_bonus"] = 1
		ctx["ignores_cover"] = (_spotted[target] as UnitState).has_keyword("MARKERLIGHT")
	return ctx


func _fight_ctx(u: UnitState) -> Dictionary:
	return {"strength_bonus": 1} if ArmyRules.in_synapse(u, units) else {}


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
	for entry in Combat.fight_plan(u, target, _fight_ctx(u)):
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
	var result: Dictionary = Combat.fight(u, target, dice, _fight_ctx(u))
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


# ---------------------------------------------------------------- save and resume

## Everything needed to carry on from this exact moment, as plain data that survives JSON (write
## it with full precision, see [SaveFile]). Units are stored by id wherever one unit refers to another.
func to_save() -> Dictionary:
	var charge_rows: Dictionary = {}
	for u: UnitState in _charge:
		charge_rows[u.id] = {"roll": _charge[u]["roll"], "targets": Battle._ids(_charge[u]["targets"])}
	var advance_rows: Dictionary = {}
	for u: UnitState in _advance_roll:
		advance_rows[u.id] = _advance_roll[u]
	var spotted_rows: Dictionary = {}
	for t: UnitState in _spotted:
		spotted_rows[t.id] = (_spotted[t] as UnitState).id
	var event_rows: Array = []
	for e in events:
		event_rows.append(Battle._event_to_save(e))
	var unit_rows: Array = []
	for u: UnitState in units:
		unit_rows.append(u.to_save())
	var undo_row: Dictionary = {}
	if not _undo.is_empty():
		undo_row = {"unit": (_undo["unit"] as UnitState).id, "from": Battle._points_to_save(_undo["from"]),
			"flags": _undo["flags"].duplicate(), "events": _undo["events"]}
	return {"version": SAVE_VERSION, "scenario": scenario.duplicate(true), "units": unit_rows,
		"unit_names": unit_names.duplicate(), "flow": flow.to_save(), "dice": dice.to_save(), "vp": vp.duplicate(),
		"turn_no": turn_no, "ai_sides": ai_sides.duplicate(), "events": event_rows, "log": log.duplicate(),
		"fight_stage": fight_stage, "counter": _counter, "reanimate_models": reanimate_models,
		"moved": Battle._ids(_moved), "shot": Battle._ids(_shot), "charge": charge_rows,
		"charge_done": Battle._ids(_charge_done), "advance_roll": advance_rows, "piled": Battle._ids(_piled),
		"consolidated": Battle._ids(_consolidated), "eligible_to_fight": Battle._ids(_eligible_to_fight),
		"shadow_used": _shadow_used.duplicate(), "observers": Battle._ids(_observers), "spotted": spotted_rows,
		"fight_seq": {} if _seq == null else _seq.to_save(), "undo": undo_row}


## Rebuild a battle from [method to_save]. Returns null if [param data] is not a save this version can read.
static func from_save(data: Dictionary) -> Battle:
	if int(data.get("version", 0)) != SAVE_VERSION or not data.has_all(SAVE_KEYS):
		return null
	var empty: Array = [{"units": []}, {"units": []}]
	var b := Battle.new(data["scenario"], empty, 1)
	for row in data["units"]:
		b.units.append(UnitState.from_save(row))
	b.unit_names = data["unit_names"].duplicate()
	b.flow = TurnFlow.from_save(data["flow"])
	b.dice = Dice.from_save(data["dice"])
	for side in range(2):
		b.vp[side] = int(data["vp"][side])
		b.ai_sides[side] = bool(data["ai_sides"][side])
	b.turn_no = int(data["turn_no"])
	for row in data["events"]:
		b.events.append(Battle._event_from_save(row))
	b.log.assign(data["log"])
	b.fight_stage = str(data["fight_stage"])
	b._counter = int(data["counter"])
	b.reanimate_models = bool(data["reanimate_models"])
	b._moved = b._units_of(data["moved"])
	b._shot = b._units_of(data["shot"])
	b._charge_done = b._units_of(data["charge_done"])
	b._piled = b._units_of(data["piled"])
	b._consolidated = b._units_of(data["consolidated"])
	b._eligible_to_fight = b._units_of(data["eligible_to_fight"])
	b._observers = b._units_of(data["observers"])
	for id in data["charge"]:
		var targets: Array[UnitState] = []
		targets.assign(b._units_of(data["charge"][id]["targets"]))
		b._charge[b.unit_by_id(id)] = {"roll": int(data["charge"][id]["roll"]), "targets": targets}
	for id in data["advance_roll"]:
		b._advance_roll[b.unit_by_id(id)] = int(data["advance_roll"][id])
	for side in data["shadow_used"]:
		b._shadow_used.append(int(side))
	for id in data["spotted"]:
		b._spotted[b.unit_by_id(id)] = b.unit_by_id(data["spotted"][id])
	if not (data["fight_seq"] as Dictionary).is_empty():
		b._seq = FightSequencer.from_save(data["fight_seq"], b.units)
	if not (data["undo"] as Dictionary).is_empty():
		var undo: Dictionary = data["undo"]
		b._undo = {"unit": b.unit_by_id(undo["unit"]), "from": Battle._points_from_save(undo["from"]),
			"flags": undo["flags"].duplicate(), "events": int(undo["events"])}
	return b


func _units_of(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var u: UnitState = unit_by_id(id)
		if u != null:
			out.append(u)
	return out


static func _ids(list: Array) -> Array:
	var out: Array = []
	for u: UnitState in list:
		out.append(u.id)
	return out


static func _points_to_save(points: Array) -> Array:
	var out: Array = []
	for p: Vector2 in points:
		out.append([p.x, p.y])
	return out


static func _points_from_save(rows: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for r in rows:
		out.append(Vector2(float(r[0]), float(r[1])))
	return out


static func _event_to_save(e: Dictionary) -> Dictionary:
	var out: Dictionary = e.duplicate(true)
	for key in ["from", "to"]:
		if out.has(key):
			out[key] = Battle._points_to_save(e[key])
	return out


static func _event_from_save(row: Dictionary) -> Dictionary:
	var out: Dictionary = row.duplicate(true)
	out["turn"] = int(row["turn"])
	out["side"] = int(row["side"])
	for key in ["from", "to"]:
		if out.has(key):
			out[key] = Battle._points_from_save(row[key])
	return out


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
