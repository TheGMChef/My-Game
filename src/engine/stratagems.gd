class_name Stratagems
extends RefCounted
## The core stratagems as data, plus who can use them and on what (core rules 15).
## See design/rules/stratagems.md for the rules in brief and the assumptions.
##
## [Battle] owns the state and the effects. This class only answers questions: which options a
## side has in a window, and why a stratagem is unavailable. An option is plain data:
## {"id", "window", "cost", "unit": unit id, "target": unit id or "", "mode": ""}.

# Windows a stratagem can be used in.
const W_ADVANCE := "advance_roll"          ## just after your unit's Advance roll
const W_CHARGE := "charge_roll"            ## just after your unit's charge roll
const W_CHARGE_MOVED := "charge_moved"     ## just after your unit's charge move
const W_SHOOTING := "shooting"             ## your Shooting phase
const W_FIGHT_SELECTED := "fight_selected" ## your unit has been picked to fight
const W_SHOCK_BEFORE := "shock_before"     ## just before a battle-shock roll
const W_SHOCK_AFTER := "shock_after"       ## just after a failed battle-shock roll
const W_END_MOVEMENT := "end_movement"     ## end of the opponent's Movement phase
const W_START_SHOOTING := "start_shooting" ## start of the opponent's Shooting phase
const W_END_CHARGE := "end_charge"         ## end of the opponent's Charge phase
const W_AFTER_FIGHT := "after_fight"       ## just after an enemy unit resolved its attacks

const INTO_THE_FRAY := "into_the_fray"
const LEAP_TO_DEFEND := "leap_to_defend"
const EXPLOSIVES_RANGE := 8.0
const EXPLOSIVES_DICE := 6
const EXPLOSIVES_HIT := 4
const CRUSH_HURT := 5
const CRUSH_MAX := 6
const INTERVENTION_RANGE := 12.0
const FRAY_RANGE := 6.0
const FRAY_MAX_ROLL := 6
## The rolls Command Re-roll can reach here. Battle-shock is the brief's addition, see the design doc.
const REROLL_KINDS: Array[String] = ["advance", "charge", "battle_shock"]

## Each stratagem's name, effect and timing text are "strat.<id>.name", ".effect" and ".when".
const DEFS: Array[Dictionary] = [
	{"id": "command_reroll", "cost": 1, "windows": [W_ADVANCE, W_CHARGE, W_SHOCK_AFTER]},
	{"id": "epic_challenge", "cost": 1, "windows": [W_FIGHT_SELECTED]},
	{"id": "insane_bravery", "cost": 1, "windows": [W_SHOCK_BEFORE], "once_per_battle": true},
	{"id": "explosives", "cost": 1, "windows": [W_SHOOTING]},
	{"id": "crushing_impact", "cost": 1, "windows": [W_CHARGE_MOVED]},
	{"id": "rapid_ingress", "cost": 1, "windows": [W_END_MOVEMENT], "needs_reserves": true},
	{"id": "fire_overwatch", "cost": 1, "windows": [W_END_MOVEMENT]},
	{"id": "smokescreen", "cost": 1, "windows": [W_START_SHOOTING]},
	{"id": "heroic_intervention", "cost": 1, "windows": [W_END_CHARGE], "modes": {LEAP_TO_DEFEND: 0, INTO_THE_FRAY: 1}},
	{"id": "counteroffensive", "cost": 2, "windows": [W_AFTER_FIGHT]},
]


static func definition(id: String) -> Dictionary:
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}


## Universal Rules Updates: a rule granting a stratagem for 0CP without naming it takes 1CP off.
static func discounted_cost(cost: int, rule_names_it: bool) -> int:
	return 0 if rule_names_it else maxi(cost - 1, 0)


## Universal Rules Updates: reuse in a phase, or past a limit, needs a rule naming the stratagem.
static func may_reuse(id: String, named_by_rules: Array) -> bool:
	return named_by_rules.has(id)


