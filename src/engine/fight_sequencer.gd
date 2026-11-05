class_name FightSequencer
extends RefCounted
## Who fights next in the Fight phase (core rules 12.04): Fights First combats alternate
## starting with the active player, then remaining combats alternate.
##
## Usage: [method begin], then repeat [method options] / [method select] until [member finished].
## Call [method refresh] after any fight that changes who is engaged (destroyed units, consolidation).

var finished: bool = false
var chooser: int = 0

var _units: Array = []
var _active_player: int = 0
var _in_fights_first: bool = true
var _selected: Array = []
var _engaged_at_start: Array = []


## Start the step. Units engaged now count as "was engaged at the start of this step".
func begin(units: Array, active_player: int) -> void:
	_units = units
	_active_player = active_player
	_selected = []
	_engaged_at_start = []
	for u in units:
		if UnitRules.engaged(u, units):
			_engaged_at_start.append(u)
	_in_fights_first = true
	chooser = active_player
	finished = false
	_settle()


## Units the current chooser may select right now.
func options() -> Array[UnitState]:
	return _eligible(chooser, _in_fights_first)


func in_fights_first_step() -> bool:
	return _in_fights_first


## Select a unit to fight. Returns false if it is not a legal choice.
func select(unit: UnitState) -> bool:
	if finished or not options().has(unit):
		return false
	_selected.append(unit)
	chooser = 1 - chooser
	if not _in_fights_first and _any_eligible(true):
		_in_fights_first = true
		chooser = _active_player
	_settle()
	return true


## Re-check eligibility after units were destroyed or moved.
func refresh() -> void:
	_settle()


func _eligible(player: int, fights_first_only: bool) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for u in _units:
		if u.owner != player or u.is_destroyed() or _selected.has(u):
			continue
		if fights_first_only and not u.is_fights_first():
			continue
		if _engaged_at_start.has(u) or u.charged or UnitRules.engaged(u, _units):
			out.append(u)
	return out


func _any_eligible(fights_first_only: bool) -> bool:
	return not _eligible(0, fights_first_only).is_empty() or not _eligible(1, fights_first_only).is_empty()


## Apply the "if not possible" rules until the chooser has an option or the step ends.
func _settle() -> void:
	for guard in range(4):
		if not _eligible(chooser, _in_fights_first).is_empty():
			return
		if _in_fights_first:
			if not _eligible(1 - chooser, true).is_empty():
				chooser = 1 - chooser
			else:
				_in_fights_first = false  # same player now chooses among remaining combats
		else:
			if not _eligible(1 - chooser, false).is_empty():
				chooser = 1 - chooser
			else:
				finished = true
				return
