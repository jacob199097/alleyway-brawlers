extends Screen
## The auction house: players sell cards to each other for Karat (backend/economy/auction.js, which
## decides everything: prices, fees, who may trade; this screen shows it and asks).
##   BROWSE       running auctions, soonest to end first: pick one, bid (or Buy Now, before the first bid)
##   SELL         your cards: pick one, set a reserve (the lowest bid) and maybe a Buy Now price, list it
##   MY AUCTIONS  what you're selling and bidding on (and the last 7 days' results)

const ROW := Vector2(880, 118)

var _tab := "browse"
var _tabs := {}
var _info := {}                  # GET /api/auction: eligible, reasons, karat, limits, rules
var _auctions: Array = []        # the list on show (browse) or yours (mine)
var _owned: Array = []           # GET /api/profile/inventory rows (sell)
var _picked := {}                # the auction or card picked on the left
var _balance: Label
var _list: VBoxContainer
var _side: VBoxContainer
var _filters: HBoxContainer
var _note: Label
var _rarity := 0                 # browse filter: 0 = any
var _clan := ""
var _search := ""
var _countdowns: Array = []      # [[Label, ends_at unix, prefix]]: the time left, ticking
var _busy := false


func _ready() -> void:
	back_to = "shop"
	UI.background(self, "menu_background.jpg", 0.7)
	Game.play_menu_music()
	UI.title(self, "AUCTION HOUSE")
	_balance = UI.label("", 26, UI.GOLD, true)
	_balance.size = Vector2(1920, 34)
	_balance.position = Vector2(0, 96)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_balance)
	UI.back_button(self, func(): Game.go("shop"))
	if not needs_server("The auction house"):
		return
	_note = UI.label("", 20, UI.RED)
	_note.position = Vector2(40, 136)
	_note.size = Vector2(1840, 30)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 8)
	_filters.position = Vector2(40, 172)
	add_child(_filters)
	var lp := UI.glass(UI.panel(Color(UI.GOLD, 0.5), Color(0.06, 0.05, 0.12, 0.95)), Color(0.03, 0.03, 0.1, 0.6))
	lp.position = Vector2(40, 236)
	lp.size = Vector2(940, 724)
	add_child(lp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var rp := UI.glass(UI.panel(Color(UI.GOLD, 0.5), Color(0.06, 0.05, 0.12, 0.95)), Color(0.03, 0.03, 0.1, 0.6))
	rp.position = Vector2(1000, 236)
	rp.size = Vector2(880, 724)
	add_child(rp)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 12)
	rp.add_child(_side)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	tabs.position = Vector2(960 - 466, 990)
	add_child(tabs)
	for t in [["browse", "BROWSE"], ["sell", "SELL"], ["mine", "MY AUCTIONS"]]:
		var tb := UI.button(t[1], _show.bind(t[0]), Vector2(300, 64), UI.GOLD)
		tabs.add_child(tb)
		_tabs[t[0]] = tb
	var r := await Api.request("GET", "/api/auction")
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	_info = r.data
	_set_karat(int(_info.get("karat", 0)))
	if not _info.get("eligible", false):
		_note.text = "To bid or sell: " + " ".join(_info.get("reasons", []))
	_show("browse")


func _process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	for cd in _countdowns:
		if is_instance_valid(cd[0]):
			(cd[0] as Label).text = str(cd[2]) + _left(float(cd[1]) - now)


func _set_karat(k: int) -> void:
	_info["karat"] = k
	Game.player.karat = k
	_balance.text = "%d KARAT" % k


func _show(tab: String) -> void:
	_tab = tab
	_picked = {}
	for k in _tabs:
		(_tabs[k] as Button).modulate = Color.WHITE if k == tab else Color(1, 1, 1, 0.55)
	_build_filters()
	_load()


func _load() -> void:
	if _busy:
		return
	_busy = true
	_clear(_list)
	_clear(_side)
	var spin := UI.spinner(self, Vector2(510, 560))
	match _tab:
		"browse":
			var q := []
			if _rarity > 0:
				q.append("rarity=%d" % _rarity)
			if _clan != "":
				q.append("clan=" + _clan.uri_encode())
			if _search != "":
				q.append("search=" + _search.uri_encode())
			var r := await Api.request("GET", "/api/auction/browse" + ("?" + "&".join(q) if not q.is_empty() else ""))
			_auctions = r.data.get("auctions", []) if r.ok else []
			if not r.ok:
				UI.toast(self, r.error, UI.RED)
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
	spin.queue_free()
	_busy = false
	_render()


