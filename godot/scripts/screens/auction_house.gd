extends Screen
## The auction house: players sell cards to each other for Karat (backend/economy/auction.js, which
## decides everything: prices, fees, who may trade; this screen shows it and asks).
##   LIVE AUCTIONS  running auctions as lots: pick one, bid (or Buy Now, before the first bid)
##   SELL           your cards: pick one, set a reserve (the lowest bid) and maybe a Buy Now price, list it
##   MY AUCTIONS    what you're selling and bidding on (and the last 7 days' results, stamped)
## A neon back-room market: gold dust in the air, a ticker of what's hot, lots that flash when someone
## bids (it checks for new bids every REFRESH seconds), coins and stamps when Karat changes hands.
## Its backdrop is assets/bg_auction_house.jpg once that exists (UI.background), the shop's until then.

const LOT := Vector2(196, 277)          # a lot's card
const PLATE_H := 96.0                   # the price plate under it
const COLS := 5
const REFRESH := 15.0                   # seconds between checks for new bids
const HOT := Color("ffcf4a")            # the gold of prices and the market's neon
const PANEL_BG := Color(0.035, 0.03, 0.07, 0.62)

var _tab := "browse"
var _tab_buttons := {}
var _tab_line: ColorRect
var _info := {}                  # GET /api/auction: eligible, reasons, karat, limits, rules
var _auctions: Array = []        # the lots on show (browse) or yours (mine)
var _owned: Array = []           # GET /api/profile/inventory rows (sell)
var _picked := {}                # the auction or card picked
var _lots := {}                  # auction id -> {root, tile, plate, price, sub, timer, chip, ends}
var _sell_tiles := {}            # card id -> CardTile (sell)
var _rarity := 0                 # filter: 0 = any
var _clan := ""
var _search := ""
var _sort := "ending"            # ending | low | high | bids
var _busy := false
var _since_refresh := 0.0

var _balance: Label
var _karat_shown := 0
var _grid_box: VBoxContainer     # the lots (in a scroll)
var _scroll: ScrollContainer
var _side: VBoxContainer         # the picked lot / card
var _side_panel: Control
var _filters: HBoxContainer
var _ticker: Label
var _ticker_x := 0.0
var _ticker_w := 0.0   # one pass of the ticker's line: it scrolls by that much, then round again
var _live_dot: ColorRect
var _countdowns: Array = []      # [[Label, ends_at unix, prefix]]: the time left, ticking
var _time_bar: ColorRect         # the picked lot's time left, as a bar
var _time_bar_full := 0.0
var _price_big: Label            # the picked lot's price
var _bid_button: Button
var _spot: TextureRect


func _ready() -> void:
	back_to = "main_menu"
	if UI.tex("bg_auction_house.jpg") or UI.tex("bg_auction_house.png"):
		UI.background(self, "menu_background.jpg", 0.5)
	else:
		UI.background(self, "bg_shop.jpg", 0.62)
	Game.play_menu_music()
	Game.sound.ambience("crowd")   # (a murmur in the room)
	_dust()
	_build_header()
	UI.back_button(self, func(): Game.go("main_menu"))
	if not needs_server("The auction house"):
		return
	_build_ticker()
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 10)
	_filters.position = Vector2(40, 186)
	add_child(_filters)
	var lp := _glass_panel(Vector2(40, 246), Vector2(1220, 744), Color(HOT, 0.35))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(_scroll)
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 18)
	_grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid_box)
	_side_panel = _glass_panel(Vector2(1280, 186), Vector2(600, 804), Color(HOT, 0.55))
	_spot = _spotlight()
	_side_panel.add_child(_spot)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	_side_panel.add_child(_side)
	var r := await Api.request("GET", "/api/auction")
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	_info = r.data
	_set_karat(int(_info.get("karat", 0)), false)
	_show("browse")


func _exit_tree() -> void:
	Game.sound.ambience("")


func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	for cd in _countdowns:
		if is_instance_valid(cd[0]):
			var left := float(cd[1]) - now
			var l: Label = cd[0]
			l.text = str(cd[2]) + _left(left)
			l.modulate = Color(1, 0.35 + 0.65 * pulse, 0.35 + 0.65 * pulse) if left < 300.0 else Color.WHITE
	if is_instance_valid(_time_bar) and _time_bar_full > 0.0:
		var end_at: float = _time_bar.get_meta("ends", 0.0)
		var frac := clampf((end_at - now) / _time_bar_full, 0.0, 1.0)
		_time_bar.size.x = 520.0 * frac
		_time_bar.color = HOT.lerp(UI.RED, clampf(1.0 - frac * 12.0, 0.0, 1.0))
	if is_instance_valid(_live_dot):
		_live_dot.modulate.a = 0.35 + 0.65 * pulse
	if is_instance_valid(_ticker) and _ticker_w > 0:
		_ticker_x -= delta * 70.0
		if _ticker_x < -_ticker_w:
			_ticker_x = fmod(_ticker_x, _ticker_w)
		_ticker.position.x = _ticker_x
	if is_instance_valid(_spot):
		_spot.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 1.4)
	_since_refresh += delta
	if _since_refresh >= REFRESH and not _busy and _tab in ["browse", "mine"] and not _info.is_empty():
		_since_refresh = 0.0
		_refresh_live()


# ── The room: header, ticker, gold dust, spotlight ───────────────────────────

