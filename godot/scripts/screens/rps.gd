extends Screen
## Rock · Paper · Scissors against the CPU decides who goes first; the winner picks.

const CHOICES := {
	"rock": {"glyph": "✊", "label": "ROCK", "color": Color("e07b39"), "beats": "scissors"},
	"paper": {"glyph": "✋", "label": "PAPER", "color": Color("4cc9f0"), "beats": "rock"},
	"scissors": {"glyph": "✌", "label": "SCISSORS", "color": Color("e63946"), "beats": "paper"},
}

var _round := 1
var _layer: Control


func _ready() -> void:
	back_to = "fight_mode"
	UI.background(self, "duel_background.png", 0.55)
	_layer = Control.new()
	_layer.size = size
	add_child(_layer)
	_choose()


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
	_text("ROUND %d — DRAW! Throw again" % _round if _round > 1 else "Choose your throw to decide who goes first",
		Vector2(0, 140), 26, UI.MUTED)
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
