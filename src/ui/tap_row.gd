class_name TapRow
extends PanelContainer
## A list row that presses like a button but can hold any layout: tap, click, Enter or gamepad.
## A press that turns into a scroll drag is not a tap.

signal pressed

const MOVE_LIMIT := 12.0

## Names the row, so a rebuilt list can put keyboard focus back on it.
var key: String = ""

var _down_at: Vector2 = Vector2.ZERO
var _down: bool = false


func _init(row_key: String = "", on: bool = false) -> void:
	key = row_key
	theme_type_variation = "RowPanelOn" if on else "RowPanel"
	custom_minimum_size.y = UITokens.HIT
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS    # a drag on a row still scrolls the list
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_down = true
			_down_at = mb.global_position
		elif _down:
			_down = false
			if mb.global_position.distance_to(_down_at) <= MOVE_LIMIT and Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		pressed.emit()


func _draw() -> void:
	if has_focus():
		draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))
