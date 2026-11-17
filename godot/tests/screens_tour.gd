extends Node
## Visits every menu screen against the mock server (tests/mock_server.mjs) and saves a
## screenshot of each. Nothing is written to the player's saved settings or session.
## Run (windowed):  godot --path godot res://tests/screens_tour.tscn -- <out_dir> [server_url] [--ffa-only]
## Other modes: --fps (frames per second on each screen), --perf-library (what the Card Library's
## frame time goes on), --craft-only (the card zoom and craft reveal in quick shots), --clans,
## --auction (the auction house's tabs: against a local backend/server.js with auctions in its database,
## as the mock server has none).
## --obtain: the Card Library's HOW TO GET IT for each kind of card.
## --site: the pictures on the website (tools/site_shots.mjs turns them into website/shots).

var _out := "user://tour"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	Game.settings.server_url = args[1] if args.size() > 1 and not args[1].begins_with("--") else "http://127.0.0.1:3999"
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


var _sized := false


func _shot(name: String, wait := 1.6) -> void:
	if not _sized:
		_sized = true
		# A small screen (or a locked one, which Windows makes 1024 wide): a window bigger than it, so the shots stay full size
		if DisplayServer.screen_get_size().x < 1920 and not "--phone" in OS.get_cmdline_user_args():
			var w := get_window()
			w.mode = Window.MODE_WINDOWED
			w.borderless = true
			w.size = Vector2i(1920, 1080)
			w.position = Vector2i.ZERO
			await get_tree().create_timer(0.5).timeout
	if "--site" in OS.get_cmdline_user_args():   # (the mouse in a corner: no card lifted or shown by hovering it)
		get_viewport().warp_mouse(Vector2(4, 4))
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
	_screen()._show("starters")
	await _shot("10_shop_starters", 2.0)
	_screen()._buy_starter(_screen()._starter_list[0], "karat")
	await _shot("10_shop_starter_buy", 0.8)


## The website's pictures (tools/site_shots.mjs picks and shrinks them). First, staged matches: two
## different clans in a different arena each, full boards (every kind of card, veteran frames, statuses),
## then one real move, so the game's own animation runs, with a run of shots to pick the best frame from.
## Then the menus, a pack opening, a victory and a rank up, Turf Defense (the partner is tests/online_bot.tscn,
## which site_shots.mjs starts on SITE_BOSS) and a free-for-all against the mock server; with --autoplay (as
## site_shots.mjs runs it) the CPU plays this seat in those two, so it isn't put out for being away.
## A card in a scene is an id, or {id, down, def, set (face down), burn, poison, bleed (amounts),
## stasis, freeze, blind, silence, stun (on), equip (the front slot it's attached to)}. Front slot i faces
## the rival's slot 4 - i. move: attack (from, target, spring: the rival's Ambush slot), summon (hand,
## slot), hustle (hand), awaken (slot), luck (slot).
const SITE_BOSS := "veyr"
const SITE_PACK := "arsonists"
const SITE_SCENES := [
	{"name": "casino", "arena": "casino", "turn": 9, "detail": "card_wild_013", "frames": 34, "every": 0.07,
		"move": {"kind": "attack", "from": 2, "target": 1},
		"you": {"name": "NEONVIPER", "avatar": "card_wild_013", "leader": "card_wild_001", "morale": 4300, "auth": [4, 9], "mastery": 9,
			"front": [{"id": "card_wild_058", "burn": 300}, "card_wild_046", "card_wild_012", "card_wild_055", "card_wild_013"],
			"back": ["card_wild_017", {"id": "card_wild_016", "set": true}, null, {"id": "card_wild_018", "equip": 4}, null],
			"hand": ["card_wild_015", "card_wild_019", "card_wild_041", "card_wild_036", "card_wild_043"],
			"gutter": ["card_wild_010", "card_wild_042"], "vets": {"card_wild_013": 3, "card_wild_012": 2, "card_wild_046": 3, "card_wild_055": 1}},
		"foe": {"name": "SCORCHMARK", "avatar": "card_arso_033", "level": 41, "leader": "card_arso_001", "morale": 3100, "mastery": 8,
			"front": ["card_arso_034", {"id": "card_arso_025", "bleed": 200}, "card_arso_026", "card_arso_033", "card_arso_004"],
			"back": ["card_arso_039", null, {"id": "card_arso_031", "set": true}, null, {"id": "card_arso_038", "set": true}],
			"hand": ["card_arso_027", "card_arso_028", "card_arso_029", "card_arso_030"], "gutter": ["card_arso_022"],
			"vets": {"card_arso_033": 3, "card_arso_026": 2}}},
	{"name": "deploy", "arena": "base", "turn": 6, "phase": "deployment", "detail": "card_mili_044", "frames": 20, "every": 0.08,
		"move": {"kind": "summon", "hand": 0, "slot": 2},
		"you": {"name": "NEONVIPER", "avatar": "card_mili_040", "leader": "card_mili_011", "morale": 5200, "auth": [8, 8], "mastery": 7,
			"front": ["card_mili_037", "card_mili_046", null, "card_mili_058", "card_mili_009"],
			"back": [{"id": "card_mili_032", "set": true}, {"id": "card_mili_005", "set": true}, null, null, null],
			"hand": ["card_mili_044", "card_mili_052", "card_mili_013", "card_mili_031", "card_mili_040"],
			"gutter": ["card_mili_003"], "vets": {"card_mili_037": 2, "card_mili_044": 3, "card_mili_046": 1}},
		"foe": {"name": "GRAVEWALTZ", "avatar": "card_unde_045", "level": 28, "leader": "card_unde_001", "morale": 4700, "mastery": 6,
			"front": ["card_unde_034", "card_unde_002", "card_unde_045", "card_unde_002", "card_unde_013"],
			"back": ["card_unde_027", {"id": "card_unde_024", "set": true}, null, null, null],
			"hand": ["card_unde_021", "card_unde_022", "card_unde_026"], "gutter": ["card_unde_012", "card_unde_007"],
			"vets": {"card_unde_045": 3}}},
	{"name": "evolve", "arena": "observatory", "turn": 7, "detail": "card_nebu_012", "frames": 36, "every": 0.12,
		"move": {"kind": "attack", "from": 2, "target": 1},
		"you": {"name": "NEONVIPER", "avatar": "card_nebu_053", "leader": "card_nebu_009", "morale": 3900, "auth": [3, 8], "mastery": 9,
			"front": ["card_nebu_045", "card_nebu_025", "card_nebu_012", "card_nebu_042", "card_nebu_053"],
			"back": ["card_nebu_043", {"id": "card_nebu_026", "set": true}, null, null, null],
			"hand": ["card_nebu_027", "card_nebu_008", "card_nebu_054", "card_nebu_041"], "hideout": ["card_nebu_013", "card_nebu_014"],
			"gutter": ["card_nebu_011"], "vets": {"card_nebu_053": 3, "card_nebu_012": 2, "card_nebu_013": 2, "card_nebu_025": 1}},
		"foe": {"name": "SALTWATER", "avatar": "card_pira_036", "level": 33, "leader": "card_pira_001", "morale": 4400, "mastery": 7,
			"front": ["card_pira_024", {"id": "card_pira_020", "down": true}, "card_pira_036", "card_pira_034", "card_pira_026"],
			"back": ["card_pira_031", {"id": "card_pira_032", "set": true}, null, null, null],
			"hand": ["card_pira_027", "card_pira_028", "card_pira_029"], "gutter": ["card_pira_017"]}},
	{"name": "brawl", "arena": "docks", "turn": 8, "detail": "card_pira_038", "frames": 36, "every": 0.08,
		"move": {"kind": "attack", "from": 2, "target": 2},
		"you": {"name": "NEONVIPER", "avatar": "card_pira_038", "leader": "card_pira_040", "morale": 4600, "auth": [2, 9], "mastery": 8,
			"front": ["card_pira_033", "card_pira_035", "card_pira_038", "card_pira_037", "card_pira_013"],
			"back": ["card_pira_041", {"id": "card_pira_032", "set": true}, null, null, null],
			"hand": ["card_pira_030", "card_pira_028", "card_pira_027", "card_pira_026"],
			"gutter": ["card_pira_005", "card_pira_018"], "vets": {"card_pira_038": 3, "card_pira_033": 2, "card_pira_013": 2}},
		"foe": {"name": "IRONSIDE", "avatar": "card_mili_040", "level": 37, "leader": "card_mili_011", "morale": 3800, "mastery": 8,
			"front": ["card_mili_035", "card_mili_001", "card_mili_054", "card_mili_034", "card_mili_058"],
			"back": [{"id": "card_mili_005", "set": true}, {"id": "card_mili_031", "set": true}, null, null, null],
			"hand": ["card_mili_038", "card_mili_043", "card_mili_030"], "gutter": ["card_mili_002"]}},
	{"name": "ko", "arena": "graveyard", "turn": 10, "detail": "card_unde_045", "frames": 36, "every": 0.08,
		"move": {"kind": "attack", "from": 2, "target": 1},
		"you": {"name": "NEONVIPER", "avatar": "card_unde_045", "leader": "card_unde_001", "morale": 2900, "auth": [5, 10], "mastery": 9,
			"front": ["card_unde_002", "card_unde_011", "card_unde_045", "card_unde_036", "card_unde_002"],
			"back": ["card_unde_054", {"id": "card_unde_030", "equip": 1}, {"id": "card_unde_028", "set": true}, null, null],
			"hand": ["card_unde_026", "card_unde_021", "card_unde_029", "card_unde_047"],
			"gutter": ["card_unde_010", "card_unde_033", "card_unde_012"], "vets": {"card_unde_045": 3, "card_unde_011": 2}},
		"foe": {"name": "HIGHROLLER", "avatar": "card_wild_046", "level": 45, "leader": "card_wild_001", "morale": 2400, "mastery": 9,
			"front": ["card_wild_035", {"id": "card_wild_009", "down": true}, "card_wild_007", "card_wild_034", "card_wild_041"],
			"back": ["card_wild_056", {"id": "card_wild_057", "set": true}, null, null, null],
			"hand": ["card_wild_014", "card_wild_044"], "gutter": ["card_wild_005", "card_wild_033"], "vets": {"card_wild_007": 2}}},
	{"name": "ambush", "arena": "caldera", "turn": 8, "detail": "card_arso_037", "frames": 46, "every": 0.12,
		"move": {"kind": "attack", "from": 3, "target": 2, "spring": 7},
		"you": {"name": "NEONVIPER", "avatar": "card_mili_047", "leader": "card_mili_011", "morale": 4100, "auth": [3, 9], "mastery": 8,
			"front": ["card_mili_047", "card_mili_040", "card_mili_026", "card_mili_044", "card_mili_037"],
			"back": [{"id": "card_mili_013", "equip": 0}, null, null, null, null],
			"hand": ["card_mili_038", "card_mili_043", "card_mili_030", "card_mili_005"],
			"gutter": ["card_mili_015"], "vets": {"card_mili_040": 3, "card_mili_047": 2}},
		"foe": {"name": "SCORCHMARK", "avatar": "card_arso_033", "level": 41, "leader": "card_arso_001", "morale": 3500, "mastery": 8,
			"front": ["card_arso_022", "card_arso_013", "card_arso_021", "card_arso_020", "card_arso_016"],
			"back": [null, null, {"id": "card_arso_037", "set": true}, null, {"id": "card_arso_032", "set": true}],
			"hand": ["card_arso_027", "card_arso_028"], "gutter": ["card_arso_017"]}},
	{"name": "inferno", "arena": "junkyard", "turn": 9, "phase": "deployment", "detail": "card_arso_036", "frames": 36, "every": 0.1,
		"move": {"kind": "hustle", "hand": 0},
		"you": {"name": "NEONVIPER", "avatar": "card_arso_033", "leader": "card_arso_001", "awake": 2, "morale": 3300, "auth": [6, 10], "mastery": 9,
			"front": ["card_arso_033", "card_arso_034", null, "card_arso_025", "card_arso_010"],
			"back": ["card_arso_039", {"id": "card_arso_038", "set": true}, null, null, null],
			"hand": ["card_arso_036", "card_arso_028", "card_arso_027", "card_arso_029", "card_arso_026"],
			"gutter": ["card_arso_018", "card_arso_019"], "vets": {"card_arso_033": 3, "card_arso_001": 3, "card_arso_010": 2}},
		"foe": {"name": "STARDUST", "avatar": "card_nebu_048", "level": 36, "leader": "card_nebu_009", "morale": 3700, "mastery": 7,
			"front": ["card_nebu_024", "card_nebu_019", "card_nebu_028", {"id": "card_nebu_036", "poison": 200}, "card_nebu_033"],
			"back": [{"id": "card_nebu_029", "set": true}, null, null, null, null],
			"hand": ["card_nebu_010", "card_nebu_027"], "gutter": ["card_nebu_023"]}},
	{"name": "stasis", "arena": "frozen", "turn": 7, "detail": "card_nebu_029", "frames": 30, "every": 0.12,
		"move": {"kind": "attack", "from": 2, "target": 2, "spring": 5},
		"you": {"name": "NEONVIPER", "avatar": "card_unde_034", "leader": "card_unde_001", "morale": 3600, "auth": [2, 8], "mastery": 9,
			"front": ["card_unde_002", "card_unde_036", "card_unde_034", "card_unde_010", "card_unde_002"],
			"back": ["card_unde_027", null, null, null, null],
			"hand": ["card_unde_022", "card_unde_023", "card_unde_025"], "gutter": ["card_unde_008"], "vets": {"card_unde_034": 3}},
		"foe": {"name": "STARDUST", "avatar": "card_nebu_048", "level": 36, "leader": "card_nebu_009", "morale": 4200, "mastery": 7,
			"front": ["card_nebu_045", "card_nebu_047", "card_nebu_024", "card_nebu_019", "card_nebu_042"],
			"back": [{"id": "card_nebu_029", "set": true}, null, {"id": "card_nebu_026", "set": true}, null, null],
			"hand": ["card_nebu_041", "card_nebu_040"], "gutter": ["card_nebu_030"]}},
	{"name": "awaken", "arena": "clocktower", "turn": 11, "phase": "deployment", "detail": "card_pira_001", "frames": 18, "every": 0.12,
		"move": {"kind": "awaken", "slot": 2},
		"you": {"name": "NEONVIPER", "avatar": "card_pira_001", "leader": "card_pira_001", "morale": 2800, "auth": [7, 10], "mastery": 9,
			"front": ["card_pira_024", "card_pira_035", null, "card_pira_036", "card_pira_020"],
			"back": ["card_pira_031", {"id": "card_pira_032", "set": true}, null, null, null],
			"hand": ["card_pira_029", "card_pira_028", "card_pira_030"], "gutter": ["card_pira_002", "card_pira_022"],
			"vets": {"card_pira_001": 3, "card_pira_036": 2}},
		"foe": {"name": "GRAVEWALTZ", "avatar": "card_unde_045", "level": 28, "leader": "card_unde_001", "morale": 3400, "mastery": 6,
			"front": ["card_unde_033", "card_unde_002", "card_unde_034", "card_unde_002", "card_unde_010"],
			"back": ["card_unde_054", {"id": "card_unde_029", "set": true}, null, null, null],
			"hand": ["card_unde_021", "card_unde_022"], "gutter": ["card_unde_013"]}},
	{"name": "luck", "arena": "pit", "turn": 8, "detail": "card_wild_023", "frames": 16, "every": 0.09,
		"move": {"kind": "luck", "slot": 1},
		"you": {"name": "NEONVIPER", "avatar": "card_wild_046", "leader": "card_wild_001", "morale": 3600, "auth": [4, 9], "mastery": 9,
			"front": ["card_wild_052", "card_wild_023", "card_wild_049", "card_wild_004", "card_wild_029"],
			"back": [{"id": "card_wild_018", "equip": 1}, "card_wild_017", {"id": "card_wild_037", "set": true}, null, null],
			"hand": ["card_wild_015", "card_wild_036", "card_wild_044", "card_wild_019"], "gutter": ["card_wild_002"],
			"vets": {"card_wild_023": 3, "card_wild_049": 2, "card_wild_052": 1}},
		"foe": {"name": "STARDUST", "avatar": "card_nebu_048", "level": 36, "leader": "card_nebu_009", "morale": 4100, "mastery": 7,
			"front": ["card_nebu_048", {"id": "card_nebu_056", "stasis": true}, "card_nebu_045", "card_nebu_050", "card_nebu_032"],
			"back": ["card_nebu_046", null, {"id": "card_nebu_007", "set": true}, null, null],
			"hand": ["card_nebu_027", "card_nebu_008"], "gutter": ["card_nebu_004"], "vets": {"card_nebu_048": 3}}},
]