func _build_header() -> void:
	var title := UI.label("AUCTION HOUSE", 58, HOT, true)
	title.label_settings.shadow_color = Color(1.0, 0.62, 0.1, 0.55)
	title.label_settings.shadow_size = 14
	title.label_settings.shadow_offset = Vector2.ZERO
	title.position = Vector2(40, 20)
	add_child(title)
	_neon_flicker(title)
	var live := HBoxContainer.new()
	live.add_theme_constant_override("separation", 10)
	live.position = Vector2(44, 98)
	add_child(live)
	_live_dot = ColorRect.new()
	_live_dot.color = UI.RED
	_live_dot.custom_minimum_size = Vector2(12, 12)
	_live_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live.add_child(_live_dot)
	live.add_child(UI.label("LIVE  ·  BLACK MARKET TRADING", 18, Color(1, 0.75, 0.75), true))
	# Tabs, with a gold line that slides to the one open
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.position = Vector2(700, 34)
	add_child(tabs)
	for t in [["browse", "LIVE AUCTIONS"], ["sell", "SELL"], ["mine", "MY AUCTIONS"]]:
		var b := Button.new()
		b.text = t[1]
		b.flat = true
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_override("font", UI.font())
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(0.75, 0.72, 0.85))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", HOT)
		b.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6))
		b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 6))
		b.add_theme_stylebox_override("pressed", UI.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 6))
		b.pressed.connect(func():
			if _tab != t[0]:
				Sfx.play("whoosh", 1.4, -14.0)
				_show(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	_tab_line = ColorRect.new()
	_tab_line.color = HOT
	_tab_line.size = Vector2(0, 4)
	_tab_line.position = Vector2(700, 92)
	add_child(_tab_line)
	# The balance, top right
	var pill := PanelContainer.new()
	var sb := UI.box(Color(0.06, 0.04, 0.0, 0.85), HOT, 2, 30)
	sb.shadow_color = Color(HOT, 0.35)
	sb.shadow_size = 10
	sb.content_margin_left = 22
	sb.content_margin_right = 26
	pill.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	row.add_child(_karat_icon(58))
	_balance = UI.label("0", 34, HOT, true)
	row.add_child(_balance)
	row.add_child(UI.label("KARAT", 16, Color(HOT, 0.8), true))
	add_child(pill)
	pill.position = Vector2(1880 - 300, 32)
	pill.custom_minimum_size = Vector2(300, 0)
	pill.set_meta("pill", true)


## A neon sign switching on: a couple of stutters and a buzz, then a slow breathe.
func _neon_flicker(c: CanvasItem) -> void:
	c.modulate.a = 0.0
	var t := c.create_tween()
	t.tween_interval(0.25)
	t.tween_callback(func(): Sfx.play("neon_buzz", 1.0, -12.0))
	for a in [1.0, 0.15, 0.9, 0.3, 1.0]:
		t.tween_property(c, "modulate:a", a, 0.05)
		t.tween_interval(randf_range(0.03, 0.09))
	var breathe := c.create_tween().set_loops()
	breathe.tween_interval(1.2)
	breathe.tween_property(c, "modulate", Color(1.08, 1.05, 1.0), 1.6).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(c, "modulate", Color(0.92, 0.9, 0.9), 1.6).set_trans(Tween.TRANS_SINE)


## The Karat coin from the main menu bar (assets/karat_icon.png, cut from main_menu_bar.png), or a drawn one.
func _karat_icon(d: float) -> Control:
	var t := UI.tex("karat_icon.png")
	if t == null:
		return _coin(d * 0.6)
	var r := UI.texture_rect(t, Vector2(d, d))
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## A gold coin (drawn): the Karat flying between places.
func _coin(d: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var o := Vector2(d, d) / 2
		c.draw_circle(o, d / 2, HOT.darkened(0.35))
		c.draw_circle(o, d / 2 - 2.5, HOT)
		c.draw_circle(o + Vector2(-d * 0.12, -d * 0.12), d * 0.16, Color(1, 1, 0.85, 0.7))
		c.draw_arc(o, d / 2 - 5.5, 0, TAU, 24, HOT.darkened(0.25), 1.5))
	return c


func _build_ticker() -> void:
	var band := Panel.new()
	band.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.01, 0.03, 0.82), Color(HOT, 0.45), 1, 0))
	band.position = Vector2(0, 132)
	band.size = Vector2(1920, 40)
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_ticker = UI.label("", 19, Color(1, 0.9, 0.7), true)
	_ticker.position = Vector2(0, 7)
	band.add_child(_ticker)


## What's on the ticker: lots ending soon, bidding wars, Buy Now deals (from the auctions on show).
func _fill_ticker(list: Array) -> void:
	if not is_instance_valid(_ticker):
		return
	var items: Array[String] = []
	var now := Time.get_unix_time_from_system()
	var sorted := list.duplicate()
	sorted.sort_custom(func(a, b): return _unix(a.get("endsAt")) < _unix(b.get("endsAt")))
	for a in sorted.slice(0, 4):
		items.append("⏱ ENDING SOON  %s  %s" % [str(a.get("name", "")).to_upper(), _left(_unix(a.get("endsAt")) - now)])
	var hot := list.filter(func(a): return int(a.get("bids", 0)) >= 2)
	hot.sort_custom(func(a, b): return int(a.get("bids", 0)) > int(b.get("bids", 0)))
	for a in hot.slice(0, 3):
		items.append("🔥 BIDDING WAR  %s  %d BIDS  %d K" % [str(a.get("name", "")).to_upper(), int(a.get("bids", 0)), int(a.get("highBid", 0))])
	for a in list.filter(func(x): return x.get("canBuyNow", false)).slice(0, 3):
		items.append("⚡ BUY NOW  %s  %d K" % [str(a.get("name", "")).to_upper(), int(a.get("buyNow", 0))])
	var legend := list.filter(func(x): return int(x.get("rarity", 1)) >= 5)
	for a in legend.slice(0, 2):
		items.append("★ LEGENDARY ON THE BLOCK  %s" % str(a.get("name", "")).to_upper())
	if items.is_empty():
		items.append("THE BLOCK IS QUIET  ·  LIST A CARD IN SELL AND BE THE FIRST")
	items.append("SALES PAY A %d%% FEE  ·  A LATE BID KEEPS THE AUCTION OPEN" % int(_rules().get("saleFeePct", 10)))
	var line := "      ✦      ".join(items) + "      ✦      "
	# Over and over, enough to fill the band while it scrolls one pass along: no gap
	_ticker.text = line
	var one := _ticker.get_minimum_size().x
	_ticker.text = line + line
	_ticker_w = _ticker.get_minimum_size().x - one   # (two minus one: trailing spaces and all)
	_ticker.text = line.repeat(int(ceil(1920.0 / maxf(1.0, _ticker_w))) + 1)
	_ticker.reset_size()
	_ticker_x = fmod(_ticker_x, maxf(1.0, _ticker_w))


## Gold dust drifting up through the room.
func _dust() -> void:
	var p := CPUParticles2D.new()
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.texture = CardTile._soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(980, 560)
	p.position = Vector2(960, 560)
	p.direction = Vector2(0.3, -1)
	p.spread = 35.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.42
	var ramp := Gradient.new()
	ramp.set_color(0, Color(HOT, 0.0))
	ramp.set_color(1, Color(HOT, 0.0))
	ramp.add_point(0.25, Color(HOT, 0.55))
	ramp.add_point(0.75, Color(1.0, 0.85, 0.5, 0.4))
	p.color_ramp = ramp
	add_child(p)


