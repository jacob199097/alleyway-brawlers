extends SceneTree
## What the game needs worked out from the arena pictures (assets/arena_1v1*.jpg, arena_ffa.jpg and the turf
## map's turf_city.jpg; 3840 wide or more), so it never reads a 4K picture back from the graphics card:
##   assets/arena_thumbs/<picture>   a small copy, 640 wide, for where it's shown small: the arena roulette,
##                                   the turf map's tiles, panel and blurred surround (ArenaRoulette.thumb).
##                                   Made where missing or older than its picture.
##   godot/data/neon_zones.json      the 160 px patches of each picture (in its picture pixels, 1536 wide:
##                                   UI.tex_size) with lit neon tubes in them, for the stutter (duel.gd _find_neon)
## Run:  godot --headless --path godot --script res://tools/make_arena_thumbs.gd   then tools/sync_assets.

const WIDTH := 640
const ZONE := 160


func _init() -> void:
	var assets := ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()
	var out := assets.path_join("arena_thumbs")
	DirAccess.make_dir_recursive_absolute(out)
	var made := 0
	var neon := {}
	for f in DirAccess.get_files_at(assets):
		var arena := (f.begins_with("arena_1v1") or f == "arena_ffa.jpg") and f.ends_with(".jpg")
		if not arena and f != "turf_city.jpg":
			continue
		var src := assets.path_join(f)
		var dst := out.path_join(f)
		var fresh := FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src)
		if fresh and not arena:
			continue
		var img := Image.load_from_file(src)
		if img == null or img.is_empty():
			push_error("Can't read " + src)
			continue
		if arena:
			neon[f] = _neon(img)
		if not fresh:
			var small := img.duplicate() as Image
			small.resize(WIDTH, roundi(WIDTH * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_LANCZOS)
			small.save_jpg(dst, 0.9)
			made += 1
	var data := ProjectSettings.globalize_path("res://data/neon_zones.json")
	var keys := neon.keys()
	keys.sort()
	var lines: Array = []
	for k in keys:
		lines.append("    %s: %s" % [JSON.stringify(k), JSON.stringify(neon[k])])
	var fa := FileAccess.open(data, FileAccess.WRITE)
	fa.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	fa.close()
	print("Arena thumbnails: %d made in %s; neon zones for %d pictures in %s" % [made, out, neon.size(), data])
	quit()


## The neon patches: [[x, y], ...] in ZONE steps of the picture at 1536 wide (the same test duel.gd used to
## run on the picture at the start of every match).
func _neon(src: Image) -> Array:
	var img := src.duplicate() as Image
	img.resize(1536, roundi(1536.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var out: Array = []
	for zy in range(0, img.get_height(), ZONE):
		for zx in range(0, img.get_width(), ZONE):
			var lit := 0
			var n := 0
			for y in range(zy, mini(zy + ZONE, img.get_height()), 8):
				for x in range(zx, mini(zx + ZONE, img.get_width()), 8):
					var c := img.get_pixel(x, y)
					n += 1
					if c.v > 0.55 and c.s > 0.45:
						lit += 1
			if n > 0 and float(lit) / n >= 0.05:
				out.append([zx / ZONE, zy / ZONE])
	return out
