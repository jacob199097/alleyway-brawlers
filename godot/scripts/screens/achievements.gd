extends Screen
## Achievements (backend/economy/achievements.js): every goal with its progress and reward, and
## on the right the looks they unlock: avatar, title and card back.

const ROW := Vector2(1180, 100)

var _data: Dictionary = {}
var _filter := "all"
var _list: VBoxContainer
var _count: Label
var _look: VBoxContainer
var _chips := {}


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.75)
	Game.play_menu_music()
	UI.title(self, "ACHIEVEMENTS")
	UI.back_button(self, func(): Game.go(back_to))
	_count = UI.label("", 24, UI.GOLD, true)
	_count.position = Vector2(1540, 46)
	add_child(_count)
	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 112)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	for f in [["all", "ALL"], ["todo", "TO DO"], ["done", "UNLOCKED"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 50)
		b.add_theme_font_size_override("font_size", 18)
		var key: String = f[0]
		b.pressed.connect(func():
			Sfx.play("click")
			_filter = key
			_render_list())
		_chips[key] = b
		bar.add_child(b)
	var p := UI.glass(UI.panel(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0.45)), Color(0.02, 0.02, 0.06, 0.42))
	p.position = Vector2(30, 180)
	p.size = Vector2(1220, 800)
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var lp := UI.glass(UI.panel(UI.GOLD), Color(0.06, 0.04, 0.02, 0.6))
	lp.position = Vector2(1270, 112)
	lp.size = Vector2(620, 938)
	add_child(lp)
	_look = VBoxContainer.new()
	_look.add_theme_constant_override("separation", 12)
	lp.add_child(_look)
	await _load()


func _load() -> void:
	var spin := UI.spinner(self, Vector2(640, 560))
	var r := await Api.request("GET", "/api/achievements")
	spin.queue_free()
	if not r.ok or not (r.data is Dictionary):
		UI.toast(self, r.error if r.error != "" else "Achievements aren't available right now.", UI.RED)
		return
	_data = r.data
	_render_list()
	_render_look()
	_intro()


func _render_list() -> void:
	for k in _chips:
		_chips[k].set_pressed_no_signal(k == _filter)
	for c in _list.get_children():
		c.queue_free()
	var all: Array = _data.get("achievements", [])
	var done := all.filter(func(a): return a.get("unlocked", false)).size()
	_count.text = "%d / %d UNLOCKED" % [done, all.size()]
	# Closest to done first; unlocked ones after, newest first
	var rows := all.filter(func(a): return _filter == "all" or (_filter == "done") == bool(a.get("unlocked", false)))
	rows.sort_custom(func(a, b):
		if bool(a.unlocked) != bool(b.unlocked):
			return not a.unlocked
		if a.unlocked:
			return str(a.get("unlockedAt", "")) > str(b.get("unlockedAt", ""))
		return _pct(a) > _pct(b))
	for a in rows:
		_list.add_child(_row(a))
	UI.stagger(_list.get_children())
	if rows.is_empty():
		_list.add_child(UI.label("Nothing here yet." if _filter == "done" else "You've unlocked everything!", 26, UI.MUTED, true))


static func _pct(a: Dictionary) -> float:
	return float(a.get("progress", 0)) / maxf(1.0, float(a.get("target", 1)))


func _row(a: Dictionary) -> Control:
	var got: bool = a.get("unlocked", false)
	var clan_col := _clan_color(a.get("clan"))
	var p := UI.panel(UI.GOLD if got else Color(1, 1, 1, 0.14), Color(0.09, 0.07, 0.02, 0.62) if got else Color(0.03, 0.03, 0.08, 0.5))
	p.custom_minimum_size = ROW
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var icon := UI.achievement_icon(got, 60, UI.GOLD if got else Color(0.45, 0.47, 0.6))
	icon.custom_minimum_size = Vector2(64, 0)
	if icon is Label:
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(icon)
	if got:   # (a trophy that catches the light now and then)
		var shine := icon.create_tween().set_loops()
		shine.tween_interval(randf_range(2.0, 6.0))
		shine.tween_property(icon, "self_modulate", Color(1.6, 1.5, 1.1), 0.25)
		shine.tween_property(icon, "self_modulate", Color.WHITE, 0.6)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(UI.label(str(a.get("name", "")).to_upper(), 26, clan_col if clan_col != Color.TRANSPARENT else (UI.GOLD if got else Color.WHITE), true))
	col.add_child(UI.label(str(a.get("desc", "")), 19, Color(0.86, 0.86, 0.95)))
	var target := int(a.get("target", 1))
	if not got and target > 1:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var track := ColorRect.new()
		track.color = Color("1a1a3a")
		track.custom_minimum_size = Vector2(420, 10)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.color = UI.BLUE
		fill.size = Vector2(420 * _pct(a), 10)
		track.add_child(fill)
		UI.grow_bar(fill, 0.35)
		line.add_child(track)
		line.add_child(UI.label("%d / %d" % [int(a.get("progress", 0)), target], 17, UI.BLUE, true))
		col.add_child(line)
	elif got:
		col.add_child(UI.label("Unlocked %s" % str(a.get("unlockedAt", "")).left(10), 16, UI.MUTED))
	var gift := UI.label(UI.reward_text(a.get("reward", {})), 18, UI.GOLD if got else UI.MUTED, true)
	gift.custom_minimum_size = Vector2(330, 0)
	gift.autowrap_mode = TextServer.AUTOWRAP_WORD
	gift.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gift.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gift)
	return p


