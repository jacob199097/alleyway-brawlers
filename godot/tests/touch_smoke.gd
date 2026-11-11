extends Node
## Touch controls (scripts/touch.gd) driven by fake fingers: a tap clicks, a held finger right-clicks
## without clicking, a finger dragged off a button doesn't click it, a pinch turns the mouse wheel,
## the back button is Esc. Then in a duel: a hand card held shows the zoom, tapped opens its menu.
##   godot --path godot res://tests/touch_smoke.tscn -- --touch
## As on a 20:9 phone, the frame in the middle of a wider screen (scripts/widescreen.gd):
##   godot --headless --path godot res://tests/touch_smoke.tscn -- --touch --mobile
## (headless: in a window, Godot reads the real mouse, not the fake fingers' pointer)

var fails: Array = []
var _log: Array = []


func _ready() -> void:
	await get_tree().process_frame
	if not Game.touch.active:
		push_error("TOUCH SMOKE: run it with  -- --touch")
		get_tree().quit(1)
		return
	if Game.wide.active:   # (a 20:9 phone screen: the frame in the middle, widescreen.gd)
		get_tree().root.size = Vector2i(2400, 1080)
		await get_tree().process_frame
		_check(Game.wide.margin == Vector2(240, 0), "a 20:9 screen: the frame sits in the middle (margin %s)" % Game.wide.margin)
	await _gestures()
	var holder := Node.new()   # screen changes free the current scene; keep this script alive
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	await _duel()
	if fails.is_empty():
		print("TOUCH SMOKE OK")
		get_tree().quit(0)
	else:
		for f in fails:
			push_error("TOUCH SMOKE: " + f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails.append(what)


## A finger event, at a point of the 1920×1080 game.
func _finger(index: int, at: Vector2, pressed := true, drag := false) -> void:
	var to: Vector2 = get_tree().root.get_final_transform() * at
	var e: InputEvent
	if drag:
		e = InputEventScreenDrag.new()
	else:
		e = InputEventScreenTouch.new()
		e.pressed = pressed
	e.index = index
	e.position = to
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout


func _gestures() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var b := Button.new()
	b.text = "TAP ME"
	b.position = Vector2(800, 400)
	b.size = Vector2(320, 120)
	layer.add_child(b)
	var taps := [0]
	b.pressed.connect(func(): taps[0] += 1)
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_log.append(e.button_index))
	var mid := b.position + b.size / 2
	# Tap
	await _finger(0, mid)
	await _finger(0, mid, false)
	_check(taps[0] == 1, "a tap clicks the button")
	# Hold
	_log.clear()
	await _finger(0, mid)
	await _wait(0.7)
	await _finger(0, mid, false)
	_check(taps[0] == 1, "a held finger doesn't click")
	_check(_log == [MOUSE_BUTTON_RIGHT], "a held finger right-clicks (got %s)" % str(_log))
	# Drag off
	await _finger(0, mid)
	for i in 6:
		await _finger(0, mid + Vector2(0, 60.0 * (i + 1)), true, true)
	await _finger(0, mid + Vector2(0, 360), false)
	_check(taps[0] == 1, "a finger dragged off the button doesn't click it")
	# Drag a little (less than the slop) is still a tap
	await _finger(0, mid)
	await _finger(0, mid + Vector2(8, 6), true, true)
	await _finger(0, mid + Vector2(8, 6), false)
	_check(taps[0] == 2, "a finger that wobbles a little still taps")
	# Just beside a small button (on the panel round it): the tap presses it; well away, it doesn't
	var panel := Panel.new()
	panel.position = Vector2(100, 600)
	panel.size = Vector2(500, 300)
	layer.add_child(panel)
	var small := Button.new()
	small.position = Vector2(150, 120)
	small.size = Vector2(140, 40)
	panel.add_child(small)
	var small_taps := [0]
	small.pressed.connect(func(): small_taps[0] += 1)
	var beside := panel.position + small.position + Vector2(70, 40 + 25)
	await _finger(0, beside)
	await _finger(0, beside, false)
	_check(small_taps[0] == 1, "a tap just beside a button presses it")
	var away := panel.position + small.position + Vector2(70, 40 + 90)
	await _finger(0, away)
	await _finger(0, away, false)
	_check(small_taps[0] == 1, "a tap well away from a button doesn't")
	panel.queue_free()
	# Pinch
	var wheels := [0, 0]
	var pad := Control.new()
	pad.position = Vector2(0, 0)
	pad.size = Vector2(1920, 380)
	layer.add_child(pad)
	pad.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				wheels[0] += 1
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				wheels[1] += 1)
	await _finger(0, Vector2(900, 200))
	await _finger(1, Vector2(1000, 200))
	for i in 5:
		await _finger(0, Vector2(900 - 30 * (i + 1), 200), true, true)
		await _finger(1, Vector2(1000 + 30 * (i + 1), 200), true, true)
	await _finger(1, Vector2(1150, 200), false)
	await _finger(0, Vector2(750, 200), false)
	_check(wheels[0] >= 3 and wheels[1] == 0, "fingers pinched apart zoom in (wheel up %d, down %d)" % wheels)
	_check(taps[0] == 2, "a pinch doesn't click")
	# Back button
	var esc := [0]
	var catcher := Control.new()
	catcher.size = Vector2(1920, 1080)
	layer.add_child(catcher)
	catcher.focus_mode = Control.FOCUS_ALL
	catcher.grab_focus()
	catcher.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			esc[0] += 1)
	Game.touch.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(esc[0] == 1, "the back button is Esc")
	_check(not get_tree().quit_on_go_back, "the back button doesn't close the game")
	layer.queue_free()


