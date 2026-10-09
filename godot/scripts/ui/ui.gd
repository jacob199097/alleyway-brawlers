class_name UI
extends RefCounted
## Shared look and building blocks for the menu screens: theme, labels, buttons, panels,
## backgrounds, toasts, dialogs and the card zoom.

const BLUE := Color("4cc9f0")
const RED := Color("e63946")
const GOLD := Color("f4d35e")
const GREEN := Color("4caf50")
const PURPLE := Color("e040fb")
const INK := Color(0.03, 0.03, 0.08, 0.92)
const MUTED := Color(0.62, 0.66, 0.82)

const RARITY_COLOR := {1: Color("aaaaaa"), 2: Color("4cc9f0"), 3: Color("f4d35e"), 4: Color("c77dff"), 5: Color("ff6b35")}
const RARITY_LABEL := {1: "Common", 2: "Rare", 3: "Epic", 4: "Legendary", 5: "Mythic"}
const TITLES := [[1, "Street Prospect"], [5, "Alley Runner"], [10, "Corner Hustler"], [15, "Turf Brawler"],
	[20, "Made Enforcer"], [25, "Shot Caller"], [30, "District Fixer"], [35, "Crew Chief"],
	[40, "Underboss"], [45, "Syndicate Kingpin"], [50, "King of the Streets"]]
const TYPE_NAMES := {"gang_member": "GANG MEMBER", "hustle": "HUSTLE", "ambush": "AMBUSH", "leader": "LEADER"}

static var _font: SystemFont
static var _theme: Theme
static var _tex := {}


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	return _font


static func theme() -> Theme:
	if _theme:
		return _theme
	var th := Theme.new()
	th.default_font_size = 20
	th.set_stylebox("panel", "Panel", box(INK, Color(1, 1, 1, 0.12), 2, 10))
	th.set_stylebox("panel", "PanelContainer", box(INK, Color(1, 1, 1, 0.12), 2, 10))
	th.set_stylebox("normal", "Button", box(Color("1c2040"), Color(BLUE, 0.7), 2, 8))
	th.set_stylebox("hover", "Button", box(Color("28305e"), GOLD, 2, 8))
	th.set_stylebox("pressed", "Button", box(Color("12162e"), GOLD, 2, 8))
	th.set_stylebox("disabled", "Button", box(Color("0d0f1e"), Color(1, 1, 1, 0.1), 2, 8))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", GOLD)
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	th.set_font("font", "Button", font())
	th.set_font_size("font_size", "Button", 22)
	th.set_stylebox("normal", "LineEdit", box(Color("1a1a2e"), Color(BLUE, 0.8), 2, 6))
	th.set_stylebox("focus", "LineEdit", box(Color("1a1a2e"), GOLD, 2, 6))
	th.set_font_size("font_size", "LineEdit", 22)
	th.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.35))
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.9, 1.0))
	th.set_font_size("normal_font_size", "RichTextLabel", 18)
	var track := box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	th.set_stylebox("slider", "HSlider", track)
	var filled := box(BLUE, Color(0, 0, 0, 0), 0, 6)
	filled.content_margin_top = 6
	filled.content_margin_bottom = 6
	th.set_stylebox("grabber_area", "HSlider", filled)
	th.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var grab := box(Color(BLUE, 0.5), Color(0, 0, 0, 0), 0, 4)
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", box(BLUE, Color(0, 0, 0, 0), 0, 4))
	th.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4))
	_theme = th
	return th


static func box(bg: Color, border: Color, width := 2, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func label(text: String, font_size := 20, color := Color.WHITE, heading := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	if heading:
		ls.font = font()
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = maxi(3, font_size / 10)
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, on_press: Callable, size := Vector2(240, 56), accent := BLUE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	if accent != BLUE:
		b.add_theme_stylebox_override("normal", box(accent.darkened(0.7), accent, 2, 8))
		b.add_theme_stylebox_override("hover", box(accent.darkened(0.55), GOLD, 2, 8))
	b.pressed.connect(func():
		Sfx.play("click")
		on_press.call())
	return b


## A button made of artwork (menu tiles): brightens and grows on hover.
static func image_button(path: String, size: Vector2, on_press: Callable, fallback := "") -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = tex(path)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = size
	b.size = size
	b.pivot_offset = size / 2
	if b.texture_normal == null and fallback != "":
		var l := label(fallback, 40, GOLD, true)
		l.size = size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
	b.mouse_entered.connect(func():
		Sfx.play("click", 1.4, -10.0)
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE * 1.04, 0.1)
		t.tween_property(b, "modulate", Color(1.25, 1.25, 1.25), 0.1))
	b.mouse_exited.connect(func():
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE, 0.12)
		t.tween_property(b, "modulate", Color.WHITE, 0.12))
	b.pressed.connect(func():
		Sfx.play("click")
		on_press.call())
	return b


static func panel(accent := Color(1, 1, 1, 0.12), bg := INK) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, accent, 2, 12))
	return p


## A texture from res://assets, or null if it isn't synced yet.
static func tex(path: String) -> Texture2D:
	if not path.begins_with("res://"):
		path = "res://assets/%s" % path
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[path] = t
	return t


static func texture_rect(t: Texture2D, size: Vector2, cover := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Full-screen background art with a dark veil.
static func background(parent: Control, path := "menu_background.png", dim := 0.55) -> void:
	var bg := texture_rect(tex(path), Vector2(1920, 1080), true)
	parent.add_child(bg)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, dim)
	veil.size = Vector2(1920, 1080)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(veil)


