extends Screen
## First login: pick a starting clan. The server seeds the starter inventory and deck.

const CLANS := [
	{"id": "lion_pride", "label": "LIONS", "color": Color("ffd166"), "image": "lions_deck.png",
		"blurb": "Aggressive pride that swarms the field.\nFull starter deck included."},
]

var _selected := ""
var _tiles := {}
var _confirm: Button


func _ready() -> void:
	UI.background(self)
	UI.title(self, "CHOOSE YOUR CLAN")
	var sub := UI.label("Your starter inventory and deck depend on this choice.", 24, UI.MUTED)
	sub.size = Vector2(1920, 30)
	sub.position = Vector2(0, 100)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	for i in CLANS.size():
		var c: Dictionary = CLANS[i]
		var tile := Button.new()
		tile.toggle_mode = true
		tile.custom_minimum_size = Vector2(600, 680)
		tile.position = Vector2(960 - CLANS.size() * 360 + 60 + i * 720, 170)   # centred, however many clans
		add_child(tile)
		var art := UI.texture_rect(UI.tex(c.image), Vector2(560, 448))
		art.position = Vector2(20, 20)
		tile.add_child(art)
		var name := UI.label(c.label, 48, c.color, true)
		name.size = Vector2(600, 60)
		name.position = Vector2(0, 490)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(name)
		var blurb := UI.label(c.blurb, 22, Color(0.85, 0.85, 0.9))
		blurb.size = Vector2(600, 80)
		blurb.position = Vector2(0, 570)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(blurb)
		tile.pressed.connect(_select.bind(c.id))
		_tiles[c.id] = tile
	_confirm = UI.button("CONFIRM", _do_confirm, Vector2(360, 70), UI.GREEN)
	_confirm.position = Vector2(780, 975)
	_confirm.disabled = true
	add_child(_confirm)


func _select(id: String) -> void:
	_selected = id
	for k in _tiles:
		_tiles[k].set_pressed_no_signal(k == id)
	_confirm.disabled = false


func _do_confirm() -> void:
	_confirm.disabled = true
	_confirm.text = "SAVING…"
	var r := await Api.request("POST", "/api/onboarding/start-clan", {"clan": _selected})
	if not r.ok:
		_confirm.disabled = false
		_confirm.text = "CONFIRM"
		UI.toast(self, r.error, UI.RED)
		return
	Game.player.chosen_clan = _selected
	Game.go("main_menu")
