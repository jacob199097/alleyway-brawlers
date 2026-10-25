extends Node
## Plays a Turf Defense match on this PC through the duel screen's online path (no server): the
## rules run here (duel_state.gd with the boss rules), the CPU plays every seat, and each move's
## events reach the duel as coop:update messages, so the boss's entrance, its board, its phases and
## the end can be looked at (or recorded). Screenshots go to <out> at set moments.
## Run (not headless):  godot --path godot res://tests/turf_preview.tscn -- <out dir> [boss id] [level]

const BOSSES := "res://data/bosses.json"

var _out := ""
var _st: DuelState
var _boss := {}
var _lv := {}
var _shots := {}     # name -> taken
var _t := 0.0        # seconds since the duel opened
var _hit_phase := false
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var boss_id: String = args[1] if args.size() > 1 else "archon"
	var level := int(args[2]) if args.size() > 2 else 2
	DirAccess.make_dir_recursive_absolute(_out)
	Game.offline = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BOSSES))
	for b in data.bosses:
		if b.id == boss_id:
			_boss = b
	for l in _boss.levels:
		if int(l.level) == level:
			_lv = l
	var setup := DuelAI.test_setup()
	var rules := {"order": ["player", "ally", "boss"], "teams": {"player": "crew", "ally": "crew", "boss": "boss"},
		"morale": {"boss": int(_lv.morale)},
		"boss": {"seat": "boss", "name": _boss.name, "draw": int(_lv.get("draw", 0)), "authority": int(_lv.get("authority", 0)), "phases": _lv.get("phases", [])}}
	_st = DuelState.new({"player": setup.decks.player, "ally": setup.decks.player.duplicate(), "boss": setup.decks.opponent},
		{"player": setup.hideouts.player, "ally": setup.hideouts.player.duplicate(), "boss": setup.hideouts.opponent},
		{"player": setup.leaders.player, "ally": setup.leaders.player, "boss": str(_boss.leader)}, "player", 4242, rules)
	var info := {"id": _boss.id, "clan": _boss.clan, "name": _boss.name, "short": _boss.get("short", _boss.name), "title": _boss.title,
		"color": _boss.color, "arena": _boss.arena, "portrait": _boss.portrait, "prize": _boss.prize, "lines": _boss.lines,
		"level": int(_lv.level), "level_name": _lv.name, "morale": int(_lv.morale), "draw": int(_lv.get("draw", 0)),
		"authority": int(_lv.get("authority", 0)), "phases": (_lv.get("phases", []) as Array).map(func(p): return {"below": p.below, "label": p.label})}
	var players := {"player": {"username": "Jacob", "level": 12, "avatar_url": ""}, "ally": {"username": "Friend", "level": 9, "avatar_url": ""},
		"boss": {"username": _boss.name, "cpu": true, "boss": true}}
	Game.duel_setup = {"online": true, "start": {"matchId": "preview", "mode": "coop", "resync": false, "boss": info, "players": players,
		"view": _view(), "arena": _boss.arena, "clock": 90}}
	_st.start()
	await get_tree().process_frame
	var holder := Node.new()   # (screen changes free the current scene; keep this script alive)
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	Net.inbox.append(["coop:update", {"matchId": "preview", "events": _st.take_events(), "view": _view(), "clock": 90}])
	Game.go("duel")


func _view() -> Dictionary:
	return {"turn": _st.turn, "active": _st.active, "phase": _st.phase, "winner": _st.winner, "pending": {},
		"sides": _st.sides.duplicate(true), "seats": _st.seats.duplicate(), "teams": _st.teams.duplicate()}


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Duel" or _done:
		if scene != null and scene.name == "PostMatch":
			_shot("90_post_match", 3.5)
		return
	_t += delta
	_shot("01_intro_name", 2.2)
	_shot("02_intro_line", 4.6)
	_shot("03_intro_crew", 10.0)
	if _t < 15.0 or scene.get("_playing") or not (scene.get("_queue") as Array).is_empty():
		_maybe_phase_shots()
		return
	_shot("10_board", 15.5)
	# Knock the boss into its first phase once the board has had a few turns
	if not _hit_phase and _st.turn >= 4 and _st.winner == "":
		_hit_phase = true
		_shots["_phase_at"] = _t
		_st._damage("boss", int(_lv.morale) - int(_lv.phases[0].below) + 100)
		_push()
		return
	if _st.winner != "":
		return
	var who: String = _st.pending.side if not _st.pending.is_empty() else _st.active
	var a := DuelAI.choose(_st, who, "normal")
	if a.is_empty() or not _st.do_action(who, a):
		_st.do_action(who, {"kind": "next"})
	_push()
	if _t > 240.0:   # long enough: end it
		_st._damage("boss", 99999)
		_push()


func _maybe_phase_shots() -> void:
	if _shots.has("_phase_at"):
		var since: float = _t - float(_shots._phase_at)
		_shot("20_phase_card", float(_shots._phase_at) + 0.9)
		_shot("21_phase_line", float(_shots._phase_at) + 2.6)
		if since > 6.0:
			_shot("22_after_phase", float(_shots._phase_at) + 6.0)


func _push() -> void:
	var evs := _st.take_events()
	if evs.is_empty():
		return
	var msg := {"matchId": "preview", "events": evs, "view": _view(), "clock": 90}
	Net.inbox.append(["coop:update", msg])
	if _st.winner != "":
		var won := _st.winner != "boss"
		Net.inbox.append(["coop:over", {"matchId": "preview", "won": won, "boss": Game.duel_setup.start.boss,
			"players": Game.duel_setup.start.players, "turns": _st.turn,
			"rewards": {"won": won, "first": won, "bossId": _boss.id, "level": int(_lv.level), "karatEarned": 600, "xpEarned": 700,
				"packs": 1, "prize": _boss.prize if won else null, "unlockedNext": won, "newLevel": 12, "newXp": 9000}}])


func _shot(name: String, at: float) -> void:
	if _shots.has(name) or _t < at and name != "90_post_match":
		return
	if name == "90_post_match":
		if not _shots.has("_post_t"):
			_shots._post_t = Time.get_ticks_msec() / 1000.0
			return
		if Time.get_ticks_msec() / 1000.0 - float(_shots._post_t) < at:
			return
	_shots[name] = true
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("shot ", name)
	if name == "90_post_match":
		get_tree().quit()
