class_name RosterScreen
extends PanelContainer
## Pick an army and units for each side before the battle. Setup only: nothing here
## touches battle state. Emits [signal started] with the two army dictionaries that
## [Battle] takes. Datasheets have no points, so sides are balanced by eye.

signal started(armies: Array)

const MAX_UNITS := 12
const NARROW_WIDTH := 900.0
const ROW_HEIGHT := 60
const TINY_WIDTH := 560.0
const SHORT_HEIGHT := 500.0

var _armies: Array = []
var _sides: Array[Dictionary] = []     ## per side: widgets and picks
var _row: BoxContainer
var _status: Label
var _wordmark: Control
var _hint: Label
var _start: Button
var _web_callback: JavaScriptObject
var _extra_path: String = ""


func setup(extra_path: String = "", local: bool = true) -> void:
	_extra_path = extra_path
	_armies = ArmyLoader.load_all(extra_path, local)
	_build()
	for side in range(2):
		_fill_army_options(side)
		_set_army(side, _default_army_for(side))
	_update_start()


# ---------------------------------------------------------------- building

func _build() -> void:
	theme_type_variation = "Screen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITokens.SPACE_3)
	margin.add_theme_constant_override("margin_right", UITokens.SPACE_3)
	margin.add_theme_constant_override("margin_top", UITokens.SPACE_3)
	margin.add_theme_constant_override("margin_bottom", UITokens.SPACE_3)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITokens.SPACE_3)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SPACE_4)
	root.add_child(head)
	_wordmark = TopBar.make_wordmark("LabelWordmarkSmall")
	head.add_child(_wordmark)
	var title := Label.new()
	title.text = UIText.t("roster.title")
	title.theme_type_variation = "LabelTitle"
	head.add_child(title)
	_hint = Label.new()
	_hint.text = UIText.t("roster.hint")
	_hint.theme_type_variation = "LabelMeta"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_row = BoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override("separation", UITokens.SPACE_6)
	scroll.add_child(_row)
	for side in range(2):
		_sides.append(_build_side(side))

	var bar := HFlowContainer.new()
	root.add_child(bar)
	bar.add_child(_button(UIText.t("roster.load_file"), _on_load_pressed))
	bar.add_child(_button(UIText.t("roster.quick_fill"), _on_quick_fill))
	_status = Label.new()
	_status.theme_type_variation = "LabelDim"
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	_start = _button(UIText.t("roster.start"), _on_start)
	_start.theme_type_variation = "PrimaryButton"
	_start.icon = UIIcons.stripe(UITokens.ON_ACTION)
	bar.add_child(_start)
	resized.connect(_on_resized)
	_on_resized()


func _build_side(side: int) -> Dictionary:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UITokens.SPACE_2)
	_row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(ShapeMark.new(side, 14.0))
	var header := Label.new()
	header.text = UIText.t("roster.side_you") if side == 0 else UIText.t("roster.side_opponent")
	header.theme_type_variation = "LabelHeading"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(header)
	var picked_label := Label.new()
	picked_label.theme_type_variation = "LabelSmallStat"
	head.add_child(picked_label)
	var army_opt := OptionButton.new()
	army_opt.custom_minimum_size.y = UITokens.HIT
	army_opt.clip_text = true
	army_opt.item_selected.connect(func(i: int) -> void: _set_army(side, i))
	col.add_child(army_opt)
	var search := LineEdit.new()
	search.placeholder_text = UIText.t("roster.search")
	search.custom_minimum_size.y = UITokens.HIT
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t: String) -> void: _fill_available(side))
	col.add_child(search)
	var avail_scroll := ScrollContainer.new()
	avail_scroll.custom_minimum_size.y = 240
	avail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(avail_scroll)
	var avail := VBoxContainer.new()
	avail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_scroll.add_child(avail)
	var picks_title := Label.new()
	picks_title.text = UIText.t("roster.picks_title")
	picks_title.theme_type_variation = "LabelSection"
	picks_title.uppercase = true
	col.add_child(picks_title)
	var picks_scroll := ScrollContainer.new()
	picks_scroll.custom_minimum_size.y = 200
	picks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(picks_scroll)
	var picks_box := VBoxContainer.new()
	picks_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picks_scroll.add_child(picks_box)
	return {"army_opt": army_opt, "search": search, "avail": avail, "picked_label": picked_label,
		"picks_box": picks_box, "army": -1, "picks": [], "shown": []}


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UITokens.HIT * 2, UITokens.HIT)
	b.pressed.connect(handler)
	return b


