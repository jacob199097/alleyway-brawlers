class_name DuelState
extends RefCounted
## Rules for one duel. Pure data: no nodes, no animation.
##
## Players act through do_action() with plain dictionaries, e.g.
##   {kind = "summon", uid = 12, slot = 2, position = "atk"}
## Every change is recorded as an event; the duel screen takes them with take_events() and
## animates them one by one. Because actions and events are plain data, these same rules can
## later run on the server and stream events to both players.
##
## Effects that say "you may" or "choose" pause the game with a prompt (`pending`) that the
## deciding player answers with {kind = "choose", option = id} (or "discard" for discards).
## Options are listed best-first for the deciding side, so the CPU can simply take the first.
##
## Ported from client/scenes/DuelScene.js, client/cards/BrawlPhase.js and EffectBus.js.
##
## Free-for-all (FFA): pass 3-4 decks (seats in turn order, e.g. p1..p4) instead of player and
## opponent. Every opponent is an enemy: attacks name the opponent they go at ({kind = "attack", from,
## target, foe}), effects on "an enemy" can pick any opponent's card, "enemies" hit them all, and an
## effect on "your opponent" (discard, mill, Morale damage, face-down cards) hits the one being fought
## (in a brawl) or the one its player chooses. A player at 0 Morale (or decked out) is out (their place
## in `places`); their cards leave at the end of the action and the last one standing wins. Durations
## that run "through the next turn" last a full round. With two players everything is as before.

const START_MORALE := 6000
const MAX_AUTHORITY := 15
const HAND_LIMIT := 9
const OPENING_HAND := 5
const SECOND_PLAYER_AUTHORITY := 1 # going second: extra Authority on your first turn only
const LEADER_DEFEAT_PENALTY := 0   # Morale lost when a Dormant leader is defeated (none: it was never on the field)
const FRONT := [0, 1, 2, 3, 4]   # character slots
const DORMANT_GIFTS := ["pierce", "immune", "untargetable", "undead", "lifesteal"]   # passives a Dormant leader can give your characters
const BACK := [5, 6, 7, 8, 9]    # ambush slots
const DIRECT := -1               # attack target: the opponent's morale
const NO_SLOT := -10             # effects of a card that isn't on the field (a Hustle, a sprung Ambush)
## Ambushes with hand-written rules; any other Ambush with effects is a Card Forge Ambush (_spring_fx)
const HAND_AMBUSHES := ["no_witnesses_ambush", "lion_ambush", "kings_test"]
## What an "immune" passive keeps off a card
const IMMUNE_TO := ["poison", "burn", "bleed", "shock", "freeze", "stasis", "stun", "suppress", "silence", "bounty", "charm"]
const LEADER := -2               # attack target: the opponent's dormant leader

var turn := 1
var active := "player"
var phase := "upkeep"
var winner := ""
var end_reason := ""     # how the game ended: "morale" or "deck_out"
## The prompt the game is waiting on, or {}:
##   {kind = "choose", side, key, prompt, options = [{id, label, side?, slot?}], card, cb}
##   {kind = "discard", side, count, prompt, cb}
var pending := {}
var sides := {}
var rng := RandomNumberGenerator.new()

var _events: Array = []
var _uid := 0
var _asks: Array = []        # prompts queued behind `pending`
var _in_answer := false      # prompts raised while answering one go first
var _new_asks: Array = []
var _did := 0                # effects that did something (see then in _do_fx)
# Luck (coin flips, die rolls) has its own generator, mulberry32 as in DuelState.js, so both
# engines roll the same: from the match's seed, fixed for seed -1 (tests compare engines)
const LUCK_SALT := 0x5BD1E995
const LUCK_TEST_SEED := 0x2545F491
const M32 := 0xFFFFFFFF
var _luck_t := 0
var _luck_last := {}         # the last flip or roll: {won, value} (if_luck follows it)
var _luck_wait := {}         # a DOUBLE OR NOTHING not yet decided: {uid, ask} (its "If tails" waits for it)
var _roll := 1               # the last die's value ("for each pip")
var _attack_ctx := {}        # the attack being resolved
var rules := {}              # a challenge's twist (see _init)
var _fixed_order := false    # seed -1: never shuffle (tests compare engines)
var seats: Array = ["player", "opponent"]   # turn order (FFA: p1, p2, ... by name)
var ffa := false             # 3-4 players
var teams := {}              # Turf Defense: seat -> team (teammates aren't foes; see DuelState.js)
var _healing := false        # "when you gain Morale" effects are running (they can't set themselves off)
var _take_self := false      # a card just milled or discarded may take itself from the Gutter (_to_gutter_fx)
var first_seat := "player"
var places := {}             # FFA: side -> finishing place (1 = the winner)


## decks/hideouts: {"player": [card ids], "opponent": [...]}; leaders: {"player": id, ...}
## rules: a challenge's twist (shared/challenges.js): start_authority, start_morale, opening_hand,
## pierce (every attack pierces). Same as DuelState.js.
func _init(decks: Dictionary, hideouts: Dictionary, leaders: Dictionary, first := "player", seed_value := 0, rules_ := {}) -> void:
	rules = rules_.duplicate()
	if seed_value > 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_luck_t = ((seed_value ^ LUCK_SALT) & M32) if seed_value > 0 else (LUCK_TEST_SEED if seed_value == -1 else rng.randi())
	active = first
	first_seat = first
	_fixed_order = seed_value == -1
	# Turn order: player, opponent; FFA seats by name (p1, p2, ...), whatever order they come in
	var keys: Array = decks.keys()
	var order: Array = []
	if rules.get("order") is Array:
		for k in rules.order:
			if keys.has(str(k)):
				order.append(str(k))
	if order.size() == keys.size():
		seats = order
	elif keys.size() == 2 and keys.has("player"):
		seats = ["player", "opponent"]
	else:
		seats = keys.duplicate()
		seats.sort()
	ffa = seats.size() > 2
	teams = rules.teams.duplicate() if rules.get("teams") is Dictionary else {}
	for side in seats:
		var deck: Array = []
		for id in decks[side]:
			deck.append(make_card(id))
		if seed_value != -1:   # -1 keeps the given order (tests compare engines)
			_shuffle(deck)
		var hideout: Array = []
		for id in hideouts.get(side, []):
			hideout.append(make_card(id))
		var field: Array = []
		field.resize(10)
		var leader_id: String = leaders.get(side, "")
		var leader = make_card(leader_id) if leader_id != "" else null
		if leader != null:
			leader.influence = int(leader.influence) if leader.get("influence") != null else leader.base_defense   # (Forge leaders set it; else DEF)
			leader.influence_max = leader.influence
		var morale: int = int(rules.get("morale", {}).get(side, 0)) if rules.get("morale") is Dictionary else 0
		if morale <= 0:
			morale = int(rules.get("start_morale", 0)) if int(rules.get("start_morale", 0)) > 0 else START_MORALE
		sides[side] = {
			"morale": morale, "max_morale": morale,
			"authority": maxi(1, int(rules.get("start_authority", 1))), "authority_max": maxi(1, int(rules.get("start_authority", 1))),
			"deck": deck, "hand": [], "field": field, "gutter": [], "hideout": hideout,
			"leader": leader, "leader_state": "dormant" if leader != null else "none",
			"brutus_bonus": 0, "promoted": {}, "mentor_used": false, "turns": 0,
		}


## `spec` is a card id, or {id, ...} with server-side stats (name, authority, attack, defense,
## rarity) that override the rules data.
func make_card(spec) -> Dictionary:
	var id: String = str(spec.id) if spec is Dictionary else str(spec)
	var c: Dictionary = CardDB.get_card(id).duplicate(true)
	if spec is Dictionary:
		for key in spec:
			if key != "id":
				c[key] = spec[key]
	_uid += 1
	c.uid = _uid
	c.id = id
	for key in ["authority", "level", "rarity"]:
		c[key] = int(c.get(key, 0))
	c.base_attack = int(c.get("attack", 0))
	c.base_defense = int(c.get("defense", 0))
	c.attack = c.base_attack
	c.defense = c.base_defense
	c.position = "atk"
	c.face_down = false
	c.downed = false
	c.has_attacked = false
	c.deployed_turn = 0
	if c.get("effectKey") == null:
		c.effectKey = ""   # Card Forge cards may have no hand-written effect
	c.mods = []   # temporary buffs/debuffs: {atk, def, until_turn}
	return c


## Online play: mirror the board the server sent (from this player's side; the opponent's hand,
## deck and face-down cards are stubs), so the screen can ask the usual questions —
## can_summon, attack_targets, pending — without running the rules locally.
func load_view(v: Dictionary) -> void:
	turn = int(v.get("turn", 1))
	active = str(v.get("active", "player"))
	phase = str(v.get("phase", "upkeep"))
	winner = str(v.get("winner", ""))
	pending = v.get("pending", {}) if v.get("pending") is Dictionary else {}
	sides = v.get("sides", {})
	seats = v.get("seats", ["player", "opponent"]) if v.get("seats") is Array else ["player", "opponent"]
	ffa = seats.size() > 2
	teams = v.get("teams", {}) if v.get("teams") is Dictionary else {}
	_asks.clear()
	_new_asks.clear()


static func other(side: String) -> String:
	return "opponent" if side == "player" else "player"


func take_events() -> Array:
	var out := _events
	_events = []
	return out


# ── Queries ──────────────────────────────────────────────────────────────────

func card_at(side: String, slot: int):
	return sides[side].field[slot]


## Front-row characters: [{slot, card}]
func characters(side: String) -> Array:
	var out: Array = []
	for slot in FRONT:
		var c = sides[side].field[slot]
		if c != null:
			out.append({"slot": slot, "card": c})
	return out


static func is_lion(c) -> bool:
	return c != null and c.get("clanTag") == "lion"


func lion_count(side: String) -> int:
	var n := 0
	for e in characters(side):
		if is_lion(e.card):
			n += 1
	return n


func leader_dormant(side: String) -> bool:
	return sides[side].leader_state == "dormant"


func can_act(side: String) -> bool:
	return winner == "" and pending.is_empty() and side == active and sides.has(side) and not _is_out(side)


# ── Seats (two players, or FFA) ──────────────────────────────────────────────

func _is_out(side: String) -> bool:
	return int(sides[side].get("out", 0)) > 0


## The opponents still in, in turn order after `side` (two players: just the other one).
func foes_of(side: String) -> Array:
	var i := seats.find(side)
	var out: Array = []
	for k in range(1, seats.size()):
		var s: String = seats[(i + k) % seats.size()]
		if not _is_out(s) and not _teammates(s, side):
			out.append(s)
	return out


## Teams: whether two seats play on the same side (never without teams).
func _teammates(a: String, b: String) -> bool:
	return not teams.is_empty() and a != b and teams.has(a) and teams.get(a) == teams.get(b)


func _alive() -> Array:
	return seats.filter(func(s): return not _is_out(s))


## The next seat still in after `side`.
func _next_seat(side: String) -> String:
	var i := seats.find(side)
	for k in range(1, seats.size() + 1):
		var s: String = seats[(i + k) % seats.size()]
		if not _is_out(s):
			return s
	return side


## Every seat, starting with this one.
func _order(start_side: String) -> Array:
	var i := seats.find(start_side)
	var out: Array = []
	for k in seats.size():
		out.append(seats[(i + k) % seats.size()])
	return out


## How many more turns until the next turn of everyone else has passed (two players: 1).
func _round_span() -> int:
	return maxi(1, _alive().size() - 1)


## The opponent an effect on "your opponent" hits: in a brawl, the other side of it; otherwise the
## only one, or the one its player chooses (lowest Morale first). ok: which can be hit at all.
func _with_foe(side: String, c: Dictionary, vs: Dictionary, ok: Callable, fn: Callable) -> void:
	var foes := foes_of(side).filter(ok)
	if foes.is_empty():
		return
	var fixed := ""
	if not vs.is_empty() and str(vs.get("side", "")) != "" and vs.side != side and vs.side in foes:
		fixed = vs.side
	elif not _attack_ctx.is_empty() and _attack_ctx.side == side and _attack_ctx.foe in foes:
		fixed = _attack_ctx.foe
	elif not _attack_ctx.is_empty() and _attack_ctx.foe == side and _attack_ctx.side in foes:
		fixed = _attack_ctx.side
	elif foes.size() == 1:
		fixed = foes[0]
	if fixed != "":
		fn.call(fixed)
		return
	var order := foes.duplicate()
	order.sort_custom(func(a, b): return sides[a].morale < sides[b].morale or (sides[a].morale == sides[b].morale and seats.find(a) < seats.find(b)))
	var options: Array = order.map(func(x): return {"id": x, "label": x, "side": x})
	_ask(side, "foe", "%s: choose an opponent" % c.name, c, options, func(x: String):
		if sides.has(x) and not _is_out(x):
			fn.call(x))


## Every opponent's characters, with their side.
func _enemy_chars(side: String) -> Array:
	var out: Array = []
	for f in foes_of(side):
		for x in characters(f):
			out.append({"side": f, "slot": x.slot, "card": x.card})
	return out


func can_deploy_now(side: String) -> bool:
	return can_act(side) and phase in ["deployment", "regroup"]


## Character classes: Strivers level up (only they can PROMOTE); Brawlers are standalone;
## Heavies are standalone too, and need one of your characters sacrificed to come into play
## (the Heavy takes its lane).
static func needs_tribute(c) -> bool:
	return c != null and c.get("subtype") == "heavy"


## How many characters a Heavy sacrifices (tributeCost, 1-3; 0: not a Heavy).
static func tributes_for(c) -> int:
	if not needs_tribute(c):
		return 0
	var n := int(c.get("tributeCost", 1))
	return clampi(n if n > 0 else 1, 1, 3)


## tribute: a slot (-1 none) or a list of slots.
static func tribute_list(tribute) -> Array:
	if tribute is Array:
		return tribute.map(func(t): return int(t))
	return [int(tribute)] if int(tribute) >= 0 else []


## One of your characters a deploy can send to the Gutter (a Heavy's sacrifice, or one deployed over).
func can_sacrifice(side: String, slot: int) -> bool:
	var t = card_at(side, slot) if slot in FRONT else null
	return t != null and t.get("cardType") != "leader" and not in_stasis(t)


## Summon `c` into `slot`. A Heavy names the characters it sacrifices (`tribute`: their slots;
## it takes one of their lanes). Anything else goes in an empty lane, or over one of your
## characters (`tribute`: that slot), which goes to the Gutter.
func can_summon(side: String, c: Dictionary, slot: int, tribute = -1) -> bool:
	if not can_deploy_now(side) or c.get("cardType") != "gang_member":
		return false
	if not slot in FRONT or sides[side].authority < cost_of(side, c):
		return false
	var list := tribute_list(tribute)
	var seen := {}
	for t in list:
		if seen.has(t) or not can_sacrifice(side, t):
			return false
		seen[t] = true
	if needs_tribute(c):
		return list.size() == tributes_for(c) and slot in list
	if list.is_empty():
		return sides[side].field[slot] == null
	return list.size() == 1 and list[0] == slot


## Whether `c` can be summoned anywhere right now (a Heavy needs characters to sacrifice).
func can_summon_somewhere(side: String, c: Dictionary) -> bool:
	var n := tributes_for(c)
	var fodder := FRONT.filter(func(t): return can_sacrifice(side, t))
	if n > 0:
		return fodder.size() >= n and can_summon(side, c, fodder[0], fodder.slice(0, n))
	for slot in FRONT:
		if can_summon(side, c, slot) or can_summon(side, c, slot, slot):
			return true
	return false


# ── Continuous / Equip (Card Forge subtype of a Hustle or Ambush) ────────────
# A Continuous card stays face-up in the back row once played (an Ambush once sprung): its
# "passive" effects keep working (buffs for your characters or the enemy's, PIERCE / immunity /
# "can't be targeted" for yours, cheaper cards) and its triggered ones fire like a character's.
# An Equip Hustle goes to the back row attached to a character (equip_to: ally | enemy): its
# "passive" effects are that character's; it goes to the Gutter when the character leaves.

static func is_lasting(c) -> bool:
	return c is Dictionary and str(c.get("cardType", "")) in ["hustle", "ambush"] \
		and str(c.get("subtype", "")) in ["continuous", "equip"]


## Face-up Continuous / Equip cards in a side's back row: [{slot, card}] (sub: only that kind).
func _lasting(side: String, sub := "") -> Array:
	var out: Array = []
	for b in BACK:
		var c = sides[side].field[b]
		if c != null and not c.get("face_down", false) and is_lasting(c) and (sub == "" or str(c.subtype) == sub):
			out.append({"slot": b, "card": c})
	return out


func _empty_back(side: String) -> int:
	for b in BACK:
		if sides[side].field[b] == null:
			return b
	return -1


## Continuous cards' triggered effects (turn_start, ally_deployed, ...); `def` itself is skipped.
func _run_lasting(side: String, when: String, def = null, vs := {}) -> void:
	for x in _lasting(side, "continuous"):
		if winner != "":
			return
		if sides[side].field[x.slot] == x.card and not is_same(x.card, def):
			_run_fx(side, x.slot, x.card, when, def, vs)


## The Equip cards on character c: [{side (their owner), slot, card}]
## An Equip card (a Hustle that attaches to a character).
## Whose card it is: a CHARMED character fights for whoever charmed it, but goes back to its owner
## (to their Gutter, hand or deck if it leaves the field).
func _owner_of(side: String, c) -> String:
	return str(c.charmed.owner) if c is Dictionary and c.get("charmed") is Dictionary else side


## A Continuous Ambush its owner may flip face-up (outside an attack): set on an earlier turn, not JAMMED.
func can_flip(side: String, slot: int) -> bool:
	if not (slot in BACK) or winner != "" or not sides.has(side) or sides[side].get("out", false):
		return false
	var a = card_at(side, slot)
	return a != null and a.get("face_down", false) and a.get("cardType") == "ambush" and is_lasting(a) \
		and a.get("set_turn") != null and int(a.set_turn) < turn and int(sides[side].get("jam_until", -1)) < turn


## Flip a Continuous Ambush face-up: its "when sprung" effects happen (with no attacker) and it stays.
func _flip_set(side: String, slot: int) -> void:
	var a: Dictionary = card_at(side, slot)
	_spring(side, slot)
	_effect(side, a, "%s is flipped face-up" % a.name, slot)
	for e in _fx(a, "defend"):
		if winner != "":
			return
		if _fx_cond(side, NO_SLOT, e, null):
			_do_fx(side, NO_SLOT, a, e, {})
	_recalc()


## On a player's turn, the others may flip their Continuous Ambushes (its start, and after they deploy).
func _offer_flips() -> void:
	for side in foes_of(active):
		var slots: Array = BACK.filter(func(b): return can_flip(side, b))
		if slots.is_empty():
			continue
		var options: Array = [{"id": "no", "label": "NOT NOW"}]
		for b in slots:
			options.append({"id": str(b), "label": "FLIP %s" % str(card_at(side, b).name).to_upper(), "side": side, "slot": b})
		_ask(side, "flip", "Flip a Continuous Ambush face-up?", card_at(side, slots[0]), options, func(choice: String) -> void:
			var b := int(choice)
			if choice != "no" and can_flip(side, b):
				_flip_set(side, b))


static func is_equip(c) -> bool:
	return c is Dictionary and str(c.get("cardType", "")) == "hustle" and str(c.get("subtype", "")) == "equip"


func _equips_on(c) -> Array:
	var out: Array = []
	if not c is Dictionary or not c.has("uid"):
		return out
	for side in sides:
		for x in _lasting(side, "equip"):
			if int(x.card.get("equipped_to", -1)) == int(c.uid):
				out.append({"side": side, "slot": x.slot, "card": x.card})
	return out


## The characters an Equip Hustle can go on (its owner's, or with equip_to "enemy" the foe's).
func _equip_targets(side: String, c: Dictionary) -> Array:
	var out: Array = []
	for on in (foes_of(side) if str(c.get("equip_to", "ally")) == "enemy" else [side]):
		for x in characters(on):
			if not in_stasis(x.card) and (on == side or _passive(on, x.slot, x.card, "untargetable").is_empty()):
				out.append({"side": on, "slot": x.slot, "card": x.card})
	return out


## An Equip whose character has left the field goes to the Gutter.
func _sweep_equips() -> void:
	for side in sides:
		for x in _lasting(side, "equip"):
			var to := int(x.card.get("equipped_to", -1))
			if to < 0:
				continue
			var on := false
			for s2 in sides:
				for y in characters(s2):
					if int(y.card.uid) == to:
						on = true
			if not on:
				sides[side].field[x.slot] = null
				x.card.erase("equipped_to")
				sides[side].gutter.append(x.card)
				_emit("ko", {"side": side, "slot": x.slot, "card": x.card.duplicate(true)})


## Ambushes and Hustles are set face-down in the back row. An Ambush is paid for when it's set;
## a Hustle when it's activated, any time on your turn (set_hustle_slot, can_hustle).
func can_set(side: String, c: Dictionary, slot: int) -> bool:
	if not can_deploy_now(side) or not c.get("cardType") in ["ambush", "hustle"]:
		return false
	if not slot in BACK or sides[side].field[slot] != null:
		return false
	return c.get("cardType") == "hustle" or sides[side].authority >= cost_of(side, c)


## The back-row slot of c if it's a Hustle set face-down there (-1: it isn't).
func set_hustle_slot(side: String, c) -> int:
	if not c is Dictionary or c.get("cardType") != "hustle" or not c.get("face_down", false):
		return -1
	for b in BACK:
		if is_same(sides[side].field[b], c):
			return b
	return -1


func hustle_ready(side: String, c: Dictionary) -> bool:
	match c.get("effectKey", ""):
		"lion_rescue":
			return not _downed_lions(side).is_empty()
		"blood_scent":
			return not _promotable_strivers(side).is_empty()
	return true


func can_hustle(side: String, c: Dictionary) -> bool:
	# One set in the back row: in any phase you act in (the turn it was set too)
	var set := set_hustle_slot(side, c)
	var now := (can_act(side) and phase in ["deployment", "brawl", "regroup"]) if set >= 0 else can_deploy_now(side)
	if not (now and c.get("cardType") == "hustle" and sides[side].authority >= cost_of(side, c) and hustle_ready(side, c)):
		return false
	if is_lasting(c):   # a Continuous / Equip card needs room in the back row (an Equip, a character)
		return (set >= 0 or _empty_back(side) >= 0) and (str(c.subtype) != "equip" or not _equip_targets(side, c).is_empty())
	return card_can(side, NO_SLOT, c, "*")


## Whether any of card c's effects for a trigger would do something now (a card with none
## always can). Hustles can't be played, nor Ambushes sprung, when nothing would happen.
func card_can(side: String, slot: int, c: Dictionary, when: String, vs := {}, def = null) -> bool:
	var list := _fx(c, when)
	if list.is_empty():
		return c.get("effects", []).is_empty()
	return list.any(func(e): return fx_can(side, slot, c, e, vs, def))