func _render() -> void:
	_clear(_list)
	_countdowns.clear()
	var rows := []
	match _tab:
		"browse":
			for a in _auctions:
				rows.append(_auction_row(a))
			if _auctions.is_empty():
				_list.add_child(UI.label("No auctions running%s." % (" that match" if _rarity or _clan != "" or _search != "" else ""), 24, UI.MUTED))
		"sell":
			for row in _owned:
				var card := CardDB.get_card(str(row.get("art_url", "")))
				if card.is_empty() or (_rarity and int(card.get("rarity", 1)) != _rarity) or (_clan != "" and str(card.get("clan", "")) != _clan) \
						or (_search != "" and not str(card.get("name", "")).to_lower().contains(_search.to_lower())):
					continue
				rows.append(_card_row(card, int(row.get("quantity", 1))))
			if rows.is_empty():
				_list.add_child(UI.label("No cards here to sell.", 24, UI.MUTED))
		"mine":
			var heading := ""
			for a in _auctions:
				if a._side != heading:
					heading = a._side
					_list.add_child(UI.label("SELLING" if heading == "selling" else "BIDDING", 26, UI.GOLD, true))
				rows.append(_auction_row(a))
			if _auctions.is_empty():
				_list.add_child(UI.label("Nothing yet: sell a card, or bid on one in BROWSE.", 24, UI.MUTED))
	UI.stagger(rows, 0.0, 0.03)
	_render_side()


# ── The list ─────────────────────────────────────────────────────────────────

func _row_button(selected: bool, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = ROW
	b.add_theme_stylebox_override("normal", UI.box(Color("16141f"), UI.GOLD if selected else accent.darkened(0.35), 2, 8))
	b.add_theme_stylebox_override("hover", UI.box(Color("201c2c"), UI.GOLD, 2, 8))
	_list.add_child(b)
	return b


func _thumb(parent: Control, card: Dictionary) -> void:
	var t := UI.texture_rect(UI.card_art(card), Vector2(70, 99))
	t.position = Vector2(12, 9)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)


func _put(parent: Control, text: String, at: Vector2, size: int, color: Color, heading := false, width := 0.0) -> Label:
	var l := UI.label(text, size, color, heading)
	l.position = at
	if width > 0:
		l.size = Vector2(width, size + 10)
		l.clip_text = true
	parent.add_child(l)
	return l


func _auction_row(a: Dictionary) -> Button:
	var card := CardDB.get_card(str(a.get("card", "")))
	var sel: bool = not _picked.is_empty() and _picked.get("id") == a.get("id")
	var b := _row_button(sel, UI.rarity_color(a.get("rarity", 1)))
	_thumb(b, card)
	_put(b, str(a.get("name", card.get("name", "?"))), Vector2(100, 10), 24, Color.WHITE, true, 470)
	_put(b, "%s  ·  %s" % [UI.RARITY_LABEL.get(int(a.get("rarity", 1)), ""), "by " + str(a.get("seller")) if a.get("seller") else "(left the game)"],
		Vector2(100, 46), 18, UI.rarity_color(a.get("rarity", 1)), false, 470)
	var price = a.get("highBid")
	var bids := int(a.get("bids", 0))
	_put(b, "%d" % int(price if price != null else a.get("startPrice", 0)), Vector2(600, 14), 30, UI.GOLD, true)
	_put(b, ("%d bid%s" % [bids, "" if bids == 1 else "s"]) if price != null else "reserve", Vector2(600, 56), 16, UI.MUTED)
	if a.get("canBuyNow", false):
		_put(b, "BUY NOW  %d" % int(a.get("buyNow", 0)), Vector2(100, 80), 17, UI.GREEN, true)
	var status := str(a.get("status", "active"))
	var state := _put(b, "", Vector2(740, 16), 18, UI.BLUE, true, 130)
	if status == "active":
		_countdowns.append([state, _unix(a.get("endsAt")), ""])
		state.text = _left(_unix(a.get("endsAt")) - Time.get_unix_time_from_system())
	else:
		state.text = _result(a)
		state.label_settings.font_color = UI.GREEN if _result(a) in ["SOLD", "WON"] else UI.MUTED
	var tag := ""
	var tag_color := UI.GREEN
	if status == "active" and a.get("mine", false):
		tag = "YOURS"
		tag_color = UI.GOLD
	elif status == "active" and a.get("leading", false):
		tag = "LEADING"
	elif status == "active" and a.get("_side", "") == "bidding":
		tag = "OUTBID"
		tag_color = UI.RED
	if tag != "":
		_put(b, tag, Vector2(740, 60), 18, tag_color, true)
	b.pressed.connect(func():
		Sfx.play("click")
		_picked = a
		_render())
	return b


