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

const START_MORALE := 6000
const MAX_AUTHORITY := 15
const HAND_LIMIT := 9
const OPENING_HAND := 5
const SECOND_PLAYER_AUTHORITY := 1 # going second: extra Authority on your first turn only
const LEADER_DEFEAT_PENALTY := 1000
const FRONT := [0, 1, 2, 3, 4]   # character slots
const BACK := [5, 6, 7, 8, 9]    # ambush slots
const DIRECT := -1               # attack target: the opponent's morale
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
var _fixed_order := false    # seed -1: never shuffle (tests compare engines)


## decks/hideouts: {"player": [card ids], "opponent": [...]}; leaders: {"player": id, ...}
func _init(decks: Dictionary, hideouts: Dictionary, leaders: Dictionary, first := "player", seed_value := 0) -> void:
	if seed_value > 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	active = first
	_fixed_order = seed_value == -1
	for side in ["player", "opponent"]:
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
			leader.influence = leader.base_defense
		sides[side] = {
			"morale": START_MORALE, "authority": 1, "authority_max": 1,
			"deck": deck, "hand": [], "field": field, "gutter": [], "hideout": hideout,
			"leader": leader, "leader_state": "dormant" if leader != null else "none",
			"brutus_bonus": 0, "promoted": {}, "mentor_used": false,
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
	return winner == "" and pending.is_empty() and side == active


func can_deploy_now(side: String) -> bool:
	return can_act(side) and phase in ["deployment", "regroup"]


## Character classes: Strivers level up (only they can PROMOTE); Brawlers are standalone;
## Heavies are standalone too, and need one of your characters sacrificed to come into play
## (the Heavy takes its lane).
static func needs_tribute(c) -> bool:
	return c != null and c.get("subtype") == "heavy"


## Summon `c` into `slot`. A Heavy names the character it sacrifices (`tribute`), and takes
## that lane; anything else needs an empty lane and no tribute.
func can_summon(side: String, c: Dictionary, slot: int, tribute := -1) -> bool:
	if not can_deploy_now(side) or c.get("cardType") != "gang_member":
		return false
	if not slot in FRONT or sides[side].authority < c.authority:
		return false
	if needs_tribute(c):
		var t = card_at(side, tribute) if tribute in FRONT else null
		return slot == tribute and t != null and t.get("cardType") != "leader" and not in_stasis(t)
	return tribute == -1 and sides[side].field[slot] == null


## Whether `c` can be summoned anywhere right now (a Heavy needs a character to sacrifice).
func can_summon_somewhere(side: String, c: Dictionary) -> bool:
	for slot in FRONT:
		if can_summon(side, c, slot, slot if needs_tribute(c) else -1):
			return true
	return false


func can_set(side: String, c: Dictionary, slot: int) -> bool:
	if not can_deploy_now(side) or c.get("cardType") != "ambush":
		return false
	if not slot in BACK or sides[side].field[slot] != null:
		return false
	return sides[side].authority >= c.authority


func hustle_ready(side: String, c: Dictionary) -> bool:
	match c.get("effectKey", ""):
		"lion_rescue":
			return not _downed_lions(side).is_empty()
		"blood_scent":
			return not _promotable_strivers(side).is_empty()
	return true


func can_hustle(side: String, c: Dictionary) -> bool:
	return can_deploy_now(side) and c.get("cardType") == "hustle" \
		and sides[side].authority >= c.authority and hustle_ready(side, c)


## Keyword statuses (Card Forge effects). Freeze and Stasis last through the owner's next turn.
const FOREVER := 1000000        # until_turn for mods that last until the card leaves the field
const STATUS_TICKS := 3         # Poison / Burn tick at the start of the owner's next 3 turns
const STATUS_KEYS := ["poison", "burn", "bleed", "freeze_until", "stasis_until"]


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
	if c.get("shield", false):
		out.append("shield")
	return out


func can_attack_with(side: String, slot: int) -> bool:
	if not can_act(side) or phase != "brawl" or turn == 1 or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	return c != null and c.position == "atk" and not c.downed and not c.has_attacked and not c.face_down \
		and int(c.get("stun_until", 0)) < turn and not frozen(c) and not in_stasis(c)


## Attack targets: any enemy character; DIRECT when none of them is still standing (an empty
## front row, or only Downed characters); and the enemy LEADER whenever it is dormant.
func attack_targets(side: String) -> Array:
	var foe := other(side)
	# A character in STASIS can't be attacked and doesn't block a direct attack
	var foes := characters(foe).filter(func(e): return not in_stasis(e.card))
	var targets: Array = foes.map(func(e): return e.slot)
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
	if sides[side].promoted.has(slot) or CardDB.next_form(c.id) == "":
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


# ── Actions ──────────────────────────────────────────────────────────────────

func start() -> void:
	for i in OPENING_HAND:
		_draw(active, true)
		_draw(other(active), true)
	# Each player may redraw their opening hand once, first player first; then turn 1 begins
	var first := active
	_ask_mulligan(first, func(): _ask_mulligan(other(first), _begin_turn))
	_flush_asks()


func do_action(side: String, a: Dictionary) -> bool:
	if winner != "":
		return false
	var ok := false
	match a.get("kind", ""):
		"summon":
			ok = _summon(side, int(a.uid), int(a.slot), str(a.get("position", "atk")), int(a.get("tribute", -1)))
		"set":
			ok = _set_ambush(side, int(a.uid), int(a.slot))
		"hustle":
			ok = _hustle(side, int(a.uid))
		"attack":
			ok = _attack(side, int(a.from), int(a.target))
		"position":
			ok = _change_position(side, int(a.slot))
		"promote":
			if can_promote(side, int(a.slot)):
				_promote(side, int(a.slot), "Maya")
				ok = true
		"ability":
			ok = _use_ability(side, int(a.slot))
		"choose":
			ok = _answer(side, str(a.option))
		"discard":
			ok = _choose_discard(side, int(a.uid))
		"next":
			ok = _next_phase(side)
	if ok:
		_flush_asks()
		_recalc()
	return ok


func _summon(side: String, uid: int, slot: int, position: String, tribute := -1) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_summon(side, sides[side].hand[i], slot, tribute):
		return false
	var c: Dictionary = sides[side].hand.pop_at(i)
	_spend(side, c.authority)
	if needs_tribute(c):
		var t: Dictionary = card_at(side, tribute)
		sides[side].field[tribute] = null
		t.downed = false
		t.mods = []
		_clear_status(t)
		sides[side].gutter.append(t)
		_emit("tribute", {"side": side, "slot": tribute, "card": t.duplicate(true), "for": c.duplicate(true)})
	c.position = "def" if position == "def" else "atk"
	c.face_down = c.position == "def"   # set in DEF = face-down, like Yu-Gi-Oh
	c.has_attacked = false
	c.deployed_turn = turn
	sides[side].field[slot] = c
	_emit("summon", {"side": side, "slot": slot, "card": c.duplicate(true)})
	if not c.face_down:
		_on_deploy(side, slot, c)
	return true


func _set_ambush(side: String, uid: int, slot: int) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_set(side, sides[side].hand[i], slot):
		return false
	var c: Dictionary = sides[side].hand.pop_at(i)
	_spend(side, c.authority)
	c.face_down = true
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


func _hustle(side: String, uid: int) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_hustle(side, sides[side].hand[i]):
		return false
	var s: Dictionary = sides[side]
	var c: Dictionary = s.hand.pop_at(i)
	_spend(side, c.authority)
	s.gutter.append(c)
	_emit("hustle", {"side": side, "card": c.duplicate(true)})
	match c.effectKey:
		"corner_deal":
			_draw(side)
			_draw(side)
			if _has_striver(side):
				_effect(side, c, "You control a Striver: no discard")
			else:
				_effect(side, c, "Drew 2 — now discard 1")
				_ask_discard(side, 1, Callable())
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
			if turn == 1:
				_emit("notice", {"text": "NO ATTACKS ON TURN 1"})
				_set_phase("regroup")
			else:
				_set_phase("brawl")
		"brawl":
			_set_phase("regroup")
		"regroup":
			_set_phase("end")
			var extra: int = sides[side].hand.size() - HAND_LIMIT
			if extra > 0:
				_ask_discard(side, extra, _end_turn)
			else:
				_end_turn()
		_:
			return false
	return true


# ── Attacks ──────────────────────────────────────────────────────────────────
# An attack runs in steps; any step may pause for a prompt and continue from its answer.

func _attack(side: String, from: int, target: int) -> bool:
	if not can_attack_with(side, from) or not target in attack_targets(side):
		return false
	var att: Dictionary = card_at(side, from)
	att.has_attacked = true
	_emit("attack", {"side": side, "from": from, "target": target, "card": att.duplicate(true)})
	var ctx := {"side": side, "foe": other(side), "from": from, "target": target, "att": att, "bonus": 0}
	var def_now = card_at(other(side), target) if target >= 0 else null
	var k := 0
	for e in _fx(att, "attack"):
		k += 1
		var self_buff: bool = str(e.get("do", "")) == "buff" and str(e.get("target", "self")) == "self"
		if self_buff and str(e.get("if", "")) != "":
			continue   # depends on the defender: settled in the brawl (_brawl_bonus)
		if not _fx_cond(side, from, e, def_now) or not _fx_once(att, "attack%d" % k, e):
			continue
		if self_buff:
			if int(e.get("atk", 0)) != 0:
				ctx.bonus += int(e.get("atk", 0))
				_effect(side, att, "%s: %s ATK this brawl" % [att.name, _signed(int(e.get("atk", 0)))], from)
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
func _atk_redirect(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
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
						_emit("retarget", {"side": ctx.side, "from": ctx.from, "target": ctx.target})
					_atk_ambush(ctx))
			return
	_atk_ambush(ctx)


## The defender may spring a face-down Ambush on an attack against a LIONS character.
func _atk_ambush(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
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
			var a: Dictionary = card_at(foe, slot)
			_spring(foe, slot)
			if a.effectKey == "no_witnesses_ambush":
				_effect(foe, a, "No Witnesses: the attacker is Downed and the attack negated", slot)
				ctx.att.downed = true
				_emit("downed", {"side": ctx.side, "slot": ctx.from, "card": ctx.att.duplicate(true)})
				return
			_effect(foe, a, "Lion's Ambush: the attacker loses 1000 ATK this brawl", slot)
			ctx.bonus -= 1000
			_atk_resolve(ctx))


func _atk_resolve(ctx: Dictionary) -> void:
	var side: String = ctx.side
	var foe: String = ctx.foe
	var from: int = ctx.from
	var target: int = ctx.target
	var att: Dictionary = ctx.att

	if target == DIRECT:
		var dmg: int = maxi(0, att.attack + ctx.bonus)
		_emit("clash", {"side": side, "from": from, "target": DIRECT, "att": dmg, "def": 0, "vs": "DIRECT"})
		_damage(foe, dmg)
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
	var k := 0
	for e in _fx(def, "defend"):
		k += 1
		if winner != "" or not _fx_cond(foe, target, e, att) or not _fx_once(def, "defend%d" % k, e):
			continue
		if str(e.get("do", "")) == "buff" and str(e.get("target", "self")) == "self":
			def_atk += int(e.get("atk", 0))
			def_def += int(e.get("def", 0))
			_effect(foe, def, "%s: %s this brawl" % [def.name, _stat_text(e)], target)
		else:
			_do_fx(foe, target, def, e, {"side": side, "slot": from, "card": att})
	# The defender's effects may have removed or stopped the attacker (or itself)
	if winner != "" or card_at(side, from) != att or att.downed or card_at(foe, target) != def:
		return
	var bonus: int = ctx.bonus + _brawl_bonus(side, from, att, def)
	if def.get("effectKey") == "bulwark":
		bonus -= 300
		_effect(foe, def, "Bulwark: the attacker loses 300 ATK", target)

	var def_was_downed: bool = def.downed
	var def_info := {"downed": def.downed, "position": def.position, "face_down": false}
	var vs_def: bool = def.downed or def.position == "def"
	var a_val: int = maxi(0, att.attack + bonus)
	var d_val: int = (def.defense + def_def) if vs_def else (def.attack + def_atk)
	_emit("clash", {"side": side, "from": from, "target": target, "att": a_val, "def": d_val,
		"vs": "DEF" if vs_def else "ATK"})

	var result := ""
	if vs_def:
		if a_val > d_val:
			if ctx.get("pierce", false):
				_damage(foe, a_val - d_val)
			result = _defeat(foe, target)
		else:
			_emit("blocked", {"side": foe, "slot": target})
	elif a_val > d_val:
		_damage(foe, a_val - d_val)
		result = _defeat(foe, target)
	elif a_val < d_val:
		_damage(side, d_val - a_val)
		_defeat(side, from)
	else:
		_emit("notice", {"text": "TIE — BOTH GO DOWN"})
		result = _defeat(foe, target)
		_defeat(side, from)

	if winner == "" and card_at(side, from) == att and not att.downed:
		if result == "ko":
			_on_ko(side, from, att, def_was_downed, target)
			_run_fx(side, _slot_of(side, att, from), att, "ko", def_info)
		elif result == "downed":
			_on_down(side, from, att)
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


## A dormant leader soaks attacks with its Influence (its DEF). At 0 it is defeated:
## its owner loses 1000 morale and the Dormant bonus.
func _hit_leader(ctx: Dictionary) -> void:
	var foe: String = ctx.foe
	var leader: Dictionary = sides[foe].leader
	var dmg: int = maxi(0, ctx.att.attack + ctx.bonus)
	_emit("clash", {"side": ctx.side, "from": ctx.from, "target": LEADER, "att": dmg,
		"def": leader.influence, "vs": "INFLUENCE"})
	leader.influence = maxi(0, leader.influence - dmg)
	_emit("leader_hit", {"side": foe, "amount": dmg, "influence": leader.influence})
	if leader.influence <= 0:
		sides[foe].leader_state = "defeated"
		sides[foe].gutter.append(leader)
		_emit("leader_down", {"side": foe, "card": leader.duplicate(true)})
		_damage(foe, LEADER_DEFEAT_PENALTY)


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
	c.downed = true
	_emit("downed", {"side": side, "slot": slot, "card": c.duplicate(true)})
	_run_fx(side, slot, c, "self_downed")
	return "downed"


func _ko(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	c.downed = false
	c.mods = []
	_clear_status(c)
	sides[side].gutter.append(c)
	_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})
	_run_fx(side, slot, c, "self_ko")


