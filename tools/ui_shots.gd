extends SceneTree
## Walks the screens the tour skips: title, roster, settings, and the Unit and Log tabs.
## Run: godot --path . --resolution 1280x800 --rendering-driver opengl3 -s tools/ui_shots.gd -- <out_dir> <tag> [a11y]
## With a11y, the battle shots use the largest text size and the colour-blind palette.
var out_dir: String
var tag: String

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0]
	tag = args[1]
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
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

func _run() -> void:
	await _shot("title")
	(_find(root, "TitleScreen") as TitleScreen).start_pressed.emit()
	await _shot("roster-empty")
	var roster: RosterScreen = _find(root, "RosterScreen")
	roster._on_quick_fill()
	await _shot("roster-filled")
	roster._on_start()
	await _shot("battle-start")
	var game: GameRoot = _find(root, "GameRoot")
	if OS.get_cmdline_user_args().size() > 2:
		game.settings.colour_blind = true
		game.settings.text_scale_index = UISettings.TEXT_SCALES.size() - 1
		game._settings_changed()
	game._set_settings_visible(true)
	await _shot("settings")
	# Closed by hand: the real close button saves, and a11y shots must not change saved settings.
	game._settings_panel.visible = false
	game._scrim.visible = false
	game._on_unit_tapped(game.battle.living(0)[0])
	var side: SidePanel = _find(root, "SidePanel")
	if not side.visible:
		game._toggle_info()
	side._tabs[1].button_pressed = true
	side._show_page(1)
	await _shot("tab-unit")
	side._tabs[2].button_pressed = true
	side._show_page(2)
	await _shot("tab-log")
	quit()
