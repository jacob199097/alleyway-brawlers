extends Screen
## Deck builder: your collection on the left, the deck on the right.
## Click (or drag) a card to add it, click (or drag back) a deck row to remove one copy.
## 40 cards, max 3 copies, plus an optional leader. Right-click any card to zoom.
## The server validates and saves the deck.

const TILE := Vector2(150, 212)
const COLS := 7

var _inventory: Array = []
var _decks: Array = []
var _deck_idx := 0
var _deck_id = null
var _deck: Array = []          # one entry per copy: {cardId, name, rarity, art_url}
var _leader = null             # inventory row of the chosen leader, or null
var _dirty := false
var _filter_text := ""
var _faction := "all"
var _kind := "all"

var _grid: GridContainer
var _list: VBoxContainer
var _count: Label
var _deck_name: Label
var _leader_box: HBoxContainer
var _chips := {}


func _ready() -> void:
	UI.background(self, "menu_background.png", 0.72)
	Game.play_menu_music()
	_build_header()
	if not needs_server("The deck editor"):
		return
	_build_collection()
	_build_deck_panel()
	var spin := UI.spinner(self, Vector2(600, 600))
	var inv := await Api.request("GET", "/api/profile/inventory")
	var decks := await Api.request("GET", "/api/deck")
	spin.queue_free()
	if not inv.ok or not decks.ok:
		UI.toast(self, inv.error if not inv.ok else decks.error, UI.RED)
		return
	_inventory = inv.data
	_decks = decks.data if decks.data is Array else []
	if _decks.is_empty():
		_render_all()
		return
	_deck_idx = maxi(0, _decks.find_custom(func(d): return d.get("is_active", false)))
	_load_deck()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_exit()


# ── Layout ───────────────────────────────────────────────────────────────────

func _build_header() -> void:
	var back := UI.button("←  BACK", _exit, Vector2(180, 56))
	back.position = Vector2(24, 20)
	add_child(back)
	var t := UI.label("DECK BUILDER", 44, UI.GOLD, true)
	t.size = Vector2(1920, 60)
	t.position = Vector2(0, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(t)
	_count = UI.label("0/40", 34, UI.RED, true)
	_count.position = Vector2(1560, 26)
	add_child(_count)
	var save := UI.button("SAVE", _save, Vector2(180, 56), UI.GREEN)
	save.position = Vector2(1716, 20)
	add_child(save)
	if Game.offline:
		return
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 96)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = "Search…"
	search.custom_minimum_size = Vector2(300, 52)
	search.text_changed.connect(func(t):
		_filter_text = t.strip_edges().to_lower()
		_render_collection())
	bar.add_child(search)
	for f in [["all", "ALL"], ["lion_pride", "LIONS"], ["viper_clan", "VIPERS"]]:
		bar.add_child(_chip("faction", f[0], f[1]))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	bar.add_child(gap)
	for k in [["gang_member", "UNITS"], ["effect", "EFFECTS"], ["all", "ANY"]]:
		bar.add_child(_chip("kind", k[0], k[1]))
	_sync_chips()

	var sel := HBoxContainer.new()
	sel.position = Vector2(1210, 96)
	sel.add_theme_constant_override("separation", 8)
	add_child(sel)
	sel.add_child(UI.button("◀", _cycle.bind(-1), Vector2(56, 52)))
	_deck_name = UI.label("—", 24, Color.WHITE, true)
	_deck_name.custom_minimum_size = Vector2(250, 52)
	_deck_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sel.add_child(_deck_name)
	sel.add_child(UI.button("▶", _cycle.bind(1), Vector2(56, 52)))
	sel.add_child(UI.button("★ ACTIVE", _set_active, Vector2(150, 52), UI.GOLD))
	sel.add_child(UI.button("+ NEW", _new_deck, Vector2(120, 52), UI.GREEN))


