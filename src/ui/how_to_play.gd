class_name HowToPlay
extends DialogBox
## A short guide in our own words: how a turn runs, the tools, and the controls.

const WIDTH := 600.0
const SECTIONS: Array[String] = ["aim", "deploy", "turn", "phases", "stratagems", "tools", "controls"]

var close_button: Button


func _init() -> void:
	super(UIText.t("howto.title"), WIDTH)
	scroll_with_keys = true
	for section in SECTIONS:
		var head: Label = add_text(UIText.t("howto.%s.title" % section), "LabelSection")
		head.uppercase = true
		add_text(UIText.t("howto.%s.body" % section))
	close_button = add_button(UIText.t("button.close"), close, true)


func _ready() -> void:
	super()
	_first_focus = close_button