## Whether effect e of card c would do anything now: its condition holds and it has something
## to act on (a target, a card to find, an empty lane, ...).
func fx_can(side: String, slot: int, c: Dictionary, e: Dictionary, vs := {}, def = null) -> bool:
	if not _fx_cond(side, slot, e, def):
		return false
	if str(e.get("per", "")) != "" and _per_count(side, slot, e) <= 0:
		return false
	var s: Dictionary = sides[side]
	var foes: Array = foes_of(side).map(func(x): return sides[x])
	var mine := func(x): return not is_same(x, c) and _fx_kind_ok(x, e)
	match str(e.get("do", "")):
		"draw", "loot":
			return not s.deck.is_empty()
		"search":
			return s.deck.any(mine)
		"recover":   # (a token has no hand to go to)
			return s.gutter.any(func(x): return not x.get("token", false) and mine.call(x))
		"revive":
			if e.get("from", "") == "foe":
				return _room_for(side) and foes.any(func(x): return x.gutter.any(mine))
			return _room_for(side) and s.gutter.any(mine)
		"exile_gutter":
			return foes.any(func(x): return not x.gutter.is_empty())
		"call":
			return _room_for(side) and s.deck.any(mine)
		"token":
			return _room_for(side) and not CardDB.get_card(str(e.get("token", ""))).is_empty()
		"discard":
			return foes.any(func(x): return not x.hand.is_empty())
		"mill":
			return foes.any(func(x): return not x.deck.is_empty())
		"mill_self":
			return not s.deck.is_empty()
		"entomb":
			return s.deck.any(mine)
		"heal":
			return s.morale < int(s.get("max_morale", START_MORALE))
		"break_ambush":
			return foes.any(func(x): return BACK.any(func(b): return x.field[b] != null and x.field[b].get("face_down", false)))
		"shatter":
			return foes.any(func(x): return BACK.any(func(b): return x.field[b] != null and not x.field[b].get("face_down", false)))
		"wreck":
			return foes.any(func(x): return BACK.any(func(b): return x.field[b] != null))
		"influence":
			var l = s.leader
			return s.leader_state == "dormant" and l != null and int(l.influence) < int(l.get("influence_max", l.influence))
		"ramp":
			return s.authority_max < MAX_AUTHORITY
		"jam":
			return foes.any(func(x): return BACK.any(func(b): return x.field[b] != null and x.field[b].get("cardType") == "ambush"))
		"barricade":
			return true
		"tax":
			return not foes.is_empty()
		"reshuffle":
			return s.gutter.any(func(x): return not x.get("token", false))
		"tribute_damage":
			return int(c.get("tribute_atk", 0)) > 0
		"attack_again":
			return card_at(side, slot) == c and c.has_attacked and int(c.get("again_turn", 0)) != turn
	if not e.has("target"):
		return true
	if str(e.get("do", "")) == "charm" and _empty_lane(side) < 0:   # (no lane to take it to)
		return false
	var pool: String = {"down": "standing", "stand": "downed", "force_def": "attackers", "force_atk": "defenders",
		"ready": "spent", "cleanse": "statused", "rewind": "changed", "promote_ally": "promotable", "charm": "charmable", "give_undead": "unrisen", "absorb": "absorbable"}.get(str(e.get("do", "")), "any")
	var entries := _fx_targets(side, slot, c, e, vs, pool)
	if str(e.get("target", "")) == "enemy":   # (one enemy is chosen: not one that can't be targeted)
		entries = entries.filter(func(x): return _passive(x.side, x.slot, x.card, "untargetable").is_empty())
	return not entries.is_empty()


## What a card in hand costs to play: its Authority, less any "cost_down" passives on the field.
func cost_of(side: String, c: Dictionary) -> int:
	var off := 0
	var s: Dictionary = sides[side]
	var sources: Array = []
	for x in characters(side):
		if not x.card.face_down:
			sources.append([x.slot, x.card])
	if s.leader_state == "dormant" and s.leader != null:
		sources.append([-1, s.leader])
	for x in _lasting(side, "continuous"):
		sources.append([x.slot, x.card])
	for src in sources:
		for e in _fx(src[1], "dormant" if src[0] == -1 else "passive"):
			if str(e.get("do", "")) != "cost_down" or not _fx_cond(side, src[0], e, null):
				continue
			if str(e.get("clan", "")) != "" and c.get("clanTag") != str(e.get("clan", "")):
				continue
			off += maxi(1, int(e.get("amount", 1)))
	# An opponent's "cost_up" (TAX passives): your cards cost more
	var up := 0
	for foe in foes_of(side):
		var fs: Dictionary = sides[foe]
		var theirs: Array = []
		for x in characters(foe):
			if not x.card.face_down:
				theirs.append([x.slot, x.card])
		for x in _lasting(foe, "continuous"):
			theirs.append([x.slot, x.card])
		if fs.leader_state == "dormant" and fs.leader != null:
			theirs.append([-1, fs.leader])
		for src in theirs:
			for e in _fx(src[1], "dormant" if src[0] == -1 else "passive"):
				if str(e.get("do", "")) != "cost_up" or not _fx_cond(foe, src[0], e, null):
					continue
				if str(e.get("clan", "")) != "" and c.get("clanTag") != str(e.get("clan", "")):
					continue
				up += maxi(1, int(e.get("amount", 1)))
	return maxi(0, int(c.get("authority", 0)) - off + up)


## A Card Forge passive of this kind that's switched on for the card in this slot (or {}).
func _passive(side: String, slot: int, c, kind: String, ok := Callable()) -> Dictionary:
	if c == null or c.get("face_down", false):
		return {}
	for e in _fx(c, "passive"):
		if str(e.get("do", "")) == kind and (not ok.is_valid() or ok.call(e)) and _fx_cond(side, slot, e, null):
			return e
	# A Dormant leader can give your characters PIERCE, immunity or "can't be targeted"
	var s = sides.get(side)
	if kind in DORMANT_GIFTS and s != null and s.leader_state == "dormant" and s.leader != null and not is_same(s.leader, c):
		for e in _fx(s.leader, "dormant"):
			if str(e.get("do", "")) == kind and (not ok.is_valid() or ok.call(e)) \
					and (str(e.get("clan", "")) == "" or c.get("clanTag") == str(e.get("clan", ""))) and _fx_cond(side, -1, e, null):
				return e
	# Continuous cards give your characters the same gifts; an Equip gives its character any passive
	if s != null and kind in DORMANT_GIFTS:
		for x in _lasting(side, "continuous"):
			for e in _fx(x.card, "passive"):
				if str(e.get("do", "")) == kind and (not ok.is_valid() or ok.call(e)) \
						and (str(e.get("clan", "")) == "" or c.get("clanTag") == str(e.get("clan", ""))) and _fx_cond(side, x.slot, e, null):
					return e
	for q in _equips_on(c):
		for e in _fx(q.card, "passive"):
			if str(e.get("do", "")) == kind and (not ok.is_valid() or ok.call(e)) and _fx_cond(q.side, q.slot, e, null):
				return e
	return {}


## A Dormant leader's triggered effects ("While Dormant, at the start of your turn: ...").
func _leader_fx(side: String, when: String, def = null) -> void:
	var s: Dictionary = sides[side]
	if s.leader_state == "dormant" and s.leader != null and winner == "":
		_run_fx(side, -1, s.leader, when, def)


## "no_down": this card can't be Downed while its owner controls another character.
func _stays_up(side: String, slot: int, c) -> bool:
	return not _passive(side, slot, c, "no_down").is_empty() and characters(side).size() > 1


## Keyword statuses (Card Forge effects). Freeze and Stasis last through the owner's next turn.
const FOREVER := 1000000        # until_turn for mods that last until the card leaves the field
const STATUS_TICKS := 3         # Poison / Burn tick at the start of the owner's next 3 turns
const STATUS_KEYS := ["poison", "burn", "bleed", "freeze_until", "stasis_until", "silence_until", "suppress_until", "bounty"]


func in_stasis(c) -> bool:
	return c != null and int(c.get("stasis_until", 0)) >= turn


func frozen(c) -> bool:
	return c != null and int(c.get("freeze_until", 0)) >= turn


## The statuses on a character, for the field display (sent with the "stats" event).
func statuses(c: Dictionary) -> Array:
	var out: Array = []
	for k in ["poison", "burn", "bleed"]:
		if c.has(k):
			out.append(k)
	if frozen(c):
		out.append("freeze")
	if in_stasis(c):
		out.append("stasis")
	if int(c.get("stun_until", 0)) >= turn:
		out.append("stun")
	if int(c.get("suppress_until", 0)) >= turn:
		out.append("suppress")
	if c.get("shield", false):
		out.append("shield")
	if int(c.get("silence_until", 0)) >= turn:
		out.append("silence")
	if c.has("bounty"):
		out.append("bounty")
	if c.get("charmed") is Dictionary:
		out.append("charm")
	if c.get("undead_given", false):
		out.append("undead")
	if not _equips_on(c).is_empty():
		out.append("equipped")
	# Just promoted or Awakened: it can't attack this turn
	if int(c.get("rest_turn", -1)) == turn and c.get("has_attacked", false) and not c.get("downed", false):
		out.append("resting")
	return out


## No attacks yet: until everyone has had a turn (turn 1; a free-for-all's whole first round).
func no_attacks_yet() -> bool:
	return turn <= (seats.size() if ffa else 1)


func can_attack_with(side: String, slot: int) -> bool:
	if not can_act(side) or phase != "brawl" or no_attacks_yet() or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	return c != null and c.position == "atk" and not c.downed and not c.has_attacked and not c.face_down \
		and int(c.get("stun_until", 0)) < turn and int(c.get("suppress_until", 0)) < turn and not frozen(c) and not in_stasis(c)


## Attack targets: any enemy character; DIRECT when none of them is still standing (an empty
## front row, or only Downed characters); and the enemy LEADER whenever it is dormant.
## foe: which opponent (FFA; default: the first one)
func attack_targets(side: String, foe := "") -> Array:
	if foe == "":
		var all_foes := foes_of(side)
		foe = all_foes[0] if not all_foes.is_empty() else ""
	if foe == "" or foe == side or not sides.has(foe) or _is_out(foe):
		return []
	# A character in STASIS can't be attacked and doesn't block a direct attack
	var foes := characters(foe).filter(func(e): return not in_stasis(e.card))
	# Elusive characters can't be attacked while their owner has another character that can be
	var open := foes.filter(func(e): return _passive(foe, e.slot, e.card, "elusive").is_empty())
	var pool: Array = open if not open.is_empty() else foes
	# A standing Guard must be attacked first
	var guards := pool.filter(func(e): return not e.card.downed and not _passive(foe, e.slot, e.card, "guard").is_empty())
	if not guards.is_empty():
		return guards.map(func(e): return e.slot)
	var targets: Array = pool.map(func(e): return e.slot)
	if not foes.any(func(e): return not e.card.downed):
		targets.append(DIRECT)
	if leader_dormant(foe):
		targets.append(LEADER)
	return targets


## Switch ATK ↔ DEF: once per turn, not on the turn it arrived, not after attacking.
func can_change_position(side: String, slot: int) -> bool:
	if not can_deploy_now(side) or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	return c != null and not c.downed and not c.has_attacked and not frozen(c) and not in_stasis(c) \
		and c.deployed_turn != turn and c.get("position_turn", 0) != turn


## Maya Lv.1/2: promote while you control another LIONS card with equal or higher Authority.
func can_promote(side: String, slot: int) -> bool:
	if not can_deploy_now(side) or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	if c == null or c.get("ability") != "maya_promote" or c.face_down or c.downed or c.get("subtype") != "striver" or in_stasis(c):
		return false
	if sides[side].promoted.has(slot) or not _next_in_hideout(side, c):
		return false
	for e in characters(side):
		if e.slot != slot and is_lion(e.card) and e.card.authority >= c.authority:
			return true
	return false


## Maya Lv.3: once per turn, buff another LIONS character.
func can_use_ability(side: String, slot: int) -> bool:
	if not can_act(side) or not phase in ["deployment", "brawl", "regroup"] or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	if c == null or c.get("ability") != "maya_buff" or c.face_down or c.downed or in_stasis(c):
		return false
	if c.get("ability_turn", 0) == turn:
		return false
	return characters(side).any(func(e): return e.slot != slot and is_lion(e.card))


## Activated abilities (Card Forge "When: Activate"): the player uses them from the card during their
## own turn, once per turn each, paying the cost first. Returns which ones it can use now: 1 for its
## first "activate" effect, 2 for the second, ...
##   cost: "" | authority | morale | discard | sacrifice (another of your characters) | exhaust
##         (it can't attack this turn); cost_n: how much Authority, Morale or how many cards
func activations(side: String, slot: int) -> Array:
	var out: Array = []
	if not can_act(side) or not phase in ["deployment", "brawl", "regroup"] or not slot in FRONT:
		return out
	var c = card_at(side, slot)
	if c == null or c.face_down:
		return out
	if int(c.get("evolved_turn", -1)) == turn:   # a Striver that evolved this turn waits a turn
		return out
	var k := 0
	for e in _fx(c, "activate"):
		k += 1
		if int(c.get("fx_used", {}).get("activate%d" % k, -1)) != turn and fx_can(side, slot, c, e) \
				and _can_pay(side, slot, c, e):
			out.append(k)
	return out


func _can_pay(side: String, slot: int, c: Dictionary, e: Dictionary) -> bool:
	var s: Dictionary = sides[side]
	var n: int = maxi(1, int(e.get("cost_n", 1)))
	match str(e.get("cost", "")):
		"authority":
			return s.authority >= n
		"morale":
			return s.morale > n
		"discard":
			return s.hand.size() >= n
		"sacrifice":
			return characters(side).any(func(x): return x.slot != slot)
		"exhaust":
			return not c.has_attacked and not c.downed
		"exile_gutter":
			return s.gutter.size() >= n
	return true


func _activate(side: String, slot: int, k: int) -> bool:
	if not k in activations(side, slot):
		return false
	var c: Dictionary = card_at(side, slot)
	var e: Dictionary = _fx(c, "activate")[k - 1]
	var used: Dictionary = c.get("fx_used", {})
	used["activate%d" % k] = turn
	c.fx_used = used
	var go := func(): _do_fx(side, slot, c, e)
	var n: int = maxi(1, int(e.get("cost_n", 1)))
	match str(e.get("cost", "")):
		"authority":
			_spend(side, n)
			_effect(side, c, "%s: pays %d Authority to activate" % [c.name, n], slot)
			go.call()
		"morale":
			_effect(side, c, "%s: pays %d Morale to activate" % [c.name, n], slot)
			_damage(side, n, true)
			if winner == "":
				go.call()
		"discard":
			_effect(side, c, "%s: discard %d to activate" % [c.name, n], slot)
			_ask_discard(side, n, go, "%s: discard to activate" % c.name)
		"sacrifice":
			var allies := characters(side).filter(func(x): return x.slot != slot) \
				.map(func(x): return {"side": side, "slot": x.slot, "card": x.card})
			allies.sort_custom(func(a, b): return _attack_value(a.card) < _attack_value(b.card) \
				or (_attack_value(a.card) == _attack_value(b.card) and a.slot < b.slot))
			_ask_target(side, "sacrifice", "%s: choose a character to sacrifice" % c.name, c, allies, side, func(x: Dictionary):
				var name: String = x.card.name
				_ko(side, x.slot)
				_effect(side, c, "%s sacrifices %s" % [c.name, name], slot)
				if winner == "":
					go.call())
		"exile_gutter":   # the cards that have been in your Gutter longest
			_exile_gutter(side, sides[side].gutter.slice(0, n))
			_effect(side, c, "%s: EXILES %d card%s from the Gutter to activate" % [c.name, n, "" if n == 1 else "s"], slot)
			go.call()
		"exhaust":
			c.has_attacked = true
			_effect(side, c, "%s activates: it can't attack this turn" % c.name, slot)
			go.call()
		_:
			_effect(side, c, "%s activates its ability" % c.name, slot)
			go.call()
	return true


## Whether effect `e` of the card in `slot` has anyone to affect right now (abilities that only
## affect characters do nothing without one). The CPU checks this before activating.
func fx_has_targets(side: String, slot: int, e: Dictionary) -> bool:
	var c = card_at(side, slot)
	return c == null or fx_can(side, slot, c, e)


# ── Actions ──────────────────────────────────────────────────────────────────

func start() -> void:
	var order := _order(active)
	for i in (int(rules.get("opening_hand", 0)) if int(rules.get("opening_hand", 0)) > 0 else OPENING_HAND):
		for side in order:
			_draw(side, true)
	# Each player may redraw their opening hand once, in turn order; then turn 1 begins
	_mulligan_chain(order, 0)
	_flush_asks()


func _mulligan_chain(order: Array, k: int) -> void:
	if k < order.size():
		_ask_mulligan(order[k], func(): _mulligan_chain(order, k + 1))
	else:
		_begin_turn()


func do_action(side: String, a: Dictionary) -> bool:
	if winner != "":
		return false
	var ok := false
	# A new move (not an answer to a prompt): no brawl is going on any more
	if a.get("kind", "") != "choose" and a.get("kind", "") != "discard":
		_attack_ctx = {}
	match a.get("kind", ""):
		"summon":
			ok = _summon(side, int(a.uid), int(a.slot), str(a.get("position", "atk")), a.tributes if a.get("tributes") is Array else int(a.get("tribute", -1)))
		"set":
			ok = _set_ambush(side, int(a.uid), int(a.slot))
		"hustle":
			ok = _hustle(side, int(a.uid))
		"attack":
			ok = _attack(side, int(a.from), int(a.target), str(a.foe) if a.get("foe") != null else "")
		"position":
			ok = _change_position(side, int(a.slot))
		"promote":
			if can_promote(side, int(a.slot)):
				_promote(side, int(a.slot), "Maya")
				ok = true
		"ability":
			ok = _use_ability(side, int(a.slot))
		"flip":   # a Continuous Ambush, face-up on your own turn
			if can_act(side) and can_flip(side, int(a.slot)):
				_flip_set(side, int(a.slot))
				ok = true
		"activate":
			ok = _activate(side, int(a.slot), int(a.get("fx", 1)))
		"choose":
			ok = _answer(side, str(a.option))
		"discard":
			ok = _choose_discard(side, int(a.uid))
		"next":
			ok = _next_phase(side)
	if ok:
		_flush_asks()
		if ffa:
			_sweep_out()
		_recalc()
	return ok


## A player leaves (conceding, away too long, disconnected). FFA: they're out, in the last place
## still open, and the game goes on; two players: the other one wins. Same as concede in DuelState.js.
func concede(side: String, reason := "concede") -> bool:
	if winner != "" or not sides.has(side) or _is_out(side):
		return false
	_lose(side, reason)
	if ffa:
		_sweep_out()
	_recalc()
	return true


func _summon(side: String, uid: int, slot: int, position: String, tribute = -1) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_summon(side, sides[side].hand[i], slot, tribute):
		return false
	var c: Dictionary = sides[side].hand[i]
	_spend(side, cost_of(side, c))
	sides[side].hand.remove_at(i)
	var tribute_atk := 0
	for slot_ in tribute_list(tribute):   # sacrificed, or deployed over
		var t: Dictionary = card_at(side, slot_)
		sides[side].field[slot_] = null
		tribute_atk += int(t.attack)
		var own := _owner_of(side, t)
		t.erase("charmed")
		t.downed = false
		t.mods = []
		_clear_status(t)
		if not t.get("token", false) or remains(t):   # (tokens vanish, unless REMAINS)
			sides[own].gutter.append(t)
		var ev := {"side": side, "slot": slot_, "card": t.duplicate(true), "for": c.duplicate(true)}
		if not needs_tribute(c):
			ev.replace = true
		_emit("tribute", ev)
	c.position = "def" if position == "def" else "atk"
	c.face_down = false   # characters are always face-up, in ATK or DEF (only Ambushes are set face-down)
	c.has_attacked = false
	c.deployed_turn = turn
	sides[side].field[slot] = c
	if needs_tribute(c):   # (tribute_damage: "the ATK it sacrificed")
		c.tribute_atk = tribute_atk
	_emit("summon", {"side": side, "slot": slot, "card": c.duplicate(true)})
	_on_deploy(side, slot, c)
	if winner == "":   # (the others may flip a Continuous Ambush now)
		_offer_flips()
	return true


func _set_ambush(side: String, uid: int, slot: int) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_set(side, sides[side].hand[i], slot):
		return false
	var c: Dictionary = sides[side].hand[i]
	if c.get("cardType") != "hustle":   # (a Hustle is paid for when it's activated)
		_spend(side, cost_of(side, c))
	sides[side].hand.remove_at(i)
	c.face_down = true
	c.set_turn = turn
	sides[side].field[slot] = c
	_emit("set", {"side": side, "slot": slot, "card": c.duplicate(true)})
	return true


func _change_position(side: String, slot: int) -> bool:
	if not can_change_position(side, slot):
		return false
	var c: Dictionary = card_at(side, slot)
	c.position = "atk" if c.position == "def" else "def"
	c.face_down = false   # a set card flips face-up when it changes position
	c.position_turn = turn
	_emit("position", {"side": side, "slot": slot, "card": c.duplicate(true)})
	return true