## Everything [param side] can do in [param window]. [param ctx] carries the moment's details,
## such as the unit about to test.
static func options(b: Battle, side: int, window: String, ctx: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in DEFS:
		if not (d["windows"] as Array).has(window) or _blocked(b, side, d) != "":
			continue
		for o in _targets(b, side, str(d["id"]), window, ctx):
			var cost: int = int(d["cost"]) + int((d.get("modes", {}) as Dictionary).get(o.get("mode", ""), 0))
			if cost <= b.command_points(side):
				o["id"] = d["id"]
				o["window"] = window
				o["cost"] = cost
				out.append(o)
	return out


## One row per stratagem for the Stratagems tab: {"id", "cost", "options", "reason"}. An empty
## "options" array means it is greyed, and "reason" is the string key that says why.
static func overview(b: Battle, side: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var now: Array[String] = b.windows_now(side)
	for d in DEFS:
		var id: String = d["id"]
		var row: Dictionary = {"id": id, "cost": d["cost"], "options": [], "reason": _blocked(b, side, d)}
		if row["reason"] == "":
			var open_now: bool = false
			for w: String in d["windows"]:
				if now.has(w):
					open_now = true
					row["options"].append_array(options(b, side, w, b.pending_context(side)))
			if not open_now:
				row["reason"] = "strat.%s.when" % id
			elif (row["options"] as Array).is_empty():
				row["reason"] = "strat.reason.no_target"
		rows.append(row)
	return rows


## Why this stratagem can't be used by [param side] at all right now, as a string key, or "".
static func _blocked(b: Battle, side: int, d: Dictionary) -> String:
	if (b.scenario.get("banned_stratagems", []) as Array).has(d["id"]):
		return "strat.reason.banned"
	if bool(d.get("needs_reserves", false)):
		return "strat.reason.no_reserves"
	if b.used_this_battle(side, d["id"]) and bool(d.get("once_per_battle", false)):
		return "strat.reason.used_battle"
	if b.used_this_phase(side, d["id"]):
		return "strat.reason.used_phase"
	if b.command_points(side) < int(d["cost"]):
		return "strat.reason.no_cp"
	return ""


## Friendly units can be targeted unless battle-shocked or already targeted this phase.
static func _can_target(b: Battle, side: int, u: UnitState) -> bool:
	return u != null and u.owner == side and not u.is_destroyed() and not u.battle_shocked \
			and not b.targeted_this_phase(side, u)


static func _option(u: UnitState, target: UnitState = null, mode: String = "") -> Dictionary:
	return {"unit": u.id, "target": "" if target == null else target.id, "mode": mode}


static func _targets(b: Battle, side: int, id: String, window: String, ctx: Dictionary) -> Array[Dictionary]:
	match id:
		"command_reroll":
			return _reroll_targets(b, side, window, ctx)
		"insane_bravery":
			var tester: UnitState = b.unit_by_id(str(ctx.get("unit", "")))
			return [_option(tester)] if _can_target(b, side, tester) else []
		"epic_challenge":
			return _epic_targets(b, side)
		"explosives":
			return _explosive_targets(b, side)
		"crushing_impact":
			return _crush_targets(b, side)
		"fire_overwatch":
			return _overwatch_targets(b, side)
		"smokescreen":
			return _keyword_units(b, side, "SMOKE")
		"heroic_intervention":
			return _intervention_targets(b, side)
		"counteroffensive":
			return _counter_targets(b, side)
	return []


static func _reroll_targets(b: Battle, side: int, window: String, ctx: Dictionary) -> Array[Dictionary]:
	var u: UnitState = b.last_rolled
	match window:
		W_ADVANCE:
			if REROLL_KINDS.has("advance") and _can_target(b, side, u) and b.advance_roll_for(u) >= 0 and not b.has_moved(u):
				return [_option(u)]
		W_CHARGE:
			if REROLL_KINDS.has("charge") and _can_target(b, side, u) and not b.charge_state(u).is_empty() and not u.charged:
				return [_option(u)]
		W_SHOCK_AFTER:
			var tester: UnitState = b.unit_by_id(str(ctx.get("unit", "")))
			if REROLL_KINDS.has("battle_shock") and _can_target(b, side, tester):
				return [_option(tester)]
	return []


static func _epic_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.fight_options():
		if _can_target(b, side, u) and u.has_keyword("CHARACTER"):
			out.append(_option(u))
	return out


static func _explosive_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.living(side):
		if not _can_target(b, side, u) or u.advanced or b.has_shot(u) or UnitRules.engaged(u, b.units):
			continue
		if not u.has_keyword("EXPLOSIVES") and not u.has_keyword("GRENADES"):
			continue
		for e in _nearest_first(b, u):
			if u.gap_to(e) <= EXPLOSIVES_RANGE and not UnitRules.engaged(e, b.units) and b.unit_sees(u, e):
				out.append(_option(u, e))
	return out


static func _crush_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u: UnitState = b.just_charged
	if not _can_target(b, side, u) or not (u.has_keyword("MONSTER") or u.has_keyword("VEHICLE")):
		return out
	for e in _nearest_first(b, u):
		if u.gap_to(e) <= UnitRules.ENGAGEMENT_RANGE:
			out.append(_option(u, e))
	return out


static func _overwatch_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.living(side):
		if not _can_target(b, side, u) or u.has_keyword("TITANIC") or UnitRules.engaged(u, b.units):
			continue
		for e in _nearest_first(b, u):
			if not UnitRules.engaged(e, b.units) and not Combat.shoot_plan(u, e, b.units, b.snap_ctx()).is_empty():
				out.append(_option(u, e))
	return out


static func _keyword_units(b: Battle, side: int, keyword: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.living(side):
		if _can_target(b, side, u) and u.has_keyword(keyword):
			out.append(_option(u))
	return out


static func _intervention_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.living(side):
		if not _can_target(b, side, u) or UnitRules.engaged(u, b.units):
			continue
		if u.has_keyword("VEHICLE") and not (u.has_keyword("CHARACTER") or u.has_keyword("WALKER")):
			continue
		var near: bool = false
		var chargers: bool = false
		var close: bool = false
		for e in b.living(1 - side):
			var gap: float = u.gap_to(e)
			near = near or gap <= INTERVENTION_RANGE
			chargers = chargers or (e.charged and gap <= INTERVENTION_RANGE)
			close = close or gap <= FRAY_RANGE
		if near and chargers:
			out.append(_option(u, null, LEAP_TO_DEFEND))
		if near and close:
			out.append(_option(u, null, INTO_THE_FRAY))
	return out


static func _counter_targets(b: Battle, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in b.fight_candidates(side):
		if _can_target(b, side, u) and UnitRules.engaged(u, b.units):
			out.append(_option(u))
	return out


static func _nearest_first(b: Battle, u: UnitState) -> Array:
	var foes: Array = b.living(1 - u.owner)
	foes.sort_custom(func(x: UnitState, y: UnitState) -> bool: return u.gap_to(x) < u.gap_to(y))
	return foes
