extends RefCounted
## Turf Defense on the duel screen (backend/socket/coopMatch.js; the bosses: data/bosses.json): the
## boss's entrance, its phase changes, what it says during the fight, its plate with the big Morale
## bar marked where each phase starts, and the intel panel listing its phases.
##   var show := TurfShow.new(duel, start.boss)   await show.intro(players)   await show.phase(ev)

const LETTERBOX := 118.0
const TYPE_CPS := 46.0   # how fast its lines type out (characters a second)
const GOLD := Color("f4d35e")
const BLUE := Color("4cc9f0")
const TEAL := Color("3ee6d0")   # your ally (duel.gd TEAL)

var d: Node2D          # the duel screen (duel.gd)
var info: Dictionary   # the boss as the server sent it (shared/turf.js bossInfo)
var color: Color
var said := {}         # lines already said once (low, player_out)
var _plate := {}       # the boss plate's parts: ticks, phase tag
var _intel: Control
var _skip := false     # the player clicked to hurry a cutscene along


func _init(duel: Node2D, boss: Dictionary) -> void:
	d = duel
	info = boss
	color = Color(str(boss.get("color", "#e63946")))


func boss_name() -> String:
	return str(info.get("name", "THE BOSS")).to_upper()


func lines() -> Dictionary:
	return info.get("lines", {}) if info.get("lines") is Dictionary else {}


func portrait() -> Texture2D:
	return CardDB.art(str(info.get("portrait", "")))


# ── Cutscenes ────────────────────────────────────────────────────────────────

