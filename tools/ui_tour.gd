extends SceneTree
## Drives the real game screen through each phase and saves screenshots.
## Run: xvfb-run -a godot --path . --resolution 1280x800 -s tools/ui_tour.gd -- <out_dir> <tag>
var root_node: GameRoot
var out_dir: String = "res://production/qa/evidence/board-view"
var tag: String = "1280x800"

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	if args.size() > 1: tag = args[1]
	var scene: PackedScene = load("res://scenes/main.tscn")
	root_node = scene.instantiate()
	root_node.skip_roster = true
	root.add_child(root_node)
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s-%s.png" % [out_dir, name, tag])
	print("saved ", name)

func _run() -> void:
	var r: GameRoot = root_node
	var b: Battle = r.battle
	await _shot("a-start")
	r._on_next_pressed()  # end command -> movement
	await process_frame
	var tank: UnitState = b.units[0]
	for u in b.units:
		if u.owner == 0 and u.unit_name == "Line Squad": tank = u
	r._on_unit_tapped(tank)
	r._on_drag_moved(tank, Vector2(5, 3))
	await _shot("b-move-legal")
	print("verdict legal: ", r._verdict)
	# illegal: park an enemy unit where the tank would end, so it finishes within 2" of it
	for u in b.units:
		if u.owner == 0 and u.unit_name == "Siege Tank": tank = u
	var foe: UnitState = b.living(1)[1]
	var off: Vector2 = tank.centre() + Vector2(6, 0) - foe.centre()
	for m in foe.models: m["pos"] = m["pos"] + off
	r._on_unit_tapped(tank)
	r._on_drag_moved(tank, Vector2(6, 0))
	await _shot("c-move-illegal")
	print("verdict illegal: ", r._verdict)
	for m in foe.models: m["pos"] = m["pos"] - off
	r._on_cancel_pressed()
	r._on_drag_moved(tank, Vector2(5, 0))
	r._on_confirm_pressed()
	print("confirm: ", r._verdict)
	# move a few units up so shooting is possible
	for u in b.units:
		if u.owner == 0 and not b.has_moved(u):
			r._on_unit_tapped(u)
			r._on_drag_moved(u, Vector2(8, 0))
			r._on_confirm_pressed()
	r._on_next_pressed()  # -> shooting
	await process_frame
	print("phase: ", b.phase(), " busy ", r._busy)
	var shooter: UnitState = null
	var tgt: UnitState = null
	for u in b.living(0):
		for e in b.living(1):
			if shooter == null and not b.shoot_preview(u, e).is_empty():
				shooter = u; tgt = e
	print("shooter: ", shooter, " target: ", tgt)
	if shooter != null:
		r._on_unit_tapped(shooter)
		r._on_unit_tapped(tgt)
		await _shot("d-shoot-odds")
		await r._on_fire_pressed()
	await _shot("e-after-fire")
	await r._on_next_pressed()
	await _shot("f-charge-phase")
	print("phase: ", b.phase(), " active ", b.active_player(), " round ", b.flow.round_no)
	await r._on_next_pressed()  # end charge -> fight
	await _shot("g-fight-phase")
	var guard: int = 0
	var fought_shot: bool = false
	var fight_tgt: UnitState = null
	while not b.is_over() and guard < 120:
		guard += 1
		if guard == 3:
			await _shot("h-mid-game")
		if b.phase() == "fight" and b.fight_stage == "pile_in" and b.active_player() != 0 and not fought_shot:
			pass
		if b.phase() == "fight" and b.fight_stage == "fight" and b.fight_chooser() == 0:
			var opts: Array = b.fight_options()
			if not fought_shot and not opts.is_empty():
				var me: UnitState = opts[0]
				for e in b.living(1):
					if me.gap_to(e) <= 2.0 and fight_tgt == null:
						fight_tgt = e
				if fight_tgt != null:
					r._on_unit_tapped(me)
					r._on_unit_tapped(fight_tgt)
					await _shot("j-fight-odds")
					await r._on_fight_pressed()
					fought_shot = true
					continue
			if not b.fight_options().is_empty():
				r._on_unit_tapped(b.fight_options()[0])
				await r._on_skip_fight_pressed()
				continue
		await r._on_next_pressed()
		await process_frame
	print("over: ", b.is_over(), " vp ", b.vp, " guard ", guard, " phase ", b.phase())
	await _shot("i-game-over")
	quit()
