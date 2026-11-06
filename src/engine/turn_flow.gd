class_name TurnFlow
extends RefCounted
## Battle rounds, player turns and phases. Each battle round has one turn per player.
## The same player goes first every round: player 0 unless a first-turn roll-off says otherwise.

const PHASES: Array[String] = ["command", "movement", "shooting", "charge", "fight"]

var round_no: int = 1
var active_player: int = 0
var first_player: int = 0
var finished: bool = false
## Starting CP is not in the supplied PDFs, so both sides start at 0 until it is sourced.
var command_points: Array[int] = [0, 0]

var _phase_index: int = 0
var _total_rounds: int = 5


func _init(battle_rounds: int = 5) -> void:
	_total_rounds = battle_rounds


func phase() -> String:
	return PHASES[_phase_index]


## Plain data for a save file.
func to_save() -> Dictionary:
	return {"round_no": round_no, "active_player": active_player, "first_player": first_player, "finished": finished,
		"command_points": command_points.duplicate(), "phase_index": _phase_index, "total_rounds": _total_rounds}


## Rebuild from [method to_save].
static func from_save(d: Dictionary) -> TurnFlow:
	var out := TurnFlow.new(int(d["total_rounds"]))
	out.round_no = int(d["round_no"])
	out.active_player = int(d["active_player"])
	out.first_player = int(d.get("first_player", 0))
	out.finished = bool(d["finished"])
	out._phase_index = int(d["phase_index"])
	for i in range(out.command_points.size()):
		out.command_points[i] = int(d["command_points"][i])
	return out


## Set who takes the first turn of every round. Call before round 1 starts.
func set_first_player(player: int) -> void:
	first_player = player
	active_player = player


## Move to the next phase, passing the turn or starting the next round when needed.
func advance() -> void:
	if finished:
		return
	_phase_index += 1
	if _phase_index < PHASES.size():
		return
	_phase_index = 0
	if active_player == first_player:
		active_player = 1 - first_player
		return
	active_player = first_player
	round_no += 1
	if round_no > _total_rounds:
		finished = true
		round_no = _total_rounds


## Command phase step 2 (08.02): both players gain 1 CP.
func gain_command_points() -> void:
	command_points[0] += 1
	command_points[1] += 1


## Command phase steps 2 and 3 (08.02, 08.03): both players gain 1 CP, then the active
## player rolls battle-shock for each of their units that is battle-shocked or at or below
## half strength. A shocked unit that passes recovers.
func start_command_phase(units: Array, dice: Dice) -> void:
	gain_command_points()
	for u in units:
		if u.owner != active_player:
			continue
		if not (u.battle_shocked or u.at_or_below_half_strength()):
			continue
		var was_shocked: bool = u.battle_shocked
		var passed: bool = UnitRules.battle_shock_roll(u, dice, units)
		if was_shocked and passed:
			u.battle_shocked = false
