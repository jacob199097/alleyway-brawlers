extends Screen
## First login: pick a starting clan. The server seeds the starter inventory and deck.
## The clans come from the server (GET /api/onboarding/clans: every clan with a starter deck), so
## a new Card Forge clan appears here by itself. Art: assets/<clan>_deck.png, else its leader.

## Art and words for clans that have them; others use their leader's art and a plain line.
const KNOWN := {
}

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
	var r := await Api.request("GET", "/api/onboarding/clans")
	var clans: Array = r.data if r.ok and r.data is Array else []
	if clans.is_empty():
		var msg := UI.label(r.error if not r.ok else "No clans are ready yet. Try again later.", 26, UI.RED, true)
		msg.size = Vector2(1920, 40)
		msg.position = Vector2(0, 480)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(msg)
	# Centred rows (two once there are more than 4 clans); tiles get narrower the more there are
	var per_row := clans.size() if clans.size() <= 4 else ceili(clans.size() / 2.0)
	var two := clans.size() > 4
	var w := minf(600.0, 1820.0 / maxi(1, per_row) - 40.0)
	var gap := w + 40.0
	var h := 380.0 if two else 680.0
	var art_h := 236.0 if two else 448.0
	for i in clans.size():
		var c := _clan_info(clans[i])
		var row := i / per_row
		var in_row := mini(per_row, clans.size() - row * per_row)   # (a shorter last row is centred too)
		var tile := Button.new()
		tile.toggle_mode = true
		tile.custom_minimum_size = Vector2(w, h)
		tile.position = Vector2(960 - in_row * gap / 2 + 20 + (i % per_row) * gap, 170 + row * (h + 20))
		add_child(tile)
		var art := UI.texture_rect(c.image, Vector2(w - 40, art_h))
		art.position = Vector2(20, 20)
		tile.add_child(art)
		var name := UI.label(c.label, int(minf(48.0, w / 6.0)), c.color, true)
		name.size = Vector2(w, 60)
		name.position = Vector2(0, art_h + 36)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(name)
		var blurb := UI.label(c.blurb, 17 if two else 22, Color(0.85, 0.85, 0.9))
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
		blurb.size = Vector2(w - 40, 120)
		blurb.position = Vector2(20, art_h + (92 if two else 112))
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(blurb)
		# In its clan's colour: edged on hover, glowing once chosen
		var col: Color = c.color
		tile.add_theme_stylebox_override("normal", UI.box(Color(0.04, 0.04, 0.1, 0.82), Color(col, 0.35), 2, 14))
		tile.add_theme_stylebox_override("hover", UI._glow(UI.box(Color(col.darkened(0.8), 0.88), col, 3, 14), col, 0.9))
		tile.add_theme_stylebox_override("pressed", UI._glow(UI.box(Color(col.darkened(0.7), 0.92), col, 4, 14), col, 1.6))
		tile.add_theme_stylebox_override("hover_pressed", tile.get_theme_stylebox("pressed"))
		UI.juice(tile)
		tile.pressed.connect(_select.bind(c.id))
		_tiles[c.id] = tile
	_confirm = UI.button("CONFIRM", _do_confirm, Vector2(360, 70), UI.GREEN)
	_confirm.position = Vector2(780, 975)
	_confirm.disabled = true
	add_child(_confirm)


## Label, colour, art and blurb for one clan from the server's list.
func _clan_info(c: Dictionary) -> Dictionary:
	var id := str(c.get("id", ""))
	var known: Dictionary = KNOWN.get(id, {})
	var image: Texture2D = UI.tex("%s_deck.png" % id)
	if image == null and known.has("image"):
		image = UI.tex(known.image)
	if image == null and str(c.get("leader", "")) != "":
		image = CardDB.art(str(c.leader))
	if image == null:
		image = CardDB.back(str(c.get("tag", "")))
	return {"id": id, "label": str(c.get("name", id)).to_upper(), "color": CardDB.clan_color(str(c.get("color", "#b388ff"))),
		"image": image, "blurb": "%s%d cards · 40-card starter deck included" % [
			str(c.blurb) + "\n\n" if str(c.get("blurb", "")) != "" else str(known.blurb) + "\n" if known.has("blurb") else "", int(c.get("cards", 0))]}


func _select(id: String) -> void:
	_selected = id
	Sfx.play("promote", 1.2, -6.0)
	for k in _tiles:
		var t: Button = _tiles[k]
		t.set_pressed_no_signal(k == id)
		# The others step back; the chosen one pops
		t.create_tween().tween_property(t, "modulate", Color.WHITE if k == id else Color(0.55, 0.55, 0.62), 0.25)
		if k == id:
			var pop := t.create_tween()
			pop.tween_property(t, "scale", Vector2.ONE * 1.06, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pop.tween_property(t, "scale", Vector2.ONE * 1.03, 0.2)
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