func _spotlight() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.82, 0.4, 0.32))
	g.set_color(1, Color(1.0, 0.82, 0.4, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.35)
	gt.fill_to = Vector2(0.5, 0.95)
	gt.width = 256
	gt.height = 256
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.position = Vector2(-20, -40)
	t.size = Vector2(640, 640)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.top_level = false
	return t


func _glass_panel(at: Vector2, sz: Vector2, border: Color) -> Control:
	var p := UI.glass(UI.panel(border, PANEL_BG), Color(0.02, 0.02, 0.06, 0.55))
	p.position = at
	p.size = sz
	add_child(p)
	return p


# ── Tabs and loading ───────────────────────────────────────────────────────

func _show(tab: String) -> void:
	_tab = tab
	_picked = {}
	for k in _tab_buttons:
		var b: Button = _tab_buttons[k]
		b.add_theme_color_override("font_color", HOT if k == tab else Color(0.75, 0.72, 0.85))
	var target: Button = _tab_buttons[tab]
	await get_tree().process_frame   # (the buttons have their sizes now)
	var tw := create_tween().set_parallel()
	tw.tween_property(_tab_line, "position:x", target.global_position.x + 12, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tab_line, "size:x", target.size.x - 24, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_build_filters()
	_load()


func _load(quiet := false) -> void:
	if _busy:
		return
	_busy = true
	_since_refresh = 0.0
	var spin: Label = null
	if not quiet:
		_clear(_grid_box)
		spin = UI.spinner(self, Vector2(650, 600), "OPENING THE BOOKS…")
	match _tab:
		"browse":
			var r := await Api.request("GET", "/api/auction/browse" + _query())
			_auctions = r.data.get("auctions", []) if r.ok and r.data is Dictionary else []
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
			_fill_ticker(_auctions)
		"sell":
			var r := await Api.request("GET", "/api/profile/inventory")
			_owned = r.data if r.ok and r.data is Array else []
			_owned.sort_custom(func(a, b): return _sort_rarest(a, b))
		"mine":
			var r := await Api.request("GET", "/api/auction/mine")
			_auctions = []
			if r.ok:
				for a in r.data.get("selling", []):
					a["_side"] = "selling"
					_auctions.append(a)
				for a in r.data.get("bidding", []):
					a["_side"] = "bidding"
					_auctions.append(a)
	if spin:
		spin.queue_free()
	_busy = false
	_render()


func _query() -> String:
	var q := []
	if _rarity > 0:
		q.append("rarity=%d" % _rarity)
	if _clan != "":
		q.append("clan=" + _clan.uri_encode())
	if _search != "":
		q.append("search=" + _search.uri_encode())
	return ("?" + "&".join(q)) if not q.is_empty() else ""


## Every REFRESH seconds: new bids flash on their lots; new or finished lots re-lay the grid.
func _refresh_live() -> void:
	_busy = true
	var fresh: Array = []
	if _tab == "browse":
		var r := await Api.request("GET", "/api/auction/browse" + _query())
		if r.ok and r.data is Dictionary:
			fresh = r.data.get("auctions", [])
	else:
		var r := await Api.request("GET", "/api/auction/mine")
		if r.ok:
			for a in r.data.get("selling", []):
				a["_side"] = "selling"
				fresh.append(a)
			for a in r.data.get("bidding", []):
				a["_side"] = "bidding"
				fresh.append(a)
	_busy = false
	if fresh.is_empty() and _auctions.is_empty():
		return
	var same := fresh.size() == _auctions.size()
	for i in mini(fresh.size(), _auctions.size()):
		if fresh[i].get("id") != _auctions[i].get("id") or str(fresh[i].get("status")) != str(_auctions[i].get("status")):
			same = false
	if not same:
		_auctions = fresh
		if _tab == "browse":
			_fill_ticker(_auctions)
		_render(false)
		return
	for i in fresh.size():
		var was: Dictionary = _auctions[i]
		var now: Dictionary = fresh[i]
		_auctions[i] = now
		if int(was.get("bids", 0)) != int(now.get("bids", 0)):
			_update_lot(now, true)
			if not _picked.is_empty() and _picked.get("id") == now.get("id"):
				_picked = now
				_render_side()
	if _tab == "browse":
		_fill_ticker(_auctions)


func _render(entrance := true) -> void:
	_clear(_grid_box)
	_lots.clear()
	_sell_tiles.clear()
	_countdowns.clear()
	var roots: Array = []
	match _tab:
		"browse":
			var list := _sorted(_auctions)
			if list.is_empty():
				_empty_state("NO LOTS ON THE BLOCK" if _rarity == 0 and _clan == "" and _search == "" else "NOTHING MATCHES",
					"Check back soon, or be the first: list a card in SELL.")
			else:
				roots = _lot_grid(list, "")
		"sell":
			var grid := _grid()
			for row in _owned:
				var card := CardDB.get_card(str(row.get("art_url", "")))
				if card.is_empty() or str(row.get("art_url", "")) in _info.get("prizes", []) or (_rarity and int(card.get("rarity", 1)) != _rarity) or (_clan != "" and str(card.get("clan", "")) != _clan) \
						or (_search != "" and not str(card.get("name", "")).to_lower().contains(_search.to_lower())):
					continue
				var tile := CardTile.make(card, LOT)
				tile.veteran = Game.veteran_tier(str(card.get("id", "")))
				var qty := int(row.get("quantity", 1))
				tile.count_badge = "×%d" % qty
				tile.selected = not _picked.is_empty() and _picked.get("id") == card.get("id")
				tile.pressed.connect(func(t):
					Sfx.play("flip", 1.1, -8.0)
					_pick(t.card))
				tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
				_sell_tiles[str(card.get("id", ""))] = tile
				grid.add_child(tile)
				roots.append(tile)
			if roots.is_empty():
				grid.queue_free()
				_empty_state("NOTHING TO SELL HERE", "Open packs in the Shop, or change the filters.")
		"mine":
			var selling := _auctions.filter(func(a): return a._side == "selling")
			var bidding := _auctions.filter(func(a): return a._side == "bidding")
			if selling.is_empty() and bidding.is_empty():
				_empty_state("YOUR BOOK IS EMPTY", "Sell a card, or bid on one in LIVE AUCTIONS.")
			if not selling.is_empty():
				roots.append_array(_lot_grid(selling, "SELLING"))
			if not bidding.is_empty():
				roots.append_array(_lot_grid(bidding, "BIDDING"))
	if entrance:
		CardTile.cascade(roots, 0.05)
	_render_side()


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 34)
	g.add_theme_constant_override("v_separation", 30)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.add_child(g)
	_grid_box.add_child(pad)
	return g


func _empty_state(head: String, text: String) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1180, 560)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	_grid_box.add_child(box)
	var h := UI.label(head, 44, Color(HOT, 0.85), true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)
	var t := UI.label(text, 22, UI.MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	UI.stagger(box.get_children(), 0.1, 0.1)


func _sorted(list: Array) -> Array:
	var out := list.duplicate()
	match _sort:
		"low":
			out.sort_custom(func(a, b): return _price_of(a) < _price_of(b))
		"high":
			out.sort_custom(func(a, b): return _price_of(a) > _price_of(b))
		"bids":
			out.sort_custom(func(a, b): return int(a.get("bids", 0)) > int(b.get("bids", 0)))
	return out   # ("ending": the server's order, soonest first)


static func _price_of(a: Dictionary) -> int:
	var p = a.get("highBid")
	return int(p) if p != null else int(a.get("startPrice", 0))


# ── Lots ────────────────────────────────────────────────────────────────

func _lot_grid(list: Array, heading: String) -> Array:
	if heading != "":
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var bar := ColorRect.new()
		bar.color = HOT
		bar.custom_minimum_size = Vector2(6, 34)
		h.add_child(bar)
		h.add_child(UI.label(heading, 30, HOT, true))
		h.add_child(UI.label("%d" % list.size(), 22, UI.MUTED, true))
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 16)
		pad.add_theme_constant_override("margin_top", 10)
		pad.add_child(h)
		_grid_box.add_child(pad)
	var grid := _grid()
	var roots: Array = []
	for a in list:
		var root := _lot(a)
		grid.add_child(root)
		roots.append(root)
	return roots


