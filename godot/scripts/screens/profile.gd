extends Screen
## Profile: avatar, name, title, rank, level/XP, stats and recent matches. The avatar, title and
## card back are chosen on the Achievements screen, which unlocks them.


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.62)
	Game.play_menu_music()
	UI.back_button(self, func(): Game.go("main_menu"))
	await Game.refresh_player()
	_render(Game.player)


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
	if not Game.offline:
		var look_box := CenterContainer.new()
		look_box.add_child(UI.button("CHANGE LOOK  ·  ACHIEVEMENTS", func(): Game.go("achievements"), Vector2(420, 54), UI.GOLD))
		left.add_child(look_box)
	for spec in [[str(p.get("username", "")), 52, UI.GOLD], [UI.shown_title(p), 28, UI.RED],
			[str(p.get("rank", "rookie")).replace("_", " ").to_upper(), 26, UI.BLUE]]:
		var l := UI.label(spec[0], spec[1], spec[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(l)
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
	var rp := UI.label("%d Rank Points" % int(p.get("rank_points", 0)), 22, UI.MUTED)
	rp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rp)
	var bio = p.get("profile_bio")
	if bio is String and bio != "":
		var b := UI.label("\"%s\"" % bio, 20, UI.MUTED)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(b)

	var wins := int(p.get("wins", 0))
	var losses := int(p.get("losses", 0))
	var stats := [
		["KARAT", str(int(p.get("karat", 0)))], ["CONTRABAND", str(int(p.get("contraband", 0)))],
		["WINS", str(wins)], ["LOSSES", str(losses)],
		["WIN RATE", "%.1f%%" % (100.0 * wins / (wins + losses)) if wins + losses > 0 else "—"],
		["COLLECTION", "%.1f%%" % float(p.get("collection_pct", 0) if p.get("collection_pct") != null else 0)],
		["DUST", str(int(p.get("dust", 0)))],
	]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(900, 250)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	add_child(grid)
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
	if not Game.offline:
		_recent_matches()


## Your last matches, each with a replay (routes/replays.js on the server).
func _recent_matches() -> void:
	var head := UI.label("RECENT MATCHES", 26, UI.GOLD, true)
	head.position = Vector2(900, 700)
	add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(900, 744)
	scroll.size = Vector2(888, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
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
		var mode: String = {"casual": "Casual", "friendly": "Friendly", "cpu": "VS CPU", "cpu_ranked": "Ranked"}.get(m.get("mode"), "Match")
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

