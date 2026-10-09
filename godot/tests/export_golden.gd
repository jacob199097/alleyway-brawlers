extends SceneTree
## Records CPU-vs-CPU games on the Godot rules (decks, every action, every event) so the
## server's JavaScript rules can replay them and prove they match (shared/duel/engine.test.mjs).
## Run:  godot --headless --path godot --script res://tests/export_golden.gd -- <out.json> [games]

const MAX_ACTIONS := 1500


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