## A lot: the card, a price plate under it, and its tags (Buy Now, leading / outbid, the result stamp).
func _lot(a: Dictionary) -> Control:
	var card := CardDB.get_card(str(a.get("card", "")))
	var root := Control.new()
	root.custom_minimum_size = Vector2(LOT.x, LOT.y + PLATE_H + 8)
	var tile := CardTile.make(card, LOT)
	tile.veteran = 0
	tile.selected = not _picked.is_empty() and _picked.get("id") == a.get("id")
	tile.pressed.connect(func(_t):
		Sfx.play("flip", 1.1, -8.0)
		_pick(_find(a.get("id"))))
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	root.add_child(tile)
	var rc := UI.rarity_color(a.get("rarity", 1))
	var plate := Panel.new()
	plate.position = Vector2(0, LOT.y + 8)
	plate.size = Vector2(LOT.x, PLATE_H)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _plate_box(rc, tile.selected))
	root.add_child(plate)
	var price := UI.label("", 30, HOT, true)
	price.position = Vector2(12, 4)
	plate.add_child(price)
	var sub := UI.label("", 15, UI.MUTED)
	sub.position = Vector2(14, 44)
	plate.add_child(sub)
	var chip := Panel.new()   # (the time left, top right of the plate)
	chip.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.55), Color(UI.BLUE, 0.6), 1, 12))
	chip.position = Vector2(LOT.x - 98, 10)
	chip.size = Vector2(88, 28)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(chip)
	var timer := UI.label("", 16, UI.BLUE, true)
	timer.size = chip.size
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(timer)
	var tag := UI.label("", 15, UI.GREEN, true)
	tag.position = Vector2(14, 68)
	plate.add_child(tag)
	_lots[a.get("id")] = {"root": root, "tile": tile, "plate": plate, "price": price, "sub": sub, "chip": chip,
		"timer": timer, "tag": tag}
	_update_lot(a, false)
	return root


func _plate_box(rc: Color, selected: bool) -> UI.Plate:
	var sb := UI.box(Color(0.03, 0.025, 0.06, 0.92), HOT if selected else rc.darkened(0.25), 3 if selected else 2, 10)
	sb.shadow_color = Color(HOT if selected else rc, 0.4 if selected else 0.18)
	sb.shadow_size = 12 if selected else 6
	return sb


## Fill a lot from its auction; changed: a new bid just arrived (the price punches and flashes).
func _update_lot(a: Dictionary, changed: bool) -> void:
	var l: Dictionary = _lots.get(a.get("id"), {})
	if l.is_empty() or not is_instance_valid(l.root):
		return
	var status := str(a.get("status", "active"))
	var bids := int(a.get("bids", 0))
	var price: Label = l.price
	price.text = "%d" % _price_of(a)
	var sub: Label = l.sub
	sub.text = ("%d BID%s" % [bids, "" if bids == 1 else "S"]) if a.get("highBid") != null else "RESERVE"
	var timer: Label = l.timer
	var chip: Control = l.chip
	if status == "active":
		timer.text = _left(_unix(a.get("endsAt")) - Time.get_unix_time_from_system())
		_countdowns.append([timer, _unix(a.get("endsAt")), ""])
		chip.visible = true
	else:
		chip.visible = false
	var tag: Label = l.tag
	tag.text = ""
	if status == "active":
		if a.get("mine", false):
			tag.text = "★ YOUR LOT"
			tag.label_settings.font_color = HOT
		elif a.get("leading", false):
			tag.text = "▲ YOU'RE WINNING"
			tag.label_settings.font_color = UI.GREEN
		elif a.get("_side", "") == "bidding":
			tag.text = "▼ OUTBID"
			tag.label_settings.font_color = UI.RED
		elif a.get("canBuyNow", false):
			tag.text = "⚡ BUY NOW %d" % int(a.get("buyNow", 0))
			tag.label_settings.font_color = Color("7dffa8")
		else:
			tag.text = UI.RARITY_LABEL.get(int(a.get("rarity", 1)), "").to_upper()
			tag.label_settings.font_color = UI.rarity_color(a.get("rarity", 1))
	else:
		tag.text = UI.RARITY_LABEL.get(int(a.get("rarity", 1)), "").to_upper()
		tag.label_settings.font_color = UI.rarity_color(a.get("rarity", 1))
		_stamp_on(l.root, _result(a), _result_color(a), false)
	if a.get("canBuyNow", false) and status == "active" and not l.has("ribbon"):
		l["ribbon"] = _ribbon(l.root, "BUY NOW")
	elif not a.get("canBuyNow", false) and l.has("ribbon"):
		var rb: Control = l.ribbon
		if is_instance_valid(rb):
			var t := rb.create_tween()
			t.tween_property(rb, "modulate:a", 0.0, 0.3)
			t.tween_callback(rb.queue_free)
		l.erase("ribbon")
	if changed:
		_punch(price, 1.35)
		_flash(l.plate)
		_pop(l.root, "NEW BID", Vector2(LOT.x / 2, LOT.y - 20), HOT)
		Sfx.play("karat", 1.3, -10.0)


## A diagonal ribbon across a lot's top-right corner, with a light running along it.
func _ribbon(root: Control, text: String) -> Control:
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(LOT.x - 110, 0)
	clip.size = Vector2(110, 110)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.z_index = 3
	root.add_child(clip)
	var band := PanelContainer.new()
	var sb := UI.box(Color("16a34a"), Color("7dffa8"), 1, 0)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	band.add_theme_stylebox_override("panel", sb)
	band.custom_minimum_size = Vector2(170, 0)
	band.rotation_degrees = 45
	band.position = Vector2(14, -12)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, 15, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(l)
	clip.add_child(band)
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.45)
	shine.size = Vector2(18, 40)
	shine.position = Vector2(-30, -8)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(shine)
	var t := shine.create_tween().set_loops()
	t.tween_property(shine, "position:x", 200.0, 0.7).from(-30.0)
	t.tween_interval(1.8)
	return clip


func _find(id) -> Dictionary:
	for a in _auctions:
		if a.get("id") == id:
			return a
	return {}


func _pick(item: Dictionary) -> void:
	if item.is_empty():
		return
	_picked = item
	# The gold outline moves to it (no rebuild: the grid stays where it is)
	if _tab == "sell":
		for id in _sell_tiles:
			var t: CardTile = _sell_tiles[id]
			t.selected = id == str(item.get("id", ""))
	else:
		for id in _lots:
			var l: Dictionary = _lots[id]
			var sel: bool = id == item.get("id")
			(l.tile as CardTile).selected = sel
			(l.plate as Panel).add_theme_stylebox_override("panel", _plate_box(UI.rarity_color(_find(id).get("rarity", 1)), sel))
	_render_side()


# ── The side panel: the picked lot or card ──────────────────────────────────

