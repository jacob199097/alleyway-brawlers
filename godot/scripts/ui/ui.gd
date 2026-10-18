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

## Same names and colours as the Card Forge (RARITY there)
const RARITY_COLOR := {1: Color("a3a3a3"), 2: Color("62b86c"), 3: Color("4f93e3"), 4: Color("a56be3"), 5: Color("eab33a")}
const RARITY_LABEL := {1: "Common", 2: "Uncommon", 3: "Rare", 4: "Epic", 5: "Legendary"}
const TITLES := [[1, "Street Prospect"], [5, "Alley Runner"], [10, "Corner Hustler"], [15, "Turf Brawler"],
	[20, "Made Enforcer"], [25, "Shot Caller"], [30, "District Fixer"], [35, "Crew Chief"],
	[40, "Underboss"], [45, "Syndicate Kingpin"], [50, "King of the Streets"]]
const TYPE_NAMES := {"gang_member": "CHARACTER", "hustle": "HUSTLE", "ambush": "AMBUSH", "leader": "LEADER"}

const LivingBackground := preload("res://scripts/ui/living_bg.gd")

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
	th.set_stylebox("normal", "Button", _shadowed(box(Color("1c2040"), Color(BLUE, 0.7), 2, 8)))
	th.set_stylebox("hover", "Button", _glow(box(Color("28305e"), GOLD, 2, 8), GOLD))
	th.set_stylebox("pressed", "Button", _glow(box(Color("12162e"), GOLD, 2, 8), GOLD, 0.5))
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


## A soft drop shadow under a box.
static func _shadowed(sb: StyleBoxFlat) -> StyleBoxFlat:
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


## A neon glow around a box, in its accent colour.
static func _glow(sb: StyleBoxFlat, color: Color, strength := 1.0) -> StyleBoxFlat:
	sb.shadow_color = Color(color, 0.32 * strength)
	sb.shadow_size = int(16 * strength)
	return sb


## Hover and press feel for any button: it grows a touch and ticks on hover, squashes on
## press, and springs back on release.
static func juice(b: BaseButton) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.pivot_offset = b.size / 2
	var to := func(s: float, secs: float):
		var t := b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE * s, secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.play("hover", randf_range(0.96, 1.04), -6.0)
			to.call(1.04, 0.12))
	b.mouse_exited.connect(func(): to.call(1.0, 0.14))
	b.button_down.connect(func(): to.call(0.95, 0.06))
	b.button_up.connect(func(): to.call(1.04 if b.is_hovered() else 1.0, 0.18))


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
		b.add_theme_stylebox_override("normal", _shadowed(box(accent.darkened(0.7), accent, 2, 8)))
		b.add_theme_stylebox_override("hover", _glow(box(accent.darkened(0.55), GOLD, 2, 8), accent))
	juice(b)
	b.pressed.connect(func():
		Sfx.play("click")
		on_press.call())
	return b


## Rows of a list arriving one after another: each fades up and grows from slightly small (from its
## left edge, so they read as sliding in). Works inside containers (it doesn't move them).
static func stagger(nodes: Array, delay := 0.05, step := 0.045) -> void:
	var i := 0
	for n in nodes:
		if not n is Control or not is_instance_valid(n):
			continue
		var c: Control = n
		c.modulate.a = 0.0
		c.scale = Vector2(0.96, 0.96)
		var at := delay + minf(i * step, 0.6)
		var t := c.create_tween().set_parallel()
		t.tween_callback(func(): c.pivot_offset = Vector2(0, c.size.y / 2)).set_delay(at)
		t.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(at)
		t.tween_property(c, "scale", Vector2.ONE, 0.3).set_delay(at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1


## A bar's fill (a Control sized in code) growing from empty to the width it was given.
static func grow_bar(fill: Control, delay := 0.25, secs := 0.75) -> void:
	var w := fill.size.x
	fill.size.x = 0.0
	fill.create_tween().tween_property(fill, "size:x", w, secs).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Counts a label up (or down) to a number, ticking as it goes: currencies arriving.
static func count_up(l: Label, from: int, to: int, secs := 0.7, fmt := "%d", tick := "") -> void:
	if not is_instance_valid(l):
		return
	l.text = fmt % from
	if from == to:
		return
	var last := [from]
	l.create_tween().tween_method(func(x: float):
		var v := int(round(x))
		if v != last[0]:
			last[0] = v
			l.text = fmt % v
			if tick != "" and v % maxi(1, abs(to - from) / 8) == 0:
				Sfx.play(tick, randf_range(1.2, 1.4), -16.0), float(from), float(to), secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A button made of artwork (menu tiles): its neon blooms (a blurred glow that breathes), and it
## brightens, grows and flares on hover.
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
	var glow: TextureRect = null
	if b.texture_normal:
		glow = TextureRect.new()
		glow.texture = b.texture_normal
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glow.size = size
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gm := ShaderMaterial.new()
		gm.shader = preload("res://shaders/neon_glow.gdshader")
		gm.set_shader_parameter("seed", randf())
		gm.set_shader_parameter("boost", 0.0)   # (set, so hover tweens have a value to start from)
		glow.material = gm
		b.add_child(glow)
	b.mouse_entered.connect(func():
		Sfx.play("hover", 1.0, -8.0)
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE * 1.04, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "modulate", Color(1.2, 1.2, 1.2), 0.12)
		if glow:
			t.tween_property(glow.material, "shader_parameter/boost", 1.0, 0.15))
	b.mouse_exited.connect(func():
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE, 0.14)
		t.tween_property(b, "modulate", Color.WHITE, 0.14)
		if glow:
			t.tween_property(glow.material, "shader_parameter/boost", 0.0, 0.25))
	b.pressed.connect(func():
		Sfx.play("click")
		on_press.call())
	# Neon signs flicker now and then, each on its own rhythm (the glow dips with them, and now and
	# then the tube buzzes)
	var flicker := b.create_tween().set_loops()
	flicker.tween_interval(randf_range(4.0, 11.0))
	flicker.tween_callback(func():
		if randf() < 0.35 and b.is_visible_in_tree():
			Sfx.play("neon_buzz", randf_range(0.95, 1.08), -20.0))
	for a in [0.55, 1.0, 0.7, 1.0, 0.85, 1.0]:
		var d := randf_range(0.03, 0.07)
		flicker.tween_property(b, "self_modulate:a", a, d)
		if glow:
			flicker.parallel().tween_property(glow, "modulate:a", a * a, d)
	return b


