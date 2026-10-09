extends Screen
## After a duel: Victory/Defeat art (its BRAWL AGAIN / MENU buttons are part of the artwork),
## the match stats, the MVP card, and the rewards the server grants for the match.

const ART_SIZE := Vector2(920, 613)     # victory.png / defeat.png are 1536×1024
const ART_POS := Vector2(500, 0)

var _xp_fill: ColorRect
var _xp_label: Label
var _rewards: Label


func _ready() -> void:
	var d: Dictionary = Game.match_result
	var won: bool = d.get("result") == "win"
	var snap = d.get("snapshot")
	if snap is Texture2D:
		var bg := UI.texture_rect(snap, Vector2(1920, 1080), true)
		add_child(bg)
		var veil := ColorRect.new()
		veil.color = Color(0, 0, 0, 0.6)
		veil.size = size
		add_child(veil)
	else:
		UI.background(self, "duel_background.png", 0.7)
	Sfx.play("victory" if won else "defeat")
	var art := UI.texture_rect(UI.tex("victory.png" if won else "defeat.png"), ART_SIZE)
	art.position = ART_POS
	art.pivot_offset = ART_SIZE / 2
	art.scale = Vector2.ONE * 0.6
	art.modulate.a = 0.0
	add_child(art)
	var t := create_tween().set_parallel()
	t.tween_property(art, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(art, "modulate:a", 1.0, 0.25)
	if art.texture == null:
		var l := UI.label("VICTORY" if won else "DEFEAT", 160, UI.GOLD if won else UI.RED, true)
		l.size = ART_SIZE
		l.position = ART_POS
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
	# The two buttons drawn into the artwork (in its 1536×1024 pixels)
	_art_button(Rect2(205, 745, 555, 160), "BRAWL AGAIN", func(): Game.go("fight_mode"))
	_art_button(Rect2(805, 745, 495, 160), "MENU", func(): Game.go("main_menu"))
	_outcome_panel(d, won)
	_mvp_panel(d.get("mvp", {}))
	_submit(d)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		Game.go("main_menu")


func _art_button(r: Rect2, text: String, cb: Callable) -> void:
	var k := ART_SIZE.x / 1536.0
	var b := Button.new()
	b.position = ART_POS + r.position * k
	b.size = r.size * k
	b.tooltip_text = text
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.1), UI.GOLD, 3, 10))
	b.add_theme_stylebox_override("pressed", UI.box(Color(1, 1, 1, 0.2), UI.GOLD, 3, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if UI.tex("victory.png") == null:
		b.text = text
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	add_child(b)


func _outcome_panel(d: Dictionary, won: bool) -> void:
	var p := UI.panel(UI.GOLD if won else UI.RED)
	p.position = Vector2(60, 640)
	p.custom_minimum_size = Vector2(560, 400)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var reason := "Opponent's Morale reduced to 0" if won else "Your Morale reduced to 0"
	var r := UI.label(reason, 26, Color.WHITE, true)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(r)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 50)
	v.add_child(stats)
	for s in [["YOUR MORALE", d.get("player_morale", "—"), UI.BLUE if won else UI.RED],
			["OPP MORALE", d.get("opponent_morale", "—"), UI.RED if won else UI.BLUE],
			["TURNS", d.get("turns", "—"), Color.WHITE]]:
		var c := VBoxContainer.new()
		var cap := UI.label(s[0], 16, UI.MUTED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(cap)
		var val := UI.label(str(s[1]), 36, s[2], true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(val)
		stats.add_child(c)
	v.add_child(HSeparator.new())
	var cap := UI.label("XP EARNED", 16, UI.MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var track := ColorRect.new()
	track.color = Color("1a1a3a")
	track.custom_minimum_size = Vector2(500, 14)
	v.add_child(track)
	_xp_fill = ColorRect.new()
	_xp_fill.color = UI.BLUE
	_xp_fill.size = Vector2(0, 14)
	track.add_child(_xp_fill)
	_xp_label = UI.label("…", 20, UI.BLUE, true)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_xp_label)
	_rewards = UI.label("", 24, UI.GOLD, true)
	_rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_rewards)


func _mvp_panel(mvp: Dictionary) -> void:
	var p := UI.panel(UI.GOLD)
	p.position = Vector2(1300, 640)
	p.custom_minimum_size = Vector2(560, 400)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var h := UI.label("MVP BRAWLER", 22, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	if mvp.is_empty():
		var none := UI.label("No damage dealt", 22, UI.MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(none)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var tile := CardTile.make(mvp.card, Vector2(200, 283))
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
	row.add_child(tile)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	row.add_child(info)
	var mine: bool = mvp.get("owner") == "player"
	info.add_child(UI.label("YOUR CARD" if mine else "THEIR CARD", 18, UI.BLUE if mine else UI.RED, true))
	var n := UI.label(str(mvp.card.get("name", "?")).to_upper(), 30, Color("ffd86b"), true)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD
	n.custom_minimum_size = Vector2(280, 0)
	info.add_child(n)
	info.add_child(UI.label("%d" % int(mvp.get("damage", 0)), 56, Color.WHITE, true))
	info.add_child(UI.label("MORALE DEALT", 18, UI.MUTED, true))


## Rewards are decided by the server (solo-match session from match/start).
func _submit(d: Dictionary) -> void:
	if Game.offline or str(d.get("match_id", "")) == "":
		_xp_label.text = "+0 XP"
		_rewards.text = "Offline — rewards not recorded" if Game.offline else "Rewards not recorded"
		return
	var r := await Api.request("POST", "/api/match/complete", {
		"matchId": d.match_id, "result": d.result, "cardsPlayed": d.get("cards_played", 0),
		"playerMorale": d.get("player_morale", 0), "opponentMorale": d.get("opponent_morale", 0),
		"turns": d.get("turns", 0),
	})
	if not r.ok or not (r.data is Dictionary) or not r.data.has("rewards"):
		_xp_label.text = "+0 XP"
		_rewards.text = r.error if r.error != "" else "Rewards not recorded"
		return
	var rw: Dictionary = r.data.rewards
	var xp := UI.xp_progress({"level": rw.get("newLevel", Game.player.get("level", 1)), "xp": rw.get("newXp", 0)})
	_xp_label.text = "+%d XP" % int(rw.get("xpEarned", 0))
	create_tween().tween_property(_xp_fill, "size:x", 500.0 * xp.pct, 0.8).set_delay(0.4).set_trans(Tween.TRANS_QUAD)
	var lines := ["+%d Karat" % int(rw.get("karatEarned", 0))]
	if rw.get("dailyCapReached", false):
		lines.append("Daily reward limit reached")
	if rw.get("firstWinBonus", false):
		lines.append("★ First Win Bonus!")
	if rw.get("leveledUp", false):
		lines.append("→ Level %d!" % int(rw.newLevel))
	_rewards.text = "\n".join(lines)
	if rw.get("rankChanged", false):
		_rank_up(str(rw.get("newRank", "")))


func _rank_up(rank: String) -> void:
	await get_tree().create_timer(1.2).timeout
	var l := UI.label("⬆ RANK UP!\n%s" % rank.replace("_", " ").to_upper(), 72, UI.GOLD, true)
	l.size = Vector2(1920, 200)
	l.position = Vector2(0, 380)
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.scale = Vector2.ONE * 0.4
	add_child(l)
	Sfx.play("promote")
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	t.tween_interval(2.0)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)