## A Hustle from the hand, or one set face-down in the back row (it's played from there)
func _hustle(side: String, uid: int) -> bool:
	var s: Dictionary = sides[side]
	var i := _hand_index(side, uid)
	var set := -1
	if i < 0:
		for b in BACK:
			if s.field[b] != null and int(s.field[b].uid) == uid and set_hustle_slot(side, s.field[b]) == b:
				set = b
				break
	var c = s.hand[i] if i >= 0 else s.field[set] if set >= 0 else null
	if c == null or not can_hustle(side, c):
		return false
	_spend(side, cost_of(side, c))
	if i >= 0:
		s.hand.remove_at(i)
	else:
		s.field[set] = null
	if is_lasting(c):
		# Continuous / Equip: into the back row (a set one stays in its slot), face-up; its "when played" effects happen
		var b := set if set >= 0 else _empty_back(side)
		c.face_down = false
		s.field[b] = c
		var ev := {"side": side, "slot": b, "card": c.duplicate(true)}
		if set >= 0:
			ev.set = true
		_emit("lasting", ev)
		if str(c.subtype) == "equip":
			var on := side
			if str(c.get("equip_to", "ally")) == "enemy":
				on = foes_of(side)[0] if not foes_of(side).is_empty() else side
			var entries := _equip_targets(side, c)
			entries.sort_custom(_strongest_first)
			_ask_target(side, "equip", "%s: choose a character to equip" % c.name, c, entries, on, func(x: Dictionary):
				if s.field[b] != c:
					return
				c.equipped_to = x.card.uid
				_emit("equip", {"side": side, "slot": b, "target_side": x.get("side", on), "target_slot": x.slot, "card": c.duplicate(true)})
				_effect(side, c, "%s is equipped to %s" % [c.name, x.card.name], b)
				_recalc()
				_run_fx(side, b, c, "deploy"))   # (an Equip's effects come once it's on its character)
		else:
			_run_fx(side, b, c, "deploy")
	else:
		c.face_down = false
		s.gutter.append(c)
		_emit("hustle", {"side": side, "card": c.duplicate(true), "slot": set, "set": true} if set >= 0 else {"side": side, "card": c.duplicate(true)})
		# A Card Forge Hustle: all of its effects happen when it's played
		if not c.get("effects", []).is_empty():
			_run_fx(side, NO_SLOT, c, "*")
	if int(s.get("hustle_turn", 0)) != turn:
		s.hustle_turn = turn
		s.hustles = 0
	s.hustles = int(s.get("hustles", 0)) + 1   # (Hustles played this turn: "if"/"for each")
	for x in characters(side):
		_run_fx(side, x.slot, x.card, "hustle_played", c)
	_run_lasting(side, "hustle_played", c)
	for foe in foes_of(side):
		for x in characters(foe):
			_run_fx(foe, x.slot, x.card, "foe_hustle", c)
		_run_lasting(foe, "foe_hustle", c)
	_leader_fx(side, "dormant_hustle", c)
	match c.effectKey:
		"corner_deal":
			_draw(side)
			_draw(side)
			if _has_striver(side):
				_effect(side, c, "You control a Striver: no discard")
			else:
				_effect(side, c, "Drew 2 — now discard 1")
				_ask_discard(side, 1, Callable(), "%s: drew 2" % c.name)
		"lion_rescue":
			_ask_target(side, "lion_rescue", "Lion Rescue: choose a Downed LIONS character to stand", c,
				_downed_lions(side), side, func(e: Dictionary):
					e.card.downed = false
					_emit("stand", {"side": side, "slot": e.slot, "card": e.card.duplicate(true)})
					_effect(side, c, "%s stands back up" % e.card.name, e.slot))
		"blood_scent":
			_ask_target(side, "blood_scent", "Blood Scent: choose a Striver to promote", c,
				_promotable_strivers(side), side, func(e: Dictionary):
					_effect(side, c, "%s's promotion is fulfilled" % e.card.name, e.slot)
					_promote(side, e.slot, "Blood Scent"))
	return true


func _use_ability(side: String, slot: int) -> bool:
	if not can_use_ability(side, slot):
		return false
	var maya: Dictionary = card_at(side, slot)
	maya.ability_turn = turn
	var allies := characters(side).filter(func(e): return e.slot != slot and is_lion(e.card))
	allies.sort_custom(_strongest_first)
	_ask_target(side, "maya_buff", "Maya Lv.3: choose a LIONS ally to gain +400 ATK / +400 DEF", maya,
		allies, side, func(e: Dictionary):
			e.card.mods.append({"atk": 400, "def": 400, "until_turn": turn})
			_effect(side, maya, "%s gains +400 ATK and +400 DEF this turn" % e.card.name, slot))
	return true


func _next_phase(side: String) -> bool:
	if not can_act(side):
		return false
	match phase:
		"deployment":
			if no_attacks_yet():
				_emit("notice", {"text": "NO ATTACKS UNTIL EVERYONE HAS HAD A TURN" if ffa else "NO ATTACKS ON TURN 1"})
				_set_phase("regroup")
			else:
				_set_phase("brawl")
		"brawl":
			_set_phase("regroup")
		"regroup":
			_set_phase("end")
			var extra: int = sides[side].hand.size() - HAND_LIMIT
			if extra > 0:
				_ask_discard(side, extra, _end_turn, "Hand limit: %d cards, keep %d" % [sides[side].hand.size(), HAND_LIMIT])
			else:
				_end_turn()
		_:
			return false
	return true


# ── Attacks ──────────────────────────────────────────────────────────────────
# An attack runs in steps; any step may pause for a prompt and continue from its answer.

func _attack(side: String, from: int, target: int, foe := "") -> bool:
	var foes := foes_of(side)
	if foe == "":
		foe = foes[0] if not foes.is_empty() else ""
	if foe == "" or not foe in foes:
		return false
	if not can_attack_with(side, from) or not target in attack_targets(side, foe):
		return false
	var att: Dictionary = card_at(side, from)
	att.has_attacked = true
	# Attacks twice each turn: the first attack leaves it ready for one more
	if not _passive(side, from, att, "double_attack").is_empty() and int(att.get("second_attack", -1)) != turn:
		att.has_attacked = false
		att.second_attack = turn
	_emit("attack", _with_foe_key({"side": side, "from": from, "target": target, "card": att.duplicate(true)}, foe))
	var ctx := {"side": side, "foe": foe, "from": from, "target": target, "att": att, "bonus": 0}
	_attack_ctx = ctx   # (an attacker that promotes mid-attack carries on as its new form: _promote)
	if not _passive(side, from, att, "pierce").is_empty() or rules.get("pierce", false):
		ctx.pierce = true
	var def_now = card_at(foe, target) if target >= 0 else null
	# (at a leader: a Dormant one, or one that has taken the field)
	var at_leader: bool = target == LEADER or (def_now != null and def_now.get("cardType") == "leader")
	var trig: Array = []
	var n := 0
	for e in _fx(att, "attack"):
		n += 1
		trig.append(["attack", e, n])
	if at_leader:
		n = 0
		for e in _fx(att, "attack_leader"):
			n += 1
			trig.append(["attack_leader", e, n])
	for t in trig:
		var when: String = t[0]
		var e: Dictionary = t[1]
		var k: int = t[2]
		var self_buff: bool = str(e.get("do", "")) == "buff" and str(e.get("target", "self")) == "self"
		if self_buff and str(e.get("if", "")) != "" and when == "attack":
			continue   # depends on the defender: settled in the brawl (_brawl_bonus)
		if not _fx_cond(side, from, e, def_now) or not _fx_count_fire(att, "%s%d" % [when, k], e) or not _fx_once(att, "%s%d" % [when, k], e):
			continue
		if self_buff:
			if not _luck_gate(side, from, att, e):
				continue
			var se := _scaled(side, from, e)
			if int(se.get("atk", 0)) != 0:
				ctx.bonus += int(se.get("atk", 0))
				_effect(side, att, "%s: %s ATK this brawl" % [att.name, _signed(int(se.get("atk", 0)))], from)
		elif str(e.get("do", "")) == "pierce":
			ctx.pierce = true
			_effect(side, att, "%s: piercing attack" % att.name, from)
		else:
			_do_fx(side, from, att, e)
	if is_lion(att) and sides[side].brutus_bonus > 0:
		ctx.bonus += sides[side].brutus_bonus
		sides[side].brutus_bonus = 0
		_effect(side, att, "Brutus's momentum: +300 ATK", from)
	_atk_redirect(ctx)
	return true


## Block Enforcer: may take the hit for an allied LIONS character, once per turn.
## An attack whose own trigger removed its target or the attacker ends there
func _atk_gone(ctx: Dictionary) -> bool:
	if winner != "":
		return true
	if not is_same(card_at(ctx.side, ctx.from), ctx.att):
		return true
	if ctx.target >= 0 and card_at(ctx.foe, ctx.target) == null:
		_effect(ctx.side, ctx.att, "%s's target is gone: the attack ends" % ctx.att.name, ctx.from)
		return true
	return false


func _atk_redirect(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
	if _atk_gone(ctx):
		return
	if ctx.target >= 0:
		var def: Dictionary = card_at(foe, ctx.target)
		var be := _ready_enforcer(foe, ctx.target)
		if is_lion(def) and not be.is_empty():
			var worth := _enforcer_worth_it(ctx.att, def, be.card)
			var yes := {"id": "yes", "label": "REDIRECT TO BLOCK ENFORCER", "side": foe, "slot": be.slot}
			var no := {"id": "no", "label": "LET %s TAKE IT" % str(def.name).to_upper()}
			_ask(foe, "redirect", "Block Enforcer: take the hit for %s?" % def.name, be.card,
				[yes, no] if worth else [no, yes], func(choice: String):
					if choice == "yes":
						be.card.redirect_turn = turn
						ctx.target = be.slot
						_effect(foe, be.card, "Block Enforcer steps in and takes the hit", be.slot)
						_emit("retarget", _with_foe_key({"side": ctx.side, "from": ctx.from, "target": ctx.target}, ctx.foe))
					_atk_ambush(ctx))
			return
	_atk_ambush(ctx)


## The defender may spring a face-down Ambush on an attack against a LIONS character.
func _atk_ambush(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
	if _atk_gone(ctx):
		return
	if ctx.target < 0:
		_atk_resolve(ctx)
		return
	var def: Dictionary = card_at(foe, ctx.target)
	if def.face_down:
		def.face_down = false
		_emit("flip", {"side": foe, "slot": ctx.target, "card": def.duplicate(true)})
	var options: Array = []
	if is_lion(def):
		for key in ["no_witnesses_ambush", "lion_ambush"]:
			for slot in BACK:
				var a = card_at(foe, slot)
				if a != null and a.get("effectKey") == key:
					options.append({"id": str(slot), "label": "SPRING %s" % str(a.name).to_upper(), "side": foe, "slot": slot})
	# Card Forge Ambushes can be sprung when any of your characters is attacked
	# (ambushClan: only when the attacked character is of that clan; not while JAMMED)
	var jammed := int(sides[foe].get("jam_until", -1)) >= turn
	for slot in BACK:
		var a = card_at(foe, slot)
		if a != null and not jammed and a.get("cardType") == "ambush" and not a.get("effects", []).is_empty() \
				and not str(a.get("effectKey", "")) in HAND_AMBUSHES \
				and (str(a.get("ambushClan", "")) == "" or def.get("clanTag") == str(a.get("ambushClan", ""))) \
				and (is_lasting(a) or card_can(foe, NO_SLOT, a, "*", {"side": ctx.side, "slot": ctx.from, "card": ctx.att, "attacked": {"side": foe, "slot": ctx.target, "card": def}}, ctx.att)):
			options.append({"id": str(slot), "label": "SPRING %s" % str(a.name).to_upper(), "side": foe, "slot": slot})
	if options.is_empty():
		_atk_resolve(ctx)
		return
	options.append({"id": "no", "label": "DON'T SPRING"})
	_ask(foe, "ambush", "%s is attacking %s. Spring an Ambush?" % [ctx.att.name, def.name], ctx.att, options,
		func(choice: String):
			if choice == "no":
				_atk_resolve(ctx)
				return
			var slot := int(choice)
			if card_at(foe, slot) == null:   # (destroyed while the choice was waiting)
				_atk_resolve(ctx)
				return
			var a: Dictionary = card_at(foe, slot)
			_spring(foe, slot)
			if not str(a.get("effectKey", "")) in HAND_AMBUSHES:
				_spring_fx(ctx, foe, a)
				return
			if a.effectKey == "no_witnesses_ambush":
				if _stays_up(ctx.side, ctx.from, ctx.att):
					_effect(foe, a, "No Witnesses: the attack is negated", slot)
					return
				_effect(foe, a, "No Witnesses: the attacker is Downed and the attack negated", slot)
				_go_down(ctx.side, ctx.from, ctx.att)
				return
			_effect(foe, a, "Lion's Ambush: the attacker loses 1000 ATK this brawl", slot)
			ctx.bonus -= 1000
			_atk_resolve(ctx))


## A sprung Card Forge Ambush: all of its effects happen against the attack. Changing the
## attacker's ATK counts in this brawl. The attack stops if the attacker no longer can make it
## (Downed, gone, in Stasis) or the defender is gone.
func _spring_fx(ctx: Dictionary, foe: String, a: Dictionary) -> void:
	var vs := {"side": ctx.side, "slot": ctx.from, "card": ctx.att, "ctx": ctx}   # (ctx: "Negate the attack" marks it)
	var asks: Array = _new_asks if _in_answer else _asks
	var queued := asks.size()
	for e in _fx(a, "defend" if is_lasting(a) else "*"):   # (a Continuous one's other effects last)
		if winner != "":
			return
		if not _fx_cond(foe, NO_SLOT, e, ctx.att):
			continue
		if str(e.get("do", "")) == "buff" and str(e.get("target", "")) == "attacker" and str(e.get("luck", "")) != "double":
			if not _luck_gate(foe, NO_SLOT, a, e):   # (a coin flip or die roll on it)
				continue
			var atk := int(_scaled(foe, NO_SLOT, e).get("atk", 0))
			if atk != 0:
				ctx.bonus += atk
				_effect(foe, a, "%s: the attacker gets %s ATK this brawl" % [a.name, _signed(atk)], NO_SLOT)
			if e.get("negate", false):
				_negate(foe, NO_SLOT, a, vs)
		else:
			_do_fx(foe, NO_SLOT, a, e, vs)
	if winner != "":
		return
	# The attack goes on, with whatever the Ambush changed, unless it negated the attack or the
	# attacker is Downed, gone or in STASIS
	var go := func() -> void:
		if winner != "" or ctx.get("negated", false):
			return
		if card_at(ctx.side, ctx.from) != ctx.att or ctx.att.downed or in_stasis(ctx.att) or card_at(foe, ctx.target) == null:
			_effect(foe, a, "%s stops the attack" % a.name, NO_SLOT)
			return
		_atk_resolve(ctx)
	# Effects waiting on a choice (a target, DOUBLE OR NOTHING) happen before the brawl: it waits for them
	if asks.size() > queued:
		asks.append({"kind": "then", "side": foe, "cb": go})
	else:
		go.call()


func _atk_resolve(ctx: Dictionary) -> void:
	var side: String = ctx.side
	var foe: String = ctx.foe
	var from: int = ctx.from
	var target: int = ctx.target
	var att: Dictionary = ctx.att

	if target == DIRECT:
		var dmg: int = maxi(0, att.attack + ctx.bonus)
		_emit("clash", _with_foe_key({"side": side, "from": from, "target": DIRECT, "att": dmg, "def": 0, "vs": "DIRECT"}, foe))
		_damage(foe, dmg)
		_lifesteal(side, from, att, dmg)
		if winner == "" and card_at(side, from) == att:
			_run_fx(side, from, att, "direct")
		_bleed(side, att)
		return
	if target == LEADER:
		_hit_leader(ctx)
		_bleed(side, att)
		return

	var def: Dictionary = card_at(foe, target)
	var def_atk := 0
	var def_def := 0
	var vs := {"side": side, "slot": from, "card": att, "attacked": {"side": foe, "slot": target, "card": def}}
	# "When another of your characters is attacked" (covering fire)
	for x in characters(foe):
		if x.slot != target and winner == "" and card_at(side, from) == att:
			_run_fx(foe, x.slot, x.card, "ally_attacked", att, vs)
	if card_at(side, from) == att:
		_run_lasting(foe, "ally_attacked", att, vs)
	var k := 0
	for e in _fx(def, "defend"):
		k += 1
		if winner != "" or card_at(foe, target) != def or not _fx_cond(foe, target, e, att) or not _fx_count_fire(def, "defend%d" % k, e) or not _fx_once(def, "defend%d" % k, e):
			continue
		if str(e.get("do", "")) == "buff" and str(e.get("target", "self")) == "self":
			if not _luck_gate(foe, target, def, e):
				continue
			var se := _scaled(foe, target, e)
			def_atk += int(se.get("atk", 0))
			def_def += int(se.get("def", 0))
			_effect(foe, def, "%s: %s this brawl" % [def.name, _stat_text(se)], target)
		else:
			_do_fx(foe, target, def, e, vs)
	# The defender's effects may have removed or stopped the attacker (or itself)
	if winner != "" or card_at(side, from) != att or att.downed or card_at(foe, target) != def:
		return
	_recalc()   # (what they did to either card counts in this brawl, e.g. SUPPRESS on the attacker)
	var bonus: int = ctx.bonus + _brawl_bonus(side, from, att, def)
	if def.get("effectKey") == "bulwark":
		bonus -= 300
		_effect(foe, def, "Bulwark: the attacker loses 300 ATK", target)

	var def_was_downed: bool = def.downed
	var def_info := {"downed": def.downed, "position": def.position, "face_down": false}
	var vs_def: bool = def.downed or def.position == "def"
	var a_val: int = maxi(0, att.attack + bonus)
	var d_val: int = (def.defense + def_def) if vs_def else (def.attack + def_atk)
	_emit("clash", _with_foe_key({"side": side, "from": from, "target": target, "att": a_val, "def": d_val,
		"vs": "DEF" if vs_def else "ATK"}, foe))

	var result := ""
	if vs_def:
		if a_val > d_val:
			if ctx.get("pierce", false):
				_battle_damage(foe, target, def, a_val - d_val, side, from, att)
			result = _defeat(foe, target)
		else:
			_emit("blocked", {"side": foe, "slot": target})
			if a_val < d_val:   # a failed attack costs the difference, as it does against ATK
				_battle_damage(side, from, att, d_val - a_val, foe, target, def)
	elif a_val > d_val:
		_battle_damage(foe, target, def, a_val - d_val, side, from, att)
		result = _defeat(foe, target)
	elif a_val < d_val:
		_battle_damage(side, from, att, d_val - a_val, foe, target, def)
		_defeat(side, from)
	else:
		_emit("notice", {"text": "TIE — BOTH GO DOWN"})
		result = _defeat(foe, target)
		_defeat(side, from)

	if winner == "" and card_at(side, from) == att and not att.downed:
		if result == "ko":
			_on_ko(side, from, att, def_was_downed, target, foe)
			_run_fx(side, _slot_of(side, att, from), att, "ko", def_info)
		elif result == "downed":
			_on_down(side, from, att, foe)
			_run_fx(side, _slot_of(side, att, from), att, "down", def_info)
	_bleed(side, att)
	_bleed(foe, def)


## BLEED: a bleeding character loses ATK and DEF after every brawl it is in.
func _bleed(side: String, c: Dictionary) -> void:
	var n := int(c.get("bleed", 0))
	if n <= 0 or winner != "":
		return
	var slot := _slot_of(side, c, -1)
	if slot < 0:
		return
	c.mods.append({"atk": -n, "def": -n, "until_turn": FOREVER})
	_emit("status_tick", {"side": side, "slot": slot, "kind": "bleed", "amount": n, "card": c.duplicate(true)})


## A dormant leader soaks attacks with its Influence (its DEF). At 0 it is defeated and its
## Dormant effects end; its owner loses no Morale, since it never took the field.
func _hit_leader(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
	var leader: Dictionary = sides[foe].leader
	var dmg: int = maxi(0, ctx.att.attack + ctx.bonus)
	_emit("clash", _with_foe_key({"side": ctx.side, "from": ctx.from, "target": LEADER, "att": dmg,
		"def": leader.influence, "vs": "INFLUENCE"}, ctx.foe))
	leader.influence = maxi(0, leader.influence - dmg)
	_emit("leader_hit", {"side": foe, "amount": dmg, "influence": leader.influence})
	if leader.influence <= 0:
		sides[foe].leader_state = "defeated"
		sides[foe].gutter.append(leader)
		_emit("leader_down", {"side": foe, "card": leader.duplicate(true)})
	else:
		_leader_fx(foe, "dormant_hit", ctx.att)


# ── Battle results ───────────────────────────────────────────────────────────

## First loss Downs a character; losing again while Downed sends it to the Gutter.
func _defeat(side: String, slot: int) -> String:
	var c: Dictionary = card_at(side, slot)
	if c.get("shield", false):
		c.erase("shield")
		_effect(side, c, "%s's shield takes the blow" % c.name, slot)
		return "saved"
	if c.downed:
		if is_lion(c) and c.get("subtype") == "striver" and _spring_kings_test(side, slot, c):
			return "saved"
		_ko(side, slot)
		return "ko"
	if _stays_up(side, slot, c):
		_effect(side, c, "%s stays standing" % c.name, slot)
		return "saved"
	return _go_down(side, slot, c)


## A character goes Down, from a lost brawl or an effect: it drops to DEF, and its "when it's Downed"
## and its allies' "when another of your characters is Downed" effects happen. BRITTLE (Card Forge
## passive): it's KO'd instead (tokens like Skeletons don't clog the field). -> "ko" | "downed"
## REMAINS (a passive printed on a token): KO'd or sacrificed, it goes to the Gutter instead of vanishing.
static func remains(c) -> bool:
	if not c is Dictionary:
		return false
	for e in c.get("effects", []):
		if e is Dictionary and str(e.get("when", "")) == "passive" and str(e.get("do", "")) == "remains":
			return true
	return false


func _go_down(side: String, slot: int, c: Dictionary) -> String:
	if not _passive(side, slot, c, "brittle").is_empty():
		_ko(side, slot)
		return "ko"
	c.downed = true
	c.position = "def"   # a Downed character is in DEF
	_emit("downed", {"side": side, "slot": slot, "card": c.duplicate(true)})
	_run_fx(side, slot, c, "self_downed")
	_ally_downed(side, slot, c)
	return "downed"


func _ko(side: String, slot: int) -> void:
	if card_at(side, slot) == null:
		return
	var c: Dictionary = card_at(side, slot)
	var undead: bool = not c.get("token", false) and not c.get("risen", false) \
		and (c.get("undead_given", false) or not _passive(side, slot, c, "undead").is_empty())
	sides[side].field[slot] = null
	var bounty = c.get("bounty")
	var own := _owner_of(side, c)
	c.erase("charmed")
	c.downed = false
	c.mods = []
	_clear_status(c)
	if not c.get("token", false) or remains(c):   # a token vanishes (REMAINS: it goes to the Gutter)
		sides[own].gutter.append(c)
	# UNDEAD: the first time it's KO'd, it rises at the end of the turn
	if undead:
		c.rise_turn = turn
	_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})
	_run_fx(side, slot, c, "self_ko")
	# "When another of your characters is KO'd"
	for x in characters(side):
		_run_fx(side, x.slot, x.card, "ally_ko", c)
	_run_lasting(side, "ally_ko", c)
	# "When an enemy character is KO'd" (by anything): every opponent's cards
	for foe in foes_of(side):
		for x in characters(foe):
			_run_fx(foe, x.slot, x.card, "foe_ko", c)
		_run_lasting(foe, "foe_ko", c)
	# BOUNTY: whoever put it on draws
	if bounty is Dictionary and winner == "" and sides.has(str(bounty.by)):
		_effect(str(bounty.by), c, "BOUNTY on %s collected: draw %d" % [c.name, int(bounty.n)], -1)
		for i in int(bounty.n):
			if winner != "":
				break
			_draw(str(bounty.by))


## "When another of your characters is Downed" (by a brawl or an effect).
func _ally_downed(side: String, slot: int, c: Dictionary) -> void:
	for x in characters(side):
		if x.slot != slot and winner == "":
			_run_fx(side, x.slot, x.card, "ally_downed", c)
	_run_lasting(side, "ally_downed", c)


## "When this card is milled or discarded": it just went from the deck or hand to its owner's Gutter.
func _to_gutter_fx(side: String, c) -> void:
	if winner == "" and c is Dictionary and not c.get("token", false) and not c.get("effects", []).is_empty():
		_take_self = true   # (its own "put it onto the field" may take it from the Gutter)
		_run_fx(side, NO_SLOT, c, "self_gutter")
		_take_self = false


## How many Hustles a side has played this turn.
func _hustles_this_turn(side: String) -> int:
	var s: Dictionary = sides[side]
	return int(s.get("hustles", 0)) if int(s.get("hustle_turn", 0)) == turn else 0


## Whether a character has a status CLEANSE would take away.
func _afflicted(c: Dictionary) -> bool:
	return c.has("poison") or c.has("burn") or c.has("bleed") or c.has("bounty") or frozen(c) or in_stasis(c) \
		or int(c.get("stun_until", 0)) >= turn or int(c.get("suppress_until", 0)) >= turn or int(c.get("silence_until", 0)) >= turn


## Put a character back on top of its owner's deck (a token just vanishes).
func _topdeck(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	var own := _owner_of(side, c)
	c.erase("charmed")
	if c.get("token", false):
		_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})
		return
	c.downed = false
	c.mods = []
	c.position = "atk"
	c.face_down = false
	c.has_attacked = false
	for k in ["shield", "stun_until", "down_turns", "kings_test", "fx_used", "fx_count"]:
		c.erase(k)
	_clear_status(c)
	sides[own].deck.append(c)   # (draws take from the end)
	if own == side:
		_emit("topdeck", {"side": side, "slot": slot, "card": c.duplicate(true)})
	else:
		_emit("topdeck", {"side": side, "slot": slot, "card": c.duplicate(true), "to": own})


