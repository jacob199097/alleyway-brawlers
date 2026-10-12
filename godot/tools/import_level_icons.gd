extends SceneTree
## Brings level emblems made in ChatGPT into the game: assets/levels/chatgpt/level_NN.png →
## assets/levels/level_NN.png (256×256). If the picture came with a solid or checkerboard background
## instead of a transparent one, that is cut away from the edges inwards; then the emblem is trimmed,
## squared and resized. Prompts: docs/LEVEL_ICON_PROMPTS.md.
## Run:  godot --headless --path godot --script res://tools/import_level_icons.gd   then tools/sync_assets.

const SIZE := 256
const WORK := 512   # background removal runs at this size
const TOLERANCE := 0.14   # how close (0-1 per channel, averaged) a pixel must be to a background colour


func _init() -> void:
	var levels := ProjectSettings.globalize_path("res://").path_join("../assets/levels")
	var src := levels.path_join("chatgpt")
	var n := 0
	for f in DirAccess.get_files_at(src):
		var m := RegEx.create_from_string("^level_(\\d\\d)\\.png$").search(f.to_lower())
		if m == null:
			continue
		var img := Image.load_from_file(src.path_join(f))
		if img == null or img.is_empty():
			push_error("Can't read %s" % f)
			continue
		img.convert(Image.FORMAT_RGBA8)
		img.resize(WORK, WORK * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
		var cut := _cut_background(img)
		var used := img.get_used_rect()
		if used.size.x < 8 or used.size.y < 8:
			push_error("%s: nothing left after removing the background" % f)
			continue
		var side := maxi(used.size.x, used.size.y)
		var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
		out.blit_rect(img, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
		out.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		out.save_png(levels.path_join("level_%s.png" % m.get_string(1)))
		print("level_%s.png%s" % [m.get_string(1), "  (background removed)" if cut else ""])
		n += 1
	print("%d level icon(s) imported from %s" % [n, src.simplify_path()])
	quit()


## Clears the background if the picture's edges are opaque: flood-fills inwards from the border
## through pixels close to one of the border's colours (one for a plain backdrop, two for a fake
## transparency checkerboard). Returns whether anything was cleared.
func _cut_background(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var border: Array[Vector2i] = []
	for x in w:
		border.append(Vector2i(x, 0))
		border.append(Vector2i(x, h - 1))
	for y in range(1, h - 1):
		border.append(Vector2i(0, y))
		border.append(Vector2i(w - 1, y))
	var opaque := 0
	for p in border:
		if img.get_pixelv(p).a > 0.9:
			opaque += 1
	if opaque < border.size() * 0.5:
		return false   # already transparent
	# The background's colours: the common colours along the border
	var bg: Array[Color] = []
	for p in border:
		var c := img.get_pixelv(p)
		if bg.size() < 4 and not bg.any(func(b): return _near(b, c)):
			bg.append(c)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = []
	for p in border:
		if _is_bg(img.get_pixelv(p), bg):
			stack.append(p)
			seen[p.y * w + p.x] = 1
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		img.set_pixelv(p, Color(0, 0, 0, 0))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen[q.y * w + q.x]:
				continue
			seen[q.y * w + q.x] = 1
			if _is_bg(img.get_pixelv(q), bg):
				stack.append(q)
	return true


func _is_bg(c: Color, bg: Array[Color]) -> bool:
	for b in bg:
		if _near(b, c):
			return true
	return false


func _near(a: Color, b: Color) -> bool:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0 < TOLERANCE
