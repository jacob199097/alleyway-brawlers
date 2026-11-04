extends Control
## How to Play: the rules in short sections, open from the duel menu and from Settings (Gameplay).
## KEYWORDS and CARD TERMS are a page per keyword or mechanic, each with real cards that use it. The
## keywords come from the keyword glossary (scripts/keywords.gd), so new ones show up by themselves.
##   load("res://scripts/ui/how_to_play.gd").open(parent)   (no class_name: patches can't add one)

const Keywords := preload("res://scripts/keywords.gd")

## [tab label, text] (BBCode; keywords are coloured by Keywords.markup)
const SECTIONS := [
	["THE GOAL", "Bring your opponent's [b]Morale[/b] from 6000 to 0. A player who has to draw from an empty deck loses too.\n\nEach player has a deck of 40 to 60 cards (up to 3 copies of a card) from their [b]leader[/b]'s clan plus any [b]Neutral[/b] cards, the leader itself, and a [b]Hideout[/b] holding the higher levels of their Strivers. You start with 5 cards and may redraw your opening hand once."],
	["A TURN", "[b]DEPLOYMENT[/b]: play cards by paying their Authority (the number in the corner). You get 1 Authority to start and 1 more every turn, up to 15. Going second, you get 1 extra on your first turn.\n\n[b]BRAWL[/b]: attack with your characters in ATK position. Nobody attacks on turn 1.\n\n[b]REGROUP[/b]: deploy again with what Authority is left, then end your turn. You can hold up to 9 cards: discard down to 9 at the end of your turn."],
	["CHARACTERS", "Characters go in your front row, in [b]ATK[/b] (upright) or [b]DEF[/b] (sideways). You choose when you deploy, and once per turn you can switch a character's position.\n\n[b]Strivers[/b] have levels and PROMOTE into the next one from your Hideout (it can't attack the turn it promotes: the ZZZ tag). The [b]stars[/b] on a Striver show its level: one gold star of three is level 1.\n[b]Brawlers[/b] are standalone.\n[b]Heavies[/b] are played onto your own characters: they sacrifice as many as the card says (SACRIFICE 1-3) and take one of their lanes.\n\nA full front row? Drop a character on one of yours (orange lanes) to deploy over it: the old one goes to the Gutter."],
	["BRAWLS", "Attacking a character in [b]ATK[/b]: the higher ATK wins. The loser goes Down and its owner loses Morale equal to the difference. A tie Downs both.\n\nAttacking a character in [b]DEF[/b] (or Downed): beat its DEF to Down it. Its owner loses no Morale (unless the attacker has PIERCE). Fall short and the attack is blocked, and [b]you[/b] lose the difference in Morale.\n\nWhen the enemy has no standing character, you attack them [b]directly[/b]: they lose Morale equal to the attacker's ATK."],
	["DOWNED & KO", "A character that loses a brawl is [b]Downed[/b]: it drops to DEF and its effects stop working. It stands back up at the start of its owner's turn after a full round.\n\nAttacked again while Downed, it is [b]KO'd[/b] and goes to the Gutter.\n\nClick your Gutter, your opponent's Gutter or your Hideout to look through them."],
	["LEADERS", "Your leader starts [b]Dormant[/b]: its Dormant effects help you while it waits. The enemy can attack a Dormant leader to wear down its [b]Influence[/b]: at 0 it is defeated.\n\nWhen its [b]AWAKEN[/b] condition is met (on the card), it may take the field like a character, with its full strength. Usually it can't attack the turn it Awakens."],
	["HUSTLES & AMBUSHES", "A [b]Hustle[/b] does its effects when you play it, then goes to the Gutter. You can also set one face-down in your back row for free, and activate it whenever you choose on your turn (any phase, even the turn you set it), paying its Authority then.\n\nAn [b]Ambush[/b] is set face-down in your back row. When an enemy attacks one of your characters, you may spring it: its effects happen first, then the attack goes on with whatever they changed (an attacker that lost ATK may now lose the brawl). The attack only stops if the Ambush negates it, or the attacker ends up Downed, removed or in STASIS.

A [b]Continuous[/b] Ambush can also be flipped face-up without an attack, once it has been set since an earlier turn: on your turn (click it), or when you're offered the chance at the start of your opponent's turn and after they deploy.\n\nSome are CONTINUOUS (they stay face-up and keep working) or EQUIP (they attach to a character)."],
	["ABILITIES", "Card text tells you when an effect happens: when deployed, when it attacks, when an ally is KO'd...\n\nA [b]teal glow[/b] means a character has an [b]ACTIVATE[/b] ability ready: click it to use it, once per turn, paying any cost shown (Authority, Morale, a discard, a sacrifice, or not attacking this turn).\n\nWhen an effect lets you choose, the cards you can pick glow: click one, or SKIP.\n\n[b]If you do[/b]: that part only happens if the part before it worked.\n\n[b]Luck[/b]: some cards flip a coin or roll a die, shown on the board. \"If tails\" parts follow the same flip. [b]DOUBLE OR NOTHING[/b]: you choose whether to bet. Bet, and a coin decides: heads, it happens twice; tails, not at all. Don't, and it happens once. [b]LOADED DICE[/b]: once per turn, a flip or roll of yours that fails is tried again."],
	["GAME MODES", "[b]Casual[/b] and [b]Ranked[/b]: one on one, against another player. Ranked (from level 5) is a best of 3: winning the series earns Rank Points, losing it costs some, and once it's decided a rematch is friendly.\n\n[b]Free-for-all[/b]: four players, everyone for themselves, in turn order round the table. When you attack or an effect hits \"an opponent\", you choose which one. The last one standing wins; the rest are placed in the order they went out.\n\n[b]Turf Defense[/b]: you and a partner against a clan boss. You each have your own deck, board and Morale, and your partner's cards can't be targeted by yours. The boss has far more Morale, draws and gets Authority extra each turn, and changes [b]phase[/b] as its Morale drops (the marks on its bar). If one of you goes down, the other fights on: beat the boss and you both win. The first win on Street pays the boss's prize card."],
]

## The mechanics card text talks about: {name, color, text, and the cards to show: "do" (effects that
## do one of these) or "on" (leader, heavy, striver, neutral, activate, luck, or "text" with "re")}
const TERMS := [
	{"name": "PROMOTE", "color": "6fd3ff", "do": ["promote", "promote_ally"], "text": "A [b]Striver[/b] PROMOTES into its next level: that card comes out of your Hideout and takes its place, in the same position. It can't attack the turn it promotes (the ZZZ tag).\n\nEach Striver says what makes it promote. The stars on a Striver show its level: one gold star of three is level 1."},
	{"name": "HIDEOUT", "color": "6fd3ff", "on": "striver", "text": "Where your Strivers' higher levels wait. They don't go in your deck: you put them in the Hideout in the Deck Builder.\n\nA Striver can only PROMOTE when its next level is in your Hideout. Click it during a duel to look through it."},
	{"name": "DORMANT & AWAKEN", "color": "f4c430", "on": "leader", "text": "Your [b]leader[/b] starts beside the field, [b]Dormant[/b]: its Dormant effects help you all game while it waits. The enemy can attack it to wear down its [b]Influence[/b]: at 0 it is defeated.\n\nWhen its [b]AWAKEN[/b] condition is met, you may bring it onto the field as a character, at full strength. Usually it can't attack that turn."},
	{"name": "ACTIVATE", "color": "4fe3d0", "on": "activate", "text": "An ability you use yourself. When a character [b]glows teal[/b], click it to use its ACTIVATE ability: once per turn, paying any cost shown first (Authority, Morale, a discard, a sacrifice, or not attacking this turn)."},
	{"name": "SACRIFICE", "color": "ff5a5a", "on": "heavy", "text": "A [b]Heavy[/b] is played by sacrificing as many of your characters as it says (SACRIFICE 1-3): they go to the Gutter, and the Heavy takes one of their lanes.\n\nSome ACTIVATE costs and effects sacrifice characters too. A sacrificed token vanishes."},
	{"name": "TOKENS", "color": "c9b8ff", "do": ["token"], "text": "Characters made by an effect, not from your deck.\n\nWhen a token leaves the field it vanishes: it never goes to the Gutter, a hand or a deck, unless it has REMAINS."},
	{"name": "THE GUTTER", "color": "9aa4b1", "do": ["revive", "recover", "mill_self"], "text": "Your discard pile. KO'd characters and used Hustles and Ambushes go there.\n\nSome effects bring cards back from it: [b]revive[/b] puts a character back on the field, [b]recover[/b] puts a card back in your hand. Click either player's Gutter to look through it."},
	{"name": "DRAW & DISCARD", "color": "e8e8e8", "do": ["draw", "loot", "discard"], "text": "[b]Draw[/b]: take cards from the top of your deck into your hand. [b]Discard[/b]: put cards from your hand into the Gutter.\n\nA player who has to draw from an empty deck loses."},
	{"name": "SEARCH & CALL", "color": "8fe388", "do": ["search", "call"], "text": "[b]Search[/b]: look through your deck for a card that fits, add it to your hand, then the deck is shuffled. Your opponent isn't shown what you took, unless the card says so.\n\n[b]Call[/b]: put a character from your deck straight onto the field, in ATK."},
	{"name": "DOWN, STAND UP & KO", "color": "ff7a5a", "do": ["down", "stand", "ko"], "text": "Effects can [b]Down[/b] a standing character without a brawl (it drops to DEF and its effects stop), [b]stand[/b] a Downed one back up, or [b]KO[/b] a character outright: straight to the Gutter."},
	{"name": "BACK TO THE HAND", "color": "7ab8ff", "do": ["bounce", "topdeck"], "text": "The character leaves the field and goes back to its owner's hand (or on top of their deck), as good as new: its changes and statuses are gone.\n\nA token sent back vanishes."},
	{"name": "DESTROYING HUSTLES & AMBUSHES", "color": "ffb35a", "do": ["wreck", "break_ambush"], "text": "Destroys a card in your opponent's back row (set face-down, face-up, or either: the card says which). It goes to the Gutter without doing anything."},
	{"name": "MUST BE ATTACKED FIRST", "color": "d9c08a", "do": ["guard"], "text": "While this character is standing, your opponent's characters have to attack it before any of your other characters."},
	{"name": "CAN'T BE ATTACKED", "color": "a0d8ff", "do": ["elusive"], "text": "It can't be attacked while you have another character that can be."},
	{"name": "CAN'T BE TARGETED", "color": "c6b4ff", "do": ["untargetable"], "text": "Your opponent's effects can't choose it. It can still be attacked."},
	{"name": "IMMUNE", "color": "bff6ff", "do": ["immune"], "text": "The statuses the card lists don't affect it."},
	{"name": "ATK & DEF POSITION", "color": "ffd27a", "do": ["force_def", "force_atk"], "text": "[b]ATK[/b] (upright) attacks. [b]DEF[/b] (sideways) only defends. You choose when you deploy, and you can switch each character once per turn.\n\nSome effects switch an enemy's position for you."},
	{"name": "ATTACKING AGAIN", "color": "ff9f5a", "do": ["attack_again", "ready", "double_attack"], "text": "Each character attacks once a turn. Some effects let one attack again: at most once more each turn."},
	{"name": "ATK & DEF CHANGES", "color": "ffe08a", "do": ["buff", "set_stats", "swap"], "text": "Effects add to or take from ATK and DEF for a while: until the end of the turn, until the end of your next turn, or permanently (as long as it stays on the field).\n\n[b]Swap[/b]: its ATK and DEF trade places."},
	{"name": "MORALE", "color": "ff6f8f", "do": ["damage", "heal", "drain"], "text": "Both players start with 6000 Morale. Lost brawls, direct attacks and effects take it away: at 0 you lose.\n\nHEAL and DRAIN give some back, up to 6000."},
	{"name": "AUTHORITY", "color": "f2c14e", "do": ["cost_down", "cost_up", "authority"], "text": "Authority pays for your cards: 1 at the start, 1 more every turn, up to 15 (going second, 1 extra on your first turn).\n\nSome effects make cards cost less or more, or give you extra Authority."},
	{"name": "COIN FLIPS & DICE", "color": "f2c14e", "on": "luck", "text": "Some effects flip a coin or roll a die, shown on the board: they only happen if it comes up right. \"If tails\" parts follow the same flip.\n\nSee DOUBLE OR NOTHING and LOADED DICE under KEYWORDS."},
	{"name": "NEUTRAL CARDS", "color": "9aa4b1", "on": "neutral", "text": "Cards of no clan. They go in any deck, next to your leader's clan's cards, and drop from every clan's booster packs."},
	{"name": "ONCE PER TURN & IF YOU DO", "color": "e8e8e8", "on": "text", "re": "(?i)once per turn|if you do", "text": "[b]Once per turn[/b]: the ability only works the first time each turn.\n\n[b]If you do[/b]: the part after it only happens if the part before it worked."},
]


static func open(parent: Node) -> Control:
	var h: Control = load("res://scripts/ui/how_to_play.gd").new()
	parent.add_child(h)
	return h


var _text: RichTextLabel
var _cards: HBoxContainer   # the section's example cards, under its text
var _tabs := {}
var _grid: GridContainer    # KEYWORDS / CARD TERMS: a button per page
var _back: Button           # from a page back to its grid
var _tab := ""


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
	var names: Array = SECTIONS.map(func(s): return s[0]) + ["KEYWORDS", "CARD TERMS"]
	for n in names:
		var b := UI.button(n, _show.bind(n), Vector2(300, 50))
		b.toggle_mode = true
		tabs.add_child(b)
		_tabs[n] = b
	# Every card type explained on real cards, the keywords and how to get stronger (scripts/ui/card_school.gd)
	var school := UI.button("STREET SCHOOL  ▶", func(): load("res://scripts/ui/card_school.gd").open(self), Vector2(300, 50), UI.GOLD)
	tabs.add_child(school)
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
	_back = UI.button("◀  ALL", func(): _show(_tab), Vector2(300, 46))
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(_back)
	body.add_child(_text)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	body.add_child(_grid)
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
	_tab = tab
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == tab)
	_back.visible = false
	for b in _grid.get_children():
		b.queue_free()
	_grid.visible = tab in ["KEYWORDS", "CARD TERMS"]
	if _grid.visible:
		_text.text = "Keywords are the coloured words in card text (hover one on a card to read it). Pick one to see what it does, and cards that have it." \
			if tab == "KEYWORDS" else "What card text means. Pick a term to see how it works, and cards that use it."
		for p in _pages(tab):
			var b := UI.button(p.name, _open_page.bind(p), Vector2(330, 52))
			b.add_theme_color_override("font_color", p.color)
			b.add_theme_color_override("font_hover_color", p.color.lightened(0.3))
			b.add_theme_font_size_override("font_size", 18)
			_grid.add_child(b)
		_lay_cards([])
		return
	for s in SECTIONS:
		if s[0] == tab:
			_text.text = _colour_keywords(s[1])
	_show_cards(tab)


