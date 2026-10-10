extends Screen
## Rock · Paper · Scissors decides who goes first; the winner picks. Against the CPU it runs
## here; against a player the server runs it (backend/socket/onlineMatch.js, mp:rps…) and this
## screen shows it, then mp:start opens the duel.

const CHOICES := {
	"rock": {"glyph": "✊", "label": "ROCK", "color": Color("e07b39"), "beats": "scissors"},
	"paper": {"glyph": "✋", "label": "PAPER", "color": Color("4cc9f0"), "beats": "rock"},
	"scissors": {"glyph": "✌", "label": "SCISSORS", "color": Color("e63946"), "beats": "paper"},
}

var _round := 1
var _layer: Control
var _online := false      # against a player (the server decides)
var _rps_id := ""
var _rival := "RIVAL"
var _deadline := 0        # ms: when an unanswered pick or choice is made for you
var _countdown: Label
var _mine := ""
var _foe_box: Control


func _ready() -> void:
	UI.background(self, "duel_background.png", 0.55)
	_layer = Control.new()
	_layer.size = size
	add_child(_layer)
	_online = Game.duel_setup.get("online_rps", false)
	if not _online:
		back_to = "fight_mode"
		_choose()
		return
	_text("SCISSORS · PAPER · ROCK", Vector2(0, 60), 56, UI.GOLD)
	_text("Getting ready…", Vector2(0, 140), 26, UI.MUTED)


## Net marks this screen as the place for mp:rps messages.
func on_rps() -> void:
	pass


func _process(_delta: float) -> void:
	if not _online:
		return
	while not Net.rps_inbox.is_empty():
		var msg: Array = Net.rps_inbox.pop_front()
		_on_rps_event(msg[0], msg[1] if msg[1] is Dictionary else {})
	if _countdown and is_instance_valid(_countdown) and _deadline > 0:
		_countdown.text = "%ds" % maxi(0, ceili((_deadline - Time.get_ticks_msec()) / 1000.0))


func _on_rps_event(name: String, d: Dictionary) -> void:
	match name:
		"mp:rps":
			_rps_id = str(d.get("rpsId", ""))
			_round = int(d.get("round", 1))
			var opp = d.get("opponent")
			if opp is Dictionary:
				_rival = str(opp.get("username", "RIVAL")).to_upper()
			_deadline = Time.get_ticks_msec() + int(d.get("secs", 15)) * 1000
			_choose()
		"mp:rps_result":
			if str(d.get("rpsId", "")) == _rps_id:
				_show_result(str(d.get("you", "rock")), str(d.get("opponent", "rock")), str(d.get("outcome", "draw")))
		"mp:rps_choose":
			_deadline = Time.get_ticks_msec() + int(d.get("secs", 10)) * 1000
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 40)
			row.position = Vector2(600, 900)
			row.add_child(UI.button("⚡  GO FIRST", _send_first.bind(true, row), Vector2(330, 72)))
			row.add_child(UI.button("🛡  GO SECOND", _send_first.bind(false, row), Vector2(330, 72), Color("9b59b6")))
			_layer.add_child(row)
			_countdown = _text("", Vector2(0, 990), 26, UI.MUTED)
		"mp:rps_decided":
			_deadline = 0
			var you_first: bool = d.get("first") == "you"
			_text("You go first!" if you_first else "%s goes first!" % _rival, Vector2(0, 990), 34, UI.BLUE if you_first else UI.RED)
		"mp:rps_cancel":
			_deadline = 0
			var requeued: bool = d.get("requeued", false)
			UI.dialog(self, "MATCH CANCELLED", str(d.get("message", "Your opponent left.")),
				[["OK", func(): Game.go("matchmaking" if requeued else "fight_mode")]], UI.RED)


func _send_first(go_first: bool, row: Control) -> void:
	Sfx.play("click")
	row.queue_free()
	Net.send("mp:rps_first", {"rpsId": _rps_id, "goFirst": go_first})


func _clear() -> void:
	for c in _layer.get_children():
		c.queue_free()


