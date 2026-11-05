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

const LABEL_MIN_PPI: float = 11.0

var battle: Battle
var settings: UISettings = UISettings.new()

# Presentation state, set by the controller
var selected: UnitState
var ghost: Array[Vector2] = []
var ghost_ok: bool = true
var ring_centre: Vector2 = Vector2.ZERO
var ring_radius: float = 0.0
var highlights: Dictionary = {}          # UnitState -> Color
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
var _badge_box := StyleBoxFlat.new()


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_badge_box.set_corner_radius_all(UITokens.SPACE_1 * 2)
	_badge_box.set_border_width_all(1)
	_badge_box.content_margin_left = UITokens.SPACE_2
	_badge_box.content_margin_right = UITokens.SPACE_2
	_badge_box.content_margin_top = UITokens.SPACE_1
	_badge_box.content_margin_bottom = UITokens.SPACE_1
	resized.connect(queue_redraw)


# ---------------------------------------------------------------- camera

func pixels_per_inch() -> float:
	if battle == null:
		return 1.0
	var margin: float = float(UITokens.SPACE_4)
	var fit_x: float = (size.x - margin * 2.0) / battle.board.size.x
	var fit_y: float = (size.y - margin * 2.0) / battle.board.size.y
	return maxf(1.0, minf(fit_x, fit_y)) * _zoom


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
	draw_rect(Rect2(Vector2.ZERO, size), UITokens.CANVAS)
	var ppi: float = pixels_per_inch()
	var board_rect := Rect2(_origin(), battle.board.size * ppi)
	draw_rect(board_rect, UITokens.BOARD_FLOOR)
	_draw_grid(board_rect, ppi)
	_draw_zones(ppi)
	_draw_terrain(ppi)
	if settings.show_objectives:
		_draw_objectives(ppi)
	if settings.show_coherency:
		_draw_coherency(ppi)
	draw_rect(board_rect, UITokens.BORDER_STRONG, false, 2.0)
	if settings.show_engagement:
		_draw_engagement(ppi)
	if ring_radius > 0.0:
		_dashed_circle(world_to_screen(ring_centre), ring_radius * ppi, UITokens.with_alpha(UITokens.ACCENT, 0.8), 2.0)
	for u in battle.units:
		_draw_unit(u, ppi)
	_draw_ghost(ppi)
	if los_line.size() == 2:
		var c: Color = UITokens.illegal(settings.colour_blind) if los_blocked else UITokens.legal(settings.colour_blind)
		draw_dashed_line(world_to_screen(los_line[0]), world_to_screen(los_line[1]), c, 2.0, 8.0)
	for f in _fx:
		var t: float = clampf(float(f["age"]) / float(f["life"]), 0.0, 1.0)
		var col: Color = f["colour"]
		draw_line(world_to_screen(f["from"]), world_to_screen(f["to"]), UITokens.with_alpha(col, 1.0 - t * 0.7), 4.0)
	for u in battle.units:
		if ppi >= LABEL_MIN_PPI or u == selected:
			_draw_badge(u, ppi)


func _draw_grid(board_rect: Rect2, ppi: float) -> void:
	var step: float = 6.0
	var x: float = step
	while x < battle.board.size.x:
		var sx: float = board_rect.position.x + x * ppi
		draw_line(Vector2(sx, board_rect.position.y), Vector2(sx, board_rect.end.y), UITokens.GRID, 1.0)
		x += step
	var y: float = step
	while y < battle.board.size.y:
		var sy: float = board_rect.position.y + y * ppi
		draw_line(Vector2(board_rect.position.x, sy), Vector2(board_rect.end.x, sy), UITokens.GRID, 1.0)
		y += step


func _draw_zones(ppi: float) -> void:
	var keys: Array[String] = ["attacker", "defender"]
	for side in range(2):
		var r: Array = battle.scenario["deployment_zones"][keys[side]]["rect"]
		var rect := Rect2(world_to_screen(Vector2(float(r[0]), float(r[1]))), Vector2(float(r[2]), float(r[3])) * ppi)
		draw_rect(rect, UITokens.ZONE_TINT[side])


func _draw_terrain(ppi: float) -> void:
	for area in battle.terrain:
		var arect := Rect2(world_to_screen(area.rect.position), area.rect.size * ppi)
		_dashed_rect(arect, UITokens.BORDER_STRONG)
		for f in area.features:
			var frect := Rect2(world_to_screen(f["rect"].position), f["rect"].size * ppi)
			match str(f["category"]):
				"dense":
					draw_rect(frect, UITokens.TERRAIN_DENSE)
					_hatch(frect, UITokens.with_alpha(UITokens.TEXT_FAINT, 0.55), 10.0)
					draw_rect(frect, UITokens.TEXT_FAINT, false, 2.0)
				"light":
					draw_rect(frect, UITokens.TERRAIN_LIGHT)
					_dots(frect, UITokens.with_alpha(UITokens.TEXT_FAINT, 0.6), 14.0)
					draw_rect(frect, UITokens.BORDER_STRONG, false, 1.0)
				_:
					draw_rect(frect, UITokens.TERRAIN_EXPOSED)
					_dashed_rect(frect, UITokens.BORDER_STRONG)


