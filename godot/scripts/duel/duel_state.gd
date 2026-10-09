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
## Ported from client/scenes/DuelScene.js and client/cards/BrawlPhase.js.

const START_MORALE := 6000
const MAX_AUTHORITY := 15
const HAND_LIMIT := 9
const OPENING_HAND := 5
const FRONT := [0, 1, 2, 3, 4]   # character slots
const BACK := [5, 6, 7, 8, 9]    # ambush slots

var turn := 1
var active := "player"
var phase := "upkeep"
var winner := ""
var pending := {}   # a choice the game is waiting on: {kind = "discard", side, count, then}
var sides := {}
var rng := RandomNumberGenerator.new()

var _events: Array = []
var _uid := 0


## decks/hideouts: {"player": [card ids], "opponent": [...]}; leaders: {"player": id, ...}
func _init(decks: Dictionary, hideouts: Dictionary, leaders: Dictionary, first := "player", seed_value := 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	active = first
	for side in ["player", "opponent"]:
		var deck: Array = []
		for id in decks[side]:
			deck.append(make_card(id))
		_shuffle(deck)
		var hideout: Array = []
		for id in hideouts.get(side, []):
			hideout.append(make_card(id))
		var field: Array = []
		field.resize(10)
		var leader_id: String = leaders.get(side, "")
		sides[side] = {
			"morale": START_MORALE, "authority": 1, "authority_max": 1,
			"deck": deck, "hand": [], "field": field, "gutter": [], "hideout": hideout,
			"leader": make_card(leader_id) if leader_id != "" else null,
			"brutus_bonus": 0, "promoted": {}, "mentor_used": false,
		}


func make_card(id: String) -> Dictionary:
	var c: Dictionary = CardDB.get_card(id).duplicate(true)
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
	c.mods = []   # temporary buffs/debuffs: {atk, def, until_turn}
	return c


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


## Target slots for an attack; [-1] means a direct attack (no enemy characters).
func attack_targets(side: String) -> Array:
	var foes := characters(other(side))
	if foes.is_empty():
		return [-1]
	return foes.map(func(e): return e.slot)


## Maya's ability: promote while you control another LIONS card with equal or higher Authority.
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


# ── Actions ──────────────────────────────────────────────────────────────────

func start() -> void:
	for i in OPENING_HAND:
		_draw(active, true)
		_draw(other(active), true)
	_begin_turn()


func do_action(side: String, a: Dictionary) -> bool:
	if winner != "":
		return false
	match a.get("kind", ""):
		"summon":
			return _summon(side, int(a.uid), int(a.slot), str(a.get("position", "atk")))
		"set":
			return _set_ambush(side, int(a.uid), int(a.slot))
		"hustle":
			return _hustle(side, int(a.uid))
		"attack":
			return _attack(side, int(a.from), int(a.target))
		"promote":
			if not can_promote(side, int(a.slot)):
				return false
			_promote(side, int(a.slot), "Maya")
			_recalc()
			return true
		"discard":
			return _choose_discard(side, int(a.uid))
		"next":
			return _next_phase(side)
	return false


func _summon(side: String, uid: int, slot: int, position: String) -> bool:
	var i := _hand_index(side, uid)
	if i < 0 or not can_summon(side, sides[side].hand[i], slot):
		return false
	var c: Dictionary = sides[side].hand.pop_at(i)
	_spend(side, c.authority)
	c.position = "def" if position == "def" else "atk"
	c.face_down = c.position == "def"   # set in DEF = face-down, like Yu-Gi-Oh
	c.has_attacked = false
	sides[side].field[slot] = c
	_emit("summon", {"side": side, "slot": slot, "card": c.duplicate(true)})
	if not c.face_down:
		_on_deploy(side, slot, c)
	_recalc()
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
				_ask_discard(side, 1, "")
		"lion_rescue":
			var e: Dictionary = _strongest(_downed_lions(side))
			e.card.downed = false
			_emit("stand", {"side": side, "slot": e.slot, "card": e.card.duplicate(true)})
			_effect(side, c, "%s stands back up" % e.card.name)
		"blood_scent":
			var e: Dictionary = _strongest(_promotable_strivers(side))
			_effect(side, c, "%s's promotion is fulfilled" % e.card.name)
			_promote(side, e.slot, "Blood Scent")
	_recalc()
	return true


func _attack(side: String, from: int, target: int) -> bool:
	if not can_attack_with(side, from) or not target in attack_targets(side):
		return false
	var foe := other(side)
	var att: Dictionary = card_at(side, from)
	att.has_attacked = true
	_emit("attack", {"side": side, "from": from, "target": target, "card": att.duplicate(true)})

	var bonus := 0
	if is_lion(att) and sides[side].brutus_bonus > 0:
		bonus += sides[side].brutus_bonus
		sides[side].brutus_bonus = 0
		_effect(side, att, "Brutus's momentum: +300 ATK", from)

	if target == -1:
		var dmg: int = att.attack + bonus
		_emit("clash", {"side": side, "from": from, "target": -1, "att": dmg, "def": 0, "vs": "DIRECT"})
		_damage(foe, dmg)
		_recalc()
		return true

	var def: Dictionary = card_at(foe, target)
	if def.face_down:
		def.face_down = false
		_emit("flip", {"side": foe, "slot": target, "card": def.duplicate(true)})

	var amb := _spring_ambush(foe, side, from, def)
	if amb.get("negated", false):
		_recalc()
		return true
	bonus += int(amb.get("att_mod", 0)) + _brawl_bonus(side, from, att, def)
	if def.get("effectKey") == "bulwark":
		bonus -= 300
		_effect(foe, def, "Bulwark: attacker loses 300 ATK", target)

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
	_recalc()
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
				_ask_discard(side, extra, "end_turn")
			else:
				_end_turn()
		_:
			return false
	return true


func _choose_discard(side: String, uid: int) -> bool:
	if pending.get("kind") != "discard" or pending.side != side:
		return false
	var i := _hand_index(side, uid)
	if i < 0:
		return false
	_discard_at(side, i)
	pending.count -= 1
	if pending.count <= 0:
		var then: String = pending.get("then", "")
		pending = {}
		if then == "end_turn":
			_end_turn()
	return true


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
	if turn > 1:
		_draw(active)
	# King's Test survivors promote at the start of their owner's next turn
	for e in characters(active):
		if e.card.get("kings_test", false):
			e.card.erase("kings_test")
			_promote(active, e.slot, "King's Test")
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
		winner = other(side)
		_emit("game_over", {"winner": winner})


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
	sides[side].brutus_bonus = 300 if key == "brutus_enter" else sides[side].brutus_bonus
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
				for e in characters(other(side)):
					if absi(e.slot - target) == 1:
						e.card.mods.append({"def": -500, "until_turn": turn})
	if key in ["hunter_lv2", "hunter_lv3"]:
		var standing := characters(other(side)).filter(func(e): return not e.card.downed)
		if not standing.is_empty():
			var e: Dictionary = _strongest(standing)
			_effect(side, att, "%s KO: Downs %s" % [att.name, e.card.name], slot)
			e.card.downed = true
			_emit("downed", {"side": other(side), "slot": e.slot, "card": e.card.duplicate(true)})
	if was_downed:
		if key in ["hunter_lv1", "hunter_lv2"]:
			_promote(side, slot, att.name)
		elif key in ["hunter_lv3", "viper_lv3"]:
			att.has_attacked = false
			_effect(side, att, "%s may attack again" % att.name, slot)


func _on_down(side: String, slot: int, att: Dictionary) -> void:
	var key: String = att.get("effectKey", "")
	match key:
		"brutus_enter":
			sides[side].brutus_bonus = 300
		"viper_lv1", "viper_lv2":
			_promote(side, slot, att.name)
		"debt_collector":
			var foe := other(side)
			if not sides[foe].hand.is_empty():
				_effect(side, att, "Debt Collector: opponent discards 1", slot)
				_discard_at(foe, rng.randi_range(0, sides[foe].hand.size() - 1))


func _spring_ambush(side: String, attacker_side: String, from: int, def: Dictionary) -> Dictionary:
	if not is_lion(def):
		return {}
	for key in ["no_witnesses_ambush", "lion_ambush"]:
		for slot in BACK:
			var a = card_at(side, slot)
			if a == null or a.get("effectKey") != key:
				continue
			_spring(side, slot)
			if key == "no_witnesses_ambush":
				var att: Dictionary = card_at(attacker_side, from)
				_effect(side, a, "No Witnesses: attack negated", slot)
				att.downed = true
				_emit("downed", {"side": attacker_side, "slot": from, "card": att.duplicate(true)})
				return {"negated": true}
			_effect(side, a, "Lion Ambush: attacker loses 1000 ATK", slot)
			return {"att_mod": -1000}
	return {}


func _spring_kings_test(side: String, slot: int, c: Dictionary) -> bool:
	for s in BACK:
		var a = card_at(side, s)
		if a != null and a.get("effectKey") == "kings_test":
			_spring(side, s)
			_effect(side, a, "King's Test: %s survives — promotes next turn" % c.name, s)
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
			if not allies.is_empty():
				var e: Dictionary = _strongest(allies)
				e.card.mods.append({"atk": 500, "until_turn": turn})
				_effect(side, c, "%s gains +500 ATK this turn" % e.card.name, slot)
		"brutus_enter":
			var foes := characters(foe)
			if not foes.is_empty():
				var e: Dictionary = _strongest(foes)
				e.card.mods.append({"atk": -700, "until_turn": turn + 1})
				_effect(side, c, "%s loses 700 ATK" % e.card.name, slot)
		"sovereign":
			var hit := 0
			for e in characters(foe):
				if not e.card.downed and e.card.defense <= 1500:
					e.card.downed = true
					hit += 1
					_emit("downed", {"side": foe, "slot": e.slot, "card": e.card.duplicate(true)})
			if hit > 0:
				_effect(side, c, "Sovereign's arrival Downs %d enemies" % hit, slot)


## Swap a card on the field for its next form (taken from the hideout when it's there).
func _promote(side: String, slot: int, reason: String) -> bool:
	var s: Dictionary = sides[side]
	var old = card_at(side, slot)
	if old == null or s.promoted.has(slot):
		return false
	var to_id := CardDB.next_form(old.id)
	if to_id == "":
		return false
	s.promoted[slot] = true
	var promoted = null
	for i in s.hideout.size():
		if s.hideout[i].id == to_id:
			promoted = s.hideout.pop_at(i)
			break
	if promoted == null:
		promoted = make_card(to_id)
	promoted.position = "atk"
	promoted.face_down = false
	promoted.has_attacked = true   # promotion sickness: sits out the rest of the turn
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
				break
	return true


## Recompute ATK/DEF from base stats, temporary mods and passives, and report them.
func _recalc() -> void:
	var values := {}
	for side in sides:
		var s: Dictionary = sides[side]
		var foe_has_downed := characters(other(side)).any(func(e): return e.card.downed)
		var lions := lion_count(side)
		var roan: bool = s.leader != null and s.leader.get("effectKey") == "king_roan_leader" and lions >= 2
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
			values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense]
	_emit("stats", {"values": values})


