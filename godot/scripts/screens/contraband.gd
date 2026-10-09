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
	var slab := UI.panel(UI.PURPLE, Color(0, 0, 0, 0.9))
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
	var r := await Api.request("POST", "/api/shop/contraband/purchase", {"bundleId": b.id})
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	Game.player.contraband = r.data.get("newContraband", Game.player.get("contraband", 0))
	_refresh()
	Sfx.play("promote")
	UI.toast(self, "+%d Contraband added!" % int(r.data.get("contrabandGranted", 0)), UI.PURPLE)
