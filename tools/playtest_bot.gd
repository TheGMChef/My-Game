class_name PlaytestBot
extends RefCounted
## Plays a full game as the human, through GameRoot's real handlers and the action bar's offered
## buttons, so it hits the same dead ends a player would. It deploys, answers stratagem prompts and
## uses stratagems at random. [method play] reports how the game ended.
##
## Outcomes: "finished", "stall" (nothing changes however it plays), "dead_end" (nothing can be
## pressed), "two_mains" (two main actions on screen), "no_game_over" (the game ended with no
## result shown), "vp_high" (a score above the handoff's sanity limit), "step_limit",
## "prompt_blocked" (a stratagem prompt held the game up) and "hang" (a step never came back).

const STALL_LIMIT := 25
const STEP_LIMIT := 5000
const VP_LIMIT := 60
const TRAIL_SIZE := 14
const HANG_FRAMES := 600
const BLOCKED_FRAMES := 60
const USE_CHANCE := 0.5           ## how often a prompt gets Use rather than Pass
const SPEND_CHANCE := 0.35        ## how often a playable stratagem gets used at a chance to act
const AUTO_DEPLOY_CHANCE := 0.15
const DEPLOY_SCATTER := 6.0

var game: GameRoot
var rng := RandomNumberGenerator.new()
var trail: Array[String] = []
## False leaves prompts unanswered, to prove a blocked game is reported rather than hanging.
var answer_prompts: bool = true
var prompts_seen: int = 0
var _tried: Dictionary = {}          # units already handled in the current stage
var _stage_key: String = ""
var _stepping: bool = false


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
		_stepping = true
		_run_step()
		var stuck: String = await _wait_for_step()
		if stuck != "":
			return _result(stuck, steps)
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


func _run_step() -> void:
	await _step()
	_stepping = false


## Wait for the step, answering any prompt it runs into. Returns an outcome if it never finishes.
## A step stuck behind a prompt is waiting on this loop, so it has to run alongside the step.
func _wait_for_step() -> String:
	var frames: int = 0
	while _stepping or game.prompt_open() or game._busy:
		if game.prompt_open():
			if answer_prompts:
				_answer_prompt()
				frames = 0
				continue
			if frames >= BLOCKED_FRAMES:
				return "prompt_blocked"
		elif frames >= HANG_FRAMES:
			return "hang"
		frames += 1
		await game.get_tree().process_frame
	return ""


func _answer_prompt() -> void:
	prompts_seen += 1
	var count: int = game._prompt_options.size()
	if rng.randf() < USE_CHANCE:
		_note("prompt: use")
		game._on_prompt_use(rng.randi_range(0, count - 1))
	else:
		_note("prompt: pass")
		game._on_prompt_pass()


# ---------------------------------------------------------------- playing

func _step() -> void:
	var b: Battle = game.battle
	var key: String = _fingerprint_stage()
	if key != _stage_key:
		_stage_key = key
		_tried.clear()
	if game.prompt_open():
		return
	var phase: String = b.phase()
	var acted: bool = false
	if phase == "deployment":
		await _deploy()
		return
	await _maybe_spend()
	if b.is_over() or game.prompt_open():
		return
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


## Place the next unit by hand, usually scattered about a bit, or leave the rest to Auto-deploy.
func _deploy() -> void:
	if _enabled("button.start_battle"):
		await _press("button.start_battle")
		return
	var waiting: Array = game.battle.undeployed_of(GameRoot.HUMAN)
	if waiting.is_empty():
		return
	if rng.randf() < AUTO_DEPLOY_CHANCE:
		_note("auto-deploy")
		game._request_next()
		return
	var u: UnitState = waiting[rng.randi_range(0, waiting.size() - 1)]
	_note("place %s" % u.unit_name)
	game._on_tray_pressed(u.id)
	var scatter: Vector2 = Vector2(rng.randf_range(-DEPLOY_SCATTER, DEPLOY_SCATTER), rng.randf_range(-DEPLOY_SCATTER, DEPLOY_SCATTER))
	game._on_drag_moved(u, scatter)
	game._on_drag_ended(u, scatter)
	if not _enabled("button.place_unit"):
		game._on_tray_pressed(u.id)     # back to the suggested spot
	if _enabled("button.place_unit"):
		await _press("button.place_unit")
	else:
		game._request_next()


## Now and then, use something the Stratagems tab says is playable.
func _maybe_spend() -> void:
	if rng.randf() >= SPEND_CHANCE:
		return
	var rows: Array = game._stratagem_view()["rows"].filter(func(r: Dictionary) -> bool: return str(r["button"]) != "")
	if rows.is_empty():
		return
	var r: Dictionary = rows[rng.randi_range(0, rows.size() - 1)]
	_note("stratagem %s" % r["name"])
	await game._on_stratagem_pressed(str(r["id"]))


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
		await _maybe_spend()
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
	await _maybe_spend()
	if _spec("button.suggest") == {}:
		return
	await _press("button.suggest")
	if _enabled("button.confirm_charge"):
		await _press("button.confirm_charge")
		await _maybe_spend()
	else:
		await _press("button.give_up")


func _short_move(_u: UnitState) -> void:
	await _press("button.suggest")
	for key in ["button.confirm_pile_in", "button.confirm_consolidate"]:
		if _enabled(key):
			await _press(key)


func _fight(u: UnitState) -> void:
	await _maybe_spend()
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
	var stratagems: Dictionary = {}
	for e in b.events:
		if e["type"] == "stratagem":
			var key: String = "%s/%s" % [e["id"], "you" if int(e["side"]) == GameRoot.HUMAN else "ai"]
			stratagems[key] = int(stratagems.get(key, 0)) + 1
		if int(e.get("side", -1)) == GameRoot.HUMAN:
			actions[e["type"]] = int(actions.get(e["type"], 0)) + 1
	return {"outcome": outcome, "steps": steps, "round": b.flow.round_no, "vp": b.vp.duplicate(),
		"chooser": b.fight_chooser(), "trail": trail.duplicate(), "actions": actions,
		"stratagems": stratagems, "prompts": prompts_seen}
