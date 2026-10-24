extends Screen
## Deck builder: your collection on the left, the deck on the right.
## Click (or drag) a card to add it, click (or drag back) a deck row to remove one copy.
## 40 cards, max 3 copies, plus an optional leader. Right-click any card to zoom.
## Filters: search, clan, type/role, keyword and Authority. AUTO-FILL tops the deck up to 40,
## and deck codes (AWB1:...) share a deck as text. The server validates and saves the deck.

const TILE := Vector2(150, 212)
const COLS := 7
const Keywords := preload("res://scripts/keywords.gd")
const CODE_PREFIX := "AWB1:"
const KINDS := [["all", "ANY TYPE"], ["gang_member", "ALL UNITS"], ["striver", "STRIVERS"], ["brawler", "BRAWLERS"],
	["heavy", "HEAVIES"], ["effect", "ALL EFFECTS"], ["hustle", "HUSTLES"], ["ambush", "AMBUSHES"]]
const COSTS := [["all", "ANY AUTHORITY"], ["1-2", "AUTHORITY 1–2"], ["3-4", "AUTHORITY 3–4"], ["5-6", "AUTHORITY 5–6"], ["7-99", "AUTHORITY 7+"]]

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
var _keyword := "all"
var _cost := "all"

var _grid: GridContainer
var _list: VBoxContainer
var _count: Label
var _deck_name: Label
var _record: Label      # the deck's games and wins
var _leader_box: HBoxContainer
var _stats: VBoxContainer       # the Authority curve, the deck's make-up and anything worth fixing
var _chips := {}
var _shown_ids := ""            # what the collection grid showed last (it deals in when this changes)
var _rows := {}                 # card id -> its row in the deck list
var _curve_was: Array = [0, 0, 0, 0, 0, 0, 0]


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
	# The filters fit above the collection (x 24-1190), clear of the deck switcher: the search box
	# takes what's left. More than three clans: one dropdown instead of a button each.
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 96)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = "Search…"
	search.custom_minimum_size = Vector2(150, 52)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t):
		_filter_text = t.strip_edges().to_lower()
		_render_collection())
	bar.add_child(search)
	var clans := CardDB.clans()
	if clans.size() <= 3:
		bar.add_child(_chip("faction", "all", "ALL"))
		for c in clans:
			bar.add_child(_chip("faction", c.id, str(c.name).to_upper()))
	else:
		var opts := [["all", "ALL CLANS"]]
		for c in clans:
			opts.append([c.id, str(c.name).to_upper()])
		bar.add_child(_dropdown(opts, func(v): _faction = v))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	bar.add_child(gap)
	bar.add_child(_dropdown(KINDS, func(v): _kind = v, 172.0))
	var kws := [["all", "ANY KEYWORD"]]
	for k in Keywords.LIST:
		kws.append([k, Keywords.full_name(k)])
	bar.add_child(_dropdown(kws, func(v): _keyword = v, 172.0))
	bar.add_child(_dropdown(COSTS, func(v): _cost = v, 196.0))
	bar.size = Vector2(1166, 52)
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
	# The deck's record, in the top row left of the card count (clear of the leader panel)
	_record = UI.label("", 18, UI.MUTED)
	_record.size = Vector2(310, 24)
	_record.position = Vector2(1226, 40)
	_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_record)


