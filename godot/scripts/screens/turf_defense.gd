extends Screen
## TURF DEFENSE: pick a boss and a level, and quick-match with another player to fight it together
## (backend/socket/coopMatch.js; the bosses, their levels and rewards: GET /api/turf, from
## data/bosses.json). Level 1 of each boss is open; each level after it opens once you've beaten the
## one before. The first win on Street pays the boss's prize card. Net opens the duel when the match
## starts (coop:start); while you wait, everyone else online gets a pop-up to join you.

const LIST_X := 56.0
const ENTRY := Vector2(520, 178)
const DETAIL := Rect2(610, 150, 1254, 790)
const ART := Vector2(300, 424)
const LEVEL_ICONS := {1: "I", 2: "II", 3: "III"}

var _data := {}                # GET /api/turf
var _boss := {}                # the boss being looked at
var _level := 1
var _entries: Array = []       # the boss list: [{root, id}]
var _detail: Control
var _bg: Array = []            # two background layers, crossfaded when the boss changes
var _bg_front := 0
var _queue: Control            # the "looking for a partner" overlay while queued
var _queue_since := 0.0
var _queue_clock: Label
var _queue_sent := {}          # {boss, level} asked for, sent once the connection is open
var _refresh_in := 10.0


func _ready() -> void:
	back_to = "fight_mode"
	for i in 2:
		var r := TextureRect.new()
		r.size = Vector2(1920, 1080)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.modulate = Color(0.42, 0.42, 0.48, 0.0)
		add_child(r)
		_bg.append(r)
	var veil := ColorRect.new()   # (darker at the edges, so the panels read)
	veil.size = Vector2(1920, 1080)
	veil.color = Color(0.01, 0.01, 0.03, 0.35)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	Game.sound.ambience("city_rain")
	UI.title(self, "TURF DEFENSE")
	var sub := UI.label("Two players  ·  one boss  ·  defend the block together", 22, UI.MUTED)
	sub.size = Vector2(1920, 30)
	sub.position = Vector2(0, 94)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	UI.back_button(self, _back)
	var how := UI.label("Each of you brings your own deck, board and Morale. The boss has far more Morale, draws and gets Authority extra, and turns nastier at each phase. Beat it together and you both win.", 17, UI.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size = Vector2(1300, 50)
	how.position = Vector2(300, 1000)
	add_child(how)
	if not needs_server("Turf Defense"):
		return
	Net.connect_to_server()
	var spin := UI.spinner(self, Vector2(960, 540), "LOADING THE BOSSES…")
	await _load()
	spin.queue_free()
	if _data.is_empty():
		return
	_build_list()
	var join: Dictionary = Net.coop_join
	Net.coop_join = {}
	var first: Dictionary = _data.bosses[0]
	if join.has("boss"):
		for b in _data.bosses:
			if b.id == join.boss:
				first = b
	_select(first, int(join.get("level", 0)))
	_intro()
	if join.has("boss"):   # (from the "join them" pop-up)
		_quick_match()


func _load() -> void:
	var r := await Api.request("GET", "/api/turf")
	if not is_inside_tree():
		return
	if not r.ok or not (r.data is Dictionary) or not (r.data.get("bosses") is Array):
		UI.dialog(self, "TURF DEFENSE", str(r.get("error", "Couldn't load the bosses. The server may need updating.")), [["BACK", _back]], UI.RED)
		return
	_data = r.data


func _back() -> void:
	if _queue:
		Net.send("coop:leave")
	Game.go("fight_mode")


## Esc: stop looking for a partner, or go back.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _queue:
			Net.send("coop:leave")
			_hide_queue()
		else:
			_back()


func _process(delta: float) -> void:
	if not _queue_sent.is_empty() and Net.is_open:
		Net.send("coop:queue", _queue_sent)
		_queue_sent = {}
	while not Net.coop_inbox.is_empty():
		var m: Array = Net.coop_inbox.pop_front()
		_on_message(m[0], m[1])
	if _queue and is_instance_valid(_queue_clock):
		var s := int(Time.get_unix_time_from_system() - _queue_since)
		_queue_clock.text = "%d:%02d" % [s / 60, s % 60]
	# Who's waiting changes as people come and go
	_refresh_in -= delta
	if _refresh_in <= 0.0 and not _data.is_empty():
		_refresh_in = 10.0
		_refresh_waiting()


func _refresh_waiting() -> void:
	var r := await Api.request("GET", "/api/turf")
	if not is_inside_tree() or not r.ok or not (r.data is Dictionary):
		return
	_data.waiting = r.data.get("waiting", {})
	_paint_waiting()


## (Net goes to this screen on coop:queue unless it's already showing)
func on_coop_queue() -> void:
	pass


## Someone else just started looking (net.gd): show it straight away.
func on_coop_looking(_data_in: Dictionary) -> void:
	_refresh_in = 0.0


func _on_message(name: String, data) -> void:
	if not data is Dictionary:
		return
	match name:
		"coop:queue":
			for b in _data.get("bosses", []):
				if b.id == str(data.get("boss", "")):
					_select(b, int(data.get("level", 1)))
			_show_queue(float(data.get("since", Time.get_unix_time_from_system() * 1000.0)) / 1000.0)
		"coop:left":
			_hide_queue()
			var why := str(data.get("reason", ""))
			if why != "":
				UI.dialog(self, "OUT OF THE QUEUE", why, [["OK", func(): pass]], UI.RED)


## coop:start: the duel opens (it shows the boss's entrance).
func on_online_start(_data_in) -> void:
	Game.go("duel")


func on_online_error(message: String) -> void:
	_hide_queue()
	UI.dialog(self, "CAN'T START", message, [["CLOSE", func(): pass]], UI.RED)


# ── The bosses ───────────────────────────────────────────────────────────────

func _build_list() -> void:
	var bosses: Array = _data.bosses
	for i in bosses.size():
		var b: Dictionary = bosses[i]
		var col := Color(str(b.get("color", "#ffffff")))
		var root := Panel.new()
		root.position = Vector2(LIST_X, 150 + i * (ENTRY.y + 26))
		root.size = ENTRY
		root.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.03, 0.08, 0.9), Color(col, 0.35), 2, 12))
		root.mouse_filter = Control.MOUSE_FILTER_STOP
		root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_child(root)
		var pic := UI.texture_rect(UI.card_crop(str(b.get("portrait", ""))), Vector2(150, 150), true)
		pic.position = Vector2(14, 14)
		root.add_child(pic)
		var name_l := UI.label(str(b.get("name", "")).to_upper(), 24, Color.WHITE, true)
		name_l.position = Vector2(180, 16)
		name_l.size = Vector2(326, 60)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(name_l)
		var title := UI.label(str(b.get("title", "")), 16, col.lightened(0.2))
		title.position = Vector2(182, 78)
		root.add_child(title)
		var stars := UI.label(_stars(b), 26, UI.GOLD, true)
		stars.position = Vector2(180, 102)
		root.add_child(stars)
		var prize := UI.label("PRIZE WON  ✓" if b.get("prize_won", false) else "PRIZE: %s" % str(CardDB.get_card(str(b.get("prize", ""))).get("name", "?")).to_upper(), 14, UI.GREEN if b.get("prize_won", false) else UI.MUTED, true)
		prize.position = Vector2(182, 142)
		prize.size = Vector2(326, 20)
		prize.clip_text = true
		root.add_child(prize)
		var waiting := UI.label("", 14, Color("1a1200"), true)
		waiting.add_theme_stylebox_override("normal", UI.box(UI.GOLD, Color.WHITE, 1, 6))
		waiting.position = Vector2(ENTRY.x - 120, 10)
		waiting.visible = false
		root.add_child(waiting)
		root.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play("click")
				_select(b, 0))
		root.mouse_entered.connect(func():
			if _boss.get("id") != b.id:
				root.create_tween().tween_property(root, "position:x", LIST_X + 10.0, 0.12))
		root.mouse_exited.connect(func():
			root.create_tween().tween_property(root, "position:x", LIST_X, 0.12))
		_entries.append({"root": root, "id": str(b.id), "color": col, "waiting": waiting})
	_paint_waiting()