## The pages of KEYWORDS or CARD TERMS: [{name, color, text, fits}]. fits(card): 2 = it does this,
## 1 = it only mentions it, 0 = no.
func _pages(tab: String) -> Array:
	var out: Array = []
	if tab == "KEYWORDS":
		var seen := {}
		for kw in Keywords.LIST:
			var d: String = Keywords.LIST[kw][1]
			if seen.has(d):   # (EXILES is EXILE)
				continue
			seen[d] = true
			var full: String = Keywords.full_name(kw)
			out.append({"name": full, "color": Keywords.LIST[kw][0], "text": "[b]%s[/b]%s" % [full, d.substr(full.length()) if d.begins_with(full) else ": " + d],
				"fits": _keyword_fits.bind(kw)})
		out.append({"name": "DOWNED", "color": Keywords.STATUS_HELP.DOWNED[0], "text": Keywords.STATUS_HELP.DOWNED[1],
			"fits": func(c): return 2 if (c.get("effects", []) as Array).any(func(e): return str(e.get("do", "")) == "down") else 0})
		out.append({"name": "ZZZ", "color": Keywords.STATUS_HELP.RESTING[0], "text": "[b]ZZZ[/b]: " + str(Keywords.STATUS_HELP.RESTING[1]).trim_prefix("CAN'T ATTACK YET: "),
			"fits": func(c): return 2 if str(c.get("subtype", "")) == "striver" and int(c.get("level", 1)) == 2 else 0})
		return out
	for t in TERMS:
		out.append({"name": t.name, "color": Color(t.color), "text": t.text, "fits": func(c): return 2 if _term_fits(c, t) else 0})
	return out


