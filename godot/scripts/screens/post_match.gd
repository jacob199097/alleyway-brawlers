extends Screen
## After a duel: Victory/Defeat art (its BRAWL AGAIN / MENU buttons are part of the artwork),
## the match stats, your level and clan mastery filling with the XP the server grants, what the
## match paid, and the MVP card.
## After a match against a player, either can offer a REMATCH (backend/socket/onlineMatch.js).

const ART_SIZE := Vector2(920, 613)     # victory.png / defeat.png are 1536×1024
const ART_POS := Vector2(500, 0)

const PANEL_Y := 610.0
const BAR_W := 420.0   # the XP and mastery bars
const INTRO := 0.9   # seconds until the result has landed and the panels are in; counters wait for it
const GOLD_LIGHT := Color(1.0, 0.85, 0.45)
const BLOOD := Color(0.85, 0.05, 0.1)

var _xp_fill: Control
var _xp_label: Label        # "+37 XP"
var _xp_numbers: Label      # "481 / 1469 XP"
var _level_icon: TextureRect
var _level_text: Label
var _mastery_box: VBoxContainer
var _rewards: Label
var _rematch: Button
var _rematch_note: Label
var _rematch_done := false   # asked, declined or expired: nothing more to tell the server
var _won := false
var _backdrop: ShaderMaterial
var _fx: ShaderMaterial      # full-screen shockwave, colour split, impact frame, red pulse (shaders/post.gdshader)
var _shake := 0.0
var _dot: Texture2D          # soft round particle
var _add := CanvasItemMaterial.new()
var _showcase: HBoxContainer   # level-up rewards: new emblem, profile picture, free pack button


func _ready() -> void:
	var d: Dictionary = Game.match_result
	_won = d.get("result") == "win"
	Game.sound.ambience("")
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_dot = _soft_dot()
	_build_backdrop(d.get("snapshot"))
	var rays := _rays(ART_POS + ART_SIZE * Vector2(0.5, 0.42)) if _won else null
	var art := UI.texture_rect(UI.tex("victory.png" if _won else "defeat.png"), ART_SIZE)
	art.position = ART_POS
	art.pivot_offset = ART_SIZE * Vector2(0.5, 0.42)
	art.modulate.a = 0.0
	var shine := ShaderMaterial.new()
	shine.shader = preload("res://shaders/shine.gdshader")
	shine.set_shader_parameter("shine", Color(1.0, 0.93, 0.72) if _won else Color(1.0, 0.3, 0.25))
	shine.set_shader_parameter("strength", 0.9 if _won else 0.5)
	art.material = shine
	add_child(art)
	if art.texture == null:
		var l := UI.label("VICTORY" if _won else "DEFEAT", 160, UI.GOLD if _won else UI.RED, true)
		l.size = ART_SIZE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art.add_child(l)
	# The two buttons, under the title (the artwork leaves room for them)
	var again := "turf_defense" if d.get("coop", false) else "ffa_lobby" if d.get("ffa", false) else "fight_mode"
	_result_button(Vector2(645, 488), "FIGHT AGAIN" if d.get("coop", false) else "BRAWL AGAIN", UI.RED, func(): Game.go(again))
	_result_button(Vector2(975, 488), "MENU", UI.BLUE, func(): Game.go("main_menu"))
	# Turf Defense's first clear of Street: the boss's prize card, where the MVP usually goes
	var prize := str(d.get("rewards", {}).get("prize", "")) if d.get("rewards") is Dictionary and d.rewards.get("prize") is String else ""
	var side_panel: Control = _prize_panel(prize) if prize != "" else _mvp_panel(d.get("mvp", {}) if d.get("mvp") is Dictionary else {})
	var panels: Array[Control] = [_stats_strip(d, _won), _progress_panel(_won), side_panel]
	_show_mastery(d.get("mastery"))
	_submit(d)
	if d.get("online", false) and not str(d.get("mode", "")).begins_with("cpu") and str(d.get("mode", "")) != "" and not d.get("ffa", false) and not d.get("coop", false):
		_rematch_box()
	_build_fx()
	_reveal(art, shine, rays, panels)


# ── The reveal ───────────────────────────────────────────────────────────────
# Victory: the title rushes in from huge and slams down — flash, shockwave, gold sparks, turning
# rays, confetti and rising embers, with light gleaming across the lettering.
# Defeat: the title drops in and lands with a heavy thud — red flash, the board drains of colour,
# the sign flickers like a dying neon and settles crooked, ash drifts down and the edges pulse
# red like a heartbeat.

