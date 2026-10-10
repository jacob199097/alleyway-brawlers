class_name DuelAI
extends RefCounted
## CPU player. choose() returns the next action for DuelState.do_action(), one at a time,
## so the screen can animate each step.

const SLOT_ORDER := [2, 1, 3, 0, 4]   # deploy toward the middle first
const NO_TARGET := -99


## The starter decks used until the client loads real decks from the server
## (same as _buildTestDeck in DuelScene.js: Lv.1 characters plus all Hustle/Ambush cards).
static func test_setup() -> Dictionary:
	var base: Array = []
	var hideout: Array = []
	var leader := ""
	for id in CardDB.all():
		var c: Dictionary = CardDB.get_card(id)
		match c.cardType:
			"leader":
				if leader == "":
					leader = id
			"gang_member":
				if int(c.level) == 1:
					base.append(id)
				else:
					hideout.append(id)
			_:
				base.append(id)
	var deck: Array = []
	for i in 2:
		deck.append_array(base)
	return {
		"decks": {"player": deck.duplicate(), "opponent": deck.duplicate()},
		"hideouts": {"player": hideout.duplicate(), "opponent": hideout.duplicate()},
		"leaders": {"player": leader, "opponent": leader},
	}

## Difficulty: "easy" misses attacks, picks the first target that works and never sacrifices for
## a Heavy; "normal" is the standard CPU; "hard" sacrifices more readily (preferring Downed or
## weakened characters) and takes even trades that cost it the weaker card.
const LEVELS := ["easy", "normal", "hard"]


static func choose(d: DuelState, side: String, level := "normal") -> Dictionary:
	if d.winner != "":
		return {}
	if not d.pending.is_empty():
		if d.pending.side != side:
			return {}
		if d.pending.kind == "discard":
			return {"kind": "discard", "uid": _weakest(d.sides[side].hand).uid}
		# Prompts list their options best-first for the deciding side
		return {"kind": "choose", "option": d.pending.options[0].id}
	if d.active != side:
		return {}
	var a := {}
	match d.phase:
		"deployment":
			a = _deploy(d, side, level)
		"brawl":
			a = _brawl(d, side, level)
	return a if not a.is_empty() else {"kind": "next"}


static func _deploy(d: DuelState, side: String, level: String) -> Dictionary:
	var s: Dictionary = d.sides[side]
	for slot in DuelState.FRONT:
		if d.can_promote(side, slot):
			return {"kind": "promote", "slot": slot}
	for c in s.hand:
		if d.can_hustle(side, c) and _hustle_useful(d, side, c):
			return {"kind": "hustle", "uid": c.uid}
	var threat := _threat(d, side)
	if level != "easy":
		# Stand up a defender that now out-muscles everything the opponent shows
		for e in d.characters(side):
			var c: Dictionary = e.card
			if c.position == "def" and d.can_change_position(side, e.slot) and c.attack > threat:
				return {"kind": "position", "slot": e.slot}

		# A Heavy is worth a sacrifice when it clearly out-muscles the character we'd give up
		var heavy = null
		for c in s.hand:
			if DuelState.needs_tribute(c) and d.can_summon_somewhere(side, c) and (heavy == null or c.base_attack > heavy.base_attack):
				heavy = c
		if heavy != null:
			var fodder = null
			var fodder_value := 0
			for e in d.characters(side):
				if e.card.get("cardType") == "leader" or d.in_stasis(e.card):
					continue
				var v := _keep_value(e.card)
				if fodder == null or v < fodder_value:
					fodder = e
					fodder_value = v
			var margin := 400 if level == "hard" else 800
			if fodder != null and heavy.base_attack >= fodder_value + margin:
				return {"kind": "summon", "uid": heavy.uid, "slot": fodder.slot, "tribute": fodder.slot,
					"position": "atk" if heavy.base_attack >= threat else "def"}

	var free := SLOT_ORDER.filter(func(i): return s.field[i] == null)
	if not free.is_empty():
		var best = null
		for c in s.hand:
			if d.can_summon(side, c, free[0]):
				if level == "easy":
					best = c
					break
				if best == null or c.base_attack > best.base_attack:
					best = c
		if best != null:
			var pos := "atk" if best.base_attack >= threat else "def"
			return {"kind": "summon", "uid": best.uid, "slot": free[0], "position": pos}

	for slot in DuelState.BACK:
		if s.field[slot] == null:
			for c in s.hand:
				if d.can_set(side, c, slot):
					return {"kind": "set", "uid": c.uid, "slot": slot}
			break
	return {}


