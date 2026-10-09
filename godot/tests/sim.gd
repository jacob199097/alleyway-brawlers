extends SceneTree
## Plays CPU-vs-CPU duels on the rules alone (no screen) and checks they finish cleanly.
## Run:  godot --headless --path godot --script res://tests/sim.gd

const GAMES := 200
const MAX_STEPS := 5000


func _init() -> void:
	var wins := {"player": 0, "opponent": 0, "": 0}
	var turns := 0
	var counts := {}
	var failures := 0
	for g in GAMES:
		var setup := DuelAI.test_setup()
		var d := DuelState.new(setup.decks, setup.hideouts, setup.leaders, "player", g + 1)
		d.start()
		var steps := 0
		while d.winner == "" and steps < MAX_STEPS and d.turn < 120:
			var side: String = d.pending.side if not d.pending.is_empty() else d.active
			var a := DuelAI.choose(d, side)
			if a.is_empty() or not d.do_action(side, a):
				push_error("game %d: action refused %s (phase %s)" % [g, a, d.phase])
				failures += 1
				break
			steps += 1
		for e in d.take_events():
			var key: String = e.type
			if e.type == "prompt":
				key = "prompt:" + str(e.get("key", e.kind))
			counts[key] = counts.get(key, 0) + 1
		wins[d.winner] += 1
		turns += d.turn
	print("games: %d  player wins: %d  opponent wins: %d  unfinished: %d  avg turns: %.1f  refused: %d"
		% [GAMES, wins.player, wins.opponent, wins[""], float(turns) / GAMES, failures])
	print("events: ", counts)
	quit(1 if failures > 0 else 0)
