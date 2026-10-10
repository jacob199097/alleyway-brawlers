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
	var state := FileAccess.get_file_as_string(CardDB.CONTENT_DIR + "/state.json")
	print("Boot sync: now on %s; state %s; cards known %d; astra_lv1 %s" % [
		get_tree().current_scene.scene_file_path if get_tree().current_scene else "?", state,
		CardDB.all().size(), "yes" if not CardDB.get_card("astra_lv1").is_empty() else "no"])
	print("  art for astra_lv1 loads: %s" % (CardDB.art("astra_lv1") != null))
	if not keep:
		for f in DirAccess.get_files_at(CardDB.CONTENT_DIR + "/cards"):
			DirAccess.remove_absolute(CardDB.CONTENT_DIR + "/cards/" + f)
		for f in ["cards.json", "state.json"]:
			DirAccess.remove_absolute(CardDB.CONTENT_DIR + "/" + f)
	get_tree().quit()