func _damage(side: String, amount: int) -> void:
	if amount <= 0:
		return
	var s: Dictionary = sides[side]
	s.morale = maxi(0, s.morale - amount)
	_emit("damage", {"side": side, "amount": amount, "morale": s.morale})
	if s.morale <= 0 and winner == "":
		_end(other(side), "morale")


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
			extra += int(e.get("atk", 0))
			_effect(side, att, "%s: %s ATK this brawl" % [att.name, _signed(int(e.get("atk", 0)))], from)
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


func _on_ko(side: String, slot: int, att: Dictionary, was_downed: bool, target: int) -> void:
	var key: String = att.get("effectKey", "")
	var foe := other(side)
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
		var standing := characters(foe).filter(func(e): return not e.card.downed)
		standing.sort_custom(_strongest_first)
		_ask_target(side, "hunter_down", "%s KO: choose an enemy character to Down" % att.name, att,
			standing, foe, func(e: Dictionary):
				e.card.downed = true
				_effect(side, att, "%s Downs %s" % [att.name, e.card.name], slot)
				_emit("downed", {"side": foe, "slot": e.slot, "card": e.card.duplicate(true)}))
	if was_downed:
		if key in ["hunter_lv1", "hunter_lv2"]:
			_promote(side, slot, att.name)
		elif key == "hunter_lv3":
			att.has_attacked = false
			_effect(side, att, "%s may attack again this turn" % att.name, slot)


