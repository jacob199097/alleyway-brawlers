extends Node
## Runs the boot screen against a test server (tests/mock_server.mjs) to check the version check
## and card downloads. It points the game at the test server for this run only, and removes the
## downloaded cards afterwards unless --keep is given.
##   godot --path godot res://tests/boot_sync.tscn -- [server] [--keep]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Game.settings.server_url = args[0] if args.size() > 0 and not args[0].begins_with("--") else "http://127.0.0.1:3999"
	Api.token = ""
	var keep := "--keep" in args
	await get_tree().process_frame
	# A stand-in current scene, so changing scenes frees it instead of this script
	var holder := Node.new()
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	get_tree().change_scene_to_file("res://scenes/boot.tscn")
	await get_tree().create_timer(1.0).timeout
	var waited := 0.0
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path.ends_with("boot.tscn"):
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > 60.0:
			break
	var state = JSON.parse_string(FileAccess.get_file_as_string(CardDB.CONTENT_DIR + "/state.json"))
	if not (state is Dictionary):
		state = {}
	var arts: Array = state.get("art", {}).keys()
	var backs: Array = state.get("backs", {}).keys()
	var sounds: Array = state.get("sfx", {}).keys()
	print("Boot sync: now on %s; cards known %d; downloaded %d card arts, %d card backs, %d sounds" % [
		get_tree().current_scene.scene_file_path if get_tree().current_scene else "?",
		CardDB.all().size(), arts.size(), backs.size(), sounds.size()])
	# (what downloads depends on how the server's assets differ from this build's: none is fine)
	if not arts.is_empty():
		var id: String = arts[0]
		print("  downloaded art %s loads: %s" % [id, FileAccess.file_exists(CardDB.CONTENT_DIR + "/cards/%s.png" % id) and CardDB.art(id) != null])
	for f in backs:
		var clan: String = str(f).get_basename().trim_prefix("card_back_")
		print("  downloaded card back %s loads: %s" % [clan, CardDB.back(clan) != CardDB.back()])
	if not sounds.is_empty():
		var name: String = str(sounds[0]).get_basename().split("_")[0] if not str(sounds[0]).begins_with("music_") else str(sounds[0]).get_basename()
		print("  downloaded sound %s loads: %s" % [name, not Sfx.streams(name).is_empty()])
	print("  built-in sounds downloaded again: %s" % FileAccess.file_exists(CardDB.CONTENT_DIR + "/sfx/hit_1.ogg"))
	if not keep:
		for f in DirAccess.get_files_at(CardDB.CONTENT_DIR + "/cards"):
			DirAccess.remove_absolute(CardDB.CONTENT_DIR + "/cards/" + f)
		for dir in ["backs", "sfx"]:
			for f in DirAccess.get_files_at(CardDB.CONTENT_DIR + "/" + dir):
				DirAccess.remove_absolute(CardDB.CONTENT_DIR + "/" + dir + "/" + f)
		for f in ["cards.json", "state.json"]:
			DirAccess.remove_absolute(CardDB.CONTENT_DIR + "/" + f)
	get_tree().quit()