func _card_row(card: Dictionary, quantity: int) -> Button:
	var sel: bool = not _picked.is_empty() and _picked.get("id") == card.get("id")
	var b := _row_button(sel, UI.rarity_color(card.get("rarity", 1)))
	_thumb(b, card)
	_put(b, str(card.get("name", "?")), Vector2(100, 14), 24, Color.WHITE, true, 560)
	_put(b, "%s  ·  %s" % [UI.RARITY_LABEL.get(int(card.get("rarity", 1)), ""), str(card.get("clanName", "")).to_upper()],
		Vector2(100, 52), 18, UI.rarity_color(card.get("rarity", 1)), false, 560)
	_put(b, "×%d" % quantity, Vector2(760, 34), 30, UI.GOLD, true)
	b.pressed.connect(func():
		Sfx.play("click")
		_picked = card
		_render())
	return b


# ── The side panel: the picked auction or card ────────────────────────────────

func _render_side() -> void:
	_clear(_side)
	if _picked.is_empty():
		var help := ""
		match _tab:
			"browse":
				help = "Pick an auction to bid on it, or buy it outright at its Buy Now price before anyone bids. Once someone bids, Buy Now is gone and it's a bidding war: the top bid when time runs out wins, and the winner gets a mail.\n\nYour bid's Karat is held until someone outbids you: then it comes back and your mailbox says so. A bid in the last %d minutes keeps the auction open %d minutes more." % [_snipe_min(), _snipe_min()]
			"sell":
				var lim: Dictionary = _info.get("limits", {})
				help = "Pick a card to sell. It leaves your collection while the auction runs (copies your decks use can't be sold). Set a reserve (the lowest bid you'll take) and, if you like, a Buy Now price anyone can pay to take it at once, until the first bid.\n\nAuctions run %d hours. Listing costs %d%% of the reserve (at least %d Karat), and a sale pays a %d%% fee.\n\nYou can run %d auctions at once and start %d a day (%d running, %d started today)." % [
					int(_rules().get("durationHours", 24)), int(_rules().get("listingFeePct", 5)), int(_rules().get("listingFeeMin", 5)),
					int(_rules().get("saleFeePct", 10)), int(lim.get("active", 0)), int(lim.get("perDay", 0)), int(lim.get("activeUsed", 0)), int(lim.get("todayUsed", 0))]
			"mine":
				help = "Your auctions and bids, and how the last 7 days' ended. Sales, wins and outbids also arrive in your mailbox."
		var l := UI.label(help, 22, Color(0.85, 0.85, 0.95))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(830, 0)
		_side.add_child(l)
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	_side.add_child(top)
	var card: Dictionary = _picked if _tab == "sell" else CardDB.get_card(str(_picked.get("card", "")))
	var tile := CardTile.make(card, Vector2(250, 353))
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
	top.add_child(tile)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(540, 0)
	top.add_child(col)
	var heading := UI.label(str(card.get("name", "?")), 32, Color.WHITE, true)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(540, 0)
	col.add_child(heading)
	var rarity := int(card.get("rarity", 1))
	col.add_child(UI.label(UI.RARITY_LABEL.get(rarity, ""), 20, UI.rarity_color(rarity), true))
	if _tab == "sell":
		_sell_panel(col, card)
	else:
		_auction_panel(col, _picked)
	UI.stagger(_side.get_children(), 0.0, 0.05)


