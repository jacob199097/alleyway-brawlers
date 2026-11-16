extends RefCounted
## Keyword glossary. Effect keywords are coloured in card text (same colours as the Card Forge)
## and explain themselves when hovered: markup() wraps each one in a [url] tag for RichTextLabel.

const LIST := {
	"POISON": [Color("6ee26a"), "POISON X: at the start of its owner's next 3 turns, it loses X ATK. The loss lasts until it leaves the field."],
	"BURN": [Color("ff6a4a"), "BURN X: at the start of its owner's next 3 turns, its owner loses X Morale."],
	"STOKE": [Color("ff8a3a"), "STOKE X (Arsonists): BURN X. On a character that's already BURNING, its burn grows by X instead, and lasts another 3 turns."],
	"BLEED": [Color("ff4a6e"), "BLEED X: after every brawl it is in, it loses X ATK and X DEF until it leaves the field."],
	"SHOCK": [Color("4fc3ff"), "SHOCK X: if X is at least its DEF, it goes Down. Otherwise it loses X DEF this turn."],
	"FREEZE": [Color("a6ecff"), "FREEZE: it switches to DEF and can't attack or change position until the end of its owner's next turn."],
	"STASIS": [Color("9a7bff"), "STASIS (Nebula): frozen in time until the end of its owner's next turn. It can't attack, be attacked or be targeted, and its effects don't work. It doesn't block direct attacks."],
	"STUN": [Color("ffa040"), "STUN: it can't attack during its owner's next turn."],
	"BLIND": [Color("9fb0d8"), "BLIND: until the end of its owner's next turn, each time it attacks a coin is flipped. Heads, it attacks as usual. Tails, the attack misses: nothing happens, and that attack is used up."],
	"SHIELD": [Color("ffd75a"), "SHIELD: the next time it would be defeated (Downed or KO'd), it isn't."],
	"SILENCE": [Color("b8b4cc"), "SILENCE: its effects and abilities don't work for a while (it can still PROMOTE)."],
	"CONTINUOUS": [Color("ffc46b"), "CONTINUOUS: once played (an Ambush once sprung) it stays face-up in the back row, and its effects keep working until it is destroyed."],
	"EQUIP": [Color("ffc46b"), "EQUIP: attaches to a character and gives it its effects. It goes to the Gutter when that character leaves the field."],
	"PIERCE": [Color("ff74d4"), "PIERCE: if it beats a DEF or Downed character, the opponent also loses Morale equal to the difference."],
	"DRAIN": [Color("e07aff"), "DRAIN X: your opponent loses X Morale and you gain X Morale."],
	"HEAL": [Color("6ff0c0"), "HEAL X: you gain X Morale (up to the starting 6000)."],
	"SUPPRESS": [Color("b5e655"), "SUPPRESS X (Militia): pinned down: it loses X ATK and can't attack until the end of its owner's next turn."],
	"BOUNTY": [Color("f2c14e"), "BOUNTY X: when it is KO'd, whoever put the bounty on it draws X cards."],
	"LIFESTEAL": [Color("ff5d8f"), "LIFESTEAL: the Morale it takes from your opponent in a brawl, you gain."],
	"CLEANSE": [Color("bff6ff"), "CLEANSE: its statuses are gone: STASIS, FREEZE, STUN, BLIND, SUPPRESS, SILENCE, POISON, BURN, BLEED and BOUNTY."],
	"JAM": [Color("c6ff7a"), "JAM: your opponent can't spring Ambushes until the end of their next turn."],
	"REWIND": [Color("d6c2ff"), "REWIND: its ATK and DEF changes are undone, back to the printed numbers."],
	"BARRICADE": [Color("bfe3ff"), "BARRICADE X: the next X Morale damage you would take before your next turn is prevented."],
	"TAX": [Color("ffb36b"), "TAX X: your opponent gets X less Authority on their next turn."],
	"BRITTLE": [Color("e8dcc0"), "BRITTLE: when it would go Down (losing a brawl, or an effect), it's KO'd instead."],
	"REMAINS": [Color("b9a98a"), "REMAINS: when this token is KO'd or sacrificed, it goes to the Gutter instead of vanishing."],
	"MARKED": [Color("ff4d6d"), "MARKED: you can see your opponent's hand and face-down cards. Only you can: they stay hidden from everyone else."],
	"LOADED": [Color("f2c14e"), "LOADED DICE: once per turn, when one of your coin flips or die rolls fails, you may flip or roll again. You're asked each time, so you can save it for a flip that matters more."],
	"PLUNDER": [Color("e8b04a"), "PLUNDER (Pirates): take a card from your opponent for yourself: from their hand (at random, unless it says you choose), the top of their deck or their Gutter into your hand, or one of their characters onto your side of the field for good. A plundered card is shown to both players."],
	"PLUNDERS": [Color("e8b04a"), "PLUNDER (Pirates): take a card from your opponent for yourself: from their hand (at random, unless it says you choose), the top of their deck or their Gutter into your hand, or one of their characters onto your side of the field for good. A plundered card is shown to both players."],
	"INFILTRATE": [Color("9fe870"), "INFILTRATE: it can attack your opponent directly, even while they have standing characters (and past a Guard)."],
	"CHARM": [Color("ff6fb5"), "CHARM: you take control of an enemy character until the end of the turn. It can attack for you, then goes back to its owner."],
	"UNDEAD": [Color("c9e8b0"), "UNDEAD: the first time it's KO'd, it rises from the Gutter at the end of the turn, in DEF position with half its ATK and DEF."],
	"EXILE": [Color("d0a6ff"), "EXILE: removed from the game for good. It doesn't go to the Gutter, no KO effects happen, and nothing can bring it back."],
	"EXILES": [Color("d0a6ff"), "EXILE: removed from the game for good. It doesn't go to the Gutter, no KO effects happen, and nothing can bring it back."],
	"COLLATERAL": [Color("ff9a5c"), "COLLATERAL: when it KOs (or Downs) a character in a brawl, the effect hits the characters in the lanes either side of that one. After \"If you do\", it hits the characters either side of the one the effect before it hit."],
	"DOUBLE": [Color("ff8f6b"), "DOUBLE OR NOTHING: you may bet on a coin flip. Heads, the effect happens twice; tails, not at all. Don't bet, and it happens once."],
	"BRACE": [Color("9ec1e0"), "BRACE X: the first time each turn it's attacked, the attacker loses X ATK before the brawl (for the rest of the turn)."],
	"RECKLESS": [Color("ff6347"), "RECKLESS X: when it attacks, it gets +X ATK for that brawl. After the brawl, it goes Down."],
	"RALLY": [Color("ffb84d"), "RALLY X: your other characters get +X ATK this turn."],
	"TAUNT": [Color("ff7a7a"), "TAUNT: while it's standing, your opponent's attacks have to go at it (or another TAUNT character): not at your other characters, and not at you directly, not even with INFILTRATE."],
	"HEIST": [Color("f0c060"), "HEIST X (Pirates): when it makes your opponent lose Morale in a brawl (a direct attack, or beating a character), you draw X cards."],
	"ECHO": [Color("8fd3ff"), "ECHO: the effect happens again at the start of your next turn (a character's only while it's still on the field)."],
	"SHROUD": [Color("a29ec4"), "SHROUD: until it attacks, it can't be attacked and your opponent's effects can't choose it. It doesn't block direct attacks. Once it attacks, the SHROUD is gone."],
	"CORRODE": [Color("c8bb52"), "CORRODE X: at the start of its owner's next 3 turns, it loses X DEF. The loss lasts until it leaves the field."],
	"DEBT": [Color("e89a5c"), "DEBT X: the next card your opponent plays costs X more Authority (one they play before the end of their next turn)."],
	"COMBO": [Color("ffd43b"), "COMBO: it happens only if the card you played just before this one, this turn, was of the same clan (a character from your hand or a Hustle; Neutral cards break a chain). COMBO ×3: the two before it were."],
	"NEGATE": [Color("c3a6ff"), "NEGATE: stop an effect from happening. Once per turn, when an enemy card's effect is about to happen (a character's, unless the card says Hustles or any card), you may NEGATE it: it doesn't happen, nor anything that follows from it. You're asked each time, so you can save it for one that matters more. An Ambush that negates an attack stops the attack."],
	"CONFUSE": [Color("ff9fd6"), "CONFUSE: until the end of its owner's next turn, each time it attacks a coin is flipped. Heads, it attacks as chosen. Tails, it attacks a random other target instead: another it could have attacked, or one of its own side's characters (its player loses the Morale as usual)."],
}
## Keywords of more than one word: the words after the first, highlighted as part of the same keyword.
## PHRASE_ONLY ones are keywords only as the whole phrase ("Double its ATK" isn't DOUBLE OR NOTHING).
const PHRASES := {"LOADED": ["DICE"], "DOUBLE": ["OR", "NOTHING"]}
const PHRASE_ONLY := ["DOUBLE"]
## Statuses that aren't keywords, explained the same way when hovered or zoomed
const STATUS_HELP := {
	"DOWNED": [Color("ff5a5a"), "DOWNED: it lost a brawl (or was knocked down). It drops to DEF position and its effects stop working. Attacked again while Downed, it is KO'd. It stands back up, in DEF, at the start of its owner's turn after a full round."],
	"RESTING": [Color("ffb35a"), "CAN'T ATTACK YET: it was deployed, promoted or Awakened this turn, so it can't attack until its owner's next turn."],
	"GUARDED": [Color("a0d8ff"), "CAN'T BE ATTACKED: its owner has another character that can be, so attacks have to go there. It doesn't stop effects, and it's off while the card is Downed, SILENCED or face-down."],
}
const ALIASES := {"FROZEN": "FREEZE", "POISONOUS": "POISON", "BURNT": "BURN", "RALLIES": "RALLY", "RALLIED": "RALLY", "ECHOES": "ECHO",
	"CONFUSION": "CONFUSE", "NEGATES": "NEGATE", "NEGATED": "NEGATE"}
