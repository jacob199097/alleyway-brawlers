extends RefCounted
## Ranked seasons (the server's backend/economy/seasons.js; GET /api/seasons): what each rank pays this
## season, and a finished season's reward to take (POST /api/seasons/claim). The Fight screen's Ranked
## tile opens rewards(); the main menu calls claim_waiting() after the daily reward.

const RANK_COLORS := {
	"rookie": Color("9aa7b8"), "street_tough": Color("4ade80"), "enforcer": Color("38bdf8"),
	"underboss": Color("a46bff"), "kingpin": Color("ff3b3b"), "legend": Color("ffd34d"),
}


## The season and the player's place in it, or {} (offline, or the server didn't answer).
static func fetch() -> Dictionary:
	if Game.offline:
		return {}
	var r := await Api.request("GET", "/api/seasons")
	return r.data if r.ok and r.data is Dictionary else {}


## "Ends at launch" / "Ends in 12 days" / "Ends today" (Season 0 has no date: it ends when the game launches).
static func ends_text(season: Dictionary) -> String:
	var ends = season.get("ends_at")
	if not (ends is String) or ends == "":
		return "Ends at launch" if int(season.get("id", 0)) == 0 else "No end date yet"
	var left := int(floor((Time.get_unix_time_from_datetime_string(ends) - Time.get_unix_time_from_system()) / 86400.0))
	return "Ends today" if left <= 0 else "Ends in %d day%s" % [left, "" if left == 1 else "s"]


## A reward as words: "1000 Karat · 5 free packs · Prize card: Name" (a prize card still being made says so).
static func reward_text(reward: Dictionary) -> String:
	var t := UI.reward_text(reward)
	var cards: Array = reward.get("cards", []) if reward.get("cards") is Array else []
	if not cards.is_empty():
		t += "  ·  Prize card: %s" % str(CardDB.get_card(str(cards[0])).get("name", "a season prize card"))
	elif reward.get("prize", false):
		t += "  ·  a season prize card (still being made)"
	return t


## The prize card itself, as a card: a click or tap shows it full size. null if it isn't in the game yet.
static func _prize_tile(parent: Control, id: String, size: Vector2) -> CardTile:
	var card := CardDB.get_card(id)
	if card.is_empty():
		return null
	var tile := CardTile.make(card, size)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.pressed.connect(func(t: CardTile): UI.card_zoom(parent, t.card))
	tile.zoomed.connect(func(t: CardTile): UI.card_zoom(parent, t.card))
	return tile


