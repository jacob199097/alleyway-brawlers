extends Control
## STREET SCHOOL: illustrated lessons, page by page. A real card from the game, big, with boxes and
## arrows pointing at each part of it (its cost, name, crest, art, type line, text, ATK/DEF, number);
## a page for every kind of card (Brawlers, Strivers, Heavies, Leaders, Hustles, Ambushes); the
## keywords (from scripts/keywords.gd, so new ones show up by themselves); and how you get stronger
## (Karat, packs, Dust, levels, ranks, quests, mastery, veterans, the turf map).
## The tutorial (scripts/duel/tutorial.gd) opens chapters as it goes; How to Play opens them all.
##   load("res://scripts/ui/card_school.gd").open(parent, ["anatomy"], on_done)   (no class_name: patches)

const Keywords := preload("res://scripts/keywords.gd")
const CHAPTERS := ["anatomy", "characters", "leaders", "hustles", "ambushes", "keywords", "progress"]
const CHAPTER_NAMES := {"anatomy": "READING A CARD", "characters": "CHARACTERS", "leaders": "LEADERS",
	"hustles": "HUSTLES", "ambushes": "AMBUSHES", "keywords": "KEYWORDS", "progress": "GETTING STRONGER"}

## Where each part of a card is, as a fraction of the card picture (every Forge card shares the layout)
const AT := {
	"cost": Vector2(0.075, 0.055), "name": Vector2(0.5, 0.072), "crest": Vector2(0.925, 0.06),
	"art": Vector2(0.5, 0.33), "type": Vector2(0.5, 0.606), "text": Vector2(0.42, 0.7),
	"flavour": Vector2(0.5, 0.825), "atk": Vector2(0.25, 0.909), "def": Vector2(0.74, 0.909),
	"number": Vector2(0.88, 0.975), "influence": Vector2(0.84, 0.655),
}

const CARD := Vector2(430, 609)        # one card, big
const CARD_POS := Vector2(745, 140)
const SMALL := Vector2(290, 411)       # a row of cards
const BOX_W := 440.0

var chapters: Array = []
var on_done := Callable()
var _pages: Array = []
var _at := 0
var _stage: Control      # the page's content, rebuilt per page
var _title: Label
var _chapter: Label
var _count: Label
var _back: Button
var _next: Button
var _lines: Array = []   # the page's arrows (their dots pulse: redrawn every frame)


static func open(parent: Node, which: Array = [], done := Callable()) -> Control:
	var s: Control = load("res://scripts/ui/card_school.gd").new()
	s.chapters = which if not which.is_empty() else CHAPTERS.duplicate()
	s.on_done = done
	parent.add_child(s)
	return s


func _ready() -> void:
	theme = UI.theme()
	size = Vector2(1920, 1080)
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0.015, 0.012, 0.04, 0.96)
	veil.size = size
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	_chapter = UI.label("", 20, UI.MUTED, true)
	_chapter.position = Vector2(40, 30)
	add_child(_chapter)
	_title = UI.label("", 44, UI.GOLD, true)
	_title.size = Vector2(1920, 60)
	_title.position = Vector2(0, 46)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	var close := UI.button("CLOSE  ✕", _done, Vector2(170, 48))
	close.position = Vector2(1720, 24)
	add_child(close)
	_stage = Control.new()
	_stage.size = size
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_back = UI.button("◀  BACK", func(): _go(_at - 1), Vector2(220, 60))
	_back.position = Vector2(560, 990)
	add_child(_back)
	_count = UI.label("", 22, UI.MUTED, true)
	_count.size = Vector2(360, 60)
	_count.position = Vector2(780, 1000)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_count)
	_next = UI.button("NEXT  ▶", func(): _go(_at + 1), Vector2(260, 60), UI.GOLD)
	_next.position = Vector2(1140, 990)
	add_child(_next)
	for ch in chapters:
		_pages.append_array(_chapter_pages(str(ch)))
	if _pages.is_empty():
		_done()
		return
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
	_go(0)


## Keys go here while it's open (the duel underneath mustn't see Space or Esc).
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	get_viewport().set_input_as_handled()
	match e.keycode:
		KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_go(_at + 1)
		KEY_LEFT:
			_go(_at - 1)
		KEY_ESCAPE:
			_done()


