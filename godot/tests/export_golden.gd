extends SceneTree
## Records CPU-vs-CPU games on the Godot rules (decks, every action, every event) so the
## server's JavaScript rules can replay them and prove they match (shared/duel/engine.test.mjs).
## Run:  godot --headless --path godot --script res://tests/export_golden.gd -- <out.json> [games]

const MAX_ACTIONS := 1500
# Odd-numbered games give every character one of these data effects (Card Forge building
# blocks) instead of its hand-written one, so both engines are checked on every block.
const FX_SAMPLES := [
	[{"when": "deploy", "do": "buff", "target": "ally", "atk": 500}],
	[{"when": "deploy", "do": "down", "target": "enemy"}],
	[{"when": "deploy", "do": "buff", "target": "enemies", "atk": -300, "until": "next_turn"}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 400}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 600, "if": "vs_def"}],
	[{"when": "ko", "do": "draw", "amount": 1}],
	[{"when": "down", "do": "discard", "amount": 1}],
	[{"when": "ko", "do": "attack_again", "if": "vs_downed"}],
	[{"when": "turn_start", "do": "heal", "amount": 300}],
	[{"when": "deploy", "do": "damage", "amount": 200}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 300, "if": "allies", "n": 1}],
	[{"when": "passive", "do": "buff", "target": "allies", "def": 200, "clan": "nebula"}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 400, "if": "adjacent"}],
	[{"when": "passive", "do": "pierce"}, {"when": "passive", "do": "double_attack"}],
	[{"when": "passive", "do": "guard"}, {"when": "passive", "do": "no_down"}],
	[{"when": "passive", "do": "untargetable"}, {"when": "passive", "do": "immune"}],
	[{"when": "passive", "do": "cost_down", "amount": 1}],
	[{"when": "passive", "do": "cost_down", "amount": 2, "clan": "nebula", "if": "allies", "n": 1}],
	[{"when": "passive", "do": "buff", "target": "enemies", "atk": -300}],
	[{"when": "passive", "do": "guard", "if": "foe_downed"}, {"when": "deploy", "do": "poison", "target": "enemies", "amount": 200}],
	[{"when": "down", "do": "promote"}],
	[{"when": "down", "do": "promote", "times": 2}],
	[{"when": "ko", "do": "draw", "amount": 1, "times": 2}],
	[{"when": "deploy", "do": "down", "target": "enemies", "if": "foe_downed"}],
	[{"when": "attack", "do": "draw", "amount": 1}, {"when": "deploy", "do": "buff", "target": "self", "def": 300}],
	[{"when": "defend", "do": "buff", "target": "self", "atk": 300, "def": 500}],
	[{"when": "defend", "do": "stun", "target": "attacker"}],
	[{"when": "defend", "do": "bounce", "target": "attacker", "if": "vs_atk"}],
	[{"when": "direct", "do": "draw", "amount": 1}, {"when": "direct", "do": "mill", "amount": 2}],
	[{"when": "self_downed", "do": "damage", "amount": 300}],
	[{"when": "self_ko", "do": "buff", "target": "allies", "atk": 300, "until": "next_turn"}],
	[{"when": "self_ko", "do": "recover", "kind": "gang_member"}],
	[{"when": "ally_deployed", "do": "heal", "amount": 200, "once": true}],
	[{"when": "ally_deployed", "do": "buff", "target": "self", "atk": 200, "clan": "nebula"}],
	[{"when": "turn_end", "do": "shield", "target": "self", "once": true}],
	[{"when": "turn_end", "do": "stand", "target": "allies"}],
	[{"when": "deploy", "do": "ko", "target": "enemy", "if": "enemies_ge", "n": 2}],
	[{"when": "deploy", "do": "force_def", "target": "enemies"}],
	[{"when": "deploy", "do": "search", "kind": "gang_member"}, {"when": "turn_start", "do": "authority", "amount": 1, "if": "hand_le", "n": 3}],
	[{"when": "attack", "do": "pierce"}, {"when": "ko", "do": "drain", "amount": 200}],
	[{"when": "turn_start", "do": "heal", "amount": 400, "if": "morale_le", "n": 3000}, {"when": "deploy", "do": "damage", "amount": 300, "if": "foe_morale_le", "n": 4000}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 500, "if": "alone"}, {"when": "turn_start", "do": "draw", "if": "gutter_ge", "n": 4, "once": true}],
	[{"when": "passive", "do": "buff", "target": "self", "def": 400, "if": "leader_dormant"}, {"when": "deploy", "do": "stun", "target": "enemies"}],
	[{"when": "deploy", "do": "shield", "target": "ally"}, {"when": "deploy", "do": "bounce", "target": "enemy", "if": "foe_downed"}],
	[{"when": "deploy", "do": "poison", "target": "enemy", "amount": 300}],
	[{"when": "deploy", "do": "burn", "target": "enemies", "amount": 200}],
	[{"when": "defend", "do": "bleed", "target": "attacker", "amount": 200}, {"when": "attack", "do": "poison", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "shock", "target": "enemy", "amount": 900}],
	[{"when": "attack", "do": "shock", "target": "enemies", "amount": 400}, {"when": "self_ko", "do": "burn", "target": "enemies", "amount": 300}],
	[{"when": "deploy", "do": "freeze", "target": "enemy"}],
	[{"when": "defend", "do": "freeze", "target": "attacker"}, {"when": "deploy", "do": "bleed", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "stasis", "target": "enemy"}],
	[{"when": "turn_end", "do": "stasis", "target": "self", "once": true, "if": "morale_le", "n": 3000}, {"when": "passive", "do": "buff", "target": "self", "atk": 300}],
	[{"when": "defend", "do": "down", "target": "attacker", "if": "vs_def"}, {"when": "defend", "do": "ko", "target": "attacker", "once": true, "if": "vs_downed"}],
	[{"when": "deploy", "do": "search", "max_auth": 3, "choose": true}],
	[{"when": "deploy", "do": "search", "kind": "gang_member", "role": "striver", "level": 1, "amount": 2}],
	[{"when": "deploy", "do": "search", "name": "pride"}, {"when": "attack", "do": "buff", "target": "self", "atk": 300, "if": "leader_awake"}],
	[{"when": "self_ko", "do": "revive", "max_auth": 4}],
	[{"when": "deploy", "do": "revive", "choose": true, "if": "gutter_ge", "n": 2}],
	[{"when": "deploy", "do": "break_ambush", "amount": 1}],
	[{"when": "foe_deployed", "do": "buff", "target": "self", "atk": 200, "until": "turn"}],
	[{"when": "hustle_played", "do": "heal", "amount": 200}, {"when": "turn_start", "do": "damage", "amount": 100, "if": "hand_ge", "n": 3}],
	[{"when": "deploy", "do": "recover", "role": "brawler", "amount": 2, "choose": true}],
	[{"when": "passive", "do": "immune"}, {"when": "attack", "do": "pierce", "if": "leader_dormant"}],
	[{"when": "deploy", "do": "down", "target": "enemy", "clan": "nebula", "if": "adjacent", "if_clan": ""}],
	[{"when": "direct", "do": "attack_again"}, {"when": "attack", "do": "attack_again"}],
	[{"when": "attack", "do": "promote", "times": 2, "if": "vs_downed"}, {"when": "defend", "do": "draw", "amount": 1, "times": 2}],
	[{"when": "attack", "do": "draw", "amount": 1, "times": 3}],
	[{"when": "passive", "do": "immune", "statuses": ["poison", "stun"]}, {"when": "deploy", "do": "burn", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "silence", "target": "enemy"}, {"when": "turn_start", "do": "ramp", "amount": 1, "if": "authority_ge", "n": 3, "once": true}],
	[{"when": "passive", "do": "elusive"}, {"when": "deploy", "do": "break_ambush", "if": "foe_ambush"}],
	[{"when": "turn_start", "do": "influence", "amount": 500}, {"when": "deploy", "do": "discard", "amount": 1, "if": "foe_hand_le", "n": 3}],
	[{"when": "turn_end", "do": "stand", "target": "allies", "if": "ally_downed"}, {"when": "defend", "do": "silence", "target": "attacker", "until": "next_turn"}],
	[{"when": "ally_deployed", "do": "buff", "target": "allies", "atk": 200, "clan": "", "when_clan": "nebula"}, {"when": "passive", "do": "buff", "target": "self", "atk": 300, "if": "allies", "n": 2, "if_clan": "nebula", "clan": ""}],
]