func _text(t: String, at: Vector2, font_size: int, color: Color) -> Label:
	var l := UI.label(t, font_size, color, true)
	l.size = Vector2(1920, font_size * 1.4)
	l.position = Vector2(0, at.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(l)
	return l


func _choose() -> void:
	_clear()
	_text("SCISSORS · PAPER · ROCK", Vector2(0, 60), 56, UI.GOLD)
	var sub := "ROUND %d — DRAW! Throw again" % _round if _round > 1 else "Choose your throw to decide who goes first"
	if _online:
		sub = ("ROUND %d — DRAW! Throw again vs %s" % [_round, _rival]) if _round > 1 else "VS %s — the winner chooses who goes first" % _rival
	_text(sub, Vector2(0, 140), 26, UI.MUTED)
	if _online:
		_countdown = _text("", Vector2(0, 800), 30, UI.GOLD)
	var keys := CHOICES.keys()
	for i in keys.size():
		var k: String = keys[i]
		var c: Dictionary = CHOICES[k]
		var b := Button.new()
		b.custom_minimum_size = Vector2(440, 520)
		b.position = Vector2(230 + i * 520, 250)
		b.add_theme_stylebox_override("normal", UI.box(Color(0.05, 0.05, 0.12, 0.92), c.color, 3, 14))
		b.add_theme_stylebox_override("hover", UI.box(Color(0.1, 0.1, 0.2, 0.95), UI.GOLD, 4, 14))
		var g := UI.label(c.glyph, 180, c.color, false)
		g.size = Vector2(440, 360)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(g)
		var l := UI.label(c.label, 44, c.color, true)
		l.size = Vector2(440, 60)
		l.position = Vector2(0, 400)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		b.pressed.connect(_throw.bind(k))
		_layer.add_child(b)


func _throw(mine: String) -> void:
	Sfx.play("click")
	if _online:
		_mine = mine
		_deadline = 0
		Net.send("mp:rps_pick", {"rpsId": _rps_id, "pick": mine})
		_clear()
		_text("VS", Vector2(0, 430), 80, Color(1, 1, 1, 0.7))
		_reveal(mine, Vector2(360, 260), "YOU", UI.BLUE, true)
		_foe_box = _reveal(mine, Vector2(1100, 260), _rival.left(14), UI.RED, false)
		_text("Waiting for %s…" % _rival, Vector2(0, 790), 30, UI.MUTED)
		return
	var cpu: String = CHOICES.keys().pick_random()
	_clear()
	_text("VS", Vector2(0, 430), 80, Color(1, 1, 1, 0.7))
	_reveal(mine, Vector2(360, 260), "YOU", UI.BLUE, true)
	var cpu_box := _reveal(cpu, Vector2(1100, 260), "CPU", UI.RED, false)
	await get_tree().create_timer(0.6).timeout
	var glyph: Label = cpu_box.get_meta("glyph")
	var t := create_tween()
	t.tween_property(glyph, "scale:x", 0.0, 0.12)
	t.tween_callback(func():
		glyph.text = CHOICES[cpu].glyph
		glyph.label_settings.font_color = CHOICES[cpu].color)
	t.tween_property(glyph, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK)
	await t.finished
	Sfx.play("hit")
	await get_tree().create_timer(0.4).timeout
	if mine == cpu:
		_text("DRAW!", Vector2(0, 820), 64, UI.GOLD)
		await get_tree().create_timer(1.4).timeout
		_round += 1
		_choose()
	elif CHOICES[mine].beats == cpu:
		_text("YOU WIN!", Vector2(0, 790), 64, UI.BLUE)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 40)
		row.position = Vector2(600, 900)
		row.add_child(UI.button("⚡  GO FIRST", _launch.bind("player"), Vector2(330, 72)))
		row.add_child(UI.button("🛡  GO SECOND", _launch.bind("opponent"), Vector2(330, 72), Color("9b59b6")))
		_layer.add_child(row)
	else:
		var first := ["player", "opponent"].pick_random() as String
		_text("CPU WINS!", Vector2(0, 790), 64, UI.RED)
		_text("CPU chooses to go %s!" % ("second" if first == "player" else "first"), Vector2(0, 880), 30, UI.RED)
		await get_tree().create_timer(1.8).timeout
		_launch(first)


## Online: the server's result (a pick made for you if the time ran out).
func _show_result(mine: String, theirs: String, outcome: String) -> void:
	if _mine != mine or _foe_box == null or not is_instance_valid(_foe_box):
		_clear()
		_text("VS", Vector2(0, 430), 80, Color(1, 1, 1, 0.7))
		_reveal(mine, Vector2(360, 260), "YOU", UI.BLUE, true)
		_foe_box = _reveal(mine, Vector2(1100, 260), _rival.left(14), UI.RED, false)
	_mine = ""
	for c in _layer.get_children():
		if c is Label and c.text.begins_with("Waiting for"):
			c.queue_free()
	var glyph: Label = _foe_box.get_meta("glyph")
	var t := create_tween()
	t.tween_property(glyph, "scale:x", 0.0, 0.12)
	t.tween_callback(func():
		glyph.text = CHOICES[theirs].glyph
		glyph.label_settings.font_color = CHOICES[theirs].color)
	t.tween_property(glyph, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK)
	await t.finished
	Sfx.play("hit")
	match outcome:
		"draw":
			_text("DRAW!", Vector2(0, 820), 64, UI.GOLD)
		"win":
			_text("YOU WIN!", Vector2(0, 790), 64, UI.BLUE)
		_:
			_text("%s WINS!" % _rival, Vector2(0, 790), 64, UI.RED)
			_text("%s is choosing who goes first…" % _rival, Vector2(0, 880), 30, UI.RED)


func _reveal(choice: String, at: Vector2, who: String, accent: Color, show: bool) -> Control:
	var c: Dictionary = CHOICES[choice]
	var p := Panel.new()
	p.position = at
	p.size = Vector2(460, 460)
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.05, 0.12, 0.92), c.color if show else accent, 3, 14))
	_layer.add_child(p)
	var w := UI.label(who, 36, accent, true)
	w.size = Vector2(460, 50)
	w.position = Vector2(0, 20)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(w)
	var g := UI.label(c.glyph if show else "?", 180, c.color if show else Color.WHITE, not show)
	g.size = Vector2(460, 320)
	g.position = Vector2(0, 80)
	g.pivot_offset = g.size / 2
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(g)
	p.set_meta("glyph", g)
	return p


func _launch(first: String) -> void:
	Game.duel_setup.first = first
	Game.go("duel")