func _site_shots() -> void:
	Engine.time_scale = 1.0
	# A player with a name of their own (the plates in online matches show it)
	var r := await Api.request("POST", "/api/auth/login", {"email": "neonviper@example.com", "password": "x"})
	if r.ok:
		Api.token = r.data.token
		Game.player = r.data.player
	Game.settings.tutorial_offered = true
	Game.settings.last_seen_version = str(ProjectSettings.get_setting("application/config/version", ""))
	if not "--online-only" in OS.get_cmdline_user_args():   # (--online-only: just Turf Defense and the free-for-all again)
		for s in SITE_SCENES:
			await _site_scene(s)
		await _site_menus()
	await _site_online()


func _site_scene(s: Dictionary) -> void:
	var you: Dictionary = s.you
	var foe: Dictionary = s.foe
	Game.player.username = str(you.name)
	Game.player.level = 34
	Game.player.avatar_url = "card:" + str(you.avatar)
	Game.duel_setup = {"first": "player", "arena": str(s.arena)}
	Game.go("duel")
	await get_tree().create_timer(4.0).timeout
	var d = _screen()
	while d.get("_intro_on"):   # (the opening face-off plays first: duel.gd _match_intro)
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout
	var st = d.duel
	d.ai_sides = []
	get_viewport().warp_mouse(Vector2(4, 4))
	if d._menu:   # (the opening hand: keep it, so the events waiting on it play out)
		for b in d._menu.find_children("*", "Button", true, false):
			b.pressed.emit()
			break
	var waited := 0.0
	while d._playing and waited < 6.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	d._queue.clear()
	d._playing = false
	st.turn = int(s.get("turn", 8))
	st.active = "player"
	st.phase = str(s.get("phase", "brawl"))
	st.pending = {}
	st._asks = []
	_site_side(st, st.sides.player, you)
	_site_side(st, st.sides.opponent, foe)
	st._recalc()
	# The rival's plate as a player's (name, picture, level, clan mastery); yours with your mastery
	var opp: Panel = d.get_node("HUD/UI/OppPanel")
	for ch in opp.get_children():
		ch.queue_free()
	d._build_panel("opponent", opp, str(foe.name), "card:" + str(foe.avatar), "LV %d  ·  ONLINE" % int(foe.level), int(foe.level))
	d._names = {"player": str(you.name), "opponent": str(foe.name)}
	d._clan_line(opp, {"clan": str(CardDB.get_card(str(foe.leader)).clanTag), "clan_level": int(foe.mastery)})
	d._clan_line(d.get_node("HUD/UI/PlayerPanel"), {"clan": str(CardDB.get_card(str(you.leader)).clanTag), "clan_level": int(you.mastery)})
	# The board, from the staged state
	for side in ["player", "opponent"]:
		for v in d.hand[side]:
			v.queue_free()
		d.hand[side] = []
		for slot in d.field[side]:
			if d.field[side][slot] != null:
				d.field[side][slot].queue_free()
		d.field[side] = {}
	for side in d.leaders:
		d.leaders[side].queue_free()
	d.leaders.clear()
	for key in d._pile_backs:   # (the piles' moving backs, made with the first leader's clan: made again)
		d._pile_backs[key].rect.queue_free()
	d._pile_backs.clear()
	d._vets = {"player": you.get("vets", {}), "opponent": foe.get("vets", {})}
	d._make_leader_views()
	d._build_from_view()
	d.counts = st._counts()
	d._refresh_hud()
	d.queue_redraw()
	d._show_detail(CardDB.get_card(str(s.detail)))
	await _shot("site_%s_still" % s.name, 1.4)
	var mv: Dictionary = s.move
	var ok := true
	Engine.time_scale = 0.35   # (slowed, so the shots catch more of the move)
	match str(mv.kind):
		"attack":
			ok = d._act("player", {"kind": "attack", "from": int(mv.from), "target": int(mv.target)})
		"summon":
			d._phase_flash("DEPLOYMENT PHASE", d.BLUE)
			ok = d._act("player", {"kind": "summon", "uid": int(st.sides.player.hand[int(mv.hand)].uid), "slot": int(mv.slot)})
		"hustle":
			ok = d._act("player", {"kind": "hustle", "uid": int(st.sides.player.hand[int(mv.hand)].uid)})
		"awaken":
			var sd: Dictionary = st.sides.player
			sd.leader_state = "awake"
			sd.leader.deployed_turn = st.turn
			sd.field[int(mv.slot)] = sd.leader
			d._ev_awaken({"side": "player", "slot": int(mv.slot), "card": sd.leader.duplicate(true)})
		"luck":
			d._ev_luck({"side": "player", "slot": int(mv.slot), "kind": "coin", "value": 1, "won": true, "need": 1})
	# The questions the move raises, answered here (their events follow the move's in the queue): the
	# rival springs the Ambush the scene names or none; anything else takes its first option (e.g. ATK
	# for a card that promoted)
	var asked := 0
	while ok and not st.pending.is_empty() and asked < 6:
		asked += 1
		var side := str(st.pending.get("side", ""))
		var ids: Array = st.pending.get("options", []).map(func(o): return str(o.get("id", "")))
		var pick := ""
		if side == "opponent" and mv.has("spring") and ids.has(str(mv.spring)):
			pick = str(mv.spring)
		elif ids.has("no"):
			pick = "no"
		elif not ids.is_empty():
			pick = ids[0]
		if pick == "" or not st.do_action(side, {"kind": "choose", "option": pick}):
			break
		d._queue.append_array(st.take_events())
	print("site scene %s: the move %s (%d answered)" % [s.name, "went through" if ok else "was REFUSED", asked])
	for i in int(s.get("frames", 16)):
		await _shot("site_%s_%02d" % [s.name, i], float(s.get("every", 0.1)))
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.0).timeout