## ★ for each level beaten, ☆ for the rest.
func _stars(b: Dictionary) -> String:
	var s := ""
	for l in b.get("levels", []):
		s += "★" if int(l.get("clears", 0)) > 0 else "☆"
	return s


func _waiting_for(boss_id: String, level := 0) -> int:
	var n := 0
	var w: Dictionary = _data.get("waiting", {}) if _data.get("waiting") is Dictionary else {}
	for k in w:
		var parts := str(k).split(":")
		if parts[0] == boss_id and (level == 0 or (parts.size() > 1 and int(parts[1]) == level)):
			n += int(w[k])
	return n


func _paint_waiting() -> void:
	for e in _entries:
		var n := _waiting_for(e.id)
		e.waiting.text = " %d WAITING " % n
		e.waiting.visible = n > 0
	if _detail and is_instance_valid(_detail) and _detail.has_meta("waiting"):
		var l: Label = _detail.get_meta("waiting")
		var n := _waiting_for(str(_boss.get("id", "")), _level)
		l.text = "⚑  %d PLAYER%s WAITING HERE: JOIN THEM!" % [n, "" if n == 1 else "S"] if n > 0 else ""


## Show a boss (level 0: the first one not beaten yet that's open).
func _select(b: Dictionary, level: int) -> void:
	var changed: bool = _boss.get("id") != b.get("id")
	_boss = b
	var levels: Array = b.get("levels", [])
	if level <= 0:
		level = 1
		for l in levels:
			if l.get("unlocked", false) and int(l.get("clears", 0)) == 0:
				level = int(l.level)
				break
			if l.get("unlocked", false):
				level = int(l.level)
	_level = level
	for e in _entries:
		var on: bool = e.id == str(b.id)
		e.root.add_theme_stylebox_override("panel", UI._glow(UI.box(Color(0.06, 0.04, 0.1, 0.95), e.color, 3, 12), e.color, 0.8) if on \
			else UI.box(Color(0.04, 0.03, 0.08, 0.9), Color(e.color, 0.35), 2, 12))
		e.root.create_tween().tween_property(e.root, "position:x", LIST_X + (22.0 if on else 0.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if changed:
		_show_arena(str(b.get("arena", "")))
		Sfx.play("flip", 0.9, -4.0)
	_build_detail(changed)


func _show_arena(id: String) -> void:
	var arena: Dictionary = preload("res://scripts/ui/arena_roulette.gd").find(id)
	var path := "res://assets/" + str(arena.get("image", "arena_1v1.png"))
	if not ResourceLoader.exists(path):
		return
	_bg_front = 1 - _bg_front
	var front: TextureRect = _bg[_bg_front]
	var back: TextureRect = _bg[1 - _bg_front]
	front.texture = load(path)
	move_child(front, 1)
	var t := create_tween().set_parallel()
	t.tween_property(front, "modulate:a", 1.0, 0.6)
	t.tween_property(back, "modulate:a", 0.0, 0.6)
	front.scale = Vector2.ONE * 1.04
	front.pivot_offset = front.size / 2
	t.tween_property(front, "scale", Vector2.ONE, 6.0).set_trans(Tween.TRANS_SINE)


func _build_detail(animate: bool) -> void:
	if _detail and is_instance_valid(_detail):
		_detail.queue_free()
	var b := _boss
	var col := Color(str(b.get("color", "#ffffff")))
	var lv := _level_data()
	var root := Panel.new()
	root.position = DETAIL.position
	root.size = DETAIL.size
	root.add_theme_stylebox_override("panel", UI._glow(UI.box(Color(0.03, 0.02, 0.06, 0.62), Color(col, 0.75), 2, 14), col, 0.5))
	add_child(root)
	UI.glass(root, Color(0.03, 0.02, 0.06, 0.55), 10.0)
	_detail = root
	if _queue and is_instance_valid(_queue):   # (the queue overlay stays on top)
		move_child(_queue, -1)
	# The boss's card, over a glow in its colour, floating
	var glow := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray([Color(col, 0.5), Color(col, 0.0)])
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	glow.texture = g
	glow.size = Vector2(560, 620)
	glow.position = Vector2(-90, 10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)
	var art_card: Dictionary = CardDB.get_card(str(b.get("portrait", ""))).duplicate()
	art_card.id = str(b.get("portrait", ""))
	var art := CardTile.make(art_card, ART)
	art.position = Vector2(40, 60)
	art.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	art.pressed.connect(func(t): UI.card_zoom(self, t.card))
	root.add_child(art)
	var bob := art.create_tween().set_loops()
	bob.tween_property(art, "position:y", 48.0, 2.0).set_trans(Tween.TRANS_SINE)
	bob.tween_property(art, "position:y", 60.0, 2.0).set_trans(Tween.TRANS_SINE)
	var tag := UI.label(str(CardDB.clan(str(b.get("clan", ""))).get("name", str(b.get("clan", "")).capitalize())).to_upper() + " BOSS", 16, col.lightened(0.3), true)
	tag.position = Vector2(40, 500)
	tag.size = Vector2(ART.x, 24)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tag)
	# Name, title, a line of theirs
	var x := 380.0
	var w := DETAIL.size.x - x - 36.0
	var name_l := UI.label(str(b.get("name", "")).to_upper(), 50, Color.WHITE, true)
	name_l.label_settings.outline_color = Color(col, 0.8)
	name_l.label_settings.outline_size = 10
	name_l.position = Vector2(x, 26)
	name_l.size = Vector2(w, 64)
	root.add_child(name_l)
	var title := UI.label(str(b.get("title", "")).to_upper(), 22, col.lightened(0.25), true)
	title.position = Vector2(x + 2, 88)
	root.add_child(title)
	var intro: Array = b.get("lines", {}).get("intro", []) if b.get("lines") is Dictionary else []
	if not intro.is_empty():
		var quote := UI.label("“%s”" % str(intro[0]), 19, Color(0.88, 0.86, 0.95))
		quote.position = Vector2(x + 2, 122)
		quote.size = Vector2(w, 30)
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(quote)
	# The levels
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	tabs.position = Vector2(x, 178)
	root.add_child(tabs)
	for l in b.get("levels", []):
		tabs.add_child(_level_tab(l, col))
	# This level: what the boss has, and its phases
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.position = Vector2(x, 268)
	info.size = Vector2(w, 0)
	root.add_child(info)
	var stats := UI.label(_stat_line(lv), 20, Color.WHITE, true)
	info.add_child(stats)
	var phases: Array = lv.get("phases", [])
	var ph_head := UI.label("PHASES", 16, UI.MUTED, true)
	info.add_child(ph_head)
	var p1 := UI.label("1  ·  THE FIGHT BEGINS", 18, Color(1, 1, 1, 0.8), true)
	info.add_child(p1)
	for i in phases.size():
		var row := UI.label("%d  ·  %s   (at %d Morale)" % [i + 2, str(phases[i].get("label", "")).to_upper(), int(phases[i].get("below", 0))], 18, col.lightened(0.35), true)
		info.add_child(row)
	# What beating it pays
	var pay := _pay_box(lv, col)
	pay.position = Vector2(x, 500)
	root.add_child(pay)
	# Record, who's waiting, and the button
	var rec := UI.label(_record(lv), 16, UI.MUTED)
	rec.position = Vector2(x, 694)
	root.add_child(rec)
	var waiting := UI.label("", 18, UI.GOLD, true)
	waiting.position = Vector2(x, 720)
	root.add_child(waiting)
	root.set_meta("waiting", waiting)
	var pulse := waiting.create_tween().set_loops()
	pulse.tween_property(waiting, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(waiting, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	var open: bool = lv.get("unlocked", false)
	var go := UI.button("QUICK MATCH" if open else "🔒  " + _lock_text(), _quick_match, Vector2(400, 76), UI.GREEN if open else UI.MUTED)
	go.disabled = not open
	go.position = Vector2(DETAIL.size.x - 436, 680)
	root.add_child(go)
	_paint_waiting()
	if animate:
		root.modulate.a = 0.0
		root.position.x = DETAIL.position.x + 40
		var t := root.create_tween().set_parallel()
		t.tween_property(root, "modulate:a", 1.0, 0.25)
		t.tween_property(root, "position:x", DETAIL.position.x, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _level_data() -> Dictionary:
	for l in _boss.get("levels", []):
		if int(l.level) == _level:
			return l
	return {}


func _level_tab(l: Dictionary, col: Color) -> Control:
	var n := int(l.level)
	var open: bool = l.get("unlocked", false)
	var beaten := int(l.get("clears", 0)) > 0
	var on := n == _level
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 70)
	b.text = "%s  %s%s" % [LEVEL_ICONS.get(n, str(n)), str(l.get("name", "")).to_upper(), "  ✓" if beaten else ("" if open else "  🔒")]
	b.add_theme_font_size_override("font_size", 24)
	var accent: Color = col if on else (Color(1, 1, 1, 0.35) if open else Color(1, 1, 1, 0.15))
	b.add_theme_stylebox_override("normal", UI.box(Color(col.darkened(0.7), 0.95) if on else Color(0.05, 0.05, 0.1, 0.9), accent, 3 if on else 2, 10))
	b.add_theme_stylebox_override("hover", UI.box(Color(col.darkened(0.6), 0.95), col, 3, 10))
	b.add_theme_color_override("font_color", Color.WHITE if open else Color(1, 1, 1, 0.45))
	b.pressed.connect(func():
		Sfx.play("click")
		_level = n
		_build_detail(false))
	UI.juice(b)
	return b


func _stat_line(lv: Dictionary) -> String:
	var bits := ["%d MORALE" % int(lv.get("morale", 0))]
	if int(lv.get("draw", 0)) > 0:
		bits.append("DRAWS %d EXTRA" % int(lv.draw))
	if int(lv.get("authority", 0)) > 0:
		bits.append("+%d AUTHORITY A TURN" % int(lv.authority))
	return "  ·  ".join(bits)


func _lock_text() -> String:
	for l in _boss.get("levels", []):
		if int(l.level) == _level - 1:
			return "BEAT %s FIRST" % str(l.get("name", "")).to_upper()
	return "LOCKED"


func _record(lv: Dictionary) -> String:
	var c := int(lv.get("clears", 0))
	var a := int(lv.get("attempts", 0))
	if a == 0:
		return "Not fought yet"
	var s := "%d win%s in %d fight%s" % [c, "" if c == 1 else "s", a, "" if a == 1 else "s"]
	if lv.get("best_turns") != null:
		s += "  ·  best: %d turns" % int(lv.best_turns)
	return s


## The rewards for this level: its first clear (Street: the prize card too), or what every win after pays.
func _pay_box(lv: Dictionary, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.02, 0.05, 0.8), Color(UI.GOLD, 0.5), 2, 10))
	p.custom_minimum_size = Vector2(DETAIL.size.x - 380 - 36, 176)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	p.add_child(row)
	var first: bool = int(lv.get("clears", 0)) == 0
	var r: Dictionary = (lv.get("first_clear", {}) if first else lv.get("clear", {}))
	var prize_id := str(_boss.get("prize", ""))
	if first and int(lv.level) == 1 and prize_id != "" and not _boss.get("prize_won", false):
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(110, 156)
		row.add_child(stage)
		var c: Dictionary = CardDB.get_card(prize_id).duplicate()
		c.id = prize_id
		var tile := CardTile.make(c, Vector2(110, 156))
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
		stage.add_child(tile)
		tile.rest_rotation = -4.0
	var col_v := VBoxContainer.new()
	col_v.add_theme_constant_override("separation", 6)
	col_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col_v)
	col_v.add_child(UI.label("FIRST CLEAR" if first else "EVERY WIN", 18, UI.GOLD, true))
	if first and int(lv.level) == 1 and prize_id != "" and not _boss.get("prize_won", false):
		var pc: Dictionary = CardDB.get_card(prize_id)
		var rarity := int(pc.get("rarity", 1))
		col_v.add_child(UI.label("PRIZE CARD: %s" % str(pc.get("name", "?")).to_upper(), 22, UI.rarity_color(rarity), true))
		col_v.add_child(UI.label(str(UI.RARITY_LABEL.get(rarity, "")).to_upper() + ("  ·  ALL ITS LEVELS" if pc.get("promotesTo") is String else "") + "  ·  right-click to look", 14, UI.MUTED))
	var bits := []
	if int(r.get("karat", 0)) > 0:
		bits.append("%d KARAT" % int(r.karat))
	if int(r.get("xp", 0)) > 0:
		bits.append("%d XP" % int(r.xp))
	if int(r.get("packs", 0)) > 0:
		bits.append("%d FREE PACK%s" % [int(r.packs), "" if int(r.packs) == 1 else "S"])
	col_v.add_child(UI.label("  ·  ".join(bits), 24, Color.WHITE, true))
	if first and _level < (_boss.get("levels", []) as Array).size():
		col_v.add_child(UI.label("…and the next level opens", 15, UI.MUTED))
	var loss: Dictionary = _data.get("loss", {}) if _data.get("loss") is Dictionary else {}
	if not loss.is_empty():
		col_v.add_child(UI.label("A loss still pays %d Karat and %d XP" % [int(loss.get("karat", 0)), int(loss.get("xp", 0))], 14, UI.MUTED))
	return p