func _on_down(side: String, slot: int, att: Dictionary) -> void:
	var key: String = att.get("effectKey", "")
	match key:
		"brutus_enter":
			sides[side].brutus_bonus = 300
			_effect(side, att, "Brutus: your next LIONS attacker gains +300 ATK", slot)
		"debt_collector":
			var foe := other(side)
			if not sides[foe].hand.is_empty():
				_effect(side, att, "Debt Collector: your opponent discards 1 card", slot)
				_ask_discard(foe, 1, Callable())


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
	sides[side].field[slot] = null
	sides[side].gutter.append(a)
	a.face_down = false
	_emit("ambush", {"side": side, "slot": slot, "card": a.duplicate(true)})


# ── Effects ──────────────────────────────────────────────────────────────────

func _on_deploy(side: String, slot: int, c: Dictionary) -> void:
	_run_fx(side, slot, c, "deploy")
	for x in characters(side):
		if x.slot != slot:
			_run_fx(side, x.slot, x.card, "ally_deployed", c)
	var foe := other(side)
	match c.get("effectKey", ""):
		"pride_lieutenant_deploy":
			var allies := characters(side).filter(func(e): return e.slot != slot and is_lion(e.card))
			allies.sort_custom(_strongest_first)
			_ask_target(side, "lieutenant", "Pride Lieutenant: choose a LIONS ally to gain +500 ATK", c,
				allies, side, func(e: Dictionary):
					e.card.mods.append({"atk": 500, "until_turn": turn})
					_effect(side, c, "%s gains +500 ATK this turn" % e.card.name, slot))
		"brutus_enter":
			var foes := characters(foe)
			foes.sort_custom(_strongest_first)
			_ask_target(side, "brutus", "Brutus: choose an enemy character to lose 700 ATK", c,
				foes, foe, func(e: Dictionary):
					e.card.mods.append({"atk": -700, "until_turn": turn + 1})
					_effect(side, c, "%s loses 700 ATK until the end of your opponent's next turn" % e.card.name, slot))
		"sovereign":
			var hit := 0
			for e in characters(foe):
				if not e.card.downed and e.card.defense <= 1500:
					e.card.downed = true
					hit += 1
					_emit("downed", {"side": foe, "slot": e.slot, "card": e.card.duplicate(true)})
			if hit > 0:
				_effect(side, c, "Sovereign's arrival Downs %d enem%s" % [hit, "y" if hit == 1 else "ies"], slot)