## Remove a character from the game: it doesn't go to the Gutter, and no KO effects happen.
func _exile(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	c.erase("charmed")
	_clear_status(c)
	_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true), "exiled": true})


## Battle damage: the Morale a side loses for its card losing a brawl (the other card's side may gain
## it with LIFESTEAL). None if its card has "no battle damage" (a Card Forge passive).
func _battle_damage(side: String, slot: int, mine: Dictionary, amount: int, other_side: String, other_slot: int, other: Dictionary) -> void:
	if amount <= 0:
		return
	if not _passive(side, slot, mine, "no_battle_damage").is_empty():
		_effect(side, mine, "%s: no battle damage" % mine.name, slot)
		return
	_damage(side, amount)
	_lifesteal(other_side, other_slot, other, amount)


## LIFESTEAL (Card Forge passive): the Morale a character takes from an opponent in a brawl, its owner gains.
func _lifesteal(side: String, slot: int, c, amount: int) -> void:
	if amount <= 0 or winner != "" or c == null or _passive(side, slot, c, "lifesteal").is_empty():
		return
	_heal(side, c, amount, slot)


func _damage(side: String, amount: int, paid := false) -> void:
	if amount <= 0:
		return
	var s: Dictionary = sides[side]
	var wall := 0 if paid else int(s.get("barricade", 0))
	if wall > 0:
		var held := mini(wall, amount)
		s.barricade = wall - held
		amount -= held
		_emit("barricade", {"side": side, "amount": s.barricade, "held": held})
		if amount <= 0:
			return
	s.morale = maxi(0, s.morale - amount)
	_emit("damage", {"side": side, "amount": amount, "morale": s.morale})
	if s.morale <= 0 and winner == "":
		_lose(side, "morale")
	elif winner == "":
		# A leader that Awakens at low Morale (its own, or an opponent's) can take the field right
		# away, even in the middle of the other player's Brawl phase
		for x in [side] + foes_of(side):
			_check_awaken(x, true)
		_boss_phases(side)


## Turf Defense: the boss's phases its Morale has dropped into, each once, in order.
func _boss_phases(side: String) -> void:
	var b = rules.get("boss")
	if not b is Dictionary or str(b.get("seat", "")) != side or winner != "":
		return
	var s: Dictionary = sides[side]
	var phases: Array = b.get("phases", []) if b.get("phases") is Array else []
	while winner == "" and int(s.get("boss_phase", 0)) < phases.size() and s.morale <= int(phases[int(s.get("boss_phase", 0))].get("below", 0)):
		var ph: Dictionary = phases[int(s.get("boss_phase", 0))]
		s.boss_phase = int(s.get("boss_phase", 0)) + 1
		_emit("boss_phase", {"side": side, "phase": s.boss_phase, "label": str(ph.get("label", ""))})
		var src = s.leader if s.leader != null else {"name": str(b.get("name", "The boss")), "uid": "boss", "effects": []}
		for e in (ph.get("fx", []) if ph.get("fx") is Array else []):
			for foe in (foes_of(side) if e.get("each_foe", false) else [""]):
				if winner != "":
					break
				_do_fx(side, NO_SLOT, src, e, {"side": foe} if foe != "" else {})
		_recalc()


## `side` is out (no Morale, or decked out). Two players: the other one wins. FFA: they take the
## last place still open, their cards leave at the end of the action (_sweep_out), and the last
## player standing wins.
func _lose(side: String, reason: String) -> void:
	if winner != "":
		return
	if not ffa:
		_end(seats[1] if seats[0] == side else seats[0], reason)
		return
	var s: Dictionary = sides[side]
	if _is_out(side):
		return
	s.out = _alive().size()
	places[side] = s.out
	_emit("eliminated", {"side": side, "place": s.out, "reason": reason})
	var left := _alive()
	# The last one standing wins; with teams, the last team standing (every seat left is on it)
	if left.size() == 1 or (not teams.is_empty() and left.all(func(x): return x == left[0] or _teammates(x, left[0]))):
		for x in left:
			places[x] = 1
		_end(left[0], reason)


## FFA, after each action: the cards of players who went out leave the game, their prompts are
## dropped, and if it was their turn the next player's begins.
func _sweep_out() -> void:
	var changed := false
	for side in seats:
		var s: Dictionary = sides[side]
		if not _is_out(side) or s.get("cleared", false):
			continue
		s.cleared = true
		changed = true
		var field: Array = []
		field.resize(10)
		s.field = field
		s.hand = []
		if s.leader_state == "dormant":
			s.leader_state = "defeated"
	if not changed or winner != "":
		return
	_asks = _asks.filter(func(a): return not _is_out(a.side))
	if pending.has("side") and _is_out(str(pending.side)):
		pending = {}
	while winner == "" and _is_out(active):
		for side in seats:
			for c in sides[side].field:
				if c != null:
					c.mods = c.mods.filter(func(m): return m.until_turn > turn)
		active = _next_seat(active)
		turn += 1
		_begin_turn()
	_flush_asks()
	if seats.any(func(x): return _is_out(x) and not sides[x].get("cleared", false)):
		_sweep_out()


## FFA events about a brawl say which opponent it's with (two players: unchanged).
func _with_foe_key(ev: Dictionary, foe: String) -> Dictionary:
	if ffa:
		ev.foe = foe
	return ev


func _end(win_side: String, reason: String) -> void:
	winner = win_side
	end_reason = reason
	pending = {}
	_asks.clear()
	_new_asks.clear()
	_emit("game_over", {"winner": winner, "reason": reason})


func _brawl_bonus(side: String, from: int, att: Dictionary, def: Dictionary) -> int:
	var extra := 0
	var k := 0
	for e in _fx(att, "attack"):
		k += 1
		if str(e.get("do", "")) == "buff" and str(e.get("target", "self")) == "self" \
				and str(e.get("if", "")) != "" and _fx_cond(side, from, e, def) and _fx_once(att, "attack%d" % k, e):
			if not _luck_gate(side, from, att, e):
				continue
			var se := _scaled(side, from, e)
			if int(se.get("atk", 0)) != 0:
				extra += int(se.get("atk", 0))
				_effect(side, att, "%s: %s ATK this brawl" % [att.name, _signed(int(se.get("atk", 0)))], from)
	return extra + _key_brawl_bonus(side, from, att, def)


func _key_brawl_bonus(side: String, from: int, att: Dictionary, def: Dictionary) -> int:
	var key: String = att.get("effectKey", "")
	if key == "goldfang_attacker" and def.position == "def" and not def.downed:
		_effect(side, att, "Goldfang hits a defender: +500 ATK", from)
		return 500
	if def.downed and key in ["hunter_lv1", "hunter_lv2", "hunter_lv3", "mauler"]:
		_effect(side, att, "%s smells blood: +500 ATK vs Downed" % att.name, from)
		return 500
	return 0


func _on_ko(side: String, slot: int, att: Dictionary, was_downed: bool, target: int, foe := "") -> void:
	var key: String = att.get("effectKey", "")
	if foe == "":
		foe = foes_of(side)[0] if not foes_of(side).is_empty() else side
	if key == "brutus_enter":
		sides[side].brutus_bonus = 300
		_effect(side, att, "Brutus: your next LIONS attacker gains +300 ATK", slot)
	match key:
		"eric_lv3_draw":
			_effect(side, att, "Eric Lv.3 KO: draw 1 card", slot)
			_draw(side)
		"lion_clan_bonus":
			if att.get("promotesTo") is String and not att.get("abilityOnlyPromote", false):
				_promote(side, slot, att.name)
		"mauler":
			if was_downed:
				_effect(side, att, "Mauler: enemies in the next lanes lose 500 DEF this turn", slot)
				for e in characters(foe):
					if absi(e.slot - target) == 1:
						e.card.mods.append({"def": -500, "until_turn": turn})
	if key in ["hunter_lv2", "hunter_lv3"]:
		var standing := characters(foe).filter(func(e): return not e.card.downed and not _stays_up(foe, e.slot, e.card))
		standing.sort_custom(_strongest_first)
		_ask_target(side, "hunter_down", "%s KO: choose an enemy character to Down" % att.name, att,
			standing, foe, func(e: Dictionary):
				_effect(side, att, "%s Downs %s" % [att.name, e.card.name], slot)
				_go_down(foe, e.slot, e.card))
	if was_downed:
		if key in ["hunter_lv1", "hunter_lv2"]:
			_promote(side, slot, att.name)
		elif key == "hunter_lv3":
			att.has_attacked = false
			_effect(side, att, "%s may attack again this turn" % att.name, slot)


func _on_down(side: String, slot: int, att: Dictionary, foe := "") -> void:
	var key: String = att.get("effectKey", "")
	match key:
		"brutus_enter":
			sides[side].brutus_bonus = 300
			_effect(side, att, "Brutus: your next LIONS attacker gains +300 ATK", slot)
		"debt_collector":
			if foe == "":
				foe = foes_of(side)[0] if not foes_of(side).is_empty() else ""
			if foe != "" and not sides[foe].hand.is_empty():
				_effect(side, att, "Debt Collector: your opponent discards 1 card", slot)
				_ask_discard(foe, 1, Callable(), "Debt Collector makes you discard")


func _spring_kings_test(side: String, slot: int, c: Dictionary) -> bool:
	for s in BACK:
		var a = card_at(side, s)
		if a != null and a.get("effectKey") == "kings_test":
			_spring(side, s)
			_effect(side, a, "King's Test: %s survives — it may promote next turn" % c.name, s)
			c.kings_test = true
			return true
	return false


func _spring(side: String, slot: int) -> void:
	var a: Dictionary = card_at(side, slot)
	a.face_down = false
	if is_lasting(a):   # a Continuous Ambush stays, face-up
		_emit("ambush", {"side": side, "slot": slot, "card": a.duplicate(true), "stays": true})
		return
	sides[side].field[slot] = null
	sides[side].gutter.append(a)
	_emit("ambush", {"side": side, "slot": slot, "card": a.duplicate(true)})


# ── Effects ──────────────────────────────────────────────────────────────────

## evolved: a Striver's new form arriving by promotion. Its own "when deployed" effects run, but it
## doesn't count as a deploy for other cards ("when you / your opponent deploy a character").
func _on_deploy(side: String, slot: int, c: Dictionary, evolved := false) -> void:
	c.erase("fx_count")   # "times" counts start fresh each time a card enters the field
	_run_fx(side, slot, c, "deploy")
	var foes := foes_of(side)
	if not evolved:
		for x in characters(side):
			if x.slot != slot:
				_run_fx(side, x.slot, x.card, "ally_deployed", c)
		for foe in foes:
			for x in characters(foe):
				_run_fx(foe, x.slot, x.card, "foe_deployed", c)
		_run_lasting(side, "ally_deployed", c)
		for foe in foes:
			_run_lasting(foe, "foe_deployed", c)
		_leader_fx(side, "dormant_ally_deployed", c)
		for foe in foes:
			_leader_fx(foe, "dormant_foe_deployed", c)
	match c.get("effectKey", ""):
		"pride_lieutenant_deploy":
			var allies := characters(side).filter(func(e): return e.slot != slot and is_lion(e.card))
			allies.sort_custom(_strongest_first)
			_ask_target(side, "lieutenant", "Pride Lieutenant: choose a LIONS ally to gain +500 ATK", c,
				allies, side, func(e: Dictionary):
					e.card.mods.append({"atk": 500, "until_turn": turn})
					_effect(side, c, "%s gains +500 ATK this turn" % e.card.name, slot))
		"brutus_enter":
			var enemies := _enemy_chars(side)
			enemies.sort_custom(_strongest_first)
			_ask_target(side, "brutus", "Brutus: choose an enemy character to lose 700 ATK", c,
				enemies, foes[0] if not foes.is_empty() else side, func(e: Dictionary):
					e.card.mods.append({"atk": -700, "until_turn": turn + _round_span()})
					_effect(side, c, "%s loses 700 ATK until the end of your opponent's next turn" % e.card.name, slot))
		"sovereign":
			var hit := 0
			for foe in foes:
				for e in characters(foe):
					if not e.card.downed and e.card.defense <= 1500 and not _stays_up(foe, e.slot, e.card):
						hit += 1
						_go_down(foe, e.slot, e.card)
			if hit > 0:
				_effect(side, c, "Sovereign's arrival Downs %d enem%s" % [hit, "y" if hit == 1 else "ies"], slot)


## Swap a card on the field for its next form (from the hideout when it's there).
## The owner picks ATK or DEF for the new form.
func _promote(side: String, slot: int, reason: String) -> void:
	var s: Dictionary = sides[side]
	var old = card_at(side, slot)
	if old == null or old.get("subtype") != "striver" or old.get("charmed") is Dictionary:   # only Strivers level up (not a CHARMED one)
		return
	var to_id := CardDB.next_form(old.id)
	if to_id == "":
		return
	if not _next_in_hideout(side, old):   # (its next level has to be waiting in the Hideout)
		_emit("notice", {"side": side, "text": "%s CAN'T PROMOTE: NO %s LV%d IN THE HIDEOUT" % [str(old.name).to_upper(),
			str(CardDB.get_card(to_id).get("name", to_id)).to_upper(), int(CardDB.get_card(to_id).get("level", 2))]})
		return
	if s.promoted.has(slot):   # (once per turn)
		_emit("notice", {"side": side, "text": "%s CAN'T PROMOTE AGAIN THIS TURN" % str(old.name).to_upper()})
		return
	s.promoted[slot] = true
	var preview := CardDB.get_card(to_id)
	var ask := _ask(side, "position", "Promote to %s: choose its position" % preview.get("name", to_id), preview, [
		{"id": "atk", "label": "ATK POSITION"}, {"id": "def", "label": "DEF POSITION"},
	], func(pos: String):
		if card_at(side, slot) != old or old.get("downed", false) or in_stasis(old):
			return
		var promoted = null
		for i in s.hideout.size():
			if s.hideout[i].id == to_id:
				promoted = s.hideout.pop_at(i)
				break
		if promoted == null:
			promoted = make_card(to_id)
		promoted.position = pos
		promoted.face_down = false
		promoted.has_attacked = true   # promotion sickness: sits out the rest of the turn
		promoted.rest_turn = turn   # shown as resting: it can't attack this turn
		promoted.evolved_turn = turn   # ...nor use its Activate abilities (see activations)
		promoted.deployed_turn = turn
		s.field[slot] = promoted
		if not _attack_ctx.is_empty() and is_same(_attack_ctx.att, old):   # promoted mid-attack: the attack goes on
			_attack_ctx.att = promoted
		# The same fighter, stronger: its ATK/DEF changes (buffs and debuffs) and its Equips carry
		# over; its statuses (STASIS, FREEZE, ...) don't
		promoted.mods = old.get("mods", []).map(func(m): return m.duplicate())
		for q in _equips_on(old):
			q.card.equipped_to = promoted.uid
		old.mods = []
		old.downed = false
		_clear_status(old)
		s.gutter.append(old)
		_emit("promote", {"side": side, "slot": slot, "from": old.duplicate(true),
			"card": promoted.duplicate(true), "reason": reason})
		_on_deploy(side, slot, promoted, true)
		for x in characters(side):
			if winner == "":
				_run_fx(side, x.slot, x.card, "ally_promoted", promoted)
		_run_lasting(side, "ally_promoted", promoted)
		if promoted.get("subtype") == "striver" and is_lion(promoted) and not s.mentor_used:
			for e in characters(side):
				if e.card.get("effectKey") == "pride_mentor_draw":
					s.mentor_used = true
					_effect(side, e.card, "Pride Mentor: a Striver promoted — draw 2", e.slot)
					_draw(side)
					_draw(side)
					break)
	# Downed, KO'd or in STASIS before the player answers (an Ambush mid-attack): it doesn't promote
	ask.still = func() -> bool: return card_at(side, slot) == old and not old.get("downed", false) and not in_stasis(old)


## King Roan awakens at the start of your turn once you control 4+ LIONS characters or have
## 10+ Authority: he takes a front-row slot (sending any card there to the Gutter).
## A Dormant leader whose Awaken condition is met is offered the field: at the start of its owner's
## turn, and the moment Morale drops (mid_turn), once a turn ("stay Dormant" isn't asked again until
## the next turn).
func _check_awaken(side: String, mid_turn := false) -> void:
	var s: Dictionary = sides[side]
	if s.leader_state != "dormant" or s.get("awaken_asking", false) or (mid_turn and int(s.get("awaken_waited", -1)) == turn):
		return
	var cond: Dictionary = s.leader.get("awakenCondition", {})
	if cond.is_empty():
		return
	# Any of: N+ standing (clan) characters, Authority N+, Morale N or less
	# (King Roan's older form: lions = LIONS characters, authorityThreshold = Authority)
	var clan := "lion" if cond.get("lions") != null else str(cond.get("clan", ""))
	var chars := characters(side).filter(func(e): return (clan == "" or e.card.get("clanTag") == clan) \
			and not e.card.downed and not e.card.face_down).size()
	var need_chars = cond.get("lions") if cond.get("lions") != null else cond.get("chars", 99)
	var need_auth = cond.get("authorityThreshold") if cond.get("authorityThreshold") != null else cond.get("authority", 99)
	var ready: bool = chars >= int(need_chars) or s.authority_max >= int(need_auth) \
			or (cond.get("morale") != null and s.morale <= int(cond.morale)) \
			or (cond.get("gutter") != null and s.gutter.size() >= int(cond.gutter)) \
			or (cond.get("foe_morale") != null and foes_of(side).any(func(f): return sides[f].morale <= int(cond.foe_morale))) \
			or (cond.get("influence") != null and int(s.leader.influence) <= int(cond.influence)) 			or (cond.get("luck") != null and int(s.get("luck_won", 0)) >= int(cond.luck))   # N won coin flips / die rolls
	if not ready:
		return
	var options: Array = []
	var empties: Array = []
	var taken: Array = []
	for slot in FRONT:
		var c = s.field[slot]
		if c == null:
			empties.append({"id": str(slot), "label": "LANE %d (EMPTY)" % (slot + 1), "side": side, "slot": slot})
		else:
			taken.append({"id": str(slot), "label": "REPLACE %s" % str(c.name).to_upper(), "side": side, "slot": slot,
				"value": _attack_value(c)})
	taken.sort_custom(func(a, b): return a.value < b.value or (a.value == b.value and a.slot < b.slot))
	options.append_array(empties)
	options.append_array(taken)
	options.append({"id": "wait", "label": "STAY DORMANT FOR NOW"})
	s.awaken_asking = true
	_ask(side, "awaken", "%s AWAKENS! Choose a lane" % s.leader.name, s.leader, options, func(choice: String):
		s.erase("awaken_asking")
		if s.leader_state != "dormant":
			return
		if choice == "wait":
			s.awaken_waited = turn
			return
		var slot := int(choice)
		var displaced = s.field[slot]
		if displaced != null:
			s.field[slot] = null
			displaced.downed = false
			displaced.mods = []
			s.gutter.append(displaced)
			_emit("ko", {"side": side, "slot": slot, "card": displaced.duplicate(true)})
		var king: Dictionary = s.leader
		s.leader_state = "awake"
		king.position = "atk"
		king.has_attacked = not bool(cond.get("ready", false))   # ready: it may attack the turn it Awakens
		if not bool(cond.get("ready", false)):
			king.rest_turn = turn
		king.deployed_turn = turn
		s.field[slot] = king
		_emit("awaken", {"side": side, "slot": slot, "card": king.duplicate(true)})
		_effect(side, king, "%s takes the street" % king.name, slot)
		king.erase("fx_count")
		_run_fx(side, slot, king, "awaken")
		_recalc())