## Screen title centred at the top.
static func title(parent: Control, text: String, color := GOLD) -> Label:
	var l := label(text, 48, color, true)
	l.size = Vector2(1920, 70)
	l.position = Vector2(0, 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


static func back_button(parent: Control, on_press: Callable, text := "←  BACK") -> Button:
	var b := button(text, on_press, Vector2(200, 56))
	b.position = Vector2(32, 1080 - 56 - 28)
	parent.add_child(b)
	return b


static func toast(parent: Control, msg: String, color := BLUE) -> void:
	var l := label(msg, 24, color, true)
	var p := panel(color)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var sz := p.get_combined_minimum_size()
	p.position = Vector2(960 - sz.x / 2, 1080 - 150)
	var t := p.create_tween()
	t.tween_interval(2.2)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


## A modal dialog. buttons: [[label, callable, accent?], ...]; each closes the dialog first.
static func dialog(parent: Control, heading: String, text: String, buttons: Array, accent := GOLD) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.7)
	veil.size = Vector2(1920, 1080)
	parent.add_child(veil)
	var p := panel(accent, Color(0.04, 0.04, 0.12, 0.98))
	p.custom_minimum_size = Vector2(760, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	var h := label(heading, 36, accent, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	if text != "":
		var t := label(text, 22, Color(0.85, 0.85, 0.95))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.custom_minimum_size = Vector2(700, 0)
		col.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	for spec in buttons:
		var cb: Callable = spec[1]
		row.add_child(button(spec[0], func():
			veil.queue_free()
			cb.call(), Vector2(220, 56), spec[2] if spec.size() > 2 else BLUE))
	veil.add_child(p)
	p.reset_size()
	var sz := p.get_combined_minimum_size()
	p.position = (Vector2(1920, 1080) - sz) / 2
	return veil


## "LOADING…" text that pulses until freed.
static func spinner(parent: Control, pos: Vector2, text := "LOADING…") -> Label:
	var l := label(text, 28, BLUE, true)
	l.size = Vector2(600, 40)
	l.position = pos - l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	var t := l.create_tween().set_loops()
	t.tween_property(l, "modulate:a", 0.3, 0.5)
	t.tween_property(l, "modulate:a", 1.0, 0.5)
	return l


static func player_title(level: int) -> String:
	var out: String = TITLES[0][1]
	for entry in TITLES:
		if level >= entry[0]:
			out = entry[1]
	return out


## XP within the current level, on the backend's curve: {current, needed, pct}
static func xp_progress(p: Dictionary) -> Dictionary:
	var lvl := mini(int(p.get("level", 1)), 50)
	var at_level := 0
	for i in range(1, lvl):
		at_level += int(floor(100.0 * pow(i, 1.5)))
	var needed := int(floor(100.0 * pow(lvl, 1.5)))
	if lvl >= 50:
		return {"current": needed, "needed": needed, "pct": 1.0}
	var current := clampi(int(p.get("xp", 0)) - at_level, 0, needed)
	return {"current": current, "needed": needed, "pct": float(current) / needed if needed > 0 else 1.0}


static func rarity_color(r) -> Color:
	return RARITY_COLOR.get(int(r) if r != null else 1, RARITY_COLOR[1])


## Card art for a server row / catalog card (art_url, cardId or id).
static func card_art(c: Dictionary) -> Texture2D:
	for key in ["art_url", "cardId", "id"]:
		var v = c.get(key)
		if v is String and v != "":
			var t := CardDB.art(v)
			if t:
				return t
	return null


## Large card view over everything: art, name, type line, stats and effect text.
static func card_zoom(parent: Control, c: Dictionary) -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.78)
	veil.size = Vector2(1920, 1080)
	parent.add_child(veil)
	veil.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			veil.queue_free())
	var art := texture_rect(card_art(c) if card_art(c) else CardDB.back(), Vector2(520, 736))
	art.position = Vector2(400, 172)
	veil.add_child(art)
	var info := VBoxContainer.new()
	info.position = Vector2(980, 230)
	info.custom_minimum_size = Vector2(560, 0)
	info.add_theme_constant_override("separation", 12)
	veil.add_child(info)
	var rarity := int(c.get("rarity", 1)) if c.get("rarity") != null else 1
	info.add_child(label(str(c.get("name", "?")), 48, Color.WHITE, true))
	var kind := str(c.get("cardType", c.get("card_type", "")))
	var line: Array = [TYPE_NAMES.get(kind, "CARD"), str(RARITY_LABEL.get(rarity, "")).to_upper()]
	var sub = c.get("subtype")
	if sub is String:
		line.insert(1, sub.to_upper())
	if c.get("authority") != null:
		line.append("AUTHORITY %d" % int(c.authority))
	info.add_child(label("  ·  ".join(line), 20, rarity_color(rarity)))
	if kind in ["gang_member", "leader"] and c.get("attack") != null:
		info.add_child(label("ATK %d    DEF %d" % [int(c.attack), int(c.get("defense", 0))], 32, GOLD, true))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(560, 0)
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("italics_font_size", 20)
	var text := str(c.get("effectText", c.get("effect_text", "")))
	var flavour = c.get("flavourText", c.get("flavour_text"))
	if flavour is String and flavour != "":
		text += "\n\n[i][color=#8a8aa0]%s[/color][/i]" % flavour
	body.text = text
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(body)
	var hint := label("Click anywhere to close", 18, MUTED)
	hint.position = Vector2(860, 1010)
	veil.add_child(hint)
	veil.modulate.a = 0.0
	veil.create_tween().tween_property(veil, "modulate:a", 1.0, 0.12)
