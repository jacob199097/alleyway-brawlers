extends Node
## Controller support (Xbox, PlayStation, Steam Deck): the controller drives a mouse pointer of its
## own, so every screen works with it the way it works with a mouse.
##   Left stick   move the pointer          D-pad     jump to the next button / card that way
##   A            click (hold to drag)      X         right-click (zoom in on a card)
##   B / Start    Esc (back, cancel, menu)  Y         Space (next phase / end turn, continue)
##   LB / RB      ← / → (pages, Striver levels)        Right stick   scroll
##   View/Select  L (battle log)            LT        E (emotes)
## The clicks and keys it makes are ordinary input events (marked with DEVICE), so screens need no
## controller code; scripts that read the mouse position directly use Game.pad.pointer(self).
## Using the real mouse hands control back to it.

const DEVICE := 77            # on the mouse and key events made here
const DEADZONE := 0.2
const SPEED := 1500.0         # pointer speed at full tilt (pixels of the 1920×1080 game a second)
const REPEAT_DELAY := 0.38    # a held D-pad: first repeat, then every REPEAT_EVERY
const REPEAT_EVERY := 0.12
const SCROLL_EVERY := 0.05
const BUTTON_KEYS := {
	JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_START: KEY_ESCAPE, JOY_BUTTON_Y: KEY_SPACE,
	JOY_BUTTON_BACK: KEY_L, JOY_BUTTON_LEFT_SHOULDER: KEY_LEFT, JOY_BUTTON_RIGHT_SHOULDER: KEY_RIGHT}
const DPAD := {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
	JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}
## The button prompts shown for a few seconds when the controller takes over
const HINTS := [["A", "Select"], ["B", "Back"], ["X", "Zoom"], ["Y", "Next / End turn"], ["LB RB", "Pages"], ["R", "Scroll"]]
const GLYPH_COLORS := {"A": Color("5fd35f"), "B": Color("ef5350"), "X": Color("42a5f5"), "Y": Color("ffca28")}

var active := false           # the controller is driving the pointer (the mouse cursor is hidden)
var cursor := Vector2(960, 540)   # where the pointer is (viewport coordinates)
var _dev := 0                 # the controller last used
var _mask := 0                # mouse buttons held through the controller
var _held_dir := Vector2.ZERO
var _repeat_t := 0.0
var _scroll_t := 0.0
var _lt_down := false
var _glide: Tween
var _hits: Array = []         # [Control, its visible rect] in drawing order (what a click would land on)
var _providers: Array = []    # [rect, node]: cards and spots on boards drawn outside the GUI (duel.gd pad_targets)
var _hits_age := 99.0
var _over := Rect2()          # the button / card under the pointer, outlined
var _over_shown := Rect2()
var _hint_t := 0.0
var _layer: CanvasLayer
var _ink: Node2D
var _script_inputs := {}      # Script -> whether it has its own _gui_input


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Godot's own controller focus-navigation would fight the pointer: the pointer does it all
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	_ink = Node2D.new()
	_ink.draw.connect(_draw_ink)
	_layer.add_child(_ink)
	_ink.visible = false


## Where the mouse is for this canvas item: the controller's pointer while it's in use.
## (Use instead of get_global_mouse_position() wherever a script reads the position itself.)
func pointer(ci: CanvasItem) -> Vector2:
	if not active:
		return ci.get_global_mouse_position()
	return ci.get_canvas_transform().affine_inverse() * cursor


func _input(e: InputEvent) -> void:
	if e.device == DEVICE:
		return
	if e is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		_dev = e.device
		_on_button(e.button_index, e.pressed)
	elif e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()   # (read in _process)
		_dev = e.device
	elif active and (e is InputEventMouseButton or (e is InputEventMouseMotion and e.relative.length() > 3.0)):
		_set_active(false)   # the mouse is back


