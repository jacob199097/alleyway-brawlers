extends Screen
## The ranked leaderboard (GET /api/profile/leaderboard): the top three on a podium, everyone else in
## a list under it, your own row lit up (pinned at the bottom when you're outside the top 50).

const MEDALS := [Color("ffd34d"), Color("cfd8e6"), Color("e0965a")]   # gold, silver, bronze
const RANK_COLORS := {
	"rookie": Color("9aa7b8"), "street_tough": Color("4ade80"), "enforcer": Color("38bdf8"),
	"underboss": Color("a46bff"), "kingpin": Color("ff3b3b"), "legend": Color("ffd34d"),
}

var _me_id := ""


func _ready() -> void:
	back_to = "fight_mode"
	UI.background(self, "menu_background.png", 0.62)
	Game.play_menu_music()
	UI.title(self, "LEADERBOARD")
	UI.back_button(self, func(): Game.go(back_to))
	if not needs_server("The leaderboard"):
		return
	_me_id = str(Game.player.get("id", ""))
	var spin := UI.spinner(self, Vector2(960, 540), "LOADING…")
	var r := await Api.request("GET", "/api/profile/leaderboard")
	spin.queue_free()
	if not r.ok or not (r.data is Dictionary):
		UI.toast(self, r.error if not r.ok else "The leaderboard couldn't be loaded.", UI.RED)
		return
	var top: Array = r.data.get("top", [])
	var me = r.data.get("me")
	var sub := UI.label("Ranked by Rank Points  ·  %d players" % int(r.data.get("total", top.size())), 22, UI.MUTED)
	sub.size = Vector2(1920, 30)
	sub.position = Vector2(0, 92)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	_podium(top.slice(0, 3))
	_list(top.slice(3), me if me is Dictionary else {}, top)
	_intro()


## The top three: gold in the middle and highest, silver left, bronze right. They rise in one by one.
func _podium(three: Array) -> void:
	var spots := [[960, 0], [640, 60], [1280, 90]]   # [centre x, how much lower] for 1st, 2nd, 3rd
	for i in three.size():
		var p: Dictionary = three[i]
		var col: Color = MEDALS[i]
		var card := UI.glass(UI.panel(col, Color(0.05, 0.05, 0.1, 0.9)), Color(0.04, 0.03, 0.08, 0.6))
		card.custom_minimum_size = Vector2(280, 0)
		card.position = Vector2(spots[i][0] - 140, 150 + spots[i][1])
		add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var place := UI.label("#%d" % int(p.get("place", i + 1)), 44 if i == 0 else 36, col, true)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(place)
		var frame := PanelContainer.new()
		var fb := UI.box(Color(0, 0, 0, 0.5), col, 3, 10)
		for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
			fb.set(m, 4)
		frame.add_theme_stylebox_override("panel", UI._glow(fb, col, 0.8))
		frame.add_child(UI.texture_rect(UI.avatar(p.get("avatar_url")), Vector2(150, 150) if i == 0 else Vector2(124, 124), true))
		var c := CenterContainer.new()
		c.add_child(frame)
		v.add_child(c)
		var name := UI.label(str(p.get("username", "?")), 28, Color.WHITE, true)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.clip_text = true
		v.add_child(name)
		v.add_child(_rank_line(p, 20, true))
		var rec := UI.label("Lv %d  ·  %d W / %d L" % [int(p.get("level", 1)), int(p.get("wins", 0)), int(p.get("losses", 0))], 17, UI.MUTED)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rec)
		if str(p.get("id", "")) == _me_id:
			v.add_child(_you_tag())
		# Up from below, in podium order (the winner last, for the drum roll)
		var to := card.position
		card.position.y += 120
		card.modulate.a = 0.0
		var t := card.create_tween().set_parallel()
		var at := 0.25 + (2 - i) * 0.18
		t.tween_property(card, "position", to, 0.5).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(at)
		if i == 0:
			t.tween_callback(func(): Sfx.play("promote", 1.1, -6.0)).set_delay(at + 0.35)


## Fourth place down, in a glass list; your own row stands out (pinned underneath if you're further down).
func _list(rest: Array, me: Dictionary, top: Array) -> void:
	var p := UI.glass(UI.panel(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0.45)), Color(0.02, 0.02, 0.06, 0.5))
	p.position = Vector2(360, 590)
	p.size = Vector2(1200, 352)
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if rest.is_empty():
		var none := UI.label("Only the podium so far. Win Ranked Brawls to climb onto it.", 22, UI.MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(none)
	for row in rest:
		list.add_child(_row(row))
	UI.stagger(list.get_children(), 0.6, 0.035)
	# You, if you're not on the board already
	var shown := top.any(func(x): return str(x.get("id", "")) == _me_id)
	if not me.is_empty() and not shown:
		var mine := _row(me)
		mine.position = Vector2(360, 956)
		mine.custom_minimum_size = Vector2(1200, 0)
		add_child(mine)


func _row(p: Dictionary) -> Control:
	var mine := str(p.get("id", "")) == _me_id
	var clan_col: Color = CardDB.clan(str(p.get("chosen_clan", ""))).get("color", Color(1, 1, 1, 0.2))
	var row := UI.panel(UI.GOLD if mine else Color(clan_col, 0.35), Color(0.12, 0.1, 0.03, 0.75) if mine else Color(0.03, 0.03, 0.08, 0.5))
	row.custom_minimum_size = Vector2(0, 64)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	row.add_child(h)
	var place := UI.label("#%d" % int(p.get("place", 0)), 28, UI.GOLD if mine else Color.WHITE, true)
	place.custom_minimum_size = Vector2(80, 0)
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(place)
	h.add_child(UI.texture_rect(UI.avatar(p.get("avatar_url")), Vector2(48, 48), true))
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(who)
	who.add_child(UI.label(str(p.get("username", "?")) + ("   (YOU)" if mine else ""), 22, UI.GOLD if mine else Color.WHITE, true))
	var title = p.get("title")
	who.add_child(UI.label("Lv %d%s" % [int(p.get("level", 1)), "  ·  " + str(title) if title is String and title != "" else ""], 16, UI.MUTED))
	var rank := _rank_line(p, 20, false)
	rank.custom_minimum_size = Vector2(330, 0)
	h.add_child(rank)
	var rec := UI.label("%d W  /  %d L" % [int(p.get("wins", 0)), int(p.get("losses", 0))], 18, UI.MUTED)
	rec.custom_minimum_size = Vector2(150, 0)
	rec.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rec)
	return row


## "[badge] ENFORCER  ·  820 RP"
func _rank_line(p: Dictionary, size: int, centred: bool) -> HBoxContainer:
	var rank := str(p.get("rank", "rookie"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	if centred:
		line.alignment = BoxContainer.ALIGNMENT_CENTER
	if UI.tex("ranks/%s.png" % rank):
		line.add_child(UI.texture_rect(UI.tex("ranks/%s.png" % rank), Vector2(size * 1.7, size * 1.7)))
	var l := UI.label("%s  ·  %d RP" % [rank.replace("_", " ").to_upper(), int(p.get("rank_points", 0))], size, RANK_COLORS.get(rank, Color.WHITE), true)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(l)
	return line


func _you_tag() -> Label:
	var l := UI.label("THAT'S YOU", 16, UI.GOLD, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
