extends Screen
## Contraband bundles. The client only names a bundle; the server owns price and amount and
## grants it once per verified payment.

const BUNDLES := [
	{"id": "cb_500", "image": "contraband_4.99.png", "label": "500 CB · $4.99"},
	{"id": "cb_1200", "image": "contraband_9.99.png", "label": "1,200 CB · $9.99", "tag": "STARTER"},
	{"id": "cb_2500", "image": "contraband_19.99.png", "label": "2,500 CB · $19.99"},
	{"id": "cb_7000", "image": "contraband_49.99.png", "label": "7,000 CB · $49.99", "tag": "BEST VALUE"},
	{"id": "cb_15000", "image": "contraband_99.99.png", "label": "15,000 CB · $99.99"},
]

var _balance: Label


func _ready() -> void:
	back_to = "shop"
	UI.background(self, "menu_background.png", 0.7)
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
	slab.position = Vector2(60, 200)
	slab.custom_minimum_size = Vector2(1800, 700)
	add_child(slab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	slab.add_child(row)
	for b in BUNDLES:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		row.add_child(col)
		var tag := UI.label(b.get("tag", " "), 22, UI.GOLD, true)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
		col.add_child(UI.texture_rect(UI.tex(b.image), Vector2(330, 450)))
		var l := UI.label(b.label, 22, Color.WHITE, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		col.add_child(UI.button("PURCHASE", _purchase.bind(b), Vector2(330, 60), UI.PURPLE))


func _refresh() -> void:
	_balance.text = "BALANCE  %d CB" % int(Game.player.get("contraband", 0))


func _purchase(b: Dictionary) -> void:
	if Game.steam.active:
		_steam_purchase(b)
		return
	var r := await Api.request("POST", "/api/shop/contraband/purchase", {"bundleId": b.id})
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh()
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
	Game.player.contraband = f.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh()
	Sfx.play("promote")
	UI.toast(self, "+%d Contraband added!" % int(f.data.get("contrabandGranted", 0)), UI.PURPLE)