## One side of a staged match: its leader (Dormant, or on the street in slot "awake"), field, hand,
## Gutter, Hideout, a deck, Morale and Authority.
func _site_side(st, sd: Dictionary, p: Dictionary) -> void:
	var leader: Dictionary = st.make_card(str(p.leader))
	leader.influence = int(leader.influence) if leader.get("influence") != null else int(leader.base_defense)
	leader.influence_max = leader.influence
	sd.leader = leader
	sd.leader_state = "dormant"
	var field: Array = []
	field.resize(10)
	var front: Array = p.get("front", [])
	for i in front.size():
		if front[i] != null:
			field[i] = _site_card(st, front[i])
	var back: Array = p.get("back", [])
	for i in back.size():
		if back[i] != null:
			var c := _site_card(st, back[i])
			if back[i] is Dictionary and back[i].has("equip") and field[int(back[i].equip)] != null:
				c.equipped_to = field[int(back[i].equip)].uid
			field[5 + i] = c
	if p.has("awake"):
		sd.leader_state = "awake"
		leader.deployed_turn = 1
		field[int(p.awake)] = leader
	sd.field = field
	sd.hand = p.get("hand", []).map(func(e): return _site_card(st, e))
	sd.gutter = p.get("gutter", []).map(func(e): return _site_card(st, e))
	sd.hideout = p.get("hideout", []).map(func(e): return _site_card(st, e))
	sd.deck = []
	for i in 17:
		sd.deck.append(st.make_card(str(p.hand[0])))
	sd.morale = int(p.morale)
	sd.authority = int(p.auth[0]) if p.has("auth") else 4
	sd.authority_max = int(p.auth[1]) if p.has("auth") else 9


func _site_card(st, e) -> Dictionary:
	var spec: Dictionary = e if e is Dictionary else {"id": e}
	var c: Dictionary = st.make_card(str(spec.id))
	c.deployed_turn = 1
	if spec.get("down", false):
		c.downed = true
	if spec.get("def", false):
		c.position = "def"
	if spec.get("set", false):
		c.face_down = true
	if spec.has("burn"):
		c.burn = {"amt": int(spec.burn), "left": 3}
	if spec.has("poison"):
		c.poison = {"amt": int(spec.poison), "left": 3}
	if spec.has("bleed"):
		c.bleed = int(spec.bleed)
	for k in ["stasis", "freeze", "blind", "silence", "stun"]:
		if spec.get(k, false):
			c[k + "_until"] = st.turn + 1
	return c


## The menus, a pack opening (its Epic or better turning over), a victory and a rank up.
func _site_menus() -> void:
	for s in ["main_menu", "fight_mode", "card_library", "deck_builder", "territory", "shop"]:
		Game.go(s)
		await _shot("site_" + s, 2.8)
	var clan: Dictionary = CardDB.clan(SITE_PACK)
	_screen()._buy({"id": SITE_PACK, "label": str(clan.get("name", SITE_PACK)), "image": "%s_booster.png" % SITE_PACK, "color": clan.get("color", "#ff7a3d")}, "karat")
	await _shot("site_pack_ready", 1.8)
	var opening = _screen()._opening
	opening.tear_now()
	for i in 8:
		await _shot("site_pack_burst_%02d" % i, 0.12)
	await get_tree().create_timer(2.0).timeout
	for k in opening._cards:   # the Epic or better, at full length
		if k.rarity >= 4:
			opening._enqueue(k)
	for i in 26:
		await _shot("site_pack_epic_%02d" % i, 0.22)
	opening.reveal_all()
	await _shot("site_pack_done", 4.0)
	var session := await Api.request("POST", "/api/match/start", {"ranked": true})
	Game.match_result = {"result": "win", "player_morale": 2900, "opponent_morale": 0, "turns": 13, "cards_played": 11,
		"match_id": session.data.matchId if session.ok else "",
		"mvp": {"card": CardDB.get_card("card_unde_045"), "owner": "player", "damage": 4100, "kos": 3},
		"mastery": {"clan": "underworld", "name": "Underworld", "color": "#4f1c5e", "xp": 1250, "gained": 100,
			"levels": [0, 300, 700, 1200, 1800, 2500, 3300, 4200, 5200, 6300]}}
	Game.go("post_match")
	await _shot("site_victory", 2.6)
	_screen()._rank_up("underboss")
	await _shot("site_rank_up", 3.0)


## Turf Defense against SITE_BOSS with tests/online_bot.tscn as the partner (its entrance, then the fight),
## then a free-for-all (the mock server fills the table with CPUs of random clans).
func _site_online() -> void:
	Net.connect_to_server()
	await get_tree().create_timer(1.5).timeout
	Net.coop_join = {"boss": SITE_BOSS, "level": 1}
	Game.go("turf_defense")
	var waited := 0.0
	while _screen().name != "Duel" and waited < 120.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _screen().name == "Duel":
		for i in 26:   # the boss's entrance
			await _shot("site_turf_intro_%02d" % i, 0.4)
		for i in 14:
			await _shot("site_turf_%02d" % i, 5.0)
	else:
		print("site: no Turf Defense match (is the partner bot running?)")
	Game.go("ffa_lobby")
	await get_tree().create_timer(2.5).timeout
	_screen()._toggle_ready()
	waited = 0.0
	while _screen().name != "Duel" and waited < 90.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if _screen().name == "Duel":
		for i in 16:
			await _shot("site_ffa_%02d" % i, 7.0)


## Settings → Accessibility: the same screens with everything off ("acc_off_") and with Larger text and
## Colour-Blind Colours ("acc_on_"), to compare. Only the settings in memory change: nothing is saved.
func _access_shots() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	for run in [["off", 0, false], ["on", 2, true]]:
		var tag: String = run[0]
		Game.settings.text_size = run[1]
		Game.settings.cb_colors = run[2]
		UI.reset_theme()
		Game.go("main_menu")
		await get_tree().create_timer(2.0).timeout
		SettingsPanel.open(_screen())
		await get_tree().process_frame
		var panel: SettingsPanel = _screen().get_children().filter(func(c): return c is SettingsPanel)[0]
		panel._show("access")
		await _shot("acc_%s_settings" % tag, 0.6)
		panel.close()
		var htp: Control = load("res://scripts/ui/how_to_play.gd").open(_screen())
		htp._show("KEYWORDS")
		await _shot("acc_%s_keywords" % tag, 0.8)
		htp.queue_free()
		_screen()._show_patch_notes("0.6.0", version)
		await _shot("acc_%s_patch_notes" % tag, 1.4)
		var poison := ""   # (a card with a few keywords in its text, zoomed)
		for c in CardDB.all().values():
			if UI.Keywords.found(str(c.get("effectText", ""))).size() >= 3 and c.get("cardType") == "gang_member":
				poison = str(c.id)
				break
		Game.go("card_library")
		await get_tree().create_timer(2.4).timeout
		UI.card_zoom(_screen(), CardDB.get_card(poison), true)
		await _shot("acc_%s_zoom" % tag, 1.0)
		# A CPU match, both sides played by the CPU: the card panel, then the battle log
		Game.duel_setup = await Game.load_duel_deck()
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(4.5).timeout
		var d = _screen()
		if d._menu:   # (the opening hand: keep it)
			for b in d._menu.find_children("*", "Button", true, false):
				b.pressed.emit()
				break
		d.ai_sides = ["player", "opponent"]
		d._after_events()
		for i in 3:
			await _shot("acc_%s_duel_%d" % [tag, i], 9.0)
		d._show_detail(CardDB.get_card(poison), [900, 300], ["poison", "downed"])
		await _shot("acc_%s_duel_detail" % tag, 0.6)
		d._toggle_log()
		await _shot("acc_%s_duel_log" % tag, 0.6)


## The turf map (a district opened, last week's Karat claimed), veteran cards in the library and the
## zoom, a CPU match fought in a district (both sides' marks), and the post-match lines.
func _turf_map_shots() -> void:
	Game.go("main_menu")
	await _shot("t01_main_menu", 2.5)
	Game.go("territory")
	await _shot("t02_turf_map", 2.5)
	var tm = _screen()
	if tm._world and not tm._pins.is_empty():   # (a district hovered: its standings)
		var m: Control = tm._pins[5].get_child(0)
		m.mouse_entered.emit()
		await _shot("t02a_hint", 0.8)
		m.mouse_exited.emit()
	if tm._world:   # (the city: zoomed in on the middle, then back out)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		ev.position = Vector2(960, 560)
		for i in 5:
			tm._gui_input(ev)
		await _shot("t02b_zoomed", 1.5)
		tm._zoom_to = 1.0
		tm._pos_to = tm._clamp_pos(tm._pos_to, 1.0)
		await get_tree().create_timer(1.0).timeout
	tm._open(tm._data.districts[0])
	await _shot("t03_district", 0.8)
	tm._close()
	tm._claim()
	await _shot("t04_claimed", 1.2)
	Game.go("card_library")
	await get_tree().create_timer(2.5).timeout
	var lib = _screen()
	var best := ""
	for id in Game.veterans:
		if best == "" or Game.veteran_tier(id) > Game.veteran_tier(best):
			best = id
	if best != "":
		lib._show_detail(CardDB.get_card(best))
	await _shot("t05_library", 1.0)
	if best != "":
		UI.card_zoom(lib, CardDB.get_card(best), true)
	await _shot("t06_zoom", 1.0)
	Game.go("territory")
	await get_tree().create_timer(2.5).timeout
	# FIGHT HERE, as a player does it: open the district (its gang's stars), press it
	var map = _screen()
	map._open(map._data.districts[11])
	await _shot("t06a_district_stars", 0.8)
	for b in map.find_children("*", "Button", true, false):
		if "FIGHT HERE" in b.text:
			b.pressed.emit()
			break
	await _shot("t06c_arena", 1.2)
	await get_tree().create_timer(5.0).timeout
	print("fight here: now on ", get_tree().current_scene.scene_file_path, " arena ", Game.duel_setup.get("start", {}).get("arena", "?"), " wanted ", map._data.districts[11].id if is_instance_valid(map) else "(map gone)")
	if _screen() and _screen().get("_menu"):
		_screen()._menu.visible = false
	await _shot("t07_duel", 0.5)
	await _shot("t08_duel_later", 4.0)
	_screen()._countdown_box("WAITING FOR OPPONENT TO RECONNECT", "If they don't come back in time, you win.", 60, UI.GOLD)
	await _shot("t08b_reconnect", 1.5)
	_screen()._close_countdown()
	Game.match_result = {"result": "win", "online": true, "mode": "cpu", "turns": 9, "player_morale": 4200, "opponent_morale": 0,
		"rewards": {"outcome": "win", "karatEarned": 26, "xpEarned": 65, "newXp": int(Game.player.get("xp", 0)) + 65, "newLevel": int(Game.player.get("level", 1))},
		"veterans": [{"id": best, "tier": 3, "name": "Street Legend"}] if best != "" else [],
		"turf": {"district": "docks", "name": "The Docks", "clan": str(CardDB.clans()[0].id), "points": 2}}
	Game.go("post_match")
	await _shot("t09_post_match", 5.0)


## Frames drawn per second on each screen (V-Sync and the FPS cap off), after it has settled.
func _fps_run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for s in ["main_menu", "fight_mode", "card_library", "deck_builder", "shop", "profile", "achievements", "leaderboard", "social"]:
		Game.go(s)
		await get_tree().create_timer(2.5).timeout
		await _fps(s)
	var deck := await Game.load_duel_deck()
	Game.duel_setup = deck
	Game.duel_setup.first = "player"
	Game.go("duel")
	await get_tree().create_timer(4.0).timeout
	await _fps("duel")


func _fps(s: String) -> void:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(2.0).timeout
	print("fps %-14s %.0f" % [s, (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)])


