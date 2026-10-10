extends Screen

## Card library: your collection (or every card in the game), with filters and a detail panel
## that follows the mouse. Right-click a card to zoom it; click it to pick it for crafting
## (the bar along the bottom): scrap it into Dust, or craft it from Dust (backend/routes/craft.js).

const Keywords := preload("res://scripts/keywords.gd")

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
var _craft: Dictionary = {}     # GET /api/craft: dust, values per rarity, extras
var _pick: Dictionary = {}      # the card picked for crafting
var _tiles := {}                # card id -> its tile
var _bar: HBoxContainer


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
		_build_craft_bar()
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
	bar.add_child(_chip("faction", "all", "ALL CLANS"))
	for c in CardDB.clans():
		bar.add_child(_chip("faction", c.id, str(c.name).to_upper()))
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
	_tiles.clear()
	var shown := 0
	var entries := _entries()
	entries.sort_custom(_rarest_first)
	for c in entries:
		if _faction != "all" and str(c.get("clan", "")) != _faction:
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
		tile.selected = not _pick.is_empty() and str(_pick.get("id", "")) == str(c.get("id", ""))
		_tiles[str(c.get("id", ""))] = tile
		tile.hovered.connect(func(t): _show_detail(t.card))
		tile.pressed.connect(func(t):
			if Game.offline:
				UI.card_zoom(self, t.card)
			else:
				_select(t.card))
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
	# Keywords are coloured and explain themselves when hovered
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.meta_underlined = false
	t.add_theme_font_size_override("normal_font_size", 18)
	t.add_theme_font_size_override("bold_font_size", 18)
	t.add_theme_color_override("default_color", Color(0.88, 0.88, 0.95))
	t.text = Keywords.markup(str(c.get("effectText", "")))
	t.custom_minimum_size = Vector2(480, 0)
	t.meta_hover_started.connect(func(meta): t.tooltip_text = Keywords.LIST.get(str(meta), [null, ""])[1])
	t.meta_hover_ended.connect(func(_meta): t.tooltip_text = "")
	_detail.add_child(t)
	if not Game.offline:
		_detail.add_child(UI.label("Owned: %d" % int(c.get("quantity", 0)), 18, UI.BLUE, true))


# ── Crafting ─────────────────────────────────────────────────────────────────

func _build_craft_bar() -> void:
	var p := UI.panel(UI.PURPLE, Color(0.06, 0.03, 0.09, 0.94))
	p.position = Vector2(250, 992)
	p.size = Vector2(1650, 76)
	add_child(p)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 16)
	p.add_child(_bar)
	var r := await Api.request("GET", "/api/craft")
	if r.ok and r.data is Dictionary:
		_craft = r.data
	_render_bar()


## Dust, the picked card with its scrap and craft buttons, and "scrap extras".
func _render_bar() -> void:
	if _bar == null:
		return
	for c in _bar.get_children():
		c.queue_free()
	var dust := UI.label("✦ %d DUST" % int(_craft.get("dust", 0)), 26, UI.PURPLE, true)
	dust.custom_minimum_size = Vector2(230, 0)
	dust.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dust.tooltip_text = "Scrap cards to make Dust, then spend it crafting the cards you're missing."
	dust.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.add_child(dust)
	var info := UI.label("", 21, Color(0.9, 0.9, 1.0), true)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_child(info)
	if _pick.is_empty():
		info.text = "Click a card to scrap or craft it"
		info.add_theme_color_override("font_color", UI.MUTED)
	else:
		var have := _have(_pick)
		var cap := _cap(_pick)
		var v := _values(_pick)
		info.text = "%s  ·  %s  ·  OWNED %d / %d" % [str(_pick.get("name", "?")).to_upper(),
			str(UI.RARITY_LABEL.get(int(_pick.get("rarity", 1)), "")).to_upper(), have, cap]
		info.add_theme_color_override("font_color", UI.rarity_color(_pick.get("rarity")))
		var scrap := UI.button("SCRAP  +%d" % int(v.get("scrap", 0)), _scrap, Vector2(200, 56), UI.RED)
		scrap.disabled = have <= 0
		scrap.tooltip_text = "Turn one copy into Dust." if have > 0 else "You don't own this card."
		_bar.add_child(scrap)
		var make := UI.button("CRAFT  −%d" % int(v.get("craft", 0)), _make, Vector2(200, 56), UI.GREEN)
		make.disabled = have >= cap or int(_craft.get("dust", 0)) < int(v.get("craft", 0))
		make.tooltip_text = "You have all a deck can use." if have >= cap else ("Not enough Dust." if make.disabled else "Make a copy from Dust.")
		_bar.add_child(make)
	var extras := int(_craft.get("extras", 0))
	var all := UI.button("SCRAP EXTRAS  +%d" % int(_craft.get("extrasDust", 0)), _scrap_extras, Vector2(290, 56), UI.PURPLE)
	all.disabled = extras <= 0
	all.tooltip_text = "Scrap every copy beyond what a deck can hold (3 of a card, 1 leader): %d card%s." % [extras, "" if extras == 1 else "s"] \
		if extras > 0 else "No extra copies: you have 3 or fewer of every card."
	_bar.add_child(all)


