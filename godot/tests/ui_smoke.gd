extends Node
## Drives the duel screen like a player would (card menu → summon → slot, attack → target)
## against the CPU and checks the rules state follows.
## Run:  godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn

var duel_screen: Node
var summons := 0
var attacks := 0
var prompts := {}


func _ready() -> void:
	duel_screen = load("res://scenes/duel.tscn").instantiate()
	add_child(duel_screen)
	_run()


## Raise a prompt for the player and answer it through the on-screen buttons.
func _prompt_check() -> void:
	for i in 300:
		if duel_screen.get("duel") != null:
			break
		await get_tree().process_frame
	if duel_screen.get("duel") == null:
		push_error("UI smoke failed: the duel screen didn't load")
		get_tree().quit(1)
		return
	var d: DuelState = duel_screen.duel
	while duel_screen._playing or d.active != "player" or d.phase != "deployment":
		await get_tree().process_frame
	var answered: Array = []
	d._ask("player", "test", "Pick one", {}, [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}],
		func(o): answered.append(o))
	d._flush_asks()
	duel_screen._queue.append_array(d.take_events())
	duel_screen._pump()
	while duel_screen._playing:
		await get_tree().process_frame
	_check(duel_screen._mode == "choose", "prompt panel shown")
	_first_enabled_button(duel_screen._menu).pressed.emit()
	_check(answered == ["a"], "prompt answer reaches the rules")
	_check(d.pending.is_empty(), "prompt cleared")
	prompts["test"] = 1


func _run() -> void:
	await _prompt_check()
	var frames := 0
	while frames < 60 * 1800 and (summons < 6 or attacks < 6):
		await get_tree().process_frame
		frames += 1
		var d: DuelState = duel_screen.duel
		if d == null or d.winner != "":
			break
		if duel_screen._playing:
			continue
		if not d.pending.is_empty() and d.pending.side == "player":
			if d.pending.kind == "discard":
				_check(duel_screen._mode == "discard", "discard prompt shown")
				var v: CardView = duel_screen.hand.player[0]
				duel_screen._act("player", {"kind": "discard", "uid": v.uid})
			else:
				_check(duel_screen._mode == "choose", "effect prompt shown")
				var btn := _first_enabled_button(duel_screen._menu)
				_check(btn != null, "prompt has buttons")
				prompts[d.pending.key] = prompts.get(d.pending.key, 0) + 1
				btn.pressed.emit()
			continue
		if d.active != "player":
			continue
		if duel_screen._mode != "idle":
			continue
		match d.phase:
			"deployment":
				if not _try_summon():
					duel_screen._on_next()
			"brawl":
				if not _try_attack():
					duel_screen._on_next()
			_:
				duel_screen._on_next()
	print("UI smoke: summons %d, attacks %d, turn %d, prompts answered %s" % [summons, attacks, duel_screen.duel.turn, prompts])
	get_tree().quit(0 if summons >= 1 else 1)


func _try_summon() -> bool:
	for v in duel_screen.hand.player:
		if v.card.cardType != "gang_member" or not duel_screen._playable(v.card):
			continue
		duel_screen._open_hand_menu(v)
		_check(duel_screen._mode == "menu", "menu opens")
		var btn := _first_enabled_button(duel_screen._menu)
		_check(btn != null, "menu has an enabled option")
		btn.pressed.emit()
		_check(duel_screen._mode == "place", "slot choice after SUMMON")
		var key: String = duel_screen._valid.keys()[0]
		var slot := int(key.split(":")[1])
		duel_screen._place(slot)
		_check(duel_screen.duel.sides.player.field[slot] != null, "card is on the field")
		summons += 1
		return true
	return false


func _try_attack() -> bool:
	for slot in duel_screen.field.player:
		if not duel_screen.duel.can_attack_with("player", slot):
			continue
		duel_screen._on_field_click(slot)
		_check(duel_screen._mode == "target", "targeting mode")
		if duel_screen._direct_btn:
			duel_screen._direct_btn.pressed.emit()
		else:
			var key: String = duel_screen._valid.keys()[0]
			duel_screen._cancel_interaction()
			duel_screen._act("player", {"kind": "attack", "from": slot, "target": int(key.split(":")[1])})
		_check(duel_screen.duel.sides.player.field[slot] == null or duel_screen.duel.sides.player.field[slot].has_attacked,
			"attack resolved")
		attacks += 1
		return true
	return false


func _first_enabled_button(n: Node) -> Button:
	if n is Button and not n.disabled:
		return n
	for c in n.get_children():
		var b := _first_enabled_button(c)
		if b:
			return b
	return null


func _check(ok: bool, what: String) -> void:
	if not ok:
		push_error("UI smoke failed: " + what)
		get_tree().quit(1)