## The Card Library's zoom and craft reveal in many quick shots, then the shop, to see each frame change.
func _craft_shots() -> void:
	Game.go("card_library")
	await get_tree().create_timer(2.0).timeout
	var lib = _screen()
	await _shot("c00_library", 0.1)
	Net.show_achievements([{"name": "Untouchable", "reward": {"dust": 300, "title": "Untouchable"}}])
	for i in 4:
		await _shot("c1%d_banner" % i, 0.3)
	for id in CardDB.all():
		var sc: Dictionary = CardDB.get_card(id)
		if CardDB.striver_stage(sc).x == 2:
			UI.card_zoom(lib, sc)
			break
	for i in 6:
		await _shot("c2%d_zoom" % i, 0.3)
	for t in lib._tiles.values():
		if int(t.card.get("rarity", 1)) >= 5:
			lib._reveal(t.card, t)
			break
	for i in 10:
		await _shot("c3%d_reveal" % i, 0.3)
	Game.go("shop")
	for i in 10:
		await _shot("c4%d_shop" % i, 0.5)


func _screen() -> Node:
	return get_tree().current_scene


## The auction house: browse (an auction picked, one with Buy Now), sell (a card picked, Buy Now offered),
## my auctions (my listing picked).
func _auction_shots() -> void:
	Game.go("main_menu")
	await _shot("a00_main_menu", 3.0)
	Game.go("auction_house")
	await _shot("a01_browse", 2.8)
	var ah = _screen()
	if not ah._auctions.is_empty():
		ah._picked = ah._auctions[0]
		ah._render()
		await _shot("a02_browse_picked", 1.2)
		for a in ah._auctions:
			if not a.get("leading", false) and not a.get("mine", false):
				ah._picked = a
				ah._render()
				await _shot("a03_browse_bid", 1.2)
				break
		for a in ah._auctions:
			if a.get("canBuyNow", false) and not a.get("mine", false):
				ah._picked = a
				ah._render()
				await _shot("a03b_buy_now", 1.2)
				break
		for a in ah._auctions:   # (a real bid on the local server: coins, the price punching, the balance ticking)
			if not a.get("leading", false) and not a.get("mine", false) and a.get("minBid") != null:
				ah._pick(a)
				await get_tree().create_timer(0.6).timeout
				ah._bid(a, int(a.minBid))
				await _shot("a03c_bid_coins", 0.45)
				await _shot("a03d_bid_done", 1.4)
				break
	ah._show("sell")
	await _shot("a04_sell", 2.0)
	if not ah._owned.is_empty():
		ah._picked = CardDB.get_card(str(ah._owned[0].get("art_url", "")))
		ah._render()
		await _shot("a05_sell_picked", 1.2)
		for c in ah._side.find_children("*", "CheckButton", true, false):
			(c as CheckButton).button_pressed = true   # (Buy Now offered)
		await _shot("a05b_sell_buy_now", 0.8)
		ah._do_list(ah._picked, 500 if int(ah._picked.get("rarity", 1)) >= 5 else 160, 0)   # (a real listing: the LISTED stamp)
		await _shot("a05c_listed", 0.6)
		await get_tree().create_timer(1.6).timeout
	ah._show("mine")
	await _shot("a06_mine", 2.0)
	for a in ah._auctions:
		if a.get("mine", false) and str(a.get("status", "")) == "active":
			ah._picked = a
			ah._render()
			await _shot("a07_mine_picked", 1.2)
			break


## 0.9.148's touches. In a match, slowed down so each shows: a stat change, BLOCKED, a heal streaming to
## the Morale, a leader hit and healed, a change of position, a card sent back to the hand, a discard,
## several statuses on one card, the card panel with the wordiest card (at the largest Text Size too).
## Then the Deck Builder's warnings with an empty Hideout, and the Shop's packs and starters.
func _polish_shots() -> void:
	var phone := Game.mobile()
	var n := 4 if phone else 7   # (shots per moment)
	Game.duel_setup = await Game.load_duel_deck()
	Game.duel_setup.first = "player"
	Game.duel_setup.arena = "alley"
	Game.go("duel")
	await get_tree().create_timer(4.5).timeout
	var d = _screen()
	if d._menu:
		d._menu.visible = false
	d._cancel_interaction()
	var units: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
	var turn := 4
	CardView.turn_now = turn
	var put := func(side: String, slot: int, k: int, statuses: Array, extra: Dictionary) -> CardView:
		var c: Dictionary = CardDB.get_card(units[k % units.size()]).duplicate()
		c.uid = 900 + slot + (10 if side == "player" else 0)
		c.position = "atk"
		c.merge(extra)
		var old = d.field[side].get(slot)
		if old:
			old.queue_free()
		var v: CardView = d._new_view(c, side, true)
		v.position = d.slot_pos(side, slot)
		v.home = v.position
		v.show_badge = true
		v.set_stats(int(c.attack), int(c.defense), int(c.attack), int(c.defense))
		v.statuses = statuses
		d.field[side][slot] = v
		return v
	for slot in 5:
		put.call("opponent", slot, 3 + slot * 4, [], {})
		put.call("player", slot, 23 + slot * 4, [], {})
	# A stat change: the first report of each card is quiet, the second shows what moved
	var values := func(changes: Dictionary) -> Dictionary:
		var out := {"player": {}, "opponent": {}}
		for side in out:
			for slot in 5:
				var v: CardView = d.field[side][slot]
				var ch: Array = changes.get("%s%d" % [side[0], slot], [0, 0])
				out[side][slot] = [int(v.card.attack) + ch[0], int(v.card.defense) + ch[1], int(v.card.attack), int(v.card.defense)]
		return out
	d._ev_stats({"values": values.call({})})
	await _shot("pol_board", 1.0)
	Engine.time_scale = 0.4
	d._ev_stats({"values": values.call({"p1": [300, 0], "p3": [200, 200], "o2": [-400, 0], "o4": [0, -200]})})
	for i in n + 1:
		await _shot("pol_stats_%02d" % i, 0.06)
	await get_tree().create_timer(0.5).timeout
	# BLOCKED: the rival's card in lane 2 holds
	d._ev_blocked({"side": "opponent", "slot": 2})
	for i in n:
		await _shot("pol_blocked_%02d" % i, 0.05)
	await get_tree().create_timer(0.5).timeout
	# A heal, from my card in lane 2 to my Morale
	var src: CardView = d.field["player"][2]
	d._queue = [{"type": "effect", "side": "player", "slot": 2, "card": src.card, "text": ""}]
	d._ev_heal({"side": "player", "amount": 500, "morale": int(d.duel.sides.player.morale) + 500})
	d._queue = []
	for i in n + 2:
		await _shot("pol_heal_%02d" % i, 0.06)
	await get_tree().create_timer(0.4).timeout
	# The leaders: the rival's hit, mine healed
	if d.leaders.has("opponent"):
		d._ev_leader_hit({"side": "opponent", "amount": 2, "influence": 8})
		for i in n - 2:
			await _shot("pol_leader_hit_%02d" % i, 0.05)
		await get_tree().create_timer(0.4).timeout
	if d.leaders.has("player"):
		d._ev_leader_heal({"side": "player", "amount": 2, "influence": 12})
		for i in n - 2:
			await _shot("pol_leader_heal_%02d" % i, 0.05)
		await get_tree().create_timer(0.4).timeout
	# A change of position, a card sent back to the hand, a discard
	var turned: Dictionary = d.field["player"][0].card.duplicate()
	turned.position = "def"
	d._ev_position({"side": "player", "slot": 0, "card": turned})
	for i in n - 2:
		await _shot("pol_position_%02d" % i, 0.05)
	await get_tree().create_timer(0.4).timeout
	d._ev_bounce({"side": "opponent", "slot": 0, "card": d.field["opponent"][0].card})
	for i in n - 2:
		await _shot("pol_bounce_%02d" % i, 0.05)
	await get_tree().create_timer(0.4).timeout
	if not d.hand.player.is_empty():
		d._ev_discard({"side": "player", "card": d.hand.player[0].card})
		for i in n:
			await _shot("pol_discard_%02d" % i, 0.08)
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.2).timeout
	# Several statuses on one card: one, two, three and five of them side by side
	put.call("player", 1, 27, ["burn"], {"burn": {"amt": 200, "left": 3}})
	put.call("player", 2, 31, ["burn", "poison"], {"burn": {"amt": 200, "left": 3}, "poison": {"amt": 300, "left": 2}})
	put.call("player", 3, 35, ["burn", "poison", "freeze"], {"burn": {"amt": 200, "left": 3}, "poison": {"amt": 300, "left": 2}, "freeze_until": turn + 1})
	put.call("player", 4, 39, ["burn", "poison", "bleed", "freeze", "resting"],
		{"burn": {"amt": 400, "left": 1}, "poison": {"amt": 100, "left": 3}, "bleed": 200, "freeze_until": turn + 1})
	await _shot("pol_statuses", 1.6)
	# The card panel: the wordiest character, then a plain one
	var wordiest: String = units[0]
	for id in units:
		if str(CardDB.get_card(id).get("effectText", "")).length() > str(CardDB.get_card(wordiest).get("effectText", "")).length():
			wordiest = id
	d._show_detail(CardDB.get_card(wordiest))
	await _shot("pol_panel_long", 0.8)
	d._show_detail(d.field["opponent"][1].card)
	await _shot("pol_panel_short", 0.6)
	if not phone:   # (the same card at the largest Text Size: a new match, as its labels are sized when it opens)
		Game.settings.text_size = 2
		UI.reset_theme()
		Game.duel_setup = await Game.load_duel_deck()
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(4.5).timeout
		d = _screen()
		if d._menu:
			d._menu.visible = false
		d._cancel_interaction()
		d._show_detail(CardDB.get_card(wordiest))
		await _shot("pol_panel_long_text2", 0.8)
		Game.settings.text_size = 0
		UI.reset_theme()
	# The Deck Builder with nothing in the Hideout (its Strivers can't promote), then the Shop
	Game.go("deck_builder")
	await _shot("pol_deck", 2.8)
	var db = _screen()
	db._hideout = []
	db._render_deck()
	db._render_stats()
	await _shot("pol_deck_warnings", 0.8)
	Game.go("shop")
	await _shot("pol_shop_packs", 2.8)
	_screen()._show("starters")
	await _shot("pol_shop_starters", 2.0)


