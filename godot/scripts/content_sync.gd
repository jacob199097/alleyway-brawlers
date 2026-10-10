extends RefCounted
## Keeps the game's cards (and clan card backs) up to date without a new build. At start-up (boot screen) it asks the
## server what the latest card data and card images are (backend/routes/content.js), compares
## their fingerprints with what's built in (data/content.json) and what was downloaded before
## (user://content), and downloads only what changed. It also reports whether this build of the
## game is out of date.
##
##   var sync := preload("res://scripts/content_sync.gd").new()
##   sync.progress.connect(func(done, total, id, tex): ...)
##   var r := await sync.run()   # {reachable, version: {latest, minimum, downloadUrl}, downloaded, failed}

signal progress(done: int, total: int, id: String, texture: Texture2D)
## Fired once the download list is known (0 = nothing to download).
signal started(total: int)

const DIR := CardDB.CONTENT_DIR
const STATE := DIR + "/state.json"


## The version of this build (project.godot, application/config/version).
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## -1, 0 or 1, comparing "1.2.10"-style versions part by part.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


func run(download := true) -> Dictionary:
	var out := {"reachable": false, "version": {}, "downloaded": 0, "failed": 0}
	var r: Dictionary = await Api.request("GET", "/api/content/manifest")
	if not r.ok or not (r.data is Dictionary):
		return out
	out.reachable = true
	var m: Dictionary = r.data
	out.version = m.get("client", {})
	if not download:
		return out
	DirAccess.make_dir_recursive_absolute(DIR + "/cards")
	var bundled := _read_json("res://data/content.json")
	var state := _read_json(STATE)
	if not state.has("art"):
		state.art = {}
	var bundled_art: Dictionary = bundled.get("art", {})

	# Card data: the built-in copy if it matches the server, otherwise a downloaded one
	var want_cards: String = str(m.get("cards", {}).get("hash", ""))
	var need_cards := false
	if want_cards == str(bundled.get("cards", "")):
		_remove(DIR + "/cards.json")
		state.erase("cards")
	elif want_cards != "" and (want_cards != str(state.get("cards", "")) or not FileAccess.file_exists(DIR + "/cards.json")):
		need_cards = true

	# Card images: download the ones that differ from both the built-in and the cached copy
	var todo: Array = []
	var art: Dictionary = m.get("art", {})
	for id in art:
		var h := str(art[id].get("hash", ""))
		var file := "%s/cards/%s.png" % [DIR, id]
		# Built in only counts if this build really has the file (a patch updates the list, not the art)
		if h == str(bundled_art.get(id, "")) and ResourceLoader.exists("res://assets/cards/%s.png" % id):
			_remove(file)
			state.art.erase(id)
		elif h != str(state.art.get(id, "")) or not FileAccess.file_exists(file):
			todo.append(id)

	# Images the server no longer lists (a card was removed) aren't needed any more
	for f in DirAccess.get_files_at(DIR + "/cards"):
		var id := f.get_basename()
		if f.ends_with(".png") and not art.has(id):
			_remove("%s/cards/%s" % [DIR, f])
			state.art.erase(id)

	# Card backs (a new clan's back): same rules, kept in user://content/backs
	DirAccess.make_dir_recursive_absolute(DIR + "/backs")
	if not state.has("backs"):
		state.backs = {}
	var backs: Dictionary = m.get("backs", {})
	var bundled_backs: Dictionary = bundled.get("backs", {})
	var back_todo: Array = []
	for id in backs:
		var h := str(backs[id].get("hash", ""))
		var file := "%s/backs/%s.png" % [DIR, id]
		if h == str(bundled_backs.get(id, "")) and ResourceLoader.exists("res://assets/%s.png" % id):
			_remove(file)
			state.backs.erase(id)
		elif h != str(state.backs.get(id, "")) or not FileAccess.file_exists(file):
			back_todo.append(id)

	var total := todo.size() + back_todo.size() + (1 if need_cards else 0)
	started.emit(total)
	var done := 0
	if need_cards:
		var c: Dictionary = await Api.fetch("/api/content/cards.json")
		if c.ok and _sha256(c.body) == want_cards:
			_write(DIR + "/cards.json", c.body)
			state.cards = want_cards
			CardDB.reload()   # names for the download screen
			out.downloaded += 1
		else:
			out.failed += 1
		done += 1
		progress.emit(done, total, "", null)
	for id in todo:
		var want := str(art[id].get("hash", ""))
		var a: Dictionary = await Api.fetch("/api/content/art/%s.png" % id)
		var tex: Texture2D = null
		if a.ok and _sha256(a.body) == want:
			_write("%s/cards/%s.png" % [DIR, id], a.body)
			state.art[id] = want
			out.downloaded += 1
			var img := Image.new()
			if img.load_png_from_buffer(a.body) == OK:
				tex = ImageTexture.create_from_image(img)
		else:
			out.failed += 1
		done += 1
		progress.emit(done, total, str(id), tex)
		_save_state(state)   # keep what's done if the game is closed part-way
	for id in back_todo:
		var want := str(backs[id].get("hash", ""))
		var b: Dictionary = await Api.fetch("/api/content/back/%s.png" % id)
		if b.ok and _sha256(b.body) == want:
			_write("%s/backs/%s.png" % [DIR, id], b.body)
			state.backs[id] = want
			out.downloaded += 1
		else:
			out.failed += 1
		done += 1
		progress.emit(done, total, str(id), null)
		_save_state(state)
	_save_state(state)
	if total > 0:
		CardDB.reload()
	return out


static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _save_state(state: Dictionary) -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		f.close()
