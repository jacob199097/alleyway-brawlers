extends Screen
## Card packs: buy with Karat, Contraband or a free pack (the server rolls the cards), then the
## pack opening (scripts/ui/pack_opening.gd), where the player can open another without leaving it.

## Known packs and their art. The server's list decides what's on sale: a new Card Forge clan
## shows up with its name, and art from assets/<id>_booster.png once that file exists.
const PACKS := []

var _balance: Label
var _free := 0                   # free packs from levelling up (any pack, the player's choice)
var _free_buttons: Array[Button] = []
var _busy := false
var _opening = null              # the pack opening (ui/pack_opening.gd), while it's up
var _art_rects := {}             # pack id -> where its art sits on the shelf (the opening starts there)
## The pack opening's synthesised sounds (sfx.gd), made ready while the shop is open
const PACK_SOUNDS := ["tear", "charge", "burst", "shimmer", "reveal_rare", "reveal_epic", "new_card"]


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
			packs.append(known.get(id, {"id": id, "label": str(info.get("name", sp.get("name", id))), "image": "%s_booster.png" % id,
				"color": info.get("color", Color("b388ff"))}))
	var step: float = minf(480.0, 1700.0 / maxi(1, packs.size()))
	for i in packs.size():
		_pack(packs[i], Vector2(760.0 - (packs.size() - 1) * step / 2.0 + i * step, 170))
	Sfx.warm(PACK_SOUNDS)


func _refresh_balance() -> void:
	_balance.text = "KARAT  %d     ·     CONTRABAND  %d" % [int(Game.player.get("karat", 0)), int(Game.player.get("contraband", 0))]
	if _free > 0:
		_balance.text += "     ·     FREE PACKS  %d" % _free
	for b in _free_buttons:
		b.visible = _free > 0
		b.text = "OPEN FREE  (%d LEFT)" % _free


func _pack(p: Dictionary, at: Vector2) -> void:
	var art := UI.texture_rect(UI.tex(p.image) if UI.tex(p.image) else CardDB.back(), Vector2(400, 543))
	art.position = at
	art.pivot_offset = art.size / 2
	_art_rects[p.id] = Rect2(at + Vector2(0, 5), Vector2(400, 533))
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(art)
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
	# A free pack from levelling up: any pack the player picks
	var free := UI.button("", _buy.bind(p, "free"), Vector2(384, 60), UI.GREEN)
	free.position = at + Vector2(8, 712)
	add_child(free)
	_free_buttons.append(free)
	_refresh_balance()


func _buy(p: Dictionary, currency: String) -> void:
	if _busy or _opening:
		return
	var data := await _purchase(p, currency, self)
	if data.is_empty() or not is_inside_tree():
		return
	_opening = load("res://scripts/ui/pack_opening.gd").open(self, p, data, currency, _art_rects.get(p.id, Rect2()))
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
