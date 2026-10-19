extends Screen
## Main menu: player bar (avatar, name, level, title, XP, currencies, settings/mail/social/shop
## icons), quests on the left, Fight / Deck Editor / Card Library in the middle, and
## Shop / Profile / Social on the right.

const BAR_SCALE := 0.8   # main_menu_bar.png is 2400 wide; drawn at 1920

var _contraband: Label
var _karat: Label
var _quest_box: Control


func _ready() -> void:
	UI.background(self, "menu_background.png", 0.35)
	Game.play_menu_music()
	if not Game.offline and not await Game.refresh_player():
		Game.sign_out()
		Game.go("login")
		return
	_build_bar(Game.player)
	_version_label()
	_build_center()
	_build_right()
	_build_quests()
	_intro()
	if not Game.offline:
		Net.rejoin()   # a match still running (the game closed mid-match) opens again
		await _daily()
		if not is_inside_tree():
			return
	var returning: bool = Game.settings.tutorial_offered
	if not Game.settings.tutorial_done and not Game.settings.tutorial_offered:
		# First visit: suggest the guided first duel once
		Game.set_setting("tutorial_offered", true)
		await get_tree().create_timer(0.6).timeout
		UI.dialog(self, "NEW TO THE ALLEY?", "Play a quick guided duel to learn the basics: Authority, attacking, Downed cards, leaders and Direct Attacks.",
			[["PLAY TUTORIAL", Game.start_tutorial, UI.GREEN], ["NOT NOW", func(): pass]])
	_patch_notes(returning)
	if Game.offline:
		var l := UI.label("OFFLINE  ·  vs CPU with the starter deck  ·  nothing is saved", 22, UI.PURPLE, true)
		l.size = Vector2(1920, 30)
		l.position = Vector2(0, 1040)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)


## Today's daily reward (GET /api/daily), if it hasn't been taken: shown, and waited on until closed.
func _daily() -> void:
	var r := await Api.request("GET", "/api/daily")
	if not r.ok or not (r.data is Dictionary) or r.data.get("claimed", true) or not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	var popup := _daily_popup(r.data)
	await popup.tree_exited


