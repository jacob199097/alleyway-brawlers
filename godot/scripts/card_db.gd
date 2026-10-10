class_name CardDB
extends RefCounted
## Card rules data (data/cards.json, exported from shared/cards.js) and card art lookup.
## Newer cards downloaded from the server (scripts/content_sync.gd) live in user://content and
## take priority over the ones built into the game.

const CONTENT_DIR := "user://content"

static var _cards: Dictionary = {}
static var _art: Dictionary = {}


static func all() -> Dictionary:
	if _cards.is_empty():
		var path := CONTENT_DIR + "/cards.json"
		if not FileAccess.file_exists(path):
			path = "res://data/cards.json"
		var text := FileAccess.get_file_as_string(path)
		_cards = JSON.parse_string(text)
	return _cards


## Every clan with collectable cards: [{id, name, color, tag}], by name. Worked out from the cards
## (each names its clan: clanName/clanColor, shared/cards.js), so new clans need no code.
static func clans() -> Array:
	var seen := {}
	for id in all():
		var c: Dictionary = all()[id]
		var clan := str(c.get("clan", ""))
		if clan == "" or seen.has(clan) or c.get("cardType") == "leader":
			continue
		seen[clan] = {"id": clan, "name": str(c.get("clanName", clan.capitalize())),
			"color": Color(str(c.get("clanColor", "#b388ff"))), "tag": str(c.get("clanTag", ""))}
	var out: Array = seen.values()
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


## One clan's entry from clans(), or {} if it has no cards.
static func clan(id: String) -> Dictionary:
	for c in clans():
		if c.id == id:
			return c
	return {}


## Forget loaded cards and art (after new content is downloaded).
static func reload() -> void:
	_cards = {}
	_art = {}


static func get_card(id: String) -> Dictionary:
	return all().get(id, {})


## The form a card promotes into: promotesTo, or the next `_lvN` card (Hunter).
static func next_form(id: String) -> String:
	var card := get_card(id)
	if card.get("promotesTo") is String:
		return card.promotesTo
	var re := RegEx.create_from_string("^(.*_lv)(\\d)$")
	var m := re.search(id)
	if m:
		var guess := "%s%d" % [m.get_string(1), int(m.get_string(2)) + 1]
		if all().has(guess):
			return guess
	return ""


## Card art texture, or null when the art isn't synced (see tools/sync_assets).
static func art(id: String) -> Texture2D:
	if _art.has(id):
		return _art[id]
	var tex: Texture2D = null
	var downloaded := CONTENT_DIR + "/cards/%s.png" % id
	if FileAccess.file_exists(downloaded):
		var img := Image.load_from_file(downloaded)
		if img and not img.is_empty():
			img.generate_mipmaps()   # stays sharp when drawn small
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		var path := "res://assets/cards/%s.png" % id
		tex = load(path) if ResourceLoader.exists(path) else null
	_art[id] = tex
	return tex


## The card back: a clan's own (assets/card_back_<clan tag>.png, e.g. card_back_nebula.png) when
## there is one, otherwise the standard back.
## Clan backs whose galaxy turns (shaders/card.gdshader, galaxy).
const SPINNING_BACKS := ["nebula"]


static func back_spins(clan: String) -> bool:
	return clan in SPINNING_BACKS and ResourceLoader.exists("res://assets/card_back_%s.png" % clan)


static func back(clan := "") -> Texture2D:
	var own := "res://assets/card_back_%s.png" % clan
	if clan != "" and ResourceLoader.exists(own):
		return load(own)
	return load("res://assets/card_back.png") if ResourceLoader.exists("res://assets/card_back.png") else null