## `deal`: which match this is. A random opening hand now and then has nothing to play on turn 1, and
## dragging needs a card that can be played: then a new match is dealt (up to 5).
func _duel(deal := 1) -> void:
	Game.offline = true
	Game.duel_setup = {"first": "player"}
	Game.go("duel")
	var d: Node = null
	for i in 400:
		await get_tree().process_frame
		d = get_tree().current_scene
		if d and d.name == "Duel" and d.get("_menu") != null:
			break
	if d == null or d.name != "Duel":
		_check(false, "a duel starts")
		return
	await _wait(1.0)
	if d._menu:   # (the opening hand: keep it)
		for bt in d._menu.find_children("*", "Button", true, false):
			bt.pressed.emit()
			break
	await _wait(2.5)
	if Game.wide.active and Game.wide.margin.x > 0:   # (-- --mobile in a phone-shaped window)
		var off: Vector2 = d.get_viewport().get_canvas_transform().origin
		_check(off.length() < 30.0, "a wide screen: the board stays under the duel's HUD (off by %s)" % off)
	var hand: Array = d.hand.player
	if hand.is_empty():
		_check(false, "the duel has a hand to touch")
		return
	var at: Vector2 = hand[0].get_global_transform_with_canvas().origin
	# Hold a hand card: the zoom (a veil over the screen), not the hand menu
	var ui: Node = d.get_node("HUD/UI")
	var before := ui.get_child_count()
	await _finger(0, at)
	await _wait(0.7)
	await _finger(0, at, false)
	await _wait(0.6)
	_check(d._menu == null or not is_instance_valid(d._menu), "holding a hand card doesn't open its menu")
	_check(ui.get_child_count() > before, "holding a hand card zooms in on it")
	# Close the zoom (tap anywhere), then tap the card: its menu
	await _finger(0, Vector2(960, 540))
	await _finger(0, Vector2(960, 540), false)
	await _wait(0.6)
	await _finger(0, at)
	await _finger(0, at, false)
	await _wait(0.6)
	_check(d._menu != null and is_instance_valid(d._menu), "tapping a hand card opens its menu")
	# Drag a hand card up towards the board: it's picked up, and goes back (or is played) on letting go
	d._cancel_and_refresh()
	await _wait(0.4)
	var playable: Array = d.hand.player.filter(func(v): return d._playable(v.card) or d._settable(v.card))
	if playable.is_empty():
		if deal < 5:
			print("  (nothing to play in this opening hand: dealing a new match)")
			await _duel(deal + 1)
			return
		_check(false, "the opening hand has a card to play")
		return
	at = playable[0].get_global_transform_with_canvas().origin
	await _finger(0, at)
	var dragged := false
	for i in 8:
		await _finger(0, at + Vector2(0, -40.0 * (i + 1)), true, true)
		dragged = dragged or d._dragging
	await _finger(0, at + Vector2(0, -320), false)
	await _wait(0.6)
	_check(dragged, "dragging a hand card picks it up")
	_check(not d._dragging, "letting go puts it down")