func _go(i: int) -> void:
	if i >= _pages.size():
		_done()
		return
	if i < 0:
		return
	_at = i
	Sfx.play("whoosh", 1.4, -12.0)
	for c in _stage.get_children():
		c.queue_free()
	_lines.clear()
	var p: Dictionary = _pages[i]
	_title.text = str(p.title)
	_chapter.text = "STREET SCHOOL  ·  " + str(CHAPTER_NAMES.get(p.chapter, ""))
	_count.text = "%d / %d" % [i + 1, _pages.size()]
	_back.disabled = i == 0
	_next.text = "DONE  ✓" if i == _pages.size() - 1 else "NEXT  ▶"
	match str(p.get("mode", "single")):
		"single":
			_single(p)
		"row":
			_row(p)
		"tiles":
			_tiles(p)
	if p.has("text"):
		_page_text(str(p.text), 806 if p.get("mode", "single") != "tiles" else 900)


func _process(_delta: float) -> void:
	for l in _lines:
		if is_instance_valid(l):
			l.queue_redraw()


func _done() -> void:
	if not is_inside_tree():
		return
	set_process_input(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)
	if on_done.is_valid():
		on_done.call()


# ── Page layouts ─────────────────────────────────────────────────────────────

## One big card with callouts down both sides, each with an arrow to its part of the card.
## p.callouts: [[part, heading, text], ...]; parts left of the card's middle go on the left.
func _single(p: Dictionary) -> void:
	var c: Dictionary = p.cards[0]
	var rect := Rect2(CARD_POS, CARD)
	_card(c, rect)
	var left: Array = []
	var right: Array = []
	for co in p.get("callouts", []):
		var a: Vector2 = AT[co[0]] if co[0] is String else co[0]
		(left if a.x < 0.5 or (a.x == 0.5 and left.size() <= right.size()) else right).append([a, co[1], co[2]])
	var n := 0
	const STEP := 126.0   # a box's height and the gap under it
	for side in [left, right]:
		var on_left: bool = side == left
		side.sort_custom(func(x, y): return x[0].y < y[0].y)
		# Each box level with its part of the card, pushed apart where they'd overlap, kept on screen
		var ys: Array = []
		for i in side.size():
			var want: float = rect.position.y + side[i][0].y * rect.size.y - 40.0
			ys.append(maxf(want, (ys[i - 1] + STEP) if i > 0 else 120.0))
		for i in range(side.size() - 1, -1, -1):
			var limit: float = 800.0 - STEP * (side.size() - i)
			if ys[i] > limit:
				ys[i] = limit
		for i in side.size():
			var a: Vector2 = side[i][0]
			if absf(a.x - 0.5) < 0.01:   # (a part in the middle: point at its near side, so arrows don't cross)
				a.x = 0.36 if on_left else 0.64
			var box := _callout(side[i][1], side[i][2], p.get("color", UI.GOLD))
			box.position = Vector2(CARD_POS.x - 60 - BOX_W if on_left else CARD_POS.x + CARD.x + 60, ys[i])
			_arrow(box, rect.position + a * rect.size, on_left, n)
			n += 1


## A row of cards, each with a caption under it and an arrow from the caption to one part of it.
## p.captions: [[part, heading, text], ...] one per card.
func _row(p: Dictionary) -> void:
	var cards: Array = p.cards
	var k := cards.size()
	var w := SMALL.x * (0.9 if k >= 4 else 1.0)
	var size := Vector2(w, w * SMALL.y / SMALL.x)
	var gap := 60.0 if k <= 3 else 34.0
	var x0 := (1920.0 - (k * size.x + (k - 1) * gap)) / 2.0
	for i in k:
		var rect := Rect2(Vector2(x0 + i * (size.x + gap), 132), size)
		_card(cards[i], rect)
		if i < p.get("captions", []).size():
			var cap: Array = p.captions[i]
			var box := _callout(cap[1], cap[2], p.get("color", UI.GOLD), rect.size.x + 20)
			box.position = Vector2(rect.position.x - 10, rect.end.y + 26)
			if cap[0] != "":
				_arrow(box, rect.position + AT[cap[0]] * rect.size, false, i, true)