## Settings → Accessibility → Colour-Blind Colours: keywords coloured by what they do, in colours
## people with colour blindness can tell apart (Okabe-Ito, lightened for the dark screens). A keyword
## in none of these keeps its own colour.
const CB_GROUPS := [
	[Color("ffa630"), ["POISON", "BURN", "STOKE", "BLEED", "SHOCK", "PIERCE", "DRAIN", "LIFESTEAL", "BOUNTY", "BRITTLE", "TAX", "COLLATERAL", "CORRODE", "DEBT"]],   # damage and weakening
	[Color("eb9cd0"), ["STUN", "BLIND", "CONFUSE", "FREEZE", "STASIS", "SUPPRESS", "SILENCE", "JAM", "CHARM", "EXILE", "EXILES", "MARKED", "TAUNT", "NEGATE"]],   # holding back
	[Color("6cc4ff"), ["SHIELD", "HEAL", "CLEANSE", "BARRICADE", "UNDEAD", "REWIND", "REMAINS", "BRACE", "SHROUD"]],   # protection and recovery
	[Color("f0e442"), ["CONTINUOUS", "EQUIP", "LOADED", "DOUBLE", "PLUNDER", "PLUNDERS", "INFILTRATE", "RECKLESS", "RALLY", "HEIST", "ECHO", "COMBO"]],   # card rules
]
const CB_STATUS := {"DOWNED": Color("ffa630"), "RESTING": Color("f0e442"), "GUARDED": Color("6cc4ff")}