## Swap a card on the field for its next form (from the hideout when it's there).
## The owner picks ATK or DEF for the new form.
func _promote(side: String, slot: int, reason: String) -> void:
	var s: Dictionary = sides[side]
	var old = card_at(side, slot)
	if old == null or s.promoted.has(slot) or old.get("subtype") != "striver":   # only Strivers level up
		return
	var to_id := CardDB.next_form(old.id)
	if to_id == "":
		return
	s.promoted[slot] = true
	var preview := CardDB.get_card(to_id)
	_ask(side, "position", "Promote to %s: choose its position" % preview.get("name", to_id), preview, [
		{"id": "atk", "label": "ATK POSITION"}, {"id": "def", "label": "DEF POSITION"},
	], func(pos: String):
		if card_at(side, slot) != old:
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
		promoted.deployed_turn = turn
		s.field[slot] = promoted
		old.mods = []
		old.downed = false
		_clear_status(old)
		s.gutter.append(old)
		_emit("promote", {"side": side, "slot": slot, "from": old.duplicate(true),
			"card": promoted.duplicate(true), "reason": reason})
		_on_deploy(side, slot, promoted)
		if promoted.get("subtype") == "striver" and is_lion(promoted) and not s.mentor_used:
			for e in characters(side):
				if e.card.get("effectKey") == "pride_mentor_draw":
					s.mentor_used = true
					_effect(side, e.card, "Pride Mentor: a Striver promoted — draw 2", e.slot)
					_draw(side)
					_draw(side)
					break)


