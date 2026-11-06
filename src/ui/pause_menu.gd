class_name PauseMenu
extends DialogBox
## The in-battle menu. The controller answers each signal; closing the menu is Resume.

signal rules_pressed
signal settings_pressed
signal restart_pressed
signal quit_pressed

const WIDTH := 340.0

var resume_button: Button


func _init() -> void:
	super(UIText.t("pause.title"), WIDTH)
	body.add_theme_constant_override("separation", UITokens.SPACE_1)
	resume_button = _item("pause.resume", close, true)
	_item("pause.rules", func() -> void: rules_pressed.emit())
	_item("pause.settings", func() -> void: settings_pressed.emit())
	_item("pause.restart", func() -> void: restart_pressed.emit())
	_item("pause.quit", func() -> void: quit_pressed.emit())


func _ready() -> void:
	super()
	_first_focus = resume_button


func _item(key: String, handler: Callable, primary: bool = false) -> Button:
	var b := DialogBox.make_button(UIText.t(key), handler, primary)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(b)
	return b
