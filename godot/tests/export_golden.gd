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
	[{"when": "passive", "do": "buff", "target": "allies", "def": 200, "clan": "lion"}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 400, "if": "adjacent"}],
	[{"when": "down", "do": "promote"}],
	[{"when": "deploy", "do": "down", "target": "enemies", "if": "foe_downed"}],
	[{"when": "attack", "do": "draw", "amount": 1}, {"when": "deploy", "do": "buff", "target": "self", "def": 300}],
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
					if CardDB.get_card(deck[i]).get("cardType") == "gang_member":
						deck[i] = {"id": deck[i], "effectKey": "", "effects": FX_SAMPLES[rng.randi_range(0, FX_SAMPLES.size() - 1)]}
		var first := "player" if g % 2 == 0 else "opponent"
		var d := DuelState.new(setup.decks, setup.hideouts, setup.leaders, first, -1)
		d.start()
		var steps: Array = [{"action": null, "side": "", "events": d.take_events()}]
		var n := 0
		while d.winner == "" and n < MAX_ACTIONS:
			var side: String = d.pending.side if not d.pending.is_empty() else d.active
			var a := DuelAI.choose(d, side)
			if a.is_empty() or not d.do_action(side, a):
				push_error("refused action in game %d" % g)
				break
			steps.append({"action": a, "side": side, "events": d.take_events()})
			n += 1
		records.append({"decks": setup.decks, "hideouts": setup.hideouts, "leaders": setup.leaders,
			"first": first, "steps": steps, "winner": d.winner})
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
