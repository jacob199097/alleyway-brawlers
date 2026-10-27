extends SceneTree
## Fills see-through holes inside card images with a dark backing, so the arena never shows through
## a card (a clan frame with transparent metalwork, like Underworld's, left holes in every card made
## with it: on a bright arena such as the Koi Garden the cards looked washed out). The card's own
## outline (its notched corners and edges, transparent on purpose) stays transparent: "outside" is
## whatever can be reached from the image's border without crossing the frame.
## The Card Forge paints the same backing now (drawPanelCard), so new exports don't need this.
##
##   godot --headless --path godot --script res://tools/fill_card_holes.gd -- <dir> <prefix> [--preview <out.png>]
##   e.g. -- ../assets/cards card_unde_       (every Underworld card image, in place)

const BACKING := Color("100d14")
const SCALE := 4        # the outline is found on a quarter-size mask...
const CLOSE := 2        # ...with gaps in the frame up to this many (small) pixels closed first


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <dir> <file prefix> [--preview <out.png>]")
		quit(2)
		return
	var dir: String = args[0] if args[0].is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(args[0])
	var preview := args[args.find("--preview") + 1] if "--preview" in args else ""
	var done := 0
	for f in DirAccess.get_files_at(dir):
		if not f.begins_with(args[1]) or not f.ends_with(".png"):
			continue
		var img := Image.load_from_file(dir.path_join(f))
		img.convert(Image.FORMAT_RGBA8)
		var filled := _fill(img)
		if preview != "":
			_preview(img, filled).save_png(preview)
			print("preview of %s: %s" % [f, preview])
			quit()
			return
		if filled > 0:
			img.save_png(dir.path_join(f))
			done += 1
		print("%s: %d pixels filled" % [f, filled])
	print("%d image(s) changed" % done)
	quit()


## Paints the backing under every pixel inside the card's outline; returns how many changed.
func _fill(img: Image) -> int:
	var inside := _inside(img)
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a >= 0.999 or not inside[(y / SCALE) * (w / SCALE + 1) + x / SCALE]:
				continue
			img.set_pixel(x, y, Color(BACKING.lerp(Color(c.r, c.g, c.b), c.a), 1.0))
			n += 1
	return n


## A quarter-size mask: true inside the card's outline (the frame, and everything it encloses).
func _inside(img: Image) -> PackedByteArray:
	var w := img.get_width() / SCALE + 1
	var h := img.get_height() / SCALE + 1
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				solid[(y / SCALE) * w + x / SCALE] = 1
	# Close small gaps in the frame, so the outside can't leak in through them
	var closed := solid.duplicate()
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				continue
			for dy in range(-CLOSE, CLOSE + 1):
				for dx in range(-CLOSE, CLOSE + 1):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						closed[yy * w + xx] = 1
	# The outside: reachable from the border without crossing the (closed) frame
	var outside := PackedByteArray()
	outside.resize(w * h)
	var todo: Array[int] = []
	for x in w:
		todo.append(x)
		todo.append((h - 1) * w + x)
	for y in h:
		todo.append(y * w)
		todo.append(y * w + w - 1)
	while not todo.is_empty():
		var i: int = todo.pop_back()
		if outside[i] == 1 or closed[i] == 1:
			continue
		outside[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: todo.append(i - 1)
		if x < w - 1: todo.append(i + 1)
		if y > 0: todo.append(i - w)
		if y < h - 1: todo.append(i + w)
	# Grow the outside back by what closing added, so the outline isn't pushed outwards
	var grown := outside.duplicate()
	for y in h:
		for x in w:
			if outside[y * w + x] == 0:
				continue
			for dy in range(-CLOSE, CLOSE + 1):
				for dx in range(-CLOSE, CLOSE + 1):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h and solid[yy * w + xx] == 0:
						grown[yy * w + xx] = 1
	var inside := PackedByteArray()
	inside.resize(w * h)
	for i in w * h:
		inside[i] = 0 if grown[i] == 1 else 1
	return inside


## The filled card over a pale pond colour (any hole left shows bright), to check before writing.
func _preview(filled: Image, _count: int) -> Image:
	var out := Image.create(filled.get_width(), filled.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color("bfe9e4"))
	out.blend_rect(filled, Rect2i(Vector2i.ZERO, filled.get_size()), Vector2i.ZERO)
	return out