static func panel(accent := Color(1, 1, 1, 0.12), bg := INK) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg, accent, 2, 12)
	if accent.a > 0.5:
		_glow(sb, accent, 0.7)
	else:
		_shadowed(sb)
	p.add_theme_stylebox_override("panel", sb)
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


## The 3D card shader (shaders/card.gdshader) set up for a TextureRect of this size.
## Tilt it with set_shader_parameter("y_rot" / "x_rot"); rarity 4+ gets holographic foil.
static func card_material(size: Vector2, rarity := 1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/card.gdshader")
	m.set_shader_parameter("quad_size", size)
	rarity_fx(m, rarity, randf())
	return m


## How a card comes alive by rarity (shaders/card.gdshader): Common and Uncommon stay still; Rare
## glints now and then; Epic's art moves (its glowing parts throb, with a breathing halo) over the
## holographic foil; Legendary's art moves more (shifting colours, drifting scene, rising sparks) and
## twinkles. seed (0..1) keeps cards out of step with each other.
static func rarity_fx(m: ShaderMaterial, rarity: int, seed := 0.0) -> void:
	m.set_shader_parameter("foil", 1.0 if rarity >= 4 else 0.0)
	m.set_shader_parameter("shine", 0.7 if rarity == 3 else 0.0)
	m.set_shader_parameter("art_fx", 0.0 if rarity < 4 else 1.0 if rarity == 4 else 2.0)
	m.set_shader_parameter("sparkle", 1.0 if rarity >= 5 else 0.0)
	m.set_shader_parameter("shine_seed", seed)


static func texture_rect(t: Texture2D, size: Vector2, cover := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Full-screen background art with a dark veil, brought to life (see living_bg.gd).
static func background(parent: Control, path := "menu_background.png", dim := 0.55) -> void:
	parent.add_child(LivingBackground.new().setup(tex(path), dim))


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
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.set_parallel()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
	t.tween_property(p, "position:y", p.position.y, 0.28).from(p.position.y + 40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
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
	p.pivot_offset = sz / 2
	veil.modulate.a = 0.0
	p.scale = Vector2.ONE * 0.9
	var t := veil.create_tween().set_parallel()
	t.tween_property(veil, "modulate:a", 1.0, 0.15)
	t.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("phase", 0.8, -8.0)
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


## The title under a player's name: one they unlocked and chose (achievements), else their level's.
static func shown_title(p: Dictionary) -> String:
	var t = p.get("title")
	return str(t) if t is String and t != "" else player_title(int(p.get("level", 1)))


## A player's avatar (players.avatar_url): always card art. Everyone has each clan's leader and
## commonest characters (shared/clans.js freeAvatars); achievements unlock a clan's rarest card
## ("clan:<clan>") and any owned card ("card:<id>"); every 5 levels unlocks "level:<n>".
static func avatar(key) -> Texture2D:
	# Every profile picture is a crop of card art:
	#   card:<id>   that card · clan:<clan> the clan's rarest character (Loyalist reward) ·
	#   level:<n>   a picture from assets/avatars, else an Epic / Legendary card (every 5 levels) ·
	#   cpu         the CPU opponent · anything else (none yet, retired pictures) the default
	var k := str(key) if key != null else ""
	var id := ""
	if k.begins_with("card:"):
		id = k.substr(5)
	elif k.begins_with("clan:"):
		id = _avatar_card(func(c): return c.get("clan") == k.substr(5) and c.get("cardType") == "gang_member")
	elif k.begins_with("level:"):
		var n := int(k.substr(6))
		var pic := tex("avatars/level_%02d.png" % n)
		if pic:
			return pic
		var rare := _avatar_cards(func(c): return c.get("cardType") == "gang_member" and int(c.get("rarity", 1)) >= 4)
		if rare.is_empty():
			return level_icon(n)
		id = rare[(maxi(1, n / 5) - 1) % rare.size()]
	elif k == "cpu":
		var leaders := _avatar_cards(func(c): return c.get("cardType") == "leader")
		id = leaders[1] if leaders.size() > 1 else _avatar_card(func(c): return c.get("cardType") == "gang_member")
	var art := card_crop(id) if id != "" else null
	if art:
		return art
	# The default: the first leader's art
	art = card_crop(_avatar_card(func(c): return c.get("cardType") == "leader"))
	return art if art else level_icon(1)


## A card's art window (below the name bar) as a square, or null when the card has no art. The
## window runs the card's width and is about 0.64 of it tall: the square is its full height, centred.
static func card_crop(id: String) -> Texture2D:
	var src: Texture2D = CardDB.art(id) if id != "" else null
	if src == null:
		return null
	var s := src.get_size()
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = Rect2(s.x * 0.18, s.y * 0.122, s.x * 0.64, s.x * 0.64)
	return at


## Cards (not tokens) that pass `ok`, rarest first, then by id: the order pictures are picked in.
static func _avatar_cards(ok: Callable) -> Array:
	var out: Array = []
	for cid in CardDB.all():
		var c: Dictionary = CardDB.get_card(cid)
		if not c.get("token", false) and ok.call(c):
			out.append(cid)
	out.sort_custom(func(a, b):
		var ra := int(CardDB.get_card(a).get("rarity", 1))
		var rb := int(CardDB.get_card(b).get("rarity", 1))
		return ra > rb or (ra == rb and str(a) < str(b)))
	return out


static func _avatar_card(ok: Callable) -> String:
	var list := _avatar_cards(ok)
	return list[0] if not list.is_empty() else ""


## What an achievement gives, in a few words: "300 Karat · Title: Untouchable".
static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("karat", 0)) > 0:
		parts.append("%d Karat" % int(r.karat))
	if int(r.get("dust", 0)) > 0:
		parts.append("%d Dust" % int(r.dust))
	if int(r.get("free_packs", 0)) > 0:
		parts.append("%d free pack%s" % [int(r.free_packs), "" if int(r.free_packs) == 1 else "s"])
	if r.get("title") is String:
		parts.append("Title: %s" % r.title)
	if r.get("avatar") is String:
		parts.append("Avatar")
	if r.get("back") is String:
		parts.append("Card back")
	return "  ·  ".join(parts)


## The emblem for a level (assets/levels, drawn by tools/make_badges.gd); past 50 keeps the top one.
static func level_icon(level: int) -> Texture2D:
	return tex("levels/level_%02d.png" % clampi(level, 1, 50))


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
	var rarity_ := int(c.get("rarity", 1)) if c.get("rarity") != null else 1
	var mat := card_material(art.size, rarity_)
	art.material = mat
	veil.add_child(art)
	# The big card tilts toward the mouse and catches the light
	var tilt := [Vector2.ZERO]
	veil.gui_input.connect(func(e):
		if e is InputEventMouseMotion:
			var m: Vector2 = ((e.position - art.position - art.size / 2) / (art.size / 2)).clamp(-Vector2.ONE, Vector2.ONE)
			tilt[0] = Vector2(-m.x, m.y) * 14.0
			mat.set_shader_parameter("y_rot", tilt[0].x)
			mat.set_shader_parameter("x_rot", tilt[0].y)
			mat.set_shader_parameter("glare", clampf(tilt[0].length() / 12.0, 0.0, 1.0)))
	art.pivot_offset = art.size / 2
	art.scale = Vector2.ONE * 0.85
	art.create_tween().tween_property(art, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var swing := art.create_tween()
	swing.tween_method(func(d: float): mat.set_shader_parameter("y_rot", d), -35.0, 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("flip", 0.9, -4.0)
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
