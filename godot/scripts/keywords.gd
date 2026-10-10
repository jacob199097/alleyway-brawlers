extends RefCounted
## Keyword glossary. Effect keywords are coloured in card text (same colours as the Card Forge)
## and explain themselves when hovered: markup() wraps each one in a [url] tag for RichTextLabel.

const LIST := {
	"POISON": [Color("6ee26a"), "POISON X: at the start of its owner's next 3 turns, it loses X ATK. The loss lasts until it leaves the field."],
	"BURN": [Color("ff6a4a"), "BURN X: at the start of its owner's next 3 turns, its owner loses X Morale."],
	"BLEED": [Color("ff4a6e"), "BLEED X: after every brawl it is in, it loses X ATK and X DEF until it leaves the field."],
	"SHOCK": [Color("4fc3ff"), "SHOCK X: if X is at least its DEF, it goes Down. Otherwise it loses X DEF this turn."],
	"FREEZE": [Color("a6ecff"), "FREEZE: it switches to DEF and can't attack or change position until the end of its owner's next turn."],
	"STASIS": [Color("9a7bff"), "STASIS (Nebula): frozen in time until the end of its owner's next turn. It can't attack, be attacked or be targeted, and its effects don't work. It doesn't block direct attacks."],
	"STUN": [Color("ffa040"), "STUN: it can't attack during its owner's next turn."],
	"SHIELD": [Color("ffd75a"), "SHIELD: the next time it would be defeated (Downed or KO'd), it isn't."],
	"PIERCE": [Color("ff74d4"), "PIERCE: if it beats a DEF or Downed character, the opponent also loses Morale equal to the difference."],
	"DRAIN": [Color("e07aff"), "DRAIN X: your opponent loses X Morale and you gain X Morale."],
	"HEAL": [Color("6ff0c0"), "HEAL X: you gain X Morale (up to the starting 6000)."],
}
const ALIASES := {"FROZEN": "FREEZE", "POISONOUS": "POISON", "BURNT": "BURN"}
const ENDINGS := [["ED", ""], ["NED", ""], ["ING", ""], ["S", ""], ["D", ""], ["ED", "E"], ["ING", "E"]]


## The keyword a word belongs to ("STUNNED" -> "STUN"), or "".
static func find(word: String) -> String:
	var w := word.to_upper().trim_suffix("'S")
	if LIST.has(w):
		return w
	if ALIASES.has(w):
		return ALIASES[w]
	for e in ENDINGS:
		if w.ends_with(e[0]):
			var b: String = w.substr(0, w.length() - e[0].length()) + e[1]
			if LIST.has(b):
				return b
	return ""


## Card text as BBCode with every keyword coloured, bold and hoverable.
static func markup(text: String) -> String:
	var re := RegEx.create_from_string("[A-Za-z']+")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		var word := m.get_string()
		var kw := find(word) if word[0] == word[0].to_upper() else ""
		out += _escape(text.substr(at, m.get_start() - at))
		if kw != "":
			out += "[url=%s][b][color=#%s]%s[/color][/b][/url]" % [kw, LIST[kw][0].to_html(false), word]
		else:
			out += _escape(word)
		at = m.get_end()
	return out + _escape(text.substr(at))


## Tooltip text for a keyword.
static func describe(kw: String) -> String:
	if not LIST.has(kw):
		return ""
	return "[b][color=#%s]%s[/color][/b]\n%s" % [LIST[kw][0].to_html(false), kw, LIST[kw][1]]


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
