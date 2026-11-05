class_name BoardView
extends Control
## Draws the board and reports taps and drags. It reads the [Battle] but never changes it:
## anything it shows that is not in the battle (selection, a pending move, highlights) is
## presentation state set by the controller.

signal unit_tapped(unit: UnitState)
signal empty_tapped(world_pos: Vector2)
signal drag_moved(unit: UnitState, delta: Vector2)
signal drag_ended(unit: UnitState, delta: Vector2)
## Emitted when a second finger lands mid-drag, so the move preview is thrown away.
signal drag_cancelled
signal view_changed

const MIN_TAP_RADIUS := 28.0
const DRAG_START_PX := 10.0

const LABEL_MIN_PPI: float = 9.0
const RAIL_MIN_PPI: float = 11.0
const GRID_STEP: float = 6.0
const PLATE_NAME_MAX := 22
const PLATE_GAP := 8.0
const BOARD_MARGIN := 24.0
const BOARD_MARGIN_NO_RAILS := 6.0

## How a unit is marked for the current order. Set per unit in [member highlights].
const MARK_IN_RANGE := "in_range"
const MARK_TARGET := "target"

var battle: Battle
var settings: UISettings = UISettings.new()

# Presentation state, set by the controller
var selected: UnitState
var ghost: Array[Vector2] = []
var ghost_ok: bool = true
var ring_centre: Vector2 = Vector2.ZERO
var ring_radius: float = 0.0
var highlights: Dictionary = {}          # UnitState -> MARK_IN_RANGE or MARK_TARGET
var los_line: Array[Vector2] = []
var los_blocked: bool = false
var anim_positions: Dictionary = {}      # unit id -> Array[Vector2]
var acted: Array = []                    # units that have used their action this phase
var drag_enabled: bool = false

var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO          # screen px offset added to the fitted position
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _drag_unit: UnitState
var _panning: bool = false
var _moved_far: bool = false
var _touches: Dictionary = {}              # finger index -> position
var _pinch_dist: float = 0.0
var _pinch_mid: Vector2 = Vector2.ZERO
var _fx: Array[Dictionary] = []
var _plate_box: StyleBoxFlat = UIThemeBuilder.notch(UITokens.HULL, UITokens.EDGE, UITokens.NOTCH_SM / 2, 0)
var _plate_font: Font = UIThemeBuilder.spaced(UITokens.FONT_DISPLAY)


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


# ---------------------------------------------------------------- camera

func pixels_per_inch() -> float:
	if battle == null:
		return 1.0
	var fit: float = _fit_scale(BOARD_MARGIN)
	if fit < RAIL_MIN_PPI:
		fit = _fit_scale(BOARD_MARGIN_NO_RAILS)    # no edge labels to make room for
	return maxf(1.0, fit) * _zoom


func _fit_scale(margin: float) -> float:
	return minf((size.x - margin * 2.0) / battle.board.size.x, (size.y - margin * 2.0) / battle.board.size.y)


func _origin() -> Vector2:
	var board_px: Vector2 = battle.board.size * pixels_per_inch()
	return (size - board_px) * 0.5 + _pan


func world_to_screen(p: Vector2) -> Vector2:
	return _origin() + p * pixels_per_inch()


func screen_to_world(p: Vector2) -> Vector2:
	return (p - _origin()) / pixels_per_inch()


func zoom_by(factor: float, around: Vector2 = Vector2(-1, -1)) -> void:
	var anchor: Vector2 = around if around.x >= 0.0 else size * 0.5
	var world_before: Vector2 = screen_to_world(anchor)
	_zoom = clampf(_zoom * factor, 1.0, 4.0)
	var after: Vector2 = world_to_screen(world_before)
	_pan += anchor - after
	_clamp_pan()
	view_changed.emit()
	queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	view_changed.emit()
	queue_redraw()


func _clamp_pan() -> void:
	if _zoom <= 1.0:
		_pan = Vector2.ZERO
		return
	var board_px: Vector2 = battle.board.size * pixels_per_inch()
	var slack: Vector2 = Vector2(maxf(0.0, (board_px.x - size.x) * 0.5 + 64.0), maxf(0.0, (board_px.y - size.y) * 0.5 + 64.0))
	_pan = _pan.clamp(-slack, slack)


# ---------------------------------------------------------------- effects

## A short line between two world points, e.g. a shot. Skipped for reduced motion (drawn static, briefly).
func flash(from_world: Vector2, to_world: Vector2, colour: Color, seconds: float = 0.8) -> void:
	_fx.append({"from": from_world, "to": to_world, "colour": colour, "life": seconds, "age": 0.0})
	set_process(true)
	queue_redraw()