## Recompute ATK/DEF from base stats, temporary mods and passives, and report them.
func _recalc() -> void:
	_sweep_equips()
	var values := {}
	for side in sides:
		var s: Dictionary = sides[side]
		var foe_has_downed := _enemy_chars(side).any(func(e): return e.card.downed)
		var lions := lion_count(side)
		var roan: bool = s.leader_state == "dormant" and s.leader.get("effectKey") == "king_roan_leader" and lions >= 2
		var auras := _auras(side)
		var foe_auras: Array = []
		for f in foes_of(side):
			foe_auras.append_array(_auras(f).filter(func(a): return str(a[1].get("target", "")) == "enemies"))
		values[side] = {}
		for slot in FRONT:
			var c = s.field[slot]
			if c == null:
				continue
			# (what an Equip changed, on its character or any other, goes when the Equip is gone)
			if c.mods.any(func(m): return m.get("equip") != null):
				var on: Array = []
				for sd in sides:
					for x in _lasting(sd, "equip"):
						on.append(int(x.card.uid))
				c.mods = c.mods.filter(func(m): return m.get("equip") == null or on.has(int(m.equip)))
			var atk: int = c.base_attack
			var df: int = c.base_defense
			var set_atk := false   # (a set_stats: it is that number; only later changes count)
			var set_def := false
			for m in c.mods:
				if m.get("set_atk") != null:
					atk = int(m.set_atk)
					set_atk = true
				else:
					atk += int(m.get("atk", 0))
				if m.get("set_def") != null:
					df = int(m.set_def)
					set_def = true
				else:
					df += int(m.get("def", 0))
			var atk_set := atk
			var def_set := df
			var other_lions := lions - (1 if is_lion(c) else 0)
			match c.get("effectKey", ""):
				"lion_grunt_synergy":
					if other_lions > 0:
						atk += 300
				"pride_runner_adjacency":
					if _adjacent_lion(side, slot):
						atk += 400
				"eric_lv3_draw":
					atk += 100 * other_lions
				"kingpin":
					if foe_has_downed:
						atk += 400
				"sovereign":
					if foe_has_downed:
						atk += 600
			if roan and is_lion(c):
				atk += 300
			for a in auras:
				if _aura_hits(a, slot, c):
					atk += int(a[1].get("atk", 0))
					df += int(a[1].get("def", 0))
			for a in foe_auras:
				var clan := str(a[1].get("clan", ""))
				if clan == "" or c.get("clanTag") == clan:
					atk += int(a[1].get("atk", 0))
					df += int(a[1].get("def", 0))
			for q in _equips_on(c):   # an Equip's buffs are its character's
				for e in _fx(q.card, "passive"):
					if str(e.get("do", "")) == "buff" and _fx_cond(q.side, q.slot, e, null):
						var se := _scaled(q.side, q.slot, e)
						atk += int(se.get("atk", 0))
						df += int(se.get("def", 0))
			for adj in [slot - 1, slot + 1]:
				if adj in FRONT and s.field[adj] != null and s.field[adj].get("effectKey") == "bulwark":
					df += 400
			if set_atk:   # (auras, Equips and the like don't change a set number)
				atk = atk_set
			if set_def:
				df = def_set
			if c.mods.filter(func(m): return m.get("swap", false)).size() % 2 == 1:   # (swapped: ATK and DEF trade places)
				var was := atk
				atk = df
				df = was
			c.attack = maxi(0, atk)
			c.defense = maxi(0, df)
			values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense, c.face_down, statuses(c)]
	_emit("stats", {"values": values})


# ── Card effects from data (Card Forge) ──────────────────────────────────────
# A card's "effects" list holds building blocks: {when, do, target, atk, def, amount, until,
# clan, kind, if, n, once, times}. shared/duel/DuelState.js runs exactly the same rules.
#   when:   deploy | attack | defend | ko | down | direct | self_downed | self_ko |
#           ally_deployed | ally_ko (another of your characters is KO'd) | turn_start | turn_end |
#           passive | activate (the player uses it from the card: see activations())
#   do:     buff | down | ko | stand | bounce | force_def | stun | shield | pierce | draw |
#           search | recover | discard | mill | damage | heal | drain | authority | promote |
#           attack_again | ready (allies that attacked may attack again) | force_atk | poison |
#           burn | bleed | shock | freeze | stasis | suppress (Militia: -X ATK, can't attack)
#   (more when: foe_ko (an enemy is KO'd) | foe_turn_end | ally_attacked (another of yours is
#           attacked); more if: self_def | self_atk | enemies_le | turn_ge | deck_le | allies_le)
#   more do: token (copies of the card `token` into empty lanes; they vanish when they leave the
#           field) | call (a character from your deck onto the field, filters like revive)
#   per:    "for each": atk / def / amount are multiplied by a count (allies | enemies |
#           foe_downed | gutter | foe_gutter | hand; per_clan, per_kind, per_max)
#   or:     "choose one": this effect or the next (same trigger); the player picks (label: its text)
#   until:  buff: turn | next_turn | forever (while the card stays on the field)
#   amount: poison (ATK lost per turn), burn (Morale lost per turn), bleed (ATK/DEF lost per
#           brawl), shock (damage to DEF: Downs the target if it is at least its DEF)
#   target: self | ally | allies | enemy | enemies | attacker (defend only)
#   clan:   only characters with this clan tag (for ally_deployed: the deployed ally's clan)
#   kind:   search / recover: "" | gang_member | hustle | ambush
#   if:     "" | vs_def | vs_downed | vs_atk | allies | alone | adjacent | foe_downed |
#           hand_le | morale_le | foe_morale_le | enemies_ge | gutter_ge | leader_dormant
#   n:      the number for allies / hand_le / morale_le / foe_morale_le / enemies_ge / gutter_ge
#   once:   true = once per turn
#   passive (when "passive"): buff (target self / allies / enemies) | pierce | untargetable |
#           immune (no POISON, BURN, BLEED, SHOCK, FREEZE, STASIS or STUN) | guard (must be
#           attacked first while standing) | double_attack | cost_down (amount, clan: your cards
#           cost that much less) | no_down (can't be Downed while you control another character)
#   times:  ko / down: happens once the card has KO'd / Downed this many characters while on the
#           field (it then counts again from 0; leaving the field resets the count)

## if_done ("If you do, ..."): an effect that follows on from the one before it becomes that
## effect's then (see _do_fx), so it happens only if the one before did something.
static func _fold_if_done(list: Array) -> Array:
	if not list.any(func(e): return e is Dictionary and e.get("if_done", false)):
		return list
	var out: Array = []
	for e in list:
		if e is Dictionary and e.get("if_done", false) and not out.is_empty() and out[-1] is Dictionary:
			var top: Dictionary = out[-1].duplicate()
			out[-1] = top
			var p: Dictionary = top
			while p.get("then") is Dictionary:
				p.then = p.then.duplicate()
				p = p.then
			p.then = e
		else:
			out.append(e)
	return out


func _fx(c, when: String) -> Array:
	var out: Array = []
	if c == null or in_stasis(c):   # a character in STASIS is frozen in time: no effects
		return out
	# SILENCED: its effects don't work, except its own PROMOTE (a Striver still levels up)
	var silenced: bool = int(c.get("silence_until", 0)) >= turn
	# A Downed character's effects don't work, except as it goes Down or is KO'd, and the ones
	# that stand it back up ("At the end of your turn: if this card is Downed, it stands back up")
	var downed: bool = c.get("downed", false) and not when in ["self_downed", "self_ko"]
	for e in _fold_if_done(c.get("effects", [])):
		if e is Dictionary and (when == "*" or str(e.get("when", "")) == when):   # "*": all (Hustles, Ambushes)
			if silenced and str(e.get("do", "")) != "promote":
				continue
			# (...but a "?" card keeps the ATK and DEF its own passive gives it: Downed isn't SILENCE)
			var own_stats: bool = when == "passive" and c.get("varStats", false) and str(e.get("do", "")) == "buff" \
				and str(e.get("target", "")) in ["", "self"]
			if downed and not (str(e.get("do", "")) == "stand" and str(e.get("target", "")) == "self") and not own_stats:
				continue
			out.append(e)
	return out


## Once-per-turn effects: true the first time this turn (and marks it used), false after.
## times: the effect waits until its trigger has happened that many times (e.g. Downs 2 characters).
## times on attack / defend triggers: counts this one; true once it has happened enough (then counts again).
func _fx_count_fire(c: Dictionary, key: String, e: Dictionary) -> bool:
	if not _fx_count(c, key, e):
		return false
	if int(e.get("times", 1)) > 1:
		c.fx_count.erase(key)
	return true


func _fx_count(c: Dictionary, key: String, e: Dictionary) -> bool:
	var need := int(e.get("times", 1))
	if need <= 1:
		return true
	var count: Dictionary = c.get("fx_count", {})
	count[key] = int(count.get(key, 0)) + 1
	c.fx_count = count
	return int(count[key]) >= need


func _fx_once(c: Dictionary, key: String, e: Dictionary) -> bool:
	if not e.get("once", false):
		return true
	var used: Dictionary = c.get("fx_used", {})
	if int(used.get(key, -1)) == turn:
		return false
	used[key] = turn
	c.fx_used = used
	return true


## Characters on \`side\`, other than the one in \`except\`, that pass the effect's clan filter.
func _cond_clan(e: Dictionary) -> Dictionary:
	var ce := e.duplicate()
	ce["clan"] = e.get("if_clan", e.get("clan", ""))
	return ce


func _fx_pool(side: String, e: Dictionary, except: int, standing_only := false) -> Array:
	var clan := str(e.get("clan", ""))
	return characters(side).filter(func(x):
		return x.slot != except and (clan == "" or x.card.get("clanTag") == clan) \
			and not (standing_only and x.card.downed))


## Cards of the condition's clan (if_clan; "" = any) among `cards`
func _of_if_clan(cards: Array, e: Dictionary) -> Array:
	var clan := str(e.get("if_clan", ""))
	return cards.filter(func(x): return clan == "" or x.get("clanTag") == clan)


## "For each": what effect `e` counts (per: allies | enemies | foe_downed | gutter | foe_gutter | hand;
## per_clan: only that clan's; per_kind: only that card type's (gang_member | hustle | ambush), for
## cards in a Gutter or hand; per_max: at most this many).
func _per_count(side: String, slot: int, e: Dictionary) -> int:
	var clan := str(e.get("per_clan", ""))
	var kind := str(e.get("per_kind", ""))
	var of_clan := func(x: Dictionary) -> bool: return (clan == "" or x.get("clanTag") == clan) and (kind == "" or x.get("cardType") == kind)
	var s: Dictionary = sides[side]
	var n := 0
	match str(e.get("per", "")):
		"allies":
			n = characters(side).filter(func(x): return x.slot != slot and of_clan.call(x.card)).size()
		"enemies":
			n = _enemy_chars(side).size()
		"foe_downed":
			n = _enemy_chars(side).filter(func(x): return x.card.downed).size()
		"gutter":
			n = s.gutter.filter(of_clan).size()
		"foe_gutter":
			n = 0
			for f in foes_of(side):
				n += sides[f].gutter.filter(of_clan).size()
		"hand":
			n = s.hand.filter(of_clan).size()
		"roll":   # the die just rolled (_luck_gate)
			n = maxi(1, _roll)
		"hustles_turn":   # Hustles you've played this turn
			n = _hustles_this_turn(side)
		"statused":
			n = _enemy_chars(side).filter(func(x): return _afflicted(x.card)).size()
		"lost_1000":
			n = maxi(0, int(s.get("max_morale", START_MORALE)) - int(s.morale)) / 1000
		_:
			return 1
	if e.get("per_max") != null:
		n = mini(n, int(e.per_max))
	return n


## Effect `e` with its numbers multiplied by its "for each" count.
func _scaled(side: String, slot: int, e: Dictionary) -> Dictionary:
	if str(e.get("per", "")) == "":
		return e
	var k := _per_count(side, slot, e)
	var out := e.duplicate()
	out.atk = int(e.get("atk", 0)) * k
	out.def = int(e.get("def", 0)) * k
	out.amount = int(e.get("amount", 1)) * k
	out.erase("per")
	return out


## Room for a card an effect puts onto the field: an empty lane, or a character to replace (_ask_replace).
func _room_for(side: String) -> bool:
	return _empty_lane(side) >= 0 or FRONT.any(func(l): return can_sacrifice(side, l))


## A card an effect puts onto the field (call, revive, token): in the first empty lane (place(lane)),
## or, the field full, the player may send one of their characters to the Gutter to make room (as
## deploying over one does) or keep them all (keep()). The CPU replaces its weakest character only
## for a stronger card. Same as _askReplace in DuelState.js.
func _ask_replace(side: String, c: Dictionary, card: Dictionary, place: Callable, keep: Callable) -> void:
	var lane := _empty_lane(side)
	if lane >= 0:
		place.call(lane)
		return
	var mine: Array = []
	for l in FRONT:
		if can_sacrifice(side, l):
			mine.append({"slot": l, "card": card_at(side, l)})
	if mine.is_empty():
		keep.call()
		return
	mine.sort_custom(func(a, b): return _attack_value(a.card) < _attack_value(b.card) \
		or (_attack_value(a.card) == _attack_value(b.card) and a.slot < b.slot))
	var opts: Array = []
	for x in mine:
		opts.append({"id": str(x.slot), "label": "REPLACE %s  (%d / %d)" % [str(x.card.name).to_upper(), int(x.card.attack), int(x.card.defense)],
			"side": side, "slot": x.slot})
	var no := {"id": "keep", "label": "KEEP THEM ALL"}
	var better := _attack_value(card) > _attack_value(mine[0].card)
	_ask(side, "replace", "Your field is full. Replace one of your characters with %s?" % card.name, card,
		opts + [no] if better else [no] + opts, func(choice: String) -> void:
			if winner != "":
				return
			var free := _empty_lane(side)
			if free >= 0:   # (a lane came free meanwhile)
				place.call(free)
				return
			var l := int(choice)
			if choice == "keep" or not (l in FRONT) or not can_sacrifice(side, l):
				keep.call()
				return
			var t: Dictionary = card_at(side, l)
			sides[side].field[l] = null
			var own := _owner_of(side, t)
			t.erase("charmed")
			t.downed = false
			t.mods = []
			_clear_status(t)
			if not t.get("token", false) or remains(t):   # (tokens vanish, unless REMAINS)
				sides[own].gutter.append(t)
			_emit("tribute", {"side": side, "slot": l, "card": t.duplicate(true), "for": card.duplicate(true), "replace": true})
			_effect(side, c, "%s: %s makes room for %s" % [c.name, t.name, card.name], NO_SLOT)
			place.call(l))


func _empty_lane(side: String) -> int:
	for l in FRONT:
		if sides[side].field[l] == null:
			return l
	return -1


## "Choose one": the player picks one of two effects (the CPU takes the first: one that has
## something to act on).
func _choose_fx(side: String, slot: int, c: Dictionary, opts: Array, vs: Dictionary) -> void:
	if opts.size() == 1:
		_do_fx(side, slot, c, opts[0], vs)
		return
	if not _fx_useful(side, slot, c, opts[0], vs) and _fx_useful(side, slot, c, opts[1], vs):
		opts = [opts[1], opts[0]]
	var options: Array = []
	for k in opts.size():
		var label := str(opts[k].get("label", ""))
		options.append({"id": str(k), "label": label.to_upper() if label != "" else str(opts[k].get("do", "")).to_upper()})
	_ask(side, "fx_choice", "%s: choose one" % c.name, c, options, func(choice: String):
		var k := int(choice)
		if k >= 0 and k < opts.size() and winner == "":
			_do_fx(side, _slot_of(side, c, slot), c, opts[k], vs))


## Whether an effect has anything to act on (one that affects characters needs one).
func _fx_useful(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary) -> bool:
	return fx_can(side, slot, c, e, vs)


func _fx_cond(side: String, slot: int, e: Dictionary, def) -> bool:
	var n := int(e.get("n", 1))
	var s: Dictionary = sides[side]
	match str(e.get("if", "")):
		"vs_def":
			return def != null and (def.get("position") == "def" or def.get("face_down", false) or def.get("downed", false))
		"vs_downed":
			return def != null and def.get("downed", false)
		"vs_atk":
			return def != null and def.get("position") == "atk" and not def.get("downed", false)
		# (if_clan: whose characters count; without it, the effect's clan as before)
		"allies":
			return _fx_pool(side, _cond_clan(e), slot).size() >= n
		"allies_le":
			return _fx_pool(side, _cond_clan(e), slot).size() <= n
		"alone":
			return characters(side).all(func(x): return x.slot == slot)
		"adjacent":
			return _fx_pool(side, _cond_clan(e), slot).any(func(x): return absi(x.slot - slot) == 1)
		"foe_downed":
			return _enemy_chars(side).any(func(x): return x.card.downed)
		"hand_le":
			return s.hand.size() <= n
		"morale_le":
			return s.morale <= n
		"foe_morale_le":
			return foes_of(side).any(func(f): return sides[f].morale <= n)
		"enemies_ge":
			return _enemy_chars(side).size() >= n
		"gutter_ge":
			return _of_if_clan(s.gutter, e).size() >= n
		"foe_gutter_ge":
			return foes_of(side).any(func(f): return sides[f].gutter.size() >= n)
		"leader_dormant":
			return s.leader_state == "dormant"
		"leader_awake":
			return s.leader_state == "awake"
		"foe_hand_le":
			return foes_of(side).any(func(f): return sides[f].hand.size() <= n)
		"foe_ambush":
			return foes_of(side).any(func(f): return BACK.any(func(b): return sides[f].field[b] != null))
		"authority_ge":
			return s.authority_max >= n
		"ally_downed":
			var clan := str(e.get("if_clan", ""))
			return characters(side).any(func(x): return x.slot != slot and x.card.downed 				and (clan == "" or x.card.get("clanTag") == clan))
		"hand_ge":
			return _of_if_clan(s.hand, e).size() >= n
		"self_def":
			var me = card_at(side, slot)
			return me != null and me.get("position") == "def"
		"self_atk":
			var me = card_at(side, slot)
			return me != null and me.get("position") == "atk" and not me.get("downed", false)
		"enemies_le":
			return _enemy_chars(side).size() <= n
		"turn_ge":
			return turn >= n
		"deck_le":
			return s.deck.size() <= n
		"foe_statused":
			return _enemy_chars(side).any(func(x): return _afflicted(x.card))
		"hustles_ge":
			return _hustles_this_turn(side) >= n
		"morale_behind":
			return foes_of(side).any(func(f): return sides[f].morale > s.morale)
		"morale_ahead":
			return not foes_of(side).is_empty() and foes_of(side).all(func(f): return sides[f].morale < s.morale)
	return true


## Run a card's effects for a trigger. \`def\` is the other card involved (the defender for
## attack / ko / down, the attacker for defend, the new ally for ally_deployed).
func _run_fx(side: String, slot: int, c: Dictionary, when: String, def = null, vs := {}) -> void:
	if def is Dictionary and when.ends_with("deployed"):   # (target "deployed": that character)
		vs = vs.duplicate()
		vs.deployed = def
	var list := _fx(c, when)
	var i := 0
	while i < list.size():
		var e: Dictionary = list[i]
		i += 1
		var k := i
		if winner != "":
			return
		# "Choose one" (or): this effect or the next; the player picks one whose condition holds
		var opts: Array = [e]
		if e.get("or", false) and i < list.size():
			opts.append(list[i])
			i += 1
		# when_clan: only when an ally of that clan is deployed (without it, the effect's clan as before)
		var wc := str(e.get("when_clan", e.get("clan", "")))
		if (when == "ally_deployed" or when == "dormant_ally_deployed") and wc != "" and (def == null or def.get("clanTag") != wc):
			continue
		var key := "%s%d" % [when, k]
		opts = opts.filter(func(o): return _fx_cond(side, slot, o, def))
		if opts.is_empty() or not _fx_count(c, key, e):
			continue
		if _fx_once(c, key, e):
			if int(e.get("times", 1)) > 1:
				c.fx_count.erase(key)   # start counting again
			if opts.size() > 1:
				_choose_fx(side, slot, c, opts, vs)
			else:
				_do_fx(side, slot, c, opts[0], vs)


## then: a follow-up effect that happens only if this one did something ("If you do, ...").
## Effects that wait on a choice (a target, a card to take) run it after the answer, and not on SKIP.
func _do_fx(side: String, slot: int, c: Dictionary, e: Dictionary, vs := {}) -> void:
	var w := _luck_wait
	if not w.is_empty() and w.uid == c.get("uid") and str(e.get("if_luck", "")) != "":   # ("If tails, ..." waits for the bet it follows)
		var ask: Dictionary = w.ask
		var cb: Callable = ask.cb
		ask.cb = func(answer) -> void:
			cb.call(answer)
			if winner == "":
				_do_fx(side, _slot_of(side, c, slot), c, e, vs)
		return
	if str(e.get("luck", "")) == "double":
		_ask_double(side, slot, c, e, vs)
		return
	if not _luck_gate(side, slot, c, e):
		return
	_do_fx_run(side, slot, c, e, vs)


## DOUBLE OR NOTHING (same as _askDouble in DuelState.js): the player chooses to bet (a coin; heads,
## the effect happens twice; tails, not at all) or to take it once, with no flip. The CPU bets when
## it has LOADED DICE to fall back on.
func _ask_double(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary) -> void:
	var s = sides.get(side)
	var loaded := false
	if s != null and int(s.get("loaded_turn", -1)) != turn:
		for x in characters(side):
			if not _passive(side, x.slot, x.card, "loaded").is_empty():
				loaded = true
	var bet := {"id": "double", "label": "DOUBLE OR NOTHING"}
	var once := {"id": "once", "label": "JUST ONCE"}
	var w := {"uid": c.get("uid")}
	w.ask = _ask(side, "double", "%s: double or nothing? Flip a coin: heads, it happens twice; tails, not at all. Or take it once." % c.name,
		c, [bet, once] if loaded else [once, bet], func(choice: String) -> void:
			if is_same(_luck_wait, w):
				_luck_wait = {}
			if winner != "":
				return
			var at := _slot_of(side, c, slot)
			if choice != "double":
				_luck_last = {}   # (no flip: no "If heads" or "If tails")
				_effect(side, c, "%s: no bet, it happens once" % c.name, at)
				_do_fx_run(side, at, c, e, vs)
				return
			if not _luck_gate(side, at, c, e):
				return
			_do_fx_run(side, at, c, e, vs)
			if winner == "":
				_do_fx_run(side, _slot_of(side, c, slot), c, e, vs))   # heads: twice
	_luck_wait = w


func _do_fx_run(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary) -> void:
	_do_fx_then(side, slot, c, e, vs)
	if e.get("negate", false):   # ("... and negate the attack": an Ambush)
		_negate(side, slot, c, vs)


## A sprung Ambush stops the attack (vs.ctx: the attack; nothing outside one).
func _negate(side: String, slot: int, c: Dictionary, vs: Dictionary) -> void:
	var actx = vs.get("ctx")
	if not (actx is Dictionary) or actx.get("negated", false):
		return
	actx.negated = true
	_effect(side, c, "%s negates the attack" % c.name, slot)


func _do_fx_then(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary) -> void:
	var then = e.get("then")
	if not (then is Dictionary):
		_do_fx_one(side, slot, c, e, vs)
		return
	var did := _did
	var asks: Array = _new_asks if _in_answer else _asks
	var queued := asks.size()
	var next := func() -> void:
		if winner == "":
			_do_fx(side, _slot_of(side, c, slot), c, then, vs)
	_do_fx_one(side, slot, c, e, vs)
	if _did > did:
		next.call()
	elif asks.size() > queued:
		var ask: Dictionary = asks[queued]
		var cb: Callable = ask.cb
		if ask.kind == "choose":
			ask.cb = func(answer) -> void:
				var before := _did
				cb.call(answer)
				if _did > before:
					next.call()
		else:
			ask.cb = func() -> void:
				var before := _did
				if cb.is_valid():
					cb.call()
				if _did > before:
					next.call()