## The entrance: letterbox, the boss's card sliding in over its colour, its name slamming down,
## its lines typed out one by one, then the two of you, and DEFEND THE TURF. A click hurries each
## step; SKIP ends it.
func intro(players: Dictionary) -> void:
	var root := _stage()
	var bars := _letterbox(root)
	var dim: ColorRect = root.get_child(0)
	d.create_tween().tween_property(dim, "color:a", 0.88, 0.5)
	var skip := UI.button("SKIP  ▶", func(): root.set_meta("skip", true), Vector2(150, 44), Color(1, 1, 1, 0.5))
	skip.position = Vector2(1740, 1080 - LETTERBOX + 36)
	root.add_child(skip)
	Game.sound.music("", 0.8)
	Sfx.play("riser", 0.55)
	await _hold(root, 0.5)
	# The card, over a glow in its colour
	var glow := _glow(Vector2(1300, 520), 900.0, 0.55)
	root.add_child(glow)
	var art := UI.texture_rect(portrait(), Vector2(400, 565))
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(2000, 230)
	art.rotation_degrees = 4.0
	art.pivot_offset = art.size / 2
	root.add_child(art)
	var t: Tween = d.create_tween().set_parallel()
	t.tween_property(art, "position:x", 1110.0, 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(art, "rotation_degrees", -3.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	glow.modulate.a = 0.0
	t.tween_property(glow, "modulate:a", 1.0, 0.8)
	var bob := art.create_tween().set_loops()
	bob.tween_property(art, "position:y", 214.0, 1.8).set_trans(Tween.TRANS_SINE)
	bob.tween_property(art, "position:y", 230.0, 1.8).set_trans(Tween.TRANS_SINE)
	await _hold(root, 0.6)
	# Its name, title and level
	var tag: Label = d._label(26, color.lightened(0.25), true)
	tag.text = "TURF DEFENSE  ·  %s" % str(info.get("level_name", "")).to_upper()
	tag.position = Vector2(140, 250)
	root.add_child(tag)
	var name_l: Label = d._label(96, Color.WHITE, true)
	name_l.text = boss_name()
	name_l.position = Vector2(130, 290)
	name_l.size = Vector2(960, 120)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.label_settings.outline_color = Color(color, 0.9)
	name_l.label_settings.outline_size = 14
	name_l.pivot_offset = Vector2(0, 60)
	name_l.scale = Vector2.ONE * 1.8
	name_l.modulate.a = 0.0
	root.add_child(name_l)
	var nt: Tween = d.create_tween().set_parallel()
	nt.tween_property(name_l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	nt.tween_property(name_l, "modulate:a", 1.0, 0.1)
	await d._wait(0.18)
	Sfx.play("slam", 0.7)
	Sfx.play("boom", 0.6, -4.0)
	d.shake(24)
	d._post_pulse("aberration", 12.0, 0.5)
	var title: Label = d._label(34, color.lightened(0.4), true)
	title.text = str(info.get("title", "")).to_upper()
	title.position = Vector2(140, 290 + name_l.get_minimum_size().y + 4)
	root.add_child(title)
	var stats: Label = d._label(22, Color(1, 1, 1, 0.75), true)
	stats.text = _stat_line()
	stats.position = Vector2(140, title.position.y + 50)
	root.add_child(stats)
	for n in [title, stats]:
		n.modulate.a = 0.0
		d.create_tween().tween_property(n, "modulate:a", 1.0, 0.35)
	await _hold(root, 0.7)
	# What it has to say
	var said_any := false
	for line in (lines().get("intro", []) as Array):
		if root.get_meta("skip", false):
			break
		said_any = true
		await _typed(root, str(line), Vector2(140, 1080 - LETTERBOX - 210), 900.0, 2.0)
	if not said_any:
		await _hold(root, 0.6)
	# The crew
	if not root.get_meta("skip", false):
		await _crew(root, players)
	Sfx.play("boom", 0.75)
	d.shake(18)
	d._sweep_banner("DEFEND THE TURF!", GOLD)
	await d._wait(0.35)
	var out: Tween = d.create_tween().set_parallel()
	out.tween_property(root, "modulate:a", 0.0, 0.45)
	for b in bars:
		out.tween_property(b, "position:y", b.position.y + (-LETTERBOX if b.position.y < 540 else LETTERBOX), 0.45)
	await out.finished
	root.queue_free()
	music(0)


## A phase: its colour floods the screen, the boss's card slams in, the phase's name, and its line.
func phase(ev: Dictionary) -> void:
	var n := int(ev.get("phase", 1))
	var label := str(ev.get("label", "")).to_upper()
	update_phase(n)
	var root := _stage()
	var bars := _letterbox(root)
	var dim: ColorRect = root.get_child(0)
	dim.color = Color(color.darkened(0.75), 0.0)
	d.create_tween().tween_property(dim, "color:a", 0.78, 0.25)
	d._screen_flash(color, 0.55)
	d._post_pulse("aberration", 18.0, 0.6)
	d.shake(30)
	Sfx.play("riser", 0.7)
	Sfx.play("boom", 0.55)
	var glow := _glow(Vector2(560, 520), 760.0, 0.7)
	root.add_child(glow)
	var art := UI.texture_rect(portrait(), Vector2(320, 452))
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(-400, 300)
	art.rotation_degrees = -6.0
	art.pivot_offset = art.size / 2
	root.add_child(art)
	var t: Tween = d.create_tween().set_parallel()
	t.tween_property(art, "position:x", 400.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(art, "rotation_degrees", 3.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var shiver := art.create_tween().set_loops(12)   # (it trembles with power)
	shiver.tween_property(art, "position:y", 296.0, 0.05)
	shiver.tween_property(art, "position:y", 304.0, 0.05)
	await d._wait(0.3)
	var head: Label = d._label(30, color.lightened(0.4), true)
	head.text = "PHASE %d" % (n + 1)
	head.position = Vector2(800, 330)
	root.add_child(head)
	var big: Label = d._label(104, Color.WHITE, true)
	big.text = label
	big.position = Vector2(790, 370)
	big.size = Vector2(1060, 130)
	big.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big.label_settings.outline_color = Color(color, 0.95)
	big.label_settings.outline_size = 16
	big.pivot_offset = Vector2(0, 60)
	big.scale = Vector2.ONE * 2.0
	big.modulate.a = 0.0
	root.add_child(big)
	var bt: Tween = d.create_tween().set_parallel()
	bt.tween_property(big, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bt.tween_property(big, "modulate:a", 1.0, 0.08)
	await d._wait(0.16)
	Sfx.play("slam", 0.6)
	d.shake(26)
	d._burst(Vector2(1080, 440), color.lightened(0.3), 70, 900, 1.1, -60.0)
	var said_line := str((lines().get("phase", {}) as Dictionary).get(str(n), "")) if lines().get("phase") is Dictionary else ""
	if said_line != "":
		await _typed(root, said_line, Vector2(800, 380 + big.get_minimum_size().y + 20), 960.0, 1.4)
	else:
		await _hold(root, 1.4)
	var out: Tween = d.create_tween().set_parallel()
	out.tween_property(root, "modulate:a", 0.0, 0.35)
	for b in bars:
		out.tween_property(b, "position:y", b.position.y + (-LETTERBOX if b.position.y < 540 else LETTERBOX), 0.35)
	await out.finished
	root.queue_free()
	music(n)


## The boss's last word as the match ends (it lost: "defeat", it won: "victory").
func farewell(won_by_crew: bool) -> void:
	var line := str(lines().get("defeat" if won_by_crew else "victory", ""))
	if line == "":
		return
	var root := _stage()
	var dim: ColorRect = root.get_child(0)
	d.create_tween().tween_property(dim, "color:a", 0.6, 0.3)
	var art := UI.texture_rect(portrait(), Vector2(260, 367))
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(300, 330)
	art.modulate = Color(0.55, 0.55, 0.6) if won_by_crew else Color.WHITE
	root.add_child(art)
	if won_by_crew:   # (it crumbles)
		var fall: Tween = d.create_tween().set_parallel()
		fall.tween_property(art, "rotation_degrees", 9.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(art, "position:y", 380.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _typed(root, line, Vector2(620, 440), 1000.0, 1.3)
	var out: Tween = d.create_tween()
	out.tween_property(root, "modulate:a", 0.0, 0.35)
	await out.finished
	root.queue_free()


## A line in the middle of the fight (low Morale, a player going down): a speech box by the boss's
## plate that types out and fades, without stopping the match.
func say(key: String) -> void:
	if said.has(key):
		return
	var text := str(lines().get(key, ""))
	if text == "":
		return
	said[key] = true
	var p: Control = d._panels.get("boss", {}).get("root")
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", d._box(Color(0.03, 0.02, 0.06, 0.95), color, 3, 12))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var face := UI.texture_rect(UI.card_crop(str(info.get("portrait", ""))), Vector2(56, 56), true)
	row.add_child(face)
	var l: Label = d._label(24, Color.WHITE, true)
	l.text = "“%s”" % text
	l.custom_minimum_size = Vector2(0, 56)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.visible_ratio = 0.0
	row.add_child(l)
	d.overlay.add_child(box)
	box.z_index = 40
	box.reset_size()
	var sz := box.get_combined_minimum_size()
	var at := Vector2(1028 - sz.x / 2, 24)
	if p:
		at = Vector2(p.position.x + p.size.x / 2 - sz.x / 2, p.position.y + p.size.y + 6)
	box.position = at
	box.modulate.a = 0.0
	Sfx.play("neon_buzz", 0.7, -8.0)
	var t := box.create_tween()
	t.tween_property(box, "modulate:a", 1.0, 0.2)
	t.tween_property(l, "visible_ratio", 1.0, text.length() / TYPE_CPS)
	t.tween_interval(2.4)
	t.tween_property(box, "modulate:a", 0.0, 0.5)
	t.tween_callback(box.queue_free)


## The music: the boss's own track if the game has one, the tense one once it's angry.
func music(phase_now: int) -> void:
	if Game.sound.has_track("boss"):
		Game.sound.music("boss", 1.5)
	elif phase_now >= 1 and Game.sound.has_track("duel_tense"):
		Game.sound.music("duel_tense", 1.5)
	else:
		Game.sound.music("duel", 1.5)


# ── The boss's plate and intel ──────────────────────────────────────────────

## Its plate, under its board: picture, name and title, Morale, and a long bar marked where each
## phase starts. Returns the parts duel.gd keeps in _panels (morale, bar, auth, piles, flash).
func build_plate(p: Panel) -> Dictionary:
	p.add_theme_stylebox_override("panel", UI._glow(d._box(Color(0.04, 0.02, 0.06, 0.94), color, 3, 10), color, 0.9))
	var av := TextureRect.new()
	av.position = Vector2(8, 8)
	av.size = Vector2(74, 74)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture = UI.card_crop(str(info.get("portrait", "")))
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(av)
	var n: Label = d._label(24, Color.WHITE, true)
	n.text = boss_name()
	n.position = Vector2(92, 2)
	n.label_settings.outline_color = Color(color, 0.7)
	p.add_child(n)
	var sub: Label = d._label(13, color.lightened(0.35), true)
	sub.text = "%s  ·  %s" % [str(info.get("title", "")).to_upper(), str(info.get("level_name", "")).to_upper()]
	sub.position = Vector2(94, 32)
	p.add_child(sub)
	var morale: Label = d._label(34, Color.WHITE, true)
	var most := int(info.get("morale", 10000))
	morale.text = str(most)
	morale.label_settings.outline_color = Color(color, 0.85)
	morale.size = Vector2(p.size.x - 16, 40)
	morale.position = Vector2(8, 0)
	morale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(morale)
	var track := ColorRect.new()
	track.position = Vector2(92, 54)
	track.size = Vector2(p.size.x - 104, 12)
	track.color = Color(1, 1, 1, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(track)
	var bar := ColorRect.new()
	bar.size = track.size
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	var sheen := ColorRect.new()   # (a lighter top edge on the bar)
	sheen.size = Vector2(track.size.x, 3)
	sheen.color = Color(1, 1, 1, 0.25)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(sheen)
	# Where each phase starts: a notch across the bar
	var ticks: Array = []
	var phases: Array = info.get("phases", []) if info.get("phases") is Array else []
	for i in phases.size():
		var x: float = track.size.x * clampf(float(phases[i].get("below", 0)) / maxf(1.0, float(most)), 0.0, 1.0)
		var tick := ColorRect.new()
		tick.size = Vector2(4, 20)
		tick.position = Vector2(x - 2, -4)
		tick.color = Color.WHITE
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(tick)
		var cap := ColorRect.new()   # (a small diamond on top)
		cap.size = Vector2(8, 8)
		cap.pivot_offset = cap.size / 2
		cap.rotation = PI / 4
		cap.position = Vector2(x - 4, -10)
		cap.color = color.lightened(0.5)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(cap)
		ticks.append([tick, cap])
	var auth: Label = d._label(13, GOLD, true)
	auth.position = Vector2(92, 70)
	auth.pivot_offset = Vector2(0, 8)
	p.add_child(auth)
	var piles: Label = d._label(12, Color(0.72, 0.7, 0.82))
	piles.position = Vector2(240, 72)
	p.add_child(piles)
	var tag: Label = d._label(13, color.lightened(0.45), true)
	tag.position = Vector2(p.size.x - 290, 70)
	tag.size = Vector2(280, 18)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.text = "PHASE 1"
	p.add_child(tag)
	var flash := ColorRect.new()
	flash.color = Color(1, 0.15, 0.15, 0)
	flash.size = p.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(flash)
	_plate = {"ticks": ticks, "tag": tag}
	return {"root": p, "morale": morale, "bar": bar, "auth": auth, "piles": piles,
		"flash": flash, "shown": float(most), "base": p.position, "accent": color}


## The intel panel (top right, where a 1v1 opponent's plate goes): the boss's level and its phases,
## the ones it has reached ticked off and the next one lit.
func build_intel(p: Panel) -> void:
	p.visible = true
	for c in p.get_children():
		c.queue_free()
	_intel = VBoxContainer.new()
	_intel.position = Vector2(12, 10)
	_intel.size = Vector2(p.size.x - 24, p.size.y - 20)
	_intel.add_theme_constant_override("separation", 2)
	p.add_child(_intel)
	update_phase(0)


func update_phase(reached: int) -> void:
	if _plate.has("tag"):
		var phases: Array = info.get("phases", [])
		_plate.tag.text = "PHASE %d  ·  %s" % [reached + 1, str(phases[reached - 1].get("label", "")).to_upper()] if reached > 0 and reached <= phases.size() else "PHASE 1"
		for i in _plate.ticks.size():
			for node in _plate.ticks[i]:
				node.modulate = Color(1, 1, 1, 0.3) if i < reached else Color.WHITE
	if _intel == null or not is_instance_valid(_intel):
		return
	for c in _intel.get_children():
		c.queue_free()
	var head: Label = d._label(18, color.lightened(0.3), true)
	head.text = "BOSS  ·  %s" % str(info.get("level_name", "")).to_upper()
	_intel.add_child(head)
	var perks: Label = d._label(12, Color(1, 1, 1, 0.7))
	var bits := ["%d MORALE" % int(info.get("morale", 0))]
	if int(info.get("draw", 0)) > 0:
		bits.append("+%d DRAW" % int(info.draw))
	if int(info.get("authority", 0)) > 0:
		bits.append("+%d AUTHORITY" % int(info.authority))
	perks.text = "  ·  ".join(bits)
	perks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perks.custom_minimum_size = Vector2(_intel.size.x, 0)
	_intel.add_child(perks)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_intel.add_child(gap)
	var phases: Array = info.get("phases", []) if info.get("phases") is Array else []
	for i in phases.size():
		var done := i < reached
		var next := i == reached
		var l: Label = d._label(14, Color(1, 1, 1, 0.35) if done else (color.lightened(0.4) if next else Color(1, 1, 1, 0.75)), true)
		l.text = "%s %s  ·  ≤ %d" % ["✓" if done else ("▶" if next else "·"), str(phases[i].get("label", "")).to_upper(), int(phases[i].get("below", 0))]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(_intel.size.x, 0)
		_intel.add_child(l)


# ── Pieces ───────────────────────────────────────────────────────────────────

## A full-screen layer over everything (its first child is the dim), that takes clicks: a click
## hurries the cutscene.
func _stage() -> Control:
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.z_index = 300
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = root.size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventJoypadButton and e.pressed):
			_skip = true)
	d.overlay.add_child(root)
	return root


func _letterbox(root: Control) -> Array:
	var out: Array = []
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 0.96)
		b.size = Vector2(1920, LETTERBOX)
		b.position = Vector2(0, -LETTERBOX if top else 1080.0)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		var edge := ColorRect.new()   # (a thin line of the boss's colour on the inside edge)
		edge.color = Color(color, 0.8)
		edge.size = Vector2(1920, 3)
		edge.position = Vector2(0, LETTERBOX - 3 if top else 0.0)
		b.add_child(edge)
		d.create_tween().tween_property(b, "position:y", 0.0 if top else 1080.0 - LETTERBOX, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		out.append(b)
	return out


func _glow(at: Vector2, size: float, strength: float) -> TextureRect:
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray([Color(color, strength), Color(color, 0.0)])
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var r := TextureRect.new()
	r.texture = g
	r.size = Vector2(size, size)
	r.position = at - r.size / 2
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pulse := r.create_tween().set_loops()
	pulse.tween_property(r, "scale", Vector2.ONE * 1.06, 1.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(r, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE)
	r.pivot_offset = r.size / 2
	return r


## A line typed out in the boss's voice under its name, then held a moment (a click finishes the
## typing at once, a second click moves on).
func _typed(root: Control, text: String, at: Vector2, width: float, hold: float) -> void:
	var speaker: Label = d._label(18, color.lightened(0.3), true)
	speaker.text = boss_name()
	speaker.position = at
	root.add_child(speaker)
	var l: Label = d._label(38, Color.WHITE, true)
	l.text = "“%s”" % text
	l.position = at + Vector2(0, 26)
	l.size = Vector2(width, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible_ratio = 0.0
	root.add_child(l)
	_skip = false
	var secs := text.length() / TYPE_CPS
	var shown := 0.0
	var last_chars := 0
	while shown < secs and not _skip and not root.get_meta("skip", false):
		await d.get_tree().process_frame
		shown += d.get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		l.visible_ratio = shown / secs
		var chars := int(l.visible_ratio * text.length())
		if chars - last_chars >= 3:   # (a soft tick as it types)
			last_chars = chars
			Sfx.play("click", randf_range(1.5, 1.8), -18.0)
	l.visible_ratio = 1.0
	_skip = false
	await _hold(root, hold)
	var t: Tween = d.create_tween().set_parallel()
	t.tween_property(l, "modulate:a", 0.0, 0.2)
	t.tween_property(speaker, "modulate:a", 0.0, 0.2)
	await t.finished
	l.queue_free()
	speaker.queue_free()


## Wait, unless the player clicks (or skips the whole thing).
func _hold(root: Control, secs: float) -> void:
	_skip = false
	var left := secs
	while left > 0.0 and not _skip and not root.get_meta("skip", false):
		await d.get_tree().process_frame
		left -= d.get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	_skip = false


## The two of you, side by side, against it.
func _crew(root: Control, players: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	for key in ["player", "ally"]:
		var p: Dictionary = players.get(key, {}) if players.get(key) is Dictionary else {}
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var pic := UI.texture_rect(UI.avatar(str(p.get("avatar_url", "")) if p.get("avatar_url") else ""), Vector2(120, 120), true)
		box.add_child(pic)
		var n: Label = d._label(26, BLUE if key == "player" else TEAL, true)
		n.text = str(p.get("username", "YOU" if key == "player" else "ALLY")).to_upper().left(14)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(n)
		row.add_child(box)
		if key == "player":
			var amp: Label = d._label(64, GOLD, true)
			amp.text = "&"
			amp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(amp)
	row.reset_size()
	row.position = Vector2(960 - row.size.x / 2 - 300, 1080 - LETTERBOX - 260)
	row.modulate.a = 0.0
	var t: Tween = d.create_tween().set_parallel()
	t.tween_property(row, "modulate:a", 1.0, 0.3)
	t.tween_property(row, "position:y", row.position.y - 30.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("turn_yours", 1.0)
	await _hold(root, 1.3)


func _stat_line() -> String:
	var bits := ["%d MORALE" % int(info.get("morale", 0))]
	if int(info.get("draw", 0)) > 0:
		bits.append("DRAWS %d EXTRA" % int(info.draw))
	if int(info.get("authority", 0)) > 0:
		bits.append("+%d AUTHORITY A TURN" % int(info.authority))
	var n: int = (info.get("phases", []) as Array).size() if info.get("phases") is Array else 0
	if n > 0:
		bits.append("%d PHASES" % (n + 1))
	return "  ·  ".join(bits)
