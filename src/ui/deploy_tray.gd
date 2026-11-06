class_name DeployTray
extends PanelContainer
## The units still to be placed, as one row of buttons under the board during deployment.
## Display only: rows are {"id", "name", "count", "selected"}, and tapping one reports its unit.

signal picked(unit_id: String)

var _row: HBoxContainer
var _shown: Array = []


func _init() -> void:
	theme_type_variation = "BarPanel"
	visible = false
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size.y = UITokens.HIT
	add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", UITokens.SPACE_2)
	scroll.add_child(_row)


func show_units(rows: Array) -> void:
	if rows == _shown:
		return
	_shown = rows.duplicate(true)
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for r in rows:
		var b := Button.new()
		b.text = "%s  %s" % [r["name"], r["count"]]
		b.toggle_mode = true
		b.button_pressed = bool(r["selected"])
		b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
		b.pressed.connect(func() -> void: picked.emit(str(r["id"])))
		_row.add_child(b)