func _render_side() -> void:
	_clear(_side)
	_price_big = null
	_bid_button = null
	_time_bar = null
	_countdowns = _countdowns.filter(func(cd): return is_instance_valid(cd[0]) and not (cd[0] as Node).has_meta("side"))
	if _picked.is_empty():
		_side_intro()
		return
	var card: Dictionary = _picked if _tab == "sell" else CardDB.get_card(str(_picked.get("card", "")))
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(560, 372)
	_side.add_child(stage)
	var tile := CardTile.make(card, Vector2(252, 356))
	tile.position = Vector2(154, 8)
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
	stage.add_child(tile)
	_float(tile)
	if _tab != "sell" and str(_picked.get("status", "active")) != "active":
		_stamp_on(stage, _result(_picked), _result_color(_picked), false, Vector2(280, 190))
	var name_l := UI.label(str(card.get("name", "?")), 34, Color.WHITE, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_l.custom_minimum_size = Vector2(560, 0)
	_side.add_child(name_l)
	var rarity := int(card.get("rarity", 1))
	var line: String = str(UI.RARITY_LABEL.get(rarity, "")).to_upper()
	if _tab != "sell":
		line += "   ·   SOLD BY %s" % (str(_picked.get("seller")).to_upper() if _picked.get("seller") else "A PLAYER WHO LEFT")
	var sub := UI.label(line, 18, UI.rarity_color(rarity), true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(560, 0)
	_side.add_child(sub)
	if _tab == "sell":
		_sell_panel(card)
	else:
		_auction_panel(_picked)
	UI.stagger(_side.get_children(), 0.0, 0.04)
	Sfx.play("flip", 0.9, -10.0)


func _side_intro() -> void:
	var head := ""
	var text := ""
	match _tab:
		"browse":
			head = "PICK A LOT"
			text = "Bid on it, or buy it outright at its Buy Now price before anyone bids. Once someone bids, Buy Now is gone and it's a bidding war: the top bid when time runs out wins, and the winner gets a mail.\n\nYour bid's Karat is held until someone outbids you: then it comes back and your mailbox says so. A bid in the last %d minutes keeps the auction open %d minutes more." % [_snipe_min(), _snipe_min()]
		"sell":
			var lim: Dictionary = _info.get("limits", {})
			head = "PICK A CARD TO SELL"
			text = "It leaves your collection while the auction runs (copies your decks use can't be sold). Set a reserve, the lowest bid you'll take, and if you like a Buy Now price anyone can pay to take it at once, until the first bid.\n\nAuctions run %d hours. Listing costs %d%% of the reserve (at least %d Karat), and a sale pays a %d%% fee.\n\nRunning: %d of %d.   Started today: %d of %d." % [
				int(_rules().get("durationHours", 24)), int(_rules().get("listingFeePct", 5)), int(_rules().get("listingFeeMin", 5)),
				int(_rules().get("saleFeePct", 10)), int(lim.get("activeUsed", 0)), int(lim.get("active", 0)), int(lim.get("todayUsed", 0)), int(lim.get("perDay", 0))]
		"mine":
			head = "YOUR BOOK"
			text = "Your lots and your bids, and how the last 7 days' went. Sales, wins and outbids also arrive in your mailbox."
	var h := UI.label(head, 36, HOT, true)
	h.custom_minimum_size = Vector2(560, 0)
	_side.add_child(h)
	var t := UI.label(text, 21, Color(0.86, 0.85, 0.95))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(560, 0)
	_side.add_child(t)
	if not _info.get("eligible", true):
		_side.add_child(_lock_box())
	UI.stagger(_side.get_children(), 0.0, 0.06)


func _lock_box() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.25, 0.02, 0.05, 0.6), UI.RED, 2, 10))
	var col := VBoxContainer.new()
	p.add_child(col)
	col.add_child(UI.label("🔒  TRADING LOCKED", 22, UI.RED, true))
	var t := UI.label(" ".join(_info.get("reasons", [])), 19, Color(1, 0.85, 0.85))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(520, 0)
	col.add_child(t)
	return p


func _auction_panel(a: Dictionary) -> void:
	var status := str(a.get("status", "active"))
	var bids := int(a.get("bids", 0))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_child(top)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	top.add_child(left)
	var label := "WINNING BID" if status == "sold" else ("TOP BID  ·  %d BID%s" % [bids, "" if bids == 1 else "S"]) if a.get("highBid") != null else "RESERVE  ·  NO BIDS YET"
	left.add_child(UI.label(label, 16, UI.MUTED, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	left.add_child(row)
	row.add_child(_karat_icon(60))
	_price_big = UI.label("0", 56, HOT, true)
	_price_big.label_settings.shadow_color = Color(1.0, 0.6, 0.1, 0.45)
	_price_big.label_settings.shadow_size = 10
	_price_big.label_settings.shadow_offset = Vector2.ZERO
	row.add_child(_price_big)
	UI.count_up(_price_big, int(_price_of(a) * 0.7), _price_of(a), 0.6)
	if a.get("canBuyNow", false):
		var bn := VBoxContainer.new()
		bn.add_theme_constant_override("separation", 0)
		top.add_child(bn)
		bn.add_child(UI.label("BUY NOW", 16, Color("7dffa8"), true))
		bn.add_child(UI.label("%d" % int(a.get("buyNow", 0)), 40, Color("7dffa8"), true))
	if status != "active":
		var r := UI.label("ENDED: " + _result(a), 24, _result_color(a), true)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.custom_minimum_size = Vector2(560, 0)
		_side.add_child(r)
		return
	# Time left: a ticking label and a bar running down (red in the last hours)
	var ends := UI.label("", 22, UI.BLUE, true)
	ends.set_meta("side", true)
	ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ends.custom_minimum_size = Vector2(560, 0)
	_side.add_child(ends)
	var end_at := _unix(a.get("endsAt"))
	_countdowns.append([ends, end_at, "ENDS IN  "])
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.08)
	track.custom_minimum_size = Vector2(520, 6)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_side.add_child(track)
	_time_bar = ColorRect.new()
	_time_bar.color = HOT
	_time_bar.size = Vector2(520, 6)
	_time_bar.set_meta("ends", end_at)
	_time_bar_full = float(_rules().get("durationHours", 24)) * 3600.0
	track.add_child(_time_bar)
	if a.get("buyNow") != null and not a.get("canBuyNow", false):
		_side.add_child(_small("Buy Now (%d) is gone: it has bids. It's a bidding war now." % int(a.get("buyNow", 0)), true))
	if a.get("mine", false):
		_side.add_child(_small("This is your lot.", true))
		if bids == 0:
			_side.add_child(_centered(UI.button("CANCEL AUCTION", _cancel.bind(a), Vector2(320, 56), UI.RED)))
			_side.add_child(_small("Takes it down and the card comes back. The listing fee isn't refunded.", true))
		else:
			_side.add_child(_small("It has bids, so it runs to the end.", true))
		return
	if a.get("leading", false):
		var w := UI.label("▲ YOU'RE THE TOP BIDDER", 26, UI.GREEN, true)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.custom_minimum_size = Vector2(560, 0)
		_side.add_child(w)
		_side.add_child(_small("If someone outbids you, your Karat comes back and your mailbox tells you.", true))
		return
	if a.get("minBid") == null:
		_side.add_child(_small("It has reached its highest price.", true))
		return
	if not _info.get("eligible", false):
		_side.add_child(_lock_box())
		return
	var lo := int(a.minBid)
	var hi := int(a.get("maxPrice", lo))
	var amount := _amount_box(lo, hi, lo)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 8)
	_side.add_child(chips)
	for q in [["MIN", 0.0], ["+10%", 0.10], ["+25%", 0.25], ["+50%", 0.5]]:
		var c := Button.new()
		c.text = q[0]
		c.custom_minimum_size = Vector2(96, 40)
		c.add_theme_font_size_override("font_size", 17)
		c.add_theme_stylebox_override("normal", UI.box(Color(0.1, 0.08, 0.02, 0.8), Color(HOT, 0.5), 1, 18))
		c.add_theme_stylebox_override("hover", UI.box(Color(0.2, 0.15, 0.03, 0.9), HOT, 1, 18))
		UI.juice(c)
		c.pressed.connect(func():
			Sfx.play("click", 1.3, -8.0)
			amount.value = clampi(int(ceil(lo * (1.0 + float(q[1])))), lo, hi)
			_punch(amount, 1.08))
		chips.add_child(c)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	_side.add_child(row2)
	row2.add_child(amount)
	_bid_button = UI.button("PLACE BID", func(): _bid(a, int(amount.value)), Vector2(220, 60), UI.GOLD)
	row2.add_child(_bid_button)
	_glow_pulse(_bid_button)
	_side.add_child(_small("At least %d Karat. You have %d." % [lo, int(_info.get("karat", 0))], true))
	if a.get("canBuyNow", false):
		var bn := UI.button("⚡  BUY NOW FOR %d" % int(a.buyNow), _buy_now.bind(a), Vector2(452, 60), UI.GREEN)
		_shine(bn)
		_side.add_child(_centered(bn))