## Beside the ranks: the season's prize card and the ranks that win it (Kingpin and Legend), or null.
static func _prize_column(parent: Control, tiers: Array) -> Control:
	var id := ""
	var ranks: Array = []
	for t in tiers:   # (Legend first)
		var cards = t.get("reward", {}).get("cards") if t.get("reward") is Dictionary else null
		if cards is Array and not cards.is_empty():
			id = str(cards[0])
			ranks.push_front(str(t.get("name", t.get("tier", ""))))
	var tile := _prize_tile(parent, id, Vector2(230, 326))
	if tile == null:
		return null
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := UI.label("SEASON PRIZE CARD", 20, UI.GOLD, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	v.add_child(tile)
	var how := UI.label("Reach %s this season to win it. Not in packs, crafting or the Auction House.
%s it to see it up close." % [" or ".join(ranks), "Tap" if Game.mobile() else "Click"], 16, UI.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.custom_minimum_size = Vector2(270, 0)
	v.add_child(how)
	return v


## What each rank pays this season, the player's best rank marked.
static func rewards(parent: Control, s: Dictionary) -> void:
	var season: Dictionary = s.get("season", {}) if s.get("season") is Dictionary else {}
	var me: Dictionary = s.get("me", {}) if s.get("me") is Dictionary else {}
	var peak := str(me.get("peak_tier", "rookie"))
	var dlg := UI.dialog(parent, "%s  ·  REWARDS" % str(season.get("name", "SEASON")).to_upper(),
		"Rewards go by the highest rank you reach this season, even if you drop back after. Play at least one Ranked match to earn one. When a new season starts, every rank drops back %d." % int(s.get("soft_reset_tiers", 2)),
		[["CLOSE", func(): pass, UI.GOLD]], UI.GOLD)
	var col: VBoxContainer = dlg.get_child(0).get_child(0)
	var sub := UI.label(("%s  ·  " % str(season.get("subtitle", "")) if str(season.get("subtitle", "")) != "" else "") + ends_text(season)
		+ ("  ·  your best so far: %s (%d RP)" % [peak.replace("_", " ").capitalize(), int(me.get("peak_points", 0))] if int(me.get("ranked", 0)) > 0 else "  ·  you haven't played Ranked this season yet"), 20, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.move_child(sub, 1)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	var tiers: Array = s.get("tiers", []) if s.get("tiers") is Array else []
	tiers = tiers.duplicate()
	tiers.reverse()   # (Legend at the top)
	for t in tiers:
		var tier := str(t.get("tier", ""))
		var col_t: Color = RANK_COLORS.get(tier, Color.WHITE)
		var mine := tier == peak and int(me.get("ranked", 0)) > 0
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.box(Color(col_t, 0.16 if mine else 0.06), Color(col_t, 0.9 if mine else 0.25), 2, 8))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		h.add_child(UI.texture_rect(UI.tex("ranks/%s.png" % tier), Vector2(54, 54)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UI.label("%s%s" % [str(t.get("name", tier)).to_upper(), "   ◀ YOUR BEST" if mine else ""], 24, col_t, true))
		v.add_child(UI.label("%d+ RP  ·  %s" % [int(t.get("min", 0)), reward_text(t.get("reward", {}) if t.get("reward") is Dictionary else {})], 18, Color(0.88, 0.88, 0.96)))
		list.add_child(row)
	list.custom_minimum_size = Vector2(900, 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := HBoxContainer.new()   # (the ranks, and the prize card beside them)
	body.add_theme_constant_override("separation", 20)
	body.add_child(list)
	var prize := _prize_column(parent, tiers)
	if prize:
		body.add_child(prize)
	col.add_child(body)
	col.move_child(body, 3)
	await parent.get_tree().process_frame
	var p: Control = dlg.get_child(0)
	p.reset_size()
	p.position = (Vector2(1920, 1080) - p.size) / 2


## Each finished season's reward the player hasn't taken: shown one after another, taken with CLAIM.
static func claim_waiting(parent: Control, s: Dictionary = {}) -> void:
	if s.is_empty():
		s = await fetch()
	var waiting: Array = s.get("unclaimed", []) if s.get("unclaimed") is Array else []
	for u in waiting:
		if not parent.is_inside_tree():
			return
		var tier := str(u.get("peak_tier", "rookie"))
		var reward: Dictionary = u.get("reward", {}) if u.get("reward") is Dictionary else {}
		var done := [false]
		var dlg := UI.dialog(parent, "%s IS OVER" % str(u.get("name", "THE SEASON")).to_upper(),
			"You reached %s (%d Ranked match%s). Your reward:\n%s" % [str(u.get("peak_tier_name", tier)).to_upper(), int(u.get("ranked_games", 0)),
				"" if int(u.get("ranked_games", 0)) == 1 else "es", reward_text(reward)],
			[["CLAIM", func(): done[0] = true, UI.GREEN]], RANK_COLORS.get(tier, UI.GOLD))
		var col: VBoxContainer = dlg.get_child(0).get_child(0)
		var top := HBoxContainer.new()   # (the rank's emblem, and the prize card it won)
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 40)
		var emblem := UI.texture_rect(UI.tex("ranks/%s.png" % tier), Vector2(150, 150))
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(emblem)
		var cards: Array = reward.get("cards", []) if reward.get("cards") is Array else []
		var prize := _prize_tile(parent, str(cards[0]), Vector2(170, 241)) if not cards.is_empty() else null
		if prize:
			top.add_child(prize)
		col.add_child(top)
		col.move_child(top, 1)
		var p: Control = dlg.get_child(0)
		parent.get_tree().process_frame.connect(func():   # (centred again once it has grown)
			if is_instance_valid(p):
				p.reset_size()
				p.position = (Vector2(1920, 1080) - p.size) / 2
				p.pivot_offset = p.size / 2, CONNECT_ONE_SHOT)
		await dlg.tree_exited
		if not done[0] or not parent.is_inside_tree():
			continue
		var r := await Api.request("POST", "/api/seasons/claim", {"season": int(u.get("season", 0))})
		if not parent.is_inside_tree():
			return
		if r.ok:
			await Game.refresh_player()
			UI.toast(parent, "%s reward taken: %s" % [str(u.get("name", "Season")), reward_text(r.data.get("reward", reward) if r.data is Dictionary else reward)], UI.GREEN)
		else:
			UI.toast(parent, str(r.error), UI.RED)
