extends Node
## The keywords of 0.9.154 on the real duel screen, one after another with a caption, for a recording.
## The rules run as in a match; the cards are copies of real ones given the keywords (none has them yet).
##   godot --path godot --rendering-driver opengl3_angle --resolution 1280x720 --write-movie <out.avi> --fixed-fps 30 res://tests/keyword_showcase.tscn

const Keywords := preload("res://scripts/keywords.gd")

var screen: Node
var d: DuelState
var _band: Control
var _title: Label
var _text: Label


func _ready() -> void:
	screen = load("res://scenes/duel.tscn").instantiate()
	add_child(screen)
	_caption_layer()
	await _to_my_turn()
	_stage()
	await _hold(1.5)
	await _say("BRAND NEW KEYWORDS", "Eleven of them, as they look in a match", Color.WHITE, 2.4)
	await _say("TAUNT", "Enemies have to attack it: no other target, and no direct attacks", "TAUNT", 3.2)
	await _say("SHROUD", "It can't be attacked or targeted until it attacks", "SHROUD", 3.2)
	await _say("CORRODE", "At the start of its owner's next 3 turns, it loses DEF", "CORRODE", 0.6)
	await _play(func(): d._do_fx("player", 4, _card("player", 4), {"do": "corrode", "target": "enemies", "amount": 200}))
	await _hold(1.2)
	await _play(func(): d._status_ticks("opponent"))
	await _hold(1.4)
	await _say("CONFUSE", "Its attacks are a coin flip: tails, it hits the wrong target, even its own side", "CONFUSE", 0.6)
	await _play(func(): d._do_fx("player", 4, _card("player", 4), {"do": "confuse", "target": "opposite"}))
	await _hold(1.8)
	await _say("RALLY", "Your other characters get more ATK this turn", "RALLY", 0.6)
	await _play(func(): d._do_fx("player", 4, _card("player", 4), {"do": "rally", "amount": 300}))
	await _hold(1.6)
	await _say("DEBT", "Your opponent's next card costs more Authority", "DEBT", 0.6)
	await _play(func(): d._do_fx("player", 4, _card("player", 4), {"do": "debt", "amount": 2}))
	await _hold(1.6)
	await _say("ECHO", "A card's effect happens again at the start of your next turn", "ECHO", 0.6)
	await _play(func():
		d._echo_later("player", 4, _card("player", 4), {"do": "draw", "amount": 1, "echo": true})
		d._run_echoes("player"))
	await _hold(1.6)
	await _play(func(): d._set_phase("brawl"))
	await _say("BRACE  ·  SHROUD", "The first attacker each turn loses ATK  ·  attacking lifts the SHROUD", "BRACE", 0.6)
	await _play(func(): d.do_action("player", {"kind": "attack", "from": 3, "target": 2}))
	await _hold(1.8)
	await _say("RECKLESS", "More ATK when it attacks, then it goes Down", "RECKLESS", 0.6)
	await _play(func(): d.do_action("player", {"kind": "attack", "from": 0, "target": 0}))
	await _hold(1.8)
	await _say("HEIST", "Costing your opponent Morale in a brawl draws you a card", "HEIST", 0.6)
	await _play(func(): d.do_action("player", {"kind": "attack", "from": 1, "target": 1}))
	await _hold(1.8)
	await _say("CONFUSED", "Tails: it attacks one of its own side", "CONFUSE", 0.6)
	await _play(func():
		var c: Dictionary = _card("player", 2)
		c.confuse_until = d.turn + 3
		d._emit("status", {"side": "player", "slot": 2, "kind": "confuse", "card": c.duplicate(true)})
		d._recalc())
	await _hold(1.4)
	_tails_on_own_side(2, 4)
	await _play(func(): d.do_action("player", {"kind": "attack", "from": 2, "target": 4}))
	await _hold(2.4)
	await _say("HOVER A KEYWORD ON A CARD", "to read it in full", Color.WHITE, 3.0)
	get_tree().quit(0)


## Wait for the duel to load and the opening hand, then for the player's first turn.
func _to_my_turn() -> void:
	while screen.get("duel") == null:
		await get_tree().process_frame
	d = screen.duel
	while screen._playing or d.active != "player" or d.phase != "deployment" or not d.pending.is_empty():
		if not screen._playing and d.pending.get("side") == "player" and screen._mode == "choose":
			var keep := _button_named(screen._menu, "KEEP THIS HAND")
			if keep:
				keep.pressed.emit()
		await get_tree().process_frame


