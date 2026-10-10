extends Screen
## Card packs: buy with Karat or Contraband (the server rolls the cards), then a pack-opening
## reveal where higher rarities get more suspense.

## Known packs and their art. The server's list decides what's on sale: a new Card Forge clan
## shows up with its name, and art from assets/<id>_booster.png once that file exists.
const PACKS := [
	{"id": "lion_pride", "label": "Lion Clan", "image": "Lion_booster.png", "color": Color("ffd166")},
]

var _balance: Label
var _busy := false
var _reveal: Control


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.6)
	Game.play_menu_music()
	UI.title(self, "CARD PACKS")
	_balance = UI.label("", 26, UI.GOLD, true)
	_balance.size = Vector2(1920, 34)
	_balance.position = Vector2(0, 100)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_balance)
	_refresh_balance()
	UI.back_button(self, func(): Game.go("main_menu"))
	if not needs_server("The shop"):
		return
	var cb := UI.button("PURCHASE CONTRABAND", func(): Game.go("contraband"), Vector2(380, 64), UI.PURPLE)
	cb.position = Vector2(1500, 990)
	add_child(cb)
	var packs: Array = PACKS.duplicate()
	var r := await Api.request("GET", "/api/shop/packs")
	if r.ok and r.data is Dictionary and r.data.get("packs") is Array and not r.data.packs.is_empty():
		var known := {}
		for p in PACKS:
			known[p.id] = p
		packs = []
		for sp in r.data.packs:
			var id := str(sp.get("id", ""))
			packs.append(known.get(id, {"id": id, "label": str(sp.get("name", id)), "image": "%s_booster.png" % id,
				"color": Color("b388ff")}))
	var step: float = minf(480.0, 1700.0 / maxi(1, packs.size()))
	for i in packs.size():
		_pack(packs[i], Vector2(760.0 - (packs.size() - 1) * step / 2.0 + i * step, 170))


func _refresh_balance() -> void:
	_balance.text = "KARAT  %d     ·     CONTRABAND  %d" % [int(Game.player.get("karat", 0)), int(Game.player.get("contraband", 0))]


func _pack(p: Dictionary, at: Vector2) -> void:
	var art := UI.texture_rect(UI.tex(p.image) if UI.tex(p.image) else CardDB.back(), Vector2(400, 543))
	art.position = at
	art.pivot_offset = art.size / 2
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(art)
	art.mouse_entered.connect(func(): create_tween().tween_property(art, "scale", Vector2.ONE * 1.04, 0.12))
	art.mouse_exited.connect(func(): create_tween().tween_property(art, "scale", Vector2.ONE, 0.12))
	var name := UI.label(str(p.label).to_upper(), 30, p.color, true)
	name.size = Vector2(400, 40)
	name.position = at + Vector2(0, 555)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name)
	var sub := UI.label("3 cards per pack", 18, UI.MUTED)
	sub.size = Vector2(400, 24)
	sub.position = at + Vector2(0, 596)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.position = at + Vector2(8, 640)
	row.add_child(UI.button("200 KARAT", _buy.bind(p, "karat"), Vector2(184, 60), UI.GOLD))
	row.add_child(UI.button("100 CB", _buy.bind(p, "contraband"), Vector2(184, 60), UI.PURPLE))
	add_child(row)


func _buy(p: Dictionary, currency: String) -> void:
	if _busy:
		return
	_busy = true
	var r := await Api.request("POST", "/api/shop/open", {"packType": p.id, "currency": currency})
	_busy = false
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	Game.player.karat = r.data.get("newKarat", Game.player.get("karat", 0))
	Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh_balance()
	_open_pack(p, r.data.get("cardsReceived", []))


# ── Pack opening ─────────────────────────────────────────────────────────────