func _do_fx_one(side: String, slot: int, c: Dictionary, e: Dictionary, vs := {}) -> void:
	var s: Dictionary = sides[side]
	if str(e.get("per", "")) != "":   # "for each ...": nothing to count, nothing happens
		if _per_count(side, slot, e) <= 0:
			return
		e = _scaled(side, slot, e)
	var n: int = maxi(1, int(e.get("amount", 1)))
	match str(e.get("do", "")):
		"buff":
			var mod := {"atk": int(e.get("atk", 0)), "def": int(e.get("def", 0)), "until_turn": _until(e)}
			if is_equip(c):   # (an Equip's changes leave with it: _recalc)
				mod.equip = c.uid
			var label := _stat_text(mod)
			var fn := func(x: Dictionary) -> String:
				x.card.mods.append(mod.duplicate())
				return "%s: %s" % [x.card.name, label]
			_fx_apply(side, slot, c, e, vs, "any", label, fn, "%s: %s to %%s" % [c.name, label])
		"down":
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				return ("%s Downs %s: it's BRITTLE, so it's KO'd" if _go_down(x.side, x.slot, x.card) == "ko" else "%s Downs %s") % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "standing", "DOWN", fn, "%s Downs %%s" % c.name)
		"ko":
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_ko(x.side, x.slot)
				return "%s KOs %s" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "any", "KO", fn, "%s KOs %%s" % c.name)
		"ready":
			# Characters that already attacked this turn may attack again (at most once more each turn)
			var fn := func(x: Dictionary) -> String:
				x.card.has_attacked = false
				x.card.again_turn = turn
				return "%s may attack again this turn" % x.card.name
			_fx_apply(side, slot, c, e, vs, "spent", "attack again", fn, "%s: %%s may attack again this turn" % c.name)
		"stand":
			var fn := func(x: Dictionary) -> String:
				x.card.downed = false
				x.card.erase("down_turns")
				_emit("stand", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s stands back up" % x.card.name
			_fx_apply(side, slot, c, e, vs, "downed", "stand up", fn, "%s: %%s stand back up" % c.name)
		"bounce":
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_bounce(x.side, x.slot)
				return "%s sends %s back to the hand" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "any", "send back to the hand", fn, "%s sends %%s back to the hand" % c.name)
		"topdeck":   # back on top of its owner's deck: they draw it again
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_topdeck(x.side, x.slot)
				return "%s puts %s on top of its owner's deck" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "any", "put on top of the deck", fn, "%s puts %%s on top of the deck" % c.name)
		"exile":   # gone for good: not to the Gutter, so nothing can bring it back
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_exile(x.side, x.slot)
				return "%s EXILES %s" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "any", "EXILE", fn, "%s EXILES %%s" % c.name)
		"set_stats":   # its ATK and / or DEF become these numbers: earlier changes stop counting, later ones still do
			var mod := {"until_turn": _until(e)}
			if is_equip(c):
				mod.equip = c.uid
			if e.get("atk") != null and str(e.atk) != "":
				mod.set_atk = maxi(0, int(e.atk))
			if e.get("def") != null and str(e.def) != "":
				mod.set_def = maxi(0, int(e.def))
			var label := _set_text(mod)
			var fn := func(x: Dictionary) -> String:
				x.card.mods.append(mod.duplicate())
				_recalc()
				return "%s: %s" % [x.card.name, label]
			_fx_apply(side, slot, c, e, vs, "any", label, fn, "%s: %s for %%s" % [c.name, label])
		"swap":   # ATK and DEF trade places (until the end of the turn, the next, or for good)
			var until := _until(e)
			var fn := func(x: Dictionary) -> String:
				x.card.mods.append({"swap": true, "until_turn": until, "equip": c.uid} if is_equip(c) else {"swap": true, "until_turn": until})
				return "%s: ATK and DEF swapped" % x.card.name
			_fx_apply(side, slot, c, e, vs, "any", "swap ATK and DEF", fn, "%s swaps the ATK and DEF of %%s" % c.name)
		"cleanse":   # CLEANSE: its statuses are gone (STASIS, FREEZE, STUN, SUPPRESS, SILENCE, POISON, BURN, BLEED, BOUNTY)
			var fn := func(x: Dictionary) -> String:
				var kept = x.card.get("undead_given", false)
				_clear_status(x.card)
				if kept:
					x.card.undead_given = true
				x.card.erase("stun_until")
				_emit("cleanse", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s is cleansed" % x.card.name
			_fx_apply(side, slot, c, e, vs, "statused", "cleanse", fn, "%s cleanses %%s" % c.name)
		"rewind":   # REWIND: its ATK / DEF changes are undone (back to its printed stats)
			var fn := func(x: Dictionary) -> String:
				x.card.mods = []
				_recalc()
				_emit("rewind", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s is rewound to its printed ATK and DEF" % x.card.name
			_fx_apply(side, slot, c, e, vs, "changed", "rewind", fn, "%s rewinds %%s" % c.name)
		"negate":   # an Ambush: the attack stops (older cards; now an option on any effect: negate)
			_negate(side, slot, c, vs)
		"jam":   # JAM: the opponent can't spring Ambushes until the end of their next turn
			for foe in foes_of(side):
				sides[foe].jam_until = _owner_next_turn(foe)
				_emit("jam", {"side": foe, "until": sides[foe].jam_until})
			_effect(side, c, "%s JAMS your opponent's Ambushes" % c.name, slot)
		"barricade":   # BARRICADE N: the next N Morale damage before your next turn is prevented
			s.barricade = int(s.get("barricade", 0)) + n
			_emit("barricade", {"side": side, "amount": s.barricade})
			_effect(side, c, "%s raises a BARRICADE of %d" % [c.name, n], slot)
		"bounty":   # BOUNTY X: when it's KO'd, whoever put the bounty on it draws X
			var fn := func(x: Dictionary) -> String:
				x.card.bounty = {"by": side, "n": n}
				return "%s puts a BOUNTY of %d on %s" % [c.name, n, x.card.name]
			_fx_apply(side, slot, c, e, vs, "any", "put a BOUNTY on", fn, "%s puts a BOUNTY of %d on %%s" % [c.name, n])
		"force_def":
			var fn := func(x: Dictionary) -> String:
				x.card.position = "def"
				x.card.position_turn = turn
				_emit("position", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s forces %s into DEF" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "attackers", "force into DEF", fn, "%s forces %%s into DEF" % c.name)
		"force_atk":
			# Pulled out of cover: a face-up character in DEF switches to ATK
			var fn := func(x: Dictionary) -> String:
				x.card.position = "atk"
				x.card.position_turn = turn
				_emit("position", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s forces %s into ATK" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "defenders", "force into ATK", fn, "%s forces %%s into ATK" % c.name)
		"stun":
			var fn := func(x: Dictionary) -> String:
				x.card.stun_until = _owner_next_turn(x.side)
				return "%s stuns %s: it can't attack next turn" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "any", "stun", fn, "%s stuns %%s" % c.name)
		"shield":
			var fn := func(x: Dictionary) -> String:
				x.card.shield = true
				return "%s is shielded from the next defeat" % x.card.name
			_fx_apply(side, slot, c, e, vs, "any", "shield", fn, "%s shields %%s" % c.name)
		"influence":
			# A Dormant leader regains Influence, up to what it started with
			var l = s.leader
			if s.leader_state != "dormant" or l == null:
				return
			var gain: int = mini(n, int(l.get("influence_max", l.influence)) - int(l.influence))
			if gain <= 0:
				return
			l.influence += gain
			_effect(side, c, "%s: %s regains %d Influence" % [c.name, l.name, gain], slot)
			_emit("leader_heal", {"side": side, "amount": gain, "influence": l.influence})
		"ramp":
			# More Authority every turn from now on (and this turn)
			var before: int = s.authority_max
			s.authority_max = mini(MAX_AUTHORITY, s.authority_max + n)
			var d: int = s.authority_max - before
			if d <= 0:
				return
			s.authority += d
			_effect(side, c, "%s: +%d max Authority" % [c.name, d], slot)
			_emit("authority", {"side": side, "value": s.authority, "max": s.authority_max, "delta": d})
		"silence":
			var until_turn: int = FOREVER if str(e.get("until", "turn")) == "forever" else turn + (_round_span() if str(e.get("until", "turn")) == "next_turn" else 0)
			var fn := func(x: Dictionary) -> String:
				x.card.silence_until = until_turn
				_recalc()
				return "%s silences %s: its effects stop" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "any", "silence", fn, "%s silences %%s" % c.name)
		"draw":
			_effect(side, c, "%s: draw %d" % [c.name, n], slot)
			for i in n:
				_draw(side)
		"loot":   # draw N, then discard discard_n (as many as drawn unless set; 0: none)
			var d: int = maxi(0, int(e.get("discard_n", n)))
			_effect(side, c, "%s: draw %d, then discard %d" % [c.name, n, d], slot)
			for i in n:
				if winner != "":
					break
				_draw(side)
			var k: int = mini(d, s.hand.size())
			if k > 0 and winner == "":
				_ask_discard(side, k, Callable(), "%s: loot" % c.name)
		"search":
			var found := _fx_take(side, c, e, s.deck, "%s: choose a card to add to your hand" % c.name, func(card: Dictionary) -> bool:
				s.hand.append(card)
				# What it found stays hidden from the other players, unless the card says to reveal it
				_effect(side, c, "%s: searches the deck for %s" % [c.name, card.name], slot,
					"" if e.get("reveal") == true else "%s: searches the deck for a card" % c.name)
				_emit("draw", {"side": side, "card": card.duplicate(true), "opening": false})
				return true, _shuffle_deck.bind(side))
			if not found:
				_emit("effect", {"side": side, "card": c.duplicate(true), "text": "%s: nothing to find in the deck" % c.name, "slot": slot})   # (not something done)
		"revive", "call":
			# A character from your Gutter (revive) or deck (call) onto the field, in the first
			# empty lane, in ATK (the field full: the player may replace one of their characters)
			if not _room_for(side):
				return
			var from_deck := str(e.get("do", "")) == "call"
			# (from: "foe": a character from the opponent's Gutter, which fights for you from now on)
			var robbed := ""
			if not from_deck and e.get("from", "") == "foe":
				for f in foes_of(side):
					if sides[f].gutter.any(func(x): return _fx_kind_ok(x, e)):
						robbed = f
						break
				if robbed == "":
					return
			var pile: Array = s.deck if from_deck else (sides[robbed].gutter if robbed != "" else s.gutter)
			var place := func(card: Dictionary, lane: int) -> bool:
				card.downed = false
				card.mods = []
				_clear_status(card)
				card.erase("fx_count")
				if not from_deck:
					var rev := {"side": side, "card": card.duplicate(true)}
					if robbed != "":
						rev.from_side = robbed
					_emit("recover", rev)
				card.erase("rise_turn")   # (taken before it could rise)
				card.position = "def" if e.get("position", "") == "def" else "atk"   # (position: "def": it comes in DEF)
				card.face_down = false
				card.has_attacked = false
				card.deployed_turn = turn
				s.field[lane] = card
				var ev := {"side": side, "slot": lane, "card": card.duplicate(true)}
				if from_deck:
					ev.from = "deck"
				_emit("summon", ev)
				_effect(side, c, ("%s: %s is called in" if from_deck else ("%s raises %s from the enemy's Gutter" if robbed != "" else "%s: %s is back on the street")) % [c.name, card.name], slot)
				_recalc()
				if is_same(card_at(side, lane), card):
					_on_deploy(side, lane, card)   # (it counts as deployed)
				return true
			_fx_take(side, c, e, pile, "%s: choose a character to %s" % [c.name, "call in" if from_deck else "bring back"], func(card: Dictionary, cont: Callable) -> Variant:
				var free := _empty_lane(side)
				if free >= 0:
					return place.call(card, free)
				_ask_replace(side, c, card, func(l: int) -> void: cont.call(place.call(card, l)), func() -> void:
					pile.append(card)
					cont.call(false))
				return "wait", _shuffle_deck.bind(side) if from_deck else Callable())
		"token":
			# Copies of a token card (Card Forge: marked Token, never in packs or decks) in the
			# first empty lanes, in ATK (the field full: the player may replace characters for
			# them). They vanish when they leave the field.
			var spec := str(e.get("token", ""))
			if spec == "" or CardDB.get_card(spec).is_empty():
				return
			var made := [0]
			var one := func(lane: int) -> void:
				var t := make_card(spec)
				t.token = true
				t.deployed_turn = turn
				s.field[lane] = t
				_emit("summon", {"side": side, "slot": lane, "card": t.duplicate(true), "from": "token"})
				made[0] += 1
				_recalc()
				if is_same(card_at(side, lane), t):
					_on_deploy(side, lane, t)   # (it counts as deployed)
			var finish := func() -> void:
				if made[0] > 0:
					_effect(side, c, "%s: %d %s token%s join%s the fight" % [c.name, made[0], CardDB.get_card(spec).get("name", "token"),
						"" if made[0] == 1 else "s", "s" if made[0] == 1 else ""], slot)
					_recalc()
			var more := func(k: int, again: Callable) -> void:
				while k > 0 and _empty_lane(side) >= 0:
					one.call(_empty_lane(side))
					k -= 1
				if k <= 0 or winner != "":
					finish.call()
					return
				var spec_card: Dictionary = CardDB.get_card(spec).duplicate(true)
				spec_card.token = true
				_ask_replace(side, c, spec_card, func(l: int) -> void:
					one.call(l)
					again.call(k - 1, again), finish)
			more.call(mini(n, FRONT.size()), more)
		"break_ambush", "shatter", "wreck":
			# The opponent's face-down cards in the back row (break_ambush), its face-up Continuous and
			# Equip cards (shatter), or either (wreck), left to right
			var kind := str(e.get("do", ""))
			var hit := func(a) -> bool: return a != null and (kind == "wreck" or bool(a.get("face_down", false)) == (kind == "break_ambush"))
			_with_foe(side, c, vs, func(f): return BACK.any(func(b): return hit.call(sides[f].field[b])), func(foe: String):
				var k := n
				for b in BACK:
					var a = sides[foe].field[b]
					if k <= 0 or not hit.call(a):
						continue
					sides[foe].field[b] = null
					sides[foe].gutter.append(a)
					var up: bool = not a.get("face_down", false)
					if up:
						a.erase("equipped_to")
					_emit("ko", {"side": foe, "slot": b, "card": a.duplicate(true)})
					_effect(side, c, ("%s: destroys %s" % [c.name, a.name]) if up else ("%s: destroys a face-down card" % c.name), slot)
					k -= 1
				_recalc())   # (what a face-up one gave is gone)
		"recover":
			var back := _fx_take(side, c, e, s.gutter, "%s: choose a card to return to your hand" % c.name, func(card: Dictionary) -> bool:
				card.downed = false
				card.mods = []
				s.hand.append(card)
				_effect(side, c, "%s: %s returns to the hand" % [c.name, card.name], slot)
				_emit("recover", {"side": side, "card": card.duplicate(true)})
				return true)
			if back:
				return
		"discard":
			_with_foe(side, c, vs, func(f): return not sides[f].hand.is_empty(), func(foe: String):
				var k: int = mini(n, sides[foe].hand.size())
				_effect(side, c, "%s: your opponent discards %d" % [c.name, k], slot)
				_ask_discard(foe, k, Callable(), "%s makes you discard" % c.name))
		"mill":
			_with_foe(side, c, vs, func(f): return not sides[f].deck.is_empty(), func(foe: String):
				var fd: Array = sides[foe].deck
				var lost := mini(n, fd.size())
				_effect(side, c, "%s: your opponent loses %d card%s from the deck" % [c.name, lost, "" if lost == 1 else "s"], slot)
				for i in lost:
					var milled: Dictionary = fd.pop_back()
					sides[foe].gutter.append(milled)
					_emit("mill", {"side": foe, "card": milled.duplicate(true)})
					_to_gutter_fx(foe, milled))
		"mill_self":   # the top N cards of your own deck go to your Gutter (fills it on purpose)
			var lost := mini(n, s.deck.size())
			if lost > 0:
				_effect(side, c, "%s: the top %d card%s of your deck go%s to your Gutter" % [c.name, lost, "" if lost == 1 else "s", "es" if lost == 1 else ""], slot)
				for i in lost:
					if s.deck.is_empty():   # (a milled card's own effect may have drawn the rest)
						break
					var milled: Dictionary = s.deck.pop_back()
					s.gutter.append(milled)
					_emit("mill", {"side": side, "card": milled.duplicate(true)})
					_to_gutter_fx(side, milled)
		"entomb":   # a card of your choice (filters like search) from your deck to your Gutter
			var sent := _fx_take(side, c, e, s.deck, "%s: choose a card to send to your Gutter" % c.name, func(card: Dictionary) -> bool:
				s.gutter.append(card)
				_effect(side, c, "%s: sends %s from the deck to the Gutter" % [c.name, card.name], slot)
				_emit("mill", {"side": side, "card": card.duplicate(true)})
				_to_gutter_fx(side, card)
				return true, _shuffle_deck.bind(side))
			if not sent:
				_emit("effect", {"side": side, "card": c.duplicate(true), "text": "%s: nothing in the deck to send" % c.name, "slot": slot})   # (not something done)
		"tax":   # TAX N: the opponent gets N less Authority on their next turn
			_with_foe(side, c, vs, func(_f): return true, func(foe: String):
				sides[foe].tax = int(sides[foe].get("tax", 0)) + n
				_effect(side, c, "%s: TAX %d: your opponent gets %d less Authority next turn" % [c.name, n, n], slot))
		"reshuffle":   # up to N cards from your Gutter (the oldest; not tokens) shuffled back into your deck
			var back: Array = s.gutter.filter(func(x): return not x.get("token", false)).slice(0, n)
			if not back.is_empty():
				for x in back:
					s.gutter.erase(x)
					x.mods = []
					x.downed = false
					_clear_status(x)
					x.erase("fx_count")
					x.erase("rise_turn")
					x.has_attacked = false
					x.face_down = false
					s.deck.append(x)
				_effect(side, c, "%s: %d card%s from your Gutter shuffled back into your deck" % [c.name, back.size(), "" if back.size() == 1 else "s"], slot)
				_emit("recycle", {"side": side, "count": back.size()})
				_shuffle_deck(side)
		"tribute_damage":   # a Heavy: the ATK of the characters it sacrificed, as Morale damage
			var dmg := int(c.get("tribute_atk", 0))
			if dmg > 0:
				_with_foe(side, c, vs, func(_f): return true, func(foe: String):
					_effect(side, c, "%s: %d Morale damage (the ATK it sacrificed)" % [c.name, dmg], slot)
					_damage(foe, dmg))
		"give_undead":   # UNDEAD for a character: the next time it's KO'd, it rises at the end of the turn
			var fn := func(x: Dictionary) -> String:
				x.card.undead_given = true
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "undead", "card": x.card.duplicate(true)})
				return "%s is UNDEAD: it will rise once after it's KO'd" % x.card.name
			_fx_apply(side, slot, c, e, vs, "unrisen", "UNDEAD", fn, "%s makes %%s UNDEAD" % c.name)
		"exile_gutter":   # the newest cards in the opponent's Gutter, out of the game
			_with_foe(side, c, vs, func(f): return not sides[f].gutter.is_empty(), func(foe: String):
				var g: Array = sides[foe].gutter
				var gone: Array = g.slice(maxi(0, g.size() - n))
				_exile_gutter(foe, gone)
				_effect(side, c, "%s EXILES %d card%s from the enemy's Gutter" % [c.name, gone.size(), "" if gone.size() == 1 else "s"], slot))
		"absorb":   # tribute one of your characters (or the one just deployed): this card gains its ATK and DEF
			if card_at(side, slot) != c:
				return
			var take := func(x: Dictionary) -> String:
				if card_at(side, slot) != c or card_at(x.side, x.slot) != x.card:
					return "%s can't tribute it now" % c.name
				var atk := int(x.card.attack)
				var df := int(x.card.defense)
				var nm: String = x.card.name
				_ko(x.side, x.slot)
				c.mods.append({"atk": atk, "def": df, "until_turn": FOREVER})
				_recalc()
				_emit("absorb", {"side": side, "slot": slot, "from_slot": x.slot, "atk": atk, "def": df, "card": c.duplicate(true)})
				return "%s tributes %s: +%d ATK and +%d DEF" % [c.name, nm, atk, df]
			if str(e.get("target", "")) == "deployed":   # the player may say no
				var found: Array = _fx_targets(side, slot, c, e, vs, "any").filter(func(t): return t.side == side and not is_same(t.card, c))
				if found.is_empty():
					return
				var x: Dictionary = found[0]
				var worth: bool = x.card.get("token", false) or int(x.card.attack) + int(x.card.defense) <= int(c.attack) + int(c.defense)
				var yes := {"id": "yes", "label": "TRIBUTE %s" % str(x.card.name).to_upper()}
				var no := {"id": "no", "label": "KEEP IT"}
				_ask(side, "absorb", "%s: tribute %s? %s gains its ATK and DEF" % [c.name, x.card.name, c.name], x.card, [yes, no] if worth else [no, yes], func(choice):
					if choice == "yes" and winner == "":
						_effect(side, c, take.call(x), slot))
				return
			_fx_apply(side, slot, c, e, vs, "absorbable", "tribute", take, "%s tributes %%s" % c.name)
		"promote_ally":   # PROMOTE one (or all) of your Strivers
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_promote(x.side, x.slot, c.name)
				return "%s PROMOTES %s" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "promotable", "PROMOTE", fn, "%s PROMOTES %%s" % c.name)
		"charm":   # CHARM: take control of an enemy character until the end of the turn
			var fn := func(x: Dictionary) -> String:
				var lane := _empty_lane(side)
				if lane < 0:
					return "%s resists the CHARM (no room)" % x.card.name
				sides[x.side].field[x.slot] = null
				x.card.charmed = {"owner": x.side, "slot": x.slot, "until": turn}
				x.card.has_attacked = false
				x.card.erase("rest_turn")
				sides[side].field[lane] = x.card
				_emit("charm", {"side": x.side, "slot": x.slot, "to_side": side, "to_slot": lane, "card": x.card.duplicate(true)})
				_recalc()
				return "%s CHARMS %s: it fights for %s this turn" % [c.name, x.card.name, "its charmer" if side == active else "the other side"]
			_fx_apply(side, slot, c, e, vs, "charmable", "CHARM", fn, "%s CHARMS %%s" % c.name)
		"damage":
			if e.get("to", "") == "self":   # the card's own player loses it (a risk or a price; a BARRICADE doesn't stop it)
				_effect(side, c, "%s: you lose %d Morale" % [c.name, n], slot)
				_damage(side, n, true)
				return
			_with_foe(side, c, vs, func(_f): return true, func(foe: String):
				_effect(side, c, "%s: %d Morale damage" % [c.name, n], slot)
				_damage(foe, n))
		"heal":
			_heal(side, c, n, slot)
		"drain":
			_with_foe(side, c, vs, func(_f): return true, func(foe: String):
				_effect(side, c, "%s drains %d Morale" % [c.name, n], slot)
				_damage(foe, n)
				if winner == "":
					_heal(side, c, n, slot))
		"authority":
			s.authority += n
			_effect(side, c, "%s: +%d Authority this turn" % [c.name, n], slot)
			_emit("authority", {"side": side, "value": s.authority, "max": s.authority_max, "delta": n})
		"promote":
			if card_at(side, slot) == c:
				_promote(side, slot, c.name)
		"attack_again":
			# At most one extra attack per card each turn, so no trigger can attack forever
			if card_at(side, slot) == c and c.has_attacked and int(c.get("again_turn", 0)) != turn:
				c.has_attacked = false
				c.again_turn = turn
				_effect(side, c, "%s may attack again this turn" % c.name, slot)
		"poison", "burn":
			var kind := str(e.get("do", ""))
			var fn := func(x: Dictionary) -> String:
				var cur: Dictionary = x.card.get(kind, {})
				x.card[kind] = {"amt": maxi(n, int(cur.get("amt", 0))), "left": STATUS_TICKS}
				_emit("status", {"side": x.side, "slot": x.slot, "kind": kind, "card": x.card.duplicate(true)})
				if kind == "poison":
					return "%s is POISONED: -%d ATK each turn" % [x.card.name, n]
				return "%s is BURNING: its owner loses %d Morale each turn" % [x.card.name, n]
			_fx_apply(side, slot, c, e, vs, "any", kind.to_upper(), fn,
				"%s %s %%s" % [c.name, "poisons" if kind == "poison" else "burns"])
		"bleed":
			var fn := func(x: Dictionary) -> String:
				x.card.bleed = maxi(n, int(x.card.get("bleed", 0)))
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "bleed", "card": x.card.duplicate(true)})
				return "%s is BLEEDING: -%d ATK / DEF after every brawl" % [x.card.name, n]
			_fx_apply(side, slot, c, e, vs, "any", "BLEED", fn, "%s makes %%s bleed" % c.name)
		"shock":
			var fn := func(x: Dictionary) -> String:
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "shock", "card": x.card.duplicate(true)})
				if not x.card.downed and n >= int(x.card.get("defense", 0)) and not _stays_up(x.side, x.slot, x.card):
					var name: String = x.card.name
					return ("%s SHOCKS %s: it's BRITTLE, so it's KO'd" if _go_down(x.side, x.slot, x.card) == "ko" else "%s SHOCKS %s: it goes Down") % [c.name, name]
				x.card.mods.append({"atk": 0, "def": -n, "until_turn": turn})
				_recalc()
				return "%s SHOCKS %s: -%d DEF this turn" % [c.name, x.card.name, n]
			_fx_apply(side, slot, c, e, vs, "any", "SHOCK", fn, "%s shocks %%s" % c.name)
		"suppress":
			# SUPPRESS X (Militia): pinned down through its owner's next turn: -X ATK and it can't attack
			var fn := func(x: Dictionary) -> String:
				var until_turn := _owner_next_turn(x.side)
				x.card.suppress_until = until_turn
				x.card.mods.append({"atk": -n, "def": 0, "until_turn": until_turn})
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "suppress", "card": x.card.duplicate(true)})
				_recalc()
				return "%s is SUPPRESSED: -%d ATK and it can't attack through its owner's next turn" % [x.card.name, n]
			_fx_apply(side, slot, c, e, vs, "any", "SUPPRESS", fn, "%s suppresses %%s" % c.name)
		"freeze":
			var fn := func(x: Dictionary) -> String:
				x.card.freeze_until = _owner_next_turn(x.side)
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "freeze", "card": x.card.duplicate(true)})
				if x.card.position != "def":
					x.card.position = "def"
					x.card.position_turn = turn
					_emit("position", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s is FROZEN in DEF through its owner's next turn" % x.card.name
			_fx_apply(side, slot, c, e, vs, "any", "FREEZE", fn, "%s freezes %%s" % c.name)
		"stasis":
			var fn := func(x: Dictionary) -> String:
				x.card.stasis_until = _owner_next_turn(x.side)
				_emit("status", {"side": x.side, "slot": x.slot, "kind": "stasis", "card": x.card.duplicate(true)})
				return "%s is in STASIS until its owner's next turn ends" % x.card.name
			_fx_apply(side, slot, c, e, vs, "any", "STASIS", fn, "%s puts %%s in STASIS" % c.name)


## The last turn a change lasts: this turn, through the next one, or (forever) while the card stays
## on the field (its mods are cleared when it leaves).
func _until(e: Dictionary) -> int:
	match str(e.get("until", "turn")):
		"next_turn":
			return turn + _round_span()
		"forever":
			return FOREVER
	return turn


## The last turn of "through its owner's next turn" for a character on `side` (two players: the
## active one's is 2 away, the other's 1).
func _owner_next_turn(side: String) -> int:
	if side == active:
		return turn + maxi(2, _alive().size())
	var d := 1
	var s := _next_seat(active)
	while s != side and d < seats.size():
		s = _next_seat(s)
		d += 1
	return turn + d


func _clear_status(c: Dictionary) -> void:
	for k in STATUS_KEYS:
		c.erase(k)
	c.erase("undead_given")


## Cards out of a side's Gutter and out of the game (Card Forge: exile_gutter).
func _exile_gutter(side: String, cards: Array) -> void:
	if cards.is_empty():
		return
	var s: Dictionary = sides[side]
	for g in cards:
		var i: int = s.gutter.find(g)
		if i >= 0:
			s.gutter.remove_at(i)
		g.erase("rise_turn")   # (an UNDEAD card exiled doesn't rise)
	_emit("gutter_exile", {"side": side, "cards": cards.map(func(g): return g.duplicate(true))})


## POISON and BURN tick at the start of their owner's turn.
func _status_ticks(side: String) -> void:
	for e in characters(side):
		var c: Dictionary = e.card
		for kind in ["poison", "burn"]:
			if winner != "" or not c.has(kind):
				continue
			var st: Dictionary = c[kind]
			var amt := int(st.amt)
			st.left = int(st.left) - 1
			if int(st.left) <= 0:
				c.erase(kind)
			_emit("status_tick", {"side": side, "slot": e.slot, "kind": kind, "amount": amt, "card": c.duplicate(true)})
			if kind == "poison":
				c.mods.append({"atk": -amt, "def": 0, "until_turn": FOREVER})
			else:
				_damage(side, amt)


## Apply a targeted effect. \`pool_kind\`: any | standing | downed | attackers (in ATK, standing).
## \`fn\` changes one character and returns its callout; \`all_text\` has a %s for "N enemies" etc.
func _fx_apply(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary, pool_kind: String,
		what: String, fn: Callable, all_text: String) -> void:
	var target := str(e.get("target", "self"))
	var entries := _fx_targets(side, slot, c, e, vs, pool_kind)
	if (target == "ally" or target == "enemy") and not _equipped_entry(c).is_empty():   # an Equip: its own character, no choice
		for x in entries:
			_effect(side, c, fn.call(x), slot)
	elif target == "ally" or target == "enemy":
		var best_first := func(a: Dictionary, b: Dictionary) -> bool:
			var va := _target_value(side, e, a)
			var vb := _target_value(side, e, b)
			if va != vb:
				return va > vb
			var sa := seats.find(a.side)
			var sb := seats.find(b.side)
			return sa < sb or (sa == sb and a.slot < b.slot)
		entries.sort_custom(best_first)
		var on := side
		if target != "ally":
			on = foes_of(side)[0] if not foes_of(side).is_empty() else side
		var cb := func(x: Dictionary): _effect(side, c, fn.call(x), slot)
		_ask_target(side, "fx", "%s: choose %s (%s)" % [c.name, "an ally" if target == "ally" else "an enemy", what], c,
			entries, on, cb, true)
	elif target == "allies" or target == "enemies" or target == "all":
		var count := 0
		for x in entries:   # (one a chained trigger already removed is skipped)
			if winner != "" or not is_same(card_at(x.side, x.slot), x.card):
				continue
			fn.call(x)
			count += 1
		if count > 0:
			var who := ("%d of your characters" % count) if target == "allies" \
				else ("%d character%s" % [count, "" if count == 1 else "s"]) if target == "all" \
				else ("%d enem%s" % [count, "y" if count == 1 else "ies"])
			_effect(side, c, all_text % who, slot)
	else:
		for x in entries:
			_effect(side, c, fn.call(x), slot)


## The characters effect `e` of card `c` would affect ({side, slot, card}), before choosing one.
## pool_kind: any | standing | downed | attackers (in ATK, standing) | spent (attacked this turn)
## An effect's "only ones ..." limit: statused, def, atk, downed, standing
func _only_fits(c: Dictionary, only: String) -> bool:
	match only:
		"statused":
			return _afflicted(c)
		"def":
			return c.position == "def" and not c.downed
		"atk":
			return c.position == "atk" and not c.downed
		"downed":
			return c.downed
		"standing":
			return not c.downed
	return true


## The character an Equip is on, as {side, slot, card}; {} for anything else.
func _equipped_entry(c) -> Dictionary:
	if not c is Dictionary or str(c.get("subtype", "")) != "equip" or c.get("equipped_to") == null:
		return {}
	for s in sides:
		for x in characters(s):
			if int(x.card.get("uid", -1)) == int(c.equipped_to):
				return {"side": s, "slot": x.slot, "card": x.card}
	return {}


func _fx_targets(side: String, slot: int, c: Dictionary, e: Dictionary, vs: Dictionary, pool_kind: String) -> Array:
	var target := str(e.get("target", "self"))
	var only := str(e.get("only", ""))
	var pick := func(x) -> bool:
		# "only ones with a status / in DEF position / ...": the card's own limit, on top of the action's
		if only != "" and not _only_fits(x.card, only):
			return false
		match pool_kind:
			"standing":
				return not x.card.downed
			"downed":
				return x.card.downed
			"attackers":
				return x.card.position == "atk" and not x.card.downed
			"defenders":
				return x.card.position == "def" and not x.card.downed and not x.card.get("face_down", false) and not frozen(x.card)
			"spent":
				return x.card.has_attacked and not x.card.downed and int(x.card.get("again_turn", 0)) != turn
			"statused":
				return _afflicted(x.card)
			"promotable":
				return x.card.get("subtype") == "striver" and _next_in_hideout(x.side, x.card) and not sides[x.side].promoted.has(x.slot) \
					and not x.card.downed and not (x.card.get("charmed") is Dictionary)
			"charmable":
				return x.card.get("cardType") != "leader" and not (x.card.get("charmed") is Dictionary)
			"absorbable":
				return x.card.get("cardType") != "leader" and not is_same(x.card, c)
			"unrisen":
				return not x.card.get("token", false) and not x.card.get("risen", false) and not x.card.get("undead_given", false)
			"changed":   # REWIND helps: an enemy's net gains, your character's net losses
				var net := 0
				for m in x.card.get("mods", []):
					net += int(m.get("atk", 0)) + int(m.get("def", 0))
				return net < 0 if x.side == side else net > 0
		return true
	var entries: Array = []
	var worn := _equipped_entry(c) if target in ["self", "ally", "enemy"] else {}
	if not worn.is_empty():   # an Equip's "this card" / "one ally" / "one enemy" is the character it's on
		entries = [worn]
	else:
		match target:
			"self":
				if card_at(side, slot) == c:
					entries = [{"side": side, "slot": slot, "card": c}]
			"attacker":
				if not vs.is_empty() and card_at(vs.side, vs.slot) == vs.card:
					entries = [{"side": vs.side, "slot": vs.slot, "card": vs.card}]
			"attacked":   # the character being attacked (Ambushes, "when another of your characters is attacked")
				var a := {}
				if vs.has("attacked"):
					a = vs.attacked
				elif vs.has("ctx"):
					a = {"side": vs.ctx.foe, "slot": vs.ctx.target, "card": card_at(vs.ctx.foe, vs.ctx.target)}
				if not a.is_empty() and a.card != null and card_at(a.side, a.slot) == a.card:
					entries = [{"side": a.side, "slot": a.slot, "card": a.card}]
			"deployed":   # "that character": the one just deployed (deploy triggers)
				if vs.get("deployed") is Dictionary:
					for s2 in sides:
						for l in FRONT:
							if is_same(sides[s2].field[l], vs.deployed):
								entries = [{"side": s2, "slot": l, "card": vs.deployed}]
			"ally", "allies":
				entries = _fx_pool(side, e, slot).map(func(x): return {"side": side, "slot": x.slot, "card": x.card})
			"enemy", "enemies":
				for foe in foes_of(side):
					entries.append_array(_fx_pool(foe, e, -99).map(func(x): return {"side": foe, "slot": x.slot, "card": x.card}))
			"neighbors":   # the allies in the lanes next to this card
				if slot in FRONT and is_same(card_at(side, slot), c):
					entries = _fx_pool(side, e, slot).filter(func(x): return absi(x.slot - slot) == 1).map(func(x): return {"side": side, "slot": x.slot, "card": x.card})
			"opposite":   # the enemy across the table from it (your lane 1 faces their lane 5)
				if slot in FRONT and is_same(card_at(side, slot), c):
					for foe in foes_of(side):
						var t = card_at(foe, 4 - slot)
						if t != null and _fx_pool(foe, e, -99).any(func(x): return is_same(x.card, t)):
							entries.append({"side": foe, "slot": 4 - slot, "card": t})
			"all":   # every character: yours (not this card) and every opponent's
				entries = _fx_pool(side, e, slot).map(func(x): return {"side": side, "slot": x.slot, "card": x.card})
				for foe in foes_of(side):
					entries.append_array(_fx_pool(foe, e, -99).map(func(x): return {"side": foe, "slot": x.slot, "card": x.card}))
	var what_ := str(e.get("do", ""))
	# (a leader on the field can be affected like any character, but has no hand to go back to)
	# (STASIS can't be targeted, except to be cleansed of it)
	entries = entries.filter(func(x): return pick.call(x) and not (x.card.get("cardType") == "leader" and what_ in ["bounce", "topdeck", "exile"]) \
		and (what_ == "cleanse" or not in_stasis(x.card)))
	# immune: to the statuses it lists (none listed: all of them)
	var covers := func(im: Dictionary) -> bool:
		var list = im.get("statuses")
		return not (list is Array) or list.is_empty() or what_ in list
	if what_ in IMMUNE_TO:
		entries = entries.filter(func(x): return _passive(x.side, x.slot, x.card, "immune", covers).is_empty())
	if what_ == "down":
		entries = entries.filter(func(x): return not _stays_up(x.side, x.slot, x.card))
	if target == "attacker" or target == "deployed":
		entries = entries.filter(func(x): return x.side == side or _passive(x.side, x.slot, x.card, "untargetable").is_empty())
	return entries


## How good a target `x` is for effect `e`, from the deciding side's view (prompts list the
## best first, and that is the CPU's pick). Plain strength unless the effect cares about more.
func _target_value(side: String, e: Dictionary, x: Dictionary) -> int:
	var c: Dictionary = x.card
	var value := _attack_value(c)
	var standing_atk: bool = not c.downed and c.position == "atk"
	match str(e.get("do", "")):
		"shock":
			if not c.downed and maxi(1, int(e.get("amount", 1))) >= int(c.get("defense", 0)):
				return 100000 + value   # one it knocks Down
		"stasis":
			if x.side == side:
				return (100000 if c.downed else 0) + value   # shelter a Downed ally from the KO
			return (100000 if standing_atk else 0) + value
		"poison", "bleed":
			if c.has(str(e.do)):
				return value - 50000
			if c.downed:
				return value - 20000
		"burn":
			if c.has("burn"):
				return int(c.get("defense", 0)) - 50000
			return (0 if c.downed else 10000) + int(c.get("defense", 0))   # one that will stay around
		"freeze", "stun":
			var key := "freeze_until" if str(e.do) == "freeze" else "stun_until"
			if int(c.get(key, 0)) >= turn:
				return value - 50000
			if standing_atk:
				return 100000 + value
		"shield":
			if c.get("shield", false):
				return value - 50000
	return value


func _fx_kind_ok(card: Dictionary, e: Dictionary) -> bool:
	var kind := "gang_member" if str(e.get("do", "")) in ["revive", "call"] else str(e.get("kind", ""))
	var clan := str(e.get("clan", ""))
	if not ((kind == "" or card.get("cardType") == kind) and (clan == "" or card.get("clanTag") == clan) \
			and card.get("cardType") != "leader"):
		return false
	# search / recover / revive filters: Authority N or less, role, level, name
	if e.get("max_auth") != null and int(card.get("authority", 0)) > int(e.max_auth):
		return false
	if str(e.get("role", "")) != "" and (card.get("cardType") != "gang_member" or str(card.get("subtype", "brawler")) != str(e.role)):
		return false
	if e.get("level") != null and (card.get("cardType") != "gang_member" or maxi(1, int(card.get("level", 1))) != int(e.level)):
		return false
	if str(e.get("name", "")) != "" and not str(card.get("name", "")).to_lower().contains(str(e.name).to_lower()):
		return false
	return true


## search / recover / revive: take matching cards from a pile (top first), `amount` times; with
## `choose` the player picks each one (options best first, so the CPU takes the best).
## Same as _fxTake in shared/duel/DuelState.js.
## after: once it's done (every card taken, or skipped), when it looked through the pile (a deck is
## shuffled then)
func _fx_take(side: String, c: Dictionary, e: Dictionary, pile: Array, prompt: String, take: Callable, after := Callable(), left := -1) -> bool:
	var amount := maxi(1, int(e.get("amount", 1)))
	if left < 0:
		left = amount
	var matches: Array = []
	for i in range(pile.size() - 1, -1, -1):
		if (not is_same(pile[i], c) or _take_self) and _fx_kind_ok(pile[i], e) \
				and not (pile[i].get("token", false) and str(e.get("do", "")) == "recover"):
			matches.append(pile[i])
	if matches.is_empty():
		if after.is_valid() and left < amount:   # (found some before)
			after.call()
		return false
	var done := func() -> void:
		if after.is_valid():
			after.call()
	var next := func(card: Dictionary) -> void:
		var at := -1
		for i in pile.size():
			if pile[i].uid == card.uid:
				at = i
				break
		if at < 0:
			done.call()
			return
		# take(card, cont): true taken, false not (the rest stop); "wait": it asks first, then cont(taken)
		var go := func(taken) -> void:
			if not taken:
				done.call()
			elif left > 1:
				_fx_take(side, c, e, pile, prompt, take, after, left - 1)
			else:
				done.call()
		var got: Dictionary = pile.pop_at(at)
		var r = take.call(got, go) if take.get_argument_count() >= 2 else take.call(got)
		if not (r is String and r == "wait"):
			go.call(r)
	if not e.get("choose", false):
		next.call(matches[0])
		return true
	var seen := {}
	var opts: Array = []
	for k in matches.size():
		var m: Dictionary = matches[k]
		var key := "%s|%s" % [m.id, m.name]
		if not seen.has(key):
			seen[key] = true
			opts.append({"m": m, "k": k})
	opts.sort_custom(func(a, b):
		var da := int(a.m.get("authority", 0)) - int(b.m.get("authority", 0))
		if da != 0:
			return da > 0
		var dk := int(a.m.get("base_attack", 0)) - int(b.m.get("base_attack", 0))
		if dk != 0:
			return dk > 0
		return a.k < b.k)
	var shown: Array = opts.slice(0, 8)
	var options: Array = []
	for k in shown.size():   # (each option carries its card: the player sees the cards to choose from)
		options.append({"id": str(k), "label": "%s  (%d)" % [str(shown[k].m.name).to_upper(), int(shown[k].m.get("authority", 0))],
			"card": shown[k].m.duplicate(true)})
	options.append({"id": "skip", "label": "SKIP"})
	_ask(side, "fx_pick", prompt, c, options, func(choice: String):
		var k := int(choice) if choice != "skip" else -1
		if k >= 0 and k < shown.size():
			next.call(shown[k].m)
		else:
			done.call())
	return true


## A deck that was searched is shuffled (not in the engines' comparison games, which keep a fixed order).
func _shuffle_deck(side: String) -> void:
	if not _fixed_order:
		_shuffle(sides[side].deck)
	_emit("shuffle", {"side": side})


func _heal(side: String, c: Dictionary, n: int, slot: int) -> void:
	var s: Dictionary = sides[side]
	var gain: int = mini(n, int(s.get("max_morale", START_MORALE)) - s.morale)
	if gain > 0:
		s.morale += gain
		_effect(side, c, "%s: +%d Morale" % [c.name, gain], slot)
		_emit("heal", {"side": side, "amount": gain, "morale": s.morale})
		if not _healing:   # ("when you gain Morale" can't set itself off again)
			_healing = true
			for x in characters(side):
				if winner == "":
					_run_fx(side, x.slot, x.card, "heal_gained")
			_run_lasting(side, "heal_gained")
			_healing = false


## A character goes back to its owner's hand, reset.
func _bounce(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	var own := _owner_of(side, c)
	c.erase("charmed")
	if c.get("token", false):   # a token has no hand to go back to: it vanishes
		_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})
		return
	c.downed = false
	c.mods = []
	c.position = "atk"
	c.face_down = false
	c.has_attacked = false
	for k in ["shield", "stun_until", "down_turns", "kings_test", "fx_used", "fx_count"]:
		c.erase(k)
	_clear_status(c)
	sides[own].hand.append(c)
	if own == side:
		_emit("bounce", {"side": side, "slot": slot, "card": c.duplicate(true)})
	else:
		_emit("bounce", {"side": side, "slot": slot, "card": c.duplicate(true), "to": own})