func _on_resized() -> void:
	if _row == null:
		return
	_row.vertical = size.x < NARROW_WIDTH
	_wordmark.visible = size.x >= TINY_WIDTH
	_hint.visible = size.y >= SHORT_HEIGHT
	# Wide: share the spare height between the two lists. Narrow: fixed heights, page scrolls.
	var spare: float = maxf(size.y - 400.0, 280.0)
	for s in _sides:
		(s["avail"] as Control).get_parent().custom_minimum_size.y = 240.0 if _row.vertical else spare * 0.55
		(s["picks_box"] as Control).get_parent().custom_minimum_size.y = 200.0 if _row.vertical else spare * 0.45


# ---------------------------------------------------------------- data

func _default_army_for(side: int) -> int:
	if _armies.is_empty():
		return -1
	# Prefer the user's own armies over the invented placeholders.
	var own: Array = []
	var all: Array = []
	for i in range(_armies.size()):
		all.append(i)
		if not str(_armies[i].get("source", "")).ends_with("armies_placeholder.json"):
			own.append(i)
	var pool: Array = own if own.size() >= 2 else all
	return int(pool[mini(side, pool.size() - 1)])


func _fill_army_options(side: int) -> void:
	var opt: OptionButton = _sides[side]["army_opt"]
	opt.clear()
	for a in _armies:
		opt.add_item(UIText.t("roster.army_entry", [str(a["name"]).replace("_", " "), (a["units"] as Array).size()]))


func _set_army(side: int, index: int) -> void:
	var s: Dictionary = _sides[side]
	s["army"] = index
	s["picks"] = []
	if index >= 0:
		(s["army_opt"] as OptionButton).select(index)
	_fill_available(side)
	_fill_picks(side)
	_update_start()


func _models_text(u: Dictionary) -> String:
	if ArmyLoader.max_models(u) <= 1:
		return UIText.t("roster.model_one")
	var count: String = str(ArmyLoader.min_models(u))
	if ArmyLoader.max_models(u) > ArmyLoader.min_models(u):
		count += "-%d" % ArmyLoader.max_models(u)
	return UIText.t("roster.models_range", [count])


func _stats_text(u: Dictionary) -> String:
	return UIText.t("roster.unit_stats", [int(u.get("move", 0)), int(u.get("toughness", 0)),
		int(u.get("save", 7)), int(u.get("wounds", 1))])


# ---------------------------------------------------------------- lists

func _fill_available(side: int) -> void:
	var s: Dictionary = _sides[side]
	var box: VBoxContainer = s["avail"]
	_clear(box)
	s["shown"] = []
	if s["army"] < 0:
		return
	var needle: String = (s["search"] as LineEdit).text.strip_edges().to_lower()
	var units: Array = _armies[s["army"]]["units"]
	for i in range(units.size()):
		var u: Dictionary = units[i]
		if needle != "" and not str(u["name"]).to_lower().contains(needle):
			continue
		s["shown"].append(i)
		box.add_child(_unit_row(side, i, u))
	if box.get_child_count() == 0:
		var empty := Label.new()
		empty.text = UIText.t("roster.no_match")
		empty.theme_type_variation = "LabelDim"
		box.add_child(empty)


