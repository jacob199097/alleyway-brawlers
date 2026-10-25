extends Node
## Screenshots of the Turf Defense menus against tests/mock_server.mjs: Fight Mode's tiles, the boss
## screen (two bosses, a locked level), and the "looking for a partner" overlay.
## Run (not headless):  godot --path godot res://tests/turf_screen_shots.tscn -- <out dir> [server]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	Game.settings.server_url = args[1] if args.size() > 1 else "http://127.0.0.1:3999"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().process_frame
	var holder := Node.new()   # (screen changes free the current scene; keep this script alive)
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	var r := await Api.request("POST", "/api/auth/login", {"email": "shots@x.com", "password": "x"})
	Api.token = r.data.token
	Game.player = r.data.player
	Net.connect_to_server()
	Game.go("fight_mode")
	await _wait(2.5)
	_shot(out, "30_fight_mode")
	Game.go("turf_defense")
	await _wait(3.5)
	_shot(out, "31_turf_screen")
	var scene := get_tree().current_scene
	var bosses: Array = scene._data.get("bosses", [])
	if bosses.size() > 3:
		scene._select(bosses[3], 2)
		await _wait(1.5)
		_shot(out, "32_turf_locked")
		scene._select(bosses[1], 1)
		await _wait(1.0)
		scene._quick_match()
		await _wait(3.0)
		_shot(out, "33_turf_queue")
		Net.send("coop:leave")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)