## King Roan awakens at the start of your turn once you control 4+ LIONS characters or have
## 10+ Authority: he takes a front-row slot (sending any card there to the Gutter).
func _check_awaken(side: String) -> void:
	var s: Dictionary = sides[side]
	if s.leader_state != "dormant":
		return
	var cond: Dictionary = s.leader.get("awakenCondition", {})
	if cond.is_empty():
		return
	var lions := characters(side).filter(func(e): return is_lion(e.card) and not e.card.downed and not e.card.face_down).size()
	if lions < int(cond.get("lions", 99)) and s.authority_max < int(cond.get("authorityThreshold", 99)):
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
	_ask(side, "awaken", "%s AWAKENS! Choose his lane" % s.leader.name, s.leader, options, func(choice: String):
		if choice == "wait":
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
		king.has_attacked = true
		king.deployed_turn = turn
		s.field[slot] = king
		_emit("awaken", {"side": side, "slot": slot, "card": king.duplicate(true)})
		_effect(side, king, "%s takes the street himself" % king.name, slot))


## Recompute ATK/DEF from base stats, temporary mods and passives, and report them.
func _recalc() -> void:
	var values := {}
	for side in sides:
		var s: Dictionary = sides[side]
		var foe_has_downed := characters(other(side)).any(func(e): return e.card.downed)
		var lions := lion_count(side)
		var roan: bool = s.leader_state == "dormant" and s.leader.get("effectKey") == "king_roan_leader" and lions >= 2
		var auras := _auras(side)
		values[side] = {}
		for slot in FRONT:
			var c = s.field[slot]
			if c == null:
				continue
			var atk: int = c.base_attack
			var df: int = c.base_defense
			for m in c.mods:
				atk += int(m.get("atk", 0))
				df += int(m.get("def", 0))
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
			for adj in [slot - 1, slot + 1]:
				if adj in FRONT and s.field[adj] != null and s.field[adj].get("effectKey") == "bulwark":
					df += 400
			c.attack = maxi(0, atk)
			c.defense = maxi(0, df)
			values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense, c.face_down, statuses(c)]
	_emit("stats", {"values": values})


# ── Card effects from data (Card Forge) ──────────────────────────────────────
# A card's "effects" list holds building blocks: {when, do, target, atk, def, amount, until,
# clan, kind, if, n, once}. shared/duel/DuelState.js runs exactly the same rules.
#   when:   deploy | attack | defend | ko | down | direct | self_downed | self_ko |
#           ally_deployed | turn_start | turn_end | passive
#   do:     buff | down | ko | stand | bounce | force_def | stun | shield | pierce | draw |
#           search | recover | discard | mill | damage | heal | drain | authority | promote |
#           attack_again | poison | burn | bleed | shock | freeze | stasis
#   amount: poison (ATK lost per turn), burn (Morale lost per turn), bleed (ATK/DEF lost per
#           brawl), shock (damage to DEF: Downs the target if it is at least its DEF)
#   target: self | ally | allies | enemy | enemies | attacker (defend only)
#   clan:   only characters with this clan tag (for ally_deployed: the deployed ally's clan)
#   kind:   search / recover: "" | gang_member | hustle | ambush
#   if:     "" | vs_def | vs_downed | vs_atk | allies | alone | adjacent | foe_downed |
#           hand_le | morale_le | foe_morale_le | enemies_ge | gutter_ge | leader_dormant
#   n:      the number for allies / hand_le / morale_le / foe_morale_le / enemies_ge / gutter_ge
#   once:   true = once per turn

func _fx(c, when: String) -> Array:
	var out: Array = []
	if c == null or in_stasis(c):   # a character in STASIS is frozen in time: no effects
		return out
	for e in c.get("effects", []):
		if e is Dictionary and str(e.get("when", "")) == when:
			out.append(e)
	return out


## Once-per-turn effects: true the first time this turn (and marks it used), false after.
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
func _fx_pool(side: String, e: Dictionary, except: int, standing_only := false) -> Array:
	var clan := str(e.get("clan", ""))
	return characters(side).filter(func(x):
		return x.slot != except and (clan == "" or x.card.get("clanTag") == clan) \
			and not (standing_only and x.card.downed))


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
		"allies":
			return _fx_pool(side, e, slot).size() >= n
		"alone":
			return characters(side).all(func(x): return x.slot == slot)
		"adjacent":
			return _fx_pool(side, e, slot).any(func(x): return absi(x.slot - slot) == 1)
		"foe_downed":
			return characters(other(side)).any(func(x): return x.card.downed)
		"hand_le":
			return s.hand.size() <= n
		"morale_le":
			return s.morale <= n
		"foe_morale_le":
			return sides[other(side)].morale <= n
		"enemies_ge":
			return characters(other(side)).size() >= n
		"gutter_ge":
			return s.gutter.size() >= n
		"leader_dormant":
			return s.leader_state == "dormant"
	return true


