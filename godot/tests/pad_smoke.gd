extends Node
## Controller support (scripts/pad.gd) driven by fake controller input: the D-pad jumps between
## buttons, A clicks, the right stick scrolls a list, and in a duel A on a hand card opens its menu.
## Needs a window (the pointer's clicks go through it):
##   godot --path godot --resolution 1280x720 res://tests/pad_smoke.tscn

var fails: Array = []


func _ready() -> void:
	await _buttons()
	await _duel()
	if fails.is_empty():
		print("PAD SMOKE OK")
		get_tree().quit(0)
	else:
		for f in fails:
			push_error("PAD SMOKE: " + f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails.append(what)


func _press(button: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _buttons() -> void:
	var ui := Control.new()
	ui.size = Vector2(1920, 1080)
	add_child(ui)
	var clicked: Array = []
	var row: Array = []
	for i in 3:
		var b := Button.new()
		b.text = "B%d" % i
		b.position = Vector2(300 + i * 400, 200)
		b.size = Vector2(240, 80)
		b.pressed.connect(func(): clicked.append(i))
		ui.add_child(b)
		row.append(b)
	var list := ScrollContainer.new()
	list.position = Vector2(300, 400)
	list.size = Vector2(400, 300)
	ui.add_child(list)
	var col := VBoxContainer.new()
	list.add_child(col)
	for i in 20:
		var b := Button.new()
		b.text = "Item %d" % i
		b.custom_minimum_size = Vector2(380, 70)
		col.add_child(b)
	await _frames(3)
	# From the middle of the screen, up goes to the button above
	Game.pad._set_active(true)   # (it starts where the real mouse is: put it in the middle)
	Game.pad._move_to(Vector2(960, 540))
	await _press(JOY_BUTTON_DPAD_UP)
	await _frames(12)
	_check(Game.pad.active, "a controller button turns the pointer on")
	_check(Game.pad.cursor.distance_to(_centre(row[1])) < 2.0, "D-pad up from the middle lands on the button above")
	await _press(JOY_BUTTON_DPAD_LEFT)
	await _frames(12)
	_check(Game.pad.cursor.distance_to(_centre(row[0])) < 2.0, "D-pad left goes to the next button that way")
	_check(row[0].is_hovered(), "the button under the pointer is hovered")
	await _press(JOY_BUTTON_A)
	_check(clicked == [0], "A clicks the button under the pointer (got %s)" % [clicked])
	# Down into the list, then down past its bottom edge: it scrolls
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _frames(12)
	var first: Control = col.get_child(0)
	_check(Game.pad.cursor.distance_to(_centre(first)) < 2.0, "D-pad down goes into the list")
	for i in 6:
		await _press(JOY_BUTTON_DPAD_DOWN)
		await _frames(12)
	_check(list.scroll_vertical > 0, "D-pad down past the bottom scrolls the list (scroll %d)" % list.scroll_vertical)
	# Moving the real mouse hands it back
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(40, 0)
	m.position = Vector2(100, 100)
	Input.parse_input_event(m)
	await _frames(2)
	_check(not Game.pad.active, "moving the mouse turns the pointer off")
	ui.queue_free()
	await _frames(2)


func _duel() -> void:
	var duel: Node = load("res://scenes/duel.tscn").instantiate()
	add_child(duel)
	for i in 1200:
		await get_tree().process_frame
		var d = duel.get("duel")
		if d and d.active == "player" and d.phase == "deployment" and d.pending.is_empty() and not duel._playing \
				and duel._mode == "idle" and not duel.hand.player.is_empty():
			break
		if d and d.pending.get("side") == "player" and duel._mode == "choose" and duel._menu:
			for b in duel._menu.find_children("*", "Button", true, false):
				if not b.disabled:
					b.pressed.emit()
					break
	_check(duel._mode == "idle" and not duel.hand.player.is_empty(), "the duel reaches the player's turn")
	await _frames(30)
	Game.pad._set_active(true)
	Game.pad._move_to(Vector2(960, 540))
	# Down from the middle of the board: onto a hand card (the hand is along the bottom)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _frames(12)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _frames(20)
	var on_hand: bool = duel._hand_view_at(Game.pad.pointer(duel)) != null
	_check(on_hand, "the D-pad reaches a card in the hand")
	await _press(JOY_BUTTON_A)
	await _frames(20)
	_check(duel._mode == "menu", "A on a hand card opens its menu (mode %s)" % duel._mode)
	await _press(JOY_BUTTON_B)
	await _frames(10)
	_check(duel._mode != "menu", "B closes the menu")
	duel.queue_free()
