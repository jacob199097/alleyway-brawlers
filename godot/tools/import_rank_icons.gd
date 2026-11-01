extends SceneTree
## Brings the ranked-tier emblems made in ChatGPT into the game: assets/ranks/chatgpt/sheet.png, a
## 3 × 2 sheet on a flat dark background in RANK order (rookie, street_tough, enforcer / underboss,
## kingpin, legend) → assets/ranks/<tier>.png (512×512, transparent). The background is cut away from
## the edges inwards; each shape left goes to the emblem whose grid cell holds its centre (so a crown
## or wing poking into the next cell stays with its own emblem), then each emblem is trimmed, squared
## and resized. make_badges.gd leaves these alone once they exist.
## The veteran card badges the same way: assets/veteran/chatgpt/sheet.png, 3 side by side (bronze,
## silver, gold) → assets/veteran/tier_1.png … tier_3.png (256×256; UI.draw_veteran).
## Each sheet is done only if it's there.
## Run:  godot --headless --path godot --script res://tools/import_rank_icons.gd   then tools/sync_assets.

const RANKS := ["rookie", "street_tough", "enforcer", "underboss", "kingpin", "legend"]
const VETERAN := ["tier_1", "tier_2", "tier_3"]
const TOLERANCE := 0.03   # tight: the emblems' black ink outlines are only a little darker than the backdrop


func _init() -> void:
	var assets := ProjectSettings.globalize_path("res://").path_join("../assets")
	var done := 0
	if FileAccess.file_exists(assets.path_join("ranks/chatgpt/sheet.png")):
		_import(assets.path_join("ranks"), 3, 2, RANKS, 512)
		done += 1
	if FileAccess.file_exists(assets.path_join("veteran/chatgpt/sheet.png")):
		_import(assets.path_join("veteran"), 3, 1, VETERAN, 256)
		done += 1
	if done == 0:
		push_error("No assets/ranks/chatgpt/sheet.png or assets/veteran/chatgpt/sheet.png")
	quit(0 if done > 0 else 1)


## Cuts dir/chatgpt/sheet.png (cols × rows emblems, in names' order) into dir/<name>.png, size² each.
func _import(dir: String, cols: int, rows: int, names: Array, size: int) -> void:
	var sheet := Image.load_from_file(dir.path_join("chatgpt/sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var w := sheet.get_width()
	var h := sheet.get_height()
	var bg := sheet.get_pixel(2, 2)
	var alpha := _cut_background(sheet, bg)
	# Label the shapes left (8-connected) and give each to the cell holding its centre
	var label := PackedInt32Array()
	label.resize(w * h)
	var owner_of: Array[int] = []
	var cw := w / cols
	var ch := h / rows
	for start in w * h:
		if label[start] != 0 or alpha[start] == 0:
			continue
		var id := owner_of.size() + 1
		var stack := PackedInt32Array([start])
		label[start] = id
		var sx := 0
		var sy := 0
		var n := 0
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % w
			var y := i / w
			sx += x
			sy += y
			n += 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var qx := x + dx
					var qy := y + dy
					if qx < 0 or qy < 0 or qx >= w or qy >= h:
						continue
					var j := qy * w + qx
					if label[j] == 0 and alpha[j] != 0:
						label[j] = id
						stack.append(j)
		owner_of.append(clampi(sx / n / cw, 0, cols - 1) + clampi(sy / n / ch, 0, rows - 1) * cols)
	for e in names.size():
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for i in w * h:
			if label[i] != 0 and owner_of[label[i] - 1] == e:
				img.set_pixel(i % w, i / w, sheet.get_pixel(i % w, i / w))
		var used := img.get_used_rect()
		var side := maxi(used.size.x, used.size.y) + 8
		var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
		out.blit_rect(img, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
		out.resize(size, size, Image.INTERPOLATE_LANCZOS)
		out.save_png(dir.path_join("%s.png" % names[e]))
		print("%s.png  (%dx%d emblem)" % [names[e], used.size.x, used.size.y])


## Flood-fills inwards from the border through pixels close to the backdrop colour, making them
## transparent; the pixels just inside get a soft edge. Returns each pixel's alpha (0 = cleared).
func _cut_background(img: Image, bg: Color) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var alpha := PackedByteArray()
	alpha.resize(w * h)
	alpha.fill(1)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	var cleared := PackedInt32Array()
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if seen[i]:
			continue
		seen[i] = 1
		var x := i % w
		var y := i / w
		if not _near(img.get_pixel(x, y), bg):
			continue
		cleared.append(i)
		alpha[i] = 0
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	for i in cleared:
		img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	# soften the edge: a pixel next to the cleared area that is still close-ish to the backdrop fades
	for i in cleared:
		for j in [i - 1, i + 1, i - w, i + w]:
			if j < 0 or j >= w * h or alpha[j] == 0:
				continue
			var c := img.get_pixel(j % w, j / w)
			if c.a > 0.99:
				var diff := (absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)) / 3.0
				c.a = clampf(diff / (TOLERANCE * 3.0), 0.35, 1.0)
				img.set_pixel(j % w, j / w, c)
	return alpha


func _near(a: Color, b: Color) -> bool:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0 < TOLERANCE
