class_name ReactionPrompt
extends PanelContainer
## A compact question over the board when a stratagem can answer the opponent: what it is, what it
## costs, and Use or Pass, with no timer. Nothing here changes the game: it reports the choice.
## View: {"title", "effect", "cp", "rows": [text]}. The first row is the one main action.

signal use_pressed(index: int)
signal pass_pressed

const WIDTH := 420.0
const MARGIN := 8.0

var _title: Label
var _effect: Label
var _cp: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _pass: Button
var _first: Button


func _init() -> void:
	theme_type_variation = "Dialog"
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITokens.SPACE_2)
	add_child(col)
	_title = _label(col, "LabelHeading")
	_effect = _label(col, "LabelBody")
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	col.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", UITokens.SPACE_1)
	_scroll.add_child(_rows)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	_cp = _label(foot, "LabelMeta")
	_cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pass = Button.new()
	_pass.theme_type_variation = "GhostButton"
	_pass.text = UIText.t("prompt.pass")
	_pass.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	_pass.pressed.connect(func() -> void: pass_pressed.emit())
	foot.add_child(_pass)


func _label(parent: Control, style: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = style
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func ask(view: Dictionary) -> void:
	_title.text = str(view["title"])
	_effect.text = str(view["effect"])
	_cp.text = str(view["cp"])
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_first = null
	var rows: Array = view["rows"]
	for i in range(rows.size()):
		var b := Button.new()
		b.text = str(rows[i])
		b.custom_minimum_size.y = UITokens.HIT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if i == 0:
			b.theme_type_variation = "PrimaryButton"
			b.icon = UIIcons.stripe(UITokens.ON_ACTION)
			_first = b
		b.pressed.connect(func() -> void: use_pressed.emit(i))
		_rows.add_child(b)
	visible = true
	refit()
	_settle()
	_focus_first.call_deferred()


## Wrapped text only knows its height once it has been laid out at its width, a frame later.
func _settle() -> void:
	for i in range(2):
		await get_tree().process_frame
		if not is_inside_tree():
			return
		refit()


func _focus_first() -> void:
	if visible and is_instance_valid(_first) and _first.is_inside_tree():
		_first.grab_focus()


## Keep the box inside the board: a fixed width where it fits, and the rows scroll when short of height.
func refit() -> void:
	var holder: Control = get_parent()
	if holder == null or not visible:
		return
	var room: Vector2 = holder.size - Vector2(MARGIN, MARGIN) * 2.0
	var width: float = minf(WIDTH, room.x)
	var inner: float = width - get_theme_stylebox("panel").get_minimum_size().x
	for l: Label in [_title, _effect]:
		l.custom_minimum_size.x = inner
	var without_rows: float = get_theme_stylebox("panel").get_minimum_size().y
	var col: VBoxContainer = get_child(0)
	for c: Control in col.get_children():
		if c != _scroll:
			without_rows += c.get_combined_minimum_size().y
	without_rows += float(col.get_theme_constant("separation") * (col.get_child_count() - 1))
	var wanted: float = _rows.get_combined_minimum_size().y
	var fits: float = maxf(float(UITokens.HIT), room.y - without_rows)
	_scroll.custom_minimum_size.y = minf(wanted, fits)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if wanted <= fits else ScrollContainer.SCROLL_MODE_AUTO
	size = Vector2.ZERO
	position = Vector2((holder.size.x - width) * 0.5, MARGIN)
	size = Vector2(width, get_combined_minimum_size().y)


func close() -> void:
	visible = false
