extends Screen

## Card library: your collection (or every card in the game), with filters and a detail panel
## that follows the mouse. Right-click a card to zoom it; click it to pick it for crafting
## (the bar along the bottom): scrap it into Dust, or craft it from Dust (backend/routes/craft.js).

const Keywords := preload("res://scripts/keywords.gd")

const TILE := Vector2(150, 212)

var _owned: Dictionary = {}     # art_url -> inventory row
var _show_all := false
var _dust_was := -1   # the Dust the bar last showed (it counts to a new amount)
var _faction := "all"
var _kind := "all"
var _sub := "any"               # the finer filter (dropdown): a role, a Heavy's sacrifices, Continuous / Equip, tokens
## The dropdown's choices: [key, label]
const SUBS := [["any", "ANY KIND"], ["striver", "STRIVERS"], ["brawler", "BRAWLERS"], ["heavy", "HEAVIES"],
	["heavy1", "HEAVIES · SACRIFICE 1"], ["heavy2", "HEAVIES · SACRIFICE 2"], ["heavy3", "HEAVIES · SACRIFICE 3"],
	["continuous", "CONTINUOUS"], ["equip", "EQUIP"], ["token", "TOKENS (made by effects)"]]
var _rarities := {}
var _grid: GridContainer
var _total: Label
var _detail: VBoxContainer
var _chips := {}
var _craft: Dictionary = {}     # GET /api/craft: dust, values per rarity, extras
var _pick: Dictionary = {}      # the card picked for crafting
var _tiles := {}                # card id -> its tile
var _bar: HBoxContainer
var _hero: TextureRect          # the side panel's big card (tilts toward the mouse)
var _hero_mat: ShaderMaterial
var _hero_tilt := Vector2.ZERO
var _detail_id := "-"           # the card the side panel shows ("" = the collection)
var _detail_panel: Control


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
	var p := UI.glass(UI.panel(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0.45)), Color(0.02, 0.02, 0.06, 0.38), 6.0)
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
	var dp := UI.glass(UI.panel(UI.BLUE))
	dp.position = Vector2(1380, 190)
	dp.size = Vector2(520, 790)
	add_child(dp)
	_detail_panel = dp
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
		_detail_id = "-"   # (the collection, now that it is known)
		_show_detail({})
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
	var clans := CardDB.clans()
	if clans.size() <= 3:
		bar.add_child(_chip("faction", "all", "ALL CLANS"))
		for c in clans:
			bar.add_child(_chip("faction", c.id, str(c.name).to_upper()))
	else:   # (more clans than fit as buttons: a list, like the Deck Builder's)
		var pick := OptionButton.new()
		pick.add_item("ALL CLANS")
		pick.set_item_metadata(0, "all")
		for c in clans:
			pick.add_item(str(c.name).to_upper())
			pick.set_item_metadata(pick.item_count - 1, c.id)
		pick.custom_minimum_size = Vector2(220, 50)
		pick.add_theme_font_size_override("font_size", 17)
		pick.item_selected.connect(func(i):
			Sfx.play("click")
			_faction = str(pick.get_item_metadata(i))
			_render())
		bar.add_child(pick)
	bar.add_child(_spacer())
	for k in [["all", "ANY TYPE"], ["gang_member", "UNITS"], ["hustle", "HUSTLE"], ["ambush", "AMBUSH"], ["leader", "LEADER"]]:
		bar.add_child(_chip("kind", k[0], k[1]))
	var sub := OptionButton.new()
	for i in SUBS.size():
		sub.add_item(SUBS[i][1], i)
	sub.custom_minimum_size = Vector2(300, 50)
	sub.fit_to_longest_item = false   # (it stays 300 wide, clear of the card count beside it)
	sub.position = Vector2(1180, 36)
	sub.add_theme_font_size_override("font_size", 17)
	sub.item_selected.connect(func(i):
		Sfx.play("click")
		_sub = SUBS[i][0]
		_render())
	add_child(sub)
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
		if CardDB.get_card(id).get("token", false) != (_sub == "token"):   # tokens (made only by effects): only under TOKENS
			continue
		var c: Dictionary = CardDB.get_card(id).duplicate()
		var row = _owned.get(id)
		if row != null:
			for key in ["name", "rarity", "authority", "attack", "defense"]:
				if row.get(key) != null:
					c[key] = row[key]
			c.quantity = int(row.get("quantity", 0))
		seen[id] = true
		if _show_all or row != null or _sub == "token":
			out.append(c)
	for id in _owned:   # owned cards the rules data doesn't know yet
		if not seen.has(id):
			var row: Dictionary = _owned[id]
			out.append({"id": id, "art_url": id, "name": row.name, "rarity": row.rarity, "cardType": row.card_type,
				"clanTag": row.get("clan_tag", ""), "effectText": row.get("effect_text", ""), "quantity": row.quantity})
	return out


