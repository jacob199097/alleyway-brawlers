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
	_build_center()
	_build_right()
	_build_quests()
	_intro()
	if not Game.settings.tutorial_done and not Game.settings.tutorial_offered:
		# First visit: suggest the guided first duel once
		Game.set_setting("tutorial_offered", true)
		await get_tree().create_timer(0.6).timeout
		UI.dialog(self, "NEW TO THE ALLEY?", "Play a quick guided duel to learn the basics: Authority, attacking, Downed cards, leaders and Direct Attacks.",
			[["PLAY TUTORIAL", Game.start_tutorial, UI.GREEN], ["NOT NOW", func(): pass]])
	if Game.offline:
		var l := UI.label("OFFLINE  ·  vs CPU with the starter deck  ·  nothing is saved", 22, UI.PURPLE, true)
		l.size = Vector2(1920, 30)
		l.position = Vector2(0, 1040)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		SettingsPanel.open(self)


## Position on the bar artwork (in its 2400-wide pixels) → screen.
static func _bar(x: float, y: float) -> Vector2:
	return Vector2(x, y) * BAR_SCALE


func _build_bar(p: Dictionary) -> void:
	var bar := UI.texture_rect(UI.tex("main_menu_bar.png"), Vector2(1920, 208))
	add_child(bar)
	var avatar_path := "%s.png" % p.get("avatar_url", "profile_001")
	var av := UI.texture_rect(UI.tex(avatar_path) if UI.tex(avatar_path) else UI.tex("profile_001.png"), Vector2(128, 128), true)
	av.position = _bar(180, 130) - Vector2(64, 64)
	av.mouse_filter = Control.MOUSE_FILTER_STOP
	av.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Game.go("profile"))
	av.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(av)
	_text(str(p.get("username", "")).to_upper(), _bar(540, 92), 30, Color.WHITE)
	_text(str(int(p.get("level", 1))), _bar(1150, 92), 30, UI.BLUE)
	_text(UI.player_title(int(p.get("level", 1))), _bar(420, 170), 24, UI.RED)
	var xp := UI.xp_progress(p)
	_text("%d / %d" % [xp.current, xp.needed], _bar(1090, 158), 18, UI.BLUE)
	var track := ColorRect.new()
	track.color = Color("1a1a3a")
	track.position = _bar(990, 183)
	track.size = Vector2(260 * BAR_SCALE, 7)
	add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.BLUE
	fill.size = Vector2(track.size.x * xp.pct, 7)
	track.add_child(fill)
	_contraband = _text(str(int(p.get("contraband", 0))), _bar(1960, 100), 26, UI.PURPLE)
	_karat = _text(str(int(p.get("karat", 0))), _bar(2110, 104), 26, UI.GOLD)
	_hotspot(_bar(1392, 124), func(): SettingsPanel.open(self))
	var mail := _hotspot(_bar(1524, 126), func(): Game.go("mailbox"))
	_hotspot(_bar(1656, 126), func(): Game.go("social"))
	_hotspot(_bar(1858, 126), func(): Game.go("shop"))
	if not Game.offline:
		_mail_badge(mail)


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
	var lib := UI.button("CARD LIBRARY", func(): Game.go("card_library"), Vector2(420, 68))
	lib.position = Vector2(830, 895)
	add_child(lib)


func _build_right() -> void:
	var items := [["shop_menu.png", "SHOP", "shop"], ["profile_menu.png", "PROFILE", "profile"], ["social_menu.png", "SOCIAL", "social"]]
	for i in items.size():
		var it: Array = items[i]
		var b := UI.image_button(it[0], Vector2(420, 229), func(): Game.go(it[2]), it[1])
		b.position = Vector2(1470, 236 + i * 244)
		add_child(b)


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
	for i in mini(3, main.size()):
		_quest_row(main[i], top + Vector2(0, 14 + i * 74))
	var daily: Array = r.data.get("daily", [])
	var bottom := Vector2(118, 640) * QUEST_SCALE
	for i in mini(4, daily.size()):
		_quest_row(daily[i], bottom + Vector2(0, 10 + i * 58))


func _quest_row(q: Dictionary, at: Vector2) -> void:
	var w := 500.0
	var done: bool = int(q.progress) >= int(q.target)
	var claimed: bool = q.get("claimed", false)
	var row := Control.new()
	row.position = at
	_quest_box.add_child(row)
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
	fill.size = Vector2(track.size.x * clampf(float(q.progress) / float(q.target), 0, 1), 8)
	track.add_child(fill)
	if done and not claimed:
		var reward := "+%dK" % int(q.rewardKarat) if int(q.get("rewardKarat", 0)) > 0 else "+%dC" % int(q.get("rewardContraband", 0))
		var b := UI.button("CLAIM %s" % reward, func(): pass, Vector2(140, 40), UI.GREEN)
		b.add_theme_font_size_override("font_size", 16)
		b.position = Vector2(w - 146, 5)
		b.pressed.connect(_claim.bind(q, b))
		row.add_child(b)
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
	b.queue_free()
	Game.player.karat = r.data.get("karat", Game.player.get("karat", 0))
	Game.player.contraband = r.data.get("contraband", Game.player.get("contraband", 0))
	_karat.text = str(int(Game.player.karat))
	_contraband.text = str(int(Game.player.contraband))
	Sfx.play("promote", 1.2, -6.0)
	UI.toast(self, "Quest reward claimed!", UI.GREEN)