func _chip(group: String, value: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(96, 52)
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


## A filter dropdown: options [[value, label], ...]; assign(value) stores it, then the grid redraws.
func _dropdown(options: Array, assign: Callable, width := 186.0) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(width, 52)
	o.add_theme_font_size_override("font_size", 17)
	o.fit_to_longest_item = false
	for opt in options:
		o.add_item(opt[1])
	o.get_popup().add_theme_font_size_override("font_size", 20)
	o.item_selected.connect(func(i: int):
		Sfx.play("click")
		assign.call(options[i][0])
		_render_collection())
	return o


func _sync_chips() -> void:
	for key in _chips:
		var parts: PackedStringArray = key.split(":")
		_chips[key].set_pressed_no_signal((_faction if parts[0] == "faction" else _kind) == parts[1])


func _build_collection() -> void:
	# No panel: the collection lies on the workbench in the background art
	var p := UI.panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
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
	var p := UI.glass(UI.panel(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0.45)))
	p.position = Vector2(1206, 166)
	p.size = Vector2(694, 894)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	var lp := UI.glass(UI.panel(UI.GOLD, Color(0.08, 0.06, 0.12, 0.95)), Color(0.1, 0.07, 0.02, 0.6))
	col.add_child(lp)
	_leader_box = HBoxContainer.new()
	_leader_box.add_theme_constant_override("separation", 16)
	lp.add_child(_leader_box)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 4)
	col.add_child(_stats)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	col.add_child(tools)
	var fill := UI.button("AUTO-FILL", _auto_fill, Vector2(160, 52), UI.GREEN)
	fill.tooltip_text = "Top the deck up to 40 with cards from your collection"
	tools.add_child(fill)
	tools.add_child(UI.button("CLEAR", func():
		if _deck.is_empty():
			return
		UI.dialog(self, "CLEAR THE DECK?", "Take every card out of this deck? (Nothing is saved until you press SAVE.)",
			[["CLEAR", func():
				_deck.clear()
				_dirty = true
				_render_all(), UI.RED], ["CANCEL", func(): pass]]), Vector2(120, 52), UI.RED))
	tools.add_child(UI.button("COPY CODE", _copy_code, Vector2(170, 52)))
	tools.add_child(UI.button("PASTE CODE", _paste_code, Vector2(170, 52)))
	# Drop a collection card here to add it
	p.set_drag_forwarding(Callable(), func(_at, d): return d is Dictionary and d.get("source") == "collection",
		func(_at, d): _add(d.item))


# ── Data ─────────────────────────────────────────────────────────────────────

func _load_deck() -> void:
	var d: Dictionary = _decks[_deck_idx]
	_deck_id = d.id
	_deck_name.text = str(d.get("name", "Deck")).left(18) + ("  ★" if d.get("is_active", false) else "")
	var g := int(d.get("games", 0))
	_record.text = "No games yet" if g == 0 else "%d game%s · %d%% won" % [g, "" if g == 1 else "s", roundi(100.0 * int(d.get("wins", 0)) / g)]
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


## A Striver's higher levels you haven't collected ("Rook LV2"): it can't promote past them.
func _missing_levels(card_id: String) -> Array:
	var line := CardDB.striver_line(card_id)
	var out: Array = []
	if line.is_empty() or line[0] != card_id:
		return out
	for i in range(1, line.size()):
		if _owned_copies(line[i]) <= 0:
			out.append("%s LV%d" % [CardDB.get_card(line[i]).get("name", line[i]), i + 1])
	return out


func _owned_copies(card_id: String) -> int:
	for i in _inventory:
		if str(i.get("art_url", "")) == card_id:
			return int(i.get("quantity", 0))
	return 0


## Under the deck list: the Hideout, the higher levels of the deck's Strivers that come along with
## them (up to 3 of each you own), and any level you haven't collected yet (it can't promote past it).
func _render_hideout(card_ids: Array) -> void:
	var lines: Array = []
	for id in card_ids:
		var line := CardDB.striver_line(str(id))
		if line.is_empty() or line[0] != str(id):
			continue
		for i in range(1, line.size()):
			var n := mini(3, _owned_copies(line[i]))
			var name := "%s LV%d" % [CardDB.get_card(line[i]).get("name", line[i]), i + 1]
			lines.append([name, n])
	if lines.is_empty():
		return
	var head := UI.label("HIDEOUT  ·  COMES WITH YOUR STRIVERS", 15, UI.GOLD, true)
	head.tooltip_text = "Your Strivers' higher levels wait in the Hideout during a match and come out when they promote. You don't add them: every copy you own (up to 3) comes along."
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	_list.add_child(head)
	for l in lines:
		var row := UI.label(("   %s  ×%d" % [l[0], l[1]]) if l[1] > 0 else "   %s  —  NOT COLLECTED" % l[0], 15, UI.MUTED if l[1] > 0 else UI.RED)
		_list.add_child(row)