func _sell_panel(card: Dictionary) -> void:
	var rarity := int(card.get("rarity", 1))
	var band: Dictionary = _rules().get("prices", {}).get(str(rarity), {"min": 10, "max": 150})
	var lo := int(band.get("min", 10))
	var hi := int(band.get("max", 150))
	if not _info.get("eligible", false):
		_side.add_child(_lock_box())
		return
	_side.add_child(_small("Prices for this rarity: %d to %d Karat" % [lo, hi], true))
	var reserve := _price_row("RESERVE", lo, hi, lo)
	var offer := CheckButton.new()
	offer.text = "BUY NOW"
	offer.add_theme_font_override("font", UI.font())
	offer.add_theme_font_size_override("font_size", 20)
	offer.add_theme_color_override("font_color", Color("7dffa8"))
	var buy := _price_row(offer, mini(hi, lo + 1), hi, mini(hi, lo * 3))
	buy.editable = false
	(buy.get_parent() as Control).modulate.a = 0.5
	# The receipt: what it costs now, what comes back
	var receipt := PanelContainer.new()
	var rsb := UI.box(Color(0.96, 0.93, 0.84, 0.95), Color(0.6, 0.5, 0.3), 1, 4)
	rsb.content_margin_left = 22
	rsb.content_margin_right = 22
	receipt.add_theme_stylebox_override("panel", rsb)
	receipt.custom_minimum_size = Vector2(520, 0)
	receipt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	receipt.rotation_degrees = -0.6
	_side.add_child(receipt)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	receipt.add_child(rows)
	var ink := Color(0.12, 0.1, 0.08)
	var receipt_line := func(what: String) -> Label:
		var h := HBoxContainer.new()
		var l := UI.label(what, 18, ink)
		l.label_settings.outline_size = 0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var v := UI.label("", 20, ink, true)
		v.label_settings.outline_size = 0
		h.add_child(v)
		rows.add_child(h)
		return v
	var fee_v: Label = receipt_line.call("Listing fee (now)")
	var keep_v: Label = receipt_line.call("Sold at the reserve, you get")
	var buy_v: Label = receipt_line.call("Bought now, you get")
	var keep := func(price: int) -> int:   # (what the seller gets after the sale fee)
		return price - ceili(price * float(_rules().get("saleFeePct", 10)) / 100.0)
	var update := func(_v: float = 0.0):
		var start := int(reserve.value)
		buy.min_value = mini(hi, start + 1)   # (Buy Now is above the reserve)
		var fee := maxi(int(_rules().get("listingFeeMin", 5)), ceili(start * float(_rules().get("listingFeePct", 5)) / 100.0))
		fee_v.text = "−%d" % fee
		keep_v.text = "+%d" % keep.call(start)
		buy_v.text = ("+%d" % keep.call(int(buy.value))) if offer.button_pressed else "—"
	reserve.value_changed.connect(update)
	buy.value_changed.connect(update)
	offer.toggled.connect(func(on: bool):
		Sfx.play("click", 1.2 if on else 0.9, -8.0)
		buy.editable = on
		(buy.get_parent() as Control).create_tween().tween_property(buy.get_parent(), "modulate:a", 1.0 if on else 0.5, 0.15)
		update.call())
	update.call()
	_side.add_child(_small("A %d%% fee comes off every sale. More if bids go higher." % int(_rules().get("saleFeePct", 10)), true))
	var list := UI.button("LIST IT ON THE BLOCK", func():
		_list_card(card, int(reserve.value), int(buy.value) if offer.button_pressed and reserve.value < hi else 0), Vector2(452, 62), UI.GOLD)
	_glow_pulse(list)
	_side.add_child(_centered(list))