# ── Quick match ──────────────────────────────────────────────────────────────

func _quick_match() -> void:
	if _queue or not _level_data().get("unlocked", false):
		return
	var spin := UI.spinner(self, Vector2(1236, 980), "CHECKING YOUR DECK…")
	var deck := await Game.load_duel_deck()
	spin.queue_free()
	if not is_inside_tree():
		return
	if deck.has("error"):
		var buttons := [["CLOSE", func(): pass]]
		if deck.get("gate", false):
			buttons.push_front(["DECK EDITOR", func(): Game.go("deck_builder"), UI.BLUE])
		UI.dialog(self, "CAN'T START", deck.error, buttons, UI.RED)
		return
	Sfx.play("ambush", 1.1, -4.0)
	_queue_sent = {"boss": str(_boss.get("id", "")), "level": _level}
	_show_queue(Time.get_unix_time_from_system())


## Waiting for a partner: the boss looms, a clock counts up, and you can stop looking.
func _show_queue(since: float) -> void:
	_queue_since = since
	if _queue and is_instance_valid(_queue):
		return
	var col := Color(str(_boss.get("color", "#ffffff")))
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.size = root.size
	dim.color = Color(0, 0, 0, 0.78)
	root.add_child(dim)
	add_child(root)
	_queue = root
	var ring := Control.new()   # a radar sweep round the boss's face
	ring.position = Vector2(960, 420)
	root.add_child(ring)
	var ang := [0.0]
	ring.draw.connect(func():
		for k in 3:
			ring.draw_arc(Vector2.ZERO, 190.0 + k * 34.0, 0.0, TAU, 96, Color(col, 0.18 - k * 0.05), 2.0, true)
		ring.draw_arc(Vector2.ZERO, 200.0, ang[0], ang[0] + 1.2, 48, Color(col, 0.9), 6.0, true))
	var spinner := ring.create_tween().set_loops()
	spinner.tween_method(func(a: float):
		ang[0] = a
		ring.queue_redraw(), 0.0, TAU, 2.2)
	var face := UI.texture_rect(UI.card_crop(str(_boss.get("portrait", ""))), Vector2(300, 300), true)
	face.position = Vector2(810, 270)
	root.add_child(face)
	var h := UI.label("LOOKING FOR A PARTNER", 44, Color.WHITE, true)
	h.size = Vector2(1920, 60)
	h.position = Vector2(0, 660)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(h)
	var lv := _level_data()
	var what := UI.label("%s  ·  %s" % [str(_boss.get("name", "")).to_upper(), str(lv.get("name", "")).to_upper()], 24, col.lightened(0.3), true)
	what.size = Vector2(1920, 34)
	what.position = Vector2(0, 722)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(what)
	_queue_clock = UI.label("0:00", 40, UI.GOLD, true)
	_queue_clock.size = Vector2(1920, 50)
	_queue_clock.position = Vector2(0, 768)
	_queue_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_queue_clock)
	var hint := UI.label("Everyone online gets a pop-up to join you. A friend can also pick the same boss and level here.", 18, UI.MUTED)
	hint.size = Vector2(1920, 26)
	hint.position = Vector2(0, 830)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	var cancel := UI.button("STOP LOOKING", func():
		Net.send("coop:leave")
		_hide_queue(), Vector2(300, 64), UI.RED)
	cancel.position = Vector2(810, 890)
	root.add_child(cancel)
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.25)


func _hide_queue() -> void:
	_queue_sent = {}
	if _queue and is_instance_valid(_queue):
		var q := _queue
		var t := q.create_tween()
		t.tween_property(q, "modulate:a", 0.0, 0.2)
		t.tween_callback(q.queue_free)
	_queue = null
