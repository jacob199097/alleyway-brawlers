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
		if c.get("token", false):   # (made only by effects)
			continue
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
		if level == "hard" and d.pending.get("key") == "ambush" and d.pending.options.any(func(o): return o.id == "no") \
				and not _attack_hurts(d, side):
			return {"kind": "choose", "option": "no"}   # this attack fails anyway: keep the Ambush
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
		"regroup":
			if level == "hard":
				a = _brace(d, side)
	return a if not a.is_empty() else {"kind": "next"}


## Hard, before ending its turn: characters in ATK that would lose to an enemy that can attack
## next turn switch to DEF, so a lost brawl costs no Morale. Same as brace in DuelAI.js.
static func _brace(d: DuelState, side: String) -> Dictionary:
	var danger := 0
	for foe in d.foes_of(side):
		for e in d.characters(foe):
			if not e.card.downed and not e.card.get("face_down", false):
				danger = maxi(danger, int(e.card.attack))
	for slot in DuelState.FRONT:
		var c = d.card_at(side, slot)
		if c != null and c.position == "atk" and c.get("cardType") != "leader" and danger > int(c.attack) and d.can_change_position(side, slot):
			return {"kind": "position", "slot": slot}
	return {}


static func _deploy(d: DuelState, side: String, level: String) -> Dictionary:
	var s: Dictionary = d.sides[side]
	for slot in DuelState.FRONT:
		if d.can_promote(side, slot):
			return {"kind": "promote", "slot": slot}
	var act := _activation(d, side, level)
	if not act.is_empty():
		return act
	for c in s.hand:
		if d.can_hustle(side, c) and _hustle_useful(d, side, c):
			return {"kind": "hustle", "uid": c.uid}
	# A Hustle it set on an earlier turn, once it would do something
	for slot in DuelState.BACK:
		var c = s.field[slot]
		if d.set_hustle_slot(side, c) == slot and d.can_hustle(side, c) and _hustle_useful(d, side, c):
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
			# Its sacrifices: the characters least worth keeping (ties: the leftmost lane)
			var n := DuelState.tributes_for(heavy)
			var fodder: Array = d.characters(side).filter(func(e): return d.can_sacrifice(side, e.slot)) 				.map(func(e): return {"slot": e.slot, "v": _keep_value(e.card)})
			fodder.sort_custom(func(x, y): return x.v < y.v or (x.v == y.v and x.slot < y.slot))
			fodder = fodder.slice(0, n)
			var given := 0
			for f in fodder:
				given += int(f.v)
			var margin := 400 if level == "hard" else 800
			if fodder.size() == n and heavy.base_attack >= given + margin:
				return {"kind": "summon", "uid": heavy.uid, "slot": fodder[0].slot, "tributes": fodder.map(func(f): return f.slot),
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
	elif level != "easy":
		# Front row full: deploy over the character least worth keeping, for a clearly stronger one
		# (a Downed one counts half: it stands back up, if it isn't finished off first)
		var worth := func(c: Dictionary) -> int: return int(c.attack) / 2 if c.downed else _keep_value(c)
		var mine: Array = d.characters(side).filter(func(e): return d.can_sacrifice(side, e.slot)) 			.map(func(e): return {"slot": e.slot, "v": worth.call(e.card)})
		mine.sort_custom(func(x, y): return x.v < y.v or (x.v == y.v and x.slot < y.slot))
		if not mine.is_empty():
			var weakest: Dictionary = mine[0]
			var best = null
			for c in s.hand:
				if d.can_summon(side, c, weakest.slot, weakest.slot) and (best == null or c.base_attack > best.base_attack):
					best = c
			if best != null and best.base_attack >= int(weakest.v) + (400 if level == "hard" else 800):
				return {"kind": "summon", "uid": best.uid, "slot": weakest.slot, "tributes": [weakest.slot],
					"position": "atk" if best.base_attack >= threat else "def"}

	for slot in DuelState.BACK:
		if s.field[slot] == null:
			# Ambushes first; then a Hustle it couldn't use now, to activate when it would do something
			for kind in ["ambush", "hustle"]:
				for c in s.hand:
					if c.cardType == kind and d.can_set(side, c, slot):
						return {"kind": "set", "uid": c.uid, "slot": slot}
			break
	return {}


## Activated abilities (Card Forge "Activate"): use one when it has something to work on and its
## cost is cheap enough. The CPU never sacrifices its own characters, and only gives up an attack
## ("exhaust") with a character that can't attack anyway.
## Whether the attack on one of side's characters (an Ambush may answer it) would beat it.
static func _attack_hurts(d: DuelState, side: String) -> bool:
	var ctx: Dictionary = d._attack_ctx
	if ctx.is_empty() or ctx.foe != side:
		return true
	var df = d.card_at(side, int(ctx.target))
	if df == null:
		return true
	var guard: int = df.defense if df.downed or df.position == "def" else df.attack
	return int(ctx.att.attack) + int(ctx.bonus) >= guard


## An effect on every character (target "all") from the card in slot: worth it when it hits more of
## the opponents' characters than the CPU's own (not counting that card). Same as allWorth in DuelAI.js.
static func _all_worth(d: DuelState, side: String, slot: int) -> bool:
	var mine := d.characters(side).filter(func(x): return x.slot != slot and not d.in_stasis(x.card)).size()
	var theirs := d._enemy_chars(side).filter(func(x): return not d.in_stasis(x.card)).size()
	return theirs > mine


static func _activation(d: DuelState, side: String, level := "normal") -> Dictionary:
	var s: Dictionary = d.sides[side]
	for slot in DuelState.FRONT:
		for k in d.activations(side, slot):
			var e: Dictionary = d._fx(d.card_at(side, slot), "activate")[k - 1]
			var n: int = maxi(1, int(e.get("cost_n", 1)))
			var cost := str(e.get("cost", ""))
			if not d.fx_has_targets(side, slot, e):
				continue
			if str(e.get("target", "")) == "all" and not _all_worth(d, side, slot):
				continue
			if cost == "sacrifice":
				# Hard: when the one it would give up (the weakest, as the prompt offers) is Downed or weak
				if level != "hard":
					continue
				var mine: Array = d.characters(side).filter(func(x): return x.slot != slot)
				mine.sort_custom(func(a, b): return DuelState._attack_value(a.card) < DuelState._attack_value(b.card) \
					or (DuelState._attack_value(a.card) == DuelState._attack_value(b.card) and a.slot < b.slot))
				if mine.is_empty() or _keep_value(mine[0].card) > 600:
					continue
			if cost == "morale" and s.morale <= n * 3:
				continue
			if cost == "discard" and s.hand.size() < n + 2:
				continue
			if cost == "exhaust" and (d.phase != "brawl" or d.can_attack_with(side, slot)):
				continue
			return {"kind": "activate", "slot": slot, "fx": k}
	return {}


static func _brawl(d: DuelState, side: String, level: String) -> Dictionary:
	# Maya Lv.3 buffs an ally before the punches start
	for slot in DuelState.FRONT:
		if d.can_use_ability(side, slot):
			return {"kind": "ability", "slot": slot}
	var act := _activation(d, side, level)
	if not act.is_empty():
		return act
	# Easy and Normal take the first attacker's best hit; Hard picks the best hit of all
	var plan := {}
	var plan_score := 0.0
	for slot in DuelState.FRONT:
		if not d.can_attack_with(side, slot):
			continue
		if level == "easy" and _roll(d, side, slot) < 35:
			continue   # an easy CPU sometimes forgets to attack
		var att: Dictionary = d.card_at(side, slot)
		var best := NO_TARGET
		var best_foe := ""
		var best_score := 0.0
		for foe in d.foes_of(side):
			# FFA: a little extra for hitting whoever is weakest, so the CPU closes players out
			var focus: float = (6000.0 - d.sides[foe].morale) / 6000.0 if d.ffa else 0.0
			for t in d.attack_targets(side, foe):
				var score := 0.0
				if t == DuelState.DIRECT:
					# Finish the game (or a player) if this hit does it; otherwise chip their morale
					score = 100.0 if att.attack >= d.sides[foe].morale else 2.5 + att.attack / 2000.0 + focus
				elif t == DuelState.LEADER:
					# Knock out a dormant leader when one hit does it (−1000 morale, no Dormant bonus);
					# chipping its Influence is a last resort
					score = 4.0 if att.attack >= d.sides[foe].leader.influence else 0.5
				else:
					score = _target_score(att, d.card_at(foe, t), level)
					if score > 0.0:
						score += focus * 0.5
				if score > best_score:
					best_score = score
					best = t
					best_foe = foe
					if level == "easy":
						break
			if level == "easy" and best != NO_TARGET:
				break
		var hit := {"kind": "attack", "from": slot, "target": best}
		if d.ffa:
			hit.foe = best_foe
		if best != NO_TARGET and level != "hard":
			return hit
		if best != NO_TARGET and best_score > plan_score:
			plan_score = best_score
			plan = hit
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
	for foe in d.foes_of(side):
		for e in d.characters(foe):
			if e.card.position == "atk" and not e.card.downed and not e.card.face_down:
				threat = maxi(threat, e.card.attack)
	return threat


## A Card Forge Hustle is worth playing now if at least one of its effects would do something
## (buffing allies needs allies, hitting enemies needs enemies). Hand-written Hustles: always.
## Swapping its ATK and DEF lowers what an attacker must beat (its ATK when it stands in ATK
## position, its DEF in DEF or Downed). Same as swapWeakens in DuelAI.js.
static func _swap_weakens(c: Dictionary) -> bool:
	return c.attack < c.defense if c.position == "def" or c.downed else c.defense < c.attack


static func _hustle_useful(d: DuelState, side: String, c: Dictionary) -> bool:
	var effects: Array = c.get("effects", [])
	if effects.is_empty():
		return true
	var foes := d.foes_of(side)
	var allies := d.characters(side).filter(func(e): return not d.in_stasis(e.card))
	var enemies := d._enemy_chars(side).filter(func(e): return not d.in_stasis(e.card))
	for e in effects:
		var what := str(e.get("do", ""))
		match str(e.get("target", "")):
			"ally", "allies":
				if what == "stand":
					if allies.any(func(x): return x.card.downed):
						return true
				elif what == "cleanse":   # (STASIS too)
					if d.characters(side).any(func(x): return d._afflicted(x.card)):
						return true
				elif not allies.is_empty():
					return true
			"enemy", "enemies":
				if what == "swap":   # (only when it makes them easier to beat)
					if enemies.any(func(x): return _swap_weakens(x.card)):
						return true
				elif not enemies.is_empty():
					return true
			"all":   # (everyone's characters: worth it when it hits more of theirs than ours)
				if enemies.size() > allies.size():
					return true
			_:
				if what == "discard":
					if foes.any(func(f): return not d.sides[f].hand.is_empty()):
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
