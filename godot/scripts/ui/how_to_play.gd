extends Control
## How to Play: the rules in short sections, open from the duel menu and from Settings (Gameplay).
## The keyword section is built from the keyword glossary (scripts/keywords.gd), so it stays current.
##   load("res://scripts/ui/how_to_play.gd").open(parent)   (no class_name: patches can't add one)

const Keywords := preload("res://scripts/keywords.gd")

## [tab label, text] (BBCode; keywords are coloured by Keywords.markup)
const SECTIONS := [
	["THE GOAL", "Bring your opponent's [b]Morale[/b] from 6000 to 0. A player who has to draw from an empty deck loses too.\n\nEach player has a 40-card deck (up to 3 copies of a card), a [b]leader[/b], and a [b]Hideout[/b] holding the higher levels of their Strivers. You start with 5 cards and may redraw your opening hand once."],
	["A TURN", "[b]DEPLOYMENT[/b]: play cards by paying their Authority (the number in the corner). You get 1 Authority to start and 1 more every turn, up to 15. Going second, you get 1 extra on your first turn.\n\n[b]BRAWL[/b]: attack with your characters in ATK position. Nobody attacks on turn 1.\n\n[b]REGROUP[/b]: deploy again with what Authority is left, then end your turn. You can hold up to 9 cards: discard down to 9 at the end of your turn."],
	["CHARACTERS", "Characters go in your front row, in [b]ATK[/b] (upright) or [b]DEF[/b] (sideways). You choose when you deploy, and once per turn you can switch a character's position.\n\n[b]Strivers[/b] have levels and PROMOTE into the next one from your Hideout (it can't attack the turn it promotes: the ZZZ tag). The [b]stars[/b] on a Striver show its level: one gold star of three is level 1.\n[b]Brawlers[/b] are standalone.\n[b]Heavies[/b] are played onto your own characters: they sacrifice as many as the card says (SACRIFICE 1-3) and take one of their lanes.\n\nA full front row? Drop a character on one of yours (orange lanes) to deploy over it: the old one goes to the Gutter."],
	["BRAWLS", "Attacking a character in [b]ATK[/b]: the higher ATK wins. The loser goes Down and its owner loses Morale equal to the difference. A tie Downs both.\n\nAttacking a character in [b]DEF[/b] (or Downed): beat its DEF to Down it. Its owner loses no Morale (unless the attacker has PIERCE). Fall short and the attack is blocked, and [b]you[/b] lose the difference in Morale.\n\nWhen the enemy has no standing character, you attack them [b]directly[/b]: they lose Morale equal to the attacker's ATK."],
	["DOWNED & KO", "A character that loses a brawl is [b]Downed[/b]: it drops to DEF and its effects stop working. It stands back up at the start of its owner's turn after a full round.\n\nAttacked again while Downed, it is [b]KO'd[/b] and goes to the Gutter.\n\nClick your Gutter, your opponent's Gutter or your Hideout to look through them."],
	["LEADERS", "Your leader starts [b]Dormant[/b]: its Dormant effects help you while it waits. The enemy can attack a Dormant leader to wear down its [b]Influence[/b]: at 0 it is defeated.\n\nWhen its [b]AWAKEN[/b] condition is met (on the card), it may take the field like a character, with its full strength. Usually it can't attack the turn it Awakens."],
	["HUSTLES & AMBUSHES", "A [b]Hustle[/b] does its effects when you play it, then goes to the Gutter. You can also set one face-down in your back row for free, and activate it whenever you choose on your turn (any phase, even the turn you set it), paying its Authority then.\n\nAn [b]Ambush[/b] is set face-down in your back row. When an enemy attacks one of your characters, you may spring it: its effects happen first, then the attack goes on with whatever they changed (an attacker that lost ATK may now lose the brawl). The attack only stops if the Ambush negates it, or the attacker ends up Downed, removed or in STASIS.

A [b]Continuous[/b] Ambush can also be flipped face-up without an attack, once it has been set since an earlier turn: on your turn (click it), or when you're offered the chance at the start of your opponent's turn and after they deploy.\n\nSome are CONTINUOUS (they stay face-up and keep working) or EQUIP (they attach to a character)."],
	["ABILITIES", "Card text tells you when an effect happens: when deployed, when it attacks, when an ally is KO'd...\n\nA [b]teal glow[/b] means a character has an [b]ACTIVATE[/b] ability ready: click it to use it, once per turn, paying any cost shown (Authority, Morale, a discard, a sacrifice, or not attacking this turn).\n\nWhen an effect lets you choose, the cards you can pick glow: click one, or SKIP.\n\n[b]If you do[/b]: that part only happens if the part before it worked.\n\n[b]Luck[/b]: some cards flip a coin or roll a die, shown on the board. \"If tails\" parts follow the same flip. [b]DOUBLE OR NOTHING[/b]: you choose whether to bet. Bet, and a coin decides: heads, it happens twice; tails, not at all. Don't, and it happens once. [b]LOADED DICE[/b]: once per turn, a flip or roll of yours that fails is tried again."],
	["GAME MODES", "[b]Casual[/b] and [b]Ranked[/b]: one on one. Ranked earns Rank Points (from level 5).\n\n[b]Free-for-all[/b]: four players, everyone for themselves, in turn order round the table. When you attack or an effect hits \"an opponent\", you choose which one. The last one standing wins; the rest are placed in the order they went out.\n\n[b]Turf Defense[/b]: you and a partner against a clan boss. You each have your own deck, board and Morale, and your partner's cards can't be targeted by yours. The boss has far more Morale, draws and gets Authority extra each turn, and changes [b]phase[/b] as its Morale drops (the marks on its bar). If one of you goes down, the other fights on: beat the boss and you both win. The first win on Street pays the boss's prize card."],
]


static func open(parent: Node) -> Control:
	var h: Control = load("res://scripts/ui/how_to_play.gd").new()
	parent.add_child(h)
	return h


var _text: RichTextLabel
var _cards: HBoxContainer   # the section's example cards, under its text
var _tabs := {}


func _ready() -> void:
	theme = UI.theme()
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.72)
	veil.size = size
	add_child(veil)
	var p := UI.panel(UI.GOLD, Color(0.05, 0.05, 0.12, 0.98))
	p.position = Vector2(260, 110)
	p.custom_minimum_size = Vector2(1400, 860)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	var h := UI.label("HOW TO PLAY", 48, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	row.add_child(tabs)
	var names: Array = SECTIONS.map(func(s): return s[0]) + ["KEYWORDS"]
	for n in names:
		var b := UI.button(n, _show.bind(n), Vector2(300, 50))
		b.toggle_mode = true
		tabs.add_child(b)
		_tabs[n] = b
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1030, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(1000, 0)
	_text.add_theme_font_size_override("normal_font_size", 24)
	_text.add_theme_font_size_override("bold_font_size", 24)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	scroll.add_child(body)
	body.add_child(_text)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 28)
	body.add_child(_cards)
	var close := UI.button("CLOSE", queue_free, Vector2(240, 56), UI.GOLD)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	_show(names[0])


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