## The seven-day track: past days ticked off, today's glowing, the rest to come; CLAIM pays today's.
func _daily_popup(s: Dictionary) -> Control:
	var day := int(s.get("day", 1))
	var rewards: Array = s.get("rewards", [])
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.0)
	veil.size = Vector2(1920, 1080)
	veil.z_index = 40
	add_child(veil)
	veil.create_tween().tween_property(veil, "color:a", 0.62, 0.25)
	var panel := UI.glass(UI.panel(UI.GOLD, Color(0.05, 0.05, 0.1, 0.9)), Color(0.04, 0.03, 0.08, 0.7))
	panel.position = Vector2(300, 250)
	panel.custom_minimum_size = Vector2(1320, 0)
	veil.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := UI.label("DAILY REWARD", 52, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UI.label("Day %d of 7  ·  come back every day: day 7 brings a free pack. Miss a day and it starts over." % day, 21, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var tiles: Array = []
	for i in rewards.size():
		var t := _daily_tile(i + 1, rewards[i], day)
		row.add_child(t)
		tiles.append(t)
	UI.stagger(tiles, 0.15, 0.06)
	var claim := UI.button("CLAIM DAY %d" % day, func(): pass, Vector2(360, 66), UI.GREEN)
	var bc := CenterContainer.new()
	bc.add_child(claim)
	col.add_child(bc)
	claim.pressed.connect(func():
		claim.disabled = true
		claim.text = "…"
		var r := await Api.request("POST", "/api/daily/claim")
		if not is_instance_valid(veil):
			return
		if not r.ok:
			UI.toast(self, r.error, UI.RED)
			veil.queue_free()
			return
		await _daily_paid(r.data, tiles[day - 1] if day <= tiles.size() else null)
		if not is_instance_valid(veil):
			return
		var out := veil.create_tween()
		out.tween_interval(0.9)
		out.tween_property(veil, "modulate:a", 0.0, 0.3)
		out.tween_callback(veil.queue_free))
	# Rises in
	panel.modulate.a = 0.0
	var to := panel.position
	panel.position.y += 60
	var t := panel.create_tween().set_parallel()
	t.tween_property(panel, "modulate:a", 1.0, 0.3)
	t.tween_property(panel, "position", to, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("promote", 1.3, -8.0)
	return veil


## One day's tile: DAY n, what it pays, ticked off (before today), glowing (today) or dim (to come).
func _daily_tile(n: int, reward: Dictionary, today: int) -> PanelContainer:
	var past := n < today
	var now := n == today
	var col := UI.GOLD if now else Color(0.5, 0.85, 0.5) if past else Color(1, 1, 1, 0.25)
	var tile := UI.panel(col, Color(0.12, 0.09, 0.02, 0.85) if now else Color(0.03, 0.03, 0.08, 0.75))
	tile.custom_minimum_size = Vector2(160, 250)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	tile.add_child(v)
	var head := UI.label("DAY %d" % n, 24, col if not past else UI.MUTED, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var icon := CenterContainer.new()
	icon.custom_minimum_size = Vector2(0, 110)
	v.add_child(icon)
	var words: Array = []
	if int(reward.get("free_packs", 0)) > 0:
		var art := UI.tex("%s_booster.png" % str(Game.player.get("chosen_clan", "")))
		if art:
			icon.add_child(UI.texture_rect(art, Vector2(80, 108)))
		words.append("FREE PACK")
	elif int(reward.get("dust", 0)) > 0:
		icon.add_child(UI.label("✦", 76, UI.PURPLE, true))
	else:
		var coin := PanelContainer.new()
		var cb := UI.box(Color("3b2a05"), UI.GOLD, 4, 40)
		coin.add_theme_stylebox_override("panel", UI._glow(cb, UI.GOLD, 0.6))
		coin.custom_minimum_size = Vector2(80, 80)
		var k := UI.label("K", 44, UI.GOLD, true)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		coin.add_child(k)
		icon.add_child(coin)
	if int(reward.get("karat", 0)) > 0:
		words.push_front("%d KARAT" % int(reward.karat))
	if int(reward.get("dust", 0)) > 0:
		words.push_front("%d DUST" % int(reward.dust))
	var amt := UI.label("\n".join(words), 18, Color.WHITE if not past else UI.MUTED, true)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(amt)
	if past:
		tile.modulate = Color(0.75, 0.75, 0.8)
		var tick := UI.label("✓", 28, Color(0.5, 0.95, 0.5), true)
		tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tick)
	elif now:
		tile.pivot_offset = tile.custom_minimum_size / 2
		var pulse := tile.create_tween().set_loops()
		pulse.tween_property(tile, "scale", Vector2.ONE * 1.06, 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(tile, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
		tile.set_meta("pulse", pulse)
	else:
		tile.modulate = Color(0.6, 0.6, 0.68)
	return tile


## Today's reward paid: the tile stamps, coins fly to the Karat count, the menu's numbers catch up.
func _daily_paid(d: Dictionary, tile) -> void:
	var reward: Dictionary = d.get("reward", {})
	var k0 := int(Game.player.get("karat", 0))
	Game.player.karat = int(d.get("karat", k0))
	Game.player.dust = int(d.get("dust", Game.player.get("dust", 0)))
	Game.player.free_packs = int(d.get("free_packs", Game.player.get("free_packs", 0)))
	Sfx.play("level_up", 1.1, -4.0)
	var from := Vector2(960, 540)
	if tile is Control and is_instance_valid(tile):
		var tc: Control = tile
		from = tc.get_global_rect().get_center()
		if tc.has_meta("pulse"):   # (it stops breathing: it's taken)
			(tc.get_meta("pulse") as Tween).kill()
		var stamp := tc.create_tween()
		stamp.tween_property(tc, "scale", Vector2.ONE * 1.18, 0.1)
		stamp.tween_property(tc, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var tick := UI.label("✓", 90, Color(0.5, 1.0, 0.5), true)
		tick.size = tc.size
		tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tick.pivot_offset = tick.size / 2
		tick.scale = Vector2.ONE * 2.2
		tc.add_child(tick)
		tick.create_tween().tween_property(tick, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if int(reward.get("karat", 0)) > 0 and _karat:
		_coins(from, _karat.get_global_rect().get_center(), UI.GOLD)
		await get_tree().create_timer(0.5).timeout
		Sfx.play("karat", 1.0, -2.0)
		UI.count_up(_karat, k0, int(Game.player.karat), 0.7, "%d", "click")
	var gained := []
	if int(reward.get("dust", 0)) > 0:
		gained.append("+%d DUST" % int(reward.dust))
	if int(reward.get("free_packs", 0)) > 0:
		gained.append("+1 FREE PACK")
	if not gained.is_empty():
		UI.toast(self, "  ·  ".join(gained), UI.PURPLE)


## "What's new" once per version (data/patch_notes.json): every version since the one the
## player last saw. New players just start from the current one.
func _patch_notes(returning: bool) -> void:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var seen := str(Game.settings.get("last_seen_version", ""))
	if mine == "" or seen == mine:
		return
	Game.set_setting("last_seen_version", mine)
	if returning:
		_show_patch_notes(seen, mine)


## The notes for every version after `seen` up to `mine` ("" seen: just `mine`).
func _show_patch_notes(seen: String, mine: String) -> void:
	var all = JSON.parse_string(FileAccess.get_file_as_string("res://data/patch_notes.json"))
	if not all is Array:
		return
	var lines: Array = []
	for entry in all:
		var v := str(entry.get("version", ""))
		if _newer(v, mine) or (seen != "" and not _newer(v, seen)):
			continue   # not out yet, or seen already
		if seen == "" and v != mine:
			continue   # first time we track it: just this version
		lines.append("[b][color=#f4d35e]%s[/color][/b]" % v)
		for n in entry.get("notes", []):
			lines.append("•  " + str(n))
		lines.append("")
	if lines.is_empty():
		return
	await get_tree().create_timer(0.7).timeout
	var dlg := UI.dialog(self, "WHAT'S NEW", "", [["GOT IT", func(): pass, UI.GREEN]], UI.BLUE)
	var col: VBoxContainer = dlg.get_child(0).get_child(0)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(1000, 0)
	text.add_theme_font_size_override("normal_font_size", 21)
	text.add_theme_font_size_override("bold_font_size", 24)
	text.text = "
".join(lines)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1020, mini(620, 34 * lines.size()))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(text)
	col.add_child(scroll)
	col.move_child(scroll, 1)
	await get_tree().process_frame
	var p: Control = dlg.get_child(0)
	p.reset_size()
	p.position = (Vector2(1920, 1080) - p.size) / 2
	p.pivot_offset = p.size / 2


## a > b, for versions like "0.6.1".
static func _newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		SettingsPanel.open(self)


## Position on the bar artwork (in its 2400-wide pixels) → screen.
static func _bar(x: float, y: float) -> Vector2:
	return Vector2(x, y) * BAR_SCALE


## The game's version, small in the bottom-right corner (what to quote when something goes wrong).
func _version_label() -> void:
	var v := UI.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 18, Color(1, 1, 1, 0.45))
	v.size = Vector2(300, 24)
	v.position = Vector2(1600, 1048)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)


func _build_bar(p: Dictionary) -> void:
	var bar := UI.texture_rect(UI.tex("main_menu_bar.png"), Vector2(1920, 208))
	add_child(bar)
	# (inside the neon frame in the bar artwork, its glow showing evenly all round)
	var av := UI.texture_rect(UI.avatar(p.get("avatar_url")), Vector2(120, 120), true)
	av.position = _bar(182, 134) - Vector2(60, 60)
	av.mouse_filter = Control.MOUSE_FILTER_STOP
	av.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Game.go("profile"))
	av.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(av)
	_text(str(p.get("username", "")).to_upper(), _bar(540, 92), 30, Color.WHITE)
	var lv_icon := UI.texture_rect(UI.level_icon(int(p.get("level", 1))), Vector2(42, 42))
	lv_icon.position = _bar(1172, 90) - Vector2(21, 21)
	add_child(lv_icon)
	_text(str(int(p.get("level", 1))), _bar(1206, 92), 30, UI.BLUE)
	_text(UI.shown_title(p), _bar(420, 170), 24, UI.RED)
	var xp := UI.xp_progress(p)
	_text("%d / %d" % [xp.current, xp.needed], _bar(1090, 158), 18, UI.BLUE)
	var track := ColorRect.new()
	track.color = Color("1a1a3a")
	track.position = _bar(990, 183)
	track.size = Vector2(260 * BAR_SCALE, 7)
	add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.BLUE
	fill.size = Vector2(0, 7)
	track.add_child(fill)
	_fill_xp(p, track, fill)
	_contraband = _text("0", _bar(1960, 100), 26, UI.PURPLE)
	_karat = _text("0", _bar(2110, 104), 26, UI.GOLD)
	# (currencies count up as the menu opens: from a bit below, so it's quick)
	var c := int(p.get("contraband", 0))
	var k := int(p.get("karat", 0))
	UI.count_up(_contraband, int(c * 0.6), c, 0.8)
	UI.count_up(_karat, int(k * 0.6), k, 0.8)
	_hotspot(_bar(1392, 124), func(): SettingsPanel.open(self))
	var mail := _hotspot(_bar(1524, 126), func(): Game.go("mailbox"))
	_hotspot(_bar(1656, 126), func(): Game.go("social"))
	_hotspot(_bar(1858, 126), func(): Game.go("contraband"))   # the briefcase and the Contraband count: the CB store
	_hotspot(_bar(1975, 112), func(): Game.go("contraband"))
	if not Game.offline:
		_mail_badge(mail)


## The XP bar fills from where it last stood: from empty the first time, else from the XP before this
## visit, with "+N XP" over it (and a flash through a new level).
func _fill_xp(p: Dictionary, track: ColorRect, fill: ColorRect) -> void:
	var total := int(p.get("xp", 0))
	var xp := UI.xp_progress(p)
	var seen := Game.xp_seen
	Game.xp_seen = total
	var gained := total - seen if seen >= 0 else 0
	var tw := fill.create_tween()
	tw.tween_interval(0.3)
	if gained <= 0:
		tw.tween_property(fill, "size:x", track.size.x * xp.pct, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return
	var before := UI.xp_progress({"level": int(p.get("level", 1)), "xp": seen})
	var levelled: bool = xp.current < gained   # (the bar wrapped round: this visit crossed a level)
	fill.size.x = 0.0 if levelled else track.size.x * before.pct
	var pop := UI.label("+%d XP" % gained, 22, UI.BLUE, true)
	pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pop.add_theme_constant_override("outline_size", 6)
	pop.position = track.position + Vector2(track.size.x - 90, -40)
	pop.modulate.a = 0.0
	add_child(pop)
	var pt := pop.create_tween()
	pt.tween_interval(0.45)
	pt.tween_property(pop, "modulate:a", 1.0, 0.15)
	pt.parallel().tween_property(pop, "position:y", pop.position.y - 14, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.tween_interval(1.2)
	pt.tween_property(pop, "modulate:a", 0.0, 0.4)
	pt.tween_callback(pop.queue_free)
	if levelled:
		var glow := ColorRect.new()
		glow.color = Color(1, 1, 1, 0)
		glow.size = track.size
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(glow)
		tw.tween_callback(func(): Sfx.play("level_up", 1.0, -6.0))
		tw.tween_property(glow, "color:a", 0.9, 0.12)
		tw.tween_property(glow, "color:a", 0.0, 0.5)
	tw.tween_property(fill, "size:x", track.size.x * xp.pct, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Sfx.play("karat", 1.4, -12.0))


func _text(t: String, at: Vector2, font_size: int, color: Color) -> Label:
	var l := UI.label(t, font_size, color, true)
	l.position = at - Vector2(0, font_size * 0.7)
	add_child(l)
	return l


## An invisible click zone over an icon drawn on the bar artwork.
func _hotspot(center: Vector2, cb: Callable) -> Control:
	var b := Button.new()
	b.flat = true
	b.position = center - Vector2(42, 42)
	b.size = Vector2(84, 84)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.25), 2, 12))
	b.add_theme_stylebox_override("pressed", UI.box(Color(1, 1, 1, 0.15), UI.GOLD, 2, 12))
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	add_child(b)
	return b


func _mail_badge(anchor: Control) -> void:
	var r := await Api.request("GET", "/api/mail")
	if not r.ok or int(r.data.get("unread", 0)) <= 0 or not is_instance_valid(anchor):
		return
	var dot := UI.label(str(int(r.data.unread)), 18, Color.WHITE, true)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.RED, Color.WHITE, 2, 14))
	p.add_child(dot)
	p.position = anchor.position + Vector2(56, -4)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)


