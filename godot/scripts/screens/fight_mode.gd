extends Screen
## Pick a battle mode. Duels use the player's saved active deck (checked for 40 cards first).

const RANK_COLORS := {
	"rookie": Color("9aa7b8"), "street_tough": Color("4ade80"), "enforcer": Color("38bdf8"),
	"underboss": Color("a46bff"), "kingpin": Color("ff3b3b"), "legend": Color("ffd34d"),
}

const CARD := Vector2(150, 212)   # a card in a mode's picture (the card art's shape)

var _starting := false
var _spin: Label = null
var _arena: Control = null   # the arena roulette while a CPU match starts
const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "arena_rooftop.png" if UI.tex("arena_rooftop.png") else "duel_background.png", 0.4 if UI.tex("arena_rooftop.png") else 0.62)
	Game.sound.ambience("rooftop")   # (the rooftop over the city)
	UI.title(self, "SELECT BATTLE MODE")
	if Game.player.get("first_win_ready", false) and not Game.offline:
		var chip := UI.label("★  FIRST WIN OF THE DAY: +%d XP BONUS WAITING  ★" % int(Game.player.get("first_win_xp", 75)), 22, UI.GOLD, true)
		chip.size = Vector2(1920, 30)
		chip.position = Vector2(0, 104)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.label_settings.outline_color = Color(0, 0, 0, 0.8)
		chip.label_settings.outline_size = 6
		add_child(chip)
		var glow := chip.create_tween().set_loops()
		glow.tween_property(chip, "modulate", Color(1.3, 1.25, 1.0), 0.9).set_trans(Tween.TRANS_SINE)
		glow.tween_property(chip, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
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
		{"id": "ffa", "title": "FREE-FOR-ALL", "color": Color("ff9f43"),
			"sub": "4 players online: CPUs fill empty seats\nLast one standing wins",
			"locked": Game.offline, "lock_text": "Needs the server"},
	]
	for i in modes.size():
		_card(modes[i], Vector2(90 + i * 440, 170))
	UI.back_button(self, func(): Game.go("main_menu"))
	var tut := UI.button("HOW TO PLAY  ·  TUTORIAL", Game.start_tutorial, Vector2(440, 60), UI.GREEN)
	tut.position = Vector2(960 - 220, 958)
	add_child(tut)
	if not Game.offline:
		var lb := UI.button("🏆  LEADERBOARD", func(): Game.go("leaderboard"), Vector2(300, 60), UI.GOLD)
		lb.position = Vector2(400, 958)
		add_child(lb)
	if not Game.offline:
		_weekly()


## This week's challenge (GET /api/challenge): its twist, its reward, and PLAY (or WON).
func _weekly() -> void:
	var r := await Api.request("GET", "/api/challenge")
	if not r.ok or not (r.data is Dictionary) or not is_inside_tree():
		return
	var c: Dictionary = r.data
	var p := UI.panel(UI.RED, Color(0.08, 0.03, 0.05, 0.94))
	p.position = Vector2(1210, 940)
	p.custom_minimum_size = Vector2(680, 110)
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label("WEEKLY CHALLENGE  ·  %s" % str(c.get("name", "")).to_upper(), 22, UI.RED, true))
	var t := UI.label(str(c.get("text", "")), 17, Color.WHITE)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 0)
	v.add_child(t)
	var reward := UI.reward_text(c.get("reward", {}) if c.get("reward") is Dictionary else {})
	v.add_child(UI.label(("Won this week  ·  a new one each Monday") if c.get("won", false) else "Beat the Hard CPU: " + reward, 16, UI.MUTED))
	var b := UI.button("PLAY AGAIN" if c.get("won", false) else "PLAY", _start.bind("challenge"), Vector2(170, 64), UI.RED)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)


