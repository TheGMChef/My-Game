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
var _forced: UnitState                  # must be picked next (Counteroffensive)


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


## Plain data for a save file. Units are stored by id; destroyed ones no longer matter.
func to_save() -> Dictionary:
	return {"finished": finished, "chooser": chooser, "active_player": _active_player,
		"in_fights_first": _in_fights_first,
		"selected": _selected.map(func(u: UnitState) -> String: return u.id),
		"engaged_at_start": _engaged_at_start.map(func(u: UnitState) -> String: return u.id),
		"forced": "" if _forced == null else _forced.id}


## Rebuild from [method to_save] against the battle's [param units].
static func from_save(d: Dictionary, units: Array) -> FightSequencer:
	var out := FightSequencer.new()
	out._units = units
	out.finished = bool(d["finished"])
	out.chooser = int(d["chooser"])
	out._active_player = int(d["active_player"])
	out._in_fights_first = bool(d["in_fights_first"])
	for u: UnitState in units:
		if (d["selected"] as Array).has(u.id):
			out._selected.append(u)
		if (d["engaged_at_start"] as Array).has(u.id):
			out._engaged_at_start.append(u)
		if str(d.get("forced", "")) == u.id:
			out._forced = u
	return out


## Units the current chooser may select right now.
func options() -> Array[UnitState]:
	if _forced_is_live():
		return [_forced]
	return _eligible(chooser, _in_fights_first)


## Every unit of [param player] that could still fight this step, Fights First or not.
func candidates(player: int) -> Array[UnitState]:
	return _eligible(player, false)


## Make [param unit] the next unit selected, by its own player, whatever the order would be.
func force_next(unit: UnitState) -> void:
	_forced = unit
	chooser = unit.owner
	finished = false


func _forced_is_live() -> bool:
	return _forced != null and not _forced.is_destroyed() and not _selected.has(_forced)


func in_fights_first_step() -> bool:
	return _in_fights_first


## Select a unit to fight. Returns false if it is not a legal choice.
func select(unit: UnitState) -> bool:
	if finished or not options().has(unit):
		return false
	_selected.append(unit)
	_forced = null
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
	if _forced_is_live():
		return
	_forced = null
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