## A selectable row: a check, the unit's name and size, and its key stats.
func _unit_row(side: int, index: int, u: Dictionary) -> Button:
	var count: int = 0
	for p in _sides[side]["picks"]:
		if p["unit"] == u:
			count += 1
	var b := Button.new()
	b.theme_type_variation = "RowButtonOn" if count > 0 else "RowButton"
	b.custom_minimum_size.y = ROW_HEIGHT
	b.tooltip_text = _unit_tooltip(u)
	b.pressed.connect(_add_pick.bind(side, index))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITokens.SPACE_3
	row.offset_right = -UITokens.SPACE_3
	row.add_theme_constant_override("separation", UITokens.SPACE_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var check := TextureRect.new()
	check.texture = UIIcons.get_icon("box_check" if count > 0 else "box", UITokens.ACTION if count > 0 else UITokens.EDGE_STRONG, 20)
	check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(check)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	var name_label := Label.new()
	name_label.text = str(u["name"]) if count <= 1 else "%s  ×%d" % [u["name"], count]
	name_label.theme_type_variation = "LabelRowName"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(name_label)
	var models := Label.new()
	models.text = _models_text(u)
	models.theme_type_variation = "LabelMeta"
	names.add_child(models)
	var stats := Label.new()
	stats.text = _stats_text(u)
	stats.theme_type_variation = "LabelSmallStat"
	stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(stats)
	return b


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _unit_tooltip(u: Dictionary) -> String:
	var lines: PackedStringArray = []
	for w in u.get("weapons", []):
		lines.append("%s  %s" % [w["name"], " ".join(w.get("abilities", []))])
	return "\n".join(lines)


func _add_pick(side: int, unit_index: int) -> void:
	var s: Dictionary = _sides[side]
	if (s["picks"] as Array).size() >= MAX_UNITS:
		_status.text = UIText.t("roster.max_units", [MAX_UNITS])
		return
	var u: Dictionary = _armies[s["army"]]["units"][unit_index]
	(s["picks"] as Array).append({"unit": u, "models": ArmyLoader.min_models(u)})
	_status.text = ""
	_fill_available(side)
	_fill_picks(side)
	_update_start()


func _remove_pick(side: int, pick_index: int) -> void:
	(_sides[side]["picks"] as Array).remove_at(pick_index)
	_fill_available(side)
	_fill_picks(side)
	_update_start()


func _fill_picks(side: int) -> void:
	var s: Dictionary = _sides[side]
	var box: VBoxContainer = s["picks_box"]
	_clear(box)
	var picks: Array = s["picks"]
	(s["picked_label"] as Label).text = UIText.t("roster.picked", [picks.size(), MAX_UNITS])
	for i in range(picks.size()):
		var p: Dictionary = picks[i]
		var u: Dictionary = p["unit"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SPACE_2)
		var name_label := Label.new()
		name_label.text = u["name"]
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if ArmyLoader.max_models(u) > ArmyLoader.min_models(u):
			var spin := SpinBox.new()
			spin.min_value = ArmyLoader.min_models(u)
			spin.max_value = ArmyLoader.max_models(u)
			spin.value = p["models"]
			spin.custom_minimum_size = Vector2(UITokens.HIT * 2.5, UITokens.HIT)
			spin.value_changed.connect(func(v: float) -> void: p["models"] = int(v))
			row.add_child(spin)
		var rm := Button.new()
		rm.icon = UIIcons.get_icon("close", UITokens.INK, 18)
		rm.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rm.tooltip_text = UIText.t("roster.remove")
		rm.custom_minimum_size = Vector2(UITokens.HIT, UITokens.HIT)
		rm.pressed.connect(_remove_pick.bind(side, i))
		row.add_child(rm)
		box.add_child(row)


# ---------------------------------------------------------------- actions

func _update_start() -> void:
	var ready_to_go: bool = true
	for s in _sides:
		if (s["picks"] as Array).is_empty():
			ready_to_go = false
	_start.disabled = not ready_to_go


func _on_quick_fill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for side in range(2):
		var s: Dictionary = _sides[side]
		if s["army"] < 0:
			continue
		s["picks"] = []
		var units: Array = _armies[s["army"]]["units"]
		var order: Array = range(units.size())
		order.shuffle()
		for idx in order.slice(0, mini(5, units.size())):
			var u: Dictionary = units[idx]
			(s["picks"] as Array).append({"unit": u, "models": ArmyLoader.min_models(u)})
		_fill_available(side)
		_fill_picks(side)
	_update_start()


func _on_start() -> void:
	var out: Array = []
	for s in _sides:
		var units: Array = []
		for p in s["picks"]:
			units.append(ArmyLoader.prepare_unit(p["unit"], int(p["models"])))
		out.append({"name": _armies[s["army"]]["name"], "units": units})
	started.emit(out)


# ---------------------------------------------------------------- loading army files

func _on_load_pressed() -> void:
	if OS.has_feature("web"):
		_web_pick()
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.json ; Army files"])
	dlg.use_native_dialog = true
	dlg.file_selected.connect(func(path: String) -> void:
		_import_text(FileAccess.get_file_as_string(path), path.get_file())
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func _web_pick() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		_import_text(str(args[0]), str(args[1])))
	JavaScriptBridge.get_interface("window").godotRosterCb = _web_callback
	JavaScriptBridge.eval("""
	(function(){
	  try {
	    console.log('roster: opening file picker');
	    var i = document.createElement('input'); i.type = 'file'; i.accept = '.json,application/json';
	    i.onchange = function(){ var f = i.files[0]; if (!f) return; var r = new FileReader();
	      r.onload = function(){ window.godotRosterCb(r.result, f.name); }; r.readAsText(f); };
	    i.click();
	  } catch (e) { console.log('roster: picker failed ' + e); }
	})();
	""")


## Add the armies in this JSON text, and keep a copy in user://armies for next time.
func _import_text(text: String, file_name: String, persist: bool = true) -> void:
	var found: Array = ArmyLoader.parse_text(text, "user://armies/" + file_name)
	if found.is_empty():
		_status.text = UIText.t("roster.load_failed", [file_name])
		return
	if persist:
		DirAccess.make_dir_recursive_absolute("user://armies")
		var f := FileAccess.open("user://armies/" + file_name, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	_armies.append_array(found)
	for side in range(2):
		_fill_army_options(side)
		_sides[side]["army_opt"].select(_sides[side]["army"])
	_status.text = UIText.t("roster.loaded", [found.size(), file_name])