func _card(m: Dictionary, at: Vector2) -> void:
	var col: Color = m.color
	var locked: bool = m.locked
	var p := UI.panel(Color(col, 0.4 if locked else 0.95), Color(0.05, 0.05, 0.12, 0.92))
	p.position = at
	p.custom_minimum_size = Vector2(420, 760)
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
	s.custom_minimum_size = Vector2(380, 64)
	v.add_child(s)
	var art := Control.new()
	art.custom_minimum_size = Vector2(380, 480)
	v.add_child(art)
	var fan: Array = []
	if m.id == "ranked" and not locked:
		_rank_art(art)
	else:
		fan = _mode_art(art, m.id, col)
		var icon := UI.label({"casual": "VS", "ranked": "🔒", "cpu": "CPU", "ffa": "FFA"}[m.id], 120 if fan.is_empty() else 84, col, true)
		icon.size = Vector2(380, 400)
		if not fan.is_empty():   # (over the cards, low down: the cards are the picture)
			icon.size = Vector2(380, 120)
			icon.position = Vector2(0, 360 if m.id != "casual" else 190)
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
		v.add_child(UI.button("SELECT", _start.bind(m.id), Vector2(380, 70), col))
		# The whole tile lifts toward you on hover
		p.pivot_offset = Vector2(210, 380)
		p.mouse_entered.connect(func():
			p.create_tween().tween_property(p, "scale", Vector2.ONE * 1.03, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_spread(fan, 1.0))
		p.mouse_exited.connect(func():
			if not p.get_global_rect().has_point(p.get_global_mouse_position()):
				p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.15)
				_spread(fan, 0.0))


## A mode's picture made of real cards, fanned from a point below them, over a glow in the mode's
## colour. Returns the cards (for _spread). Casual: the clans' leaders lean in at each other; the CPU:
## one strong card of the other clan beside a card face down; FFA: the top card of each clan, fanned.
func _mode_art(parent: Control, id: String, col: Color) -> Array:
	var picks := _mode_cards(id)
	if picks.is_empty():
		return []
	var glow := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray([Color(col, 0.55), Color(col, 0.0)])
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	glow.texture = g
	glow.size = Vector2(420, 360)
	glow.position = Vector2(-20, 50)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glow)
	var n := picks.size()
	# [x offset, degrees]: casual leans the two in at each other; the others fan out
	var lay: Array = {"casual": [[-78.0, 8.0], [78.0, -8.0]], "cpu": [[-52.0, -7.0], [42.0, 5.0]],
		"ffa": [[-105.0, -12.0], [-35.0, -4.0], [35.0, 4.0], [105.0, 12.0]]}.get(id, [])
	var out: Array = []
	for i in n:
		var tex: Texture2D = picks[i]
		var holder := Control.new()
		holder.size = CARD
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.pivot_offset = CARD / 2
		var base: Array = lay[i] if i < lay.size() else [0.0, 0.0]
		holder.position = Vector2(190 - CARD.x / 2 + base[0], 90)
		holder.rotation_degrees = base[1]
		holder.set_meta("base", base)
		var shadow := ColorRect.new()
		shadow.color = Color(0, 0, 0, 0.45)
		shadow.size = CARD
		shadow.position = Vector2(8, 10)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(shadow)
		var r := UI.texture_rect(tex, CARD)
		r.stretch_mode = TextureRect.STRETCH_SCALE
		holder.add_child(r)
		parent.add_child(holder)
		out.append(holder)
		# A slow sway, out of step card to card
		var sway := holder.create_tween().set_loops()
		sway.tween_property(r, "position:y", -5.0, 1.6 + i * 0.3).set_trans(Tween.TRANS_SINE)
		sway.tween_property(r, "position:y", 0.0, 1.6 + i * 0.3).set_trans(Tween.TRANS_SINE)
	return out


## Opens the fan (hovered: 1) or closes it back (0).
func _spread(fan: Array, open: float) -> void:
	for h in fan:
		if not is_instance_valid(h):
			continue
		var base: Array = h.get_meta("base")
		var t: Tween = h.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(h, "rotation_degrees", base[1] * (1.0 + 0.45 * open), 0.25)
		t.tween_property(h, "position:x", 190 - CARD.x / 2 + base[0] * (1.0 + 0.18 * open), 0.25)
		t.tween_property(h, "position:y", 90 - 14.0 * open, 0.25)


