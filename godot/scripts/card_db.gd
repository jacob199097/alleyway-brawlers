class_name CardDB
extends RefCounted
## Card rules data (data/cards.json, exported from shared/cards.js) and card art lookup.

static var _cards: Dictionary = {}
static var _art: Dictionary = {}


static func all() -> Dictionary:
	if _cards.is_empty():
		var text := FileAccess.get_file_as_string("res://data/cards.json")
		_cards = JSON.parse_string(text)
	return _cards


static func get_card(id: String) -> Dictionary:
	return all().get(id, {})


## The form a card promotes into: promotesTo, or the next `_lvN` card (Hunter, Viper).
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
	var path := "res://assets/cards/%s.png" % id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_art[id] = tex
	return tex


static func back() -> Texture2D:
	return load("res://assets/card_back.png") if ResourceLoader.exists("res://assets/card_back.png") else null