func _build_center() -> void:
	var fight := UI.image_button("fight_menu.png", Vector2(560, 306), func(): Game.go("fight_mode"), "FIGHT")
	fight.position = Vector2(760, 236)
	add_child(fight)
	var deck := UI.image_button("deck_editor.png", Vector2(560, 306), func(): Game.go("deck_builder"), "DECK EDITOR")
	deck.position = Vector2(760, 560)
	add_child(deck)
	# A wide neon sign under DECK EDITOR once assets/achievements_menu.png exists, a button until then
	var go_ach := func(): Game.go("achievements")
	if UI.tex("achievements_menu.png"):
		var sign := UI.image_button("achievements_menu.png", Vector2(560, 170), go_ach, "ACHIEVEMENTS")
		sign.position = Vector2(760, 878)
		sign.disabled = Game.offline
		add_child(sign)
	else:
		var ach := UI.button("ACHIEVEMENTS", go_ach, Vector2(272, 68), UI.GOLD)
		ach.position = Vector2(904, 895)
		ach.disabled = Game.offline
		add_child(ach)


func _build_right() -> void:
	var items := [["shop_menu.png", "SHOP", "shop"], ["profile_menu.png", "PROFILE", "profile"], ["library_menu.png", "CARD LIBRARY", "card_library"]]   # Social is the chat bubble on the bar (library_menu: patches skip names starting with c)
	for i in items.size():
		var it: Array = items[i]
		var b := UI.image_button(it[0], Vector2(420, 229), func(): Game.go(it[2]), it[1])
		b.position = Vector2(1470, 236 + i * 244)
		add_child(b)
		var free := int(Game.player.get("free_packs", 0))
		if it[2] == "shop" and free > 0 and not Game.offline:   # free packs from levelling up, waiting
			var tag := PanelContainer.new()
			tag.add_theme_stylebox_override("panel", UI.box(UI.GREEN, Color.WHITE, 2, 14))
			tag.add_child(UI.label("🎁 %d FREE PACK%s" % [free, "" if free == 1 else "S"], 20, Color.WHITE, true))
			tag.position = b.position + Vector2(250, 6)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tag)
			var pulse := tag.create_tween().set_loops()
			pulse.tween_property(tag, "modulate:a", 0.6, 0.6)
			pulse.tween_property(tag, "modulate:a", 1.0, 0.6)


