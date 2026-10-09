extends Node
## Plays the tutorial start to finish through the duel screen: presses NEXT on reading steps,
## finds the one allowed move on action steps, checks off-lesson moves are refused, then lets
## the CPU finish the free-play part for the player.
## Run:  godot --headless --fixed-fps 60 --path godot res://tests/tutorial_smoke.tscn

var screen: Node
var tut: Node
var _was_done := false   # the player's real setting, put back afterwards


func _ready() -> void:
	_was_done = Game.settings.tutorial_done
	Game.duel_setup = {"mode": "tutorial"}
	screen = load("res://scenes/duel.tscn").instantiate()
	add_child(screen)
	_run()


func _run() -> void:
	await get_tree().process_frame
	tut = screen._tutorial
	_check(tut != null, "tutorial started")
	var frames := 0
	var refused_checked := false
	while tut.active and frames < 60 * 600:
		await get_tree().process_frame
		frames += 1
		if screen._playing or not screen._queue.is_empty():
			continue
		# The coach checks its step in the duel's own frame update: give it a couple of frames
		await get_tree().process_frame
		await get_tree().process_frame
		if screen._playing or not screen._queue.is_empty() or not tut.active:
			continue
		var st: Dictionary = tut.steps[tut.index]
		if st.type == tut.INFO:
			print("  step %d: info" % (tut.index + 1))
			tut._next.pressed.emit()
			await get_tree().process_frame
			continue
		if st.type == tut.WAIT or screen.duel.pending.get("side", "player") != "player" and not screen.duel.pending.is_empty():
			continue
		if screen.duel.active != "player" and screen.duel.pending.is_empty():
			continue
		if not refused_checked:
			refused_checked = true
			_check(not screen._act("player", {"kind": "next"}) or st.allow.call({"kind": "next"}), "off-lesson move is refused")
		var a := _find_allowed(st)
		if a.is_empty():
			continue
		print("  step %d: %s   [phase %s turn %d active %s pending %s/%s idle %s]" % [tut.index + 1, a, screen.duel.phase, screen.duel.turn, screen.duel.active, screen.duel.pending.get("side", "-"), screen.duel.pending.get("key", "-"), not screen._playing and screen._queue.is_empty()])
		var at: int = tut.index
		_check(screen._act("player", a), "allowed move accepted: %s (phase %s, turn %d, active %s, pending %s)" % [a, screen.duel.phase, screen.duel.turn, screen.duel.active, screen.duel.pending.get("key", "-")])
		# Let the animations play and the coach move on (some steps take several moves)
		for i in 600:
			await get_tree().process_frame
			frames += 1
			if tut.index != at or (i > 30 and not screen._playing and screen._queue.is_empty()):
				break
	_check(not tut.active, "lessons finished (stuck at step %d)" % (tut.index + 1))
	print("lessons done at turn %d, rival Morale %d" % [screen.duel.turn, screen.duel.sides.opponent.morale])
	# Free play: the CPU plays the player's side too
	screen.ai_sides = ["player", "opponent"]
	screen._after_events()
	while screen.duel.winner == "" and frames < 60 * 1200:
		await get_tree().process_frame
		frames += 1
	print("Tutorial smoke: winner %s at turn %d, tutorial_done %s" % [screen.duel.winner, screen.duel.turn, Game.settings.tutorial_done])
	var ok: bool = screen.duel.winner != "" and Game.settings.tutorial_done
	Game.set_setting("tutorial_done", _was_done)
	get_tree().quit(0 if ok else 1)


func _find_allowed(st: Dictionary) -> Dictionary:
	var d: DuelState = screen.duel
	var cands: Array = [{"kind": "next"}, {"kind": "choose", "option": "keep"}]
	for c in d.sides.player.hand:
		for slot in DuelState.FRONT:
			if d.sides.player.field[slot] == null:
				cands.append({"kind": "summon", "uid": c.uid, "slot": slot, "position": "atk"})
				break
	for from in DuelState.FRONT:
		for t in d.attack_targets("player"):
			cands.append({"kind": "attack", "from": from, "target": t})
	for a in cands:
		if st.allow.call(a):
			return a
	return {}


func _check(ok: bool, what: String) -> void:
	if not ok:
		push_error("Tutorial smoke failed: " + what)
		Game.set_setting("tutorial_done", _was_done)
		get_tree().quit(1)