## A keyword's (or status's) colour: its own, or its group's with Colour-Blind Colours on.
static func color(kw: String) -> Color:
	if cb():
		if CB_STATUS.has(kw):
			return CB_STATUS[kw]
		for g in CB_GROUPS:
			if kw in g[1]:
				return g[0]
	if STATUS_HELP.has(kw):
		return STATUS_HELP[kw][0]
	return LIST[kw][0] if LIST.has(kw) else Color("e6e6f0")


static func cb() -> bool:
	return bool(Game.settings.get("cb_colors", false))
const ENDINGS := [["ED", ""], ["NED", ""], ["ING", ""], ["S", ""], ["D", ""], ["ED", "E"], ["ING", "E"]]


## The keyword a word belongs to ("STUNNED" -> "STUN"), or "".
static func find(word: String) -> String:
	var k := _find(word)
	return "" if k in PHRASE_ONLY else k


static func _find(word: String) -> String:
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


## The words of a text ([A-Za-z']+ matches) and the keyword each belongs to ("" for none); a
## keyword starts with a capital, and every word of a multi-word one is tagged with it.
static func _tag(text: String) -> Array:
	var ms: Array = RegEx.create_from_string("[A-Za-z']+").search_all(text)
	var tags: Array = []
	tags.resize(ms.size())
	tags.fill("")
	var i := 0
	while i < ms.size():
		var word: String = ms[i].get_string()
		var up := word.to_upper()
		if word[0] == up[0] and PHRASES.has(up):
			var rest: Array = PHRASES[up]
			var whole := true
			for k in rest.size():
				var j := i + 1 + k
				if j >= ms.size() or ms[j].get_string().to_upper() != rest[k] \
						or text.substr(ms[j - 1].get_end(), ms[j].get_start() - ms[j - 1].get_end()).strip_edges() != "":
					whole = false
					break
			if whole:
				for k in rest.size() + 1:
					tags[i + k] = up
				i += rest.size() + 1
				continue
		if word[0] == up[0]:
			tags[i] = find(word)
		i += 1
	return [ms, tags]