func clear_effects() -> void:
	_fx.clear()
	queue_redraw()


func _process(delta: float) -> void:
	for f in _fx:
		f["age"] = float(f["age"]) + delta
	_fx = _fx.filter(func(f: Dictionary) -> bool: return float(f["age"]) < float(f["life"]))
	if _fx.is_empty():
		set_process(false)
	queue_redraw()


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return  # a finger pretending to be a mouse; real touch events below handle fingers
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_on_press(mb.position, mb.button_index == MOUSE_BUTTON_MIDDLE)
			else:
				_on_release(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing:
			_on_motion(mm.position, mm.relative)
	elif event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		zoom_by((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
	elif event is InputEventPanGesture:
		_pan -= (event as InputEventPanGesture).delta * 8.0
		_clamp_pan()
		queue_redraw()


## Two fingers pinch to zoom and slide to pan; they cancel any one-finger drag in progress.
func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_on_press(t.position, false)
		elif _touches.size() == 2:
			_cancel_press()
			_pinch_start()
	else:
		var was_single: bool = _touches.size() == 1
		_touches.erase(t.index)
		if was_single:
			_on_release(t.position)
		elif _touches.size() == 2:
			_pinch_start()


func _on_touch_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	_touches[d.index] = d.position
	if _touches.size() == 1:
		if _pressing:
			_on_motion(d.position, d.relative)
		return
	if _touches.size() != 2:
		return
	var pts: Array = _touches.values()
	var dist: float = (pts[0] as Vector2).distance_to(pts[1])
	var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
	if _pinch_dist > 8.0 and dist > 8.0:
		zoom_by(dist / _pinch_dist, mid)
	_pan += mid - _pinch_mid
	_clamp_pan()
	_pinch_dist = dist
	_pinch_mid = mid
	queue_redraw()


func _pinch_start() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _cancel_press() -> void:
	if _pressing and _drag_unit != null and _moved_far:
		drag_cancelled.emit()
	_pressing = false
	_drag_unit = null
	_panning = false


func _on_press(pos: Vector2, force_pan: bool) -> void:
	grab_focus()
	_pressing = true
	_press_pos = pos
	_moved_far = false
	_panning = false
	_drag_unit = null
	if drag_enabled and selected != null and not force_pan and unit_at(pos) == selected:
		_drag_unit = selected


func _on_motion(pos: Vector2, relative: Vector2) -> void:
	if not _moved_far and pos.distance_to(_press_pos) >= DRAG_START_PX:
		_moved_far = true
	if not _moved_far:
		return
	if _drag_unit != null:
		drag_moved.emit(_drag_unit, (pos - _press_pos) / pixels_per_inch())
	else:
		_panning = true
		_pan += relative
		_clamp_pan()
		queue_redraw()


func _on_release(pos: Vector2) -> void:
	if not _pressing:
		return
	_pressing = false
	if _drag_unit != null and _moved_far:
		drag_ended.emit(_drag_unit, (pos - _press_pos) / pixels_per_inch())
	elif not _moved_far:
		var hit: UnitState = unit_at(pos)
		if hit != null:
			unit_tapped.emit(hit)
		else:
			empty_tapped.emit(screen_to_world(pos))
	_drag_unit = null
	_panning = false


## The unit whose model is under a screen point (generous touch radius), or null.
func unit_at(screen_pos: Vector2) -> UnitState:
	var best: UnitState = null
	var best_d: float = INF
	for u in battle.units:
		var positions: Array[Vector2] = _positions_of(u)
		var r: float = maxf(u.base_radius * pixels_per_inch(), MIN_TAP_RADIUS)
		for p in positions:
			var d: float = world_to_screen(p).distance_to(screen_pos)
			if d <= r and d < best_d:
				best_d = d
				best = u
	return best


# ---------------------------------------------------------------- drawing

func _positions_of(u: UnitState) -> Array[Vector2]:
	if anim_positions.has(u.id):
		return anim_positions[u.id]
	var out: Array[Vector2] = []
	for m in u.models:
		out.append(m["pos"])
	return out


func _draw() -> void:
	if battle == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), UITokens.VOID)
	var ppi: float = pixels_per_inch()
	var board_rect := Rect2(_origin(), battle.board.size * ppi)
	draw_rect(board_rect, UITokens.BOARD_FLOOR)
	_draw_zones(ppi)
	_draw_grid(board_rect, ppi)
	_draw_rails(board_rect, ppi)
	_draw_terrain(ppi)
	if settings.show_objectives:
		_draw_objectives(ppi)
	if settings.show_coherency:
		_draw_coherency(ppi)
	draw_rect(board_rect, UITokens.EDGE_STRONG, false, 1.5)
	if settings.show_engagement:
		_draw_engagement(ppi)
	if ring_radius > 0.0:
		draw_arc(world_to_screen(ring_centre), ring_radius * ppi, 0.0, TAU, 96, UITokens.with_alpha(UITokens.ACTION, 0.8), 2.0, true)
	if los_line.size() == 2:
		var c: Color = UITokens.illegal(settings.colour_blind) if los_blocked else UITokens.INK
		draw_dashed_line(world_to_screen(los_line[0]), world_to_screen(los_line[1]), c, 2.0, 6.0)
	for u in battle.units:
		_draw_unit(u, ppi)
	_draw_ghost(ppi)
	for f in _fx:
		var t: float = clampf(float(f["age"]) / float(f["life"]), 0.0, 1.0)
		var col: Color = f["colour"]
		draw_line(world_to_screen(f["from"]), world_to_screen(f["to"]), UITokens.with_alpha(col, 1.0 - t * 0.7), 4.0)
	_draw_plates(ppi, board_rect)


func _draw_grid(board_rect: Rect2, ppi: float) -> void:
	var x: float = GRID_STEP
	while x < battle.board.size.x:
		var sx: float = board_rect.position.x + x * ppi
		draw_line(Vector2(sx, board_rect.position.y), Vector2(sx, board_rect.end.y), UITokens.BOARD_GRID, 1.0)
		x += GRID_STEP
	var y: float = GRID_STEP
	while y < battle.board.size.y:
		var sy: float = board_rect.position.y + y * ppi
		draw_line(Vector2(board_rect.position.x, sy), Vector2(board_rect.end.x, sy), UITokens.BOARD_GRID, 1.0)
		y += GRID_STEP


## Letters along the top and numbers down the side, one for each 6-inch square.
func _draw_rails(board_rect: Rect2, ppi: float) -> void:
	if ppi < RAIL_MIN_PPI:
		return
	var font: Font = UITokens.FONT_MONO
	var size_px: int = UITokens.TEXT_META
	var i: int = 0
	while float(i + 1) * GRID_STEP <= battle.board.size.x:
		var text: String = "ABCDEFGHIJKL"[i]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var cx: float = board_rect.position.x + (float(i) + 0.5) * GRID_STEP * ppi
		draw_string(font, Vector2(cx - w * 0.5, board_rect.position.y - 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, UITokens.INK_FAINT)
		i += 1
	i = 0
	while float(i + 1) * GRID_STEP <= battle.board.size.y:
		var cy: float = board_rect.position.y + (float(i) + 0.5) * GRID_STEP * ppi
		draw_string(font, Vector2(board_rect.position.x - 14.0, cy + 4.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, UITokens.INK_FAINT)
		i += 1


func _draw_zones(ppi: float) -> void:
	var keys: Array[String] = ["attacker", "defender"]
	for side in range(2):
		var r: Array = battle.scenario["deployment_zones"][keys[side]]["rect"]
		var rect := Rect2(world_to_screen(Vector2(float(r[0]), float(r[1]))), Vector2(float(r[2]), float(r[3])) * ppi)
		draw_rect(rect, UITokens.ZONE_TINT[side])


## Dense terrain is solid, light terrain is half filled and exposed terrain is a thin outline.
func _draw_terrain(ppi: float) -> void:
	for area in battle.terrain:
		var arect := Rect2(world_to_screen(area.rect.position), area.rect.size * ppi)
		draw_rect(arect, UITokens.EDGE, false, 1.0)
		for f in area.features:
			var frect := Rect2(world_to_screen(f["rect"].position), f["rect"].size * ppi)
			match str(f["category"]):
				"dense":
					_notched_rect(frect, UITokens.TERRAIN_FILL, UITokens.TERRAIN_EDGE, 2.0)
				"light":
					_notched_rect(frect, UITokens.with_alpha(UITokens.TERRAIN_FILL, 0.55), UITokens.TERRAIN_EDGE, 1.5)
				_:
					_notched_rect(frect, UITokens.with_alpha(UITokens.TERRAIN_FILL, 0.25), UITokens.EDGE_STRONG, 1.0)


func _draw_objectives(ppi: float) -> void:
	for o in battle.objectives:
		var c: Vector2 = world_to_screen(o)
		var who: int = Missions.controller(o, battle.units, battle.objective_range)
		var col: Color = UITokens.RELAY if who < 0 else UITokens.SIDE_COLOURS[who]
		var reach: float = battle.objective_range * ppi
		draw_circle(c, reach, UITokens.with_alpha(col, 0.1))
		draw_arc(c, reach, 0.0, TAU, 64, col, 1.5, true)
		_diamond(c, 11.0, UITokens.BOARD_FLOOR)
		_diamond_line(c, 11.0, col, 2.5)
		_diamond(c, 4.5, col)


func _draw_coherency(ppi: float) -> void:
	for u in battle.units:
		var p: Array[Vector2] = _positions_of(u)
		for i in range(p.size()):
			for j in range(i + 1, p.size()):
				if Geo.edge_distance(p[i], u.base_radius, p[j], u.base_radius) <= UnitRules.COHERENCY_NEAR:
					draw_line(world_to_screen(p[i]), world_to_screen(p[j]), UITokens.with_alpha(UITokens.SIDE_COLOURS[u.owner], 0.5), 1.5)


func _draw_engagement(ppi: float) -> void:
	## Soft translucent discs (not outlines) so overlapping model zones read as one area.
	if selected == null:
		return
	for u in battle.units:
		if u.owner == selected.owner or selected.gap_to(u) > 14.0:
			continue
		var col: Color = UITokens.with_alpha(UITokens.SIDE_COLOURS[u.owner], 0.07)
		for p in _positions_of(u):
			draw_circle(world_to_screen(p), (u.base_radius + UnitRules.ENGAGEMENT_RANGE) * ppi, col)


func _draw_unit(u: UnitState, ppi: float) -> void:
	var side_col: Color = UITokens.SIDE_COLOURS[u.owner]
	var fill: Color = UITokens.with_alpha(side_col, 0.5 if acted.has(u) else 1.0)
	var mark: String = str(highlights.get(u, ""))
	var positions: Array[Vector2] = _positions_of(u)
	var r: float = u.base_radius * ppi
	for p in positions:
		var c: Vector2 = world_to_screen(p)
		if u.owner == 0:
			draw_circle(c, r, fill)
		else:
			draw_colored_polygon(_hex_points(c, r * 1.1), fill)
		_outline(c, r, u.owner, UITokens.VOID, 1.5)
		if u == selected:
			_outline(c, r + 3.5, u.owner, UITokens.ACTION, 3.0)
		elif mark == MARK_IN_RANGE:
			_outline(c, r + 3.5, u.owner, UITokens.legal(settings.colour_blind), 2.5)
	if u.starting_strength == 1 and u.wounds_per_model > 1 and not positions.is_empty():
		_draw_wound_arc(u, world_to_screen(positions[0]), r)
	if mark == MARK_TARGET:
		_brackets(_unit_bounds(u, ppi).grow(6.0), UITokens.INK)


## The arc around a large single model shows the wounds it has left.
func _draw_wound_arc(u: UnitState, c: Vector2, r: float) -> void:
	var fraction: float = float(u.total_wounds_left()) / float(u.wounds_per_model)
	var radius: float = r * (1.1 if u.owner == 1 else 1.0) + 6.0
	draw_arc(c, radius, 0.0, TAU, 48, UITokens.RAISED, 4.0, true)
	if fraction > 0.0:
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, UITokens.legal(settings.colour_blind), 4.0, true)


func _draw_ghost(ppi: float) -> void:
	if ghost.is_empty() or selected == null:
		return
	var col: Color = UITokens.legal(settings.colour_blind) if ghost_ok else UITokens.illegal(settings.colour_blind)
	for p in ghost:
		var c: Vector2 = world_to_screen(p)
		var r: float = selected.base_radius * ppi
		draw_circle(c, r, UITokens.with_alpha(col, 0.25))
		if ghost_ok:
			draw_arc(c, r, 0.0, TAU, 32, col, 2.5)
		else:
			_dashed_circle(c, r, col, 2.5)
			draw_line(c + Vector2(-r, -r) * 0.5, c + Vector2(r, r) * 0.5, col, 2.5)
			draw_line(c + Vector2(-r, r) * 0.5, c + Vector2(r, -r) * 0.5, col, 2.5)


func _draw_plates(ppi: float, board_rect: Rect2) -> void:
	var units: Array[UnitState] = []
	var entries: Array = []
	for u in battle.units:
		if _positions_of(u).is_empty() or (ppi < LABEL_MIN_PPI and u != selected):
			continue
		units.append(u)
		entries.append({"size": _plate_size(u), "anchor": _unit_bounds(u, ppi).grow(8.0), "first": u == selected})
	var view: Rect2 = board_rect.intersection(Rect2(Vector2.ZERO, size)).grow(-2.0)
	var spots: Array[Rect2] = PlateLayout.arrange(entries, view)
	for i in range(units.size()):
		_draw_plate(units[i], spots[i])


func _plate_name(u: UnitState) -> String:
	var name_text: String = u.unit_name.to_upper()
	if name_text.length() > PLATE_NAME_MAX:
		name_text = name_text.left(PLATE_NAME_MAX - 1).strip_edges() + "…"
	return name_text


## The model count, or wounds left for a single large model.
func _plate_count(u: UnitState) -> String:
	if u.starting_strength == 1 and u.wounds_per_model > 1:
		return "%d/%d" % [u.total_wounds_left(), u.wounds_per_model]
	return str(u.model_count())


func _plate_size(u: UnitState) -> Vector2:
	var w: float = _plate_font.get_string_size(_plate_name(u), HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL).x
	w += UITokens.FONT_MONO.get_string_size(_plate_count(u), HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL).x
	if u.battle_shocked:
		w += _plate_font.get_string_size(UIText.t("chip.shocked_short"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL).x + PLATE_GAP
	return Vector2(ceilf(w) + PLATE_GAP + UITokens.SPACE_2 * 2.0, 22.0)


func _draw_plate(u: UnitState, rect: Rect2) -> void:
	var side_col: Color = UITokens.SIDE_COLOURS[u.owner]
	_plate_box.bg_color = UITokens.with_alpha(UITokens.HULL, 0.94)
	_plate_box.border_color = UITokens.ACTION if u == selected else side_col
	draw_style_box(_plate_box, rect)
	var base: float = rect.position.y + 16.0
	var x: float = rect.position.x + UITokens.SPACE_2
	var name_text: String = _plate_name(u)
	draw_string(_plate_font, Vector2(x, base), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL, UITokens.INK)
	x += _plate_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL).x + PLATE_GAP
	if u.battle_shocked:
		var chip: String = UIText.t("chip.shocked_short")
		draw_string(_plate_font, Vector2(x, base), chip, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL, UITokens.illegal(settings.colour_blind))
		x += _plate_font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL).x + PLATE_GAP
	draw_string(UITokens.FONT_MONO_BOLD, Vector2(x, base), _plate_count(u), HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.TEXT_LABEL, side_col)


func _unit_bounds(u: UnitState, ppi: float) -> Rect2:
	var positions: Array[Vector2] = _positions_of(u)
	var bounds := Rect2(world_to_screen(positions[0]), Vector2.ZERO)
	for p in positions:
		bounds = bounds.expand(world_to_screen(p))
	return bounds.grow(u.base_radius * ppi)


# ---------------------------------------------------------------- drawing helpers

func _hex_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(6):
		var a: float = TAU * float(k) / 6.0 + TAU / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## An outline that follows the side's token shape.
func _outline(c: Vector2, r: float, side: int, col: Color, width: float) -> void:
	if side == 0:
		draw_arc(c, r, 0.0, TAU, 32, col, width, true)
		return
	var pts: PackedVector2Array = _hex_points(c, r * 1.1)
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _diamond_line(c: Vector2, r: float, col: Color, width: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, width, true)


## A filled rectangle with the Muster notch on the top-right and bottom-left corners.
func _notched_rect(rect: Rect2, fill: Color, line: Color, width: float) -> void:
	var n: float = minf(float(UITokens.NOTCH_MD), minf(rect.size.x, rect.size.y) * 0.3)
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	var pts := PackedVector2Array([p, Vector2(e.x - n, p.y), Vector2(e.x, p.y + n), e, Vector2(p.x + n, e.y), Vector2(p.x, e.y - n)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, line, width, true)


## Corner brackets around a target.
func _brackets(rect: Rect2, col: Color) -> void:
	var l: float = minf(14.0, minf(rect.size.x, rect.size.y) * 0.3)
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	for corner: Array in [[p, Vector2(1, 1)], [Vector2(e.x, p.y), Vector2(-1, 1)], [Vector2(p.x, e.y), Vector2(1, -1)], [e, Vector2(-1, -1)]]:
		var at: Vector2 = corner[0]
		var dir: Vector2 = corner[1]
		draw_polyline(PackedVector2Array([at + Vector2(dir.x * l, 0), at, at + Vector2(0, dir.y * l)]), col, 3.0)


func _dashed_circle(c: Vector2, r: float, col: Color, width: float) -> void:
	if r < 2.0:
		return
	var segs: int = maxi(12, int(r / 3.0))
	for i in range(0, segs, 2):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		draw_arc(c, r, a0, a1, 4, col, width)