func _show(tab: String) -> void:
	Sfx.play("click")
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == tab)
	var body := ""
	if tab == "KEYWORDS":
		var lines: Array = []
		for kw in Keywords.LIST:
			var d: String = Keywords.LIST[kw][1]
			var full: String = Keywords.full_name(kw)
			lines.append("[color=#%s][b]%s[/b][/color]%s" % [Keywords.LIST[kw][0].to_html(false), full, d.substr(full.length()) if d.begins_with(full) else ": " + d])   # ("POISON X: ...")
		lines.append("[b]ZZZ[/b]: just promoted or Awakened: it can't attack until your next turn.")
		lines.append("[b]DOWNED[/b]: in DEF, its effects stop; it stands back up after a round unless it is attacked again (KO).")
		body = "\n\n".join(lines)
	else:
		for s in SECTIONS:
			if s[0] == tab:
				body = _colour_keywords(s[1])
	_text.text = body
	_show_cards(tab)


## Real cards for a section: [card, caption, degrees turned, dimmed]. Your clan's first.
func _show_cards(tab: String) -> void:
	for c in _cards.get_children():
		c.queue_free()
	var mine := str(Game.player.get("chosen_clan", ""))
	var pool: Array = []
	for id in CardDB.all():
		var c: Dictionary = CardDB.all()[id]
		if not c.get("token", false) and str(c.get("clan", "")) != "":
			pool.append(c)
	pool.sort_custom(func(a, b):
		var ma := 0 if str(a.get("clan", "")) == mine else 1
		var mb := 0 if str(b.get("clan", "")) == mine else 1
		return ma < mb if ma != mb else str(a.id) < str(b.id))
	var find := func(ok: Callable) -> Dictionary:
		for c in pool:
			if ok.call(c):
				return c
		return {}
	var unit := func(c): return c.get("cardType") == "gang_member" and int(c.get("level", 1)) == 1
	var picks: Array = []
	match tab:
		"THE GOAL", "LEADERS":
			for c in pool:
				if c.get("cardType") == "leader" and picks.size() < 2:
					picks.append([c, "LEADER  ·  %s" % str(c.get("clanName", "")).to_upper(), 0.0, false])
		"A TURN":
			for want in [1, 4, 7]:
				var c: Dictionary = find.call(func(x): return unit.call(x) and int(x.get("authority", 0)) == want)
				if not c.is_empty():
					picks.append([c, "AUTHORITY %d" % want, 0.0, false])
		"CHARACTERS":
			for role in ["striver", "brawler", "heavy"]:
				var c: Dictionary = find.call(func(x): return unit.call(x) and str(x.get("subtype", "")) == role)
				if not c.is_empty():
					picks.append([c, role.to_upper(), 0.0, false])
		"BRAWLS":
			var a: Dictionary = find.call(func(x): return unit.call(x) and int(x.get("attack", 0)) >= 2000)
			var d: Dictionary = find.call(func(x): return unit.call(x) and int(x.get("defense", 0)) >= 2000 and x != a)
			if not a.is_empty():
				picks.append([a, "IN ATK  ·  ATK %d" % int(a.attack), 0.0, false])
			if not d.is_empty():
				picks.append([d, "IN DEF  ·  DEF %d" % int(d.defense), 90.0, false])
		"DOWNED & KO":
			var c: Dictionary = find.call(func(x): return unit.call(x))
			if not c.is_empty():
				picks.append([c, "DOWNED: SIDEWAYS, EFFECTS OFF", 90.0, true])
		"HUSTLES & AMBUSHES":
			for kind in [["hustle", "", "HUSTLE"], ["ambush", "", "AMBUSH"], ["", "continuous", "CONTINUOUS"]]:
				var c: Dictionary = find.call(func(x): return (kind[0] == "" or x.get("cardType") == kind[0]) and (kind[1] == "" or str(x.get("subtype", "")) == kind[1]) \
					and (kind[1] != "" or str(x.get("subtype", "")) == ""))
				if not c.is_empty():
					picks.append([c, kind[2], 0.0, false])
		"ABILITIES":
			for c in pool:
				if picks.size() < 2 and (c.get("effects", []) as Array).any(func(e): return str(e.get("when", "")) == "activate"):
					picks.append([c, "ACTIVATE", 0.0, false])
	for p in picks:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(212, 212) if p[2] != 0.0 else Vector2(150, 212)
		var tile := CardTile.make(p[0], Vector2(150, 212))
		tile.position = (holder.custom_minimum_size - tile.size) / 2
		holder.add_child(tile)
		tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
		tile.ready.connect(func():
			tile.pivot_offset = tile.size / 2
			tile.rotation_degrees = p[2]
			if p[3]:
				tile.modulate = Color(0.6, 0.6, 0.7))
		box.add_child(holder)
		var cap := UI.label(p[1], 16, UI.GOLD, true)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(holder.custom_minimum_size.x, 0)
		box.add_child(cap)
		_cards.add_child(box)
	CardTile.cascade(_cards.get_children(), 0.05)


## Keywords coloured like on the cards; the section's own [b] tags are kept (markup() escapes
## brackets, so it only gets the text between them).
static func _colour_keywords(text: String) -> String:
	var out := ""
	var at := 0
	for m in RegEx.create_from_string("\\[/?b\\]").search_all(text):
		out += Keywords.markup(text.substr(at, m.get_start() - at)) + m.get_string()
		at = m.get_end()
	return out + Keywords.markup(text.substr(at))