## A Striver above level 1 (a promoted form): it never goes in the deck, it waits in the Hideout
## and comes with its level 1 card. Its level, or 0 for any other card.
static func _hideout_level(item: Dictionary) -> int:
	var lv := int(item.get("level", 1))
	return lv if item.get("card_type") == "gang_member" and lv > 1 else 0


func _add(item: Dictionary, from: Control = null) -> void:
	if _hideout_level(item) > 0:
		UI.toast(self, "Level %d %s waits in the Hideout: add its level 1 card and it comes along" % [_hideout_level(item), item.get("name", "")], UI.GOLD)
		Sfx.play("error")
		return
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
	var missing := _missing_levels(str(item.get("art_url", "")))
	if not missing.is_empty():   # (it can't promote past a level you haven't collected)
		UI.toast(self, "%s can't promote yet: you haven't collected %s" % [item.get("name", ""), " and ".join(missing)], UI.GOLD)
	var start := from.get_global_rect() if from and is_instance_valid(from) else Rect2()
	_render_all()
	_fly_in(item, start)
	if _deck.size() == 40:
		_complete()


func _remove(card_id) -> void:
	for i in range(_deck.size() - 1, -1, -1):
		if _deck[i].cardId == card_id:
			_deck.remove_at(i)
			_dirty = true
			Sfx.play("flip")
			break
	_render_all()
	var row = _rows.get(card_id)
	if row is Control and is_instance_valid(row):
		row.modulate = Color(1.6, 0.6, 0.6)
		row.create_tween().tween_property(row, "modulate", Color.WHITE, 0.35)


