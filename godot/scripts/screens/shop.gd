extends Screen
## Card packs: buy with Karat, Contraband or a free pack (the server rolls the cards), then the
## pack opening (scripts/ui/pack_opening.gd), where the player can open another without leaving it.
## Starter decks: every clan's, under its deck box (POST /api/shop/starter adds the cards and the deck).
## Contracts: today's three (GET /api/contracts, backend/economy/contracts.js): pay Karat for a goal, do it in one
## of the next few matches and it pays out more; one at a time.

## Known packs and their art. The server's list decides what's on sale: a new Card Forge clan
## shows up with its name, and art from assets/<id>_booster.png once that file exists.
const PACKS := []

var _balance: Label
var _free := 0                   # free packs from levelling up (any pack, the player's choice)
var _free_buttons: Array[Button] = []
var _busy := false
var _opening = null              # the pack opening (ui/pack_opening.gd), while it's up
var _arts := {}                  # pack id -> its art on the shelf (the opening starts where it is)
## More packs than fit (one per clan): a carousel showing SHOWN at a time, scrolled with the arrows,
## the mouse wheel or the arrow keys
const SHOWN := 3
const STEP := 480.0
var _row: Control
var _first := 0
var _count := 0
var _dots: HBoxContainer
var _arrows: Array[Button] = []
var _title: Label
var _clip: Control
## Tabs: card packs or starter decks (GET /api/shop/starters)
var _tab := "packs"
var _tabs := {}
var _pack_list: Array = []
var _starter_list: Array = []
var _starter_cost := {}
var _contracts := {}             # GET /api/contracts: today's offers, the active one, seconds until new ones
var _contract_info: Label
## The pack opening's synthesised sounds (sfx.gd), made ready while the shop is open
const PACK_SOUNDS := ["tear", "charge", "burst", "shimmer", "reveal_rare", "reveal_epic", "new_card"]


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.jpg", 0.6)
	Game.play_menu_music()
	_title = UI.title(self, "CARD PACKS")
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
	var ah := UI.button("AUCTION HOUSE", func(): Game.go("auction_house"), Vector2(300, 60), UI.GOLD)   # (screens/auction_house.gd)
	ah.position = Vector2(1580, 26)
	add_child(ah)
	var packs: Array = PACKS.duplicate()
	var r := await Api.request("GET", "/api/shop/packs")
	if r.ok and r.data is Dictionary and r.data.get("contrabandOpen", true) == false:   # (not on sale before the game is released)
		UI.strike(cb, "Contraband goes on sale when the game is released")
		var soon := UI.label("ON SALE AT RELEASE", 16, UI.MUTED, true)
		soon.size = Vector2(380, 22)
		soon.position = Vector2(1500, 1055)
		soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(soon)
	if r.ok and r.data is Dictionary:
		_free = int(r.data.get("freePacks", 0))
		Game.player.free_packs = _free
		_refresh_balance()
	if r.ok and r.data is Dictionary and r.data.get("packs") is Array and not r.data.packs.is_empty():
		var known := {}
		for p in PACKS:
			known[p.id] = p
		packs = []
		for sp in r.data.packs:
			var id := str(sp.get("id", ""))
			var info := CardDB.clan(id)
			var entry: Dictionary = known.get(id, {"id": id, "label": str(info.get("name", sp.get("name", id))), "image": "%s_booster.png" % id,
				"color": info.get("color", Color("b388ff"))}).duplicate()
			entry.odds = sp.get("odds", {})
			packs.append(entry)
	_pack_list = packs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	tabs.position = Vector2(960 - 624, 990)   # (bottom centre: the back button is bottom left)
	add_child(tabs)
	for t in [["packs", "CARD PACKS"], ["starters", "STARTER DECKS"], ["contracts", "CONTRACTS"], ["animated", "ANIMATED"]]:
		var tb := UI.button(t[1], _show.bind(t[0]), Vector2(300, 64), UI.GOLD)
		tabs.add_child(tb)
		_tabs[t[0]] = tb
	_show("packs")
	Sfx.warm(PACK_SOUNDS)