## Run a card's effects for a trigger. \`def\` is the other card involved (the defender for
## attack / ko / down, the attacker for defend, the new ally for ally_deployed).
func _run_fx(side: String, slot: int, c: Dictionary, when: String, def = null, vs := {}) -> void:
	var k := 0
	for e in _fx(c, when):
		k += 1
		if winner != "":
			return
		if when == "ally_deployed" and str(e.get("clan", "")) != "" and (def == null or def.get("clanTag") != str(e.get("clan", ""))):
			continue
		if _fx_cond(side, slot, e, def) and _fx_once(c, "%s%d" % [when, k], e):
			_do_fx(side, slot, c, e, vs)


func _do_fx(side: String, slot: int, c: Dictionary, e: Dictionary, vs := {}) -> void:
	var foe := other(side)
	var s: Dictionary = sides[side]
	var n: int = maxi(1, int(e.get("amount", 1)))
	match str(e.get("do", "")):
		"buff":
			var mod := {"atk": int(e.get("atk", 0)), "def": int(e.get("def", 0)),
				"until_turn": turn + (1 if str(e.get("until", "turn")) == "next_turn" else 0)}
			var label := _stat_text(mod)
			var fn := func(x: Dictionary) -> String:
				x.card.mods.append(mod.duplicate())
				return "%s: %s" % [x.card.name, label]
			_fx_apply(side, slot, c, e, vs, "any", label, fn, "%s: %s to %%s" % [c.name, label])
		"down":
			var fn := func(x: Dictionary) -> String:
				x.card.downed = true
				_emit("downed", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s Downs %s" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "standing", "DOWN", fn, "%s Downs %%s" % c.name)
		"ko":
			var fn := func(x: Dictionary) -> String:
				var name: String = x.card.name
				_ko(x.side, x.slot)
				return "%s KOs %s" % [c.name, name]
			_fx_apply(side, slot, c, e, vs, "any", "KO", fn, "%s KOs %%s" % c.name)
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
		"force_def":
			var fn := func(x: Dictionary) -> String:
				x.card.position = "def"
				x.card.position_turn = turn
				_emit("position", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
				return "%s forces %s into DEF" % [c.name, x.card.name]
			_fx_apply(side, slot, c, e, vs, "attackers", "force into DEF", fn, "%s forces %%s into DEF" % c.name)
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
		"draw":
			_effect(side, c, "%s: draw %d" % [c.name, n], slot)
			for i in n:
				_draw(side)
		"search":
			var deck: Array = s.deck
			for i in range(deck.size() - 1, -1, -1):
				if _fx_kind_ok(deck[i], e):
					var found: Dictionary = deck.pop_at(i)
					s.hand.append(found)
					_effect(side, c, "%s: searches the deck for %s" % [c.name, found.name], slot)
					_emit("draw", {"side": side, "card": found.duplicate(true), "opening": false})
					return
			_effect(side, c, "%s: nothing to find in the deck" % c.name, slot)
		"recover":
			var gutter: Array = s.gutter
			for i in range(gutter.size() - 1, -1, -1):
				if gutter[i] != c and _fx_kind_ok(gutter[i], e):
					var back: Dictionary = gutter.pop_at(i)
					back.downed = false
					back.mods = []
					s.hand.append(back)
					_effect(side, c, "%s: %s returns to the hand" % [c.name, back.name], slot)
					_emit("recover", {"side": side, "card": back.duplicate(true)})
					return
		"discard":
			var k: int = mini(n, sides[foe].hand.size())
			if k > 0:
				_effect(side, c, "%s: your opponent discards %d" % [c.name, k], slot)
				_ask_discard(foe, k, Callable())
		"mill":
			var fd: Array = sides[foe].deck
			var lost := mini(n, fd.size())
			if lost > 0:
				_effect(side, c, "%s: your opponent loses %d card%s from the deck" % [c.name, lost, "" if lost == 1 else "s"], slot)
				for i in lost:
					var milled: Dictionary = fd.pop_back()
					sides[foe].gutter.append(milled)
					_emit("mill", {"side": foe, "card": milled.duplicate(true)})
		"damage":
			_effect(side, c, "%s: %d Morale damage" % [c.name, n], slot)
			_damage(foe, n)
		"heal":
			_heal(side, c, n, slot)
		"drain":
			_effect(side, c, "%s drains %d Morale" % [c.name, n], slot)
			_damage(foe, n)
			if winner == "":
				_heal(side, c, n, slot)
		"authority":
			s.authority += n
			_effect(side, c, "%s: +%d Authority this turn" % [c.name, n], slot)
			_emit("authority", {"side": side, "value": s.authority, "max": s.authority_max, "delta": n})
		"promote":
			if card_at(side, slot) == c:
				_promote(side, slot, c.name)
		"attack_again":
			if card_at(side, slot) == c and c.has_attacked:
				c.has_attacked = false
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
				if not x.card.downed and n >= int(x.card.get("defense", 0)):
					x.card.downed = true
					_emit("downed", {"side": x.side, "slot": x.slot, "card": x.card.duplicate(true)})
					return "%s SHOCKS %s: it goes Down" % [c.name, x.card.name]
				x.card.mods.append({"atk": 0, "def": -n, "until_turn": turn})
				_recalc()
				return "%s SHOCKS %s: -%d DEF this turn" % [c.name, x.card.name, n]
			_fx_apply(side, slot, c, e, vs, "any", "SHOCK", fn, "%s shocks %%s" % c.name)
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


## The last turn of "through its owner's next turn" for a character on `side`.
func _owner_next_turn(side: String) -> int:
	return turn + (2 if side == active else 1)


func _clear_status(c: Dictionary) -> void:
	for k in STATUS_KEYS:
		c.erase(k)


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
	var foe := other(side)
	var target := str(e.get("target", "self"))
	var pick := func(x) -> bool:
		match pool_kind:
			"standing":
				return not x.card.downed
			"downed":
				return x.card.downed
			"attackers":
				return x.card.position == "atk" and not x.card.downed
		return true
	var entries: Array = []
	match target:
		"self":
			if card_at(side, slot) == c:
				entries = [{"side": side, "slot": slot, "card": c}]
		"attacker":
			if not vs.is_empty() and card_at(vs.side, vs.slot) == vs.card:
				entries = [{"side": vs.side, "slot": vs.slot, "card": vs.card}]
		"ally", "allies":
			entries = _fx_pool(side, e, slot).map(func(x): return {"side": side, "slot": x.slot, "card": x.card})
		"enemy", "enemies":
			entries = _fx_pool(foe, e, -99).map(func(x): return {"side": foe, "slot": x.slot, "card": x.card})
	entries = entries.filter(func(x): return pick.call(x) and x.card.get("cardType") != "leader" and not in_stasis(x.card))
	if target == "ally" or target == "enemy":
		var best_first := func(a: Dictionary, b: Dictionary) -> bool:
			var va := _target_value(side, e, a)
			var vb := _target_value(side, e, b)
			return va > vb or (va == vb and a.slot < b.slot)
		entries.sort_custom(best_first)
		var on := side if target == "ally" else foe
		var cb := func(x: Dictionary): _effect(side, c, fn.call(x), slot)
		_ask_target(side, "fx", "%s: choose %s (%s)" % [c.name, "an ally" if target == "ally" else "an enemy", what], c,
			entries, on, cb)
	elif target == "allies" or target == "enemies":
		var count := entries.size()
		for x in entries:
			fn.call(x)
		if count > 0:
			var who := ("%d of your characters" % count) if target == "allies" else ("%d enem%s" % [count, "y" if count == 1 else "ies"])
			_effect(side, c, all_text % who, slot)
	else:
		for x in entries:
			_effect(side, c, fn.call(x), slot)


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
	var kind := str(e.get("kind", ""))
	var clan := str(e.get("clan", ""))
	return (kind == "" or card.get("cardType") == kind) and (clan == "" or card.get("clanTag") == clan) \
		and card.get("cardType") != "leader"


func _heal(side: String, c: Dictionary, n: int, slot: int) -> void:
	var s: Dictionary = sides[side]
	var gain: int = mini(n, START_MORALE - s.morale)
	if gain > 0:
		s.morale += gain
		_effect(side, c, "%s: +%d Morale" % [c.name, gain], slot)
		_emit("heal", {"side": side, "amount": gain, "morale": s.morale})


## A character goes back to its owner's hand, reset.
func _bounce(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	c.downed = false
	c.mods = []
	c.position = "atk"
	c.face_down = false
	c.has_attacked = false
	for k in ["shield", "stun_until", "down_turns", "kings_test", "fx_used"]:
		c.erase(k)
	_clear_status(c)
	sides[side].hand.append(c)
	_emit("bounce", {"side": side, "slot": slot, "card": c.duplicate(true)})


## Passive buffs active on \`side\`: [[source slot (-1 = dormant leader), effect], ...]
func _auras(side: String) -> Array:
	var s: Dictionary = sides[side]
	var out: Array = []
	for x in characters(side):
		if x.card.face_down:
			continue
		for e in _fx(x.card, "passive"):
			if str(e.get("do", "")) == "buff" and _fx_cond(side, x.slot, e, null):
				out.append([x.slot, e])
	if s.leader_state == "dormant" and s.leader != null:
		for e in _fx(s.leader, "passive"):
			if str(e.get("do", "")) == "buff" and _fx_cond(side, -1, e, null):
				out.append([-1, e])
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


# ── Turn flow ────────────────────────────────────────────────────────────────

func _begin_turn() -> void:
	var s: Dictionary = sides[active]
	s.promoted = {}
	s.mentor_used = false
	_set_phase("upkeep")
	_emit("turn", {"side": active, "turn": turn})
	# Authority grows once both players have had a turn
	if turn > 2:
		s.authority_max = mini(MAX_AUTHORITY, s.authority_max + 1)
		s.authority = s.authority_max
		_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": 1})
	# Going second is a disadvantage (in CPU mirror matches the first player won ~70%);
	# one extra Authority on that player's first turn brings it close to even
	if turn == 2 and SECOND_PLAYER_AUTHORITY > 0:
		s.authority = s.authority_max + SECOND_PLAYER_AUTHORITY
		_emit("authority", {"side": active, "value": s.authority, "max": s.authority_max, "delta": SECOND_PLAYER_AUTHORITY})
	if turn > 1:
		_draw(active)
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


func _end_turn() -> void:
	for e in characters(active):
		_run_fx(active, e.slot, e.card, "turn_end")
	if winner != "":
		return
	var s: Dictionary = sides[active]
	for c in s.field:
		if c != null:
			c.has_attacked = false
	s.brutus_bonus = 0
	for side in sides:
		for c in sides[side].field:
			if c != null:
				c.mods = c.mods.filter(func(m): return m.until_turn > turn)
	active = other(active)
	turn += 1
	_begin_turn()


func _set_phase(p: String) -> void:
	phase = p
	_emit("phase", {"phase": p, "side": active})


# ── Prompts ──────────────────────────────────────────────────────────────────

func _ask(side: String, key: String, prompt: String, card: Dictionary, options: Array, cb: Callable) -> void:
	var ask := {"kind": "choose", "side": side, "key": key, "prompt": prompt, "options": options,
		"card": card.duplicate(true), "cb": cb}
	if _in_answer:
		_new_asks.append(ask)
	else:
		_asks.append(ask)


## Pick one character from `entries` ([{slot, card}], best first). One option resolves at once.
func _ask_target(side: String, key: String, prompt: String, source: Dictionary, entries: Array,
		target_side: String, cb: Callable) -> void:
	if entries.is_empty():
		return
	if entries.size() == 1:
		cb.call(entries[0])
		return
	var options: Array = []
	for e in entries:
		options.append({"id": str(e.slot), "label": "%s  (%d / %d)" % [str(e.card.name).to_upper(), e.card.attack, e.card.defense],
			"side": target_side, "slot": e.slot})
	_ask(side, key, prompt, source, options, func(choice: String):
		for e in entries:
			if str(e.slot) == choice and card_at(target_side, e.slot) == e.card:
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


func _ask_discard(side: String, count: int, then: Callable) -> void:
	var ask := {"kind": "discard", "side": side, "count": count, "cb": then,
		"prompt": "Choose %d card%s to discard" % [count, "" if count == 1 else "s"]}
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
		if ask.kind == "discard" and sides[ask.side].hand.is_empty():
			if ask.cb.is_valid():
				_run_answer(ask.cb)
			continue
		pending = ask
		_emit("prompt", _prompt_event(ask))


static func _prompt_event(ask: Dictionary) -> Dictionary:
	var ev := ask.duplicate()
	ev.erase("cb")
	return ev


# ── Helpers ──────────────────────────────────────────────────────────────────

func _draw(side: String, opening := false) -> void:
	var s: Dictionary = sides[side]
	if s.deck.is_empty():
		# Decked out: a player who has to draw from an empty deck loses
		if winner == "":
			_end(other(side), "deck_out")
		return
	var c: Dictionary = s.deck.pop_back()
	s.hand.append(c)
	_emit("draw", {"side": side, "card": c.duplicate(true), "opening": opening})


func _discard_at(side: String, i: int) -> void:
	var c: Dictionary = sides[side].hand.pop_at(i)
	sides[side].gutter.append(c)
	_emit("discard", {"side": side, "card": c.duplicate(true)})


func _spend(side: String, amount: int) -> void:
	if amount <= 0:
		return
	var s: Dictionary = sides[side]
	s.authority = maxi(0, s.authority - amount)
	_emit("authority", {"side": side, "value": s.authority, "max": s.authority_max, "delta": -amount})


func _effect(side: String, c: Dictionary, text: String, slot := -1) -> void:
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


func _promotable_strivers(side: String) -> Array:
	var out := characters(side).filter(func(e): return is_lion(e.card) and e.card.get("subtype") == "striver" \
		and not e.card.downed and not e.card.face_down and not sides[side].promoted.has(e.slot) \
		and CardDB.next_form(e.card.id) != "")
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
	return out