static func _clan_color(clan) -> Color:
	if not clan is String:
		return Color.TRANSPARENT
	var c := CardDB.clan(clan)
	return c.get("color", UI.PURPLE) if not c.is_empty() else Color.TRANSPARENT


# ── Your look: avatar, title, card back ──────────────────────────────────────

func _render_look() -> void:
	for c in _look.get_children():
		c.queue_free()
	var cos: Dictionary = _data.get("cosmetics", {})
	var eq: Dictionary = _data.get("equipped", {})
	_look.add_child(UI.label("YOUR LOOK", 30, UI.GOLD, true))

	_look.add_child(UI.label("AVATAR", 18, UI.MUTED, true))
	var avs := HFlowContainer.new()
	avs.add_theme_constant_override("h_separation", 10)
	avs.add_theme_constant_override("v_separation", 10)
	_look.add_child(avs)
	var current := str(eq.get("avatar", ""))
	for key in cos.get("avatars", []):
		avs.add_child(_pick(UI.avatar(key), Vector2(84, 84), str(key) == current, func(): _equip({"avatar": key})))
	if current.begins_with("card:") and not current in cos.get("avatars", []):   # (one worn from before)
		avs.add_child(_pick(UI.avatar(current), Vector2(84, 84), true, func(): pass))
	var more := UI.label("More pictures: every 5 levels, each clan's Loyalist achievement and Clan Mastery (on your profile).", 16, UI.MUTED)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD
	more.custom_minimum_size = Vector2(560, 0)
	_look.add_child(more)

	_look.add_child(UI.label("TITLE", 18, UI.MUTED, true))
	var titles := OptionButton.new()
	titles.add_theme_font_size_override("font_size", 20)
	titles.custom_minimum_size = Vector2(560, 50)
	titles.add_item("%s  (level title)" % UI.player_title(int(Game.player.get("level", 1))))
	titles.set_item_metadata(0, null)
	var chosen = eq.get("title")
	for t in cos.get("titles", []):
		titles.add_item(str(t.text))
		titles.set_item_metadata(titles.item_count - 1, str(t.id))
		if chosen is String and chosen == str(t.id):
			titles.select(titles.item_count - 1)
	titles.item_selected.connect(func(i): _equip({"title": titles.get_item_metadata(i)}))
	_look.add_child(titles)

	_look.add_child(UI.label("CARD BACK", 18, UI.MUTED, true))
	var backs := HFlowContainer.new()
	backs.add_theme_constant_override("h_separation", 12)
	backs.add_theme_constant_override("v_separation", 12)
	_look.add_child(backs)
	var back_now = eq.get("back")
	var own_clan := str(Game.player.get("chosen_clan", ""))
	var clan_back := VBoxContainer.new()
	clan_back.add_child(_pick(CardDB.back(own_clan), Vector2(96, 134), back_now == null, func(): _equip({"back": null})))
	clan_back.add_child(_caption("YOUR DECK'S"))
	backs.add_child(clan_back)
	for key in cos.get("backs", []):
		if key == "default":   # the retired Classic back (older servers still list it)
			continue
		var v := VBoxContainer.new()
		v.add_child(_pick(CardDB.back(str(key)), Vector2(96, 134), back_now is String and back_now == key,
			func(): _equip({"back": key})))
		v.add_child(_caption(str(CardDB.clan(str(key)).get("name", key)).to_upper()))
		backs.add_child(v)
	var note := UI.label("Your card back shows on your cards in every match, for both players.", 16, UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size = Vector2(560, 0)
	_look.add_child(note)


func _caption(t: String) -> Label:
	var l := UI.label(t, 13, UI.MUTED, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(96, 0)
	return l


## A clickable picture, outlined in gold when it's the one in use.
func _pick(t: Texture2D, sz: Vector2, on: bool, cb: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = sz + Vector2(8, 8)
	b.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0.3), UI.GOLD if on else Color(1, 1, 1, 0.15), 3 if on else 1, 8))
	b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.08), UI.GOLD if on else UI.BLUE, 3 if on else 2, 8))
	b.add_theme_stylebox_override("pressed", UI.box(Color(1, 1, 1, 0.12), UI.GOLD, 3, 8))
	var img := UI.texture_rect(t, sz, true)
	img.position = Vector2(4, 4)
	b.add_child(img)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


func _equip(change: Dictionary) -> void:
	var r := await Api.request("POST", "/api/achievements/equip", change)
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	var eq: Dictionary = _data.get("equipped", {})
	for k in change:
		eq[k] = change[k]
	if change.has("avatar"):
		Game.player.avatar_url = change.avatar
	if change.has("back"):
		Game.player.card_back = change.back
	if change.has("title"):
		var text = null
		for t in _data.get("cosmetics", {}).get("titles", []):
			if change.title != null and str(t.id) == str(change.title):
				text = t.text
		Game.player.title = text
	_render_look()
	UI.toast(self, "Saved", UI.GREEN)

