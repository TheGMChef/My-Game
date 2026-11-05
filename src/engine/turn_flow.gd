class_name TurnFlow
extends RefCounted
## Battle rounds, player turns and phases. Each battle round has one turn per player.
## Which player goes first is a mission decision that is not sourced yet, so player 0 starts.

const PHASES: Array[String] = ["command", "movement", "shooting", "charge", "fight"]

var round_no: int = 1
var active_player: int = 0
var finished: bool = false
## Starting CP is not in the supplied PDFs, so both sides start at 0 until it is sourced.
var command_points: Array[int] = [0, 0]

var _phase_index: int = 0
var _total_rounds: int = 5


func _init(battle_rounds: int = 5) -> void:
	_total_rounds = battle_rounds


func phase() -> String:
	return PHASES[_phase_index]


## Move to the next phase, passing the turn or starting the next round when needed.
func advance() -> void:
	if finished:
		return
	_phase_index += 1
	if _phase_index < PHASES.size():
		return
	_phase_index = 0
	if active_player == 0:
		active_player = 1
		return
	active_player = 0
	round_no += 1
	if round_no > _total_rounds:
		finished = true
		round_no = _total_rounds


## Command phase steps 2 and 3 (08.02, 08.03): both players gain 1 CP, then the active
## player rolls battle-shock for each of their units that is battle-shocked or at or below
## half strength. A shocked unit that passes recovers.
func start_command_phase(units: Array, dice: Dice) -> void:
	command_points[0] += 1
	command_points[1] += 1
	for u in units:
		if u.owner != active_player:
			continue
		if not (u.battle_shocked or u.at_or_below_half_strength()):
			continue
		var was_shocked: bool = u.battle_shocked
		var passed: bool = UnitRules.battle_shock_roll(u, dice, units)
		if was_shocked and passed:
			u.battle_shocked = false
