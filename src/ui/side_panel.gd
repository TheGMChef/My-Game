class_name SidePanel
extends PanelContainer
## Orders, Unit, Log and Units tabs. Display only: the controller passes plain view data.
## Odds: {"heading", "total", "lost", "fraction", "rows": [{"title", "note", "tiles": [[label, value]]}]}
## or {"none": text}. Unit: {"side", "name", "note", "tiles", "extras", "weapons": [[name, line, index, on]]}
## with an index of -1 for a weapon that has no range to show.
## Log lines: {"text", "side"}. Units: {"id", "side", "name", "count", "selected", "marks": [[text, colour]]}.

signal rules_pressed
signal unit_row_pressed(unit_id: String)
signal weapon_pressed(index: int)

const TAB_KEYS: Array[String] = ["tab.orders", "tab.unit", "tab.log", "tab.units"]
const LATEST := 3
const LOG_LINE_HEIGHT := 22.0

var _tabs: Array[Button] = []
var _pages: Array[ScrollContainer] = []
var _title: Label
var _rules: Button
var _body: Label
var _detail: RichTextLabel
var _odds_box: VBoxContainer
var _latest: VBoxContainer
var _latest_title: Label
var _unit_box: VBoxContainer
var _log_box: VBoxContainer
var _units_box: VBoxContainer
var _units_view: Array = []
var _odds_view: Dictionary = {"unset": true}
var _unit_view: Dictionary = {"unset": true}
var _log_seen: Array = []


func _init() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITokens.SPACE_3)
	add_child(col)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	col.add_child(tab_row)
	var group := ButtonGroup.new()
	for i in range(TAB_KEYS.size()):
		var b := Button.new()
		b.theme_type_variation = "TabButton"
		b.text = UIText.t(TAB_KEYS[i]).to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.y = UITokens.HIT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_page.bind(i))
		tab_row.add_child(b)
		_tabs.append(b)
	_pages = [_page(col), _page(col), _page(col), _page(col)]
	_build_orders(_pages[0].get_child(0))
	_unit_box = _pages[1].get_child(0)
	_log_box = _pages[2].get_child(0)
	_units_box = _pages[3].get_child(0)
	_tabs[0].button_pressed = true
	_show_page(0)


