extends Node
## Touch screens (the Android build; "--touch" tries it on a PC): fingers work the game the way the
## mouse does, so screens need no touch code of their own.
##   Tap          click                       Drag              drag (cards, sliders, lists)
##   Hold still   right-click (zoom in on a card; in a duel, on nothing: cancel)
##   Pinch        mouse wheel (zoom the turf map)
##   Back button  Esc (back, cancel, the duel's menu)
## A finger going down only moves the pointer there (hover: the duel's card panel shows that card);
## what it does is decided once it lifts (a tap), moves (a drag, pressed where it went down) or is
## held (a right-click, and no left click at all). Godot's own touch-to-mouse is off while this
## runs: it presses at once, so holding a finger couldn't zoom without clicking too.
## The mouse and key events made here are marked with DEVICE.

const DEVICE := 78            # on the mouse and key events made here (the controller's are 77)
const HOLD_SECS := 0.45       # a finger held this long without moving is a right-click
const SLOP := 22.0            # moving further than this (pixels of the 1920×1080 game) makes it a drag
const PINCH_STEP := 1.12      # fingers this much further apart (or closer) = one wheel notch
const REACH := 34.0           # a tap this close to a button (pixels of the game) presses it (_aim)

var active := false
var _finger := -1             # the finger working the pointer (the first one down), or -1
var _state := ""              # its gesture so far: "wait" (tap or hold?), "drag", "done" (held, or a pinch)
var _at := Vector2.ZERO       # where it is (viewport coordinates)
var _down_at := Vector2.ZERO
var _held := 0.0
var _fingers := {}            # index -> position, every finger on the screen
var _pinch := 0.0             # the two fingers' distance at the last wheel notch (0: not pinching yet)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()   # (a touch laptop keeps Godot's own)
	set_process(active)
	if active:
		Input.emulate_mouse_from_touch = false
		get_tree().quit_on_go_back = false   # (the back button is Esc)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and active:
		_key(KEY_ESCAPE)


func _input(e: InputEvent) -> void:
	if not active or e.device == DEVICE:
		return
	if e is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if e.pressed:
			_fingers[e.index] = e.position
		else:
			_fingers.erase(e.index)
		_pinch = 0.0
		if e.pressed and _fingers.size() == 1:
			_finger = e.index
			_state = "wait"
			_at = e.position
			_down_at = e.position
			_held = 0.0
			_move(e.position, 0)
		elif e.pressed and _finger != -1:   # a second finger: a pinch from here on
			if _state == "drag":
				_button(MOUSE_BUTTON_LEFT, false, _at)
			_state = "done"
		elif not e.pressed and e.index == _finger:
			match _state:
				"wait":   # a tap
					var at := _aim(_down_at)
					if at != _down_at:
						_move(at, 0)
					_button(MOUSE_BUTTON_LEFT, true, at)
					_button(MOUSE_BUTTON_LEFT, false, at)
				"drag":
					_button(MOUSE_BUTTON_LEFT, false, e.position)
			_finger = -1
			_state = ""
	elif e is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		_fingers[e.index] = e.position
		if _fingers.size() >= 2:
			_pinch_step()
		elif e.index == _finger:
			if _state == "wait" and e.position.distance_to(_down_at) > SLOP:
				_state = "drag"
				_button(MOUSE_BUTTON_LEFT, true, _down_at)
			if _state == "drag":
				_move(e.position, MOUSE_BUTTON_MASK_LEFT)
			_at = e.position


func _process(delta: float) -> void:
	if _state != "wait":
		return
	_held += delta
	if _held >= HOLD_SECS:
		_state = "done"
		_button(MOUSE_BUTTON_RIGHT, true, _at)
		_button(MOUSE_BUTTON_RIGHT, false, _at)


## Two fingers moving apart zoom in (wheel up), together zoom out, at the point between them.
func _pinch_step() -> void:
	var f: Array = _fingers.values()
	var d: float = f[0].distance_to(f[1])
	if _pinch <= 0.0:
		_pinch = d
		return
	var mid: Vector2 = (f[0] + f[1]) / 2.0
	while d > _pinch * PINCH_STEP or d < _pinch / PINCH_STEP:
		var wheel := MOUSE_BUTTON_WHEEL_UP if d > _pinch else MOUSE_BUTTON_WHEEL_DOWN
		_move(mid, 0)
		_button(wheel, true, mid)
		_button(wheel, false, mid)
		_pinch = _pinch * PINCH_STEP if d > _pinch else _pinch / PINCH_STEP


## Where a tap goes: a finger is wider than most buttons, so a tap just beside one (on a panel, a
## dimmer, the screen, the duel's empty board) presses it, at its middle. A tap on anything that
## takes taps itself (a button, a card tile, a duel card, a text box) stays where it is.
func _aim(p: Vector2) -> Vector2:
	var under := get_viewport().gui_get_hovered_control()   # (the finger going down moved the pointer here)
	var scene := get_tree().current_scene
	if under and (under is LineEdit or under is TextEdit or under is Range or under is RichTextLabel \
			or under != scene and under.get_script() != null or not under.get_signal_connection_list("gui_input").is_empty()):
		return p   # (it takes taps itself: a card tile, a text box, a slider, a dimmer that closes its dialog)
	var n: Node = under
	while n is Control:   # (on a button, or on a label inside one)
		if n is BaseButton:
			return p
		n = n.get_parent()
	if under == null and scene and scene.has_method("touch_owns") and scene.touch_owns(p):
		return p
	var best := p
	var best_d := REACH
	for b in (under if under else get_tree().root).find_children("*", "BaseButton", true, false):
		if not b.is_visible_in_tree() or b.disabled or b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var r: Rect2 = b.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, b.size)
		var d := _rect_distance(r, p)
		if d < best_d:
			best_d = d
			best = r.get_center()
	return best


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x), maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()


func _window_pos(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _move(p: Vector2, mask: int) -> void:
	var m := InputEventMouseMotion.new()
	m.device = DEVICE
	m.position = _window_pos(p)
	m.global_position = m.position
	m.relative = _window_pos(p) - _window_pos(_at)
	m.button_mask = mask
	Input.parse_input_event(m)


func _button(button: int, pressed: bool, p: Vector2) -> void:
	var b := InputEventMouseButton.new()
	b.device = DEVICE
	b.button_index = button
	b.pressed = pressed
	b.position = _window_pos(p)
	b.global_position = b.position
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	Input.parse_input_event(b)


func _key(code: int) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.device = DEVICE
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