## A controller button pressed and let go (scripts/pad.gd).
func _pad(button: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


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
	if "--polish" in OS.get_cmdline_user_args():   # (0.9.148's touches; with --phone --mobile, the same on a phone)
		await _polish_shots()
		get_tree().quit()
		return
	if "--rest" in OS.get_cmdline_user_args():   # (Achievements, every Settings tab, the Auction House, the turf map, Turf Defense, the lobbies)
		for s in ["achievements", "auction_house", "territory", "turf_defense", "fight_mode", "ffa_lobby", "matchmaking"]:
			Game.go(s)
			await _shot("r_" + s, 2.8)
		Game.go("main_menu")
		await get_tree().create_timer(1.5).timeout
		SettingsPanel.open(_screen())
		await get_tree().process_frame
		var sp: SettingsPanel = _screen().get_children().filter(func(c): return c is SettingsPanel)[0]
		for tab in sp._tabs.keys():
			sp._show(tab)
			await _shot("r_settings_" + str(tab), 0.5)
		get_tree().quit()
		return
	if "--site" in OS.get_cmdline_user_args():   # (the website's pictures)
		await _site_shots()
		get_tree().quit()
		return
	if "--auction" in OS.get_cmdline_user_args():
		await _auction_shots()
		get_tree().quit()
		return
	if "--seasons" in OS.get_cmdline_user_args():   # (the season's rewards; with SEASON_DONE=1 on the mock server, a reward to claim)
		Game.go("main_menu")
		await _shot("season_menu", 4.0)
		var waiting: Array = _screen().get_children().filter(func(c): return c.has_meta("ui_dialog"))
		if not waiting.is_empty():
			await _shot("season_claim", 0.6)
			for b in waiting[0].find_children("*", "Button", true, false):
				b.pressed.emit()
				break
			await _shot("season_claimed", 1.5)
		Game.go("fight_mode")
		await _shot("season_fight", 3.0)
		var s: Dictionary = await load("res://scripts/ui/seasons.gd").fetch()
		load("res://scripts/ui/seasons.gd").rewards(_screen(), s)
		await _shot("season_rewards", 1.0)
		get_tree().quit()
		return
	if "--obtain" in OS.get_cmdline_user_args():   # (the Card Library's HOW TO GET IT: a clan card, a Neutral one, a
		# ranked season's prize, a boss's prize, a Striver's LV2, and the wordiest card at the largest Text Size)
		Game.go("card_library")
		await get_tree().create_timer(3.0).timeout
		var neutral := ""
		var lv2 := ""
		var wordiest := ""
		for id in CardDB.all():
			var oc: Dictionary = CardDB.get_card(id)
			if neutral == "" and str(oc.get("clan", "")) == "neutral" and oc.get("cardType") == "gang_member":
				neutral = id
			if lv2 == "" and CardDB.striver_stage(oc).x == 2:
				lv2 = id
			if not oc.get("token", false) and (wordiest == "" or str(oc.get("effectText", "")).length() > str(CardDB.get_card(wordiest).get("effectText", "")).length()):
				wordiest = id
		for id in ["card_pira_034", neutral, "card_pira_038", "card_pira_033", lv2, wordiest]:
			_screen()._show_detail(CardDB.get_card(id))
			await _shot("obtain_%s" % id, 0.8)
		Game.settings.text_size = 2
		UI.reset_theme()
		_screen()._detail_id = "-"
		_screen()._show_detail(CardDB.get_card(wordiest))
		await _shot("obtain_wordiest_text2", 0.8)
		Game.settings.text_size = 0
		UI.reset_theme()
		get_tree().quit()
		return
	if "--zooms" in OS.get_cmdline_user_args():   # (the card zoom: a Striver's levels and how each promotes, the
		# wordiest one at the largest Text Size too; an opponent's card with its card XP)
		Game.go("card_library")
		await get_tree().create_timer(2.5).timeout
		var wordiest := ""
		for id in CardDB.all():
			var sc: Dictionary = CardDB.get_card(id)
			if CardDB.striver_stage(sc).x == 2 and (wordiest == "" or str(sc.get("effectText", "")).length() > str(CardDB.get_card(wordiest).get("effectText", "")).length()):
				wordiest = id
		for size in [0, 2]:
			Game.settings.text_size = size
			UI.reset_theme()
			var before := _screen().get_children()
			UI.card_zoom(_screen(), CardDB.get_card(wordiest), true)
			await _shot("zoom_striver_text%d" % size, 0.8)
			for v in _screen().get_children().filter(func(c): return not c in before):   # (the zoom: closed)
				v.queue_free()
			await get_tree().process_frame
		Game.settings.text_size = 0
		UI.reset_theme()
		var theirs: Dictionary = CardDB.get_card(wordiest).duplicate()
		theirs.veteran = 1
		theirs.vet_xp = 31
		theirs.mine = false
		UI.card_zoom(_screen(), theirs, true)
		await _shot("zoom_theirs", 0.8)
		get_tree().quit()
		return
	if "--access" in OS.get_cmdline_user_args():   # (Settings → Accessibility, off and on)
		await _access_shots()
		get_tree().quit()
		return
	if "--school" in OS.get_cmdline_user_args():   # (every Street School page)
		Game.go("main_menu")
		await get_tree().create_timer(2.5).timeout
		var school = load("res://scripts/ui/card_school.gd").open(_screen())
		await get_tree().process_frame
		for i in school._pages.size():
			school._go(i)
			await _shot("s%02d" % i, 1.6)
		get_tree().quit()
		return
	if "--display-click" in OS.get_cmdline_user_args():   # (clicks the Resolution row's arrows like a player, in each window mode)
		Game.go("main_menu")
		await get_tree().create_timer(1.5).timeout
		var panel := SettingsPanel.open(_screen())
		await get_tree().process_frame
		panel._show("display")
		await get_tree().create_timer(0.3).timeout
		var arrow := func(row_label: String, which: String) -> Button:
			for row in panel._body.get_children():
				if row is HBoxContainer and row.get_child_count() > 1 and row.get_child(0) is Label and row.get_child(0).text == row_label:
					for b in row.get_child(1).get_children():
						if b is Button and b.text == which:
							return b
			return null
		var click := func(b: Button):
			var at: Vector2 = get_viewport().get_screen_transform() * b.get_global_rect().get_center()
			var mv := InputEventMouseMotion.new(); mv.position = at; mv.global_position = at
			Input.parse_input_event(mv)
			await get_tree().process_frame
			var hov := get_viewport().gui_get_hovered_control()
			print("  click at ", at, " for ", b.get_global_rect(), " screen xf ", get_viewport().get_screen_transform(), " hovered ", hov.get_class() + ":" + (hov.text if hov is Button else "") if hov else "none")
			for pressed in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = at; e.global_position = at
				Input.parse_input_event(e)
				await get_tree().process_frame
			await get_tree().create_timer(0.8).timeout
		var report := func(what: String):
			var rb: Button = arrow.call("Resolution", "▶")
			var lbl := ""
			if rb: lbl = rb.get_parent().get_child(1).text
			print("CLICK %s -> mode %s res %s label '%s' window %s drawn %s" % [what, Game.settings.window_mode, Game.settings.resolution,
				lbl, DisplayServer.window_get_size(), get_viewport().get_texture().get_image().get_size()])
		await report.call("start")
		for i in 6:
			await click.call(arrow.call("Resolution", "▶" if i < 4 else "◀"))
			await report.call("res " + ("▶" if i < 4 else "◀"))
		await click.call(arrow.call("Window Mode", "◀"))   # fullscreen -> windowed
		await get_tree().create_timer(0.5).timeout
		await report.call("mode ◀")
		for i in 6:
			await click.call(arrow.call("Resolution", "▶" if i < 4 else "◀"))
			await report.call("res " + ("▶" if i < 4 else "◀"))
		get_tree().quit()
		return
	if "--display-steps" in OS.get_cmdline_user_args():   # (window mode / resolution changes: the real window after each)
		var show := func(what: String):
			await get_tree().create_timer(0.8).timeout
			print("DISPLAY %s -> mode %d size %s pos %s screen %s usable %s" % [what, DisplayServer.window_get_mode(),
				DisplayServer.window_get_size(), DisplayServer.window_get_position(),
				DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()),
				DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size])
		await show.call("start (%s %s)" % [Game.settings.window_mode, Game.settings.resolution])
		Game.go("main_menu")
		for step in [["window_mode", "fullscreen"], ["window_mode", "windowed"],
				["resolution", "1600x900"], ["resolution", "1280x720"], ["window_mode", "exclusive"],
				["window_mode", "windowed"], ["window_mode", "fullscreen"]]:
			Game.set_setting(step[0], step[1])
			await show.call("%s=%s" % step)
			print("  drawn at ", get_viewport().get_texture().get_size(), " visible ", get_viewport().get_visible_rect().size)
			if step[1] == "1280x720":
				await _shot("ds_fullscreen_720", 0.5)
		get_tree().quit()
		return
	if "--display" in OS.get_cmdline_user_args():   # (Settings → Display: window, resolution, graphics quality)
		Game.go("main_menu")
		await get_tree().create_timer(1.5).timeout
		var panel := SettingsPanel.open(_screen())
		await get_tree().process_frame
		panel._show("display")
		await _shot("d01_display", 1.0)
		get_tree().quit()
		return
	if "--veteran-frames" in OS.get_cmdline_user_args():   # (a character of each clan at each veteran tier: plain, bronze, chrome, gold)
		Game.go("main_menu")
		await get_tree().create_timer(1.5).timeout
		var veil := ColorRect.new()
		veil.color = Color(0.05, 0.05, 0.08)
		veil.size = Vector2(1920, 1080)
		_screen().add_child(veil)
		var picks := {}
		for id in CardDB.all():
			var c: Dictionary = CardDB.all()[id]
			if c.get("cardType") == "gang_member" and not c.get("token", false) and not picks.has(c.get("clan")):
				picks[c.get("clan")] = c
		var row := 0
		for clan in picks:
			for i in 4:
				var tile := CardTile.make(picks[clan], Vector2(176, 249))
				tile.veteran = i
				tile.position = Vector2(30 + (row % 2) * 950 + i * 228, 20 + (row / 2) * 262)
				veil.add_child(tile)
			row += 1
		await _shot("v01_frames", 1.5)
		get_tree().quit()
		return
	if "--turf-map" in OS.get_cmdline_user_args():   # (the turf map, veteran cards, a CPU match in a district)
		await _turf_map_shots()
		get_tree().quit()
		return
	if "--fps" in OS.get_cmdline_user_args():   # (frames per second on each screen, no shots)
		await _fps_run()
		get_tree().quit()
		return
	if "--perf-library" in OS.get_cmdline_user_args():   # (what the Card Library's frame time goes on)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		Game.go("card_library")
		await get_tree().create_timer(3.0).timeout
		await _fps("library")
		var tiles: Array = _screen()._tiles.values()
		for t in tiles:
			if t._sweep:
				t._sweep.visible = false
		await _fps("no sweeps")
		for t in tiles:
			t._art.material = null
		await _fps("+ no shader")
		for n in _screen().find_children("*", "Node2D", true, false):
			if n.material is ShaderMaterial:
				n.visible = false
		await _fps("+ no glass")
		for t in tiles:
			t.visible = false
		await _fps("+ no tiles")
		get_tree().quit()
		return
	if "--arenas" in OS.get_cmdline_user_args():   # (every 1v1 arena in a duel: its board and its life)
		var only: Array = []   # (--arena-ids=a,b: just those)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--arena-ids="):
				only = a.trim_prefix("--arena-ids=").split(",")
		for arena in load("res://scripts/ui/arena_roulette.gd").arenas():
			if not only.is_empty() and not str(arena.id) in only:
				continue
			var deck := await Game.load_duel_deck()
			Game.duel_setup = deck
			Game.duel_setup.first = "player"
			Game.duel_setup.arena = str(arena.id)
			Game.go("duel")
			await get_tree().create_timer(3.5).timeout
			if _screen()._menu:
				_screen()._menu.visible = false
			for a in OS.get_cmdline_user_args():   # (--gutter=<card id>: that card on top of both Gutters)
				if a.begins_with("--gutter="):
					for side in ["player", "opponent"]:
						_screen().counts[side]["gutter"] = 5
						_screen().counts[side]["gutter_top"] = a.trim_prefix("--gutter=")
					_screen().queue_redraw()
			if "--marked" in OS.get_cmdline_user_args():   # (MARKED: the rival's hand shows its faces to you)
				_screen().duel.sides.player.field[5] = {"uid": 99999, "id": "marked", "name": "Marked Cards", "cardType": "hustle",
					"effects": [{"when": "passive", "do": "reveal"}], "face_down": false}
			await _shot("ar_%s" % arena.id, 1.5)
			await _shot("ar_%s_b" % arena.id, 0.9)
		get_tree().quit()
		return
	if "--phone" in OS.get_cmdline_user_args():   # (with --mobile, in a phone-shaped window, e.g. --resolution 1200x540)
		for s in ["main_menu", "fight_mode", "deck_builder", "card_library", "shop", "territory", "profile"]:
			Game.go(s)
			await _shot("ph_" + s, 2.8)
		UI.dialog(_screen(), "A DIALOG", "Its dimmer reaches the edges of the screen.", [["OK", func(): pass]])
		await _shot("ph_dialog", 0.8)
		var deck8 := await Game.load_duel_deck()
		Game.duel_setup = deck8
		Game.duel_setup.first = "player"
		Game.go("duel")
		await _shot("ph_duel_open", 5.0)
		var pd = _screen()
		if pd._menu:   # (the opening hand: keep it)
			for bt in pd._menu.find_children("*", "Button", true, false):
				bt.pressed.emit()
				break
		await _shot("ph_duel", 3.0)
		if not pd.hand.player.is_empty():   # (a card in the card panel, as when a finger is on it)
			pd._show_detail(pd.hand.player[0].card)
			await _shot("ph_duel_card", 0.6)
		get_tree().quit()
		return
	if "--wild-attack" in OS.get_cmdline_user_args():   # (Wildcard's card-throwing attack, a shot every 0.08 s)
		var deck := await Game.load_duel_deck()
		Game.duel_setup = deck
		Game.duel_setup.first = "player"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var d = _screen()
		if d._menu:
			d._menu.visible = false
		var ids: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		var ac: Dictionary = CardDB.get_card(ids[0]).duplicate()
		ac.clanTag = "wildcard"
		var a = d._new_view(ac, "player", true)
		a.position = d.slot_pos("player", 2)
		a.home = a.position
		var dv = d._new_view(CardDB.get_card(ids[1]).duplicate(), "opponent", true)
		dv.position = d.slot_pos("opponent", 2)
		dv.home = dv.position
		var tpos: Vector2 = dv.home
		d._card_strike(a, dv, tpos, (tpos - a.home).normalized(), true, false)
		for i in 28:
			await _shot("w%02d" % i, 0.05)
		get_tree().quit()
		return
	if "--account" in OS.get_cmdline_user_args():   # (Settings → Account, and the login screen's register mode with its links)
		Game.go("main_menu")
		await get_tree().create_timer(2.5).timeout
		SettingsPanel.open(_screen())._show("account")
		await _shot("acc_settings", 0.8)
		Game.go("login")
		await get_tree().create_timer(2.0).timeout
		_screen()._toggle_mode()
		await _shot("acc_register", 0.6)
		get_tree().quit()
		return
	if "--pad" in OS.get_cmdline_user_args():   # (the controller's pointer and outline on each screen, after D-pad presses)
		for s in [["main_menu", [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT]], ["deck_builder", [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_DOWN]],
				["shop", [JOY_BUTTON_DPAD_DOWN]], ["card_library", [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT]]]:
			Game.go(s[0])
			await get_tree().create_timer(2.5).timeout
			for b in s[1]:
				await _pad(b)
			await _shot("pad_" + s[0], 0.4)
		SettingsPanel.open(_screen())._show("controls")
		await _shot("pad_settings_controls", 0.8)
		var deck7 := await Game.load_duel_deck()
		Game.duel_setup = deck7
		Game.duel_setup.first = "player"
		Game.go("duel")
		await get_tree().create_timer(5.0).timeout
		var pd = _screen()
		if pd._menu:   # (the opening hand: keep it)
			for bt in pd._menu.find_children("*", "Button", true, false):
				bt.pressed.emit()
				break
		await get_tree().create_timer(2.5).timeout
		await _pad(JOY_BUTTON_DPAD_DOWN)
		await _pad(JOY_BUTTON_DPAD_DOWN)
		await _shot("pad_duel_hand", 0.6)
		await _pad(JOY_BUTTON_A)
		await _shot("pad_duel_menu", 0.6)
		get_tree().quit()
		return
	if "--luck-fx" in OS.get_cmdline_user_args():   # (coin flips and die rolls, frame by frame; the menu bar; victory and defeat)
		Game.go("main_menu")
		await _shot("lk_menu", 2.5)
		var deck6 := await Game.load_duel_deck()
		Game.duel_setup = deck6
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "casino"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var y = _screen()
		if y._menu:
			y._menu.visible = false
		for roll in [["coin", 1, true], ["die", 5, true], ["coin", 0, false], ["die", 1, false]]:
			y._ev_luck({"side": "player", "slot": -1, "kind": roll[0], "value": roll[1], "won": roll[2], "need": 4 if roll[0] == "die" else 1})
			for i in 14:
				await _shot("lk_%s%d_%02d" % [roll[0], roll[1], i], 0.09)
			await get_tree().create_timer(1.2).timeout
		for res in ["win", "loss"]:
			Game.match_result = {"result": res, "player_morale": 3400 if res == "win" else 0, "opponent_morale": 0 if res == "win" else 2100, "turns": 12}
			Game.go("post_match")
			await _shot("lk_post_%s" % res, 3.0)
		get_tree().quit()
		return
	if "--duel-fx" in OS.get_cmdline_user_args():   # (the words over the table: turn, phase, an ability going off, a Hustle; shots every 0.1 s)
		var deck6 := await Game.load_duel_deck()
		Game.duel_setup = deck6
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(4.5).timeout
		var d = _screen()
		if d._menu:
			d._menu.visible = false
		var all_ids: Array = CardDB.all().keys()
		var of := func(kind: String, n: int) -> Dictionary:
			var ids: Array = all_ids.filter(func(i): return CardDB.get_card(i).get("cardType") == kind)
			return CardDB.get_card(ids[n % ids.size()]).duplicate()
		var mine: Dictionary = of.call("gang_member", 3)
		var theirs: Dictionary = of.call("gang_member", 11)
		var pv = d._new_view(mine, "player", true)
		pv.position = d.slot_pos("player", 1)
		pv.home = pv.position
		d.field["player"][1] = pv
		var ov = d._new_view(theirs, "opponent", true)
		ov.position = d.slot_pos("opponent", 3)
		ov.home = ov.position
		d.field["opponent"][3] = ov
		d._sweep_banner("YOUR TURN", d.BLUE)
		for i in 12:
			await _shot("dfx_turn_%02d" % i, 0.1)
		d._sweep_banner("THE OPPONENT'S TURN", d.RED)
		for i in 6:
			await _shot("dfx_turn2_%02d" % i, 0.1)
		await get_tree().create_timer(0.8).timeout
		d._phase_flash("BRAWL PHASE", d.BLUE)
		for i in 7:
			await _shot("dfx_phase_%02d" % i, 0.1)
		d._ev_effect({"side": "player", "slot": 1, "card": mine, "text": "%s gives %s -500 ATK and DOWNS it" % [mine.name, theirs.name]})
		for i in 16:
			await _shot("dfx_ability_%02d" % i, 0.1)
		await get_tree().create_timer(0.4).timeout
		d._ev_effect({"side": "opponent", "slot": 3, "card": theirs, "text": "%s: DRAW 2 cards, then DISCARD 1. Each character the opponent controls loses 300 DEF until the end of the turn, and %s gains ARMOR 1" % [theirs.name, theirs.name]})
		for i in 8:
			await _shot("dfx_ability2_%02d" % i, 0.1)
		await get_tree().create_timer(1.0).timeout
		var boss: Dictionary = of.call("leader", 0)
		d._ev_effect({"side": "player", "slot": -1, "card": boss, "text": "%s AWAKENS: every character you control gains 500 ATK" % boss.name})
		for i in 6:
			await _shot("dfx_leader_%02d" % i, 0.1)
		await get_tree().create_timer(1.2).timeout
		d._ev_effect({"side": "player", "slot": -1, "card": {}, "text": "The turn timer ran out"})
		await _shot("dfx_nocard", 0.4)
		await get_tree().create_timer(1.4).timeout
		var h: Dictionary = of.call("hustle", 2)
		d._action_tag(Vector2(1080, 424 + 250), "HUSTLE", d.BLUE, str(h.name))
		for i in 8:
			await _shot("dfx_hustle_%02d" % i, 0.1)
		d._action_tag(pv.home + Vector2(0, -128), "EQUIPPED", d.GOLD)
		d._action_tag(Vector2(1080, 424 + 250), "CONTINUOUS", d.GOLD, "A very long card name to fit, the Third")
		for i in 4:
			await _shot("dfx_equip_%02d" % i, 0.1)
		await get_tree().create_timer(0.8).timeout
		d._stamp(ov.position, "K.O.", Color(1, 0.35, 0.2))
		d._stamp(pv.position, "DOWNED", d.RED)
		d._float_text(Vector2(1080, 424), "BRAWL!", d.GOLD, 34)
		d._float_text(Vector2(1080, 300), "AMBUSH!", d.RED, 64)
		d._float_text(Vector2(700, 520), "-500", d.RED, 30)
		for i in 5:
			await _shot("dfx_stamp_%02d" % i, 0.1)
		await get_tree().create_timer(0.8).timeout
		d._splash_name(str(mine.name), d.GOLD, 424 + 265.0)
		await _shot("dfx_splash", 0.4)
		await get_tree().create_timer(1.0).timeout
		d._show_choice({"prompt": "Use %s's ability?" % mine.name, "card": mine, "key": "yn", "options": [{"id": "yes", "label": "YES"}, {"id": "skip", "label": "NO"}]})
		await _shot("dfx_choice", 0.5)
		d._cancel_interaction()
		if d._menu:
			d._menu.queue_free()
		d._toggle_log()
		await _shot("dfx_log", 0.5)
		get_tree().quit()
		return
	if "--menus" in OS.get_cmdline_user_args():   # (the menu screens only: profile, leaderboard, mailbox, social club, card library)
		for s in ["profile", "leaderboard", "mailbox", "social", "card_library"]:
			Game.go(s)
			await _shot("02_" + s, 2.6)
		get_tree().quit()
		return
	if "--hud" in OS.get_cmdline_user_args():   # (the match HUD: the opening hand, the phase track and End Turn, the battle log)
		Game.duel_setup = await Game.load_duel_deck()
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(4.5).timeout
		var d = _screen()
		await _shot("hud_mulligan", 0.8)
		if d._menu:
			for b in d._menu.find_children("*", "Button", true, false):
				b.pressed.emit()
				break
		await _shot("hud_my_turn", 4.0)
		d.ai_sides = ["player", "opponent"]   # (the CPU plays both hands: phases, turns and log lines go by)
		d._after_events()
		for i in 10:
			await _shot("hud_play_%02d" % i, 4.0)
		d._toggle_log()
		await _shot("hud_log", 0.8)
		await _shot("hud_log_later", 8.0)
		get_tree().quit()
		return
	if "--status-fx" in OS.get_cmdline_user_args():   # (statuses on cards in play: steady, landing and ticking; shots every 0.1 s)
		if "--safe" in OS.get_cmdline_user_args():   # (with Photosensitive mode and the colour-blind colours on)
			Game.settings.photosensitive = true
			Game.settings.cb_colors = true
		var deck7 := await Game.load_duel_deck()
		Game.duel_setup = deck7
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(4.5).timeout
		var d = _screen()
		if d._menu:
			d._menu.visible = false
		d._cancel_interaction()
		var units: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		var turn := 4
		CardView.turn_now = turn
		var put := func(side: String, slot: int, n: int, statuses: Array, extra: Dictionary, def: bool) -> CardView:
			var c: Dictionary = CardDB.get_card(units[n % units.size()]).duplicate()
			c.uid = 900 + slot + (10 if side == "player" else 0)
			c.merge(extra)
			var old = d.field[side].get(slot)
			if old:
				old.queue_free()
			var v: CardView = d._new_view(c, side, true)
			v.position = d.slot_pos(side, slot)
			v.home = v.position
			if def:
				v.rotation = PI / 2
				v.home_rot = PI / 2
			v.show_badge = true
			v.set_stats(int(c.attack), int(c.defense), int(c.attack), int(c.defense))
			v.statuses = statuses
			d.field[side][slot] = v
			return v
		# Every status, steady: the top row one each, the bottom row the rest and a card with several
		put.call("opponent", 0, 3, ["burn"], {"burn": {"amt": 200, "left": 3}}, false)
		put.call("opponent", 1, 7, ["freeze"], {"freeze_until": turn + 1}, true)
		put.call("opponent", 2, 11, ["poison"], {"poison": {"amt": 300, "left": 2}}, false)
		put.call("opponent", 3, 15, ["bleed"], {"bleed": 100}, false)
		put.call("opponent", 4, 19, ["blind"], {"blind_until": turn}, false)
		var shielded: CardView = put.call("player", 0, 23, ["shield"], {}, false)
		put.call("player", 1, 27, ["stun", "suppress"], {"stun_until": turn, "suppress_until": turn + 1}, false)
		put.call("player", 2, 31, ["stasis"], {"stasis_until": turn + 2}, false)
		put.call("player", 3, 35, ["silence", "equipped"], {"silence_until": turn + 1}, true)
		var many: CardView = put.call("player", 4, 39, ["burn", "poison", "bleed", "freeze", "resting"],
			{"burn": {"amt": 400, "left": 1}, "poison": {"amt": 100, "left": 3}, "bleed": 200, "freeze_until": turn + 1}, false)
		await _shot("st_steady", 1.6)
		await _shot("st_steady2", 0.7)
		many.hovered = true
		shielded.hovered = true
		d.field["opponent"][1].hovered = true
		d.field["opponent"][0].hovered = true
		await _shot("st_hover", 0.5)
		d._show_detail(many.card, many.stats(), d._live_statuses(many))
		await _shot("st_panel", 0.3)
		for side in ["player", "opponent"]:
			for slot in 5:
				d.field[side][slot].hovered = false
		# Each one landing, from the player's card in lane 2 (shots every 0.1 s)
		var src: CardView = put.call("player", 2, 31, [], {}, false)
		var lanes := {"burn": 0, "freeze": 1, "poison": 2, "bleed": 3, "blind": 4, "shock": 2, "stun": 3, "stasis": 0, "suppress": 4, "silence": 1}
		var cards := {"burn": {"burn": {"amt": 200, "left": 3}}, "poison": {"poison": {"amt": 300, "left": 3}}, "bleed": {"bleed": 100},
			"freeze": {"freeze_until": turn + 1}, "blind": {"blind_until": turn + 1}, "stun": {"stun_until": turn + 1},
			"stasis": {"stasis_until": turn + 1}, "suppress": {"suppress_until": turn + 1}, "silence": {"silence_until": turn + 1}}
		for slot in 5:
			put.call("opponent", slot, 3 + slot * 4, [], {}, false)
		await get_tree().create_timer(0.6).timeout
		for kind in lanes:
			var tv: CardView = d.field["opponent"][lanes[kind]]
			var c2: Dictionary = tv.card.duplicate()
			c2.merge(cards.get(kind, {}), true)
			d._queue = [{"type": "effect", "side": "player", "slot": 2, "card": src.card, "text": ""}]
			d._ev_status({"side": "opponent", "slot": lanes[kind], "kind": kind, "card": c2})
			d._queue = []
			for i in (8 if kind in ["burn", "freeze", "shock", "blind"] else 5):
				await _shot("st_land_%s_%02d" % [kind, i], 0.1)
			await get_tree().create_timer(0.3).timeout
		await _shot("st_landed", 0.8)
		# One effect on the whole row, from the leader
		for slot in 5:
			put.call("opponent", slot, 3 + slot * 4, [], {}, false)
		var boss: Dictionary = CardDB.get_card(CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "leader")[0]).duplicate()
		var row: Array = []
		for slot in 5:
			var c3: Dictionary = d.field["opponent"][slot].card.duplicate()
			c3.burn = {"amt": 200, "left": 3}
			row.append({"type": "status", "side": "opponent", "slot": slot, "kind": "burn", "card": c3})
		row.append({"type": "effect", "side": "player", "slot": -1, "card": boss, "text": "%s burns 5 enemies" % boss.name})
		var play_row := func():
			while not row.is_empty():
				var ev: Dictionary = row.pop_front()
				d._queue = row.duplicate()
				if ev.type == "status":
					await d._ev_status(ev)
				else:
					d._queue = []
					await d._ev_effect(ev)
		play_row.call()
		for i in 12:
			await _shot("st_row_%02d" % i, 0.1)
		await get_tree().create_timer(1.2).timeout
		# The ticks: BURN (its cost flies to the Morale bar), POISON, BLEED
		var bv: CardView = d.field["opponent"][1]
		var bc: Dictionary = bv.card.duplicate()
		bc.burn = {"amt": 200, "left": 2}
		var tick := func():
			await d._ev_status_tick({"side": "opponent", "slot": 1, "kind": "burn", "amount": 200, "card": bc})
			await d._ev_damage({"side": "opponent", "amount": 200, "morale": 7800})
		tick.call()
		for i in 10:
			await _shot("st_tick_burn_%02d" % i, 0.1)
		var pv2: CardView = put.call("opponent", 3, 15, ["poison", "bleed"], {"poison": {"amt": 300, "left": 2}, "bleed": 100}, false)
		await get_tree().create_timer(1.0).timeout
		var pc: Dictionary = pv2.card.duplicate()
		pc.poison = {"amt": 300, "left": 1}
		d._ev_status_tick({"side": "opponent", "slot": 3, "kind": "poison", "amount": 300, "card": pc})
		for i in 5:
			await _shot("st_tick_poison_%02d" % i, 0.1)
		d._ev_status_tick({"side": "opponent", "slot": 3, "kind": "bleed", "amount": 100, "card": pc})
		for i in 4:
			await _shot("st_tick_bleed_%02d" % i, 0.1)
		get_tree().quit()
		return
	if "--clan-fx" in OS.get_cmdline_user_args():   # (each clan's summon then attack: shots every 0.1 s / 0.08 s)
		var deck5 := await Game.load_duel_deck()
		Game.duel_setup = deck5
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var x = _screen()
		if x._menu:
			x._menu.visible = false
		var units: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		for clan in ["nebula", "militia", "wildcard", "underworld"]:
			var c: Dictionary = CardDB.get_card(units[0]).duplicate()
			c.clanTag = clan
			var v = x._new_view(c, "player", true)
			v.z_index = 420
			var at: Vector2 = x.slot_pos("player", 1)
			v.position = at
			v.home = at
			var col := Color(0.7, 0.35, 1.0)
			match clan:
				"nebula": x._warp_in(v, at, col, false)
				"militia": x._airdrop(v, at, Color(0.6, 1.0, 0.3), false)
				"wildcard": x._deal_in(v, at, false)
				"underworld": x._grave_rise(v, at, false)
			for i in 10:
				await _shot("fx_%s_s%02d" % [clan, i], 0.1)
			await get_tree().create_timer(0.8).timeout
			v.home = at
			var dv = x._new_view(CardDB.get_card(units[1]).duplicate(), "opponent", true)
			dv.position = x.slot_pos("opponent", 2)
			dv.home = dv.position
			var tpos: Vector2 = dv.home
			var dir: Vector2 = (tpos - at).normalized()
			match clan:
				"nebula": x._laser_strike(v, dv, tpos, dir, true, false)
				"militia": x._gun_strike(v, dv, tpos, dir, true, false)
				"wildcard": x._card_strike(v, dv, tpos, dir, true, false)
				"underworld": x._skull_strike(v, dv, tpos, dir, true, false)
			for i in 16:
				await _shot("fx_%s_a%02d" % [clan, i], 0.08)
			await get_tree().create_timer(1.2).timeout
			v.queue_free()
			dv.queue_free()
		get_tree().quit()
		return
	if "--underworld-only" in OS.get_cmdline_user_args():   # (Underworld's grave summon, skull attack and back; Wildcard's deal-in)
		var deck4 := await Game.load_duel_deck()
		Game.duel_setup = deck4
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "crypt"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var u = _screen()
		if u._menu:
			u._menu.visible = false
		var ids: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		var uc: Dictionary = CardDB.get_card(ids[0]).duplicate()
		uc.clanTag = "underworld"
		var back = u._new_view(uc, "player", false)
		back.set_back(CardDB.back("underworld"), CardDB.back_style("underworld"))
		back.position = Vector2(1650, 700)
		back.scale = Vector2.ONE * 1.6
		var g = u._new_view(uc, "player", true)
		g.position = u.slot_pos("player", 1)
		g.z_index = 420   # (as in a real summon)
		u._grave_rise(g, u.slot_pos("player", 1), true)
		for i in 12:
			await _shot("u%02d_grave" % i, 0.12)
		var wc: Dictionary = CardDB.get_card(ids[1]).duplicate()
		wc.clanTag = "wildcard"
		var w = u._new_view(wc, "player", true)
		u._deal_in(w, u.slot_pos("player", 3), false)
		for i in 4:
			await _shot("u%02d_deal" % i, 0.1)
		await get_tree().create_timer(1.0).timeout
		var dv = u._new_view(CardDB.get_card(ids[2]).duplicate(), "opponent", true)
		dv.position = u.slot_pos("opponent", 2)
		dv.home = dv.position
		g.home = u.slot_pos("player", 1)
		var tpos: Vector2 = dv.home
		u._skull_strike(g, dv, tpos, (tpos - g.home).normalized(), true, false)
		for i in 20:
			await _shot("u%02d_skull" % i, 0.08)
		await _shot("u_back", 0.5)
		get_tree().quit()
		return
	if "--ko-only" in OS.get_cmdline_user_args():   # (each clan's KO, one after another: shots every 0.1 s)
		var deck7 := await Game.load_duel_deck()
		Game.duel_setup = deck7
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var ko = _screen()
		if ko._menu:
			ko._menu.visible = false
		var kids: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		var styles := {"nebula": "_stardust", "militia": "_blast_ko", "wildcard": "_fold_ko", "underworld": "_rift_ko", "arsonists": "_ash_ko"}
		var slot := 1
		for clan in styles:
			var kc: Dictionary = CardDB.get_card(kids[slot]).duplicate()
			kc.clanTag = clan
			var kv = ko._new_view(kc, "opponent", true)
			kv.position = ko.slot_pos("opponent", slot)
			kv.z_index = 440
			if clan == "nebula":
				ko._stardust(kv, Color(0.7, 0.35, 1.0))
			else:
				ko.call(styles[clan], kv)
			for i in 9:
				await _shot("k_%s_%02d" % [clan, i], 0.1)
			await get_tree().create_timer(0.6).timeout
			slot += 1
		get_tree().quit()
		return
	for arg in OS.get_cmdline_user_args():   # (--replay=<file>: play a replay, shots as Morale changes)
		if not str(arg).begins_with("--replay="):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(str(arg).trim_prefix("--replay=")))
		Game.duel_setup = {"online": true, "start": data.start, "replay": data}
		Game.go("duel")
		await get_tree().create_timer(3.0).timeout
		var rp = _screen()
		rp._base_speed = 4.0
		Engine.time_scale = 4.0
		var seen := {}
		var shots := 0
		var t0 := Time.get_ticks_msec()
		while shots < 9 and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
			for side in rp._panels:
				var txt: String = rp._panels[side].morale.text
				if seen.get(side, txt) != txt and shots < 9:
					Engine.time_scale = 1.0
					for k in 3:
						await _shot("rp_%02d_%s" % [shots, side], 0.15)
						shots += 1
					Engine.time_scale = 4.0
				seen[side] = rp._panels[side].morale.text
		get_tree().quit()
		return
	if "--chat" in OS.get_cmdline_user_args():   # (the friends chat: tab, missed-messages pop-up, list, a chat, a message mid-duel)
		Game.go("main_menu")
		await get_tree().create_timer(4.0).timeout
		await _shot("ch_menu", 0.2)
		Net.chat.open_list()
		await _shot("ch_list", 1.2)
		var fr: Array = (await Api.request("GET", "/api/social/friends")).data
		Net.chat.open_with(str(fr[0].friend_id), str(fr[0].friend_username), fr[0].get("friend_avatar"))
		await _shot("ch_chat", 1.2)
		Net.chat.close()
		var deck8 := await Game.load_duel_deck()
		Game.duel_setup = deck8
		Game.duel_setup.first = "player"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		if _screen()._menu:
			_screen()._menu.visible = false
		Net.event.emit("chat:message", {"fromPlayerId": str(fr[1].friend_id), "fromUsername": str(fr[1].friend_username), "fromAvatar": null, "body": "Nice play! Want to team up for Turf Defense after?"})
		await _shot("ch_duel_toast", 0.8)
		get_tree().quit()
		return
	if "--emotes-back" in OS.get_cmdline_user_args():   # (the empty card panel's back, the emote menu and bubbles, the Molotov flame)
		var deck7 := await Game.load_duel_deck()
		Game.duel_setup = deck7
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "caldera"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var eb = _screen()
		if eb._menu:
			eb._menu.visible = false
		await _shot("eb_panel", 0.3)
		eb._toggle_emote_menu()
		await _shot("eb_menu", 0.4)
		eb._toggle_emote_menu()
		eb._show_emote("player", "wp")
		eb._show_emote("opponent", "gotcha")
		await _shot("eb_bubbles", 0.8)
		var rc7: Dictionary = CardDB.get_card(CardDB.all().keys()[0]).duplicate()
		var mb = eb._new_view(rc7, "player", false)
		mb.set_back(CardDB.back("arsonists"), CardDB.back_style("arsonists"))
		mb.position = Vector2(960, 540)
		mb.scale = Vector2.ONE * 3.2
		mb.z_index = 900
		for i in 6:
			await _shot("eb_flame%d" % i, 0.12)
		get_tree().quit()
		return
	if "--arsonists-only" in OS.get_cmdline_user_args():   # (Arsonists' firewall summon, Molotov attack (big), ash KO and back)
		var deck6 := await Game.load_duel_deck()
		Game.duel_setup = deck6
		Game.duel_setup.first = "player"
		Game.duel_setup.arena = "alley"
		Game.go("duel")
		await get_tree().create_timer(3.5).timeout
		var ars = _screen()
		if ars._menu:
			ars._menu.visible = false
		var rids: Array = CardDB.all().keys().filter(func(i): return CardDB.get_card(i).get("cardType") == "gang_member")
		var rc: Dictionary = CardDB.get_card(rids[0]).duplicate()
		rc.clanTag = "arsonists"
		var rback = ars._new_view(rc, "player", false)
		rback.set_back(CardDB.back("arsonists"), CardDB.back_style("arsonists"))
		rback.position = Vector2(1650, 700)
		rback.scale = Vector2.ONE * 1.6
		var at: Vector2 = ars.slot_pos("player", 1)
		var f = ars._new_view(rc, "player", true)
		f.position = at
		f.z_index = 420   # (as in a real summon)
		ars._firewall_in(f, at, true)
		for i in 14:
			await _shot("r%02d_firewall" % i, 0.1)
		await get_tree().create_timer(1.0).timeout
		f.home = at
		var rd = ars._new_view(CardDB.get_card(rids[2]).duplicate(), "opponent", true)
		rd.position = ars.slot_pos("opponent", 2)
		rd.home = rd.position
		var rt: Vector2 = rd.home
		ars._molotov_strike(f, rd, rt, (rt - f.home).normalized(), true, false)
		for i in 22:
			await _shot("r%02d_molotov" % i, 0.08)
		await get_tree().create_timer(1.2).timeout
		var kc: Dictionary = CardDB.get_card(rids[1]).duplicate()
		kc.clanTag = "arsonists"
		var kv = ars._new_view(kc, "opponent", true)
		kv.position = ars.slot_pos("opponent", 3)
		kv.z_index = 440
		ars._ash_ko(kv)
		for i in 14:
			await _shot("r%02d_ash" % i, 0.1)
		await _shot("r_back", 0.6)
		get_tree().quit()
		return
	if "--deck-only" in OS.get_cmdline_user_args():   # (the deck editor's Hideout list, a Striver's zoom, the active deck while matchmaking)
		Game.go("deck_builder")
		await get_tree().create_timer(2.0).timeout
		var db = _screen()
		db._deck.clear()
		db._hideout.clear()
		db._auto_fill()
		db._hideout = db._hideout.slice(0, 5)   # (some levels left out: "+ ... not in the Hideout")
		db._render_all()
		await get_tree().process_frame
		db._list.get_parent().scroll_vertical = 100000   # (down to the Hideout)
		await _shot("k1_deck", 1.0)
		for item in db._inventory:
			if str(item.get("card_type", "")) == "gang_member" and CardDB.striver_line(str(item.get("art_url", ""))).size() > 1 and int(item.get("level", 1)) == 1:
				UI.card_zoom(db, item)
				break
		await _shot("k2_zoom", 1.0)
		Game.go("matchmaking")
		await _shot("k3_matchmaking", 3.0)
		get_tree().quit()
		return
	if "--second-only" in OS.get_cmdline_user_args():   # (going second: your Authority on your first turn)
		var deck3 := await Game.load_duel_deck()
		Game.duel_setup = deck3
		Game.duel_setup.first = "opponent"
		Game.go("duel")
		for i in 12:
			await get_tree().create_timer(1.5).timeout
			var d3 = _screen()
			if d3 and d3.duel and not d3.duel.pending.is_empty() and d3.duel.pending.side == "player":
				d3._act("player", {"kind": "choose", "option": "keep"})
			await _shot("s%02d" % i, 0.1)
			if d3 and d3.duel:
				print("TURN ", d3.duel.turn, " active ", d3.duel.active, " auth ", d3.duel.sides.player.authority, "/", d3.duel.sides.player.authority_max, " hud ", d3._panels.player.auth.text)
		get_tree().quit()
		return
	if "--discard-only" in OS.get_cmdline_user_args():   # (the CPU discards 2 cards to an effect of yours: a shot every 0.4 s)
		var deck2 := await Game.load_duel_deck()
		Game.duel_setup = deck2
		Game.duel_setup.first = "player"
		Game.go("duel")
		await get_tree().create_timer(4.0).timeout
		var d2 = _screen()
		if d2._menu:
			d2._menu.visible = false
		while not d2.duel.pending.is_empty() and d2.duel.pending.side == "player":   # (keep the opening hand)
			d2._act("player", {"kind": "choose", "option": "keep"})
			await get_tree().create_timer(1.5).timeout
		await get_tree().create_timer(2.5).timeout
		await _shot("d00_before", 0.2)
		d2.duel._do_fx("player", -1, {"name": "Test", "uid": -77}, {"do": "discard", "amount": 2})
		d2.duel._flush_asks()
		d2._queue.append_array(d2.duel.take_events())
		d2._pump()
		for i in 14:
			await _shot("d%02d" % (i + 1), 0.4)
		get_tree().quit()
		return
	if "--arena-only" in OS.get_cmdline_user_args():   # (the arena roulette on Scissors Paper Rock: spinning, then landed)
		Game.duel_setup = {"mode": "cpu", "difficulty": "normal"}
		Game.go("rps")
		await _shot("a1_spinning", 1.2)
		await _shot("a2_landed", 3.6)
		get_tree().quit()
		return
	if "--evolve-only" in OS.get_cmdline_user_args():   # (a Striver evolving, a shot every 0.25 s)
		var deck := await Game.load_duel_deck()
		Game.duel_setup = deck
		Game.duel_setup.first = "player"
		Game.go("duel")
		await get_tree().create_timer(4.0).timeout
		var ds = _screen()
		if ds._menu:
			ds._menu.visible = false   # (the opening-hand prompt: out of the way of the shots)
		for id in CardDB.all():
			var lv1: Dictionary = CardDB.get_card(id)
			if CardDB.striver_stage(lv1).x == 1 and CardDB.next_form(id) != "":
				var lv2: Dictionary = CardDB.get_card(CardDB.next_form(id)).duplicate()
				lv2.position = "atk"
				ds._ev_promote({"side": "player", "slot": 4, "card": lv2, "from": lv1})
				break
		for i in 22:
			await _shot("e%02d" % i, 0.25)
		get_tree().quit()
		return
	if "--craft-only" in OS.get_cmdline_user_args():   # (the card zoom and craft reveal, a shot every 0.3 s)
		await _craft_shots()
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
	var htp: Control = load("res://scripts/ui/how_to_play.gd").open(_screen())
	await _shot("04_how_to_play", 0.8)
	htp._show("BRAWLS")
	await _shot("04_how_to_play_brawls", 0.8)
	htp._show("CHARACTERS")
	await _shot("04_how_to_play_chars", 0.8)
	htp.queue_free()
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
	_screen()._rank_up("underboss")
	await _shot("06_rank_up", 3.0)
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
	Game.duel_setup.rooftop = true   # (the rooftop arena first, then the back alley for the rest)
	Game.go("duel")
	await _shot("07_duel_rooftop", 4.0)
	Game.duel_setup = await Game.load_duel_deck()
	Game.duel_setup.first = "player"
	Game.duel_setup.rooftop = false
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
	duel_screen._ev_luck({"side": "player", "slot": -1, "kind": "coin", "value": 1, "need": 1, "won": true, "double": true})
	await _shot("07_luck_double", 0.75)
	await get_tree().create_timer(0.6).timeout
	duel_screen._ev_luck({"side": "player", "slot": -1, "kind": "die", "value": 5, "need": 4, "won": true, "again": true})
	await _shot("07_luck_loaded", 0.75)
	await get_tree().create_timer(0.6).timeout
	var legend = duel_screen._new_view(CardDB.get_card("card_mili_040"), "player", true)
	legend.position = Vector2(1080, 900)
	duel_screen._legendary_entrance(legend, legend.card)
	await _shot("07_legendary", 1.6)
	await get_tree().create_timer(1.5).timeout
	legend.queue_free()
	# A Striver evolving (LV1 into LV2, in an empty lane), shot at each stage of it
	for id in CardDB.all():
		var lv1: Dictionary = CardDB.get_card(id)
		if CardDB.striver_stage(lv1).x == 1 and CardDB.next_form(id) != "":
			var lv2: Dictionary = CardDB.get_card(CardDB.next_form(id)).duplicate()
			lv2.position = "atk"
			duel_screen._ev_promote({"side": "player", "slot": 4, "card": lv2, "from": lv1})
			break
	for at in [["charge", 0.8], ["cocoon", 1.0], ["burst", 1.25], ["reveal", 1.0]]:
		await _shot("07_evolve_" + at[0], at[1])
	await get_tree().create_timer(2.0).timeout
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