# ── Quests ───────────────────────────────────────────────────────────────────
# quests.png is 2400×1309 with wide empty margins: only its frame region is drawn.

const QUEST_REGION := Rect2(660, 36, 1068, 1212)
const QUEST_SCALE := 0.62


func _build_quests() -> void:
	var at := AtlasTexture.new()
	at.atlas = UI.tex("quests.png")
	at.region = QUEST_REGION
	var frame := UI.texture_rect(at if at.atlas else null, QUEST_REGION.size * QUEST_SCALE)
	frame.position = Vector2(40, 236)
	add_child(frame)
	_quest_box = Control.new()
	_quest_box.position = frame.position
	add_child(_quest_box)
	if Game.offline:
		return
	var r := await Api.request("GET", "/api/quests")
	if not r.ok:
		return
	var main: Array = r.data.get("main", []).filter(func(q): return not q.claimed)
	main.sort_custom(func(a, b): return float(a.progress) / a.target > float(b.progress) / b.target)
	var top := Vector2(118, 216) * QUEST_SCALE
	var n := 0
	for i in mini(3, main.size()):
		_quest_row(main[i], top + Vector2(0, 14 + i * 74), n)
		n += 1
	var daily: Array = r.data.get("daily", [])
	var bottom := Vector2(118, 640) * QUEST_SCALE
	for i in mini(4, daily.size()):
		_quest_row(daily[i], bottom + Vector2(0, 10 + i * 58), n)
		n += 1