## The card art for a mode's picture (none if the art isn't there).
func _mode_cards(id: String) -> Array:
	var mine := str(Game.player.get("chosen_clan", ""))
	var leaders := {}
	var top := {}   # clan -> its rarest, then strongest, character
	for cid in CardDB.all():
		var c: Dictionary = CardDB.all()[cid]
		var clan := str(c.get("clan", ""))
		if clan == "" or c.get("token", false) or int(c.get("level", 1)) > 1:   # (a Striver shows at its first level)
			continue
		if c.get("cardType") == "leader":
			leaders[clan] = cid
		elif c.get("cardType") == "gang_member":
			var best: Dictionary = CardDB.get_card(top.get(clan, ""))
			var score := int(c.get("rarity", 1)) * 100000 + int(c.get("attack", 0))
			if best.is_empty() or score > int(best.get("rarity", 1)) * 100000 + int(best.get("attack", 0)):
				top[clan] = cid
	var clans: Array = top.keys()
	clans.sort()
	if clans.has(mine):   # (yours first)
		clans.erase(mine)
		clans.push_front(mine)
	var other: String = clans[1] if clans.size() > 1 else (clans[0] if clans.size() > 0 else "")
	var ids: Array = []
	match id:
		"casual":
			for k in clans.slice(0, 2):
				ids.append(leaders.get(k, top.get(k, "")))
		"cpu":
			ids = ["back:" + other, top.get(other, "")]
		"ffa":
			for k in clans:
				ids.append(top[k])
				ids.append(leaders.get(k, ""))
			ids = ids.filter(func(x): return x != "").slice(0, 4)
	var out: Array = []
	for cid in ids:
		var t: Texture2D = CardDB.back(str(CardDB.clan(cid.substr(5)).get("tag", ""))) if str(cid).begins_with("back:") else CardDB.art(str(cid))
		if t:
			out.append(t)
	return out if out.size() >= 2 else []


func _rank_art(parent: Control) -> void:
	var rank := str(Game.player.get("rank", "rookie"))
	var col: Color = RANK_COLORS.get(rank, Color.WHITE)
	var glow := TextureRect.new()   # (its colour glowing behind it)
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray([Color(col, 0.45), Color(col, 0.0)])
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	glow.texture = g
	glow.size = Vector2(420, 380)
	glow.position = Vector2(-20, 0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glow)
	var img := UI.texture_rect(UI.tex("ranks/%s.png" % rank), Vector2(300, 300))
	img.position = Vector2(40, 40)
	parent.add_child(img)
	var bob := img.create_tween().set_loops()   # (it floats)
	bob.tween_property(img, "position:y", 28.0, 1.8).set_trans(Tween.TRANS_SINE)
	bob.tween_property(img, "position:y", 40.0, 1.8).set_trans(Tween.TRANS_SINE)
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "modulate:a", 0.55, 1.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	var name := UI.label(rank.replace("_", " ").to_upper(), 30, RANK_COLORS.get(rank, Color.WHITE), true)
	name.size = Vector2(380, 40)
	name.position = Vector2(0, 350)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(name)
	var rp := UI.label("%d RP" % int(Game.player.get("rank_points", 0)), 22, UI.MUTED)
	rp.size = Vector2(380, 30)
	rp.position = Vector2(0, 392)
	rp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(rp)


func _start(mode: String) -> void:
	if _starting:
		return
	var difficulty := "hard" if mode in ["ranked", "challenge"] else "normal"
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
	if mode == "ffa":   # the lobby (screens/ffa_lobby.gd) joins the queue and starts the match
		Game.go("ffa_lobby")
		return
	# The server runs the match (and decides who goes first)
	_starting = true
	_spin = UI.spinner(self, Vector2(960, 980), "STARTING MATCH…")
	var arena := ArenaRoulette.random_id()
	_arena = ArenaRoulette.spin(self, arena, Vector2(1460, 784))
	var why := await Game.request_cpu_match(mode == "ranked", difficulty, mode == "challenge", arena)
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


## mp:start for the CPU match: the duel opens once the arena has landed.
func on_online_start(_data) -> void:
	if _arena and is_instance_valid(_arena) and not _arena.done:
		await _arena.landed
	Game.go("duel")


## mp:error while starting a CPU match (net.gd calls this on the current screen).
func on_online_error(message: String) -> void:
	if _spin and is_instance_valid(_spin):
		_spin.queue_free()
	_spin = null
	if _arena and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_starting = false
	UI.dialog(self, "CAN'T START DUEL", message, [["CLOSE", func(): pass]], UI.RED)