## The shelf for a tab: card packs, or every clan's starter deck (its deck box)
func _show(tab: String) -> void:
	if _opening or _busy:
		return
	_tab = tab
	for k in _tabs:
		(_tabs[k] as Button).modulate = Color.WHITE if k == tab else Color(1, 1, 1, 0.5)
	if tab == "starters" and _starter_list.is_empty():
		var r := await Api.request("GET", "/api/shop/starters")
		if not is_inside_tree():
			return
		if not r.ok or not r.data is Dictionary:
			UI.toast(self, r.error if not r.ok else "Could not load the starter decks.", UI.RED)
			return
		_starter_cost = r.data.get("cost", {})
		_starter_list = r.data.get("starters", [])
		if _tab != tab:
			return
	if tab == "contracts":   # (fresh each time: what's been done or failed since)
		var r := await Api.request("GET", "/api/contracts")
		if not is_inside_tree():
			return
		if not r.ok or not r.data is Dictionary:
			UI.toast(self, r.error if not r.ok else "Could not load the contracts.", UI.RED)
			return
		_contracts = r.data
		Game.player.karat = int(r.data.get("karat", Game.player.get("karat", 0)))
		_refresh_balance()
		if _tab != tab:
			return
	if tab == "animated":   # (fresh: what's been bought or crafted since)
		await Game.load_animated()
		if not is_inside_tree() or _tab != tab:
			return
	_title.text = {"starters": "STARTER DECKS", "contracts": "CONTRACTS", "animated": "ANIMATED CARDS"}.get(tab, "CARD PACKS")
	_contract_note(tab == "contracts")
	if tab == "contracts":
		_fill(_contracts.get("offers", []), _contract)
	elif tab == "animated":   # today's featured ones (the server's rotation, new each day at midnight UTC)
		var offers: Array = Game.animated_offers.filter(func(o): return o is Dictionary and o.get("featured", false))
		offers.sort_custom(func(a, b): return int(a.get("owned", false)) < int(b.get("owned", false)) if a.get("owned", false) != b.get("owned", false) \
			else (int(a.rarity) > int(b.rarity) if int(a.rarity) != int(b.rarity) else str(CardDB.get_card(str(a.id)).get("name", "")) < str(CardDB.get_card(str(b.id)).get("name", ""))))
		_fill(offers, _animated_offer)
		if offers.is_empty():
			UI.toast(self, "No animated cards yet.", UI.MUTED)
	else:
		_fill(_starter_list if tab == "starters" else _pack_list, _starter if tab == "starters" else _pack)


## The carousel: entries laid out by maker (one Control each), SHOWN at a time.
func _fill(entries: Array, maker: Callable) -> void:
	for n in [_clip, _dots]:
		if n:
			n.queue_free()
	for n in _arrows:
		n.queue_free()
	_clip = null
	_dots = null
	_arrows.clear()
	_free_buttons.clear()
	_arts.clear()
	_first = 0
	_count = entries.size()
	var shown := mini(SHOWN, _count)
	var clip := Control.new()
	_clip = clip   # (packs scrolled out of view are cut off at its edges)
	clip.clip_contents = _count > SHOWN
	clip.size = Vector2(STEP * shown, 830)
	clip.position = Vector2(960 - clip.size.x / 2, 150)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_row)
	for i in _count:
		var holder: Control = maker.call(entries[i])
		holder.position = Vector2(i * STEP + 40, 20)
		_row.add_child(holder)
	if _count > SHOWN:
		for dir in [-1, 1]:
			var b := UI.button("◀" if dir < 0 else "▶", _scroll.bind(dir), Vector2(90, 130), UI.GOLD)
			b.position = Vector2(clip.position.x - 120 if dir < 0 else clip.position.x + clip.size.x + 30, 330)
			add_child(b)
			_arrows.append(b)
		_dots = HBoxContainer.new()
		_dots.add_theme_constant_override("separation", 10)
		_dots.position = Vector2(960 - _count * 13, 960)
		add_child(_dots)
		for i in _count:
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(16, 16)
			_dots.add_child(d)
		_scroll(0)


