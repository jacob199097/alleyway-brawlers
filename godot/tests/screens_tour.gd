extends Node
## Visits every menu screen against the mock server (tests/mock_server.mjs) and saves a
## screenshot of each. Nothing is written to the player's saved settings or session.
## Run (windowed):  godot --path godot res://tests/screens_tour.tscn -- <out_dir> [server_url]

var _out := "user://tour"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	Game.settings.server_url = args[1] if args.size() > 1 else "http://127.0.0.1:3999"
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _shot(name: String, wait := 1.6) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _screen() -> Node:
	return get_tree().current_scene


func _run() -> void:
	# Screen changes free the current scene, so hand that role to a placeholder and keep going
	await get_tree().process_frame
	var holder := Node.new()
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	Game.go("login")
	await _shot("01_login")
	var r := await Api.request("POST", "/api/auth/login", {"email": "test@example.com", "password": "x"})
	if not r.ok:
		push_error("mock server not reachable: " + r.error)
		get_tree().quit(1)
		return
	Api.token = r.data.token
	Game.player = r.data.player
	for s in ["main_menu", "fight_mode", "card_library", "deck_builder", "shop", "contraband", "profile", "social", "mailbox", "clan_select"]:
		Game.go(s)
		await _shot("02_" + s, 2.2)
	# Pack opening
	Game.go("shop")
	await get_tree().create_timer(1.2).timeout
	_screen()._buy(_screen().PACKS[0], "karat")
	await _shot("03_pack_opening", 5.5)
	# Settings and a dialog
	Game.go("main_menu")
	await get_tree().create_timer(1.5).timeout
	SettingsPanel.open(_screen())
	await _shot("04_settings", 0.6)
	# Fight → deck loads → RPS
	Game.go("fight_mode")
	await get_tree().create_timer(1.0).timeout
	_screen()._start("casual")
	await _shot("05_rps", 2.5)
	# Post-match for a match session, so the server's rewards come back
	var session := await Api.request("POST", "/api/match/start", {"ranked": false})
	Game.match_result = {"result": "win", "player_morale": 3400, "opponent_morale": 0, "turns": 14,
		"cards_played": 9, "match_id": session.data.matchId,
		"mvp": {"card": CardDB.get_card("goldfang"), "owner": "player", "damage": 2300}}
	Game.go("post_match")
	await _shot("06_post_match", 2.0)
	# Duel with the player's saved deck
	var deck := await Game.load_duel_deck()
	Game.duel_setup = deck
	Game.duel_setup.first = "player"
	Game.go("duel")
	await _shot("07_duel", 4.0)
	get_tree().quit()
