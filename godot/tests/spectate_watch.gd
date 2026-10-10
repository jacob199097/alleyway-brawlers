extends Node
## Watches a friend's match like a player would: Social → 👁 WATCH → the duel in watch mode →
## STOP WATCHING. Checks nothing can be played and the other side's hand stays hidden.
## Start tests/mock_server.mjs and two online bots (tests/online_bot.tscn), then run (windowed):
##   godot --path godot res://tests/spectate_watch.tscn -- <out_dir> [server]

const TIMEOUT := 120.0

var _out := "user://spectate"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	Game.settings.server_url = args[1] if args.size() > 1 else "http://127.0.0.1:3999"
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _fail(why: String) -> void:
	push_error("spectate: " + why)
	print("spectate: FAILED (", why, ")")
	get_tree().quit(1)


func _run() -> void:
	await get_tree().process_frame
	var holder := Node.new()
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	var r := await Api.request("POST", "/api/auth/login", {"email": "watcher@example.com", "password": "x"})
	if not r.ok:
		return _fail("login: " + r.error)
	Api.token = r.data.token
	Game.player = r.data.player
	Net.connect_to_server()
	Game.go("social")
	# Wait for a friend to be in a match, then press their WATCH button
	var started := Time.get_ticks_msec()
	var target := {}
	while target.is_empty():
		if (Time.get_ticks_msec() - started) / 1000.0 > TIMEOUT:
			return _fail("no friend got into a match")
		await _wait(1.0)
		var f := await Api.request("GET", "/api/social/friends")
		for row in f.data if f.ok else []:
			if row.get("in_match", false):
				target = row
	Game.go("social")
	await _wait(1.5)
	_shot("spectate_1_social")
	var button: Button = null
	for b in get_tree().current_scene.find_children("*", "Button", true, false):
		if "WATCH" in b.text:
			button = b
	if button == null:
		return _fail("no WATCH button on the friends list")
	Net.event.connect(func(n, d): if n.begins_with("mp:") and n != "mp:update": print("net: ", n, " ", str(d).left(160)))
	print("pressing WATCH for ", target.friend_username, ", connected: ", Net.is_open)
	# Their match may still be at Scissors Paper Rock: press again until it opens
	var pressed_at := 0
	while get_tree().current_scene == null or get_tree().current_scene.name != "Duel":
		if (Time.get_ticks_msec() - started) / 1000.0 > TIMEOUT:
			return _fail("the duel never opened")
		if Time.get_ticks_msec() - pressed_at > 3000 and is_instance_valid(button):
			pressed_at = Time.get_ticks_msec()
			button.pressed.emit()
		await _wait(0.2)
	await _wait(6.0)
	var duel = get_tree().current_scene
	if not duel._spectating:
		return _fail("the duel isn't in watch mode")
	_shot("spectate_2_watching")
	var bad := 0
	if not duel._ui.next.disabled:
		push_error("the phase button can be pressed while watching")
		bad += 1
	for side in ["player", "opponent"]:
		for v in duel.hand[side]:
			if v.face_up:
				push_error("a card in %s's hand is face up for the spectator" % side)
				bad += 1
				break
	if duel._act("player", {"kind": "next"}):
		push_error("a spectator's move was sent")
		bad += 1
	print("watching %s: turn %d, %d/%d cards in hands" % [target.friend_username, duel.duel.turn, duel.hand.player.size(), duel.hand.opponent.size()])
	await _wait(10.0)
	duel._toggle_log()
	await _wait(0.3)
	_shot("spectate_3_log")
	duel._stop_watching()
	await _wait(2.0)
	if get_tree().current_scene.name == "Duel":
		push_error("STOP WATCHING didn't leave")
		bad += 1
	print("spectate: ", "OK" if bad == 0 else "%d problem(s)" % bad)
	get_tree().quit(bad)