## A keyword: its own effect (do "stasis", "give_undead") or type (Continuous, Equip), or failing that
## its name in the card's text, not counting being immune to it
func _keyword_fits(c: Dictionary, kw: String) -> int:
	var low := kw.to_lower()
	if str(c.get("subtype", "")) == low or (c.get("effects", []) as Array).any(func(e): return str(e.get("do", "")) in [low, "give_" + low]):
		return 2
	var text := str(c.get("effectText", ""))
	return 1 if Keywords.found(text).has(kw) and not text.to_lower().contains("immune to") else 0


func _term_fits(c: Dictionary, t: Dictionary) -> bool:
	var fx: Array = c.get("effects", [])
	match str(t.get("on", "")):
		"leader": return c.get("cardType") == "leader"
		"heavy": return c.get("cardType") == "gang_member" and str(c.get("subtype", "")) == "heavy"
		"striver": return str(c.get("subtype", "")) == "striver" and int(c.get("level", 1)) == 2
		"neutral": return str(c.get("clan", "")) == CardDB.NEUTRAL
		"activate": return fx.any(func(e): return str(e.get("when", "")) == "activate")
		"luck": return fx.any(func(e): return e.has("luck"))
		"text": return RegEx.create_from_string(str(t.re)).search(str(c.get("effectText", ""))) != null
	return fx.any(func(e): return str(e.get("do", "")) in t.do)