## A price row: its label (text, or a control such as the Buy Now switch), a slider and the number.
func _price_row(head, lo: int, hi: int, start: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_child(row)
	if head is String:
		var l := UI.label(head, 20, Color.WHITE, true)
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
	else:
		(head as Control).custom_minimum_size = Vector2(130, 0)
		row.add_child(head)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = maxi(lo, hi)
	slider.step = 1
	slider.value = start
	slider.custom_minimum_size = Vector2(200, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.add_theme_stylebox_override("slider", UI.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 4))
	slider.add_theme_stylebox_override("grabber_area", UI.box(Color(HOT, 0.75), Color(0, 0, 0, 0), 0, 4))
	slider.add_theme_stylebox_override("grabber_area_highlight", UI.box(HOT, Color(0, 0, 0, 0), 0, 4))
	row.add_child(slider)
	var box := _amount_box(lo, hi, start)
	box.custom_minimum_size = Vector2(170, 52)
	row.add_child(box)
	slider.share(box)   # (they move together)
	return box


func _amount_box(lo: int, hi: int, start: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = maxi(lo, hi)
	s.step = 1
	s.value = start
	s.suffix = "K"
	s.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.custom_minimum_size = Vector2(200, 60)
	s.get_line_edit().add_theme_font_size_override("font_size", 26)
	s.get_line_edit().add_theme_color_override("font_color", HOT)
	return s


func _small(text: String, centred := false) -> Label:
	var l := UI.label(text, 18, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(560, 0)
	if centred:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _centered(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


# ── Asking the server, and the show when it answers ─────────────────────────

func _bid(a: Dictionary, amount: int) -> void:
	if _busy:
		return
	_busy = true
	var r := await Api.request("POST", "/api/auction/%d/bid" % int(a.id), {"amount": amount})
	_busy = false
	if not r.ok:
		Sfx.play("error", 1.0, -6.0)
		_shake(_side_panel, 8.0)
		UI.toast(self, r.error, UI.RED)
		return
	if is_instance_valid(_bid_button) and is_instance_valid(_price_big):
		_coins(_bid_button.get_global_rect().get_center(), _price_big.get_global_rect().get_center(), 14)
	Sfx.play("slam", 1.5, -10.0)
	_set_karat(int(r.data.get("karat", 0)), true)
	UI.toast(self, "You're the top bidder on %s." % str(a.get("name", "")), UI.GREEN)
	var updated: Dictionary = r.data.get("auction", {})
	for i in _auctions.size():
		if _auctions[i].get("id") == updated.get("id"):
			if _auctions[i].has("_side"):
				updated["_side"] = _auctions[i]._side
			_auctions[i] = updated
	await get_tree().create_timer(0.45).timeout
	_picked = updated
	_update_lot(updated, true)
	_render_side()
	_fill_ticker(_auctions)


func _buy_now(a: Dictionary) -> void:
	UI.dialog(self, "BUY %s NOW?" % str(a.get("name", "")).to_upper(),
		"%d Karat, and it's yours at once. You have %d." % [int(a.buyNow), int(_info.get("karat", 0))],
		[["BUY IT", func():
			if _busy:
				return
			_busy = true
			var r := await Api.request("POST", "/api/auction/%d/buy" % int(a.id))
			_busy = false
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				_load()
				return
			_set_karat(int(r.data.get("karat", 0)), true)
			_sold_show(a, "SOLD", UI.GREEN)
			UI.toast(self, "%s is yours. It's in your collection." % str(a.get("name", "")), UI.GREEN)
			await get_tree().create_timer(1.6).timeout
			_picked = {}
			_load(), UI.GREEN], ["CANCEL", func(): pass]])


## The lot's card is stamped (SOLD, LISTED…): a slam, a shake, coins.
func _sold_show(a: Dictionary, text: String, color: Color) -> void:
	var l: Dictionary = _lots.get(a.get("id"), {})
	if not l.is_empty() and is_instance_valid(l.root):
		_stamp_on(l.root, text, color, true)
	if _side.get_child_count() > 0:
		_stamp_on(_side.get_child(0), text, color, true, Vector2(280, 190))
	_shake(self, 10.0)
	_coins(_balance.get_global_rect().get_center(), Vector2(1580, 380), 18)


## price: the reserve; buy_now: 0 = none
func _list_card(card: Dictionary, price: int, buy_now: int) -> void:
	if _busy:
		return
	var text := "It leaves your collection for %d hours, with a reserve of %d Karat%s. The listing fee isn't refunded." % [
		int(_rules().get("durationHours", 24)), price, (" and Buy Now at %d" % buy_now) if buy_now > 0 else ""]
	UI.dialog(self, "LIST %s?" % str(card.get("name", "")).to_upper(), text,
		[["LIST IT", func(): _do_list(card, price, buy_now), UI.GOLD], ["CANCEL", func(): pass]])


func _do_list(card: Dictionary, price: int, buy_now: int) -> void:
	_busy = true
	var body := {"card": str(card.get("id", "")), "startPrice": price}
	if buy_now > 0:
		body["buyNow"] = buy_now
	var r := await Api.request("POST", "/api/auction/list", body)
	_busy = false
	if not r.ok:
		Sfx.play("error", 1.0, -6.0)
		_shake(_side_panel, 8.0)
		UI.toast(self, r.error, UI.RED)
		return
	_set_karat(int(r.data.get("karat", 0)), true)
	var lim: Dictionary = _info.get("limits", {})
	lim["activeUsed"] = int(lim.get("activeUsed", 0)) + 1
	lim["todayUsed"] = int(lim.get("todayUsed", 0)) + 1
	if _side.get_child_count() > 0:
		_stamp_on(_side.get_child(0), "LISTED", HOT, true, Vector2(280, 190))
	Sfx.play("whoosh", 0.9, -8.0)
	UI.toast(self, "%s is on the block." % str(card.get("name", "")), UI.GREEN)
	await get_tree().create_timer(1.3).timeout
	_show("mine")


func _cancel(a: Dictionary) -> void:
	UI.dialog(self, "CANCEL THE AUCTION?", "%s comes back to your collection. The listing fee isn't refunded." % str(a.get("name", "")),
		[["TAKE IT DOWN", func():
			var r := await Api.request("POST", "/api/auction/%d/cancel" % int(a.id))
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
				return
			var lim: Dictionary = _info.get("limits", {})
			lim["activeUsed"] = maxi(0, int(lim.get("activeUsed", 0)) - 1)
			_sold_show(a, "WITHDRAWN", UI.MUTED)
			UI.toast(self, "Auction cancelled: the card is back.", UI.BLUE)
			await get_tree().create_timer(1.2).timeout
			_picked = {}
			_load(), UI.RED], ["CANCEL", func(): pass]])


func _set_karat(k: int, animate: bool) -> void:
	var was := _karat_shown
	_info["karat"] = k
	Game.player.karat = k
	_karat_shown = k
	if animate and was != k:
		UI.count_up(_balance, was, k, 0.7, "%d", "karat")
		_punch(_balance, 1.25)
		_pop(_balance.get_parent().get_parent() as Control, ("%+d" % (k - was)), Vector2(150, 96), UI.GREEN if k > was else UI.RED)
	else:
		_balance.text = "%d" % k


# ── Effects ───────────────────────────────────────────────────────────────

## A quick swell and settle.
func _punch(c: Control, amount: float) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2.ONE * amount, 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash(c: CanvasItem) -> void:
	if not is_instance_valid(c):
		return
	var t := c.create_tween()
	t.tween_property(c, "modulate", Color(1.9, 1.6, 0.9), 0.08)
	t.tween_property(c, "modulate", Color.WHITE, 0.55)


## Words floating up from a point and fading (NEW BID, +250).
func _pop(parent: Control, text: String, at: Vector2, color: Color) -> void:
	if not is_instance_valid(parent):
		return
	var l := UI.label(text, 24, color, true)
	l.z_index = 20
	parent.add_child(l)
	l.reset_size()
	l.position = at - l.size / 2
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ONE * 0.6
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - 46, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)


## A rubber stamp slammed on (SOLD, WON, OUTBID…); slam: it lands now, with a thud.
func _stamp_on(parent: Node, text: String, color: Color, slam: bool, centre := Vector2(-1, -1)) -> void:
	if not is_instance_valid(parent) or text == "":
		return
	var p := PanelContainer.new()
	var sb := UI.box(Color(color, 0.12), color, 4, 6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, 34, color, true)
	p.add_child(l)
	p.z_index = 10
	parent.add_child(p)
	p.reset_size()
	var c := centre if centre.x >= 0 else Vector2(LOT.x / 2, LOT.y / 2)
	p.position = c - p.size / 2
	p.pivot_offset = p.size / 2
	p.rotation_degrees = -14.0
	if slam:
		p.scale = Vector2.ONE * 2.6
		p.modulate.a = 0.0
		var t := p.create_tween().set_parallel()
		t.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(p, "modulate:a", 1.0, 0.1)
		t.chain().tween_callback(func(): Sfx.play("slam", 0.85, -4.0))
	else:
		p.modulate.a = 0.85


func _shake(c: Control, strength: float) -> void:
	var home := c.position
	var t := c.create_tween()
	for i in 6:
		var k := strength * (1.0 - i / 6.0)
		t.tween_property(c, "position", home + Vector2(randf_range(-k, k), randf_range(-k, k)), 0.035)
	t.tween_property(c, "position", home, 0.05)


## Gold coins flying from one point to another along an arc (Karat changing hands).
func _coins(from: Vector2, to: Vector2, n: int) -> void:
	for i in n:
		var c := _coin(18)
		c.top_level = true
		c.z_index = 50
		add_child(c)
		c.size = Vector2(18, 18)
		c.global_position = from + Vector2(randf_range(-30, 30), randf_range(-14, 14))
		var start := c.global_position
		var lift := Vector2(randf_range(-120, 120), randf_range(-220, -120))
		var t := c.create_tween()
		t.tween_interval(i * 0.025)
		t.tween_method(func(x: float):
			var a := start.lerp(start + lift, x)
			var b := (start + lift).lerp(to, x)
			c.global_position = a.lerp(b, x), 0.0, 1.0, 0.55 + randf() * 0.2).set_trans(Tween.TRANS_SINE)
		t.tween_property(c, "modulate:a", 0.0, 0.12)
		t.tween_callback(c.queue_free)
		if i % 4 == 0:
			t.tween_callback(func(): Sfx.play("karat", randf_range(1.2, 1.5), -14.0)).set_delay(0.0)


## A button that breathes a gold glow (the main action on the panel).
func _glow_pulse(b: Button) -> void:
	var t := b.create_tween().set_loops()
	t.tween_property(b, "modulate", Color(1.18, 1.1, 0.95), 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)


## A light sweeping across a button now and then.
func _shine(b: Button) -> void:
	b.clip_contents = true
	var s := ColorRect.new()
	s.color = Color(1, 1, 1, 0.3)
	s.size = Vector2(36, 90)
	s.rotation_degrees = 20
	s.position = Vector2(-80, -14)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(s)
	var t := s.create_tween().set_loops()
	t.tween_property(s, "position:x", 520.0, 0.6).from(-80.0)
	t.tween_interval(1.6)


## The picked card hovers gently in its spotlight.
func _float(c: Control) -> void:
	var y := c.position.y
	var t := c.create_tween().set_loops()
	t.tween_property(c, "position:y", y - 7.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(c, "position:y", y + 3.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ── Filters (lots and your cards) ───────────────────────────────────────────

func _build_filters() -> void:
	_clear(_filters)
	if _tab == "mine":
		return
	for r in [0, 1, 2, 3, 4, 5]:
		var b := Button.new()
		b.text = "ALL" if r == 0 else UI.RARITY_LABEL[r].to_upper()
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 16)
		var col: Color = HOT if r == 0 else UI.rarity_color(r)
		var on: bool = _rarity == r
		b.add_theme_color_override("font_color", Color.BLACK if on else col)
		b.add_theme_color_override("font_hover_color", Color.BLACK if on else Color.WHITE)
		b.add_theme_stylebox_override("normal", UI.box(col if on else Color(0, 0, 0, 0.45), col, 2, 22))
		b.add_theme_stylebox_override("hover", UI.box(col if on else Color(col, 0.25), col, 2, 22))
		UI.juice(b)
		b.pressed.connect(func():
			Sfx.play("click", 1.2, -8.0)
			_rarity = r
			_build_filters()
			_refilter())
		_filters.add_child(b)
	var pick := OptionButton.new()
	pick.add_item("ALL CLANS")
	pick.set_item_metadata(0, "")
	for c in CardDB.clans():
		pick.add_item(str(c.name).to_upper())
		pick.set_item_metadata(pick.item_count - 1, c.id)
		if c.id == _clan:
			pick.select(pick.item_count - 1)
	pick.custom_minimum_size = Vector2(170, 44)
	pick.add_theme_font_size_override("font_size", 16)
	pick.item_selected.connect(func(i):
		_clan = str(pick.get_item_metadata(i))
		_refilter())
	_filters.add_child(pick)
	if _tab == "browse":
		var sort := OptionButton.new()
		for s in [["ending", "ENDING SOONEST"], ["low", "PRICE: LOW"], ["high", "PRICE: HIGH"], ["bids", "MOST BIDS"]]:
			sort.add_item(s[1])
			sort.set_item_metadata(sort.item_count - 1, s[0])
			if s[0] == _sort:
				sort.select(sort.item_count - 1)
		sort.custom_minimum_size = Vector2(190, 44)
		sort.add_theme_font_size_override("font_size", 16)
		sort.item_selected.connect(func(i):
			_sort = str(sort.get_item_metadata(i))
			_render())
		_filters.add_child(sort)
	var search := LineEdit.new()
	search.placeholder_text = "Search by name…"
	search.text = _search
	search.custom_minimum_size = Vector2(190 if _tab == "browse" else 300, 44)
	search.add_theme_font_size_override("font_size", 17)
	search.text_submitted.connect(func(t):
		_search = t.strip_edges()
		_refilter())
	_filters.add_child(search)


func _refilter() -> void:
	_picked = {}
	if _tab == "browse":
		_load()   # (the server filters running auctions)
	else:
		_render()


# ── Helpers ───────────────────────────────────────────────────────────────

func _rules() -> Dictionary:
	return _info.get("rules", {})


func _snipe_min() -> int:
	return maxi(1, int(_rules().get("snipeSeconds", 120)) / 60)


static func _unix(iso) -> float:
	if not (iso is String) or iso.length() < 19:
		return 0.0
	return float(Time.get_unix_time_from_datetime_string(iso.left(19)))   # (the server's times are UTC)


## Time left: "2h 14m", "3m 05s", "ending…".
static func _left(secs: float) -> String:
	if secs <= 0:
		return "ENDING…"
	var s := int(secs)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dm %02ds" % [s / 60, s % 60]


static func _result(a: Dictionary) -> String:
	match str(a.get("status", "")):
		"sold":
			if a.get("_side", "") == "bidding":
				return "WON" if a.get("won", false) else "LOST"
			return "SOLD"
		"unsold":
			return "NO BIDS"
		"cancelled":
			return "WITHDRAWN"
	return ""


static func _result_color(a: Dictionary) -> Color:
	match _result(a):
		"SOLD":
			return UI.GREEN
		"WON":
			return Color("ffcf4a")
		"LOST":
			return UI.RED
	return UI.MUTED


static func _sort_rarest(a: Dictionary, b: Dictionary) -> bool:
	var ca := CardDB.get_card(str(a.get("art_url", "")))
	var cb := CardDB.get_card(str(b.get("art_url", "")))
	var ra := int(ca.get("rarity", 1))
	var rb := int(cb.get("rarity", 1))
	if ra != rb:
		return ra > rb
	return str(ca.get("name", "")) < str(cb.get("name", ""))


static func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()
