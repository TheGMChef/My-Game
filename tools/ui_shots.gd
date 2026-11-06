extends SceneTree
## Walks the screens the tour skips: the main menu, roster, dialogs, tools and panel tabs.
## Run: godot --path . --resolution 1280x800 --rendering-driver opengl3 -s tools/ui_shots.gd -- <out_dir> <tag> [a11y]
## With a11y, the battle shots use the largest text size and the colour-blind palette.
## Nothing here reads or writes the player's settings or save, and only the invented placeholder
## armies are loaded, so no real army name can reach the screenshots.
var out_dir: String
var tag: String
var a11y: bool = false

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0]
	tag = args[1]
	a11y = args.size() > 2
	var game: GameRoot = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.persist = false
	game.placeholder_only = true
	game.show_continue = true
	root.add_child(game)
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s-%s.png" % [out_dir, name, tag])
	print("saved ", name)

func _find(n: Node, cls: String) -> Node:
	if n.get_script() and (n.get_script() as Script).get_global_name() == cls:
		return n
	for c in n.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null

func _settings_tabs(game: GameRoot, prefix: String) -> void:
	game._open_settings()
	var d: SettingsDialog = _find(game, "SettingsDialog")
	var names: Array[String] = ["display", "gameplay", "accessibility", "controls"]
	for i in range(names.size()):
		d.show_page(i)
		d._tabs[i].grab_focus()
		await _shot("%s-%s" % [prefix, names[i]])
	d.close()
	await process_frame

## The deployment stage: a unit in hand, a bad spot, then everything down with the human first.
func _deployment(game: GameRoot) -> void:
	var u: UnitState = game.battle.undeployed_of(0)[0]
	game._on_tray_pressed(u.id)
	await _shot("deploy-placing")
	game._on_drag_moved(u, Vector2(25, 0))
	await _shot("deploy-illegal")
	game._on_drag_cancelled()
	await game._on_place_pressed()
	game._request_next()
	await _shot("deploy-ready")
	game.battle.dice = Dice.new(1, [6, 1])
	await game._on_start_battle_pressed()
	game.battle.dice = Dice.new(5)
	game.battle.flow.command_points = [3, 3]
	game._refresh()


## Play on to the first stratagem question of the AI's turn. The AI loop is not awaited: it is
## what waits for the answer.
func _prompt(game: GameRoot) -> void:
	var mine: UnitState = game.battle.living(0)[0]
	var y: float = 3.0
	for e: UnitState in game.battle.living(1):
		var offset: Vector2 = Vector2(mine.centre().x + 14.0, y) - e.centre()
		for m in e.models:
			m["pos"] = m["pos"] + offset
		y += 9.0
	for i in range(600):
		if game.prompt_open():
			break
		if not game._busy and game.battle.fight_chooser() == 0:
			game._on_unit_tapped(game.battle.fight_options()[0])
			game._on_skip_fight_pressed()
		elif not game._busy:
			game._on_next_pressed()
		await process_frame
	await _shot("prompt")
	game._on_prompt_pass()


func _run() -> void:
	var game: GameRoot = _find(root, "GameRoot")
	if a11y:
		game.settings.colour_blind = true
		game.settings.text_scale_index = UISettings.TEXT_SCALES.size() - 1
		game._settings_changed()
	await _shot("title")
	game._open_how_to()
	await _shot("how-to-play")
	(_find(game, "HowToPlay") as HowToPlay).close()
	await _settings_tabs(game, "settings-menu")
	(_find(root, "TitleScreen") as TitleScreen).start_pressed.emit()
	await _shot("roster-empty")
	var roster: RosterScreen = _find(root, "RosterScreen")
	roster._on_quick_fill()
	await _shot("roster-filled")
	roster._on_start()
	await _shot("battle-start")
	await _settings_tabs(game, "settings")
	game._open_pause()
	await _shot("pause")
	var ask: DialogBox = game._ask("confirm.quit.title", UIText.t("confirm.quit.body"), "button.quit_to_menu", func() -> void: pass)
	await _shot("confirm-quit")
	ask.close()
	await process_frame
	game._open_rules()
	await _shot("rules")
	(game.get_child(-1) as DialogBox).close()
	await process_frame
	game._pause.close()
	await process_frame
	await _deployment(game)
	var side: SidePanel = _find(root, "SidePanel")
	if not side.visible:
		game._toggle_info()
	await game._on_next_pressed()
	game._on_unit_tapped(game.battle.living(0)[0])
	await _shot("orders-selected")
	side._tabs[1].button_pressed = true
	side._show_page(1)
	await _shot("tab-unit")
	for i in range(game._selected.weapons.size()):
		if not (game._selected.weapons[i] as Weapon).is_melee():
			game._on_weapon_pressed(i)
			break
	await _shot("weapon-ring")
	side._tabs[3].button_pressed = true
	side._show_page(3)
	await _shot("tab-units")
	side._tabs[2].button_pressed = true
	side._show_page(2)
	await _shot("tab-log")
	side._tabs[4].button_pressed = true
	side._show_page(4)
	await _shot("tab-stratagems")
	if game._info_open:
		game._toggle_info()
	game._on_empty_tapped(Vector2.ZERO)
	game._set_ruler(true)
	game.board.set_measurement(game.battle.living(0)[0].centre(), game.battle.living(1)[0].centre())
	await _shot("ruler")
	game._set_ruler(false)
	await _prompt(game)
	quit()
