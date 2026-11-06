class_name PhoneHud
extends VBoxContainer
## Scores, round and current phase for the narrow right-hand column on a phone in landscape.

signal info_pressed
signal menu_pressed

var _vp: Array[Label] = []
var _round: Label
var _phase: Label
var _count: Label


func _init() -> void:
	var scores := HBoxContainer.new()
	add_child(scores)
	scores.add_child(ShapeMark.new(0))
	scores.add_child(_score())
	_round = Label.new()
	_round.theme_type_variation = "LabelSection"
	_round.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores.add_child(_round)
	scores.add_child(_score())
	scores.add_child(ShapeMark.new(1))

	var pill := PanelContainer.new()
	pill.theme_type_variation = "StepOn"
	add_child(pill)
	var row := HBoxContainer.new()
	pill.add_child(row)
	_phase = Label.new()
	_phase.theme_type_variation = "LabelSection"
	_phase.uppercase = true
	_phase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase.add_theme_color_override("font_color", UITokens.ON_ACTION)
	row.add_child(_phase)
	_count = Label.new()
	_count.theme_type_variation = "LabelSmallStat"
	_count.add_theme_color_override("font_color", UITokens.ON_ACTION)
	row.add_child(_count)

	var tools := HBoxContainer.new()
	add_child(tools)
	tools.add_child(_tool("panel", "tip.panel", func() -> void: info_pressed.emit()))
	tools.add_child(_tool("menu", "tip.menu", func() -> void: menu_pressed.emit()))


func _score() -> Label:
	var l := Label.new()
	l.theme_type_variation = "LabelScore"
	_vp.append(l)
	return l


func _tool(icon_name: String, tip_key: String, handler: Callable) -> Button:
	var b: Button = TopBar.make_icon_button(icon_name, tip_key, handler)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func refresh(round_no: int, total_rounds: int, phase: String, vp: Array, over: bool = false) -> void:
	_round.text = UIText.t("hud.round_short", [round_no, total_rounds])
	_phase.text = UIText.t("hud.battle_over") if over else UIText.t("rail." + phase)
	_count.text = "" if over else "%d/%d" % [TopBar.PHASES.find(phase) + 1, TopBar.PHASES.size()]
	_vp[0].text = str(vp[0])
	_vp[1].text = str(vp[1])