## A grid of coloured tiles: [[heading, colour, text], ...] (keywords, ways to get stronger).
func _tiles(p: Dictionary) -> void:
	var tiles: Array = p.tiles
	var cols := int(p.get("cols", 3))
	var tw := (1760.0 - (cols - 1) * 20.0) / cols
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 16)
	grid.position = Vector2(80, 130)
	_stage.add_child(grid)
	var i := 0
	for t in tiles:
		var col: Color = t[1]
		var panel := UI.panel(Color(col, 0.85), Color(0.04, 0.035, 0.09, 0.96))
		panel.custom_minimum_size = Vector2(tw, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		panel.add_child(v)
		v.add_child(UI.label(str(t[0]), 22, col, true))
		var body := RichTextLabel.new()
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.custom_minimum_size = Vector2(tw - 30, 0)
		body.add_theme_font_size_override("normal_font_size", 17)
		body.add_theme_font_size_override("bold_font_size", 17)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.text = _rich(str(t[2]))
		v.add_child(body)
		grid.add_child(panel)
		panel.modulate.a = 0.0
		panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.25).set_delay(0.04 * i)
		i += 1


func _page_text(text: String, y: float) -> void:
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.position = Vector2(260, y)
	body.custom_minimum_size = Vector2(1400, 0)
	body.size = Vector2(1400, 0)
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_font_size_override("bold_font_size", 21)
	body.add_theme_color_override("default_color", Color(0.88, 0.88, 0.96))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.text = "[center]%s[/center]" % _rich(text)
	_stage.add_child(body)


## BBCode with keywords coloured (Keywords.markup) in the text between its tags.
static func _rich(text: String) -> String:
	var re := RegEx.create_from_string("\\[/?[a-z]+[^\\]]*\\]")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += Keywords.markup(text.substr(at, m.get_start() - at)) + m.get_string()
		at = m.get_end()
	return out + Keywords.markup(text.substr(at))


# ── Pieces ───────────────────────────────────────────────────────────────────

func _card(c: Dictionary, rect: Rect2) -> void:
	var art := UI.texture_rect(UI.card_art(c), rect.size)
	art.position = rect.position
	if art.texture:
		art.material = UI.card_material(rect.size, int(c.get("rarity", 1)))
	_stage.add_child(art)
	if art.texture == null:   # (art not synced: its name at least)
		var l := UI.label(str(c.get("name", "?")), 28, Color.WHITE, true)
		l.position = rect.position + Vector2(20, 20)
		_stage.add_child(l)
	art.pivot_offset = rect.size / 2
	art.scale = Vector2.ONE * 0.92
	art.create_tween().tween_property(art, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _callout(heading: String, text: String, col: Color, width := BOX_W) -> Control:
	var panel := UI.panel(Color(col, 0.9), Color(0.035, 0.03, 0.08, 0.97))
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	v.add_child(UI.label(heading, 20, col, true))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(width - 30, 0)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_font_size_override("bold_font_size", 16)
	body.add_theme_color_override("default_color", Color(0.86, 0.86, 0.94))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.text = _rich(text)
	v.add_child(body)
	_stage.add_child(panel)
	return panel


## A line from the box to the point on the card, with a glowing dot there; it draws itself in.
func _arrow(box: Control, to: Vector2, from_left: bool, n: int, from_top := false) -> void:
	var line := Control.new()
	line.size = Vector2(1920, 1080)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(line)   # (over the card: the arrow ends on the part it explains)
	var grow := [0.0]
	var col := UI.GOLD
	line.draw.connect(func():
		if not is_instance_valid(box):
			return
		var r := box.get_rect()
		var from := Vector2(r.position.x + r.size.x / 2.0, r.position.y) if from_top \
			else Vector2(r.end.x if from_left else r.position.x, r.position.y + minf(r.size.y / 2.0, 36.0))
		var end := from.lerp(to, grow[0])
		line.draw_line(from, end, Color(0, 0, 0, 0.6), 6.0, true)
		line.draw_line(from, end, col, 3.0, true)
		if grow[0] >= 0.999:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0 + n)
			line.draw_circle(to, 9.0 + pulse * 5.0, Color(col, 0.25))
			line.draw_circle(to, 6.0, Color(0, 0, 0, 0.7))
			line.draw_circle(to, 4.5, col))
	box.modulate.a = 0.0
	var t := box.create_tween()
	t.tween_interval(0.15 + n * 0.12)
	t.tween_property(box, "modulate:a", 1.0, 0.2)
	t.tween_method(func(v: float):
		grow[0] = v
		line.queue_redraw(), 0.0, 1.0, 0.25)
	_lines.append(line)


