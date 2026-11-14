extends Screen
## Contraband bundles. The client only names a bundle; the server owns price and amount and
## grants it once per verified payment. The server also says whether Contraband is on sale at all
## (not before the game is released): if not, the bundles are shown but can't be bought.

const BUNDLES := [
	{"id": "cb_500", "image": "contraband_4.99.png", "label": "500 CB · $4.99"},
	{"id": "cb_1200", "image": "contraband_9.99.png", "label": "1,200 CB · $9.99", "tag": "STARTER"},
	{"id": "cb_2500", "image": "contraband_19.99.png", "label": "2,500 CB · $19.99"},
	{"id": "cb_7000", "image": "contraband_49.99.png", "label": "7,000 CB · $49.99", "tag": "BEST VALUE"},
	{"id": "cb_15000", "image": "contraband_99.99.png", "label": "15,000 CB · $99.99"},
]

var _balance: Label
var _closed := ""   # why nothing can be bought (the server's words), "" while Contraband is on sale


func _ready() -> void:
	back_to = "shop"
	UI.background(self, "menu_background.jpg", 0.7)
	UI.title(self, "PURCHASE CONTRABAND", UI.PURPLE)
	_balance = UI.label("", 26, UI.PURPLE, true)
	_balance.size = Vector2(1920, 34)
	_balance.position = Vector2(0, 100)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_balance)
	_refresh()
	UI.back_button(self, func(): Game.go("shop"))
	if not needs_server("Purchasing"):
		return
	var slab := UI.glass(UI.panel(UI.PURPLE, Color(0, 0, 0, 0.9)), Color(0.04, 0.01, 0.06, 0.62))
	slab.position = Vector2(60, 300)
	slab.custom_minimum_size = Vector2(1800, 0)
	add_child(slab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	slab.add_child(row)
	for i in BUNDLES.size():
		var b: Dictionary = BUNDLES[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		row.add_child(col)
		var tag := UI.label(b.get("tag", " "), 22, UI.GOLD, true)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
		col.add_child(_bundle_art(b, i))
		var l := UI.label(b.label, 22, Color.WHITE, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		col.add_child(UI.button("PURCHASE", _purchase.bind(b), Vector2(330, 60), UI.PURPLE))
	UI.stagger(row.get_children(), 0.1, 0.07)
	var s := await Api.request("GET", "/api/shop/contraband")   # (an older server has no such page: on sale)
	if s.ok and s.data is Dictionary and s.data.get("open", true) == false:
		_close(row, str(s.data.get("message", "")))


## Not on sale (before the game is released): the bundles dimmed, every PURCHASE crossed out, and a
## sign that says so.
func _close(row: Control, why: String) -> void:
	_closed = why if why != "" else "Contraband goes on sale when the game is released."
	row.modulate = Color(0.62, 0.62, 0.7)
	for col in row.get_children():
		var b := col.get_child(col.get_child_count() - 1) as Button
		if b:
			UI.strike(b, _closed)
	var banner := UI.label("ON SALE WHEN THE GAME IS RELEASED", 36, UI.GOLD, true)
	banner.size = Vector2(1920, 48)
	banner.position = Vector2(0, 176)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner)
	var note := UI.label("Nothing can be bought yet. The Contraband you have still spends in the Shop.", 22, Color(0.86, 0.88, 0.96))
	note.size = Vector2(1920, 30)
	note.position = Vector2(0, 230)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(note)


## A bundle's picture: it floats gently (each on its own beat), and lifts and brightens under the
## mouse (buying stays on the button under it).
func _bundle_art(b: Dictionary, i: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(330, 330)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var art := UI.texture_rect(UI.tex(b.image), Vector2(330, 330))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.pivot_offset = Vector2(165, 165)
	holder.add_child(art)
	if not Game.photosafe():
		var bob := art.create_tween().set_loops()
		bob.tween_interval(i * 0.37)   # (out of step with the others)
		bob.tween_property(art, "position:y", -7.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(art, "position:y", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	holder.mouse_entered.connect(func():
		Sfx.play("hover", randf_range(0.96, 1.04), -6.0)
		var t := art.create_tween().set_parallel()
		t.tween_property(art, "scale", Vector2.ONE * 1.07, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(art, "modulate", Color(1.25, 1.15, 1.3), 0.14))
	holder.mouse_exited.connect(func():
		var t := art.create_tween().set_parallel()
		t.tween_property(art, "scale", Vector2.ONE, 0.16)
		t.tween_property(art, "modulate", Color.WHITE, 0.2))
	return holder


func _refresh(from := -1) -> void:
	var now := int(Game.player.get("contraband", 0))
	if from >= 0 and from != now:
		UI.count_up(_balance, from, now, 0.8, "BALANCE  %d CB", "click")
		_balance.pivot_offset = _balance.size / 2
		_balance.scale = Vector2.ONE * 1.12
		_balance.create_tween().tween_property(_balance, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_balance.text = "BALANCE  %d CB" % now


func _purchase(b: Dictionary) -> void:
	if _closed != "":
		UI.toast(self, _closed, UI.MUTED)
		return
	if Game.steam.active:
		_steam_purchase(b)
		return
	var r := await Api.request("POST", "/api/shop/contraband/purchase", {"bundleId": b.id})
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	var was := int(Game.player.get("contraband", 0))
	Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh(was)
	Sfx.play("promote")
	UI.toast(self, "+%d Contraband added!" % int(r.data.get("contrabandGranted", 0)), UI.PURPLE)


## The Steam build: Steam's wallet (backend/routes/steam.js). The server opens the order, Steam shows
## it in its overlay, and once the player approves it there the server completes it and adds the
## Contraband (once).
func _steam_purchase(b: Dictionary) -> void:
	if not Game.player.get("steam_linked", false):
		var why: String = await Game.link_steam()   # (buying through Steam needs the Steam account linked)
		if why != "":
			UI.toast(self, why, UI.RED)
			return
	var spin := UI.spinner(self, Vector2(960, 960), "OPENING STEAM…")
	var r := await Api.request("POST", "/api/steam/purchase/init", {"bundleId": b.id, "language": Game.steam.language()})
	if not r.ok:
		spin.queue_free()
		UI.toast(self, r.error, UI.RED)
		return
	var order := str(r.data.get("orderId", ""))
	spin.text = "APPROVE THE PURCHASE IN STEAM…"
	var answer := {"done": false, "ok": false}
	var on := func(order_id: String, authorized: bool):
		if order_id == order:
			answer.done = true
			answer.ok = authorized
	Game.steam.purchase_answered.connect(on)
	var give_up := Time.get_ticks_msec() + 10 * 60 * 1000
	while not answer.done and Time.get_ticks_msec() < give_up and is_inside_tree():
		await get_tree().process_frame
	Game.steam.purchase_answered.disconnect(on)
	if not is_inside_tree():
		return
	if not answer.ok:
		spin.queue_free()
		UI.toast(self, "Purchase cancelled: nothing was charged.", UI.MUTED)
		return
	spin.text = "ADDING YOUR CONTRABAND…"
	var f := await Api.request("POST", "/api/steam/purchase/finalize", {"orderId": order})
	spin.queue_free()
	if not f.ok:
		UI.toast(self, f.error, UI.RED)
		return
	var was := int(Game.player.get("contraband", 0))
	Game.player.contraband = f.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh(was)
	Sfx.play("promote")
	UI.toast(self, "+%d Contraband added!" % int(f.data.get("contrabandGranted", 0)), UI.PURPLE)
