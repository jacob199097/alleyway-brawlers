extends Node
## A test player for online matches: logs in, joins the Casual queue, lets the CPU play its
## side through the server, and reports the result when the match ends.
## Run two at once against tests/mock_server.mjs:
##   godot --headless --path godot res://tests/online_bot.tscn -- <email> [server] [--autoplay]
## Flags after the email: "--autoplay" (required for the bot to play), "--drop" (disconnects once
## mid-match to test reconnecting), "--concede" (concedes after a few turns).

const TIMEOUT_SECS := 900.0

var _email := ""
var _elapsed := 0.0
var _dropped := false
var _conceded := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_email = args[0] if args.size() > 0 else "bot@example.com"
	Game.settings.server_url = args[1] if args.size() > 1 and not args[1].begins_with("--") else "http://127.0.0.1:3999"
	_run()


func _run() -> void:
	await get_tree().process_frame
	var holder := Node.new()   # screen changes free the current scene; keep this script alive
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	var r := await Api.request("POST", "/api/auth/login", {"email": _email, "password": "x"})
	if not r.ok:
		_finish(1, "login failed: " + r.error)
		return
	Api.token = r.data.token
	Game.player = r.data.player
	Net.connect_to_server()
	Game.go("matchmaking")


func _process(delta: float) -> void:
	_elapsed = Time.get_ticks_msec() / 1000.0   # real time (tests run with sped-up frames)
	if _elapsed > TIMEOUT_SECS:
		_finish(1, "timed out")
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var args := OS.get_cmdline_user_args()
	if scene.name == "Duel" and scene.get("duel") != null and scene.duel.turn >= 3:
		if "--drop" in args and not _dropped:
			_dropped = true
			print("[%s] dropping the connection" % _email)
			Net.disconnect_from_server()
			get_tree().create_timer(3.0).timeout.connect(func(): Net.connect_to_server())
		if "--concede" in args and not _conceded:
			_conceded = true
			print("[%s] conceding" % _email)
			Net.send("mp:concede", {"matchId": scene._match_id})
	if scene.name == "PostMatch":
		var d: Dictionary = Game.match_result
		var rw = d.get("rewards")
		_finish(0, "result %s (%s), turns %s, morale %s vs %s, rewards %s" % [d.get("result"), d.get("reason", ""),
			d.get("turns"), d.get("player_morale"), d.get("opponent_morale"),
			"+%s XP +%s Karat" % [rw.xpEarned, rw.karatEarned] if rw is Dictionary else "none"])


func _finish(code: int, msg: String) -> void:
	set_process(false)
	print("[%s] %s" % [_email, msg])
	get_tree().quit(code)
