extends Screen
## Profile: avatar, name, title, rank, level/XP, stats and recent matches. The avatar, title and
## card back are chosen on the Achievements screen, which unlocks them.
## Opened from the friends list (Game.view_player_id), it shows that friend's profile instead:
## the same stats, without currencies, the look button or replays.

var _friend := false
var _views := {}       # tab -> its Control (built when first opened)
var _tabs := {}


func _ready() -> void:
	var id := Game.view_player_id
	Game.view_player_id = ""
	_friend = id != ""
	back_to = "social" if _friend else "main_menu"
	UI.background(self, "menu_background.png", 0.62)
	Game.play_menu_music()
	UI.back_button(self, func(): Game.go(back_to))
	if not _friend:
		await Game.refresh_player()
		_render(Game.player)
		return
	var spin := UI.spinner(self, Vector2(960, 540), "LOADING PROFILE…")
	var r := await Api.request("GET", "/api/profile/player/" + id)
	spin.queue_free()
	if not r.ok or not (r.data is Dictionary):
		UI.toast(self, str(r.get("error", "")) if str(r.get("error", "")) != "" else "That profile couldn't be loaded.", UI.RED)
		return
	_render(r.data)


func _render(p: Dictionary) -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(150, 80)
	left.custom_minimum_size = Vector2(620, 0)
	left.add_theme_constant_override("separation", 14)
	add_child(left)
	var av := UI.texture_rect(UI.avatar(p.get("avatar_url")), Vector2(260, 260), true)
	var av_box := CenterContainer.new()
	av_box.add_child(av)
	left.add_child(av_box)
	if not Game.offline and not _friend:
		var look_box := CenterContainer.new()
		look_box.add_child(UI.button("CHANGE LOOK  ·  ACHIEVEMENTS", func(): Game.go("achievements"), Vector2(420, 54), UI.GOLD))
		left.add_child(look_box)
	for spec in [[str(p.get("username", "")), 52, UI.GOLD], [UI.shown_title(p), 28, UI.RED],
			[str(p.get("rank", "rookie")).replace("_", " ").to_upper(), 26, UI.BLUE]]:
		var l := UI.label(spec[0], spec[1], spec[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(l)
	var lv_box := CenterContainer.new()
	lv_box.add_child(UI.texture_rect(UI.level_icon(int(p.get("level", 1))), Vector2(150, 150)))
	left.add_child(lv_box)
	var xp := UI.xp_progress(p)
	var lvl := UI.label("Level %d  —  %d / %d XP" % [int(p.get("level", 1)), xp.current, xp.needed], 24)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(lvl)
	var track := ColorRect.new()
	track.color = Color("1a1a3a")
	track.custom_minimum_size = Vector2(620, 16)
	left.add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.BLUE
	fill.size = Vector2(620 * xp.pct, 16)
	track.add_child(fill)
	UI.grow_bar(fill, 0.4, 1.0)
	var rp := UI.label("%d Rank Points" % int(p.get("rank_points", 0)), 22, UI.MUTED)
	rp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rp)
	if p.has("last_played_at"):   # (online now, or when they last finished a match)
		var online: bool = _friend and p.get("is_online", false)
		var seen := UI.label("● Online now" if online else "Last played %s" % UI.ago(p.get("last_played_at")),
			20, UI.GREEN if online else UI.MUTED)
		seen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(seen)
	var bio = p.get("profile_bio")
	if bio is String and bio != "":
		var b := UI.label("\"%s\"" % bio, 20, UI.MUTED)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(b)

	var wins := int(p.get("wins", 0))
	var losses := int(p.get("losses", 0))
	var rate: String = "%.1f%%" % (100.0 * wins / (wins + losses)) if wins + losses > 0 else "—"
	var collection: String = "%.1f%%" % float(p.get("collection_pct", 0) if p.get("collection_pct") != null else 0)
	var stats := [
		["KARAT", str(int(p.get("karat", 0)))], ["CONTRABAND", str(int(p.get("contraband", 0)))],
		["WINS", str(wins)], ["LOSSES", str(losses)], ["WIN RATE", rate], ["COLLECTION", collection],
		["DUST", str(int(p.get("dust", 0)))],
	]
	if _friend:   # (a friend's currencies are their own business)
		var clan := CardDB.clan(str(p.get("chosen_clan", "")))
		stats = [["WINS", str(wins)], ["LOSSES", str(losses)], ["WIN RATE", rate], ["COLLECTION", collection],
			["ACHIEVEMENTS", str(int(p.get("achievements", 0)))], ["CLAN", str(clan.get("name", "—")).to_upper()],
			["MATCHES", str(wins + losses + int(p.get("draws", 0)))],
			["PLAYING SINCE", str(p.get("created_at", "")).left(10)]]
	var stats_view := Control.new()
	stats_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stats_view)
	_views["stats"] = stats_view
	if not Game.offline and not _friend:
		var bar := HBoxContainer.new()
		bar.position = Vector2(900, 170)
		bar.add_theme_constant_override("separation", 12)
		add_child(bar)
		for t in [["stats", "STATS"], ["mastery", "CLAN MASTERY"], ["decks", "DECKS"]]:
			var b := UI.button(t[1], _tab.bind(t[0]), Vector2(280, 54), UI.BLUE)
			b.toggle_mode = true
			b.set_pressed_no_signal(t[0] == "stats")
			bar.add_child(b)
			_tabs[t[0]] = b
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(900, 250)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	stats_view.add_child(grid)
	for s in stats:
		var cell := UI.panel(UI.BLUE)
		cell.custom_minimum_size = Vector2(280, 130)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(v)
		var cap := UI.label(s[0], 20, UI.MUTED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cap)
		var val := UI.label(s[1], 44, UI.GOLD, true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(val)
		grid.add_child(cell)
		_count_in(val, str(s[1]))
	UI.stagger(grid.get_children(), 0.15, 0.06)
	if not Game.offline and not _friend:
		_recent_matches(stats_view)


## A stat's number counting up to what it says ("1200", "63.2%"; anything else is left as it is).
func _count_in(l: Label, text: String) -> void:
	var pct := text.ends_with("%")
	var num := text.trim_suffix("%")
	if not num.is_valid_float():
		return
	var to := float(num)
	l.text = "0%" if pct else "0"
	l.create_tween().tween_method(func(x: float):
		l.text = ("%.1f%%" % x) if pct else str(int(round(x))), 0.0, to, 0.9).set_delay(0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _tab(which: String) -> void:
	Sfx.play("click")
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == which)
	for k in _views:
		_views[k].visible = k == which
	if _views.has(which):
		return
	var view := Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_views[which] = view
	if which == "mastery":
		_mastery(view)
	else:
		_decks(view)


## Clan mastery (economy/mastery.js): each clan's level, progress and what the next levels pay.
func _mastery(view: Control) -> void:
	var scroll := ScrollContainer.new()   # (one panel per clan: with many clans it scrolls)
	scroll.position = Vector2(900, 250)
	scroll.size = Vector2(920, 780)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(888, 0)
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	var wait := UI.label("Loading…", 22, UI.MUTED)
	col.add_child(wait)
	var r := await Api.request("GET", "/api/achievements")
	if not is_instance_valid(col):
		return
	wait.queue_free()
	var list: Array = r.data.get("mastery", []) if r.ok and r.data is Dictionary else []
	if list.is_empty():
		col.add_child(UI.label("Clan mastery isn't available right now.", 22, UI.MUTED))
		return
	col.add_child(UI.label("Every match levels up the clan your deck is built from: a win 100 XP, anything else 40.", 20, UI.MUTED))
	for m in list:
		var p := UI.panel(Color(str(m.get("color", "#b388ff"))), Color(0.05, 0.05, 0.12, 0.92))
		p.custom_minimum_size = Vector2(888, 0)
		col.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		p.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var name := UI.label("%s  ·  LEVEL %d / %d" % [str(m.name).to_upper(), int(m.level), int(m.max)], 30, Color(str(m.get("color", "#b388ff"))), true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		top.add_child(UI.label("%d wins · %d games" % [int(m.wins), int(m.games)], 20, UI.MUTED))
		var next = m.get("next")
		var track := ColorRect.new()
		track.color = Color("1a1a3a")
		track.custom_minimum_size = Vector2(860, 14)
		v.add_child(track)
		var fill := ColorRect.new()
		fill.color = Color(str(m.get("color", "#b388ff")))
		var pct := 1.0 if next == null else clampf(float(int(m.xp) - int(m.floor)) / maxf(1.0, float(int(next) - int(m.floor))), 0.0, 1.0)
		fill.size = Vector2(860 * pct, 14)
		track.add_child(fill)
		UI.grow_bar(fill, 0.2)
		var coming := ""
		for rw in m.get("rewards", []):
			if int(rw.level) > int(m.level):
				coming = "Level %d: %s" % [int(rw.level), _mastery_reward(rw.reward)]
				break
		v.add_child(UI.label(("%d / %d XP  ·  Next  %s" % [int(m.xp), int(next), coming]) if next != null else "Mastered: every reward unlocked", 20, Color.WHITE))


static func _mastery_reward(r: Dictionary) -> String:
	if r.get("title") is String:
		return "the title \"%s\"" % r.title
	if r.get("avatar") is String:
		var c := CardDB.get_card(str(r.avatar).substr(5))
		return "%s's profile picture" % str(c.get("name", "a card"))
	return UI.reward_text(r)


## Each deck's record (games and wins since this was added).
func _decks(view: Control) -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(900, 250)
	col.custom_minimum_size = Vector2(888, 0)
	col.add_theme_constant_override("separation", 10)
	view.add_child(col)
	var wait := UI.label("Loading…", 22, UI.MUTED)
	col.add_child(wait)
	var r := await Api.request("GET", "/api/deck")
	if not is_instance_valid(col):
		return
	wait.queue_free()
	if not r.ok or not (r.data is Array) or r.data.is_empty():
		col.add_child(UI.label("No decks yet: build one in the Deck Builder.", 22, UI.MUTED))
		return
	for d in r.data:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		col.add_child(row)
		var n := UI.label(str(d.get("name", "Deck")) + ("  ★" if d.get("is_active", false) else ""), 24, UI.GOLD if d.get("is_active", false) else Color.WHITE, true)
		n.custom_minimum_size = Vector2(420, 0)
		row.add_child(n)
		row.add_child(UI.label(_record(d), 22, Color(0.85, 0.85, 0.95)))


## "12 games · 7 wins · 58%" (or "No games yet").
static func _record(d: Dictionary) -> String:
	var g := int(d.get("games", 0))
	var w := int(d.get("wins", 0))
	return "No games yet" if g == 0 else "%d game%s · %d win%s · %d%%" % [g, "" if g == 1 else "s", w, "" if w == 1 else "s", roundi(100.0 * w / g)]


## Your last matches, each with a replay (routes/replays.js on the server).
func _recent_matches(parent: Control) -> void:
	var head := UI.label("RECENT MATCHES", 26, UI.GOLD, true)
	head.position = Vector2(900, 700)
	parent.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(900, 744)
	scroll.size = Vector2(888, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(870, 0)
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var spin := UI.label("Loading…", 20, UI.MUTED)
	list.add_child(spin)
	var r := await Api.request("GET", "/api/replays")
	if not is_instance_valid(list):
		return
	spin.queue_free()
	if not r.ok or not (r.data is Array):
		list.add_child(UI.label("Replays aren't available right now.", 20, UI.MUTED))
		return
	if r.data.is_empty():
		list.add_child(UI.label("Play a match and it shows up here, ready to watch again.", 20, UI.MUTED))
		return
	for m in r.data:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var won: bool = m.get("result") == "win"
		var res := UI.label({"win": "WIN", "loss": "LOSS"}.get(m.get("result"), "DRAW"), 22, UI.GREEN if won else UI.RED, true)
		res.custom_minimum_size = Vector2(80, 0)
		row.add_child(res)
		var mode: String = {"casual": "Casual", "friendly": "Friendly", "cpu": "VS CPU", "cpu_ranked": "Ranked", "cpu_challenge": "Weekly Challenge"}.get(m.get("mode"), "Match")
		var opp: Dictionary = m.get("opponent", {}) if m.get("opponent") is Dictionary else {}
		var info := UI.label("vs %s  ·  %s  ·  %d turns  ·  %s" % [opp.get("username", "?"), mode, int(m.get("turns", 0)),
			str(m.get("created_at", "")).left(10)], 20, Color(0.85, 0.85, 0.95))
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var id := str(m.id)
		row.add_child(UI.button("WATCH", func(): _watch(id), Vector2(140, 44), UI.BLUE))
		list.add_child(row)


func _watch(id: String) -> void:
	var spin := UI.spinner(self, Vector2(960, 1040), "LOADING REPLAY…")
	var r := await Api.request("GET", "/api/replays/" + id)
	spin.queue_free()
	if not r.ok or not (r.data is Dictionary):
		UI.toast(self, str(r.get("error", "")) if str(r.get("error", "")) != "" else "That replay couldn't be loaded.", UI.RED)
		return
	var data: Dictionary = Net.normalize(r.data)   # same number handling as live match messages
	Game.duel_setup = {"online": true, "start": data.start, "replay": data}
	Game.go("duel")