func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_ink.visible = on
	if on:
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		cursor = m if vp.get_visible_rect().has_point(m) else vp.get_visible_rect().get_center()
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_hint_t = 6.0
		_hits_age = 99.0
		_move_to(cursor)
	else:
		if _mask:
			for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				if _mask & (1 << (b - 1)):
					_mouse_button(b, false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_button(button: int, pressed: bool) -> void:
	if pressed:
		_set_active(true)
	var popup := _open_popup()
	if popup:   # a dropdown's list: arrows, Enter and Esc work it
		var k: int = {JOY_BUTTON_DPAD_UP: KEY_UP, JOY_BUTTON_DPAD_DOWN: KEY_DOWN, JOY_BUTTON_A: KEY_ENTER,
			JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_START: KEY_ESCAPE}.get(button, 0)
		if k and pressed:
			_key(k)
		return
	match button:
		JOY_BUTTON_A:
			_mouse_button(MOUSE_BUTTON_LEFT, pressed)
		JOY_BUTTON_X:
			_mouse_button(MOUSE_BUTTON_RIGHT, pressed)
		_:
			if DPAD.has(button):
				if pressed:
					_held_dir = DPAD[button]
					_repeat_t = REPEAT_DELAY
					_step(_held_dir)
				elif _held_dir == DPAD[button]:
					_held_dir = Vector2.ZERO
			elif BUTTON_KEYS.has(button) and pressed:
				_key(BUTTON_KEYS[button])


func _process(delta: float) -> void:
	if not active and Input.get_connected_joypads().is_empty():
		return
	# Left stick: move the pointer, a little slower over something you can click
	var v := Vector2(Input.get_joy_axis(_dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(_dev, JOY_AXIS_LEFT_Y))
	if v.length() > DEADZONE:
		_set_active(true)
		var k := (v.length() - DEADZONE) / (1.0 - DEADZONE)
		var speed := SPEED * (0.12 + 0.88 * k * k) * (0.7 if _over.has_area() else 1.0)
		if _glide and _glide.is_valid():
			_glide.kill()
		_move_to(cursor + v.normalized() * minf(k, 1.0) * speed * delta)
	# Right stick: scroll whatever is under the pointer
	var r := Vector2(Input.get_joy_axis(_dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(_dev, JOY_AXIS_RIGHT_Y))
	_scroll_t -= delta
	if r.length() > DEADZONE * 1.5:
		_set_active(true)
		if _scroll_t <= 0.0:
			_scroll_t = SCROLL_EVERY
			if absf(r.y) >= absf(r.x):
				_wheel(MOUSE_BUTTON_WHEEL_DOWN if r.y > 0 else MOUSE_BUTTON_WHEEL_UP, absf(r.y) * 0.8)
			else:
				_wheel(MOUSE_BUTTON_WHEEL_RIGHT if r.x > 0 else MOUSE_BUTTON_WHEEL_LEFT, absf(r.x) * 0.8)
	var lt := Input.get_joy_axis(_dev, JOY_AXIS_TRIGGER_LEFT) > 0.5
	if lt and not _lt_down:
		_set_active(true)
		_key(KEY_E)
	_lt_down = lt
	if not active:
		return
	# A held D-pad repeats
	if _held_dir != Vector2.ZERO:
		_repeat_t -= delta
		if _repeat_t <= 0.0:
			_repeat_t = REPEAT_EVERY
			_step(_held_dir)
	_hits_age += delta
	if _hits_age > 0.25:
		_refresh()
	_over = _target_rect_at(cursor)
	if _over.has_area():
		_over_shown = _over if not _over_shown.has_area() else Rect2(_over_shown.position.lerp(_over.position, minf(1.0, delta * 22.0)),
			_over_shown.size.lerp(_over.size, minf(1.0, delta * 22.0)))
	else:
		_over_shown = Rect2()
	_hint_t = maxf(0.0, _hint_t - delta)
	_ink.queue_redraw()


# ── Making mouse and key events ─────────────────────────────────────────────

func _window_pos(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _move_to(p: Vector2) -> void:
	p = p.clamp(Vector2.ZERO, get_viewport().get_visible_rect().size - Vector2.ONE)
	var m := InputEventMouseMotion.new()
	m.device = DEVICE
	m.position = _window_pos(p)
	m.global_position = m.position
	m.relative = _window_pos(p) - _window_pos(cursor)
	m.button_mask = _mask
	cursor = p
	Input.parse_input_event(m)


func _mouse_button(button: int, pressed: bool, factor := 1.0) -> void:
	var bit := 1 << (button - 1)
	if button <= MOUSE_BUTTON_MIDDLE:
		_mask = (_mask | bit) if pressed else (_mask & ~bit)
	var b := InputEventMouseButton.new()
	b.device = DEVICE
	b.button_index = button
	b.pressed = pressed
	b.factor = factor
	b.position = _window_pos(cursor)
	b.global_position = b.position
	b.button_mask = _mask
	Input.parse_input_event(b)


func _wheel(button: int, factor: float) -> void:
	_mouse_button(button, true, factor)
	_mouse_button(button, false, factor)


func _key(code: int) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.device = DEVICE
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)


## A dropdown's list that's open (it takes the arrow keys), or null.
func _open_popup() -> Window:
	for w in get_tree().root.get_embedded_subwindows():
		if w is PopupMenu and w.visible:
			return w
	return null


# ── What can be clicked ─────────────────────────────────────────────────────

## Looks over the screen: every Control a click could land on (in drawing order, like Godot picks
## them) and the cards / spots that nodes with pad_targets() offer.
func _refresh() -> void:
	_hits_age = 0.0
	_hits.clear()
	_providers.clear()
	var roots: Array = []   # [canvas layer, order, Control]
	var order := [0]
	_find_roots(get_tree().root, roots, order, 0)
	roots.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var screen := get_viewport().get_visible_rect()
	for r in roots:
		_add_hits(r[2], screen)


func _find_roots(n: Node, roots: Array, order: Array, layer: int) -> void:
	if n == _layer:
		return
	if n is CanvasLayer:
		if not n.visible:
			return
		layer = n.layer
	elif n is Window and n != get_tree().root:
		return   # (popups: _open_popup)
	elif n is SubViewport:
		return
	if n is CanvasItem:
		if not n.visible:
			return
		if n.has_method("pad_targets"):
			var xf: Transform2D = n.get_canvas_transform()
			for rect in n.pad_targets():
				_providers.append([xf * (rect as Rect2), n])
		if n is Control and (not n.get_parent() is Control or n.top_level):
			order[0] += 1
			roots.append([layer, order[0], n])
			return   # (its children are added under it, in _add_hits)
	for c in n.get_children():
		_find_roots(c, roots, order, layer)


func _add_hits(ci: CanvasItem, clip: Rect2) -> void:
	if not ci.visible:
		return
	var xf := ci.get_global_transform_with_canvas()
	if ci is Control:
		var rect: Rect2 = xf * Rect2(Vector2.ZERO, ci.size)
		if ci.clip_contents:
			clip = clip.intersection(rect)
		if ci.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var seen := rect.intersection(clip)
			if seen.has_area():
				_hits.append([ci, seen])
	if ci.has_method("pad_targets") and not ci is Control:
		pass   # (gathered in _find_roots)
	for c in ci.get_children():
		if c is CanvasItem and not c.top_level and not c is Window:
			_add_hits(c, clip)


## The Control a click at p would go to (the last one drawn there), or null.
func _control_at(p: Vector2) -> Control:
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][1] as Rect2).has_point(p):
			return _hits[i][0]
	return null


## Whether a Control reacts to clicks itself (a button, a text box, a slider, a card tile …).
func _clickable(c: Control) -> bool:
	if c is BaseButton:
		return not c.disabled
	if c is LineEdit or c is TextEdit or c is Range:
		return true
	if not c.gui_input.get_connections().is_empty():
		return true
	var s: Script = c.get_script()
	if s == null:
		return false
	if not _script_inputs.has(s):
		var has := false
		var at := s
		while at and not has:
			has = at.get_script_method_list().any(func(m): return m.name == "_gui_input")
			at = at.get_base_script()
		_script_inputs[s] = has
	return _script_inputs[s]


## Everything the D-pad can go to: [rect, node], each one a click would really reach.
func _targets() -> Array:
	var out: Array = []
	var screen := get_viewport().get_visible_rect()
	var big := screen.get_area() * 0.45   # (a full-screen "click anywhere" layer isn't a place to go)
	for h in _hits:
		var c: Control = h[0]
		var rect: Rect2 = h[1]
		if rect.get_area() > big or rect.size.x < 8 or rect.size.y < 8 or not _clickable(c):
			continue
		var top := _control_at(rect.get_center())
		if top == c or (top and c.is_ancestor_of(top)):
			out.append([rect, c])
	for p in _providers:
		var rect: Rect2 = (p[0] as Rect2).intersection(screen)
		if rect.has_area() and not _blocked(rect.get_center()):
			out.append([rect, p[1]])
	return out


## Whether the GUI would swallow a click at p (so the board under it never sees it).
func _blocked(p: Vector2) -> bool:
	var c := _control_at(p)
	while c:
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		c = c.get_parent() as Control
	return false


## The outline for whatever is under the pointer: the clickable Control, or a board card.
func _target_rect_at(p: Vector2) -> Rect2:
	var c := _control_at(p)
	var screen := get_viewport().get_visible_rect()
	while c:
		if _clickable(c):
			for h in _hits:
				if h[0] == c:
					return Rect2() if (h[1] as Rect2).get_area() > screen.get_area() * 0.45 else h[1]
			return Rect2()
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return Rect2()
		c = c.get_parent() as Control
	var best := Rect2()
	for t in _providers:
		var rect: Rect2 = t[0]
		if rect.has_point(p) and (not best.has_area() or rect.get_area() < best.get_area()):
			best = rect
	return best


# ── The D-pad ───────────────────────────────────────────────────────────────

func _step(dir: Vector2) -> void:
	_refresh()
	var c := _control_at(cursor)
	# On a slider: left / right move it; on a "◀ value ▶" switch: change the value
	if dir.x != 0.0 and c is Slider:
		c.value += c.step * 2.0 * signf(dir.x) if c.step > 0.0 else (c.max_value - c.min_value) * 0.05 * signf(dir.x)
		return
	if dir.x != 0.0 and c is Button and c.text.begins_with("◀"):
		var r := c.get_global_rect()
		var back := cursor
		_move_to(c.get_global_transform_with_canvas() * Vector2(c.size.x * (0.1 if dir.x < 0 else 0.9), c.size.y / 2))
		_mouse_button(MOUSE_BUTTON_LEFT, true)
		_mouse_button(MOUSE_BUTTON_LEFT, false)
		_move_to(back)
		return
	var all := _targets()
	var here := _target_rect_at(cursor)
	var best = _best_toward(all, dir, here)
	if best == null:
		# Nothing that way: scroll the list under the pointer, then look again
		var sc := _scroller_at(cursor)
		if sc:
			var bar: ScrollBar = sc.get_v_scroll_bar() if dir.y != 0.0 else sc.get_h_scroll_bar()
			var before := bar.value
			bar.value += signf(dir.y if dir.y != 0.0 else dir.x) * maxf(bar.page * 0.6, 120.0)
			if bar.value != before:
				await get_tree().process_frame
				await get_tree().process_frame
				_refresh()
				best = _best_toward(_targets(), dir, here)
		if best == null and not here.has_area():
			best = _nearest(all)   # lost in empty space: go to the closest thing
	if best != null:
		_glide_to(best[0].get_center())
		Sfx.play("click", 1.6, -16.0)


## The target the D-pad goes to from the pointer in direction dir: ahead of it, closest, and
## off to the side as little as possible.
func _best_toward(all: Array, dir: Vector2, here: Rect2):
	var best = null
	var best_score := INF
	var side := Vector2(dir.y, dir.x).abs()
	for t in all:
		var rect: Rect2 = t[0]
		if here.has_area() and rect.is_equal_approx(here):
			continue
		var to: Vector2 = rect.get_center() - cursor
		var ahead := to.dot(dir)
		# (past the edge of what the pointer is on, so a neighbour that overlaps it still counts)
		var edge: float = (here.size.dot(dir.abs()) / 2.0) if here.has_area() else 0.0
		if ahead <= maxf(6.0, edge * 0.5):
			continue
		var off := absf(to.dot(side))
		if off > ahead * 2.5 + rect.size.dot(side) / 2.0:
			continue   # too far off to the side to count as "that way"
		var score := ahead + off * 2.2
		if score < best_score:
			best_score = score
			best = t
	return best


func _nearest(all: Array):
	var best = null
	for t in all:
		if best == null or (t[0] as Rect2).get_center().distance_to(cursor) < (best[0] as Rect2).get_center().distance_to(cursor):
			best = t
	return best


func _scroller_at(p: Vector2) -> ScrollContainer:
	var c := _control_at(p)
	while c:
		if c is ScrollContainer:
			return c
		c = c.get_parent() as Control
	for i in range(_hits.size() - 1, -1, -1):   # (between the items of a list: the list's own area)
		if _hits[i][0] is ScrollContainer and (_hits[i][1] as Rect2).has_point(p):
			return _hits[i][0]
	return null


func _glide_to(p: Vector2) -> void:
	if _glide and _glide.is_valid():
		_glide.kill()
	_glide = create_tween()
	_glide.tween_method(_move_to, cursor, p, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ── Drawing: the pointer, the outline round what it's on, the button prompts ─────────

func _draw_ink() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if _over_shown.has_area():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04)
		sb.set_border_width_all(3)
		sb.border_color = Color(UI.GOLD, 0.75 + 0.25 * sin(t * 6.0))
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(UI.GOLD, 0.35)
		sb.shadow_size = 10
		sb.draw(_ink.get_canvas_item(), _over_shown.grow(6))
	# The pointer: an arrow, pressed in a little while A is held
	var s := 1.15 * (0.88 if _mask & MOUSE_BUTTON_MASK_LEFT else 1.0)
	var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(13, 35),
		Vector2(19, 32), Vector2(14, 21), Vector2(24, 21)])
	var pts := PackedVector2Array()
	for a in arrow:
		pts.append(cursor + a * s)
	_ink.draw_circle(cursor, 16.0, Color(UI.GOLD, 0.18 if _over.has_area() else 0.08))
	_ink.draw_colored_polygon(pts, Color.WHITE)
	pts.append(pts[0])
	_ink.draw_polyline(pts, Color(0.05, 0.05, 0.1), 2.5, true)
	if _hint_t > 0.0:
		_draw_hints(clampf(_hint_t, 0.0, 1.0))