func _open_pack(p: Dictionary, cards: Array) -> void:
	_reveal = Control.new()
	_reveal.size = size
	add_child(_reveal)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0)
	veil.size = size
	_reveal.add_child(veil)
	create_tween().tween_property(veil, "color:a", 0.85, 0.25)
	var title := UI.label("OPENING — %s" % str(p.label).to_upper(), 44, UI.GOLD, true)
	title.size = Vector2(1920, 60)
	title.position = Vector2(0, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal.add_child(title)

	# Pack slides up, shakes, and tears open
	var pack := UI.texture_rect(UI.tex(p.image), Vector2(340, 462))
	pack.position = Vector2(790, 1200)
	pack.pivot_offset = pack.size / 2
	_reveal.add_child(pack)
	Sfx.play("whoosh", 0.8)
	var t := create_tween()
	t.tween_property(pack, "position:y", 300.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 6:
		t.tween_property(pack, "rotation", 0.06 * (1 if i % 2 == 0 else -1), 0.05)
	t.tween_property(pack, "rotation", 0.0, 0.05)
	await t.finished
	Sfx.play("ko", 1.3)
	_flash(Color.WHITE, 0.7)
	_rays(Vector2(960, 530))
	var tear := create_tween().set_parallel()
	tear.tween_property(pack, "position:y", 120.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tear.tween_property(pack, "modulate:a", 0.0, 0.34)
	await get_tree().create_timer(0.36).timeout

	# Cards flip one by one, commons first, the best last
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("rarity", 1)) < int(b.get("rarity", 1)))
	var gap := minf(400.0, 1700.0 / maxf(1, sorted.size()))
	var start_x := 960.0 - (sorted.size() - 1) * gap / 2.0
	for i in sorted.size():
		await _flip_card(sorted[i], Vector2(start_x + i * gap, 520))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.position = Vector2(580, 960)
	row.add_child(UI.button("CONTINUE", func(): _reveal.queue_free(), Vector2(360, 66)))
	row.add_child(UI.button("GO TO DECK EDITOR", func(): Game.go("deck_builder"), Vector2(360, 66), UI.PURPLE))
	_reveal.add_child(row)


func _flip_card(c: Dictionary, center: Vector2) -> void:
	var rarity := int(c.get("rarity", 1))
	var col := UI.rarity_color(rarity)
	var size_ := Vector2(300, 424)
	var glow := ColorRect.new()
	glow.color = Color(col, 0.0)
	glow.size = size_ + Vector2(24, 24)
	glow.position = center - glow.size / 2
	_reveal.add_child(glow)
	var holder := Control.new()
	holder.size = size_
	holder.position = center - size_ / 2 + Vector2(0, -260)
	holder.pivot_offset = size_ / 2
	holder.modulate.a = 0.0
	_reveal.add_child(holder)
	var back := UI.texture_rect(CardDB.back(), size_)
	var mat := UI.card_material(size_)
	back.material = mat
	holder.add_child(back)
	var turn := func(deg: float): mat.set_shader_parameter("y_rot", deg)
	Sfx.play("draw")
	var t := create_tween().set_parallel()
	t.tween_property(holder, "position:y", center.y - size_.y / 2, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "modulate:a", 1.0, 0.2)
	t.tween_property(glow, "color:a", 0.6 if rarity >= 5 else 0.4 if rarity >= 4 else 0.25, 0.3)
	await t.finished
	# Suspense: a light beam behind the card, longer and brighter for rarer cards
	var beam := ColorRect.new()
	beam.color = Color(col, 0.0)
	beam.size = Vector2(60 if rarity >= 5 else 36 if rarity >= 4 else 16, 1080)
	beam.position = Vector2(center.x - beam.size.x / 2, 0)
	_reveal.add_child(beam)
	_reveal.move_child(beam, glow.get_index())
	var hold := 0.9 if rarity >= 5 else 0.45 if rarity >= 4 else 0.1
	var bt := create_tween()
	bt.tween_property(beam, "color:a", 0.85 if rarity >= 5 else 0.55 if rarity >= 4 else 0.3, 0.2)
	bt.tween_interval(hold)
	bt.tween_property(beam, "color:a", 0.0, 0.25)
	bt.tween_callback(beam.queue_free)
	if rarity >= 4:
		Sfx.play("ambush" if rarity >= 5 else "effect", 1.0)
	await get_tree().create_timer(hold).timeout
	if rarity >= 5:
		# Fake-out: almost flips, snaps back, then commits
		var f := create_tween()
		f.tween_method(turn, 0.0, 55.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		f.tween_method(turn, 55.0, -10.0, 0.16).set_trans(Tween.TRANS_BACK)
		f.tween_method(turn, -10.0, 0.0, 0.1)
		await f.finished
		await get_tree().create_timer(0.18).timeout
	var flip := create_tween()
	flip.tween_method(turn, 0.0, 90.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flip.tween_callback(func():
		back.texture = UI.card_art(c) if UI.card_art(c) else CardDB.back()
		mat.set_shader_parameter("foil", 1.0 if rarity >= 4 else 0.0))
	flip.tween_method(turn, -90.0, 0.0, 0.22 if rarity >= 4 else 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await flip.finished
	Sfx.play("promote" if rarity >= 3 else "flip", 1.0 + 0.1 * rarity)
	if rarity >= 3:
		_flash(col, 0.25 + 0.05 * rarity)
	var tile := CardTile.make(c, size_)
	tile.position = holder.position
	_reveal.add_child(tile)
	holder.queue_free()
	tile.pressed.connect(func(tl): UI.card_zoom(self, tl.card))
	tile.zoomed.connect(func(tl): UI.card_zoom(self, tl.card))
	var name := UI.label(str(c.get("name", "?")), 24, col, true)
	name.size = Vector2(360, 30)
	name.position = Vector2(center.x - 180, center.y + size_.y / 2 + 10)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal.add_child(name)
	var rl := UI.label(str(UI.RARITY_LABEL.get(rarity, "Common")).to_upper(), 18, col)
	rl.size = Vector2(360, 24)
	rl.position = name.position + Vector2(0, 34)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal.add_child(rl)
	await get_tree().create_timer(0.25).timeout


func _flash(color: Color, alpha: float) -> void:
	var r := ColorRect.new()
	r.color = Color(color, alpha)
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.0, 0.35)
	t.tween_callback(r.queue_free)


func _rays(center: Vector2) -> void:
	var colors := [UI.GOLD, Color("ff9800"), Color.WHITE]
	for i in 14:
		var ray := ColorRect.new()
		ray.color = colors[i % colors.size()]
		ray.size = Vector2(randf_range(160, 260), randf_range(6, 12))
		ray.pivot_offset = Vector2(0, ray.size.y / 2)
		ray.position = center - Vector2(0, ray.size.y / 2)
		ray.rotation = TAU * i / 14.0
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reveal.add_child(ray)
		var t := create_tween().set_parallel()
		t.tween_property(ray, "scale:x", 2.2, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(ray, "modulate:a", 0.0, 0.4)
		t.chain().tween_callback(ray.queue_free)
