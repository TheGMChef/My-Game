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
	if game._info_open:
		game._toggle_info()
	game._on_empty_tapped(Vector2.ZERO)
	game._set_ruler(true)
	game.board.set_measurement(game.battle.living(0)[0].centre(), game.battle.living(1)[0].centre())
	await _shot("ruler")
	quit()