# ── Helpers ──────────────────────────────────────────────────────────────────

func _draw(side: String, opening := false) -> void:
	var s: Dictionary = sides[side]
	if s.deck.is_empty():
		return
	var c: Dictionary = s.deck.pop_back()
	s.hand.append(c)
	_emit("draw", {"side": side, "card": c.duplicate(true), "opening": opening})


func _discard_at(side: String, i: int) -> void:
	var c: Dictionary = sides[side].hand.pop_at(i)
	sides[side].gutter.append(c)
	_emit("discard", {"side": side, "card": c.duplicate(true)})


func _ask_discard(side: String, count: int, then: String) -> void:
	pending = {"kind": "discard", "side": side, "count": count, "then": then}
	_emit("prompt_discard", {"side": side, "count": count})


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
	return characters(side).filter(func(e): return e.card.downed and is_lion(e.card))


func _promotable_strivers(side: String) -> Array:
	return characters(side).filter(func(e): return is_lion(e.card) and e.card.get("subtype") == "striver" \
		and not e.card.downed and not e.card.face_down and not sides[side].promoted.has(e.slot) \
		and CardDB.next_form(e.card.id) != "")


func _adjacent_lion(side: String, slot: int) -> bool:
	for adj in [slot - 1, slot + 1]:
		if adj in FRONT and is_lion(card_at(side, adj)):
			return true
	return false


func _strongest(entries: Array) -> Dictionary:
	var best: Dictionary = entries[0]
	for e in entries:
		if e.card.attack > best.card.attack:
			best = e
	return best


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
		}
	return out