func _auction_panel(col: VBoxContainer, a: Dictionary) -> void:
	col.add_child(UI.label("Seller: %s" % (a.get("seller") if a.get("seller") else "(left the game)"), 20, UI.MUTED))
	var price = a.get("highBid")
	var bids := int(a.get("bids", 0))
	if price != null:
		col.add_child(UI.label("Top bid: %d Karat  (%d bid%s)" % [int(price), bids, "" if bids == 1 else "s"], 24, UI.GOLD, true))
	else:
		col.add_child(UI.label("Reserve: %d Karat  (no bids yet)" % int(a.get("startPrice", 0)), 24, UI.GOLD, true))
	if a.get("canBuyNow", false):
		col.add_child(UI.label("Buy Now: %d Karat" % int(a.get("buyNow", 0)), 24, UI.GREEN, true))
	elif a.get("buyNow") != null and str(a.get("status", "")) == "active":
		col.add_child(_small("Buy Now (%d Karat) is gone: it has bids." % int(a.get("buyNow", 0))))
	col.add_child(UI.label("Highest price: %d Karat" % int(a.get("maxPrice", 0)), 18, UI.MUTED))
	var status := str(a.get("status", "active"))
	if status != "active":
		col.add_child(UI.label("Ended: " + _result(a), 24, UI.BLUE, true))
		return
	var ends := UI.label("", 22, UI.BLUE, true)
	col.add_child(ends)
	var end_at := _unix(a.get("endsAt"))
	ends.text = "Ends in " + _left(end_at - Time.get_unix_time_from_system())
	_countdowns.append([ends, end_at, "Ends in "])
	if a.get("mine", false):
		col.add_child(UI.label("This is your auction.", 22, UI.GOLD))
		if bids == 0:
			col.add_child(UI.button("CANCEL AUCTION", _cancel.bind(a), Vector2(300, 56), UI.RED))
			col.add_child(_small("Takes it down and the card comes back. The listing fee isn't refunded."))
		else:
			col.add_child(_small("It has bids, so it runs to the end."))
		return
	if a.get("leading", false):
		col.add_child(UI.label("You're the top bidder.", 22, UI.GREEN, true))
		return
	if a.get("minBid") == null:
		col.add_child(UI.label("It has reached its highest price.", 22, UI.MUTED))
		return
	if not _info.get("eligible", false):
		col.add_child(_small("You can't bid yet: " + " ".join(_info.get("reasons", []))))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var amount := _amount_box(int(a.minBid), int(a.get("maxPrice", a.minBid)), int(a.minBid))
	row.add_child(amount)
	row.add_child(UI.button("BID", func(): _bid(a, int(amount.value)), Vector2(160, 56), UI.GOLD))
	col.add_child(_small("At least %d Karat. You have %d." % [int(a.minBid), int(_info.get("karat", 0))]))
	if a.get("canBuyNow", false):
		col.add_child(UI.button("BUY NOW FOR %d" % int(a.buyNow), _buy_now.bind(a), Vector2(360, 56), UI.GREEN))
		col.add_child(_small("Takes it at once and ends the auction. Once anyone bids, Buy Now is gone."))


func _sell_panel(col: VBoxContainer, card: Dictionary) -> void:
	var rarity := int(card.get("rarity", 1))
	var band: Dictionary = _rules().get("prices", {}).get(str(rarity), {"min": 10, "max": 150})
	var lo := int(band.get("min", 10))
	var hi := int(band.get("max", 150))
	col.add_child(UI.label("Prices for this rarity: %d to %d Karat" % [lo, hi], 20, UI.MUTED))
	if not _info.get("eligible", false):
		col.add_child(_small("You can't sell yet: " + " ".join(_info.get("reasons", []))))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	grid.add_child(UI.label("Reserve", 22, Color.WHITE, true))
	var amount := _amount_box(lo, hi, lo)
	grid.add_child(amount)
	var offer := CheckBox.new()
	offer.text = "Buy Now"
	offer.add_theme_font_size_override("font_size", 20)
	grid.add_child(offer)
	var buy := _amount_box(mini(hi, lo + 1), hi, mini(hi, lo * 3))
	buy.editable = false
	buy.modulate.a = 0.45
	grid.add_child(buy)
	var fees := UI.label("", 20, Color(0.85, 0.85, 0.95))
	fees.autowrap_mode = TextServer.AUTOWRAP_WORD
	fees.custom_minimum_size = Vector2(540, 0)
	col.add_child(fees)
	var keep := func(price: int) -> int:   # (what the seller gets after the sale fee)
		return price - ceili(price * float(_rules().get("saleFeePct", 10)) / 100.0)
	var show_fees := func(_v: float = 0.0):
		var start := int(amount.value)
		buy.min_value = mini(hi, start + 1)   # (Buy Now is above the reserve)
		var fee := maxi(int(_rules().get("listingFeeMin", 5)), ceili(start * float(_rules().get("listingFeePct", 5)) / 100.0))
		fees.text = "Listing fee: %d Karat now.\nIf the top bid is the reserve (%d), you get %d after the %d%% fee: more if bids go higher." % [
			fee, start, keep.call(start), int(_rules().get("saleFeePct", 10))]
		if offer.button_pressed:
			fees.text += "\nIf someone buys it now (%d), you get %d." % [int(buy.value), keep.call(int(buy.value))]
	amount.value_changed.connect(show_fees)
	buy.value_changed.connect(show_fees)
	offer.toggled.connect(func(on: bool):
		buy.editable = on
		buy.modulate.a = 1.0 if on else 0.45
		show_fees.call())
	show_fees.call()
	col.add_child(UI.button("LIST FOR AUCTION", func():
		_list_card(card, int(amount.value), int(buy.value) if offer.button_pressed and amount.value < hi else 0), Vector2(320, 60), UI.GOLD))
	col.add_child(_small("Runs %d hours. No bids: the card comes back." % int(_rules().get("durationHours", 24))))