func _sub_matches(c: Dictionary) -> bool:
	var sub := str(c.get("subtype", ""))
	match _sub:
		"striver", "brawler", "heavy":
			return c.get("cardType") == "gang_member" and (sub if sub != "" else "brawler") == _sub
		"heavy1", "heavy2", "heavy3":
			return DuelState.needs_tribute(c) and DuelState.tributes_for(c) == int(_sub.substr(5))
		"continuous", "equip":
			return str(c.get("cardType", "")) in ["hustle", "ambush"] and sub == _sub
	return true


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
		if not _sub_matches(c):
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
	CardTile.cascade(_grid.get_children())


static func _rarest_first(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a.get("rarity", 1))
	var rb := int(b.get("rarity", 1))
	if ra != rb:
		return ra > rb
	return str(a.get("name", "")) < str(b.get("name", ""))


func _show_detail(c: Dictionary) -> void:
	var id := str(c.get("id", ""))
	if id == _detail_id:
		return
	_detail_id = id
	for n in _detail.get_children():
		n.queue_free()
	_hero = null
	_hero_mat = null
	_detail.add_theme_constant_override("separation", 10)
	if c.is_empty():
		_show_collection()
		return
	# The card, big, in 3D: it tilts toward the mouse over the panel, and sways gently otherwise
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(480, 470)
	_detail.add_child(holder)
	_hero = UI.texture_rect(UI.card_art(c), Vector2(330, 467))
	_hero.pivot_offset = _hero.size / 2
	if _hero.texture:
		_hero_mat = UI.card_material(_hero.size, int(c.get("rarity", 1)))
		_hero.material = _hero_mat
	holder.add_child(_hero)
	_hero.modulate.a = 0.0
	_hero.scale = Vector2.ONE * 0.9
	var tw := _hero.create_tween().set_parallel()
	tw.tween_property(_hero, "modulate:a", 1.0, 0.14)
	tw.tween_property(_hero, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	if not Game.offline:   # owned: a pip for each copy a deck can hold
		var have := int(c.get("quantity", 0))
		var cap := 1 if c.get("cardType") == "leader" else 3
		var pips := ""
		for i in cap:
			pips += "◆ " if i < have else "◇ "
		var extra := "  +%d" % (have - cap) if have > cap else ""
		_detail.add_child(UI.label("OWNED  %s%s" % [pips.strip_edges(), extra], 20, UI.BLUE if have > 0 else UI.MUTED, true))


## Before a card is hovered: the collection at a glance (all of it, then each clan, then each
## rarity), every bar filling as it appears.
func _show_collection() -> void:
	var many := CardDB.clans().size() > 4   # (a row per clan: closer together when there are many)
	if many:
		_detail.add_theme_constant_override("separation", 3)
	var all: Array = []
	for id in CardDB.all():
		var cd: Dictionary = CardDB.get_card(id)
		if not cd.get("token", false):
			all.append(cd)
	var owned := func(cd: Dictionary) -> bool:
		var row = _owned.get(str(cd.get("id", "")))
		return Game.offline or (row is Dictionary and int(row.get("quantity", 0)) > 0)
	var head := UI.label("YOUR COLLECTION", 30, UI.GOLD, true)
	_detail.add_child(head)
	var have := all.filter(owned).size()
	var big := UI.label("%d / %d cards" % [have, all.size()], 44, Color.WHITE, true)
	_detail.add_child(big)
	var i := 0
	_detail.add_child(_bar_row("", have, all.size(), UI.GOLD, i))
	_detail.add_child(_gap(14))
	_detail.add_child(UI.label("BY CLAN", 18, UI.MUTED, true))
	for clan in CardDB.clans():
		var of_clan := all.filter(func(cd): return str(cd.get("clan", "")) == clan.id)
		i += 1
		_detail.add_child(_bar_row(str(clan.name).to_upper(), of_clan.filter(owned).size(), of_clan.size(), clan.color, i, many))
	_detail.add_child(_gap(14))
	_detail.add_child(UI.label("BY RARITY", 18, UI.MUTED, true))
	for r in [5, 4, 3, 2, 1]:
		var of_r := all.filter(func(cd): return int(cd.get("rarity", 1)) == r)
		if of_r.is_empty():
			continue
		i += 1
		_detail.add_child(_bar_row(str(UI.RARITY_LABEL.get(r, "")).to_upper(), of_r.filter(owned).size(), of_r.size(), UI.rarity_color(r), i, many))
	_detail.add_child(_gap(18))
	var hint := UI.label("Hover a card to see it here. Click one to scrap or craft it.", 17, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size = Vector2(470, 0)
	_detail.add_child(hint)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## "NEBULA  ███████░░░  31 / 38": the bar fills from empty, one row after another.
func _bar_row(text: String, n: int, of: int, col: Color, i: int, compact := false) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(470, (25 if compact else 30) if text != "" else 22)
	var y := 0.0
	if text != "":
		var l := UI.label(text, 17, col, true)
		l.position = Vector2(0, 3)
		row.add_child(l)
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.08)
	back.position = Vector2(130 if text != "" else 0, 9 if text != "" else 4)
	back.size = Vector2(240 if text != "" else 470, 12)
	row.add_child(back)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = back.position
	fill.size = Vector2(0, back.size.y)
	row.add_child(fill)
	var k := float(n) / maxf(1.0, of)
	fill.create_tween().tween_property(fill, "size:x", back.size.x * k, 0.7).set_delay(0.15 + i * 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if text != "":
		var num := UI.label("%d / %d" % [n, of], 16, Color.WHITE if n == of else UI.MUTED, n == of)
		num.position = Vector2(388, 4)
		row.add_child(num)
	return row


func _process(delta: float) -> void:
	if _hero_mat == null or not is_instance_valid(_hero):
		return
	var t := Time.get_ticks_msec() / 1000.0
	var target := Vector2(sin(t * 0.7) * 5.0, cos(t * 0.53) * 3.5)   # (a slow sway)
	if _detail_panel and _detail_panel.get_global_rect().has_point(get_global_mouse_position()):
		var c := _hero.get_global_rect().get_center()
		var m := ((get_global_mouse_position() - c) / (_hero.size * 0.6)).clamp(-Vector2.ONE, Vector2.ONE)
		target = Vector2(-m.x, m.y) * 14.0
	_hero_tilt = _hero_tilt.lerp(target, 1.0 - exp(-8.0 * delta))
	_hero_mat.set_shader_parameter("y_rot", _hero_tilt.x)
	_hero_mat.set_shader_parameter("x_rot", _hero_tilt.y)
	_hero_mat.set_shader_parameter("glare", clampf(_hero_tilt.length() / 14.0, 0.0, 1.0))


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
	if _dust_was >= 0 and _dust_was != int(_craft.get("dust", 0)):   # (it runs to the new amount)
		UI.count_up(dust, _dust_was, int(_craft.get("dust", 0)), 0.8, "✦ %d DUST", "click")
	_dust_was = int(_craft.get("dust", 0))
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
	_detail_id = "-"   # (its owned count changed)
	_show_detail(_pick)
	var tile = _tiles.get(id)
	if crafting:
		await _reveal(c, tile)
	if is_instance_valid(tile):
		_burst(tile, crafting)
	if crafting:
		Sfx.play("promote", 1.15)
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


## A crafted card's reveal: purple dust pulls together in the middle of the screen, a flash, and the
## card turns in under light in its rarity's colour; a click (or a moment) sends it into its slot.
func _reveal(c: Dictionary, tile) -> void:
	var col := UI.rarity_color(c.get("rarity"))
	var rarity := int(c.get("rarity", 1))
	var centre := Vector2(960, 520)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0)
	veil.size = Vector2(1920, 1080)
	veil.z_index = 60
	add_child(veil)
	veil.create_tween().tween_property(veil, "color:a", 0.86, 0.25)
	# The dust: specks from all round that rush in
	Sfx.play("riser", 1.1, -4.0)
	for i in 36:
		var speck := ColorRect.new()
		speck.size = Vector2(6, 6)
		speck.color = UI.PURPLE.lerp(col, randf() * 0.6)
		speck.rotation = PI / 4
		var from := centre + Vector2.from_angle(randf() * TAU) * randf_range(420, 760)
		speck.position = from
		veil.add_child(speck)
		var t := speck.create_tween()
		t.tween_property(speck, "position", centre, randf_range(0.45, 0.7)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(speck.queue_free)
	await get_tree().create_timer(0.7).timeout
	# The flash, the light and the card
	var flash := ColorRect.new()
	flash.color = Color(col.lightened(0.5), 0.85)
	flash.size = veil.size
	veil.add_child(flash)
	flash.create_tween().tween_property(flash, "color:a", 0.0, 0.5)
	Sfx.play("boom", 1.2, -4.0)
	Sfx.play("legendary" if rarity >= 5 else "promote", 1.0, -2.0)
	var rays := Node2D.new()
	rays.position = centre
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rays.material = add
	var count := 10 + rarity * 2
	rays.draw.connect(func():
		for k in count:
			var a := k * TAU / count
			var w := 0.1 if k % 2 == 0 else 0.05
			rays.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * 900.0, Vector2.from_angle(a + w) * 900.0]),
				PackedColorArray([Color(col, 0.26), Color(col, 0.0), Color(col, 0.0)])))
	veil.add_child(rays)
	rays.create_tween().set_loops().tween_property(rays, "rotation", TAU, 18.0).from(0.0)
	var size := Vector2(380, 538)
	var art := UI.texture_rect(UI.card_art(c), size)
	art.position = centre - size / 2
	art.pivot_offset = size / 2
	var mat := UI.card_material(size, rarity)
	art.material = mat
	veil.add_child(art)
	art.scale = Vector2.ONE * 0.2
	var pop := art.create_tween().set_parallel()
	pop.tween_property(art, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_method(func(d: float): mat.set_shader_parameter("y_rot", d), 180.0, 0.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var word := UI.label("CRAFTED", 54, col, true)
	word.size = Vector2(1920, 70)
	word.position = Vector2(0, centre.y + size.y / 2 + 20)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	veil.add_child(word)
	var name := UI.label(str(c.get("name", "")).to_upper() + "   ·   " + str(UI.RARITY_LABEL.get(rarity, "")).to_upper(), 24, Color.WHITE, true)
	name.size = Vector2(1920, 30)
	name.position = Vector2(0, word.position.y + 70)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	veil.add_child(name)
	# Wait for a click, or a moment
	var done := [false]
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: done[0] = true)
	for i in 28:
		if done[0]:
			break
		await get_tree().create_timer(0.05).timeout
	# Into its slot
	var to: Vector2 = tile.global_position + tile.size / 2 if is_instance_valid(tile) else centre
	var fly := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fly.tween_property(art, "position", to - size / 2, 0.35)
	fly.tween_property(art, "scale", Vector2.ONE * 0.36, 0.35)
	fly.tween_property(veil, "color:a", 0.0, 0.35)
	fly.tween_property(rays, "modulate:a", 0.0, 0.25)
	fly.tween_property(word, "modulate:a", 0.0, 0.2)
	fly.tween_property(name, "modulate:a", 0.0, 0.2)
	await fly.finished
	veil.queue_free()


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