func _select(c: Dictionary) -> void:
	Sfx.play("click")
	_pick = c
	for id in _tiles:
		if is_instance_valid(_tiles[id]):
			_tiles[id].selected = id == str(c.get("id", ""))
	_show_detail(c)
	_render_bar()


func _have(c: Dictionary) -> int:
	var row = _owned.get(str(c.get("id", "")))
	return int(row.get("quantity", 0)) if row is Dictionary else 0


static func _cap(c: Dictionary) -> int:
	return 1 if str(c.get("cardType", "")) == "leader" else 3


func _values(c: Dictionary) -> Dictionary:
	var all: Dictionary = _craft.get("values", {})
	var v = all.get(str(int(c.get("rarity", 1))))
	return v if v is Dictionary else {}


func _scrap() -> void:
	var c := _pick
	var v := _values(c)
	UI.dialog(self, "SCRAP A CARD?", "Scrap one %s for %d Dust?" % [str(c.get("name", "?")), int(v.get("scrap", 0))], [
		["SCRAP", func(): _do("/api/craft/scrap", {"card": str(c.id)}, c, false), UI.RED], ["KEEP IT", func(): pass]], UI.RED)


func _make() -> void:
	var c := _pick
	var v := _values(c)
	UI.dialog(self, "CRAFT A CARD?", "Craft %s for %d Dust?" % [str(c.get("name", "?")), int(v.get("craft", 0))], [
		["CRAFT", func(): _do("/api/craft/make", {"card": str(c.id)}, c, true), UI.GREEN], ["NOT NOW", func(): pass]], UI.PURPLE)


func _do(path: String, body: Dictionary, c: Dictionary, crafting: bool) -> void:
	var r := await Api.request("POST", path, body)
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	var id := str(c.id)
	var qty := int(r.data.get("quantity", 0))
	if qty <= 0:
		_owned.erase(id)
	elif _owned.has(id):
		_owned[id].quantity = qty
	else:
		_owned[id] = {"art_url": id, "quantity": qty}
	_craft.dust = int(r.data.get("dust", 0))
	await _refresh_extras()
	_pick = c.duplicate()
	_pick.quantity = qty
	_render()
	_render_bar()
	_show_detail(_pick)
	var tile = _tiles.get(id)
	if is_instance_valid(tile):
		_burst(tile, crafting)
	if crafting:
		Sfx.play("promote", 1.15)
		UI.toast(self, "Crafted %s" % str(c.get("name", "")), UI.GREEN)
	else:
		Sfx.play("ko", 1.3, -6.0)
		UI.toast(self, "+%d Dust" % int(r.data.get("gained", 0)), UI.PURPLE)


func _scrap_extras() -> void:
	UI.dialog(self, "SCRAP EXTRAS?", "Scrap %d extra card%s for %d Dust? You keep 3 of every card (1 of each leader), so your decks don't change." % [
		int(_craft.get("extras", 0)), "" if int(_craft.get("extras", 0)) == 1 else "s", int(_craft.get("extrasDust", 0))], [
		["SCRAP THEM", func():
			var r := await Api.request("POST", "/api/craft/extras")
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				return
			var inv := await Api.request("GET", "/api/profile/inventory")
			if inv.ok:
				_owned.clear()
				for row in inv.data:
					_owned[str(row.get("art_url", ""))] = row
			_craft.dust = int(r.data.get("dust", 0))
			await _refresh_extras()
			Sfx.play("ko", 1.2, -4.0)
			UI.toast(self, "Scrapped %d cards: +%d Dust" % [int(r.data.get("scrapped", 0)), int(r.data.get("gained", 0))], UI.PURPLE)
			_render()
			_render_bar(), UI.PURPLE],
		["CANCEL", func(): pass]], UI.PURPLE)


func _refresh_extras() -> void:
	var r := await Api.request("GET", "/api/craft")
	if r.ok and r.data is Dictionary:
		_craft = r.data


## Sparks over a tile: purple dust drifting up when scrapped, a bright pop when crafted.
func _burst(tile: Control, crafting: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = tile.global_position + tile.size / 2
	p.z_index = 50
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = tile.size / 2
	p.direction = Vector2.UP
	p.spread = 70.0 if crafting else 30.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0 if crafting else 140.0
	p.gravity = Vector2(0, 120 if crafting else -60)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = UI.GOLD if crafting else UI.PURPLE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	tile.pivot_offset = tile.size / 2
	var t := tile.create_tween()
	t.tween_property(tile, "scale", Vector2.ONE * 1.12, 0.1)
	t.tween_property(tile, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
