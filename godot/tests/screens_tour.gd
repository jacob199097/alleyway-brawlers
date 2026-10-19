extends Node
## Visits every menu screen against the mock server (tests/mock_server.mjs) and saves a
## screenshot of each. Nothing is written to the player's saved settings or session.
## Run (windowed):  godot --path godot res://tests/screens_tour.tscn -- <out_dir> [server_url] [--ffa-only]

var _out := "user://tour"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	Game.settings.server_url = args[1] if args.size() > 1 and not args[1].begins_with("--") else "http://127.0.0.1:3999"
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _shot(name: String, wait := 1.6) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


## The screens that list every clan, with 8 made-up clans added to the real ones.
func _clan_shots() -> void:
	var names := ["Syndicate", "Ronin", "Voodoo", "Chrome", "Lucky Sevens", "Tide", "Ember", "Phantom"]
	var colors := ["#e05252", "#e0a052", "#52e0a0", "#52a0e0", "#f2c14e", "#4fc3ff", "#ff7a3d", "#b8b4cc"]
	for i in names.size():   # (a card each, so the game's own clan list has them)
		var id: String = names[i].to_lower().replace(" ", "_")
		CardDB.all()["fake_%s" % id] = {"id": "fake_%s" % id, "name": names[i] + " Grunt", "clan": id, "clanName": names[i],
			"clanColor": colors[i], "clanTag": id, "cardType": "gang_member", "authority": 1, "attack": 500, "defense": 500, "rarity": 1}
	for s in ["clan_select", "shop", "card_library", "deck_builder"]:
		Game.go(s)
		await _shot("10_" + s, 2.4)
	Game.go("shop")
	await get_tree().create_timer(2.0).timeout
	_screen()._scroll(1)
	_screen()._scroll(1)
	await _shot("10_shop_scrolled", 0.8)


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
	# Nothing here may save settings (that would keep the mock server's address): the main menu
	# only saves when it offers the tutorial or meets a new version, so neither happens
	Game.settings.tutorial_offered = true
	Game.settings.last_seen_version = str(ProjectSettings.get_setting("application/config/version", ""))
	if "--clans" in OS.get_cmdline_user_args():   # (the screens with 10 clans: start the mock server with EXTRA_CLANS=8)
		await _clan_shots()
		get_tree().quit()
		return
	if "--ffa-only" in OS.get_cmdline_user_args():   # (just the free-for-all screens)
		await _ffa_shots()
		get_tree().quit()
		return
	for s in ["main_menu", "fight_mode", "card_library", "deck_builder", "shop", "contraband", "profile", "social", "mailbox", "clan_select", "achievements"]:
		Game.go(s)
		await _shot("02_" + s, 2.2)
	# The profile's clan mastery and deck records
	Game.go("profile")
	await get_tree().create_timer(2.0).timeout
	_screen()._tab("mastery")
	await _shot("02_profile_mastery", 1.2)
	_screen()._tab("decks")
	await _shot("02_profile_decks", 1.0)
	Net.show_achievements([{"heading": "WEEKLY CHALLENGE", "name": "War Chest", "reward": {"karat": 300, "free_packs": 1}}])
	await _shot("02_challenge_banner", 1.0)
	# A friend comes online: the pop-up in the bottom-right corner
	Net._friend_online({"username": "AlleyCat", "avatar": null, "level": 9})
	await _shot("02_friend_online", 1.0)
	# A friend's profile (from the friends list)
	Game.view_player_id = "00000000-0000-0000-0000-000000000001"
	Game.go("profile")
	await _shot("02_friend_profile", 2.2)
	Game.go("leaderboard")
	await _shot("02_leaderboard", 2.4)
	# The daily reward on the main menu (day 3: two days ticked off, today glowing)
	Game.go("main_menu")
	await get_tree().create_timer(1.6).timeout
	_screen()._daily_popup({"day": 3, "claimed": false, "streak": 2, "rewards": [{"karat": 100}, {"dust": 50}, {"karat": 150},
		{"dust": 100}, {"karat": 200}, {"dust": 150}, {"karat": 300, "free_packs": 1}]})
	await _shot("02_daily", 1.2)
	# Crafting: pick a card in the library, then an achievement unlocking
	Game.go("card_library")
	await get_tree().create_timer(2.0).timeout
	var lib = _screen()
	var first: Dictionary = lib._tiles.values()[0].card
	lib._select(first)
	await _shot("02_card_library_craft", 0.8)
	Net.show_achievements([{"name": "Untouchable", "reward": {"dust": 300, "title": "Untouchable"}}])
	await _shot("02_achievement_banner", 1.0)
	# The zoomed card: a Striver (its whole line) with keywords (and what they mean)
	for id in CardDB.all():
		var sc: Dictionary = CardDB.get_card(id)
		if CardDB.striver_stage(sc).x == 2:
			UI.card_zoom(lib, sc)
			break
	await _shot("02_card_zoom", 0.9)
	# Crafting a Legendary: the reveal
	for t in lib._tiles.values():
		if int(t.card.get("rarity", 1)) >= 5:
			lib._reveal(t.card, t)
			break
	await _shot("02_craft_reveal", 1.1)
	await get_tree().create_timer(1.6).timeout
	# Pack opening
	Game.go("shop")
	await get_tree().create_timer(1.2).timeout
	var clan: Dictionary = CardDB.clans()[0]   # (the shop lists the server's packs: the first clan's)
	_screen()._buy({"id": clan.id, "label": clan.name, "image": "%s_booster.png" % clan.id, "color": clan.color}, "karat")
	await _shot("03_pack_ready", 1.8)
	var opening = _screen()._opening
	opening.tear_now()
	await _shot("03_pack_cards", 3.4)
	for k in opening._cards:   # the Epic first, at full length
		if k.rarity >= 4:
			opening._enqueue(k)
	await _shot("03_pack_epic", 3.3)
	opening.reveal_all()
	await _shot("03_pack_done", 4.5)
	# Settings and a dialog
	Game.go("main_menu")
	await get_tree().create_timer(1.5).timeout
	SettingsPanel.open(_screen())
	await _shot("04_settings", 0.6)
	var panel: SettingsPanel = _screen().get_children().filter(func(c): return c is SettingsPanel)[0]
	panel._show("gameplay")
	await _shot("04_settings_gameplay", 0.4)
	panel.close()
	_screen()._show_patch_notes("0.6.0", str(ProjectSettings.get_setting("application/config/version", "")))
	await _shot("04_patch_notes", 1.4)
	# Deck builder tools: empty the deck, auto-fill it, filter by a keyword
	Game.go("deck_builder")
	await get_tree().create_timer(2.0).timeout
	_screen()._deck.clear()
	_screen()._auto_fill()
	var code: String = _screen()._deck_code()
	print("deck code ", code.left(40), "… (", code.length(), " chars)")
	_screen()._deck.clear()
	_screen()._load_code(code)
	print("deck from code: ", _screen()._deck.size(), " cards")
	_screen()._kind = "striver"
	_screen()._render_collection()
	await _shot("04_deck_tools", 1.0)
	# Fight → deck loads → RPS
	Game.go("fight_mode")
	await get_tree().create_timer(1.0).timeout
	_screen()._start("casual")
	await _shot("05_rps", 2.5)
	# Post-match for a match session, so the server's rewards come back
	var session := await Api.request("POST", "/api/match/start", {"ranked": false})
	Game.match_result = {"result": "win", "player_morale": 3400, "opponent_morale": 0, "turns": 14,
		"cards_played": 9, "match_id": session.data.matchId,
		"mvp": {"card": CardDB.get_card("card_nebu_025"), "owner": "player", "damage": 2300, "kos": 2},
		"mastery": {"clan": "nebula", "name": "Nebula", "color": "#9b7bff", "xp": 1250, "gained": 100,
			"levels": [0, 300, 700, 1200, 1800, 2500, 3300, 4200, 5200, 6300]}}
	Game.go("post_match")
	await _shot("06_post_match_early", 1.6)
	await _shot("06_post_match", 2.6)
	# After a match against a player: the rematch offer
	Game.match_result = {"result": "loss", "player_morale": 0, "opponent_morale": 2100, "turns": 11,
		"online": true, "mode": "casual", "reason": "afk", "rewards": {"xpEarned": 20, "karatEarned": 10},
		"mvp": {"card": CardDB.get_card("card_mili_037"), "owner": "opponent", "damage": 2300},
		"mastery": {"clan": "militia", "name": "Militia", "color": "#9bd84a", "xp": 340, "gained": 40,
			"levels": [0, 300, 700, 1200, 1800, 2500, 3300, 4200, 5200, 6300]}}
	Game.go("post_match")
	await get_tree().create_timer(1.0).timeout
	Net.rematch_inbox.append(["mp:rematch_offer", {"fromUsername": "Rival"}])
	await _shot("06_post_match_rematch", 1.0)
	_screen()._rematch_done = true   # don't tell the (absent) server we left
	# Duel with the player's saved deck
	var deck := await Game.load_duel_deck()
	Game.duel_setup = deck
	Game.duel_setup.first = "player"
	Game.go("duel")
	await _shot("07_duel", 4.0)
	# Luck: a die rolled for a 4+ effect, then a coin flip; then a Legendary's entrance
	var duel_screen = _screen()
	duel_screen._ev_luck({"side": "player", "slot": -1, "kind": "die", "value": 5, "need": 4, "won": true})
	await _shot("07_luck_die", 0.75)
	await get_tree().create_timer(0.6).timeout
	duel_screen._ev_luck({"side": "player", "slot": -1, "kind": "coin", "value": 0, "need": 1, "won": false})
	await _shot("07_luck_coin", 0.75)
	await get_tree().create_timer(0.6).timeout
	var legend = duel_screen._new_view(CardDB.get_card("card_mili_040"), "player", true)
	legend.position = Vector2(1080, 900)
	duel_screen._legendary_entrance(legend, legend.card)
	await _shot("07_legendary", 1.6)
	await get_tree().create_timer(1.5).timeout
	legend.queue_free()
	# Let the CPU play both sides for a while, then open the battle log
	_screen().ai_sides = ["player", "opponent"]
	_screen()._after_events()
	await get_tree().create_timer(14.0).timeout
	_screen()._toggle_log()
	await _shot("07_duel_log", 0.5)
	await _ffa_shots()
	get_tree().quit()


## Free-for-all: the lobby, ready, then a match against CPUs (start the mock server with
## FFA_LOBBY_SECS=5 FFA_TURN_SECS=4 FFA_AWAY_SECS=2 (CPUs fill the table): a full table, and this player,
## who doesn't play, is put out after a while, so the end and the results show too)
func _ffa_shots() -> void:
	Engine.time_scale = 1.0
	Game.go("ffa_lobby")
	await _shot("08_ffa_lobby", 2.5)
	_screen()._toggle_ready()
	await _shot("08_ffa_lobby_ready", 1.0)
	var waited := 0.0
	while _screen().name != "Duel" and waited < 60.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if _screen().name == "Duel":
		await _shot("08_ffa_duel", 5.0)
		await _shot("08_ffa_duel_later", 12.0)
		await _shot("08_ffa_duel_out", 14.0)
		waited = 0.0
		while _screen().name == "Duel" and waited < 240.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
			if int(waited) % 40 == 0:
				await _shot("08_ffa_duel_%d" % int(waited), 0.0)
		await _shot("08_ffa_results", 3.0)