func _reveal(art: Control, shine: ShaderMaterial, rays: Node2D, panels: Array[Control]) -> void:
	Sfx.play("riser", 1.35 if _won else 0.75, -8.0)
	var t := create_tween().set_parallel()
	if _won:
		art.scale = Vector2.ONE * 2.8
		t.tween_property(art, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_property(art, "modulate:a", 1.0, 0.16)
	else:
		art.position.y = ART_POS.y - 760.0
		art.rotation = deg_to_rad(-9.0)
		t.tween_property(art, "position:y", ART_POS.y, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(art, "rotation", deg_to_rad(-2.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(art, "modulate:a", 1.0, 0.2)
	t.chain().tween_callback(_impact.bind(art, shine, rays))
	# The panels rise into place one after the other as the dust settles
	for i in panels.size():
		var p := panels[i]
		var to := p.position
		p.position.y += 460.0
		p.modulate.a = 0.0
		var pt := p.create_tween().set_parallel()
		pt.tween_property(p, "position:y", to.y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.5 + i * 0.12)
		pt.tween_property(p, "modulate:a", 1.0, 0.3).set_delay(0.5 + i * 0.12)
		pt.chain().tween_callback(func(): Sfx.play("set", 1.1 + i * 0.1, -6.0))


func _impact(art: Control, shine: ShaderMaterial, rays: Node2D) -> void:
	var at := art.position + art.pivot_offset
	Game.sound.sting("victory" if _won else "defeat", "menu")   # (then the menu music comes in)
	Sfx.play("slam", 0.9 if _won else 0.6)
	Sfx.play("boom", 1.0 if _won else 0.65, -2.0)
	_shake = 24.0 if _won else 34.0
	_flash(Color(1.0, 0.95, 0.8, 0.7) if _won else Color(0.75, 0.0, 0.05, 0.5))
	_shockwave(at)
	_grade(0.35 if _won else 0.12, 0.5 if _won else 0.32)
	if _won:
		_burst(at, GOLD_LIGHT, 150, 1300.0, 1.1)
		_burst(at, Color.WHITE, 60, 800.0, 0.6)
		if rays:
			rays.create_tween().tween_property(rays, "modulate:a", 1.0, 0.5)
		_confetti()
		_embers(GOLD_LIGHT, 70)
		_sweeps(shine, 0.85, 2.4)
		var bob := art.create_tween().set_loops()
		bob.tween_property(art, "position:y", ART_POS.y - 10, 1.8).set_trans(Tween.TRANS_SINE).set_delay(0.3)
		bob.tween_property(art, "position:y", ART_POS.y, 1.8).set_trans(Tween.TRANS_SINE)
	else:
		_burst(at + Vector2(0, 160), Color(0.5, 0.45, 0.45), 80, 600.0, 1.2, 900.0)
		# The sign swings on its hinge and flickers like a failing neon
		var swing := art.create_tween()
		swing.tween_property(art, "rotation", deg_to_rad(1.6), 0.22).set_trans(Tween.TRANS_SINE)
		swing.tween_property(art, "rotation", deg_to_rad(-1.0), 0.3).set_trans(Tween.TRANS_SINE)
		swing.tween_property(art, "rotation", deg_to_rad(-1.6), 0.4).set_trans(Tween.TRANS_SINE)
		var flicker := art.create_tween().set_loops()
		for a in [0.25, 1.0, 0.5, 1.0, 0.8, 1.0]:
			flicker.tween_property(art, "modulate:a", a, 0.05)
		flicker.tween_interval(2.5)
		_ash()
		_embers(Color(1.0, 0.25, 0.15), 22)
		_sweeps(shine, 1.6, 3.5)
		_heartbeat()


# ── Effects ──────────────────────────────────────────────────────────────────

## The board as the match ended (or the duel background), blurred, drained and graded,
## slowly pushing in; a vignette and a wash of the result's colour on top.
func _build_backdrop(snap) -> void:
	var tex: Texture2D = snap if snap is Texture2D else UI.tex("duel_background.png")
	var bg := UI.texture_rect(tex, Vector2(2000, 1125), true)
	bg.position = Vector2(-40, -22)
	bg.pivot_offset = bg.size / 2
	_backdrop = ShaderMaterial.new()
	_backdrop.shader = preload("res://shaders/backdrop.gdshader")
	_backdrop.set_shader_parameter("blur", 0.0)
	_backdrop.set_shader_parameter("saturation", 1.0)
	_backdrop.set_shader_parameter("brightness", 0.55)
	_backdrop.set_shader_parameter("grade", Color(1.08, 0.97, 0.82) if _won else Color(1.0, 0.72, 0.76))
	bg.material = _backdrop
	add_child(bg)
	bg.create_tween().tween_property(bg, "scale", Vector2.ONE * 1.06, 14.0).set_trans(Tween.TRANS_SINE)
	var wg := GradientTexture2D.new()
	wg.fill_from = Vector2(0.5, 1.0)
	wg.fill_to = Vector2(0.5, 0.0)
	wg.gradient = _gradient([Color(GOLD_LIGHT, 0.2) if _won else Color(BLOOD, 0.3), Color(0, 0, 0, 0)])
	add_child(_overlay(wg))
	var vg := GradientTexture2D.new()
	vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.45)
	vg.fill_to = Vector2(1.05, 1.05)
	vg.gradient = _gradient([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.92)], [0.0, 0.45, 1.0])
	add_child(_overlay(vg))


func _overlay(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2(1920, 1080)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Blur and drain the backdrop as the result lands.
func _grade(saturation: float, brightness: float) -> void:
	var t := create_tween().set_parallel()
	t.tween_method(func(v): _backdrop.set_shader_parameter("blur", v), 0.0, 4.0, 0.5).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): _backdrop.set_shader_parameter("saturation", v), 1.0, saturation, 0.7)
	t.tween_method(func(v): _backdrop.set_shader_parameter("brightness", v), 0.55, brightness, 0.7)


## A full-screen layer over everything that bends what's behind it (shaders/post.gdshader).
func _build_fx() -> void:
	var r := ColorRect.new()
	r.size = Vector2(1920, 1080)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx = ShaderMaterial.new()
	_fx.shader = preload("res://shaders/post.gdshader")
	_fx.set_shader_parameter("impact_tint", Color(1.0, 0.9, 0.6) if _won else Color(1.0, 0.35, 0.35))
	r.material = _fx
	add_child(r)


func _shockwave(at: Vector2) -> void:
	_fx.set_shader_parameter("wave_center", at / Vector2(1920, 1080))
	var t := create_tween().set_parallel()
	t.tween_method(func(v): _fx.set_shader_parameter("wave_radius", v), 0.0, 1.5, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): _fx.set_shader_parameter("wave_strength", v), 1.3, 0.0, 0.9)
	t.tween_method(func(v): _fx.set_shader_parameter("aberration", v), 16.0, 0.0, 0.5).set_ease(Tween.EASE_OUT)
	# Two frames of stark impact-frame ink, then back
	var i := create_tween()
	i.tween_callback(func(): _fx.set_shader_parameter("impact", 1.0))
	i.tween_interval(0.07)
	i.tween_callback(func(): _fx.set_shader_parameter("impact", 0.0))


