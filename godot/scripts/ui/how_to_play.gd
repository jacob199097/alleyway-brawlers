extends Control
## How to Play: the rules in short sections, open from the duel menu and from Settings (Gameplay).
## The keyword section is built from the keyword glossary (scripts/keywords.gd), so it stays current.
##   load("res://scripts/ui/how_to_play.gd").open(parent)   (no class_name: patches can't add one)

const Keywords := preload("res://scripts/keywords.gd")

## [tab label, text] (BBCode; keywords are coloured by Keywords.markup)
const SECTIONS := [
	["THE GOAL", "Bring your opponent's [b]Morale[/b] from 6000 to 0. A player who has to draw from an empty deck loses too.\n\nEach player has a 40-card deck (up to 3 copies of a card), a [b]leader[/b], and a [b]Hideout[/b] holding the higher levels of their Strivers. You start with 5 cards and may redraw your opening hand once."],
	["A TURN", "[b]DEPLOYMENT[/b]: play cards by paying their Authority (the number in the corner). You get 1 Authority to start and 1 more every turn, up to 15. Going second, you get 1 extra on your first turn.\n\n[b]BRAWL[/b]: attack with your characters in ATK position. Nobody attacks on turn 1.\n\n[b]REGROUP[/b]: deploy again with what Authority is left, then end your turn. You can hold up to 9 cards: discard down to 9 at the end of your turn."],
	["CHARACTERS", "Characters go in your front row, in [b]ATK[/b] (upright) or [b]DEF[/b] (sideways). You choose when you deploy, and once per turn you can switch a character's position.\n\n[b]Strivers[/b] have levels and PROMOTE into the next one from your Hideout (it can't attack the turn it promotes: the ZZZ tag).\n[b]Brawlers[/b] are standalone.\n[b]Heavies[/b] are played onto your own characters: they sacrifice as many as the card says (SACRIFICE 1-3) and take one of their lanes.\n\nA full front row? Drop a character on one of yours (orange lanes) to deploy over it: the old one goes to the Gutter."],
	["BRAWLS", "Attacking a character in [b]ATK[/b]: the higher ATK wins. The loser goes Down and its owner loses Morale equal to the difference. A tie Downs both.\n\nAttacking a character in [b]DEF[/b] (or Downed): beat its DEF to Down it. No Morale is lost (unless the attacker has PIERCE), and a failed attack costs nothing.\n\nWhen the enemy has no standing character, you attack them [b]directly[/b]: they lose Morale equal to the attacker's ATK."],
	["DOWNED & KO", "A character that loses a brawl is [b]Downed[/b]: it drops to DEF and its effects stop working. It stands back up at the start of its owner's turn after a full round.\n\nAttacked again while Downed, it is [b]KO'd[/b] and goes to the Gutter.\n\nClick your Gutter, your opponent's Gutter or your Hideout to look through them."],
	["LEADERS", "Your leader starts [b]Dormant[/b]: its Dormant effects help you while it waits. The enemy can attack a Dormant leader to wear down its [b]Influence[/b]: at 0 it is defeated.\n\nWhen its [b]AWAKEN[/b] condition is met (on the card), it may take the field like a character, with its full strength. Usually it can't attack the turn it Awakens."],
	["HUSTLES & AMBUSHES", "A [b]Hustle[/b] does its effects when you play it, then goes to the Gutter.\n\nAn [b]Ambush[/b] is set face-down in your back row. When an enemy attacks one of your characters, you may spring it. If the attacker ends up Downed, removed or in STASIS, the attack stops.\n\nSome are CONTINUOUS (they stay face-up and keep working) or EQUIP (they attach to a character)."],
	["ABILITIES", "Card text tells you when an effect happens: when deployed, when it attacks, when an ally is KO'd...\n\nA [b]teal glow[/b] means a character has an [b]ACTIVATE[/b] ability ready: click it to use it, once per turn, paying any cost shown (Authority, Morale, a discard, a sacrifice, or not attacking this turn).\n\nWhen an effect lets you choose, the cards you can pick glow: click one, or SKIP.\n\n[b]If you do[/b]: that part only happens if the part before it worked."],
]


static func open(parent: Node) -> Control:
	var h: Control = load("res://scripts/ui/how_to_play.gd").new()
	parent.add_child(h)
	return h


var _text: RichTextLabel
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
		var b := UI.button(n, _show.bind(n), Vector2(300, 54))
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
	scroll.add_child(_text)
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
			lines.append("[color=#%s][b]%s[/b][/color]%s" % [Keywords.LIST[kw][0].to_html(false), kw, d.substr(kw.length()) if d.begins_with(kw) else ": " + d])   # ("POISON X: ...")
		lines.append("[b]ZZZ[/b]: just promoted or Awakened: it can't attack until your next turn.")
		lines.append("[b]DOWNED[/b]: in DEF, its effects stop; it stands back up after a round unless it is attacked again (KO).")
		body = "\n\n".join(lines)
	else:
		for s in SECTIONS:
			if s[0] == tab:
				body = _colour_keywords(s[1])
	_text.text = body


## Keywords coloured like on the cards; the section's own [b] tags are kept (markup() escapes
## brackets, so it only gets the text between them).
static func _colour_keywords(text: String) -> String:
	var out := ""
	var at := 0
	for m in RegEx.create_from_string("\\[/?b\\]").search_all(text):
		out += Keywords.markup(text.substr(at, m.get_start() - at)) + m.get_string()
		at = m.get_end()
	return out + Keywords.markup(text.substr(at))
