class_name DuelAI
extends RefCounted
## CPU player. choose() returns the next action for DuelState.do_action(), one at a time,
## so the screen can animate each step.

const SLOT_ORDER := [2, 1, 3, 0, 4]   # deploy toward the middle first


## The starter decks used until the client loads real decks from the server
## (same as _buildTestDeck in DuelScene.js: Lv.1 characters plus all Hustle/Ambush cards).
static func test_setup() -> Dictionary:
	var base: Array = []
	var hideout: Array = []
	for id in CardDB.all():
		var c: Dictionary = CardDB.get_card(id)
		match c.cardType:
			"leader":
				pass
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
		"leaders": {"player": "king_roan", "opponent": "king_roan"},
	}


static func choose(d: DuelState, side: String) -> Dictionary:
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
			a = _deploy(d, side)
		"brawl":
			a = _brawl(d, side)
	return a if not a.is_empty() else {"kind": "next"}


static func _deploy(d: DuelState, side: String) -> Dictionary:
	var s: Dictionary = d.sides[side]
	for slot in DuelState.FRONT:
		if d.can_promote(side, slot):
			return {"kind": "promote", "slot": slot}
	for c in s.hand:
		if d.can_hustle(side, c):
			return {"kind": "hustle", "uid": c.uid}
	# Stand up a defender that now out-muscles everything the opponent shows
	var threat := _threat(d, side)
	for e in d.characters(side):
		var c: Dictionary = e.card
		if c.position == "def" and d.can_change_position(side, e.slot) and c.attack > threat:
			return {"kind": "position", "slot": e.slot}

	var free := SLOT_ORDER.filter(func(i): return s.field[i] == null)
	if not free.is_empty():
		var best = null
		for c in s.hand:
			if d.can_summon(side, c, free[0]) and (best == null or c.base_attack > best.base_attack):
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


static func _brawl(d: DuelState, side: String) -> Dictionary:
	var foe := DuelState.other(side)
	# Maya Lv.3 buffs an ally before the punches start
	for slot in DuelState.FRONT:
		if d.can_use_ability(side, slot):
			return {"kind": "ability", "slot": slot}
	for slot in DuelState.FRONT:
		if not d.can_attack_with(side, slot):
			continue
		var att: Dictionary = d.card_at(side, slot)
		var targets := d.attack_targets(side)
		if DuelState.DIRECT in targets:
			# Knock out a dormant leader when one hit does it (−1000 morale and no Dormant bonus);
			# otherwise go for the opponent's morale
			var leader = d.sides[foe].leader
			if DuelState.LEADER in targets and att.attack >= leader.influence:
				return {"kind": "attack", "from": slot, "target": DuelState.LEADER}
			return {"kind": "attack", "from": slot, "target": DuelState.DIRECT}
		var best := -1
		var best_score := 0.0
		for t in targets:
			var df: Dictionary = d.card_at(foe, t)
			var score := 0.0
			if df.face_down:
				score = 1.0 if att.attack >= 1600 else 0.0   # unknown DEF: only strong attackers try
			elif df.downed:
				score = 3.0 if att.attack > df.defense else 0.0
			elif df.position == "def":
				score = 2.0 if att.attack > df.defense else 0.0
			elif att.attack > df.attack:
				score = 2.0 + (att.attack - df.attack) / 1000.0
			if score > best_score:
				best_score = score
				best = t
		if best >= 0:
			return {"kind": "attack", "from": slot, "target": best}
	return {}


## The strongest face-up attacker the opponent shows.
static func _threat(d: DuelState, side: String) -> int:
	var threat := 0
	for e in d.characters(DuelState.other(side)):
		if e.card.position == "atk" and not e.card.downed and not e.card.face_down:
			threat = maxi(threat, e.card.attack)
	return threat


static func _weakest(hand: Array) -> Dictionary:
	var worst: Dictionary = hand[0]
	for c in hand:
		if c.authority * 1000 + c.base_attack < worst.authority * 1000 + worst.base_attack:
			worst = c
	return worst