## A keyword's or term's page: what it does, and up to three real cards that have it
func _open_page(p: Dictionary) -> void:
	Sfx.play("click")
	for b in _grid.get_children():
		b.queue_free()
	_grid.visible = false
	_back.text = "◀  ALL " + _tab
	_back.visible = true
	_text.text = "[font_size=34][color=#%s]%s[/color][/font_size]\n\n%s" % [p.color.to_html(false), p.name, _colour_keywords(p.text)]
	# The cards that do it first, then ones that mention it; tokens only when no other card has it
	var ranked: Array = []
	for c in _pool(true):
		var score: float = p.fits.call(c)
		if score > 0:
			ranked.append([score - (1.5 if c.get("token", false) else 0.0), ranked.size(), c])
	ranked.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var picks: Array = ranked.slice(0, 3).map(func(r): return [r[2], str(r[2].get("name", "")).to_upper(), 0.0, false])
	if picks.is_empty():
		_text.text += "\n\n[color=#8a8494]No card has it yet.[/color]"
	_lay_cards(picks, Vector2(200, 283))


## Every card that can be shown, your clan's first (tokens too, when asked).
func _pool(tokens := false) -> Array:
	var mine := str(Game.player.get("chosen_clan", ""))
	var pool: Array = []
	for id in CardDB.all():
		var c: Dictionary = CardDB.all()[id]
		if (tokens or not c.get("token", false)) and str(c.get("clan", "")) != "":
			pool.append(c)
	pool.sort_custom(func(a, b):
		var ma := 0 if str(a.get("clan", "")) == mine else 1
		var mb := 0 if str(b.get("clan", "")) == mine else 1
		return ma < mb if ma != mb else str(a.id) < str(b.id))
	return pool


## Real cards for a section: [card, caption, degrees turned, dimmed]. Your clan's first.
func _show_cards(tab: String) -> void:
	var pool := _pool()
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
	_lay_cards(picks)


## Cards under the text: [card, caption, degrees turned, dimmed]
func _lay_cards(picks: Array, card := Vector2(150, 212)) -> void:
	for c in _cards.get_children():
		c.queue_free()
	for p in picks:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(card.y, card.y) if p[2] != 0.0 else card
		var tile := CardTile.make(p[0], card)
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
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size = Vector2(holder.custom_minimum_size.x, 0)
		cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
