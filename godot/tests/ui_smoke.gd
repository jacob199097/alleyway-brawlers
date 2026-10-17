extends Node
## Drives the duel screen like a player would (card menu → summon → slot, attack → target, a Hustle
## set face-down and then activated) against the CPU and checks the rules state follows.
## Run:  godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn

var duel_screen: Node
var summons := 0
var attacks := 0
var prompts := {}
var set_slot := -1          # where the test's Hustle was set
var set_activated := false
var set_broken := 0         # times the CPU destroyed it first (its deck can break face-down cards)


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
	while duel_screen._playing or d.active != "player" or d.phase != "deployment" or not d.pending.is_empty():
		# The opening-hand (mulligan) prompt comes first: answer it through its buttons
		if not duel_screen._playing and d.pending.get("side") == "player" and duel_screen._mode == "choose":
			prompts[d.pending.key] = prompts.get(d.pending.key, 0) + 1
			_first_enabled_button(duel_screen._menu).pressed.emit()
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
	prompts["test"] = prompts.get("test", 0) + 1


## A Hustle (Supernova Run) drawn, then SET FACE DOWN from its menu into a back-row slot; with the
## Authority, it can be activated straight away.
func _set_hustle() -> void:
	var d: DuelState = duel_screen.duel
	d.sides.player.deck.append(d.make_card("card_nebu_010"))
	d._draw("player")
	duel_screen._queue.append_array(d.take_events())
	duel_screen._pump()
	while duel_screen._playing:
		await get_tree().process_frame
	var v: CardView = null
	for x in duel_screen.hand.player:
		if x.card.id == "card_nebu_010":
			v = x
	_check(v != null, "the Hustle is in the hand")
	duel_screen._open_hand_menu(v)
	var set_btn := _button_named(duel_screen._menu, "SET FACE DOWN")
	_check(set_btn != null, "SET FACE DOWN in a Hustle's menu")
	set_btn.pressed.emit()
	_check(duel_screen._mode == "place", "slot choice after SET FACE DOWN")
	var key: String = duel_screen._valid.keys()[0]
	set_slot = int(key.split(":")[1])
	_check(set_slot in DuelState.BACK, "a back-row slot")
	duel_screen._place(set_slot)
	var c = d.sides.player.field[set_slot]
	_check(c != null and c.id == "card_nebu_010" and c.face_down, "the Hustle is set face-down")
	while duel_screen._playing:
		await get_tree().process_frame
	duel_screen._on_field_click(set_slot)
	_check(duel_screen._mode == "menu" and (_button_named(duel_screen._menu, "ACTIVATE") != null) == d.can_hustle("player", c),
		"ACTIVATE offered whenever it can be activated, the turn it was set too")
	duel_screen._cancel_and_refresh()


## Click the set Hustle, ACTIVATE it (once it can be).
func _try_activate_set() -> bool:
	if set_activated or set_slot < 0:
		return false
	var c = duel_screen.duel.sides.player.field[set_slot]
	if c == null or c.get("id") != "card_nebu_010" or not c.get("face_down", false):
		set_slot = -1   # destroyed: another one is set next
		set_broken += 1
		return false
	if not duel_screen._set_ready(set_slot):
		return false
	duel_screen._on_field_click(set_slot)
	var btn := _button_named(duel_screen._menu, "ACTIVATE")
	_check(btn != null, "ACTIVATE in a set Hustle's menu")
	btn.pressed.emit()
	_check(duel_screen.duel.sides.player.field[set_slot] == null, "the activated Hustle left the back row")
	set_activated = true
	return true


func _run() -> void:
	await _prompt_check()
	await _set_hustle()
	var frames := 0
	while frames < 60 * 1800 and (summons < 6 or attacks < 6 or not set_activated):
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
				prompts[d.pending.key] = prompts.get(d.pending.key, 0) + 1
				if not duel_screen._valid.is_empty():
					# A target on the field: click the first glowing card, as a player would
					var key: String = duel_screen._valid.keys()[0]
					var parts := key.split(":")
					_check(duel_screen._choose_at(duel_screen.slot_pos(parts[0], int(parts[1]))), "clicking a glowing card answers the prompt")
				else:
					var btn := _first_enabled_button(duel_screen._menu)
					_check(btn != null, "prompt has buttons")
					btn.pressed.emit()
			continue
		if d.active != "player":
			continue
		if duel_screen._mode != "idle":
			continue
		match d.phase:
			"deployment":
				if not set_activated and set_slot < 0 and set_broken > 0:
					await _set_hustle()   # (the last one was destroyed before it could be activated)
				elif not _try_activate_set() and not _try_summon():
					duel_screen._on_next()
			"brawl":
				if not _try_attack():
					duel_screen._on_next()
			_:
				duel_screen._on_next()
	print("UI smoke: summons %d, attacks %d, set Hustle activated %s (destroyed first %d times), turn %d, prompts answered %s" % [
		summons, attacks, set_activated, set_broken, duel_screen.duel.turn, prompts])
	get_tree().quit(0 if summons >= 1 and set_activated else 1)


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
		var targets: Array = duel_screen.duel.attack_targets("player")
		duel_screen._on_field_click(slot)
		if duel_screen._mode == "menu":   # a card with an Activate ability asks: ATTACK or the ability
			var atk := _button_named(duel_screen._menu, "ATTACK")
			_check(atk != null, "ATTACK in the card's menu")
			atk.pressed.emit()
		_check(duel_screen._mode == "target", "targeting mode")
		var acted := true
		var picked := -99
		if duel_screen._direct_btn:
			duel_screen._direct_btn.pressed.emit()
		else:
			var key: String = duel_screen._valid.keys()[0]
			duel_screen._cancel_interaction()
			picked = int(key.split(":")[1])
			acted = duel_screen._act("player", {"kind": "attack", "from": slot, "target": picked})
		# The rules must accept the attack. (Checking has_attacked isn't enough: Hunter Lv.3, a card that
		# attacks twice each turn or one that gained an extra attack may attack again.)
		var c = duel_screen.duel.sides.player.field[slot]
		var again: bool = c != null and (c.get("effectKey") == "hunter_lv3" or int(c.get("second_attack", 0)) == duel_screen.duel.turn \
				or int(c.get("again_turn", 0)) == duel_screen.duel.turn)
		_check(acted and (c == null or c.has_attacked or again),
			"attack resolved (slot %d -> %d, acted %s, targets %s, card %s)" % [slot, picked, acted, targets, duel_screen.duel.sides.player.field[slot]])
		attacks += 1
		return true
	return false


func _button_named(n: Node, text: String) -> Button:
	if n is Button and not n.disabled and n.text.strip_edges().begins_with(text):
		return n
	for c in n.get_children():
		var b := _button_named(c, text)
		if b:
			return b
	return null


func _first_enabled_button(n: Node) -> BaseButton:
	if n is BaseButton and not n.disabled:   # (a card in a search's card picker too)
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