## Move the carousel by dir packs (0: just show where it is).
func _scroll(dir: int) -> void:
	var to := clampi(_first + dir, 0, maxi(0, _count - SHOWN))
	if dir != 0 and to == _first:
		return
	_first = to
	if dir != 0:
		Sfx.play("whoosh", 1.3, -10.0)
	_row.create_tween().tween_property(_row, "position:x", -_first * STEP, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arrows[0].disabled = _first == 0
	_arrows[1].disabled = _first >= _count - SHOWN
	for i in _dots.get_child_count():
		var on := i >= _first and i < _first + SHOWN
		(_dots.get_child(i) as ColorRect).color = UI.GOLD if on else Color(1, 1, 1, 0.25)


func _unhandled_input(e: InputEvent) -> void:
	if _count > SHOWN and not _opening:
		var dir := 0
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			dir = -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		elif e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_LEFT, KEY_RIGHT]:
			dir = -1 if e.keycode == KEY_LEFT else 1
		if dir != 0:
			_scroll(dir)
			get_viewport().set_input_as_handled()
			return
	super(e)   # (Esc: back)


func _refresh_balance() -> void:
	_balance.text = "KARAT  %d     ·     CONTRABAND  %d" % [int(Game.player.get("karat", 0)), int(Game.player.get("contraband", 0))]
	if _free > 0:
		_balance.text += "     ·     FREE PACKS  %d" % _free
	for b in _free_buttons:
		b.visible = _free > 0
		b.text = "OPEN FREE  (%d LEFT)" % _free