## Defeat: the screen's edges throb red, lub-dub, and fade between beats.
func _heartbeat() -> void:
	var set_danger := func(v): _fx.set_shader_parameter("danger", v)
	var t := create_tween().set_loops()
	t.tween_method(set_danger, 0.0, 0.42, 0.1)
	t.tween_method(set_danger, 0.42, 0.12, 0.16)
	t.tween_method(set_danger, 0.12, 0.32, 0.1)
	t.tween_method(set_danger, 0.32, 0.0, 0.7)
	t.tween_interval(0.7)


func _flash(c: Color) -> void:
	var f := ColorRect.new()
	f.color = c
	f.size = Vector2(1920, 1080)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(f)
	var t := f.create_tween()
	t.tween_property(f, "color:a", 0.0, 0.28).set_ease(Tween.EASE_OUT)
	t.tween_callback(f.queue_free)


## Light gleaming across the title now and then.
func _sweeps(shine: ShaderMaterial, secs: float, gap: float) -> void:
	var t := create_tween().set_loops()
	t.tween_interval(0.2)
	t.tween_method(func(v): shine.set_shader_parameter("progress", v), -0.3, 1.3, secs).set_trans(Tween.TRANS_SINE)
	t.tween_interval(gap)


func _burst(at: Vector2, color: Color, amount: int, speed: float, life: float, gravity := 500.0) -> void:
	var p := _particles(amount, life, _dot, _add)
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 60.0
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 60.0
	p.damping_max = 200.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.45
	p.color_ramp = _gradient([color, Color(color, 0.0)])
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


## Victory: gold and white confetti tumbling down from the top.
func _confetti() -> void:
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var p := _particles(160, 6.0, ImageTexture.create_from_image(img), null)
	p.position = Vector2(960, -40)
	p.one_shot = true
	p.explosiveness = 0.75
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1000, 10)
	p.direction = Vector2.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0, 170)
	p.damping_min = 20.0
	p.damping_max = 50.0
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_initial_ramp = _gradient([Color("ffd86b"), Color.WHITE, Color("f0a500"), Color("fff1b8")])
	p.color_ramp = _gradient([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)], [0.0, 0.8, 1.0])
	p.emitting = true


## Glowing embers drifting up from the bottom of the screen.
func _embers(color: Color, amount: int) -> void:
	var p := _particles(amount, 7.0, _dot, _add)
	p.position = Vector2(960, 1110)
	p.preprocess = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1000, 10)
	p.direction = Vector2.UP
	p.spread = 25.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(0, -12)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.26
	p.hue_variation_min = -0.03
	p.hue_variation_max = 0.03
	p.color_ramp = _gradient([Color(color, 0.0), Color(color, 0.95), Color(color.darkened(0.3), 0.0)], [0.0, 0.15, 1.0])
	p.emitting = true


## Defeat: grey ash drifting down.
func _ash() -> void:
	var p := _particles(70, 12.0, _dot, null)
	p.position = Vector2(960, -30)
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1100, 10)
	p.direction = Vector2.DOWN
	p.spread = 35.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2(14, 22)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	p.color_ramp = _gradient([Color(0.7, 0.68, 0.68, 0.0), Color(0.7, 0.68, 0.68, 0.7), Color(0.4, 0.38, 0.38, 0.0)], [0.0, 0.1, 1.0])
	p.emitting = true


func _particles(amount: int, life: float, tex: Texture2D, mat: Material) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.texture = tex
	if mat:
		p.material = mat
	add_child(p)
	return p


func _soft_dot() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 64
	g.height = 64
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = _gradient([Color.WHITE, Color(1, 1, 1, 0)])
	return g


static func _gradient(colors: Array, offsets: Array = []) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	if offsets.is_empty():
		for i in colors.size():
			offsets.append(float(i) / maxf(1.0, colors.size() - 1.0))
	g.offsets = PackedFloat32Array(offsets)
	return g


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		Game.go("main_menu")


# ── Rematch ──────────────────────────────────────────────────────────────────

func _rematch_box() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(700, 790)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_rematch = UI.button("⚔ REMATCH", _ask_rematch, Vector2(520, 72), UI.GOLD)
	col.add_child(_rematch)
	_rematch_note = UI.label("Offer your opponent another match (60 s).", 20, UI.MUTED)
	_rematch_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_rematch_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rematch_note.custom_minimum_size = Vector2(520, 0)
	col.add_child(_rematch_note)
	get_tree().create_timer(60.0).timeout.connect(func():
		if is_instance_valid(_rematch) and not _rematch_done:
			_rematch_end("The rematch offer has expired."))
	tree_exiting.connect(func():
		if not _rematch_done:
			Net.send("mp:rematch_decline"))


func _process(delta: float) -> void:
	# Camera shake from the result landing
	if _shake > 0.2:
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 8.0))
	elif position != Vector2.ZERO:
		_shake = 0.0
		position = Vector2.ZERO
	while _rematch and not Net.rematch_inbox.is_empty():
		var m: Array = Net.rematch_inbox.pop_front()
		_on_net(m[0], m[1])
	if _rematch and not _rematch_done and not Net.rps_inbox.is_empty():
		_rematch_done = true   # it's on (net.gd opens Scissors Paper Rock)


func _ask_rematch() -> void:
	if not Net.send("mp:rematch"):
		UI.toast(self, "Not connected to the server.", UI.RED)
		return
	_rematch.disabled = true
	_rematch.text = "WAITING FOR OPPONENT…"


func _on_net(name: String, data) -> void:
	match name:
		"mp:rematch_offer":
			Game.alert()
			Sfx.play("ambush", 1.2)
			_rematch.disabled = false
			_rematch.text = "✓ ACCEPT REMATCH"
			_rematch_note.text = "%s wants a rematch!" % str(data.get("fromUsername", "Your opponent"))
			_rematch_note.label_settings.font_color = UI.GOLD
		"mp:rematch_sent":
			_rematch_note.text = "Asked. It starts as soon as they agree."
		"mp:rematch_declined":
			_rematch_end(str(data.get("message", "No rematch.")))