func _draw_hints(a: float) -> void:
	var f := UI.font()
	var fs := 20
	var w := 0.0
	for h in HINTS:
		w += _glyph_w(f, h[0]) + 8.0 + f.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
	var size := get_viewport().get_visible_rect().size
	var x := (size.x - w) / 2.0
	var y := size.y - 40.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.08, 0.85 * a)
	sb.set_corner_radius_all(22)
	sb.border_color = Color(1, 1, 1, 0.15 * a)
	sb.set_border_width_all(1)
	sb.draw(_ink.get_canvas_item(), Rect2(x - 16, y - 22, w + 4, 44))
	for h in HINTS:
		x += _glyph(f, h[0], Vector2(x, y), a) + 8.0
		_ink.draw_string(f, Vector2(x, y + 7), h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
		x += f.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0


func _glyph_w(f: Font, g: String) -> float:
	return 28.0 if g.length() == 1 else f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 18.0


## A controller button: a coloured circle with its letter (or a pill for "LB RB").
func _glyph(f: Font, g: String, at: Vector2, a: float) -> float:
	var w := _glyph_w(f, g)
	var col: Color = GLYPH_COLORS.get(g, Color(0.75, 0.78, 0.9))
	if g.length() == 1 and GLYPH_COLORS.has(g):
		_ink.draw_circle(at + Vector2(14, 0), 14.0, Color(0.08, 0.08, 0.12, a))
		_ink.draw_arc(at + Vector2(14, 0), 13.0, 0.0, TAU, 32, Color(col, a), 2.5, true)
		_ink.draw_string(f, at + Vector2(14 - f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x / 2.0, 6), g,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(col, a))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.12, a)
		sb.border_color = Color(col, a)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(13)
		sb.draw(_ink.get_canvas_item(), Rect2(at + Vector2(0, -13), Vector2(w, 26)))
		_ink.draw_string(f, at + Vector2(9, 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, a))
	return w
