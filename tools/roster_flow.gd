extends SceneTree
## Drives the roster: quick fill, start, then plays a few frames of the battle and saves shots.
## Run: xvfb-run -a godot --path . --resolution 1280x800 --rendering-driver opengl3 -s tools/roster_flow.gd -- <out_dir>
func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var n = scene.instantiate()
	n.skip_title = true
	root.add_child(n)
	_go.call_deferred(OS.get_cmdline_user_args()[0])

func _shot(path: String) -> void:
	for i in 4: await process_frame
	root.get_texture().get_image().save_png(path)

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls or (n.get_script() and n.get_script().get_global_name() == cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null

func _go(out: String) -> void:
	var rs: RosterScreen = _find(root, "RosterScreen")
	rs._on_quick_fill()
	await _shot(out + "/roster-filled.png")
	rs._on_start()
	for i in 30: await process_frame
	await _shot(out + "/battle-from-roster.png")
	var gr = _find(root, "GameRoot")
	print("units: ", gr.battle.units.size(), " names: ", gr.battle.units.map(func(u): return u.unit_name + "x" + str(u.model_count())))
	quit()
