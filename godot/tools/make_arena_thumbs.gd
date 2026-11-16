extends SceneTree
## Small copies of the arena pictures (assets/arena_1v1*.jpg and arena_ffa.jpg, 3840 wide) for where an arena is shown small: the
## arena roulette, the turf map's tiles and district panel (ArenaRoulette.thumb). A 4K picture is ~40 MB
## once loaded; these are 640 wide. Makes assets/arena_thumbs/<the picture's name>, only where it's missing
## or older than its picture.
## Run:  godot --headless --path godot --script res://tools/make_arena_thumbs.gd   then tools/sync_assets.

const WIDTH := 640


func _init() -> void:
	var assets := ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()
	var out := assets.path_join("arena_thumbs")
	DirAccess.make_dir_recursive_absolute(out)
	var made := 0
	for f in DirAccess.get_files_at(assets):
		if not ((f.begins_with("arena_1v1") or f == "arena_ffa.jpg") and f.ends_with(".jpg")):
			continue
		var src := assets.path_join(f)
		var dst := out.path_join(f)
		if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src):
			continue
		var img := Image.load_from_file(src)
		if img == null or img.is_empty():
			push_error("Can't read " + src)
			continue
		img.resize(WIDTH, roundi(WIDTH * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		img.save_jpg(dst, 0.9)
		made += 1
	print("Arena thumbnails: %d made in %s" % [made, out])
	quit()
