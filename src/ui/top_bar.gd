class_name TopBar
extends PanelContainer
## Wordmark, round, phase rail and scores. Display only: it is told what to show.

signal info_pressed
signal settings_pressed

const PHASES: Array[String] = ["command", "movement", "shooting", "charge", "fight"]

var _wordmark: HBoxContainer
var _round: Label
var _steps: Array[PanelContainer] = []
var _step_labels: Array[Array] = []
var _vp: Array[Label] = []
var _cp: Array[Label] = []
var _who: Array[Label] = []
var _info: Button
var _settings: Button
var _compact: bool = false
var _tiny: bool = false


func _init() -> void:
	theme_type_variation = "BarPanel"
	custom_minimum_size.y = UITokens.TOP_BAR
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SPACE_4)
	add_child(row)
	_wordmark = make_wordmark("LabelWordmarkSmall")
	row.add_child(_wordmark)
	_round = Label.new()
	_round.theme_type_variation = "LabelSection"
	_round.uppercase = true
	row.add_child(_round)

	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", 2)
	rail.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rail)
	for i in range(PHASES.size()):
		rail.add_child(_build_step(i))

	row.add_child(_build_score(0))
	row.add_child(_build_score(1))
	_info = _bar_button(UIText.t("button.info"), func() -> void: info_pressed.emit())
	row.add_child(_info)
	_settings = _bar_button(UIText.t("button.settings"), func() -> void: settings_pressed.emit())
	row.add_child(_settings)


## The MUSTER/ wordmark, shared by the bars, the roster and the title screen.
static func make_wordmark(style: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.theme_type_variation = style
	name_label.text = UIText.t("brand.name")
	box.add_child(name_label)
	var slash := Label.new()
	slash.theme_type_variation = style
	slash.text = "/"
	slash.add_theme_color_override("font_color", UITokens.ACTION)
	box.add_child(slash)
	return box


## One step in the phase rail, such as "3 SHOOT".
func _build_step(index: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := HBoxContainer.new()
	chip.add_child(box)
	var num := Label.new()
	num.theme_type_variation = "LabelSmallStat"
	num.text = str(index + 1)
	box.add_child(num)
	var lab := Label.new()
	lab.theme_type_variation = "LabelSection"
	lab.uppercase = true
	lab.text = UIText.t("rail." + PHASES[index])
	box.add_child(lab)
	_steps.append(chip)
	_step_labels.append([num, lab])
	return chip


func _build_score(side: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_child(ShapeMark.new(side))
	var who := Label.new()
	who.theme_type_variation = "LabelSection"
	who.text = UIText.t("side.you") if side == 0 else UIText.t("side.ai")
	who.uppercase = true
	who.add_theme_color_override("font_color", UITokens.SIDE_COLOURS[side])
	box.add_child(who)
	var vp := Label.new()
	vp.theme_type_variation = "LabelScore"
	box.add_child(vp)
	var cp := Label.new()
	cp.theme_type_variation = "LabelSmallStat"
	box.add_child(cp)
	_who.append(who)
	_vp.append(vp)
	_cp.append(cp)
	return box


func _bar_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	b.pressed.connect(handler)
	return b


## Compact keeps only the current phase. Tiny also drops the wordmark and command points.
func set_density(compact: bool, tiny: bool, show_info: bool) -> void:
	_compact = compact
	_tiny = tiny
	_wordmark.visible = not compact
	_info.visible = show_info
	for side in range(2):
		_cp[side].visible = not tiny
		_who[side].visible = not tiny


func refresh(round_no: int, total_rounds: int, my_turn: bool, phase: String, cp: Array, vp: Array) -> void:
	var turn: String = UIText.t("side.you_turn") if my_turn else UIText.t("side.ai_turn")
	if _tiny:
		_round.text = UIText.t("hud.round_short", [round_no, total_rounds])
	elif _compact:
		_round.text = turn
	else:
		_round.text = "%s · %s" % [UIText.t("hud.round", [round_no, total_rounds]), turn]
	var current: int = PHASES.find(phase)
	for i in range(PHASES.size()):
		var on: bool = i == current
		_steps[i].theme_type_variation = "StepOn" if on else "StepOff"
		_steps[i].visible = on or not _compact
		var ink: Color = UITokens.ON_ACTION if on else (UITokens.INK_DIM if i < current else UITokens.INK_FAINT)
		for lab in _step_labels[i]:
			(lab as Label).add_theme_color_override("font_color", ink)
	for side in range(2):
		_vp[side].text = str(vp[side])
		_cp[side].text = UIText.t("hud.cp", [cp[side]])