func _page(parent: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", UITokens.SPACE_3)
	s.add_child(v)
	return s


func _build_orders(col: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = "LabelHeading"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_rules = Button.new()
	_rules.text = UIText.t("button.rules")
	_rules.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
	_rules.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rules.pressed.connect(func() -> void: rules_pressed.emit())
	head.add_child(_rules)
	_body = _wrapped("LabelBody")
	col.add_child(_body)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_detail)
	_odds_box = VBoxContainer.new()
	col.add_child(_odds_box)
	_latest_title = _section(UIText.t("panel.latest"))
	col.add_child(_latest_title)
	_latest = VBoxContainer.new()
	col.add_child(_latest)


func _show_page(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index


func show_orders(title: String, body: String, detail: String, rules: bool = true) -> void:
	_title.text = title
	_rules.visible = rules
	_body.text = body
	_body.visible = body != ""
	_detail.text = detail
	_detail.visible = detail != ""


func show_odds(view: Dictionary) -> void:
	if view == _odds_view:
		return
	_odds_view = view
	_clear(_odds_box)
	if view.is_empty():
		return
	if view.has("none"):
		_odds_box.add_child(_wrapped("LabelDim", str(view["none"])))
		return
	var card := _card()
	_odds_box.add_child(card)
	var col: VBoxContainer = card.get_child(0)
	var heading := _section(str(view["heading"]))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(heading)
	var row := HBoxContainer.new()
	col.add_child(row)
	var total := Label.new()
	total.theme_type_variation = "LabelReadout"
	total.text = "%.1f" % float(view["total"])
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(total)
	var note := Label.new()
	note.theme_type_variation = "LabelMeta"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.text = "%s\n%s" % [UIText.t("odds.caption"), UIText.t("odds.models_lost", [float(view["lost"])])]
	row.add_child(note)
	col.add_child(_bar(float(view["fraction"])))
	for r in view["rows"]:
		if str(r["title"]) != "":
			col.add_child(_wrapped("LabelBody", str(r["title"])))
		col.add_child(_tiles(r["tiles"]))
		col.add_child(_wrapped("LabelMeta", str(r["note"])))


func show_unit(view: Dictionary) -> void:
	if view == _unit_view:
		return
	_unit_view = view
	var focused: String = _focused_row()
	_clear(_unit_box)
	if view.is_empty():
		_unit_box.add_child(_wrapped("LabelDim", UIText.t("hint.no_unit")))
		return
	_unit_box.add_child(_unit_card(view))
	_restore_row(_unit_box, focused)


## The Units tab: your units, then the enemy's. Tapping a row reports its unit.
func show_units(rows: Array) -> void:
	if rows == _units_view:
		return
	_units_view = rows.duplicate(true)
	var focused: String = _focused_row()
	_clear(_units_box)
	for side in range(2):
		var mine: Array = rows.filter(func(r: Dictionary) -> bool: return int(r["side"]) == side)
		if mine.is_empty():
			continue
		_units_box.add_child(_section(UIText.t("panel.your_units") if side == 0 else UIText.t("panel.enemy_units")))
		for r in mine:
			_units_box.add_child(_unit_row(r))
	_restore_row(_units_box, focused)


func show_log(lines: Array) -> void:
	if lines == _log_seen:
		return
	_log_seen = lines.duplicate()
	_clear(_log_box)
	_clear(_latest)
	var count: int = lines.size()
	for i in range(count - 1, -1, -1):
		_log_box.add_child(_log_row(lines[i]))
	for i in range(maxi(0, count - LATEST), count):
		_latest.add_child(_log_row(lines[i]))
	_latest_title.visible = count > 0


func _unit_row(r: Dictionary) -> TapRow:
	var row := TapRow.new(str(r["id"]), bool(r["selected"]))
	var box := HBoxContainer.new()
	row.add_child(box)
	box.add_child(ShapeMark.new(int(r["side"]), 14.0))
	var name_label := Label.new()
	name_label.theme_type_variation = "LabelRowName"
	name_label.text = str(r["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)
	for mark in r["marks"]:
		var chip := Label.new()
		chip.theme_type_variation = "LabelMeta"
		chip.text = str(mark[0])
		chip.add_theme_color_override("font_color", mark[1])
		box.add_child(chip)
	var count := Label.new()
	count.theme_type_variation = "LabelStat"
	count.text = str(r["count"])
	box.add_child(count)
	row.pressed.connect(func() -> void: unit_row_pressed.emit(str(r["id"])))
	return row


## A weapon on the Unit tab. One with a range is a row that toggles its ring on the board.
func _weapon_row(w: Array) -> Control:
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(_wrapped("LabelBody", str(w[0])))
	text.add_child(_wrapped("LabelMeta", str(w[1])))
	if int(w[2]) < 0:
		return text
	var row := TapRow.new("weapon_%d" % int(w[2]), bool(w[3]))
	row.tooltip_text = UIText.t("tip.weapon_ring")
	row.add_child(text)
	row.pressed.connect(func() -> void: weapon_pressed.emit(int(w[2])))
	return row


func _focused_row() -> String:
	var owner_now: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return (owner_now as TapRow).key if owner_now is TapRow and is_ancestor_of(owner_now) else ""


func _restore_row(box: Control, key: String) -> void:
	if key == "":
		return
	var row: TapRow = _find_row(box, key)
	if row != null:
		row.grab_focus()


func _find_row(node: Node, key: String) -> TapRow:
	if node is TapRow and (node as TapRow).key == key:
		return node
	for c in node.get_children():
		var found: TapRow = _find_row(c, key)
		if found != null:
			return found
	return null


func _unit_card(view: Dictionary) -> PanelContainer:
	var card := _card()
	var col: VBoxContainer = card.get_child(0)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(ShapeMark.new(int(view["side"])))
	var name_label := Label.new()
	name_label.theme_type_variation = "LabelHeading"
	name_label.text = str(view["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_label)
	var note := Label.new()
	note.theme_type_variation = "LabelMeta"
	note.text = str(view["note"])
	head.add_child(note)
	col.add_child(_tiles(view["tiles"]))
	if not (view["extras"] as Array).is_empty():
		col.add_child(_wrapped("LabelMeta", ", ".join(view["extras"])))
	for w in view["weapons"]:
		col.add_child(_weapon_row(w))
	return card


func _log_row(line: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var mark := ShapeMark.new(int(line["side"]), 10.0)
	mark.custom_minimum_size.y = LOG_LINE_HEIGHT    # keeps the mark level with the first line
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	row.add_child(_wrapped("LabelDim", str(line["text"])))
	return row


func _card() -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = "Card"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UITokens.SPACE_3)
	c.add_child(v)
	return c


func _tiles(tiles: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = tiles.size()
	grid.add_theme_constant_override("h_separation", UITokens.SPACE_1)
	for t in tiles:
		var tile := PanelContainer.new()
		tile.theme_type_variation = "Tile"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		tile.add_child(v)
		var lab := _section(str(t[0]))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lab)
		var val := Label.new()
		val.theme_type_variation = "LabelStat"
		val.text = str(t[1])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(val)
		grid.add_child(tile)
	return grid


func _bar(fraction: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = UITokens.SPACE_2
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(fraction, 0.0, 1.0)
	var back := StyleBoxFlat.new()
	back.bg_color = UITokens.RAISED
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITokens.ENEMY
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _section(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "LabelSection"
	l.uppercase = true
	l.text = text
	return l


func _wrapped(style: String, text: String = "") -> Label:
	var l := Label.new()
	l.theme_type_variation = style
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