## Effects for Hustles (happen when played) and Ambushes (happen when sprung) in odd games.
const FX_CARD_SAMPLES := [
	[{"do": "draw", "amount": 2}],
	[{"do": "damage", "amount": 400}, {"do": "heal", "amount": 200}],
	[{"do": "buff", "target": "allies", "atk": 300}],
	[{"do": "down", "target": "enemy"}],
	[{"do": "poison", "target": "enemies", "amount": 200}],
	[{"do": "stasis", "target": "ally"}, {"do": "search", "kind": "gang_member"}],
	[{"do": "buff", "target": "attacker", "atk": -1200}],
	[{"do": "down", "target": "attacker"}],
	[{"do": "bounce", "target": "attacker", "if": "vs_atk"}, {"do": "draw", "amount": 1}],
	[{"do": "freeze", "target": "attacker"}, {"do": "shock", "target": "enemy", "amount": 700}],
	[{"do": "stand", "target": "allies"}, {"do": "shield", "target": "ally"}],
	[{"do": "revive", "choose": true}],
	[{"do": "break_ambush", "amount": 2}],
	[{"do": "search", "kind": "gang_member", "max_auth": 2, "amount": 2}],
]


## Card Forge leaders for every fourth game (merged over the leader card).
const LEADER_SAMPLES := [
	{"effectKey": "", "awakenCondition": {"chars": 3, "influence": 1500, "ready": true}, "effects": [
		{"when": "dormant", "do": "buff", "target": "allies", "atk": 200}, {"when": "dormant", "do": "pierce"},
		{"when": "dormant_turn_start", "do": "heal", "amount": 200}, {"when": "dormant_hit", "do": "draw", "amount": 1},
		{"when": "awaken", "do": "down", "target": "enemy"}]},
	{"effectKey": "", "awakenCondition": {"authority": 6, "gutter": 4}, "effects": [
		{"when": "dormant", "do": "cost_down", "amount": 1}, {"when": "dormant", "do": "immune"},
		{"when": "dormant_ally_deployed", "do": "damage", "amount": 100, "once": true},
		{"when": "dormant_foe_deployed", "do": "buff", "target": "enemies", "atk": -200},
		{"when": "dormant_hustle", "do": "draw", "amount": 1}, {"when": "awaken", "do": "search", "max_auth": 4, "choose": true},
		{"when": "passive", "do": "buff", "target": "allies", "atk": 300}]},
	{"effectKey": "", "awakenCondition": {"morale": 4000, "foe_morale": 2500}, "effects": [
		{"when": "dormant", "do": "untargetable"}, {"when": "dormant", "do": "buff", "target": "enemies", "def": -300},
		{"when": "dormant_turn_end", "do": "stand", "target": "allies"}, {"when": "awaken", "do": "revive"},
		{"when": "attack", "do": "buff", "target": "self", "atk": 500}]},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://golden.json"
	var games := int(args[1]) if args.size() > 1 else 25
	var rng := RandomNumberGenerator.new()
	var records: Array = []
	for g in games:
		rng.seed = 1000 + g
		var setup := DuelAI.test_setup()
		for side in ["player", "opponent"]:
			_shuffle(setup.decks[side], rng)
		if g % 2 == 1:
			for side in ["player", "opponent"]:
				var deck: Array = setup.decks[side]
				for i in deck.size():
					var kind: String = CardDB.get_card(deck[i]).get("cardType", "")
					if kind == "gang_member":
						deck[i] = {"id": deck[i], "effectKey": "", "effects": FX_SAMPLES[rng.randi_range(0, FX_SAMPLES.size() - 1)]}
					elif kind in ["hustle", "ambush"]:
						deck[i] = {"id": deck[i], "effectKey": "", "effects": FX_CARD_SAMPLES[rng.randi_range(0, FX_CARD_SAMPLES.size() - 1)]}
		var first := "player" if g % 2 == 0 else "opponent"
		var levels := {"player": DuelAI.LEVELS[g % 3], "opponent": DuelAI.LEVELS[(g + 1) % 3]}
		var d := DuelState.new(setup.decks, setup.hideouts, setup.leaders, first, -1)
		# Every fourth game the leaders are Card Forge leaders (Dormant / Awaken effects)
		var leader_fx := {}
		if g % 4 == 3:
			for side in ["player", "opponent"]:
				if d.sides[side].leader != null:
					leader_fx[side] = LEADER_SAMPLES[(g / 4 + (1 if side == "opponent" else 0)) % LEADER_SAMPLES.size()]
					d.sides[side].leader.merge(leader_fx[side].duplicate(true), true)
		d.start()
		var steps: Array = [{"action": null, "side": "", "events": d.take_events()}]
		var n := 0
		while d.winner == "" and n < MAX_ACTIONS:
			var side: String = d.pending.side if not d.pending.is_empty() else d.active
			var a := DuelAI.choose(d, side, levels[side])
			if a.is_empty() or not d.do_action(side, a):
				push_error("refused action in game %d" % g)
				break
			steps.append({"action": a, "side": side, "events": d.take_events()})
			n += 1
		records.append({"decks": setup.decks, "hideouts": setup.hideouts, "leaders": setup.leaders, "leader_fx": leader_fx,
			"first": first, "levels": levels, "steps": steps, "winner": d.winner})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(records))
	f.close()
	print("wrote %d games to %s" % [games, out_path])
	quit()


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