## Passive buffs active on \`side\`: [[source slot (-1 = dormant leader), effect], ...]
func _auras(side: String) -> Array:
	var s: Dictionary = sides[side]
	var out: Array = []
	for x in characters(side):
		if x.card.face_down:
			continue
		for e in _fx(x.card, "passive"):
			if str(e.get("do", "")) == "buff" and _fx_cond(side, x.slot, e, null):
				out.append([x.slot, _scaled(side, x.slot, e)])
	if s.leader_state == "dormant" and s.leader != null:
		for e in _fx(s.leader, "dormant"):   # (its "passive" effects work once it's on the field)
			if str(e.get("do", "")) == "buff" and _fx_cond(side, -1, e, null):
				out.append([-1, _scaled(side, -1, e)])
	for x in _lasting(side, "continuous"):   # (from the back row: they reach every character)
		for e in _fx(x.card, "passive"):
			if str(e.get("do", "")) == "buff" and _fx_cond(side, x.slot, e, null):
				out.append([x.slot, _scaled(side, x.slot, e)])
	return out


func _aura_hits(a: Array, slot: int, c: Dictionary) -> bool:
	var e: Dictionary = a[1]
	var clan := str(e.get("clan", ""))
	if clan != "" and c.get("clanTag") != clan:
		return false
	match str(e.get("target", "self")):
		"self":
			return a[0] == slot
		"allies":
			return a[0] != slot
	return false