func _amount_box(lo: int, hi: int, start: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = maxi(lo, hi)
	s.step = 1
	s.value = start
	s.suffix = "Karat"
	s.custom_minimum_size = Vector2(260, 56)
	s.get_line_edit().add_theme_font_size_override("font_size", 24)
	return s


func _small(text: String) -> Label:
	var l := UI.label(text, 18, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(540, 0)
	return l


# ── Asking the server ───────────────────────────────────────────────────────

func _bid(a: Dictionary, amount: int) -> void:
	if _busy:
		return
	_busy = true
	var r := await Api.request("POST", "/api/auction/%d/bid" % int(a.id), {"amount": amount})
	_busy = false
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	Sfx.play("karat", 1.0, -6.0)
	_set_karat(int(r.data.get("karat", 0)))
	UI.toast(self, "You're the top bidder on %s." % str(a.get("name", "")), UI.GREEN)
	_picked = r.data.get("auction", {})
	await _load()
	_reselect()


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
			Sfx.play("karat", 1.0, -6.0)
			_set_karat(int(r.data.get("karat", 0)))
			UI.toast(self, "%s is yours." % str(a.get("name", "")), UI.GREEN)
			_picked = {}
			_load(), UI.GREEN], ["CANCEL", func(): pass]])


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
		UI.toast(self, r.error, UI.RED)
		return
	Sfx.play("karat", 1.2, -6.0)
	_set_karat(int(r.data.get("karat", 0)))
	var lim: Dictionary = _info.get("limits", {})
	lim["activeUsed"] = int(lim.get("activeUsed", 0)) + 1
	lim["todayUsed"] = int(lim.get("todayUsed", 0)) + 1
	UI.toast(self, "%s is up for auction." % str(card.get("name", "")), UI.GREEN)
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
			UI.toast(self, "Auction cancelled.", UI.BLUE)
			_picked = {}
			_load(), UI.RED], ["CANCEL", func(): pass]])


## After a reload: pick the same auction again (its fresh copy).
func _reselect() -> void:
	if _picked.is_empty():
		return
	for a in _auctions:
		if a.get("id") == _picked.get("id"):
			_picked = a
	_render()


# ── Filters (browse and sell) ───────────────────────────────────────────────

func _build_filters() -> void:
	_clear(_filters)
	if _tab == "mine":
		return
	for r in [0, 1, 2, 3, 4, 5]:
		var b := Button.new()
		b.text = "ANY" if r == 0 else UI.RARITY_LABEL[r].to_upper()
		b.toggle_mode = true
		b.button_pressed = _rarity == r
		b.custom_minimum_size = Vector2(0, 50)
		b.add_theme_font_size_override("font_size", 17)
		if r > 0:
			b.add_theme_color_override("font_color", UI.rarity_color(r))
		b.pressed.connect(func():
			Sfx.play("click")
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
	pick.custom_minimum_size = Vector2(220, 50)
	pick.add_theme_font_size_override("font_size", 17)
	pick.item_selected.connect(func(i):
		_clan = str(pick.get_item_metadata(i))
		_refilter())
	_filters.add_child(pick)
	var search := LineEdit.new()
	search.placeholder_text = "Search by name"
	search.text = _search
	search.custom_minimum_size = Vector2(300, 50)
	search.add_theme_font_size_override("font_size", 18)
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
		return "ending…"
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
			return "CANCELLED"
	return ""


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