## The keywords in a text, each once, in order.
static func found(text: String) -> Array:
	var out: Array = []
	for kw in _tag(text)[1]:
		if kw != "" and not out.has(kw):
			out.append(kw)
	return out


## Card text as BBCode with every keyword coloured, bold and hoverable. Clan names in capitals
## (NEBULA) are bold in their clan's colour, as in the Card Forge.
static func markup(text: String) -> String:
	var clans := {}   # CLAN NAME -> its colour
	for c in CardDB.clans():
		clans[str(c.name).to_upper()] = c.color
	var tagged := _tag(text)
	var out := ""
	var at := 0
	for i in tagged[0].size():
		var m: RegExMatch = tagged[0][i]
		var word := m.get_string()
		var kw: String = tagged[1][i]
		out += _escape(text.substr(at, m.get_start() - at))
		if kw != "":
			out += "[url=%s][b][color=#%s]%s[/color][/b][/url]" % [kw, color(kw).to_html(false), word]
		elif word == word.to_upper() and clans.has(word):
			out += "[b][color=#%s]%s[/color][/b]" % [Color(clans[word]).to_html(false), word]
		else:
			out += _escape(word)
		at = m.get_end()
	return out + _escape(text.substr(at))


## Tooltip text for a keyword.
static func describe(kw: String) -> String:
	if STATUS_HELP.has(kw):
		return "[b][color=#%s]%s[/color][/b]\n%s" % [color(kw).to_html(false), "CAN'T ATTACK YET" if kw == "RESTING" else kw, STATUS_HELP[kw][1]]
	if not LIST.has(kw):
		return ""
	return "[b][color=#%s]%s[/color][/b]\n%s" % [color(kw).to_html(false), full_name(kw), LIST[kw][1]]


## A keyword's whole name ("LOADED" -> "LOADED DICE").
static func full_name(kw: String) -> String:
	return kw + (" " + " ".join(PHRASES[kw]) if PHRASES.has(kw) else "")


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