func _slot_of(side: String, c: Dictionary, fallback: int) -> int:
	for slot in FRONT:
		if sides[side].field[slot] == c:
			return slot
	return fallback


static func _signed(v: int) -> String:
	return ("+" if v > 0 else "") + str(v)


static func _stat_text(mod: Dictionary) -> String:
	var parts: Array = []
	if int(mod.get("atk", 0)) != 0:
		parts.append("%s ATK" % _signed(int(mod.atk)))
	if int(mod.get("def", 0)) != 0:
		parts.append("%s DEF" % _signed(int(mod.def)))
	return " / ".join(parts) if not parts.is_empty() else "no change"


## "ATK becomes 100 / DEF becomes 100" (a set_stats mod)
static func _set_text(mod: Dictionary) -> String:
	var parts: Array = []
	if mod.has("set_atk"):
		parts.append("ATK becomes %d" % int(mod.set_atk))
	if mod.has("set_def"):
		parts.append("DEF becomes %d" % int(mod.set_def))
	return " / ".join(parts) if not parts.is_empty() else "no change"


# ── Turn flow ────────────────────────────────────────────────────────────────

func _begin_turn() -> void:
	var s: Dictionary = sides[active]
	for k in sides:   # (once per turn: any turn, e.g. a Striver promoting on the opponent's)
		sides[k].promoted = {}
	s.mentor_used = false
	s.turns = int(s.get("turns", 0)) + 1
	# Every character of yours is ready to attack on your turn, including one that arrived on the
	# opponent's (promoted, revived or Awakened then: it was marked as having attacked)
	for c in s.field:
		if c != null:
			c.has_attacked = false
	if int(s.get("barricade", 0)) > 0:   # (it lasts until your next turn)
		s.barricade = 0
		_emit("barricade", {"side": active, "amount": 0})
	_set_phase("upkeep")
	_emit("turn", {"side": active, "turn": turn})
	# Authority grows every turn but your first
	if s.turns > 1:
		s.authority_max = mini(MAX_AUTHORITY, s.authority_max + 1)
		s.authority = s.authority_max
		_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": 1})
	# Going second (or later) is a disadvantage (in CPU mirror matches the first player won ~70%);
	# one extra Authority on that player's first turn brings it close to even
	if s.turns == 1 and active != first_seat and SECOND_PLAYER_AUTHORITY > 0:
		s.authority = s.authority_max + SECOND_PLAYER_AUTHORITY
		_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": SECOND_PLAYER_AUTHORITY})
	if turn > 1:
		_draw(active)
	var boss = rules.get("boss")   # (Turf Defense: the boss draws and gets Authority extra)
	if boss is Dictionary and str(boss.get("seat", "")) == active and winner == "":
		for i in int(boss.get("draw", 0)):
			if winner != "":
				break
			_draw(active)
		if int(boss.get("authority", 0)) > 0:
			s.authority += int(boss.authority)
			_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": int(boss.authority)})
	if int(s.get("tax", 0)) > 0:   # TAX: this turn's Authority, less what an opponent's card took
		var t: int = mini(int(s.tax), s.authority)
		s.tax = 0
		if t > 0:
			s.authority -= t
			_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": -t})
			_emit("notice", {"side": active, "text": "TAX: -%d AUTHORITY THIS TURN" % t})
	# A Downed character stays down for a full round (the opponent gets one turn to finish it
	# off), then gets back up in DEF position at the start of its owner's turn. Its owner
	# may switch it to ATK straight away.
	for e in characters(active):
		if not e.card.downed:
			e.card.erase("down_turns")
		elif int(e.card.get("down_turns", 0)) >= 1:
			e.card.downed = false
			e.card.erase("down_turns")
			e.card.position = "def"
			_emit("stand", {"side": active, "slot": e.slot, "card": e.card.duplicate(true)})
		else:
			e.card.down_turns = 1
	_status_ticks(active)
	if winner != "":
		return
	for e in characters(active):
		_run_fx(active, e.slot, e.card, "turn_start")
	_run_lasting(active, "turn_start")
	_leader_fx(active, "dormant_turn_start")
	# King's Test survivors may promote at the start of their owner's next turn
	for e in characters(active):
		if e.card.get("kings_test", false):
			e.card.erase("kings_test")
			var side := active
			var slot: int = e.slot
			_ask(side, "kings_test", "King's Test: promote %s now?" % e.card.name, e.card, [
				{"id": "yes", "label": "PROMOTE", "side": side, "slot": slot}, {"id": "no", "label": "NOT NOW"},
			], func(choice: String):
				if choice == "yes":
					_promote(side, slot, "King's Test"))
	_check_awaken(active)
	_recalc()
	_set_phase("deployment")
	if winner == "":
		_offer_flips()


## The end of a turn: CHARMED characters go back to their owners (to their own lane, else the first
## empty one, else their Gutter), and UNDEAD characters KO'd this turn rise (once), in DEF with half
## their ATK and DEF. Same as _turnOver in DuelState.js.
func _turn_over() -> void:
	for side in sides:
		for slot in FRONT:
			var c = sides[side].field[slot]
			if c == null or not (c.get("charmed") is Dictionary) or int(c.charmed.until) > turn:
				continue
			var own := str(c.charmed.owner)
			var back := int(c.charmed.slot)
			c.erase("charmed")
			sides[side].field[slot] = null
			var to := back if sides[own].field[back] == null else _empty_lane(own)
			if to < 0:   # no room back home: to its owner's Gutter
				c.mods = []
				_clear_status(c)
				sides[own].gutter.append(c)
				_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})
				continue
			sides[own].field[to] = c
			_emit("charm", {"side": side, "slot": slot, "to_side": own, "to_slot": to, "card": c.duplicate(true), "back": true})
	for side in sides:
		var s: Dictionary = sides[side]
		var rising: Array = s.gutter.filter(func(g): return g.get("rise_turn") != null and int(g.rise_turn) <= turn)
		for c in rising:
			c.erase("rise_turn")
			var lane := _empty_lane(side)
			if lane < 0 or s.get("out", false):   # no room: it stays in the Gutter
				continue
			s.gutter.remove_at(s.gutter.find(c))
			c.risen = true
			c.downed = false
			c.position = "def"
			c.face_down = false
			c.has_attacked = false
			c.erase("fx_count")
			c.mods = [{"atk": -int(floor(int(c.base_attack) / 2.0)), "def": -int(floor(int(c.base_defense) / 2.0)), "until_turn": FOREVER}]
			c.deployed_turn = turn
			s.field[lane] = c
			_emit("summon", {"side": side, "slot": lane, "card": c.duplicate(true), "from": "undead"})
			_effect(side, c, "%s rises from the Gutter (UNDEAD)" % c.name, lane)
	_recalc()


func _end_turn() -> void:
	for e in characters(active):
		_run_fx(active, e.slot, e.card, "turn_end")
	_run_lasting(active, "turn_end")
	for foe in foes_of(active):
		for e in characters(foe):
			_run_fx(foe, e.slot, e.card, "foe_turn_end")
		_run_lasting(foe, "foe_turn_end")
	_leader_fx(active, "dormant_turn_end")
	if winner != "":
		return
	_turn_over()
	var s: Dictionary = sides[active]
	for c in s.field:
		if c != null:
			c.has_attacked = false
	s.brutus_bonus = 0
	for side in sides:
		for c in sides[side].field:
			if c != null:
				c.mods = c.mods.filter(func(m): return m.until_turn > turn)
	active = _next_seat(active)
	turn += 1
	_begin_turn()


func _set_phase(p: String) -> void:
	phase = p
	_emit("phase", {"phase": p, "side": active})


# ── Prompts ──────────────────────────────────────────────────────────────────

func _ask(side: String, key: String, prompt: String, card: Dictionary, options: Array, cb: Callable) -> Dictionary:
	var ask := {"kind": "choose", "side": side, "key": key, "prompt": prompt, "options": options,
		"card": card.duplicate(true), "cb": cb}
	if _in_answer:
		_new_asks.append(ask)
	else:
		_asks.append(ask)
	return ask


## Pick one character from `entries` ([{slot, card}], best first). One option resolves at once.
## optional: the player always chooses (even from one) and may skip it (a card effect's target).
## Entries may carry their own side (FFA: cards on several opponents' boards; their option ids are
## then "side:slot"); otherwise they're on target_side.
func _ask_target(side: String, key: String, prompt: String, source: Dictionary, entries: Array,
		target_side: String, cb: Callable, optional := false) -> void:
	# Your opponent's effects can't choose a card that can't be targeted
	entries = entries.filter(func(e): return str(e.get("side", target_side)) == side \
		or _passive(str(e.get("side", target_side)), e.slot, e.card, "untargetable").is_empty())
	if entries.is_empty():
		return
	if entries.size() == 1 and not optional:
		cb.call(entries[0])
		return
	var multi := false
	for e in entries:
		if str(e.get("side", target_side)) != str(entries[0].get("side", target_side)):
			multi = true
	var options: Array = []
	for e in entries:
		var on := str(e.get("side", target_side))
		options.append({"id": ("%s:%d" % [on, e.slot]) if multi else str(e.slot),
			"label": "%s  (%d / %d)" % [str(e.card.name).to_upper(), e.card.attack, e.card.defense],
			"side": on, "slot": e.slot})
	if optional:
		options.append({"id": "skip", "label": "SKIP"})
	_ask(side, key, prompt, source, options, func(choice: String):
		for e in entries:
			var on := str(e.get("side", target_side))
			var id := ("%s:%d" % [on, e.slot]) if multi else str(e.slot)
			if id == choice and card_at(on, e.slot) == e.card:
				cb.call(e))


## Opening hand: keep it, or shuffle it back and draw the same number again (once).
## The suggested choice comes first: redraw when nothing in hand is cheap enough to play early.
func _ask_mulligan(side: String, then: Callable) -> void:
	var keep := {"id": "keep", "label": "KEEP THIS HAND"}
	var redraw := {"id": "redraw", "label": "REDRAW: SHUFFLE BACK AND DRAW %d" % sides[side].hand.size()}
	var cheap: bool = sides[side].hand.any(func(c): return c.cardType == "gang_member" and int(c.authority) <= 2)
	_ask(side, "mulligan", "Your opening hand. Keep it, or shuffle it back and draw a new one?", {},
		[keep, redraw] if cheap else [redraw, keep], func(choice: String):
			if choice == "redraw":
				_mulligan(side)
			then.call())


func _mulligan(side: String) -> void:
	var s: Dictionary = sides[side]
	var n: int = s.hand.size()
	for c in s.hand:
		s.deck.push_front(c)   # to the bottom: draws come off the back
	s.hand.clear()
	if not _fixed_order:
		_shuffle(s.deck)
	_emit("mulligan", {"side": side, "count": n})
	for i in n:
		_draw(side, true)


## why: what the prompt says first, so the player knows what's making them discard.
func _ask_discard(side: String, count: int, then: Callable, why := "") -> void:
	var choose := "Choose %d card%s to discard" % [count, "" if count == 1 else "s"]
	var ask := {"kind": "discard", "side": side, "count": count, "cb": then,
		"prompt": ("%s. %s" % [why, choose]) if why != "" else choose}
	if _in_answer:
		_new_asks.append(ask)
	else:
		_asks.append(ask)


func _answer(side: String, option: String) -> bool:
	if pending.get("kind") != "choose" or pending.side != side:
		return false
	if not pending.options.any(func(o): return o.id == option):
		return false
	var cb: Callable = pending.cb
	_emit("answered", {"side": side, "key": pending.key, "option": option})
	pending = {}
	_run_answer(cb.bind(option))
	return true


func _choose_discard(side: String, uid: int) -> bool:
	if pending.get("kind") != "discard" or pending.side != side:
		return false
	var i := _hand_index(side, uid)
	if i < 0:
		return false
	_discard_at(side, i)
	pending.count -= 1
	if pending.count > 0 and not sides[side].hand.is_empty():
		pending.prompt = "Choose %d more card%s to discard" % [pending.count, "" if pending.count == 1 else "s"]
		_emit("prompt", _prompt_event(pending))
		return true
	var cb: Callable = pending.cb
	pending = {}
	if cb.is_valid():
		_run_answer(cb)
	return true


## Run an answer; prompts it raises go ahead of ones already queued.
func _run_answer(cb: Callable) -> void:
	_in_answer = true
	_new_asks = []
	cb.call()
	_in_answer = false
	_asks = _new_asks + _asks
	_new_asks = []


## Make the next queued prompt current (skipping ones that no longer apply).
func _flush_asks() -> void:
	while pending.is_empty() and not _asks.is_empty() and winner == "":
		var ask: Dictionary = _asks.pop_front()
		if ask.has("still") and not ask.still.call():   # no longer applies (e.g. a promotion whose card went Down)
			continue
		if ask.kind == "then":   # (not a prompt: what waits for the prompts before it, e.g. a brawl after an Ambush's choices)
			_run_answer(ask.cb)
			continue
		if ask.kind == "discard" and sides[ask.side].hand.is_empty():
			if ask.cb.is_valid():
				_run_answer(ask.cb)
			continue
		pending = ask
		_emit("prompt", _prompt_event(ask))


static func _prompt_event(ask: Dictionary) -> Dictionary:
	var ev := ask.duplicate()
	ev.erase("cb")
	ev.erase("still")
	return ev


# ── Helpers ──────────────────────────────────────────────────────────────────

func _draw(side: String, opening := false) -> void:
	var s: Dictionary = sides[side]
	if s.deck.is_empty():
		_boss_recycle(side)
	if s.deck.is_empty():
		# Decked out: a player who has to draw from an empty deck loses
		if winner == "":
			_lose(side, "deck_out")
		return
	var c: Dictionary = s.deck.pop_back()
	s.hand.append(c)
	_emit("draw", {"side": side, "card": c.duplicate(true), "opening": opening})


## Turf Defense: the boss never runs out of cards: when its deck is empty, its Gutter (not tokens)
## is shuffled back into it ("recycle" event).
func _boss_recycle(side: String) -> void:
	var b = rules.get("boss")
	if not b is Dictionary or str(b.get("seat", "")) != side:
		return
	var s: Dictionary = sides[side]
	var back: Array = s.gutter.filter(func(c): return not c.get("token", false))
	if back.is_empty():
		return
	var keep: Array = s.gutter.filter(func(c): return c.get("token", false))
	s.gutter.clear()
	s.gutter.append_array(keep)
	for c in back:
		c.mods = []
		c.downed = false
		_clear_status(c)
		c.erase("fx_count")
		c.erase("rise_turn")
		c.has_attacked = false
		c.face_down = false
		s.deck.append(c)
	_emit("recycle", {"side": side, "count": back.size()})
	_shuffle_deck(side)


func _discard_at(side: String, i: int) -> void:
	var c: Dictionary = sides[side].hand.pop_at(i)
	sides[side].gutter.append(c)
	_emit("discard", {"side": side, "card": c.duplicate(true)})
	_to_gutter_fx(side, c)


func _spend(side: String, amount: int) -> void:
	if amount <= 0:
		return
	var s: Dictionary = sides[side]
	s.authority = maxi(0, s.authority - amount)
	_emit("authority", {"side": side, "value": s.authority, "max": s.authority_max, "delta": -amount})


## Luck (Card Forge, same as _luckGate in DuelState.js): whether an effect happens.
##   luck: "coin" (heads: it happens) | "die" (it happens on luck_on or more, 1-6; "for each pip"
##   (per: "roll") multiplies it by the die). if_luck: "won" | "lost": no roll of its own, it
##   follows the last flip or roll ("If tails, ..."). Anything else always happens.
func _luck_gate(side: String, slot: int, c: Dictionary, e: Dictionary) -> bool:
	var follow := str(e.get("if_luck", ""))
	if follow != "":
		if _luck_last.is_empty():
			return false
		_roll = int(_luck_last.value)
		return (not _luck_last.won) if follow == "lost" else bool(_luck_last.won)
	var kind := str(e.get("luck", ""))
	if kind != "coin" and kind != "die" and kind != "double" and str(e.get("per", "")) != "roll":
		return true
	var coin := kind == "coin" or kind == "double"
	var won := _luck_toss(side, slot, c, coin, 1 if coin else clampi(int(e.get("luck_on", 1)), 1, 6), kind == "double")
	var s = sides.get(side)
	if not won and s != null and int(s.get("loaded_turn", -1)) != turn and winner == "":   # LOADED DICE: once a turn, try again
		for x in characters(side):
			if not _passive(side, x.slot, x.card, "loaded").is_empty():
				s.loaded_turn = turn
				_effect(side, x.card, "%s: LOADED DICE, %s again" % [x.card.name, "flip" if coin else "roll"], x.slot)
				won = _luck_toss(side, slot, c, coin, 1 if coin else clampi(int(e.get("luck_on", 1)), 1, 6), kind == "double", true)
				break
	return won


## One flip or roll for _luck_gate (with its luck event and its line in the log).
func _luck_toss(side: String, slot: int, c: Dictionary, coin: bool, need: int, double := false, again := false) -> bool:
	var r := _luck_next()
	var value: int = (1 if r < 0.5 else 0) if coin else 1 + int(floor(r * 6.0))   # coin: 1 heads, 0 tails
	var won := value >= need
	if won and sides.has(side):   # (a leader can Awaken on it)
		sides[side].luck_won = int(sides[side].get("luck_won", 0)) + 1
	_luck_last = {"won": won, "value": value}
	_roll = value
	var ev := {"side": side, "slot": slot, "card": c.duplicate(true), "kind": "coin" if coin else "die",
		"value": value, "need": need, "won": won}
	if double:
		ev["double"] = true   # (the game shows the stakes: DOUBLE! or nothing)
	if again:
		ev["again"] = true    # (a LOADED DICE re-roll)
	_emit("luck", ev)
	var text := ""
	if coin:
		text = "%s flips a coin: %s" % [c.name, "HEADS" if value == 1 else "TAILS"]
	else:
		var note := ""
		if need > 1:
			note = (" (%d+ needed)" % need) if won else (" (needed %d+)" % need)
		text = "%s rolls a %d%s" % [c.name, value, note]
	_effect(side, c, text, slot)
	return won


## mulberry32 (DuelState.js seededRandom): 0 <= x < 1, in 32-bit steps.
func _luck_next() -> float:
	_luck_t = (_luck_t + 0x6D2B79F5) & M32
	var t := _luck_t
	var r := _imul(t ^ (t >> 15), 1 | t)
	r = ((r + _imul(r ^ (r >> 7), 61 | r)) & M32) ^ r
	return float((r ^ (r >> 14)) & M32) / 4294967296.0


## JavaScript's Math.imul (the low 32 bits of a product), unsigned, without overflowing 64 bits.
static func _imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & 0xFFFF
	return (lo + (hi << 16)) & M32


## public_text: what the other players see instead (text names a card they mustn't know).
func _effect(side: String, c: Dictionary, text: String, slot := -1, public_text := "") -> void:
	_did += 1   # effects that did something (see then in _do_fx)
	if public_text != "":
		_emit("effect", {"side": side, "card": c.duplicate(true), "text": text, "slot": slot, "public_text": public_text})
	else:
		_emit("effect", {"side": side, "card": c.duplicate(true), "text": text, "slot": slot})


func _hand_index(side: String, uid: int) -> int:
	var hand: Array = sides[side].hand
	for i in hand.size():
		if hand[i].uid == uid:
			return i
	return -1


func _has_striver(side: String) -> bool:
	return characters(side).any(func(e): return e.card.get("subtype") == "striver")


func _downed_lions(side: String) -> Array:
	var out := characters(side).filter(func(e): return e.card.downed and is_lion(e.card))
	out.sort_custom(_strongest_first)
	return out


## Whether a Striver's next level waits in the side's Hideout: it can't promote without it.
func _next_in_hideout(side: String, card: Dictionary) -> bool:
	var to := CardDB.next_form(str(card.id))
	return to != "" and sides[side].hideout.any(func(h): return h.get("id") == to)


func _promotable_strivers(side: String) -> Array:
	var out := characters(side).filter(func(e): return is_lion(e.card) and e.card.get("subtype") == "striver" \
		and not e.card.downed and not e.card.face_down and not sides[side].promoted.has(e.slot) \
		and _next_in_hideout(side, e.card))
	out.sort_custom(func(a, b): return int(a.card.level) > int(b.card.level) or (int(a.card.level) == int(b.card.level) and a.slot < b.slot))
	return out


## The Block Enforcer that could take a hit aimed at `target_slot`, as {slot, card}, or {}.
func _ready_enforcer(side: String, target_slot: int) -> Dictionary:
	for e in characters(side):
		var c: Dictionary = e.card
		if e.slot != target_slot and c.get("effectKey") == "block_enforcer_redirect" \
				and not c.downed and not c.face_down and c.get("redirect_turn", 0) != turn:
			return e
	return {}


## Would the Block Enforcer fare better against this attacker than the target would?
static func _enforcer_worth_it(att: Dictionary, target: Dictionary, be: Dictionary) -> bool:
	var target_holds: bool = (target.defense if target.downed or target.position == "def" else target.attack) >= att.attack
	var be_holds: bool = (be.defense if be.position == "def" else be.attack) >= att.attack
	return target.downed or (be_holds and not target_holds)


func _adjacent_lion(side: String, slot: int) -> bool:
	for adj in [slot - 1, slot + 1]:
		if adj in FRONT and is_lion(card_at(side, adj)):
			return true
	return false


## Sort entries strongest first; ties go to the lower lane so every engine orders them the same.
static func _strongest_first(a: Dictionary, b: Dictionary) -> bool:
	var va := _attack_value(a.card)
	var vb := _attack_value(b.card)
	return va > vb or (va == vb and a.slot < b.slot)


static func _attack_value(c: Dictionary) -> int:
	return int(c.get("attack", 0)) + (0 if c.get("downed", false) else 1)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _emit(type: String, data := {}) -> void:
	data.type = type
	data.counts = _counts()
	_events.append(data)


## Pile sizes and resources after this event, so the screen never has to read live state.
func _counts() -> Dictionary:
	var out := {}
	for side in sides:
		var s: Dictionary = sides[side]
		out[side] = {
			"deck": s.deck.size(), "gutter": s.gutter.size(), "hideout": s.hideout.size(),
			"hand": s.hand.size(), "morale": s.morale,
			"authority": s.authority, "authority_max": s.authority_max,
			"gutter_top": s.gutter.back().id if not s.gutter.is_empty() else "",
			"leader_state": s.leader_state,
			"influence": s.leader.influence if s.leader != null else 0,
		}
		if ffa:
			out[side].out = int(s.get("out", 0))
	return out
