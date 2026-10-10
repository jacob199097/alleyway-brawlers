extends Node
## Watches a replay and skips turns forward and back (duel.gd _seek_turn), checking the board is
## rebuilt for the right turn, and saves screenshots.
## Make a replay file (GET /api/replays/:id's answer), then run (windowed):
##   godot --path godot res://tests/replay_seek.tscn -- <replay.json> <out_dir>

var _out := "user://replay_seek"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[1] if args.size() > 1 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	var data = Net.normalize(JSON.parse_string(FileAccess.get_file_as_string(args[0])))
	Game.offline = true   # nothing reaches a server
	Game.duel_setup = {"online": true, "start": data.start, "replay": data}
	_run()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	await get_tree().process_frame
	var holder := Node.new()
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	Game.go("duel")
	await _wait(4.0)
	var duel = get_tree().current_scene
	var bad := 0
	print("watching: turn ", duel.duel.turn)
	for i in 3:
		duel._seek_turn(1)
		await _wait(2.5)
		print("after TURN >>: turn ", duel.duel.turn, ", next update ", duel._replay_next)
	var forward: int = duel.duel.turn
	if forward < 4:
		push_error("skipping forward didn't move on (turn %d)" % forward)
		bad += 1
	_shot("replay_forward")
	duel._toggle_log()
	await _wait(0.3)
	_shot("replay_forward_log")
	duel._toggle_log()
	duel._seek_turn(-1)
	await _wait(2.5)
	print("after << TURN: turn ", duel.duel.turn)
	if duel.duel.turn >= forward:
		push_error("skipping back didn't go back (turn %d, was %d)" % [duel.duel.turn, forward])
		bad += 1
	_shot("replay_back")
	# The board on screen matches the rules' board
	for side in ["player", "opponent"]:
		var on_field := 0
		for c in duel.duel.sides[side].field:
			if c != null:
				on_field += 1
		if on_field != duel.field[side].size():
			push_error("%s: %d cards in the rules, %d on screen" % [side, on_field, duel.field[side].size()])
			bad += 1
		if duel.duel.sides[side].hand.size() != duel.hand[side].size():
			push_error("%s hand: %d in the rules, %d on screen" % [side, duel.duel.sides[side].hand.size(), duel.hand[side].size()])
			bad += 1
	print("replay seek: ", "OK" if bad == 0 else "%d problem(s)" % bad)
	get_tree().quit(bad)
