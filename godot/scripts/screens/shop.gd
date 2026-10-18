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
	_count = packs.size()
	var shown := mini(SHOWN, _count)
	var clip := Control.new()   # (packs scrolled out of view are cut off at its edges)
	clip.clip_contents = _count > SHOWN
	clip.size = Vector2(STEP * shown, 830)
	clip.position = Vector2(960 - clip.size.x / 2, 150)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_row)
	for i in _count:
		var holder := _pack(packs[i])
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
	Sfx.warm(PACK_SOUNDS)


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
	var name := UI.label(str(p.label).to_upper(), 30, p.color, true)
	name.size = Vector2(400, 40)
	name.position = at + Vector2(0, 555)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(name)
	var sub := UI.label("3 cards per pack", 18, UI.MUTED)
	sub.size = Vector2(400, 24)
	sub.position = at + Vector2(0, 596)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.position = at + Vector2(8, 640)
	row.add_child(UI.button("200 KARAT", _buy.bind(p, "karat"), Vector2(184, 60), UI.GOLD))
	row.add_child(UI.button("100 CB", _buy.bind(p, "contraband"), Vector2(184, 60), UI.PURPLE))
	holder.add_child(row)
	# A free pack from levelling up: any pack the player picks
	var free := UI.button("", _buy.bind(p, "free"), Vector2(384, 60), UI.GREEN)
	free.position = at + Vector2(8, 712)
	holder.add_child(free)
	_free_buttons.append(free)
	_refresh_balance()
	return holder


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