## The board for the show: test copies of real cards carrying the keywords.
func _stage() -> void:
	d.turn = 5
	var mine := [
		{"id": "card_pira_044", "attack": 1700, "defense": 1500, "effects": [{"when": "passive", "do": "reckless", "amount": 600}], "effectText": "This card is RECKLESS 600."},
		{"id": "card_pira_042", "attack": 2400, "defense": 1500, "effects": [{"when": "passive", "do": "heist", "amount": 1}], "effectText": "This card has HEIST 1."},
		{"id": "card_mili_004", "attack": 1500, "defense": 2000, "effects": [{"when": "passive", "do": "taunt"}], "effectText": "This card has TAUNT."},
		{"id": "card_unde_045", "attack": 2000, "defense": 1500, "effects": [{"when": "passive", "do": "shroud"}], "effectText": "This card has SHROUD."},
		{"id": "card_wild_007", "attack": 1800, "defense": 1500, "effects": [], "effectText": "When deployed: RALLY 300. CORRODE. CONFUSE. DEBT 2. Draw 1 card. ECHO."},
	]
	var theirs := [
		{"id": "card_nebu_013"}, {"id": "card_arso_003"},
		{"id": "card_mili_001", "attack": 1600, "defense": 1600, "effects": [{"when": "passive", "do": "brace", "amount": 600}], "effectText": "This card has BRACE 600."},
		{"id": "card_unde_006"}, {"id": "card_neut_006"},
	]
	for side in ["player", "opponent"]:
		for v in screen.hand[side]:
			v.queue_free()
		screen.hand[side].clear()
		for slot in screen.field[side]:
			screen.field[side][slot].queue_free()
		screen.field[side].clear()
		var s: Dictionary = d.sides[side]
		s.field = []
		s.field.resize(10)
		var specs: Array = mine if side == "player" else theirs
		for i in specs.size():
			var c := d.make_card(specs[i])
			c.deployed_turn = 1
			s.field[i] = c
	for side in screen.leaders:
		screen.leaders[side].queue_free()
	screen.leaders.clear()
	d._recalc()
	d.take_events()
	screen._make_leader_views()
	screen.counts = d._counts()
	screen._build_from_view()
	screen._refresh_hud()


## Fix the luck so the CONFUSED attacker's coin comes up tails and its wrong target is one of its own side.
func _tails_on_own_side(from: int, target: int) -> void:
	var wrong: Array = d._confused_targets("player", "opponent", from, target)
	for i in 5000:
		var saved: int = d._luck_t
		var coin := d._luck_next()
		var pick: Dictionary = wrong[mini(wrong.size() - 1, int(floor(d._luck_next() * wrong.size())))]
		d._luck_t = saved
		if coin >= 0.5 and pick.side == "player":
			return
		d._luck_next()


func _card(side: String, slot: int) -> Dictionary:
	return d.sides[side].field[slot]


## Run some rules, then let the screen play what they did.
func _play(rules: Callable) -> void:
	rules.call()
	d._flush_asks()
	screen._queue.append_array(d.take_events())
	screen._pump()
	await get_tree().process_frame
	while screen._playing:
		await get_tree().process_frame


func _hold(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _caption_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_band = ColorRect.new()
	_band.color = Color(0.02, 0.02, 0.05, 0.72)
	_band.position = Vector2(620, 34)   # (over the opponent's empty back row)
	_band.size = Vector2(920, 84)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.modulate.a = 0.0
	layer.add_child(_band)
	_title = UI.label("", 38, Color.WHITE, true)
	_title.position = Vector2(0, 2)
	_title.size = Vector2(920, 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_title)
	_text = UI.label("", 19, Color(0.9, 0.9, 0.95))
	_text.position = Vector2(0, 48)
	_text.size = Vector2(920, 28)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_text)


## The caption: the keyword's name in its own colour (kw: a keyword or a colour), a line under it.
func _say(title: String, text: String, kw, secs: float) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", Keywords.color(kw) if kw is String else kw)
	_text.text = text
	var t := _band.create_tween()
	t.tween_property(_band, "modulate:a", 1.0, 0.2)
	await _hold(secs)


func _button_named(n: Node, text: String) -> Button:
	if n is Button and not n.disabled and n.text.strip_edges().begins_with(text):
		return n
	for c in n.get_children():
		var b := _button_named(c, text)
		if b:
			return b
	return null