## The card flies from where it was clicked in the grid to its row in the deck list, shrinking as it
## goes; the row pops and lights up when it lands.
func _fly_in(item: Dictionary, start: Rect2) -> void:
	var row = _rows.get(item.id)
	if not row is Control or not is_instance_valid(row):
		return
	var land := func():
		if not is_instance_valid(row):
			return
		row.pivot_offset = row.size / 2
		row.modulate = Color(1.5, 1.4, 1.0)
		var t: Tween = row.create_tween().set_parallel()
		t.tween_property(row, "scale", Vector2(1.04, 1.12), 0.08)
		t.chain().tween_property(row, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(row, "modulate", Color.WHITE, 0.4)
		_count.pivot_offset = _count.size / 2
		var c := _count.create_tween()
		c.tween_property(_count, "scale", Vector2.ONE * 1.18, 0.07)
		c.tween_property(_count, "scale", Vector2.ONE, 0.2)
	if start.size == Vector2.ZERO:
		land.call()
		return
	var ghost := UI.texture_rect(UI.card_art(item), start.size)
	ghost.top_level = true
	ghost.z_index = 100
	ghost.global_position = start.position
	ghost.pivot_offset = start.size / 2
	add_child(ghost)
	await get_tree().process_frame   # (the row's place, now that the list is laid out)
	if not is_instance_valid(row):
		ghost.queue_free()
		return
	var to: Vector2 = row.get_global_rect().get_center() - start.size / 2
	var t := ghost.create_tween().set_parallel()
	t.tween_property(ghost, "global_position", to, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(ghost, "scale", Vector2.ONE * 0.3, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(ghost, "rotation", 0.25, 0.32)
	t.tween_property(ghost, "modulate:a", 0.0, 0.12).set_delay(0.22)
	t.chain().tween_callback(func():
		ghost.queue_free()
		land.call())


## Forty cards: the count glows gold.
func _complete() -> void:
	Sfx.play("promote", 1.15, -6.0)
	_count.pivot_offset = _count.size / 2
	_count.modulate = Color(1.8, 1.6, 0.8)
	var t := _count.create_tween()
	t.tween_property(_count, "scale", Vector2.ONE * 1.35, 0.12)
	t.tween_property(_count, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_count, "modulate", Color.WHITE, 0.8)
	UI.toast(self, "Deck complete: 40 cards", UI.GOLD)


# ── Auto-fill and deck codes ─────────────────────────────────────────────────

func _item_for(card_id) -> Dictionary:
	for i in _inventory:
		if i.id == card_id:
			return i
	return {}


## Tops the deck up to 40: characters first (about 28), strongest for their Authority, then
## Hustles and Ambushes, then anything left. Promoted forms are skipped: they wait in the
## Hideout by themselves.
func _auto_fill() -> void:
	if _deck_id == null:
		UI.toast(self, "Make a deck first (+ NEW)", UI.RED)
		return
	if _deck.size() >= 40:
		UI.toast(self, "The deck is already full", UI.GOLD)
		return
	var pool := _inventory.filter(func(i):
		return i.get("card_type") != "leader" and not CardDB.get_card(str(i.get("art_url", ""))).is_empty() \
			and int(i.get("level", 1)) <= 1)
	var units := pool.filter(func(i): return i.get("card_type") == "gang_member")
	var effects := pool.filter(func(i): return i.get("card_type") != "gang_member")
	# The leader's clan first (its cards work together), then the best value for their Authority
	var clan := str(_leader.get("clan", "")) if _leader is Dictionary else ""
	var home := func(i) -> float: return 100000.0 if clan != "" and str(i.get("clan", "")) == clan else 0.0
	var value := func(i): return home.call(i) + float(int(i.get("attack", 0)) + int(i.get("defense", 0))) / maxf(1.0, float(i.get("authority", 1))) + 300.0 * int(i.get("rarity", 1))
	units.sort_custom(func(a, b): return value.call(a) > value.call(b))
	effects.sort_custom(func(a, b): return home.call(a) + int(a.get("rarity", 1)) > home.call(b) + int(b.get("rarity", 1)))
	var before := _deck.size()
	var unit_count := _deck.filter(func(c): return _item_for(c.cardId).get("card_type") == "gang_member").size()
	for item in units:
		while unit_count < 28 and _deck.size() < 40 and _copies(item.id) < mini(3, int(item.get("quantity", 0))):
			_deck.append({"cardId": item.id, "name": item.name, "rarity": item.rarity, "art_url": item.get("art_url", "")})
			unit_count += 1
	for item in effects + units:
		while _deck.size() < 40 and _copies(item.id) < mini(3, int(item.get("quantity", 0))):
			_deck.append({"cardId": item.id, "name": item.name, "rarity": item.rarity, "art_url": item.get("art_url", "")})
	var added := _deck.size() - before
	if added == 0:
		UI.toast(self, "No more cards in your collection to add", UI.RED)
		return
	_dirty = true
	Sfx.play("draw", 1.2)
	_render_all()
	UI.toast(self, "Added %d card(s)%s" % [added, "" if _deck.size() == 40 else " — your collection ran out at %d/40" % _deck.size()],
		UI.GREEN if _deck.size() == 40 else UI.GOLD)


## The deck as text: AWB1:<base64 of "leader|card*copies,card*copies,...">, by card ID, so a code
## works for anyone who owns the cards.
func _deck_code() -> String:
	var counts := {}
	var order: Array = []
	for c in _deck:
		var art := str(c.get("art_url", ""))
		if not counts.has(art):
			order.append(art)
		counts[art] = counts.get(art, 0) + 1
	var parts: Array = order.map(func(a): return "%s*%d" % [a, counts[a]])
	var leader := str(_leader.get("art_url", "")) if _leader is Dictionary else ""
	return CODE_PREFIX + Marshalls.utf8_to_base64("%s|%s" % [leader, ",".join(parts)])


func _copy_code() -> void:
	if _deck.is_empty():
		UI.toast(self, "The deck is empty", UI.RED)
		return
	DisplayServer.clipboard_set(_deck_code())
	UI.toast(self, "Deck code copied. Paste it to a friend!", UI.GREEN)


func _paste_code() -> void:
	if _deck_id == null:
		UI.toast(self, "Make a deck first (+ NEW)", UI.RED)
		return
	var edit := LineEdit.new()
	edit.placeholder_text = "AWB1:…"
	edit.custom_minimum_size = Vector2(700, 56)
	edit.text = DisplayServer.clipboard_get().strip_edges() if DisplayServer.clipboard_get().strip_edges().begins_with(CODE_PREFIX) else ""
	var dlg := UI.dialog(self, "PASTE A DECK CODE", "This replaces the cards in \"%s\" (nothing is saved until you press SAVE)." % _deck_name.text.trim_suffix("  ★"),
		[["LOAD", func(): _load_code(edit.text.strip_edges()), UI.GREEN], ["CANCEL", func(): pass]])
	var col: VBoxContainer = dlg.get_child(0).get_child(0)
	col.add_child(edit)
	col.move_child(edit, 2)
	edit.grab_focus()


func _load_code(code: String) -> void:
	if not code.begins_with(CODE_PREFIX):
		UI.toast(self, "That isn't a deck code", UI.RED)
		return
	var text := Marshalls.base64_to_utf8(code.trim_prefix(CODE_PREFIX))
	var halves := text.split("|")
	if halves.size() != 2:
		UI.toast(self, "That deck code is damaged", UI.RED)
		return
	var by_art := {}
	for i in _inventory:
		by_art[str(i.get("art_url", ""))] = i
	var missing: Array = []
	var deck: Array = []
	for part in halves[1].split(",", false):
		var bits := part.split("*")
		var want := clampi(int(bits[1]) if bits.size() > 1 else 1, 1, 3)
		var item: Dictionary = by_art.get(bits[0], {})
		if _hideout_level(item) > 0:   # (promoted forms wait in the Hideout, never in the deck)
			continue
		var have := mini(want, int(item.get("quantity", 0)))
		for n in have:
			deck.append({"cardId": item.id, "name": item.name, "rarity": item.rarity, "art_url": item.get("art_url", "")})
		if have < want:
			var name := str(item.get("name", CardDB.get_card(bits[0]).get("name", bits[0])))
			missing.append("%s ×%d" % [name, want - have])
	_deck = deck.slice(0, 40)
	var leader: Dictionary = by_art.get(halves[0], {})
	if halves[0] != "":
		if leader.get("card_type") == "leader":
			_leader = leader
		else:
			missing.append("%s (leader)" % CardDB.get_card(halves[0]).get("name", halves[0]))
	_dirty = true
	_render_all()
	if missing.is_empty():
		UI.toast(self, "Deck loaded (%d cards)" % _deck.size(), UI.GREEN)
	else:
		UI.dialog(self, "DECK LOADED — SOME CARDS MISSING", "You don't own enough of:\n" + "\n".join(missing) \
			+ "\n\nThe deck has %d/40. AUTO-FILL can top it up." % _deck.size(), [["OK", func(): pass]])


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
		if not _decks[_deck_idx].get("is_active", false):   # (the one you play with: ask)
			var go_on := func(make_active: bool) -> void:
				if make_active:
					await _set_active()
				if after.is_valid():
					after.call()
			UI.dialog(self, "ACTIVE DECK", "Make \"%s\" your active deck? It's the deck you play matches with." % str(_decks[_deck_idx].get("name", "Deck")),
				[["MAKE ACTIVE", go_on.bind(true), UI.GOLD], ["NOT NOW", go_on.bind(false)]])
			return
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
	# A Striver's later levels come along with its level 1 card (its stars show how many): they're
	# only listed when looking at Strivers
	if _hideout_level(item) > 0 and _kind != "striver":
		return false
	if _faction != "all" and item.get("clan") != _faction:
		return false
	match _kind:
		"gang_member":
			if item.get("card_type") != "gang_member":
				return false
		"effect":
			if item.get("card_type") == "gang_member":
				return false
		"striver", "brawler", "heavy":
			if item.get("card_type") != "gang_member" or str(item.get("subtype", "brawler")) != _kind:
				return false
		"hustle", "ambush":
			if item.get("card_type") != _kind:
				return false
	if _cost != "all":
		var r := _cost.split("-")
		var a := int(item.get("authority", 0))
		if a < int(r[0]) or a > int(r[1]):
			return false
	if _keyword != "all":
		var text := str(item.get("effect_text", "")) + " " + str(CardDB.get_card(str(item.get("art_url", ""))).get("effectText", ""))
		if not Keywords.full_name(_keyword) in text.to_upper():
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
	var ids := ""
	for item in _inventory:
		if not _matches(item):
			continue
		ids += str(item.id) + ","
		var used := _copies(item.id)
		var tile := CardTile.make(item, TILE)
		tile.rest_rotation = (absi(hash(str(item.id))) % 1000) / 1000.0 * 3.6 - 1.8   # (laid by hand on the bench)
		tile.badge = "%d/%d" % [used, mini(3, int(item.get("quantity", 0)))]
		tile.count_badge = "×%d" % int(item.get("quantity", 0))
		tile.dimmed = used >= mini(3, int(item.get("quantity", 0)))
		tile.pressed.connect(func(t): _add(item, t))
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		if CardDB.striver_stage(CardDB.get_card(str(item.get("art_url", "")))).y > 1 and _hideout_level(item) == 0:
			tile.tooltip_text = "A Striver: its higher levels wait in your Hideout and come along with it. Right-click to see them."
		if _hideout_level(item) > 0:   # (a promoted form: it comes with its level 1 card)
			tile.badge = "LV%d" % _hideout_level(item)
			tile.dimmed = true
			tile.tooltip_text = "Waits in the Hideout: add its level 1 card to the deck"
			_grid.add_child(tile)
			continue
		tile.set_drag_forwarding(func(_at):
			var prev := UI.texture_rect(UI.card_art(item), TILE * 0.8)
			prev.modulate.a = 0.85
			tile.set_drag_preview(prev)
			return {"source": "collection", "item": item}, Callable(), Callable())
		_grid.add_child(tile)
	if ids != _shown_ids:   # (a new filter or deck: deal the grid in; adding a card doesn't)
		_shown_ids = ids
		CardTile.cascade(_grid.get_children())


func _render_deck() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var grouped := {}
	var order: Array = []
	for c in _deck:
		if not grouped.has(c.cardId):
			grouped[c.cardId] = c.duplicate()
			grouped[c.cardId].count = 0
			order.append(c.cardId)
		grouped[c.cardId].count += 1
	for id in order:
		_rows[id] = _deck_row(grouped[id])
		_list.add_child(_rows[id])
	_render_hideout(order.map(func(id): return str(grouped[id].art_url)))
	_count.text = "%d/40" % _deck.size()
	_count.label_settings.font_color = UI.BLUE if _deck.size() == 40 else UI.RED
	_render_stats()


## How many cards cost 1, 2, ... 7+ Authority (bars), what kinds they are, and warnings: no leader,
## too few characters, Heavies with too little to sacrifice, Strivers that can't promote (their
## next level isn't owned, so it's not in the Hideout), a top-heavy deck.
func _render_stats() -> void:
	if _stats == null:
		return
	for c in _stats.get_children():
		c.queue_free()
	if _deck.is_empty():
		return
	var curve := [0, 0, 0, 0, 0, 0, 0]
	var kinds := {"gang_member": 0, "hustle": 0, "ambush": 0}
	var cheap := 0          # characters a Heavy could sacrifice without much loss
	var most_tributes := 0
	var stuck := {}         # Strivers whose next level isn't owned
	var owned := {}
	for i in _inventory:
		owned[str(i.get("art_url", ""))] = true
	for e in _deck:
		var c := CardDB.get_card(str(e.get("art_url", "")))
		curve[clampi(int(c.get("authority", 1)), 1, 7) - 1] += 1
		var kind := str(c.get("cardType", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind == "gang_member" and not DuelState.needs_tribute(c) and int(c.get("authority", 0)) <= 3:
			cheap += 1
		most_tributes = maxi(most_tributes, DuelState.tributes_for(c))
		var next := CardDB.next_form(str(e.get("art_url", "")))
		if c.get("subtype") == "striver" and next != "" and not owned.has(next):
			stuck[str(c.get("name", ""))] = str(CardDB.get_card(next).get("name", next))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_stats.add_child(row)
	var top: int = curve.max()
	var was := _curve_was
	_curve_was = curve.duplicate()
	for i in curve.size():
		var b := VBoxContainer.new()
		b.add_theme_constant_override("separation", 0)
		b.alignment = BoxContainer.ALIGNMENT_END
		b.custom_minimum_size = Vector2(34, 74)
		var n := UI.label(str(curve[i]) if curve[i] > 0 else "", 14, Color.WHITE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(n)
		var bar := ColorRect.new()
		bar.color = UI.GOLD if i < 6 else UI.RED
		var h: float = 2.0 + 40.0 * curve[i] / maxf(1.0, top)
		bar.custom_minimum_size = Vector2(26, 2.0 + 40.0 * int(was[i]) / maxf(1.0, top))   # (grows from where it was)
		bar.create_tween().tween_property(bar, "custom_minimum_size:y", h, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if curve[i] != int(was[i]):
			bar.modulate = Color(1.6, 1.6, 1.6)
			bar.create_tween().tween_property(bar, "modulate", Color.WHITE, 0.4)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_child(bar)
		var a := UI.label(str(i + 1) if i < 6 else "7+", 14, UI.MUTED)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(a)
		row.add_child(b)
	var make := UI.label("AUTHORITY\n%d characters · %d Hustles · %d Ambushes" % [kinds.gang_member, kinds.hustle, kinds.ambush], 15, UI.MUTED)
	make.custom_minimum_size = Vector2(360, 0)
	make.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(make)
	var warn: Array = []
	if _leader == null:
		warn.append("No leader chosen.")
	if kinds.gang_member < 20:
		warn.append("Only %d characters: most decks want 25 or more." % kinds.gang_member)
	if most_tributes > 0 and cheap < 4 + 2 * most_tributes:
		warn.append("Heavies need characters to sacrifice: only %d characters cost 3 Authority or less." % cheap)
	for name in stuck:
		warn.append("%s can't promote: you don't own %s." % [name, stuck[name]])
	if curve[6] > 6:
		warn.append("%d cards cost 7+ Authority: you may draw them long before you can play them." % curve[6])
	for w in warn.slice(0, 4):
		var l := UI.label("⚠ " + w, 15, Color("ffb35c"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(640, 0)
		_stats.add_child(l)
	if warn.size() > 4:
		_stats.add_child(UI.label("  …and %d more" % (warn.size() - 4), 14, UI.MUTED))


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
	info.custom_minimum_size = Vector2(220, 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_leader_box.add_child(info)
	info.add_child(UI.label("LEADER", 18, UI.GOLD, true))
	if _leader is Dictionary:
		info.add_child(UI.label(str(_leader.name), 30, Color.WHITE, true))
		info.add_child(UI.label("Authority %d" % int(_leader.get("authority", 0)), 20, Color("aaccff")))
	else:
		info.add_child(UI.label("No leader chosen", 24, UI.MUTED))
	# The leader's clan deck box (assets/<clan>_deckbox.png), when there is one
	var clan := str(CardDB.get_card(str(_leader.get("art_url", ""))).get("clanTag", "")) if _leader is Dictionary else ""
	var box := UI.tex("%s_deckbox.png" % clan) if clan != "" else null
	_leader_box.add_child(UI.texture_rect(box, Vector2(136, 136)))
	_leader_box.add_child(UI.button("CHANGE" if _leader is Dictionary else "CHOOSE", _pick_leader, Vector2(150, 56), UI.GOLD))
	_render_stats()   # (the "no leader" warning)


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
