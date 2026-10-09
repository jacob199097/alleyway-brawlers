extends Node
## Drives the duel screen like a player would (card menu → summon → slot, attack → target)
## against the CPU and checks the rules state follows.
## Run:  godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn

var duel_screen: Node
var summons := 0
var attacks := 0


func _ready() -> void:
	duel_screen = load("res://scenes/duel.tscn").instantiate()
	add_child(duel_screen)
	_run()


func _run() -> void:
	var frames := 0
	while frames < 60 * 600 and (summons < 3 or attacks < 2):
		await get_tree().process_frame
		frames += 1
		var d: DuelState = duel_screen.duel
		if d == null or d.winner != "":
			break
		if duel_screen._playing or d.active != "player":
			continue
		if not d.pending.is_empty():
			_check(duel_screen._mode == "discard", "discard prompt shown")
			var v: CardView = duel_screen.hand.player[0]
			duel_screen._act("player", {"kind": "discard", "uid": v.uid})
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
	print("UI smoke: summons %d, attacks %d, turn %d" % [summons, attacks, duel_screen.duel.turn])
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
