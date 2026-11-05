class_name PlaytestBot
extends RefCounted
## Plays a full game as the human, through GameRoot's real handlers and the action bar's offered
## buttons, so it hits the same dead ends a player would. [method play] reports how the game ended.
##
## Outcomes: "finished", "stall" (nothing changes however it plays), "dead_end" (nothing can be
## pressed), "two_mains" (two main actions on screen), "no_game_over" (the game ended with no
## result shown), "vp_high" (a score above the handoff's sanity limit) and "step_limit".

const STALL_LIMIT := 25
const STEP_LIMIT := 5000
const VP_LIMIT := 60
const TRAIL_SIZE := 14

var game: GameRoot
var rng := RandomNumberGenerator.new()
var trail: Array[String] = []
var _tried: Dictionary = {}          # units already handled in the current stage
var _stage_key: String = ""


func _init(target: GameRoot, seed_value: int) -> void:
	game = target
	rng.seed = seed_value


func play() -> Dictionary:
	var same: int = 0
	var last: String = ""
	var steps: int = 0
	while not game.battle.is_over():
		steps += 1
		if steps > STEP_LIMIT:
			return _result("step_limit", steps)
		await _step()
		var problem: String = _screen_problem()
		if problem != "":
			return _result(problem, steps)
		var now: String = _fingerprint()
		same = same + 1 if now == last else 0
		last = now
		if same >= STALL_LIMIT:
			return _result("stall", steps)
	if not game._over_panel.visible:
		return _result("no_game_over", steps)
	if maxi(game.battle.vp[0], game.battle.vp[1]) > VP_LIMIT:
		return _result("vp_high", steps)
	return _result("finished", steps)


# ---------------------------------------------------------------- playing

func _step() -> void:
	var b: Battle = game.battle
	var key: String = _fingerprint_stage()
	if key != _stage_key:
		_stage_key = key
		_tried.clear()
	var phase: String = b.phase()
	var acted: bool = false
	if phase == "command" and _enabled("button.shadow"):
		await _press("button.shadow")
		acted = true
	elif phase == "movement":
		acted = await _next_unit(func(u: UnitState) -> bool: return not b.has_moved(u), _move)
	elif phase == "shooting":
		acted = await _next_unit(func(u: UnitState) -> bool: return not b.has_shot(u), _shoot)
	elif phase == "charge":
		acted = await _next_unit(func(u: UnitState) -> bool: return not b.charge_finished(u), _charge)
	elif phase == "fight":
		match b.fight_stage:
			"pile_in":
				acted = await _next_unit(func(u: UnitState) -> bool: return b.can_pile_in(u), _short_move)
			"fight":
				if b.fight_chooser() == GameRoot.HUMAN:
					acted = await _next_unit(func(u: UnitState) -> bool: return b.fight_options().has(u), _fight)
			"consolidate":
				acted = await _next_unit(func(u: UnitState) -> bool: return b.can_consolidate(u), _short_move)
	if not acted:
		_note("press %s" % game._next_label())
		await game._on_next_pressed()


## Hand one unit that still can act to [param action]. False when none are left.
func _next_unit(can_act: Callable, action: Callable) -> bool:
	for u in game.battle.living(GameRoot.HUMAN):
		if not _tried.has(u) and can_act.call(u):
			_tried[u] = true
			_note("tap %s" % u.unit_name)
			game._on_unit_tapped(u)
			await action.call(u)
			return true
	return false


func _move(u: UnitState) -> void:
	if rng.randf() < 0.25 and _spec("mode.advance") != {}:
		await _press("mode.advance")
	var goal: Vector2 = game.battle.objectives[rng.randi_range(0, game.battle.objectives.size() - 1)]
	var direction: Vector2 = (goal - u.centre()).normalized()
	var reach: float = game._allowed_distance(u)
	while reach > 0.5:
		game._on_drag_moved(u, direction * reach)
		if _enabled("button.confirm_move"):
			await _press("button.confirm_move")
			return
		reach *= 0.6
	game._on_drag_moved(u, Vector2.ZERO)
	await _press("button.hold")


func _shoot(u: UnitState) -> void:
	var targets: Array = game.battle.living(1 - GameRoot.HUMAN).filter(func(e: UnitState) -> bool:
		return not game.battle.shoot_preview(u, e).is_empty())
	if targets.is_empty():
		return
	game._on_unit_tapped(targets[rng.randi_range(0, targets.size() - 1)])
	if rng.randf() < 0.3 and _enabled("button.mark_spotted"):
		await _press("button.mark_spotted")
	await _press("button.fire")


func _charge(_u: UnitState) -> void:
	if not _enabled("button.declare_charge"):
		return
	await _press("button.declare_charge")
	if _spec("button.suggest") == {}:
		return
	await _press("button.suggest")
	if _enabled("button.confirm_charge"):
		await _press("button.confirm_charge")
	else:
		await _press("button.give_up")


func _short_move(_u: UnitState) -> void:
	await _press("button.suggest")
	for key in ["button.confirm_pile_in", "button.confirm_consolidate"]:
		if _enabled(key):
			await _press(key)


func _fight(u: UnitState) -> void:
	for e in game.battle.living(1 - GameRoot.HUMAN):
		if u.gap_to(e) <= UnitRules.ENGAGEMENT_RANGE:
			game._on_unit_tapped(e)
			break
	if _enabled("button.fight"):
		await _press("button.fight")
		return
	game._on_empty_tapped(Vector2.ZERO)
	game._on_unit_tapped(u)
	await _press("button.skip_fight")


# ---------------------------------------------------------------- what is on screen

func _spec(key: String) -> Dictionary:
	var text: String = UIText.t(key)
	for s in game._action_specs():
		if str(s.get("text", "")) == text:
			return s
	return {}


func _enabled(key: String) -> bool:
	var s: Dictionary = _spec(key)
	return s != {} and not bool(s.get("disabled", false))


func _press(key: String) -> void:
	var s: Dictionary = _spec(key)
	if s == {} or bool(s.get("disabled", false)):
		_note("wanted %s, not available" % key)
		return
	_note("press %s" % s["text"])
	await (s["handler"] as Callable).call()


func _screen_problem() -> String:
	if game.battle.is_over() or game._busy:
		return ""
	var mains: int = 0
	var buttons: int = 0
	for s in game._action_specs():
		if not s.has("hint"):
			buttons += 1
		if str(s.get("role", "")) == "main":
			mains += 1
	if mains > 1:
		return "two_mains"
	if buttons == 0 and game._action_bar._next.disabled:
		return "dead_end"
	return ""


func _fingerprint_stage() -> String:
	var b: Battle = game.battle
	return "%d/%d/%s/%s" % [b.flow.round_no, b.active_player(), b.phase(), b.fight_stage]


func _fingerprint() -> String:
	var b: Battle = game.battle
	return "%s/%d/%d" % [_fingerprint_stage(), b.fight_chooser(), b.events.size()]


func _note(text: String) -> void:
	trail.append("%s: %s" % [_fingerprint_stage(), text])
	if trail.size() > TRAIL_SIZE:
		trail.pop_front()


func _result(outcome: String, steps: int) -> Dictionary:
	var b: Battle = game.battle
	var actions: Dictionary = {}
	for e in b.events:
		if int(e.get("side", -1)) == GameRoot.HUMAN:
			actions[e["type"]] = int(actions.get(e["type"], 0)) + 1
	return {"outcome": outcome, "steps": steps, "round": b.flow.round_no, "vp": b.vp.duplicate(),
		"chooser": b.fight_chooser(), "trail": trail.duplicate(), "actions": actions}
