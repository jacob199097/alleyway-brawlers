extends Screen
## Pick a battle mode. Duels use the player's saved active deck (checked for 40 cards first).

const RANK_COLORS := {
	"rookie": Color("8a9ba8"), "runner": Color("6dbf67"), "enforcer": Color("4cc9f0"), "brawler": Color("e07b39"),
	"striver": Color("9b59b6"), "shot_caller": Color("f4d35e"), "lieutenant": Color("f0a500"),
	"kingpin": Color("e63946"), "sovereign": Color("00d4ff"), "undisputed": Color("ffffff"),
}

var _starting := false
var _spin: Label = null


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "duel_background.png", 0.62)
	UI.title(self, "SELECT BATTLE MODE")
	var level := int(Game.player.get("level", 1))
	var modes := [
		{"id": "casual", "title": "CASUAL BRAWL", "color": UI.BLUE,
			"sub": "Online vs another player\nNo Rank Points at stake",
			"locked": Game.offline, "lock_text": "Needs the server"},
		{"id": "ranked", "title": "RANKED BRAWL", "color": UI.GOLD,
			"sub": "Ranked vs CPU · earn Rank Points" if level >= 5 else "Unlocks at Level 5 (you are Lv %d)" % level,
			"locked": Game.offline or level < 5, "lock_text": "Needs the server" if Game.offline else "Locked until Level 5"},
		{"id": "cpu", "title": "VS CPU", "color": Color("b388ff"),
			"sub": "Practice against the AI" + ("\nOffline: starter deck, no rewards" if Game.offline else ""),
			"locked": false},
	]
	for i in modes.size():
		_card(modes[i], Vector2(270 + i * 470, 170))
	UI.back_button(self, func(): Game.go("main_menu"))
	var tut := UI.button("HOW TO PLAY  ·  TUTORIAL", Game.start_tutorial, Vector2(440, 60), UI.GREEN)
	tut.position = Vector2(960 - 220, 958)
	add_child(tut)


func _card(m: Dictionary, at: Vector2) -> void:
	var col: Color = m.color
	var locked: bool = m.locked
	var p := UI.panel(Color(col, 0.4 if locked else 0.95), Color(0.05, 0.05, 0.12, 0.92))
	p.position = at
	p.custom_minimum_size = Vector2(440, 760)
	p.modulate = Color(1, 1, 1, 0.55) if locked else Color.WHITE
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var strip := ColorRect.new()
	strip.color = col
	strip.custom_minimum_size = Vector2(0, 8)
	v.add_child(strip)
	var t := UI.label(m.title, 40, col, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label(m.sub, 20, UI.MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(400, 64)
	v.add_child(s)
	var art := Control.new()
	art.custom_minimum_size = Vector2(400, 400)
	v.add_child(art)
	if m.id == "ranked" and not locked:
		_rank_art(art)
	else:
		var icon := UI.label({"casual": "VS", "ranked": "🔒", "cpu": "CPU"}[m.id], 120, col, true)
		icon.size = Vector2(400, 400)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art.add_child(icon)
		if not locked:
			# A neon sign: glowing outline and a slow pulse
			icon.label_settings.outline_color = Color(col, 0.6)
			icon.label_settings.outline_size = 18
			var pulse := icon.create_tween().set_loops()
			pulse.tween_property(icon, "modulate", Color(1.25, 1.25, 1.25), 1.2).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(icon, "modulate", Color.WHITE, 1.2).set_trans(Tween.TRANS_SINE)
	if locked:
		var l := UI.label("🔒  " + str(m.lock_text).to_upper(), 24, UI.MUTED, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	else:
		v.add_child(UI.button("SELECT", _start.bind(m.id), Vector2(400, 70), col))
		# The whole tile lifts toward you on hover
		p.pivot_offset = Vector2(220, 380)
		p.mouse_entered.connect(func():
			p.create_tween().tween_property(p, "scale", Vector2.ONE * 1.03, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		p.mouse_exited.connect(func():
			if not p.get_global_rect().has_point(p.get_global_mouse_position()):
				p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.15))


func _rank_art(parent: Control) -> void:
	var rank := str(Game.player.get("rank", "rookie"))
	var t := UI.tex("ranks/%s.png" % rank)
	if t == null:
		t = UI.tex("ranks/%s.png" % rank.capitalize())
	var img := UI.texture_rect(t, Vector2(300, 300))
	img.position = Vector2(50, 0)
	parent.add_child(img)
	var name := UI.label(rank.replace("_", " ").to_upper(), 30, RANK_COLORS.get(rank, Color.WHITE), true)
	name.size = Vector2(400, 40)
	name.position = Vector2(0, 310)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(name)
	var rp := UI.label("%d RP" % int(Game.player.get("rank_points", 0)), 22, UI.MUTED)
	rp.size = Vector2(400, 30)
	rp.position = Vector2(0, 352)
	rp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(rp)


func _start(mode: String) -> void:
	if _starting:
		return
	var difficulty := "hard" if mode == "ranked" else "normal"
	if mode == "cpu":
		difficulty = await _pick_difficulty()
		if difficulty == "":
			return
	if Game.offline:
		Game.duel_setup = {"mode": mode, "difficulty": difficulty}
		Game.go("rps")
		return
	if mode == "casual":
		Game.go("matchmaking")
		return
	_starting = true
	var spin := UI.spinner(self, Vector2(960, 980), "LOADING YOUR DECK…")
	var deck := await Game.load_duel_deck()
	spin.queue_free()
	_starting = false
	if deck.has("error"):
		var buttons := [["CLOSE", func(): pass]]
		if deck.get("gate", false):
			buttons.push_front(["DECK EDITOR", func(): Game.go("deck_builder"), UI.BLUE])
		UI.dialog(self, "CAN'T START DUEL", deck.error, buttons, UI.RED)
		return
	# The server runs the match (and decides who goes first)
	_starting = true
	_spin = UI.spinner(self, Vector2(960, 980), "STARTING MATCH…")
	var why := await Game.request_cpu_match(mode == "ranked", difficulty)
	if why != "":
		on_online_error(why)
		return
	# mp:start normally arrives within a second; an older server doesn't know CPU matches
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree() and _starting:
		on_online_error("The server didn't start the match. It may need updating (git pull, then restart alleyway-backend).")


## Easy / Normal / Hard for VS CPU; "" when cancelled. Rewards scale with it on the server.
func _pick_difficulty() -> String:
	var choice := [""]
	var rewards := "" if Game.offline else "

Easy pays half rewards, Hard pays 50% more."
	UI.dialog(self, "CHOOSE DIFFICULTY",
		"Easy: a forgetful CPU that misses chances.
Normal: the standard CPU.
Hard: sacrifices cleverly and trades up." + rewards,
		[["EASY", func(): choice[0] = "easy", UI.GREEN], ["NORMAL", func(): choice[0] = "normal", UI.BLUE],
		["HARD", func(): choice[0] = "hard", UI.RED], ["CANCEL", func(): choice[0] = "cancel"]], Color("b388ff"))
	while choice[0] == "":
		await get_tree().process_frame
	return "" if choice[0] == "cancel" else choice[0]


## mp:error while starting a CPU match (net.gd calls this on the current screen).
func on_online_error(message: String) -> void:
	if _spin and is_instance_valid(_spin):
		_spin.queue_free()
	_spin = null
	_starting = false
	UI.dialog(self, "CAN'T START DUEL", message, [["CLOSE", func(): pass]], UI.RED)