func _draw_objectives(ppi: float) -> void:
	for o in battle.objectives:
		var c: Vector2 = world_to_screen(o)
		var who: int = Missions.controller(o, battle.units, battle.objective_range)
		var col: Color = UITokens.TEXT_FAINT if who < 0 else UITokens.SIDE_COLOURS[who]
		_dashed_circle(c, battle.objective_range * ppi, UITokens.with_alpha(col, 0.7), 1.5)
		draw_circle(c, 6.0, col)
		draw_arc(c, 10.0, 0.0, TAU, 24, UITokens.with_alpha(col, 0.9), 2.0)


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
	var dim: bool = acted.has(u)
	var fill: Color = UITokens.with_alpha(side_col, 0.55 if dim else 0.95)
	var is_selected: bool = u == selected
	var highlight: Variant = highlights.get(u, null)
	for p in _positions_of(u):
		var c: Vector2 = world_to_screen(p)
		var r: float = u.base_radius * ppi
		if u.owner == 0:
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 32, UITokens.CANVAS, 1.5)
		else:
			var pts := PackedVector2Array()
			for k in range(6):
				var a: float = TAU * float(k) / 6.0 + TAU / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 1.1)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, UITokens.CANVAS, 1.5)
		if is_selected:
			draw_arc(c, r + 4.0, 0.0, TAU, 32, UITokens.ACCENT, 3.0)
		if highlight != null:
			_dashed_circle(c, r + 5.0, highlight as Color, 3.0)


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


func _draw_badge(u: UnitState, ppi: float) -> void:
	var positions: Array[Vector2] = _positions_of(u)
	if positions.is_empty():
		return
	var top: Vector2 = Vector2(0.0, INF)
	var sum := Vector2.ZERO
	for p in positions:
		sum += p
		if p.y < top.y:
			top = p
	var centre_x: float = sum.x / float(positions.size())
	var anchor: Vector2 = world_to_screen(Vector2(centre_x, top.y)) - Vector2(0.0, u.base_radius * ppi + 10.0)
	var font: Font = get_theme_default_font()
	var size_px: int = UITokens.TEXT_SECONDARY
	var label: String = u.unit_name
	var detail: String = (UIText.t("badge.model_one") if u.model_count() == 1 else UIText.t("badge.models", [u.model_count()])) if u.wounds_per_model <= 1 or u.starting_strength > 1 \
			else UIText.t("badge.wounds", [u.total_wounds_left(), u.wounds_per_model])
	if u.starting_strength > 1 and u.wounds_per_model > 1:
		detail = (UIText.t("badge.model_one") if u.model_count() == 1 else UIText.t("badge.models", [u.model_count()]))
	var chips: String = ""
	if u.battle_shocked:
		chips += "  " + UIText.t("chip.shocked")
	var text: String = "%s · %s%s" % [label, detail, chips]
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var rect := Rect2(anchor - Vector2(text_size.x * 0.5 + UITokens.SPACE_2, text_size.y + UITokens.SPACE_2 * 1.5),
			text_size + Vector2(UITokens.SPACE_2 * 2.0, UITokens.SPACE_1 * 2.0))
	rect.position.x = clampf(rect.position.x, 2.0, size.x - rect.size.x - 2.0)
	rect.position.y = maxf(2.0, rect.position.y)
	_badge_box.bg_color = UITokens.with_alpha(UITokens.CANVAS, 0.88)
	_badge_box.border_color = UITokens.SIDE_COLOURS[u.owner] if u != selected else UITokens.ACCENT
	draw_style_box(_badge_box, rect)
	draw_string(font, Vector2(rect.position.x + UITokens.SPACE_2, rect.position.y + UITokens.SPACE_1 + text_size.y * 0.8),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, UITokens.TEXT)


# ---------------------------------------------------------------- drawing helpers

func _dashed_circle(c: Vector2, r: float, col: Color, width: float) -> void:
	if r < 2.0:
		return
	var segs: int = maxi(12, int(r / 3.0))
	for i in range(0, segs, 2):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		draw_arc(c, r, a0, a1, 4, col, width)


func _dashed_rect(rect: Rect2, col: Color) -> void:
	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	draw_dashed_line(tl, tr, col, 1.5, 6.0)
	draw_dashed_line(tr, br, col, 1.5, 6.0)
	draw_dashed_line(br, bl, col, 1.5, 6.0)
	draw_dashed_line(bl, tl, col, 1.5, 6.0)


## Diagonal hatching clipped to a rectangle, so dense terrain reads without relying on colour.
func _hatch(rect: Rect2, col: Color, spacing: float) -> void:
	var k: float = -rect.size.y
	while k < rect.size.x:
		var a := Vector2(k, rect.size.y)
		var b := Vector2(k + rect.size.y, 0.0)
		var ca := Vector2(clampf(a.x, 0.0, rect.size.x), a.y)
		var cb := Vector2(clampf(b.x, 0.0, rect.size.x), b.y)
		if a.x < 0.0:
			ca = Vector2(0.0, rect.size.y - (0.0 - a.x))
		if b.x > rect.size.x:
			cb = Vector2(rect.size.x, b.y + (b.x - rect.size.x))
		if ca.y >= 0.0 and cb.y <= rect.size.y and ca.x <= rect.size.x:
			draw_line(rect.position + ca, rect.position + cb, col, 1.0)
		k += spacing


func _dots(rect: Rect2, col: Color, spacing: float) -> void:
	var y: float = spacing * 0.5
	while y < rect.size.y:
		var x: float = spacing * 0.5
		while x < rect.size.x:
			draw_circle(rect.position + Vector2(x, y), 1.5, col)
			x += spacing
		y += spacing