func _rematch_end(message: String) -> void:
	_rematch_done = true
	_rematch.disabled = true
	_rematch.text = "NO REMATCH"
	_rematch_note.text = message
	_rematch_note.label_settings.font_color = UI.RED


## A big comic-style button under the title, fading in once the title has landed.
func _result_button(at: Vector2, text: String, accent: Color, cb: Callable) -> void:
	var b := UI.button(text, cb, Vector2(300, 70), accent)
	b.position = at
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 32)
	b.modulate.a = 0.0
	add_child(b)
	var t := b.create_tween()
	t.tween_interval(1.1)
	t.tween_property(b, "modulate:a", 1.0, 0.35)


## The result in numbers, under the title: why it ended, and Morale and turns counting up.
func _stats_strip(d: Dictionary, won: bool) -> Control:
	var v := VBoxContainer.new()
	v.position = Vector2(660, 598)
	v.custom_minimum_size = Vector2(600, 0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var reason := "Opponent's Morale reduced to 0" if won else "Your Morale reduced to 0"
	match str(d.get("reason", "")):
		"concede":
			reason = "Your opponent conceded" if won else "You conceded"
		"disconnect":
			reason = "Your opponent left the match" if won else "You were disconnected"
		"deck_out":
			reason = "Your opponent ran out of cards" if won else "You ran out of cards"
		"afk":
			reason = "Your opponent stopped playing" if won else "You were away too long"
	var ffa: bool = d.get("ffa", false)
	if ffa:   # a free-for-all: where you finished, and the table in order
		var players: Dictionary = d.get("players", {}) if d.get("players") is Dictionary else {}
		reason = "You finished %s of %d" % [_place_text(int(d.get("place", 0))), maxi(players.size(), 3)]
	var coop: bool = d.get("coop", false)
	if coop:   # Turf Defense: you and your ally, against the boss
		var boss: Dictionary = d.get("boss", {}) if d.get("boss") is Dictionary else {}
		var ally := str(d.get("players", {}).get("ally", {}).get("username", "your ally")) if d.get("players") is Dictionary and d.players.get("ally") is Dictionary else "your ally"
		var bname := str(boss.get("short", boss.get("name", "the boss")))
		reason = ("You and %s beat %s on %s" if won else "%s… %s beat you both on %s") % ([ally, bname, str(boss.get("level_name", ""))] if won else ["So close", bname, str(boss.get("level_name", ""))])
		if not won and str(d.get("reason", "")) in ["concede", "disconnect", "afk"]:
			reason = "The crew went down against %s" % bname
	var r := UI.label(reason, 26, Color.WHITE, true)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(r)
	if ffa:
		v.add_child(_placings(d))
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 60)
	v.add_child(stats)
	var rows := [["YOUR MORALE", d.get("player_morale", "—"), UI.BLUE if won else UI.RED],
			["OPP MORALE", d.get("opponent_morale", "—"), UI.RED if won else UI.BLUE],
			["TURNS", d.get("turns", "—"), Color.WHITE]]
	if ffa:
		rows = [["PLACE", _place_text(int(d.get("place", 0))), UI.GOLD if won else UI.RED], ["TURNS", d.get("turns", "—"), Color.WHITE]]
	if coop:
		var boss_col := Color(str(d.get("boss", {}).get("color", "#e63946"))) if d.get("boss") is Dictionary else UI.RED
		rows = [["YOUR MORALE", d.get("player_morale", "—"), UI.BLUE if won else UI.RED],
			["BOSS MORALE", d.get("opponent_morale", "—"), boss_col], ["TURNS", d.get("turns", "—"), Color.WHITE]]
	for s in rows:
		var c := VBoxContainer.new()
		var cap := UI.label(s[0], 16, UI.MUTED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(cap)
		var val := UI.label(str(s[1]), 40, s[2], true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(val)
		if s[1] is int or s[1] is float:
			_count(val, int(s[1]), "%d", 0.7, 0.35)
		stats.add_child(c)
	return v


## Turf Defense: the boss's prize card, won on the first clear of Street. It rises out of the dark
## on a burst of light in its rarity's colour, flips over, and lands in your collection.
func _prize_panel(id: String) -> Control:
	var card: Dictionary = CardDB.get_card(id).duplicate()
	card.id = id
	var rarity := int(card.get("rarity", 1))
	var col := UI.rarity_color(rarity)
	var p := UI.panel(col)
	p.position = Vector2(1280, PANEL_Y)
	p.custom_minimum_size = Vector2(600, 440)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var h := UI.label("★  PRIZE CARD  ★", 24, col.lightened(0.3), true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(250, 362)
	row.add_child(stage)
	var rays := _spin_rays(Vector2(125, 181), 280.0, col.lightened(0.25), 18)
	stage.add_child(rays)
	var back := UI.texture_rect(CardDB.back(str(card.get("clanTag", ""))), Vector2(236, 334))
	back.position = Vector2(7, 14)
	back.stretch_mode = TextureRect.STRETCH_SCALE
	stage.add_child(back)
	var tile := CardTile.make(card, Vector2(236, 334))
	tile.position = Vector2(7, 14)
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
	stage.add_child(tile)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UI.label("NEW CARD", 18, UI.GREEN, true))
	var n := UI.label(str(card.get("name", "?")).to_upper(), 30, Color("ffd86b"), true)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD
	n.custom_minimum_size = Vector2(270, 0)
	info.add_child(n)
	info.add_child(UI.label(str(UI.RARITY_LABEL.get(rarity, "")).to_upper(), 18, col, true))
	info.add_child(_gap_box(10))
	var note := UI.label("Added to your collection%s.\nOnly bosses drop it." % (",\nwith every level it promotes to" if card.get("promotesTo") is String else ""), 17, UI.MUTED)
	info.add_child(note)
	# Face down first; it shakes, flips over in a flash, and the light behind it comes up
	tile.modulate.a = 0.0
	rays.modulate.a = 0.0
	back.pivot_offset = back.size / 2
	var t := create_tween()
	t.tween_interval(0.9 + INTRO)
	for i in 6:
		t.tween_property(back, "rotation_degrees", 3.0 if i % 2 == 0 else -3.0, 0.06)
	t.tween_callback(func():
		Sfx.play("riser", 0.9, -4.0)
		back.rotation_degrees = 0.0)
	t.tween_property(back, "scale", Vector2(0.0, 1.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		back.visible = false
		tile.pivot_offset = tile.size / 2
		tile.scale = Vector2(0.0, 1.0)
		tile.modulate.a = 1.0
		_flash(Color(col, 0.6))
		Sfx.play("pack_open", 1.0, -2.0))
	t.tween_property(tile, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		Sfx.play("promote", 1.2, -6.0)
		_burst(tile.get_global_rect().get_center(), col.lightened(0.4), 110, 900.0, 1.1, 250.0)
		_shake_screen(10.0)
		rays.create_tween().tween_property(rays, "modulate:a", 1.0, 0.6))
	return p


## Your level and clan mastery, each with its emblem and a bar that fills with this match's XP,
## then what the match paid.
func _progress_panel(won: bool) -> Control:
	var p := UI.panel(UI.GOLD if won else UI.RED)
	p.position = Vector2(40, PANEL_Y)
	p.custom_minimum_size = Vector2(600, 440)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var h := UI.label("YOUR PROGRESS", 22, UI.GOLD if won else UI.RED, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var lvl := int(Game.player.get("level", 1))
	var row := _track_row(UI.level_icon(lvl), "LEVEL %d" % lvl, UI.BLUE)
	_level_icon = row.icon
	_level_text = row.title
	_xp_fill = row.fill
	_xp_label = row.gain
	_xp_numbers = row.numbers
	var now := UI.xp_progress(Game.player)
	_xp_fill.size.x = (BAR_W - 4.0) * now.pct
	_xp_numbers.text = "%d / %d XP" % [now.current, now.needed]
	v.add_child(row.root)
	_mastery_box = VBoxContainer.new()
	v.add_child(_mastery_box)
	v.add_child(HSeparator.new())
	_rewards = UI.label("", 22, UI.GOLD, true)
	_rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rewards.autowrap_mode = TextServer.AUTOWRAP_WORD
	_rewards.custom_minimum_size = Vector2(560, 0)
	v.add_child(_rewards)
	return p


## A progress line: an emblem, the title and "+N XP", a rounded bar, and the numbers under it.
func _track_row(icon_tex: Texture2D, title: String, col: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var icon := UI.texture_rect(icon_tex, Vector2(92, 92))
	icon.pivot_offset = Vector2(46, 46)
	row.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := UI.label(title, 24, col, true)
	t.custom_minimum_size = Vector2(BAR_W - 130.0, 0)
	top.add_child(t)
	var gain := UI.label("", 22, Color.WHITE, true)
	gain.custom_minimum_size = Vector2(130, 0)
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(gain)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(BAR_W, 16)
	track.add_theme_stylebox_override("panel", UI.box(Color("10102a"), Color(col, 0.4), 1, 8))
	v.add_child(track)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", UI.box(col, col, 0, 6))
	fill.position = Vector2(2, 2)
	fill.size = Vector2(0, 12)
	fill.clip_contents = true
	track.add_child(fill)
	var sheen := ColorRect.new()   # light running along the bar now and then
	sheen.color = Color(1, 1, 1, 0.45)
	sheen.size = Vector2(26, 12)
	sheen.position.x = -40.0
	fill.add_child(sheen)
	var run := sheen.create_tween().set_loops()
	run.tween_interval(randf_range(2.0, 3.0))
	run.tween_property(sheen, "position:x", BAR_W, 0.9).from(-40.0).set_trans(Tween.TRANS_SINE)
	var numbers := UI.label("", 16, UI.MUTED)
	v.add_child(numbers)
	return {"root": row, "icon": icon, "title": t, "gain": gain, "fill": fill, "numbers": numbers}


## A bar filling from one point to another, rolling over with a flash at each level gained.
func _fill_bar(fill: Control, from_pct: float, to_pct: float, levels: int, delay: float, on_level: Callable) -> void:
	var w := BAR_W - 4.0
	fill.size.x = w * from_pct
	var t := create_tween()
	t.tween_interval(delay)
	for i in levels:
		t.tween_property(fill, "size:x", w, 0.45).set_trans(Tween.TRANS_QUAD)
		t.tween_callback(func():
			on_level.call(i)
			fill.modulate = Color(2.5, 2.5, 2.5)
			fill.create_tween().tween_property(fill, "modulate", Color.WHITE, 0.45)
			fill.size.x = 0.0)
	t.tween_property(fill, "size:x", w * to_pct, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A level reached: the emblem pops and changes, and "LEVEL UP!" rises off the title.
func _level_reached(icon: TextureRect, title: Label, tex: Texture2D, text: String, col: Color, tag: String) -> void:
	Sfx.play("level_up")
	title.text = text
	if tex:
		icon.texture = tex
	icon.scale = Vector2.ONE * 1.45
	icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_burst(icon.get_global_rect().get_center(), col, 50, 500.0, 0.8, 200.0)
	var l := UI.label(tag, 26, col, true)
	l.position = title.get_global_rect().position + Vector2(title.get_minimum_size().x + 14, -4)
	add_child(l)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y - 46, 1.6).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(1.0)
	t.chain().tween_callback(l.queue_free)


## Clan mastery after the match (sent with the result): the clan's emblem and its bar in the
## clan's colour, filling with this match's XP.
func _show_mastery(m) -> void:
	if not (m is Dictionary) or not (m.get("levels") is Array):
		return
	var levels: Array = m.levels
	var xp := int(m.get("xp", 0))
	var gained := int(m.get("gained", 0))
	var level_of := func(x: int) -> int: return levels.filter(func(t): return x >= int(t)).size()
	var pct_at := func(x: int, lv: int) -> float:
		if lv >= levels.size():
			return 1.0
		return clampf(float(x - int(levels[lv - 1])) / maxf(1.0, int(levels[lv]) - int(levels[lv - 1])), 0.0, 1.0)
	var before: int = level_of.call(xp - gained)
	var after: int = level_of.call(xp)
	var col := Color(str(m.get("color", "#ffffff")))
	var name := str(m.get("name", "")).to_upper()
	var row := _track_row(UI.clan_emblem(str(m.get("clan", ""))), "%s MASTERY %d" % [name, before], col)
	_mastery_box.add_child(row.root)
	row.numbers.text = "MAX LEVEL" if after >= levels.size() else "%d / %d XP" % [xp, int(levels[after])]
	_count(row.gain, gained, "+%d XP", 0.8, 0.9)
	_fill_bar(row.fill, pct_at.call(xp - gained, before), pct_at.call(xp, after), after - before, 0.9 + INTRO, func(i):
		_level_reached(row.icon, row.title, null, "%s MASTERY %d" % [name, before + i + 1], col, "LEVEL UP!"))


static func _place_text(place: int) -> String:
	return {1: "1ST", 2: "2ND", 3: "3RD"}.get(place, "%dTH" % place)


## FFA: everyone's place, best first (you in blue).
func _placings(d: Dictionary) -> Control:
	var places: Dictionary = d.get("places", {}) if d.get("places") is Dictionary else {}
	var players: Dictionary = d.get("players", {}) if d.get("players") is Dictionary else {}
	var order: Array = places.keys()
	order.sort_custom(func(a, b): return int(places[a]) < int(places[b]))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	for side in order:
		var name := str(players.get(side, {}).get("username", side)) if players.get(side) is Dictionary else str(side)
		var l := UI.label("%s %s" % [_place_text(int(places[side])), name.to_upper().left(10)], 18,
			UI.BLUE if side == "player" else UI.GOLD if int(places[side]) == 1 else UI.MUTED, true)
		row.add_child(l)
	return row


## The MVP: the card that did the most (Morale dealt, KOs), flipping in on a turning burst of light
## in its rarity's colour, with what it did counting up beside it.
func _mvp_panel(mvp: Dictionary) -> Control:
	var p := UI.panel(UI.GOLD)
	p.position = Vector2(1280, PANEL_Y)
	p.custom_minimum_size = Vector2(600, 440)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var h := UI.label("★  MVP  ★", 24, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	if mvp.is_empty() or not (mvp.get("card") is Dictionary):
		var none := UI.label("No Morale dealt this match", 22, UI.MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(none)
		return p
	var card: Dictionary = mvp.card
	var rarity := int(card.get("rarity", 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(250, 362)
	row.add_child(stage)
	var rays := _spin_rays(Vector2(125, 181), 240.0, UI.rarity_color(rarity).lightened(0.25), 14)
	stage.add_child(rays)
	var tile := CardTile.make(card, Vector2(236, 334))
	tile.position = Vector2(7, 14)
	tile.zoomed.connect(func(t): UI.card_zoom(self, t.card))
	tile.pressed.connect(func(t): UI.card_zoom(self, t.card))
	stage.add_child(tile)
	var ribbon := UI.label(" MVP ", 22, Color("1a1200"), true)
	ribbon.add_theme_stylebox_override("normal", UI.box(UI.GOLD, Color.WHITE, 2, 6))
	ribbon.position = Vector2(-6, 0)
	ribbon.rotation = deg_to_rad(-12)
	stage.add_child(ribbon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var mine: bool = mvp.get("owner") == "player"
	info.add_child(UI.label("YOUR CARD" if mine else "THEIR CARD", 18, UI.BLUE if mine else UI.RED, true))
	var n := UI.label(str(card.get("name", "?")).to_upper(), 30, Color("ffd86b"), true)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD
	n.custom_minimum_size = Vector2(270, 0)
	info.add_child(n)
	info.add_child(UI.label(str(UI.RARITY_LABEL.get(rarity, "")).to_upper(), 16, UI.rarity_color(rarity), true))
	info.add_child(_gap_box(10))
	var dmg := UI.label("0", 58, Color.WHITE, true)
	info.add_child(dmg)
	_count(dmg, int(mvp.get("damage", 0)), "%d", 0.9, 0.9)
	info.add_child(UI.label("MORALE DEALT", 16, UI.MUTED, true))
	var kos := int(mvp.get("kos", 0))
	if kos > 0:
		info.add_child(_gap_box(6))
		var k := UI.label("0", 40, UI.RED, true)
		info.add_child(k)
		_count(k, kos, "%d", 0.5, 1.4)
		info.add_child(UI.label("KO%s" % ("" if kos == 1 else "S"), 16, UI.MUTED, true))
	# The card flips in once the panel has landed, and the light behind it comes up
	tile.modulate.a = 0.0
	rays.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.75 + INTRO)
	t.tween_callback(func():
		tile.pivot_offset = tile.size / 2
		tile.scale = Vector2(0.0, 1.0)
		tile.modulate.a = 1.0
		Sfx.play("flip", 0.9, -4.0))
	t.tween_property(tile, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		Sfx.play("promote", 1.3, -8.0)
		_burst(tile.get_global_rect().get_center(), UI.rarity_color(rarity).lightened(0.4), 70, 700.0, 0.9, 250.0)
		rays.create_tween().tween_property(rays, "modulate:a", 1.0, 0.6))
	return p


func _gap_box(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Slowly turning rays of light around a point (the MVP card's burst).
func _spin_rays(center: Vector2, reach: float, col: Color, count: int) -> Node2D:
	var rays := Node2D.new()
	rays.position = center
	rays.material = _add
	rays.draw.connect(func():
		for i in count:
			var a := i * TAU / count
			var w := 0.11 if i % 2 == 0 else 0.06
			rays.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * reach, Vector2.from_angle(a + w) * reach]),
				PackedColorArray([Color(col, 0.42), Color(col, 0.0), Color(col, 0.0)])))
	var spin := rays.create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 24.0).from(0.0)
	return rays


## Rewards are decided by the server (solo-match session from match/start).
func _submit(d: Dictionary) -> void:
	if d.get("tutorial", false):
		_rewards.text = "TUTORIAL COMPLETE
" + ("You know the basics. See you in the alley!" if d.get("result") == "win" else "Replay it any time from Fight → Tutorial.")
		return
	if d.get("online", false):
		# Online matches are recorded by the server, which sends the rewards with the result
		if d.get("rewards") is Dictionary:
			_show_rewards(d.rewards)
		else:
			_xp_label.text = "+0 XP"
			_rewards.text = "Rewards not recorded"
		return
	if Game.offline or str(d.get("match_id", "")) == "":
		_xp_label.text = "+0 XP"
		_rewards.text = "Offline — rewards not recorded" if Game.offline else "Rewards not recorded"
		return
	var r := await Api.request("POST", "/api/match/complete", {
		"matchId": d.match_id, "result": d.result, "cardsPlayed": d.get("cards_played", 0),
		"playerMorale": d.get("player_morale", 0), "opponentMorale": d.get("opponent_morale", 0),
		"turns": d.get("turns", 0),
	})
	if not r.ok or not (r.data is Dictionary) or not r.data.has("rewards"):
		_xp_label.text = "+0 XP"
		_rewards.text = r.error if r.error != "" else "Rewards not recorded"
		return
	_show_rewards(r.data.rewards)


func _show_rewards(rw: Dictionary) -> void:
	var new_level := int(rw.get("newLevel", Game.player.get("level", 1)))
	var gained := int(rw.get("xpEarned", 0))
	var old_level := new_level - 1 if rw.get("leveledUp", false) else new_level
	var xp_now := int(rw.get("newXp", int(Game.player.get("xp", 0)) + gained))   # (newXp: the server's total)
	var before := UI.xp_progress({"level": old_level, "xp": xp_now - gained})
	var after := UI.xp_progress({"level": new_level, "xp": xp_now})
	_level_icon.texture = UI.level_icon(old_level)
	_level_text.text = "LEVEL %d" % old_level
	_xp_numbers.text = "%d / %d XP" % [after.current, after.needed]
	_count(_xp_label, gained, "+%d XP", 0.8, 0.4)
	_fill_bar(_xp_fill, before.pct, after.pct, new_level - old_level, 0.4 + INTRO, func(_i):
		_level_reached(_level_icon, _level_text, UI.level_icon(new_level), "LEVEL %d" % new_level, UI.BLUE, "LEVEL UP!"))
	var lines := ["+%d Karat" % int(rw.get("karatEarned", 0))]
	if rw.has("bossId"):   # Turf Defense (backend/economy/turf.js)
		if rw.get("first", false):
			lines.push_front("★ FIRST CLEAR! ★")
		if int(rw.get("packs", 0)) > 0:
			var n := int(rw.packs)
			lines.append("🎁 %d free pack%s for the first clear" % [n, "" if n == 1 else "s"])
			Game.player.free_packs = int(Game.player.get("free_packs", 0)) + n
			_free_pack_button()
		if rw.get("unlockedNext", false):
			lines.append("🔓 The next level is open")
	var rp := int(rw.get("rankPointDelta", 0))
	if rp != 0:   # (ranked matches)
		lines.append("%+d Rank Points" % rp)
	if rw.get("dailyCapReached", false):
		lines.append("Daily reward limit reached")
	if rw.get("firstWinBonus", false):
		lines.append("★ First Win Bonus!")
	# Level rewards (backend economy/postMatch.js): a free pack per level, a picture every 5 levels
	var pics: Array = rw.get("avatarsUnlocked", [])
	if not pics.is_empty():
		lines.append("New profile picture unlocked!")
		_new_avatar(str(pics[-1]))
	var packs := int(rw.get("packsEarned", 0))
	if packs > 0:
		lines.append("🎁 %d free pack%s: pick %s in the Shop" % [packs, "" if packs == 1 else "s", "it" if packs == 1 else "them"])
		Game.player.free_packs = int(Game.player.get("free_packs", 0)) + packs
		_free_pack_button()
	_rewards.text = "\n".join(lines)
	_rewards.visible_ratio = 0.0
	var reveal := create_tween()
	reveal.tween_interval(1.0 + INTRO)
	reveal.tween_callback(func(): Sfx.play("karat", 1.0, -2.0))
	reveal.tween_property(_rewards, "visible_ratio", 1.0, 0.5)
	if rw.get("rankChanged", false):
		_rank_up(str(rw.get("newRank", "")))
	# Achievements this match unlocked (sent with the result)
	var got = Game.match_result.get("achievements", [])
	if got is Array and not got.is_empty():
		get_tree().create_timer(2.4 + INTRO).timeout.connect(func(): Net.show_achievements(got))


## Roll a number up to its final value, ticking as it goes.
func _count(l: Label, to: int, fmt: String, secs: float, delay: float) -> void:
	l.text = fmt % 0
	if to == 0:
		return
	var last := [-1]
	var t := create_tween()
	t.tween_interval(delay + INTRO)
	t.tween_method(func(x: float):
		var v := int(round(x))
		l.text = fmt % v
		var step := int(x / maxf(1.0, to / 12.0))
		if step != last[0]:
			last[0] = step
			Sfx.play("click", 1.8 + 0.4 * x / to, -14.0), 0.0, float(to), secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		l.pivot_offset = l.size / 2
		var pop := l.create_tween()
		pop.tween_property(l, "scale", Vector2.ONE * 1.15, 0.08)
		pop.tween_property(l, "scale", Vector2.ONE, 0.15))


## Slowly turning rays of light behind the victory art (hidden until the title lands).
func _rays(center: Vector2) -> Node2D:
	var rays := Node2D.new()
	rays.position = center
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rays.material = m
	rays.draw.connect(func():
		for i in 18:
			var a := i * TAU / 18.0
			var w := 0.06 if i % 2 == 0 else 0.035
			rays.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * 900.0, Vector2.from_angle(a + w) * 900.0]),
				PackedColorArray([Color(1, 0.85, 0.4, 0.28), Color(1, 0.7, 0.2, 0.0), Color(1, 0.7, 0.2, 0.0)])))
	add_child(rays)
	rays.modulate.a = 0.0
	var spin := rays.create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 60.0).from(0.0)
	return rays


const RANK_COLORS := {
	"rookie": Color("9aa7b8"), "street_tough": Color("4ade80"), "enforcer": Color("38bdf8"),
	"underboss": Color("a46bff"), "kingpin": Color("ff3b3b"), "legend": Color("ffd34d"),
}


## A new rank: the screen dims, the rank's badge slams in under light in its colour with RANK UP! over
## it and its name under it; a click (or a few seconds) and it's gone.
func _rank_up(rank: String) -> void:
	await get_tree().create_timer(1.2 + INTRO).timeout
	var col: Color = RANK_COLORS.get(rank, UI.GOLD)
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.z_index = 70
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var veil := ColorRect.new()
	veil.size = layer.size
	veil.color = Color(0, 0, 0, 0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	veil.create_tween().tween_property(veil, "color:a", 0.9, 0.3)   # (dark enough that the rank is all you see)
	var centre := Vector2(960, 470)
	var rays := _spin_rays(centre, 900.0, col, 22)
	layer.add_child(rays)
	rays.modulate.a = 0.4
	var badge := UI.texture_rect(UI.tex("ranks/%s.png" % rank), Vector2(320, 320))
	badge.position = centre - badge.size / 2
	badge.pivot_offset = badge.size / 2
	badge.scale = Vector2.ONE * 3.0
	badge.modulate.a = 0.0
	layer.add_child(badge)
	var head := UI.label("RANK UP!", 64, UI.GOLD, true)
	head.size = Vector2(1920, 80)
	head.position = Vector2(0, centre.y - 260)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(head)
	var name := UI.label(rank.replace("_", " ").to_upper(), 58, col, true)
	name.size = Vector2(1920, 80)
	name.position = Vector2(0, centre.y + 175)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.modulate.a = 0.0
	layer.add_child(name)
	Sfx.play("riser", 1.0, -4.0)
	var t := create_tween()
	t.tween_property(badge, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(badge, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		Sfx.play("boom", 0.9)
		Sfx.play("level_up")
		var flash := ColorRect.new()
		flash.size = layer.size
		flash.color = Color(col.lightened(0.5), 0.7)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(flash)
		flash.create_tween().tween_property(flash, "color:a", 0.0, 0.5)
		_shake_screen(14.0))
	t.tween_property(name, "modulate:a", 1.0, 0.3)
	# A slow float while it's up
	var bob := badge.create_tween().set_loops()
	bob.tween_property(badge, "position:y", badge.position.y - 10, 1.4).set_trans(Tween.TRANS_SINE)
	bob.tween_property(badge, "position:y", badge.position.y, 1.4).set_trans(Tween.TRANS_SINE)
	var gone := [false]
	layer.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: gone[0] = true)
	for i in 70:
		if gone[0] or not is_instance_valid(layer):
			break
		await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(layer):
		return
	var out := layer.create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.35)
	out.tween_callback(layer.queue_free)


## A short shake of the whole screen.
func _shake_screen(amount: float) -> void:
	var base := position
	var s := create_tween()
	for i in 6:
		s.tween_property(self, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * (1.0 - i / 6.0), 0.04)
	s.tween_property(self, "position", base, 0.05)


## A free pack to claim: straight to the shop.
func _free_pack_button() -> void:
	var box := CenterContainer.new()
	var b := UI.button("🎁  PICK FREE PACK", func(): Game.go("shop"), Vector2(250, 60), UI.GREEN)
	b.modulate.a = 0.0
	box.add_child(b)
	_showcase_row().add_child(box)
	var t := b.create_tween()
	t.tween_interval(1.6 + INTRO)
	t.tween_property(b, "modulate:a", 1.0, 0.3)


## A newly unlocked profile picture, next to the new level's emblem.
func _new_avatar(key: String) -> void:
	var box := CenterContainer.new()
	var pic := UI.texture_rect(UI.avatar(key), Vector2(120, 120), true)
	pic.pivot_offset = Vector2(60, 60)
	pic.scale = Vector2.ZERO
	box.add_child(pic)
	_showcase_row().add_child(box)
	var t := pic.create_tween()
	t.tween_interval(1.4 + INTRO)
	t.tween_callback(func(): Sfx.play("promote", 1.3, -4.0))
	t.tween_property(pic, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The row under the title where a level-up shows off what it earned.
func _showcase_row() -> HBoxContainer:
	if _showcase == null:
		_showcase = HBoxContainer.new()
		_showcase.alignment = BoxContainer.ALIGNMENT_CENTER
		_showcase.add_theme_constant_override("separation", 28)
		_showcase.position = Vector2(660, 900)
		_showcase.size = Vector2(600, 150)
		add_child(_showcase)
	return _showcase
