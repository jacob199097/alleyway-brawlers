extends Screen
## Card library: your collection (or every card in the game), with filters and a detail panel
## that follows the mouse. Right-click or click a card to zoom it.

const TILE := Vector2(150, 212)

var _owned: Dictionary = {}     # art_url -> inventory row
var _show_all := false
var _faction := "all"
var _kind := "all"
var _rarities := {}
var _grid: GridContainer
var _total: Label
var _detail: VBoxContainer
var _chips := {}


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.78)
	Game.play_menu_music()
	UI.title(self, "CARD LIBRARY")
	UI.back_button(self, func(): Game.go("main_menu"))
	_total = UI.label("", 22, UI.MUTED)
	_total.position = Vector2(1500, 46)
	add_child(_total)
	_build_filters()
	var p := UI.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.45))
	p.position = Vector2(20, 190)
	p.size = Vector2(1340, 790)
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var dp := UI.panel(UI.BLUE)
	dp.position = Vector2(1380, 190)
	dp.size = Vector2(520, 790)
	add_child(dp)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	dp.add_child(_detail)
	_show_detail({})
	if Game.offline:
		_show_all = true
	else:
		var spin := UI.spinner(self, Vector2(690, 580))
		var r := await Api.request("GET", "/api/profile/inventory")
		spin.queue_free()
		if r.ok:
			for row in r.data:
				_owned[str(row.get("art_url", ""))] = row
		else:
			UI.toast(self, r.error, UI.RED)
	_sync_chips()
	_render()


func _build_filters() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(20, 112)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	if not Game.offline:
		bar.add_child(_chip("show", "owned", "OWNED"))
		bar.add_child(_chip("show", "all", "ALL CARDS"))
		bar.add_child(_spacer())
	for f in [["all", "ALL CLANS"], ["lion", "LIONS"], ["viper", "VIPERS"]]:
		bar.add_child(_chip("faction", f[0], f[1]))
	bar.add_child(_spacer())
	for k in [["all", "ANY TYPE"], ["gang_member", "UNITS"], ["hustle", "HUSTLE"], ["ambush", "AMBUSH"], ["leader", "LEADER"]]:
		bar.add_child(_chip("kind", k[0], k[1]))
	bar.add_child(_spacer())
	for r in range(1, 6):
		var b := _chip("rarity", str(r), str(UI.RARITY_LABEL[r]).to_upper())
		b.add_theme_color_override("font_color", UI.RARITY_COLOR[r])
		bar.add_child(b)


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(14, 0)
	return c


func _chip(group: String, value: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func():
		Sfx.play("click")
		match group:
			"show":
				_show_all = value == "all"
			"faction":
				_faction = value
			"kind":
				_kind = value
			"rarity":
				if _rarities.has(int(value)):
					_rarities.erase(int(value))
				else:
					_rarities[int(value)] = true
		_sync_chips()
		_render())
	_chips["%s:%s" % [group, value]] = b
	return b


func _sync_chips() -> void:
	for key in _chips:
		var parts: PackedStringArray = key.split(":")
		var on := false
		match parts[0]:
			"show":
				on = _show_all == (parts[1] == "all")
			"faction":
				on = _faction == parts[1]
			"kind":
				on = _kind == parts[1]
			"rarity":
				on = _rarities.has(int(parts[1]))
		_chips[key].set_pressed_no_signal(on)


## Every card to show: catalog cards merged with the player's inventory row when owned.
func _entries() -> Array:
	var out: Array = []
	var seen := {}
	for id in CardDB.all():
		var c: Dictionary = CardDB.get_card(id).duplicate()
		var row = _owned.get(id)
		if row != null:
			for key in ["name", "rarity", "authority", "attack", "defense"]:
				if row.get(key) != null:
					c[key] = row[key]
			c.quantity = int(row.get("quantity", 0))
		seen[id] = true
		if _show_all or row != null:
			out.append(c)
	for id in _owned:   # owned cards the rules data doesn't know yet
		if not seen.has(id):
			var row: Dictionary = _owned[id]
			out.append({"id": id, "art_url": id, "name": row.name, "rarity": row.rarity, "cardType": row.card_type,
				"clanTag": row.get("clan_tag", ""), "effectText": row.get("effect_text", ""), "quantity": row.quantity})
	return out


func _render() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var shown := 0
	var entries := _entries()
	entries.sort_custom(_rarest_first)
	for c in entries:
		if _faction != "all" and str(c.get("clanTag", "")) != _faction:
			continue
		if _kind != "all" and str(c.get("cardType", "")) != _kind:
			continue
		if not _rarities.is_empty() and not _rarities.has(int(c.get("rarity", 1))):
			continue
		var tile := CardTile.make(c, TILE)
		var qty := int(c.get("quantity", 0))
		if qty > 1:
			tile.count_badge = "×%d" % qty
		tile.dimmed = not Game.offline and qty == 0
		tile.hovered.connect(func(t): _show_detail(t.card))
		tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		_grid.add_child(tile)
		shown += 1
	_total.text = "%d card%s" % [shown, "" if shown == 1 else "s"]
	if shown == 0:
		var l := UI.label("No cards match these filters", 28, UI.MUTED, true)
		_grid.add_child(l)


static func _rarest_first(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a.get("rarity", 1))
	var rb := int(b.get("rarity", 1))
	if ra != rb:
		return ra > rb
	return str(a.get("name", "")) < str(b.get("name", ""))


func _show_detail(c: Dictionary) -> void:
	for n in _detail.get_children():
		n.queue_free()
	if c.is_empty():
		_detail.add_child(UI.label("Hover a card to see it here.", 22, UI.MUTED))
		return
	_detail.add_child(UI.texture_rect(UI.card_art(c), Vector2(480, 520)))
	_detail.add_child(UI.label(str(c.get("name", "?")), 34, Color.WHITE, true))
	var rarity := int(c.get("rarity", 1))
	var kind := str(UI.TYPE_NAMES.get(c.get("cardType", ""), "CARD"))
	var sub = c.get("subtype")
	var line := "%s%s  ·  %s" % [kind, ("  ·  " + str(sub).to_upper()) if sub is String else "", str(UI.RARITY_LABEL.get(rarity, "")).to_upper()]
	_detail.add_child(UI.label(line, 17, UI.rarity_color(rarity)))
	if c.get("cardType") in ["gang_member", "leader"]:
		_detail.add_child(UI.label("ATK %d   DEF %d   ·   AUTHORITY %d" % [int(c.get("attack", 0)), int(c.get("defense", 0)), int(c.get("authority", 0))], 22, UI.GOLD, true))
	var t := UI.label(str(c.get("effectText", "")), 18, Color(0.88, 0.88, 0.95))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(480, 0)
	_detail.add_child(t)
	if not Game.offline:
		_detail.add_child(UI.label("Owned: %d" % int(c.get("quantity", 0)), 18, UI.BLUE, true))