## One pack on the shelf (its art, name, prices and free-pack button), laid out from its top-left.
func _pack(p: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = Vector2(400, 790)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at := Vector2.ZERO
	var art := UI.texture_rect(UI.tex(p.image) if UI.tex(p.image) else CardDB.back(), Vector2(400, 543))
	art.position = at
	art.pivot_offset = art.size / 2
	_arts[p.id] = art
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(art)
	art.mouse_entered.connect(func():
		Sfx.play("hover", 0.9, -8.0)
		var h := create_tween().set_parallel()
		h.tween_property(art, "scale", Vector2.ONE * 1.06, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		h.tween_property(art, "modulate", Color(1.15, 1.15, 1.15), 0.14))
	art.mouse_exited.connect(func():
		var h := create_tween().set_parallel()
		h.tween_property(art, "scale", Vector2.ONE, 0.14)
		h.tween_property(art, "modulate", Color.WHITE, 0.14))
	# Packs float, each on its own beat
	var bob := art.create_tween().set_loops()
	var phase := randf_range(1.6, 2.2)
	bob.tween_property(art, "position:y", at.y - 8.0, phase).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(art, "position:y", at.y + 4.0, phase).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sway := art.create_tween().set_loops()
	sway.tween_property(art, "rotation", 0.015, phase * 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(art, "rotation", -0.015, phase * 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	holder.add_child(_text_band(at + Vector2(-6, 550), Vector2(412, 88), p.color))
	var name := UI.label(str(p.label).to_upper(), 30, p.color, true)
	name.size = Vector2(400, 40)
	name.position = at + Vector2(0, 555)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(name)
	var sub := UI.label("3 cards per pack", 16, UI.MUTED)
	var odds = p.get("odds")
	if odds is Dictionary and not odds.is_empty():   # (the server's own chances, so they're always true)
		sub.text = "3 cards  ·  a Rare or better in every pack\nEpic+ in %d%% of packs  ·  Legendary in %d%%" % [
			roundi(100.0 * float(odds.get("4", 0))), roundi(100.0 * float(odds.get("5", 0)))]
	sub.size = Vector2(400, 44)
	sub.position = at + Vector2(0, 588)
	if Game.mobile():   # (its two lines, a little bigger on a phone, still clear of the buttons)
		sub.label_settings.line_spacing = -5.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.position = at + Vector2(8, 646)
	row.add_child(UI.button("200 KARAT", _buy.bind(p, "karat"), Vector2(184, 60), UI.GOLD))
	row.add_child(UI.button("100 CB", _buy.bind(p, "contraband"), Vector2(184, 60), UI.PURPLE))
	holder.add_child(row)
	# A free pack from levelling up: any pack the player picks
	var free := UI.button("", _buy.bind(p, "free"), Vector2(384, 60), UI.GREEN)
	free.position = at + Vector2(8, 716)
	holder.add_child(free)
	_free_buttons.append(free)
	_refresh_balance()
	return holder


## A dark band behind text that sits on the shop's backdrop, so it reads whatever is behind it.
func _text_band(at: Vector2, band_size: Vector2, col: Color) -> Panel:
	var band := Panel.new()
	band.position = at
	band.size = band_size
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.08, 0.72), Color(col, 0.3), 1, 8))
	return band


## One clan's starter deck on the shelf: its deck box, what's in it and its prices.
func _starter(d: Dictionary) -> Control:
	var id := str(d.get("id", ""))
	var info := CardDB.clan(id)
	var col: Color = info.get("color", UI.GOLD)
	var holder := Control.new()
	holder.size = Vector2(400, 790)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UI.texture_rect(UI.tex("%s_deckbox.png" % id) if UI.tex("%s_deckbox.png" % id) else CardDB.back(id), Vector2(400, 400))
	box.position = Vector2(0, 90)
	box.pivot_offset = box.size / 2
	holder.add_child(box)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_entered.connect(func():
		Sfx.play("hover", 0.9, -8.0)
		box.create_tween().tween_property(box, "scale", Vector2.ONE * 1.06, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	box.mouse_exited.connect(func(): box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.14))
	var bob := box.create_tween().set_loops()
	var phase := randf_range(1.6, 2.2)
	bob.tween_property(box, "position:y", 82.0, phase).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(box, "position:y", 94.0, phase).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arts[id] = box
	holder.add_child(_text_band(Vector2(-6, 514), Vector2(412, 150 if str(d.get("blurb", "")) != "" else 98), col))
	var name := UI.label("%s STARTER" % str(d.get("name", info.get("name", id))).to_upper(), 30, col, true)
	name.size = Vector2(400, 40)
	name.position = Vector2(0, 520)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(name)
	var leader := CardDB.get_card(str(d.get("leader", "")))
	var sub := UI.label("A ready-to-play 40-card deck, its Hideout\nand %s" % ("its leader, %s" % leader.name if not leader.is_empty() else "its leader"), 16, UI.MUTED)
	sub.size = Vector2(400, 44)
	sub.position = Vector2(0, 562)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(sub)
	var blurb := UI.label(str(d.get("blurb", "")), 15, Color(1, 1, 1, 0.75))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.size = Vector2(380, 40)
	blurb.position = Vector2(10, 618)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(blurb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.position = Vector2(8, 690)
	row.add_child(UI.button("%d KARAT" % int(_starter_cost.get("karat", 800)), _buy_starter.bind(d, "karat"), Vector2(184, 60), UI.GOLD))
	row.add_child(UI.button("%d CB" % int(_starter_cost.get("contraband", 400)), _buy_starter.bind(d, "contraband"), Vector2(184, 60), UI.PURPLE))
	holder.add_child(row)
	return holder


## A card's animated version (backend/economy/animated.js): the card moving, its name, and BUY for Contraband
## (it comes with a copy of the card if you have none), or OWNED.
func _animated_offer(o: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = Vector2(400, 790)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var id := str(o.get("id", ""))
	var c := CardDB.get_card(id)
	var owned: bool = o.get("owned", false)
	var art := UI.texture_rect(CardDB.art(id), Vector2(340, 482))
	art.position = Vector2(30, 30)
	art.pivot_offset = art.size / 2
	art.material = UI.card_material(art.size, int(o.get("rarity", 1)), c)   # (always moving here: it's what's for sale)
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	art.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var zc := c.duplicate()
			zc.anim = true
			UI.card_zoom(self, zc))
	art.mouse_entered.connect(func():
		Sfx.play("hover", 0.9, -8.0)
		art.create_tween().tween_property(art, "scale", Vector2.ONE * 1.04, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	art.mouse_exited.connect(func(): art.create_tween().tween_property(art, "scale", Vector2.ONE, 0.14))
	holder.add_child(art)
	var col := UI.rarity_color(o.get("rarity"))
	var name := UI.label(str(c.get("name", id)).to_upper(), 26, col, true)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(400, 0)
	name.size = Vector2(400, 36)
	name.position = Vector2(0, 530)
	holder.add_child(name)
	var sub := UI.label("✦ ANIMATED  ·  %s" % str(UI.RARITY_LABEL.get(int(o.get("rarity", 1)), "")).to_upper(), 16, UI.MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(400, 24)
	sub.position = Vector2(0, 574)
	holder.add_child(sub)
	var note := UI.label("or craft it in the Card Library for %d Dust" % int(o.get("dust", 0)), 15, Color(1, 1, 1, 0.6))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(400, 22)
	note.position = Vector2(0, 604)
	holder.add_child(note)
	var b := UI.button("OWNED  ✓" if owned else "BUY  ·  %d CB" % int(o.get("contraband", 0)), _buy_animated.bind(o), Vector2(340, 64), UI.GREEN if owned else UI.PURPLE)
	b.position = Vector2(30, 650)
	b.disabled = owned
	holder.add_child(b)
	return holder


func _buy_animated(o: Dictionary) -> void:
	if _busy:
		return
	var id := str(o.get("id", ""))
	var name := str(CardDB.get_card(id).get("name", id))
	UI.dialog(self, "BUY THE ANIMATED VERSION?", "Buy the animated %s for %d Contraband? Every copy of it moves, in your collection and in your matches (your opponents see it too). If you don't have the card yet, a copy comes with it." % [
		name, int(o.get("contraband", 0))],
		[["BUY IT", func():
			_busy = true
			var r := await Api.request("POST", "/api/animated/buy", {"card": id})
			_busy = false
			if not is_inside_tree():
				return
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				return
			Game.player.contraband = int(r.data.get("contraband", Game.player.get("contraband", 0)))
			Game.animated[id] = true
			_refresh_balance()
			Sfx.play("karat")
			UI.toast(self, "The animated %s is yours." % name + (" A copy of the card came with it." if r.data.get("gaveCard", false) else ""), UI.GREEN)
			if _tab == "animated":
				_show("animated"), UI.PURPLE],
		["CANCEL", func(): pass]], UI.PURPLE)



## One of today's contracts: what it asks, what it pays and costs, and TAKE IT (or what became of it today).
func _contract(o: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = Vector2(400, 700)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var active = _contracts.get("active")
	var bought := str(o.get("bought", "")) if o.get("bought") is String else ""
	var col: Color = UI.GREEN if bought == "done" else UI.RED if bought == "failed" else UI.GOLD
	var paper := Panel.new()
	paper.size = Vector2(400, 640)
	paper.position = Vector2(0, 30)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.045, 0.07, 0.9), Color(col, 0.8 if bought == "active" else 0.4), 2, 12))
	holder.add_child(paper)
	var rows := [
		[UI.label("📜", 64, col), 30, 90],
		[UI.label("CONTRACT", 22, col, true), 130, 30],
		[UI.label(str(o.get("text", "")), 30, Color.WHITE, true), 175, 150],
		[UI.label("ONLY IN A MATCH YOU WIN" if o.get("win", false) else "WIN OR LOSE", 15, UI.MUTED, true), 330, 22],
		[UI.label("PAYS %d KARAT" % int(o.get("payout", 0)), 34, UI.GOLD, true), 380, 44],
		[UI.label("COSTS %d KARAT  ·  LASTS %d MATCHES" % [int(o.get("price", 0)), int(o.get("matches", 3))], 17, UI.MUTED), 430, 26],
	]
	for r in rows:
		var l: Label = r[0]
		# (wrap first, then the width: a Label sized before it wraps grows to fit its text on one line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(360, 0)
		l.size = Vector2(360, r[2])
		l.position = Vector2(20, r[1])
		paper.add_child(l)
	var text := "TAKE IT  ·  %d KARAT" % int(o.get("price", 0))
	if bought == "active":
		var left := int(active.get("matches_left", 0)) if active is Dictionary else 0
		text = "YOURS: %d MATCH%s LEFT" % [left, "" if left == 1 else "ES"]
	elif bought == "done":
		text = "DONE ✓  PAID"
	elif bought == "failed":
		text = "FAILED"
	elif active is Dictionary:
		text = "FINISH YOUR CONTRACT FIRST"
	var b := UI.button(text, _buy_contract.bind(o), Vector2(360, 64), col)
	b.position = Vector2(20, 548)
	b.disabled = bought != "" or active is Dictionary
	paper.add_child(b)
	return holder


func _buy_contract(o: Dictionary) -> void:
	if _busy:
		return
	UI.dialog(self, "TAKE THIS CONTRACT?", "Pay %d Karat. %s%s in one of your next %d matches (Casual, Ranked, or the CPU on Normal or Hard) and it pays %d Karat. If you don't, the Karat is gone." % [
		int(o.get("price", 0)), str(o.get("text", "")), " (and win)" if o.get("win", false) else "", int(o.get("matches", 3)), int(o.get("payout", 0))],
		[["TAKE IT", func():
			_busy = true
			var r := await Api.request("POST", "/api/contracts/buy", {"index": int(o.get("index", 0))})
			_busy = false
			if not is_inside_tree():
				return
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				return
			_contracts = r.data
			Game.player.karat = int(r.data.get("karat", Game.player.get("karat", 0)))
			_refresh_balance()
			Sfx.play("karat")
			if _tab == "contracts":
				_contract_note(true)
				_fill(_contracts.get("offers", []), _contract)
			UI.toast(self, "Contract taken. It shows at the start of your next match.", UI.GREEN), UI.GOLD],
		["CANCEL", func(): pass]])


## Under the contracts: how they work, and when new ones arrive.
func _contract_note(on: bool) -> void:
	if _contract_info == null:
		_contract_info = UI.label("", 18, UI.MUTED)
		_contract_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_contract_info.size = Vector2(1500, 64)
		_contract_info.position = Vector2(210, 910)
		_contract_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_contract_info)
	_contract_info.visible = on or _tab == "animated"
	if _tab == "animated":
		var secs := int(Game.get("animated_resets_in")) if Game.get("animated_resets_in") != null else 0
		_contract_info.text = "Every card has an animated version. These are in the shop today; any of them can be crafted for Dust in the Card Library.\nNEW ONES IN %dH %02dM" % [secs / 3600, (secs % 3600) / 60]
		return
	if not on:
		return
	var secs := int(_contracts.get("resetsIn", 0))
	_contract_info.text = "Do it in one of your next matches (Casual, Ranked, or the CPU on Normal or Hard) and it pays out. Don't, and the Karat is gone. One at a time.\nNEW CONTRACTS IN %dH %02dM" % [secs / 3600, (secs % 3600) / 60]


func _buy_starter(d: Dictionary, currency: String) -> void:
	if _busy:
		return
	var cost := int(_starter_cost.get(currency, 0))
	var what := "%s Starter" % str(d.get("name", ""))
	UI.dialog(self, "BUY THE %s?" % what.to_upper(), "%d %s for its 40 cards, Hideout and leader. The deck is added to your Deck Builder, ready to play." % [
		cost, "Karat" if currency == "karat" else "Contraband"], [["BUY", func():
			_busy = true
			var r := await Api.request("POST", "/api/shop/starter", {"clan": str(d.get("id", "")), "currency": currency})
			_busy = false
			if not is_inside_tree():
				return
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				return
			Game.player.karat = r.data.get("newKarat", Game.player.get("karat", 0))
			Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
			_refresh_balance()
			Sfx.play("reveal_epic")
			var box: Control = _arts.get(str(d.get("id", "")))
			if box:
				var t := box.create_tween()
				t.tween_property(box, "scale", Vector2.ONE * 1.25, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t.tween_property(box, "scale", Vector2.ONE, 0.25)
			UI.toast(self, "Added \"%s\" and its cards. Find it in the Deck Builder." % str(r.data.get("deckName", what)), UI.GREEN), UI.GOLD],
		["CANCEL", func(): pass]])


func _buy(p: Dictionary, currency: String) -> void:
	if _busy or _opening:
		return
	var data := await _purchase(p, currency, self)
	if data.is_empty() or not is_inside_tree():
		return
	var art: Control = _arts.get(p.id)
	var from := Rect2(art.global_position + Vector2(0, 5), Vector2(400, 533)) if art else Rect2()
	_opening = load("res://scripts/ui/pack_opening.gd").open(self, p, data, currency, from)
	_opening.another.connect(func(cur: String):
		var next := await _purchase(p, cur, _opening)
		if _opening:
			if next.is_empty():
				_opening.buy_failed()
			else:
				_opening.next_pack(next))
	_opening.tree_exited.connect(func(): _opening = null)


## Buys a pack on the server, which opens it. Returns the reply (the cards, new balances), or {}
## after telling the player why not.
func _purchase(p: Dictionary, currency: String, toast_on: Control) -> Dictionary:
	_busy = true
	var r := await Api.request("POST", "/api/shop/open", {"packType": p.id, "currency": currency})
	_busy = false
	if not r.ok:
		UI.toast(toast_on, r.error, UI.RED)
		return {}
	Game.player.karat = r.data.get("newKarat", Game.player.get("karat", 0))
	Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
	if r.data.get("freePacks") != null:
		_free = int(r.data.freePacks)
		Game.player.free_packs = _free
	_refresh_balance()
	return r.data