func _chip(group: String, value: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(110, 52)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(func():
		Sfx.play("click")
		if group == "faction":
			_faction = value
		else:
			_kind = value
		_sync_chips()
		_render_collection())
	_chips["%s:%s" % [group, value]] = b
	return b


func _sync_chips() -> void:
	for key in _chips:
		var parts: PackedStringArray = key.split(":")
		_chips[key].set_pressed_no_signal((_faction if parts[0] == "faction" else _kind) == parts[1])


func _build_collection() -> void:
	var p := UI.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.45))
	p.position = Vector2(20, 166)
	p.size = Vector2(1170, 894)
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	# Drop a deck row here to remove it
	p.set_drag_forwarding(Callable(), func(_at, d): return d is Dictionary and d.get("source") == "deck",
		func(_at, d): _remove(d.cardId))


func _build_deck_panel() -> void:
	var p := UI.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.45))
	p.position = Vector2(1206, 166)
	p.size = Vector2(694, 894)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	var lp := UI.panel(UI.GOLD, Color(0.08, 0.06, 0.12, 0.95))
	col.add_child(lp)
	_leader_box = HBoxContainer.new()
	_leader_box.add_theme_constant_override("separation", 16)
	lp.add_child(_leader_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	# Drop a collection card here to add it
	p.set_drag_forwarding(Callable(), func(_at, d): return d is Dictionary and d.get("source") == "collection",
		func(_at, d): _add(d.item))


# ── Data ─────────────────────────────────────────────────────────────────────

func _load_deck() -> void:
	var d: Dictionary = _decks[_deck_idx]
	_deck_id = d.id
	_deck_name.text = str(d.get("name", "Deck")).left(18) + ("  ★" if d.get("is_active", false) else "")
	var r := await Api.request("GET", "/api/deck/%s" % d.id)
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	_deck = []
	for c in r.data.get("cards", []):
		for i in int(c.copies):
			_deck.append({"cardId": c.id, "name": c.name, "rarity": c.rarity, "art_url": c.get("art_url", "")})
	_leader = r.data.get("leader")
	_dirty = false
	_render_all()


func _cycle(dir: int) -> void:
	if _decks.is_empty():
		return
	var go := func():
		_deck_idx = (_deck_idx + dir + _decks.size()) % _decks.size()
		_load_deck()
	if _dirty:
		UI.dialog(self, "UNSAVED CHANGES", "Switch decks and lose your changes?", [["SWITCH", go, UI.RED], ["CANCEL", func(): pass]])
	else:
		go.call()


func _copies(card_id) -> int:
	return _deck.filter(func(c): return c.cardId == card_id).size()


func _add(item: Dictionary) -> void:
	var have := _copies(item.id)
	if have >= 3:
		UI.toast(self, "Max 3 copies per card", UI.RED)
		return
	if have >= int(item.get("quantity", 0)):
		UI.toast(self, "You only own %d" % int(item.quantity), UI.RED)
		return
	if _deck.size() >= 40:
		UI.toast(self, "Deck full (40 cards)", UI.RED)
		return
	_deck.append({"cardId": item.id, "name": item.name, "rarity": item.rarity, "art_url": item.get("art_url", "")})
	_dirty = true
	Sfx.play("draw", 1.2)
	_render_all()


func _remove(card_id) -> void:
	for i in range(_deck.size() - 1, -1, -1):
		if _deck[i].cardId == card_id:
			_deck.remove_at(i)
			_dirty = true
			Sfx.play("flip")
			break
	_render_all()


func _save(after := Callable()) -> void:
	if _deck_id == null:
		UI.toast(self, "No deck selected", UI.RED)
		return
	if _deck.size() != 40:
		UI.toast(self, "Need 40 cards (have %d)" % _deck.size(), UI.RED)
		return
	var grouped := {}
	for c in _deck:
		grouped[c.cardId] = grouped.get(c.cardId, 0) + 1
	var cards: Array = []
	for id in grouped:
		cards.append({"cardId": id, "copies": grouped[id]})
	var r := await Api.request("PUT", "/api/deck/%s/cards" % _deck_id,
		{"cards": cards, "leaderCardId": _leader.id if _leader is Dictionary else null})
	if r.ok:
		_dirty = false
		_decks[_deck_idx].card_count = 40
		UI.toast(self, "Deck saved!", UI.GREEN)
		if after.is_valid():
			after.call()
	else:
		UI.toast(self, r.error, UI.RED)


func _set_active() -> void:
	if _deck_id == null:
		return
	var r := await Api.request("PATCH", "/api/deck/%s/activate" % _deck_id)
	if r.ok:
		for d in _decks:
			d.is_active = d.id == _deck_id
		_deck_name.text = str(_decks[_deck_idx].name).left(18) + "  ★"
		UI.toast(self, "Set as active deck", UI.BLUE)
	else:
		UI.toast(self, r.error, UI.RED)


func _new_deck() -> void:
	var edit := LineEdit.new()
	edit.placeholder_text = "Deck name"
	edit.custom_minimum_size = Vector2(500, 56)
	var dlg := UI.dialog(self, "NEW DECK", "", [
		["CREATE", func(): _create(edit.text.strip_edges()), UI.GREEN], ["CANCEL", func(): pass]])
	var col: VBoxContainer = dlg.get_child(0).get_child(0)
	col.add_child(edit)
	col.move_child(edit, 1)
	edit.grab_focus()


func _create(name: String) -> void:
	if name == "":
		return
	var r := await Api.request("POST", "/api/deck", {"name": name})
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	r.data.card_count = 0
	_decks.append(r.data)
	_deck_idx = _decks.size() - 1
	_deck_id = r.data.id
	_deck = []
	_leader = null
	_dirty = false
	_deck_name.text = name.left(18)
	_render_all()
	UI.toast(self, "Created \"%s\"" % name, UI.BLUE)


func _exit() -> void:
	if not _dirty:
		Game.go("main_menu")
		return
	var text := "Save your changes before leaving?" if _deck.size() == 40 \
		else "Your deck has %d cards — it must be 40 to save. Leave without saving?" % _deck.size()
	var buttons := [["QUIT", func(): Game.go("main_menu"), UI.RED], ["CANCEL", func(): pass]]
	if _deck.size() == 40:
		buttons.push_front(["SAVE & EXIT", func(): _save(func(): Game.go("main_menu")), UI.GREEN])
	UI.dialog(self, "UNSAVED CHANGES", text, buttons)


# ── Rendering ────────────────────────────────────────────────────────────────

func _matches(item: Dictionary) -> bool:
	if item.get("card_type") == "leader":
		return false
	if _faction != "all" and item.get("clan") != _faction:
		return false
	if _kind == "gang_member" and item.get("card_type") != "gang_member":
		return false
	if _kind == "effect" and item.get("card_type") == "gang_member":
		return false
	if _filter_text != "":
		var hay := "%s %s %s" % [item.get("name", ""), item.get("subtype", ""), item.get("card_type", "")]
		return _filter_text in hay.to_lower()
	return true


func _render_all() -> void:
	_render_collection()
	_render_deck()
	_render_leader()


func _render_collection() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	for item in _inventory:
		if not _matches(item):
			continue
		var used := _copies(item.id)
		var tile := CardTile.make(item, TILE)
		tile.badge = "%d/%d" % [used, mini(3, int(item.get("quantity", 0)))]
		tile.count_badge = "×%d" % int(item.get("quantity", 0))
		tile.dimmed = used >= mini(3, int(item.get("quantity", 0)))
		tile.pressed.connect(func(_t): _add(item))
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		tile.set_drag_forwarding(func(_at):
			var prev := UI.texture_rect(UI.card_art(item), TILE * 0.8)
			prev.modulate.a = 0.85
			tile.set_drag_preview(prev)
			return {"source": "collection", "item": item}, Callable(), Callable())
		_grid.add_child(tile)


func _render_deck() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var grouped := {}
	var order: Array = []
	for c in _deck:
		if not grouped.has(c.cardId):
			grouped[c.cardId] = c.duplicate()
			grouped[c.cardId].count = 0
			order.append(c.cardId)
		grouped[c.cardId].count += 1
	for id in order:
		_list.add_child(_deck_row(grouped[id]))
	_count.text = "%d/40" % _deck.size()
	_count.label_settings.font_color = UI.BLUE if _deck.size() == 40 else UI.RED


func _deck_row(c: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(640, 64)
	b.add_theme_stylebox_override("normal", UI.box(Color("14141e"), UI.rarity_color(c.rarity), 2, 6))
	b.add_theme_stylebox_override("hover", UI.box(Color("201a2e"), UI.GOLD, 2, 6))
	var art := AtlasTexture.new()
	var full := UI.card_art(c)
	if full:
		art.atlas = full
		art.region = Rect2(0, full.get_height() * 0.12, full.get_width(), full.get_height() * 0.3)
	var thumb := UI.texture_rect(art if full else null, Vector2(150, 56), true)
	thumb.position = Vector2(4, 4)
	b.add_child(thumb)
	var n := UI.label(str(c.name), 22, Color.WHITE, true)
	n.position = Vector2(168, 16)
	b.add_child(n)
	var cnt := UI.label("×%d" % c.count, 28, UI.GOLD, true)
	cnt.position = Vector2(540, 12)
	b.add_child(cnt)
	var minus := UI.label("−", 32, UI.RED, true)
	minus.position = Vector2(604, 8)
	b.add_child(minus)
	b.pressed.connect(func(): _remove(c.cardId))
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var item = _inventory.filter(func(i): return i.id == c.cardId)
			UI.card_zoom(self, item[0] if not item.is_empty() else c))
	b.set_drag_forwarding(func(_at): return {"source": "deck", "cardId": c.cardId}, Callable(), Callable())
	return b


func _render_leader() -> void:
	if _leader_box == null:
		return
	for c in _leader_box.get_children():
		c.queue_free()
	var art := UI.texture_rect(UI.card_art(_leader) if _leader is Dictionary else null, Vector2(96, 136))
	_leader_box.add_child(art)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(360, 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_leader_box.add_child(info)
	info.add_child(UI.label("LEADER", 18, UI.GOLD, true))
	if _leader is Dictionary:
		info.add_child(UI.label(str(_leader.name), 30, Color.WHITE, true))
		info.add_child(UI.label("Authority %d" % int(_leader.get("authority", 0)), 20, Color("aaccff")))
	else:
		info.add_child(UI.label("No leader chosen", 24, UI.MUTED))
	_leader_box.add_child(UI.button("CHANGE" if _leader is Dictionary else "CHOOSE", _pick_leader, Vector2(150, 56), UI.GOLD))


func _pick_leader() -> void:
	var leaders := _inventory.filter(func(i): return i.get("card_type") == "leader")
	var buttons := [["CLEAR LEADER", func():
		_leader = null
		_dirty = true
		_render_leader(), UI.RED], ["CANCEL", func(): pass]]
	var dlg := UI.dialog(self, "CHOOSE A LEADER", "" if not leaders.is_empty() else "No leader cards in your collection.", buttons)
	var col: VBoxContainer = dlg.get_child(0).get_child(0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	col.move_child(row, 1)
	for l in leaders:
		var tile := CardTile.make(l, TILE)
		tile.pressed.connect(func(_t):
			_leader = l
			_dirty = true
			_render_leader()
			dlg.queue_free())
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		row.add_child(tile)
	await get_tree().process_frame
	var p: Control = dlg.get_child(0)
	p.reset_size()
	p.position = (Vector2(1920, 1080) - p.size) / 2