static func _brawl(d: DuelState, side: String, level: String) -> Dictionary:
	var foe := DuelState.other(side)
	# Maya Lv.3 buffs an ally before the punches start
	for slot in DuelState.FRONT:
		if d.can_use_ability(side, slot):
			return {"kind": "ability", "slot": slot}
	# Easy and Normal take the first attacker's best hit; Hard picks the best hit of all
	var plan := {}
	var plan_score := 0.0
	for slot in DuelState.FRONT:
		if not d.can_attack_with(side, slot):
			continue
		if level == "easy" and _roll(d, side, slot) < 35:
			continue   # an easy CPU sometimes forgets to attack
		var att: Dictionary = d.card_at(side, slot)
		var targets := d.attack_targets(side)
		var best := NO_TARGET
		var best_score := 0.0
		for t in targets:
			var score := 0.0
			if t == DuelState.DIRECT:
				# Finish the game if this hit does it; otherwise chip the opponent's morale
				score = 100.0 if att.attack >= d.sides[foe].morale else 2.5 + att.attack / 2000.0
			elif t == DuelState.LEADER:
				# Knock out a dormant leader when one hit does it (−1000 morale, no Dormant bonus);
				# chipping its Influence is a last resort
				score = 4.0 if att.attack >= d.sides[foe].leader.influence else 0.5
			else:
				score = _target_score(att, d.card_at(foe, t), level)
			if score > best_score:
				best_score = score
				best = t
				if level == "easy":
					break
		if best != NO_TARGET and level != "hard":
			return {"kind": "attack", "from": slot, "target": best}
		if best != NO_TARGET and best_score > plan_score:
			plan_score = best_score
			plan = {"kind": "attack", "from": slot, "target": best}
	return plan


## How much the CPU wants to attack this enemy character (0 = not worth it).
static func _target_score(att: Dictionary, df: Dictionary, level: String) -> float:
	var score := 0.0
	if df.face_down:
		score = 1.0 if att.attack >= 1600 else 0.0   # unknown DEF: only strong attackers try
	elif df.downed:
		score = 3.0 if att.attack > df.defense else 0.0
	elif df.position == "def":
		score = 2.0 if att.attack > df.defense else 0.0
	elif att.attack > df.attack:
		score = 2.0 + (att.attack - df.attack) / 1000.0
	elif level == "hard" and att.attack == df.attack and att.base_attack < df.base_attack:
		score = 1.5   # both go Down: a trade that costs us the weaker card
	if df.get("shield", false):
		score *= 0.5   # the hit only pops the shield
	return score


## How much a character is worth keeping (lowest = the first to sacrifice for a Heavy).
static func _keep_value(c: Dictionary) -> int:
	if c.downed:
		return -1
	var v: int = c.attack
	if c.has("poison") or c.has("bleed"):
		v -= 500
	return v


## A repeatable 0-99 "dice roll" (the server's CPU must make the same choices).
static func _roll(d: DuelState, side: String, slot: int) -> int:
	return (d.turn * 37 + slot * 53 + d.sides[side].hand.size() * 17) % 100


## The strongest face-up attacker the opponent shows.
static func _threat(d: DuelState, side: String) -> int:
	var threat := 0
	for e in d.characters(DuelState.other(side)):
		if e.card.position == "atk" and not e.card.downed and not e.card.face_down:
			threat = maxi(threat, e.card.attack)
	return threat


## A Card Forge Hustle is worth playing now if at least one of its effects would do something
## (buffing allies needs allies, hitting enemies needs enemies). Hand-written Hustles: always.
static func _hustle_useful(d: DuelState, side: String, c: Dictionary) -> bool:
	var effects: Array = c.get("effects", [])
	if effects.is_empty():
		return true
	var foe := DuelState.other(side)
	var allies := d.characters(side).filter(func(e): return not d.in_stasis(e.card))
	var enemies := d.characters(foe).filter(func(e): return not d.in_stasis(e.card))
	for e in effects:
		var what := str(e.get("do", ""))
		match str(e.get("target", "")):
			"ally", "allies":
				if what == "stand":
					if allies.any(func(x): return x.card.downed):
						return true
				elif not allies.is_empty():
					return true
			"enemy", "enemies":
				if not enemies.is_empty():
					return true
			_:
				if what == "discard":
					if not d.sides[foe].hand.is_empty():
						return true
				else:
					return true
	return false


static func _weakest(hand: Array) -> Dictionary:
	var worst: Dictionary = hand[0]
	for c in hand:
		if c.authority * 1000 + c.base_attack < worst.authority * 1000 + worst.base_attack:
			worst = c
	return worst