# ── Picking cards ────────────────────────────────────────────────────────────

## A real card that passes `ok`, with art, the most typical first (rarity 2-3, with text and flavour).
static func _pick(ok: Callable, avoid: Array = []) -> Dictionary:
	var best := {}
	var best_score := -1
	for id in CardDB.all():
		var c: Dictionary = CardDB.get_card(id)
		if c.get("token", false) or id in avoid or not ok.call(c) or CardDB.art(id) == null:
			continue
		var r := int(c.get("rarity", 1))
		var score := (3 if r in [2, 3] else 1) + (2 if str(c.get("flavourText", "")) != "" else 0) \
			+ (2 if str(c.get("effectText", "")).length() in range(30, 160) else 0)
		if score > best_score:
			best = c
			best_score = score
	return best


func _chapter_pages(ch: String) -> Array:
	var out: Array = []
	match ch:
		"anatomy":
			var c := _pick(func(c): return c.get("cardType") == "gang_member" and c.get("subtype") == "brawler")
			if c.is_empty():
				return out
			out.append({"chapter": ch, "title": "READING A CARD", "cards": [c], "callouts": [
				["cost", "AUTHORITY COST", "What it costs to play. You get 1 Authority on turn 1 and 1 more every turn after."],
				["name", "NAME", "Up to 3 copies of a card in a deck."],
				["crest", "CLAN CREST", "Its clan. Many cards work best with others from the same clan."],
				["art", "ARTWORK", "Rarer cards shine and move. Hover a card in a duel to read it, right-click to zoom."],
				["type", "TYPE LINE", "What kind of card it is: [b]Brawler[/b], [b]Striver[/b] (with its level), [b]Heavy[/b], Leader, Hustle or Ambush, and its clan."],
				["text", "EFFECT", "What it does, and [b]when[/b]: when deployed, when it attacks, while it's on the field... Coloured words are keywords: hover them."],
				["flavour", "FLAVOUR TEXT", "Just for fun: who they are, in their own words."],
				["atk", "ATK", "Its attack. In a brawl, ATK against ATK: the higher number wins."],
				["def", "DEF", "Its defence: what an attacker must beat while it's in DEF position, or Downed."],
				["number", "CARD NUMBER & RARITY", "Its number in the set, and its rarity: C, U, R, E or L (Common to Legendary)."],
			], "text": "Every card has the same layout. Learn it once and you can read any card in the game."})
		"characters":
			var b := _pick(func(c): return c.get("cardType") == "gang_member" and c.get("subtype") == "brawler")
			if not b.is_empty():
				out.append({"chapter": ch, "title": "BRAWLERS", "cards": [b], "color": Color("ff8f6b"), "callouts": [
					["type", "BRAWLER", "A standalone fighter. What you see is what you get."],
					["cost", "USUALLY CHEAP", "Most Brawlers cost little, so they fill your board early."],
					["atk", "ATK / DEF", "Summon it in [b]ATK[/b] (upright) to attack, or [b]DEF[/b] (sideways) to block."],
					["text", "ITS EFFECT", "Many have an effect that fires when deployed, when attacking, or every turn."],
				], "text": "Characters fight from your front row (5 lanes). You choose ATK or DEF when you deploy them, and can switch once per turn."})
			var lv1 := _pick(func(c): return c.get("subtype") == "striver" and int(c.get("level", 1)) == 1 and CardDB.striver_line(str(c.id)).size() >= 3)
			if not lv1.is_empty():
				var line: Array = CardDB.striver_line(str(lv1.id)).map(func(i): return CardDB.get_card(i))
				out.append({"chapter": ch, "mode": "row", "title": "STRIVERS", "cards": line.slice(0, 3), "color": Color("6fd3ff"), "captions": [
					["type", "LEVEL 1", "Played from your hand like any character. Its type line says [b]LV1[/b]: the first of its levels."],
					["text", "LEVEL 2", "Waits in your [b]Hideout[/b]. When the Level 1 meets its PROMOTE condition, it becomes this."],
					["atk", "LEVEL 3", "Its strongest form. A Striver can't attack the turn it promotes."],
				], "text": "A [b]Striver[/b] grows as it fights. Its higher levels go in your deck's [b]Hideout[/b] (not your hand), and its text says how it [b]PROMOTE[/b]s."})
			var h := _pick(func(c): return c.get("subtype") == "heavy")
			if not h.is_empty():
				out.append({"chapter": ch, "title": "HEAVIES", "cards": [h], "color": Color("ff5a5a"), "callouts": [
					["type", "HEAVY · SACRIFICE X", "To play it, you [b]sacrifice[/b] X of your own characters on the field. It takes one of their lanes."],
					["cost", "BIG COST", "Heavies cost a lot of Authority: they're your late-game hitters."],
					["atk", "BIG NUMBERS", "In return, huge ATK and DEF, and strong effects."],
					["text", "HEAVY EFFECTS", "Often the effects that win games."],
				], "text": "Plan for your Heavy: keep a cheap character on the field to sacrifice, and save Authority for the turn you play it."})
		"leaders":
			var l := _pick(func(c): return c.get("cardType") == "leader")
			if not l.is_empty():
				out.append({"chapter": ch, "title": "LEADERS", "cards": [l], "color": UI.GOLD, "callouts": [
					["type", "LEADER", "Every deck has one. It starts the match [b]Dormant[/b], beside your board."],
					["text", "DORMANT EFFECT & AWAKEN", "While Dormant, its effect helps you. When its [b]AWAKEN[/b] condition is met, it can take the field as a character."],
					["influence", "INFLUENCE", "Your rival can attack your Dormant leader. Each hit wears its Influence down; at 0 it's [b]defeated[/b] and its effect stops."],
					["atk", "ATK / DEF", "Its strength once Awakened: usually the strongest card in your deck."],
				], "text": "Your leader is your deck's heart: pick one whose effect helps your plan, and guard it while it's Dormant."})
		"hustles":
			var plain := _pick(func(c): return c.get("cardType") == "hustle" and str(c.get("subtype", "")) == "")
			var cont := _pick(func(c): return c.get("cardType") == "hustle" and c.get("subtype") == "continuous")
			var eq := _pick(func(c): return c.get("cardType") == "hustle" and c.get("subtype") == "equip")
			var row: Array = []
			var caps: Array = []
			if not plain.is_empty():
				row.append(plain)
				caps.append(["text", "HUSTLE", "Play it, its effect happens, then it goes to the Gutter. Or set it face-down for free and use it later, any phase of your turn."])
			if not cont.is_empty():
				row.append(cont)
				caps.append(["type", "CONTINUOUS", "Stays face-up in your back row and keeps working until it's destroyed."])
			if not eq.is_empty():
				row.append(eq)
				caps.append(["type", "EQUIP", "Attaches to one of your characters and gives it its effect. Gone when that character leaves."])
			if not row.is_empty():
				out.append({"chapter": ch, "mode": "row", "title": "HUSTLES", "cards": row, "captions": caps, "color": Color("ffc46b"),
					"text": "Hustles are your tricks: card draw, removal, buffs. They go in your [b]back row[/b] (5 slots behind your characters)."})
		"ambushes":
			var amb := _pick(func(c): return c.get("cardType") == "ambush" and str(c.get("subtype", "")) == "")
			if not amb.is_empty():
				out.append({"chapter": ch, "title": "AMBUSHES", "cards": [amb], "color": Color("c86bff"), "callouts": [
					["type", "AMBUSH", "Set it [b]face-down[/b] in your back row. Your opponent sees a card, not which one."],
					["cost", "PAY WHEN YOU SET IT", "Its cost is paid when you set it, and your rival doesn't see what you paid."],
					["text", "SPRING IT", "When an enemy attacks one of your characters, you may spring it: its effect happens first, then the attack goes on (if it still can)."],
				], "text": "A face-down card in their back row could be anything: think before you swing. [b]Continuous[/b] Ambushes can also be flipped on your own turn and stay face-up."})
		"keywords":
			var names: Array = Keywords.LIST.keys().filter(func(k): return k != "EXILES")
			var per := 12
			for at in range(0, names.size(), per):
				var tiles: Array = []
				for k in names.slice(at, at + per):
					var e: Array = Keywords.LIST[k]
					var desc := str(e[1])
					var colon := desc.find(":")
					var said := desc.substr(colon + 1).strip_edges() if colon >= 0 else desc
					tiles.append([Keywords.full_name(k), e[0], said.left(1).to_upper() + said.substr(1)])
				out.append({"chapter": ch, "mode": "tiles", "cols": 3, "title": "KEYWORDS  (%d / %d)" % [at / per + 1, ceili(names.size() / float(per))], "tiles": tiles,
					"text": "Keywords are coloured in card text. In a duel, hover one to read it again."})
		"progress":
			out.append({"chapter": ch, "mode": "tiles", "cols": 3, "title": "GETTING STRONGER", "tiles": [
				["KARAT", UI.GOLD, "The money of the streets. Every match pays it (wins pay more, online pays more than CPU), and so do quests, the daily reward, achievements and the turf map."],
				["PACKS", Color("ff8f6b"), "[b]200 Karat[/b] buys a clan pack of new cards. Every level you gain gives you a [b]free pack[/b] too: pick it in the Shop."],
				["DUST & CRAFTING", Color("b388ff"), "In the Card Library, [b]scrap[/b] cards you don't need into Dust, and [b]craft[/b] the exact cards you want with it. SCRAP EXTRAS turns every spare copy into Dust at once."],
				["CONTRABAND", Color("ff4d8d"), "The premium currency, bought in the store (some quests pay it). It opens packs too. Nothing in the game needs it."],
				["XP & LEVELS", UI.BLUE, "Every match gives XP. Levels give a free pack, a new emblem and title, and every 5 levels a profile picture. Your [b]first win each day[/b] gives bonus XP."],
				["DAILY QUESTS & REWARD", UI.GREEN, "Quests on the main menu (win matches, play cards, open a pack) pay Karat. Log in each day for the daily reward: day 7 gives a free pack."],
			], "text": "Everything is earned by playing: no card is locked behind real money."})
			out.append({"chapter": ch, "mode": "tiles", "cols": 3, "title": "CLIMBING THE STREETS", "tiles": [
				["RANKED BRAWL", Color("ffd34d"), "From level 5, a best of 3 against another player. Winning the series earns Rank Points, losing it costs some. Climb from [b]Rookie[/b] to Street Tough, Enforcer, Underboss, Kingpin and [b]Legend[/b]."],
				["CLAN MASTERY", Color("6fd3ff"), "Each clan you play levels up on its own (10 levels), paying Karat, that clan's profile pictures and titles."],
				["VETERAN CARDS", Color("d0905a"), "Win with a card and it remembers: 5 wins makes it [b]Seasoned[/b], 15 [b]Battle-Scarred[/b] (holo foil), 40 a [b]Street Legend[/b] (gold foil). Your rivals see it."],
				["ACHIEVEMENTS", Color("ff9a3c"), "Goals of every kind, paying Karat, Dust, titles, profile pictures and card backs."],
				["TURF DEFENSE", Color("ff4d6d"), "Team up with another player against a clan boss. Beat it on Street for its [b]prize card[/b], a card you can't get anywhere else."],
				["THE TURF MAP", Color("ff6a4a"), "Every match wins influence for your clan in the district you fight in. Hold districts when the week ends to earn Karat; top fighter in one is its [b]boss[/b]."],
			], "text": "Play your way: every mode moves you forward."})
	for p in out:
		if not p.has("cards"):
			p.cards = []
	return out
