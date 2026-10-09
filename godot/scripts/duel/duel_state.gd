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


func can_summon(side: String, c: Dictionary, slot: int) -> bool:
	if not can_deploy_now(side) or c.get("cardType") != "gang_member":
		return false
	if not slot in FRONT or sides[side].field[slot] != null:
		return false
	return sides[side].authority >= c.authority


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


func can_attack_with(side: String, slot: int) -> bool:
	if not can_act(side) or phase != "brawl" or turn == 1 or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	return c != null and c.position == "atk" and not c.downed and not c.has_attacked and not c.face_down


## Attack targets: any enemy character; DIRECT when none of them is still standing (an empty
## front row, or only Downed characters); and the enemy LEADER whenever it is dormant.
func attack_targets(side: String) -> Array:
	var foe := other(side)
	var foes := characters(foe)
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
	return c != null and not c.downed and not c.has_attacked \
		and c.deployed_turn != turn and c.get("position_turn", 0) != turn


## Maya Lv.1/2: promote while you control another LIONS card with equal or higher Authority.
func can_promote(side: String, slot: int) -> bool:
	if not can_deploy_now(side) or not slot in FRONT:
		return false
	var c = card_at(side, slot)
	if c == null or c.get("ability") != "maya_promote" or c.face_down or c.downed:
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
	if c == null or c.get("ability") != "maya_buff" or c.face_down or c.downed:
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
			ok = _summon(side, int(a.uid), int(a.slot), str(a.get("position", "atk")))
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


func _summon(side: String, uid: int, slot: int, position: String) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_summon(side, sides[side].hand[i], slot):
		return false
	var c: Dictionary = sides[side].hand.pop_at(i)
	_spend(side, c.authority)
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
	if is_lion(att) and sides[side].brutus_bonus > 0:
		ctx.bonus += sides[side].brutus_bonus
		sides[side].brutus_bonus = 0
		_effect(side, att, "Brutus's momentum: +300 ATK", from)
	_atk_lane_move(ctx)
	return true


## Viper Lv.2/3: may slide to an adjacent empty lane before the brawl.
func _atk_lane_move(ctx: Dictionary) -> void:
	var att: Dictionary = ctx.att
	if att.get("effectKey") in ["viper_lv2", "viper_lv3"]:
		var lanes := _free_adjacent(ctx.side, ctx.from)
		if not lanes.is_empty():
			_ask_lane(ctx.side, att, ctx.from, lanes, "%s: move to an adjacent lane before the brawl?" % att.name,
				func(to: int):
					ctx.from = to
					_atk_redirect(ctx))
			return
	_atk_redirect(ctx)


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
		return
	if target == LEADER:
		_hit_leader(ctx)
		return

	var def: Dictionary = card_at(foe, target)
	var bonus: int = ctx.bonus + _brawl_bonus(side, from, att, def)
	if def.get("effectKey") == "bulwark":
		bonus -= 300
		_effect(foe, def, "Bulwark: the attacker loses 300 ATK", target)

	var def_was_downed: bool = def.downed
	var vs_def: bool = def.downed or def.position == "def"
	var a_val: int = maxi(0, att.attack + bonus)
	var d_val: int = def.defense if vs_def else def.attack
	_emit("clash", {"side": side, "from": from, "target": target, "att": a_val, "def": d_val,
		"vs": "DEF" if vs_def else "ATK"})

	var result := ""
	if vs_def:
		if a_val > d_val:
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
		elif result == "downed":
			_on_down(side, from, att)


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
	if c.downed:
		if is_lion(c) and c.get("subtype") == "striver" and _spring_kings_test(side, slot, c):
			return "saved"
		_ko(side, slot)
		return "ko"
	c.downed = true
	_emit("downed", {"side": side, "slot": slot, "card": c.duplicate(true)})
	return "downed"


func _ko(side: String, slot: int) -> void:
	var c: Dictionary = card_at(side, slot)
	sides[side].field[slot] = null
	c.downed = false
	c.mods = []
	sides[side].gutter.append(c)
	_emit("ko", {"side": side, "slot": slot, "card": c.duplicate(true)})


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
		elif key in ["hunter_lv3", "viper_lv3"]:
			att.has_attacked = false
			_effect(side, att, "%s may attack again this turn" % att.name, slot)
	if key == "viper_lv3":
		var lanes := _free_adjacent(side, slot)
		if not lanes.is_empty():
			_ask_lane(side, att, slot, lanes, "Viper Lv.3: move to an adjacent lane after the KO?", func(_to: int): pass)


func _on_down(side: String, slot: int, att: Dictionary) -> void:
	var key: String = att.get("effectKey", "")
	match key:
		"brutus_enter":
			sides[side].brutus_bonus = 300
			_effect(side, att, "Brutus: your next LIONS attacker gains +300 ATK", slot)
		"viper_lv1", "viper_lv2":
			_promote(side, slot, att.name)
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
	if old == null or s.promoted.has(slot):
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
			for adj in [slot - 1, slot + 1]:
				if adj in FRONT and s.field[adj] != null and s.field[adj].get("effectKey") == "bulwark":
					df += 400
			c.attack = maxi(0, atk)
			c.defense = maxi(0, df)
			values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense, c.face_down]
	_emit("stats", {"values": values})


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
	# off), then gets back up in DEF position at the start of its owner's turn. It can't
	# switch back to ATK until the turn after.
	for e in characters(active):
		if not e.card.downed:
			e.card.erase("down_turns")
		elif int(e.card.get("down_turns", 0)) >= 1:
			e.card.downed = false
			e.card.erase("down_turns")
			e.card.position = "def"
			e.card.position_turn = turn
			_emit("stand", {"side": active, "slot": e.slot, "card": e.card.duplicate(true)})
		else:
			e.card.down_turns = 1
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


## Move a card to one of `lanes` (adjacent empty front slots), or stay.
func _ask_lane(side: String, c: Dictionary, from: int, lanes: Array, prompt: String, then: Callable) -> void:
	var options: Array = [{"id": "stay", "label": "STAY"}]
	for to in lanes:
		options.append({"id": str(to), "label": "MOVE %s" % ("LEFT" if (to < from) == (side == "player") else "RIGHT"),
			"side": side, "slot": to})
	if _lane_value(side, c, lanes[0]) > _lane_value(side, c, from):
		options.push_front(options.pop_at(1))
	_ask(side, "lane", prompt, c, options, func(choice: String):
		var at := from
		if choice != "stay" and card_at(side, from) == c and card_at(side, int(choice)) == null:
			at = int(choice)
			sides[side].field[from] = null
			sides[side].field[at] = c
			_emit("move", {"side": side, "from": from, "to": at, "card": c.duplicate(true)})
		then.call(at))


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


func _free_adjacent(side: String, slot: int) -> Array:
	var out: Array = []
	for adj in [slot - 1, slot + 1]:
		if adj in FRONT and card_at(side, adj) == null:
			out.append(adj)
	return out


## How much a lane helps a card: neighbours that buff it (LIONS for Pride Runner, Bulwark).
func _lane_value(side: String, c: Dictionary, slot: int) -> int:
	var v := 0
	for adj in [slot - 1, slot + 1]:
		if adj in FRONT:
			var n = card_at(side, adj)
			if n != null and n != c:
				v += 1 if is_lion(n) else 0
				v += 2 if n.get("effectKey") == "bulwark" else 0
	return v


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