## A quest: it slides in (n: its place in the list), its bar fills; one ready to claim pulses.
func _quest_row(q: Dictionary, at: Vector2, n := 0) -> void:
	var w := 500.0
	var done: bool = int(q.progress) >= int(q.target)
	var claimed: bool = q.get("claimed", false)
	var row := Control.new()
	row.position = at - Vector2(40, 0)
	row.modulate.a = 0.0
	_quest_box.add_child(row)
	var slide := row.create_tween().set_parallel()
	slide.tween_property(row, "position", at, 0.35).set_delay(0.2 + n * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(row, "modulate:a", 1.0, 0.25).set_delay(0.2 + n * 0.07)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.size = Vector2(w, 50)
	row.add_child(bg)
	var name := UI.label(str(q.label), 20, Color(0.45, 0.45, 0.5) if claimed else UI.GREEN if done else Color.WHITE, true)
	name.position = Vector2(10, 2)
	row.add_child(name)
	var track := ColorRect.new()
	track.color = Color("111133")
	track.position = Vector2(10, 34)
	track.size = Vector2(w - 160, 8)
	row.add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.GREEN if done else UI.BLUE
	fill.size = Vector2(0, 8)
	track.add_child(fill)
	fill.create_tween().tween_property(fill, "size:x", track.size.x * clampf(float(q.progress) / float(q.target), 0, 1), 0.7) \
		.set_delay(0.35 + n * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if done and not claimed:
		var reward := "+%dK" % int(q.rewardKarat) if int(q.get("rewardKarat", 0)) > 0 else "+%dC" % int(q.get("rewardContraband", 0))
		var b := UI.button("CLAIM %s" % reward, func(): pass, Vector2(140, 40), UI.GREEN)
		b.add_theme_font_size_override("font_size", 16)
		b.position = Vector2(w - 146, 5)
		b.pressed.connect(_claim.bind(q, b))
		row.add_child(b)
		var pulse := b.create_tween().set_loops()   # (waiting to be claimed)
		pulse.tween_property(b, "self_modulate", Color(1.35, 1.35, 1.35), 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(b, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		var prog := UI.label("%d / %d" % [int(q.progress), int(q.target)], 18, UI.MUTED)
		prog.position = Vector2(w - 130, 22)
		row.add_child(prog)


func _claim(q: Dictionary, b: Button) -> void:
	b.disabled = true
	b.text = "…"
	var r := await Api.request("POST", "/api/quests/claim/%s" % q.id)
	if not r.ok:
		b.text = "ERROR"
		UI.toast(self, r.error, UI.RED)
		return
	var from := b.get_global_rect().get_center()
	b.queue_free()
	var k0 := int(Game.player.get("karat", 0))
	var c0 := int(Game.player.get("contraband", 0))
	Game.player.karat = r.data.get("karat", Game.player.get("karat", 0))
	Game.player.contraband = r.data.get("contraband", Game.player.get("contraband", 0))
	# Coins fly from the quest to the counter, which counts up as they land
	var to: Label = _karat if int(Game.player.karat) != k0 else _contraband
	_coins(from, to.get_global_rect().get_center(), UI.GOLD if to == _karat else UI.PURPLE)
	await get_tree().create_timer(0.5).timeout
	Sfx.play("karat", 1.0, -2.0)
	UI.count_up(_karat, k0, int(Game.player.karat), 0.7, "%d", "click")
	UI.count_up(_contraband, c0, int(Game.player.contraband), 0.7, "%d", "click")
	to.pivot_offset = to.size / 2
	var pop := to.create_tween()
	pop.tween_property(to, "scale", Vector2.ONE * 1.3, 0.1)
	pop.tween_property(to, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.play("promote", 1.2, -6.0)
	UI.toast(self, "Quest reward claimed!", UI.GREEN)


## A spray of coins from one point that curve up and into another.
func _coins(from: Vector2, to: Vector2, col: Color) -> void:
	for i in 14:
		var dot := ColorRect.new()
		dot.color = col.lightened(randf() * 0.4)
		dot.size = Vector2(10, 10)
		dot.pivot_offset = dot.size / 2
		dot.rotation = PI / 4
		dot.top_level = true
		dot.z_index = 100
		dot.position = from - dot.size / 2
		add_child(dot)
		var mid := from.lerp(to, 0.5) + Vector2(randf_range(-160, 160), randf_range(-220, -60))
		var t := dot.create_tween()
		var d := 0.45 + randf() * 0.25
		t.tween_method(func(k: float):
			var a := from.lerp(mid, k)
			var b2 := mid.lerp(to, k)
			dot.position = a.lerp(b2, k) - dot.size / 2, 0.0, 1.0, d).set_delay(i * 0.025).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(dot.queue_free)
