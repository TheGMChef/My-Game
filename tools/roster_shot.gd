extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var n = scene.instantiate()
	root.add_child(n)
	_go.call_deferred(a[0])
func _go(path: String) -> void:
	for i in 6: await process_frame
	root.get_texture().get_image().save_png(path)
	quit()
