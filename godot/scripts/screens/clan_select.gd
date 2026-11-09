extends Screen
## First login: pick a starting clan. The server seeds the starter inventory and deck.
## The clans come from the server (GET /api/onboarding/clans: every clan with a starter deck), so
## a new Card Forge clan appears here by itself. Art: assets/<clan>_deck.png, else its leader.

## Art and words for clans that have them; others use their leader's art and a plain line.
const KNOWN := {
}

var _selected := ""
var _tiles := {}
var _confirm: Button


func _ready() -> void:
	UI.background(self)
	UI.title(self, "CHOOSE YOUR CLAN")
	var sub := UI.label("Your starter inventory and deck depend on this choice.", 24, UI.MUTED)
	sub.size = Vector2(1920, 30)
	sub.position = Vector2(0, 100)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var r := await Api.request("GET", "/api/onboarding/clans")
	var clans: Array = r.data if r.ok and r.data is Array else []
	if clans.is_empty():
		var msg := UI.label(r.error if not r.ok else "No clans are ready yet. Try again later.", 26, UI.RED, true)
		msg.size = Vector2(1920, 40)
		msg.position = Vector2(0, 480)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(msg)
	# Centred rows (two once there are more than 4 clans); tiles get narrower the more there are
	var per_row := clans.size() if clans.size() <= 4 else ceili(clans.size() / 2.0)
	var two := clans.size() > 4
	var w := minf(600.0, 1820.0 / maxi(1, per_row) - 40.0)
	var gap := w + 40.0
	var h := 380.0 if two else 780.0   # (the rows end at 950, above CONFIRM)
	var art_h := 160.0 if two else 400.0
	for i in clans.size():
		var c := _clan_info(clans[i])
		var row := i / per_row
		var in_row := mini(per_row, clans.size() - row * per_row)   # (a shorter last row is centred too)
		var tile := Button.new()
		tile.toggle_mode = true
		tile.custom_minimum_size = Vector2(w, h)
		tile.position = Vector2(960 - in_row * gap / 2 + 20 + (i % per_row) * gap, 170 + row * (h + 20))
		add_child(tile)
		var art := UI.texture_rect(c.image, Vector2(w - 40, art_h))
		art.position = Vector2(20, 20)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(art)
		var bob := art.create_tween().set_loops()   # (the leader card floats, each on its own beat)
		bob.tween_interval(0.2 + i * 0.29)
		bob.tween_property(art, "position:y", 12.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(art, "position:y", 20.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var name := UI.label(c.label, int(minf(32.0 if two else 48.0, w / 6.0)), c.color, true)
		name.size = Vector2(w, 60)
		name.position = Vector2(0, art_h + (20 if two else 30))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(name)
		# The blurb fills the space between the name and the card count, smaller if it has to
		var top := art_h + (68 if two else 98)
		var bottom := h - (34 if two else 48)
		var blurb := UI.label(c.blurb, 17 if two else 22, Color(0.85, 0.85, 0.9))
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
		blurb.size = Vector2(w - 40, bottom - top - 8)
		blurb.position = Vector2(20, top)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.clip_text = true
		tile.add_child(blurb)
		_fit(blurb, 17 if two else 22, 12)
		var count := UI.label(c.count, 14 if two else 18, UI.MUTED)
		count.size = Vector2(w - 20, 28)
		count.position = Vector2(10, bottom)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.clip_text = true
		tile.add_child(count)
		# In its clan's colour: edged on hover, glowing once chosen
		var col: Color = c.color
		tile.add_theme_stylebox_override("normal", UI.box(Color(0.04, 0.04, 0.1, 0.82), Color(col, 0.35), 2, 14))
		tile.add_theme_stylebox_override("hover", UI._glow(UI.box(Color(col.darkened(0.8), 0.88), col, 3, 14), col, 0.9))
		tile.add_theme_stylebox_override("pressed", UI._glow(UI.box(Color(col.darkened(0.7), 0.92), col, 4, 14), col, 1.6))
		tile.add_theme_stylebox_override("hover_pressed", tile.get_theme_stylebox("pressed"))
		UI.juice(tile)
		tile.pressed.connect(_select.bind(c.id))
		_tiles[c.id] = tile
	# The tiles are dealt in, one after another
	var order: Array = _tiles.values()
	for i in order.size():
		var t: Button = order[i]
		var to := t.position
		t.position.y += 70.0
		t.modulate.a = 0.0
		var at := 0.08 + i * 0.07
		var deal := t.create_tween().set_parallel()
		deal.tween_property(t, "position:y", to.y, 0.45).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		deal.tween_property(t, "modulate:a", 1.0, 0.25).set_delay(at)
		deal.tween_callback(Sfx.play.bind("set", 1.0 + i * 0.06, -12.0)).set_delay(at)
	_confirm = UI.button("CONFIRM", _do_confirm, Vector2(360, 70), UI.GREEN)
	_confirm.position = Vector2(780, 975)
	_confirm.disabled = true
	add_child(_confirm)


## Label, colour, art and blurb for one clan from the server's list.
func _clan_info(c: Dictionary) -> Dictionary:
	var id := str(c.get("id", ""))
	var known: Dictionary = KNOWN.get(id, {})
	var image: Texture2D = UI.tex("%s_deck.png" % id)
	if image == null and known.has("image"):
		image = UI.tex(known.image)
	if image == null and str(c.get("leader", "")) != "":
		image = CardDB.art(str(c.leader))
	if image == null:
		image = CardDB.back(str(c.get("tag", "")))
	var blurb := str(c.blurb) if str(c.get("blurb", "")) != "" else str(known.get("blurb", ""))
	return {"id": id, "label": str(c.get("name", id)).to_upper(), "color": CardDB.clan_color(str(c.get("color", "#b388ff"))),
		"image": image, "blurb": blurb, "count": "%d cards · 40-card starter deck" % int(c.get("cards", 0))}


## Shrinks a wrapped label's font (from `size`, down to `smallest`) until its text fits its height.
## (UI.label sizes its text with LabelSettings, which wins over a theme override)
func _fit(l: Label, size: int, smallest: int) -> void:
	l.label_settings.font_size = size
	while size > smallest and l.get_visible_line_count() < l.get_line_count():
		size -= 1
		l.label_settings.font_size = size


func _select(id: String) -> void:
	_selected = id
	Sfx.play("promote", 1.2, -6.0)
	for k in _tiles:
		var t: Button = _tiles[k]
		t.set_pressed_no_signal(k == id)
		# The others step back; the chosen one pops
		t.create_tween().tween_property(t, "modulate", Color.WHITE if k == id else Color(0.55, 0.55, 0.62), 0.25)
		if k == id:
			var pop := t.create_tween()
			pop.tween_property(t, "scale", Vector2.ONE * 1.06, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pop.tween_property(t, "scale", Vector2.ONE * 1.03, 0.2)
	_confirm.disabled = false


func _do_confirm() -> void:
	_confirm.disabled = true
	_confirm.text = "SAVING…"
	var r := await Api.request("POST", "/api/onboarding/start-clan", {"clan": _selected})
	if not r.ok:
		_confirm.disabled = false
		_confirm.text = "CONFIRM"
		UI.toast(self, r.error, UI.RED)
		return
	Game.player.chosen_clan = _selected
	await _pick_avatar()
	Game.go("main_menu")


signal _avatar_done


## A new player picks their profile picture: any of the free ones (each clan's leader and starter
## characters), their own clan's first. SKIP keeps the default; it can be changed any time on the
## Achievements screen, where more unlock (levels, achievements, clan mastery).
func _pick_avatar() -> void:
	var r := await Api.request("GET", "/api/achievements")
	var keys: Array = []
	if r.ok and r.data is Dictionary and r.data.get("cosmetics") is Dictionary:
		keys = r.data.cosmetics.get("avatars", [])
	if keys.is_empty() or not is_inside_tree():
		return
	var mine: Array = []
	var rest: Array = []
	var seen := {}
	for k in keys:   # (each picture once)
		var src := UI.avatar_source(k)
		if seen.has(src):
			continue
		seen[src] = true
		var c := CardDB.get_card(src)
		(mine if str(c.get("clan", "")) == _selected or str(c.get("clanTag", "")) == _selected else rest).append(k)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.8)
	veil.size = Vector2(1920, 1080)
	add_child(veil)
	var p := UI.glass(UI.panel(UI.GOLD, Color(0.04, 0.04, 0.1, 0.96)), Color(0.02, 0.02, 0.06, 0.6))
	p.position = Vector2(230, 90)
	p.custom_minimum_size = Vector2(1460, 0)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	var title := UI.label("PICK YOUR PROFILE PICTURE", 44, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UI.label("Other players see it next to your name. More unlock as you play (levels, achievements, clan mastery): change it any time on the Achievements screen.", 20, UI.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.custom_minimum_size = Vector2(1400, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1420, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.custom_minimum_size = Vector2(1400, 0)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var busy := [false]
	for k in mine + rest:
		var key: String = str(k)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.25), 2, 10))
		frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pic := UI.texture_rect(UI.avatar(key), Vector2(150, 150), true)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(pic)
		frame.mouse_entered.connect(func(): frame.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.5), UI.GOLD, 3, 10)))
		frame.mouse_exited.connect(func(): frame.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.25), 2, 10)))
		frame.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not busy[0]:
				busy[0] = true
				Sfx.play("click")
				var put := await Api.request("PATCH", "/api/profile/me", {"avatarUrl": key})
				if put.ok:
					Game.player.avatar_url = key
				_avatar_done.emit())
		grid.add_child(frame)
	var skip_box := CenterContainer.new()
	skip_box.add_child(UI.button("SKIP FOR NOW", func(): _avatar_done.emit(), Vector2(300, 56)))
	col.add_child(skip_box)
	await _avatar_done
