class_name CardView
extends Node2D
## One card on screen: art or card back, a glow outline, and an ATK/DEF badge on the field.
## Holds no rules state; the duel screen updates it from event snapshots.
## The art is drawn with shaders/card.gdshader, so the card has real 3D tilt: it leans toward
## the mouse when hovered, into its motion when it flies, recoils when hit, and flips in 3D.

const SIZE := Vector2(124, 175)   # field size; hand and zoom views scale the node
const MAX_TILT := 24.0            # degrees
static var _shader: Shader = preload("res://shaders/card.gdshader")
## Keyword statuses: colour and the short tag drawn on the card (same colours as the Card Forge)
const STATUS_STYLE := {
	"poison": [Color("6ee26a"), "PSN", "POISONED"], "burn": [Color("ff6a4a"), "BRN", "BURNING"],
	"bleed": [Color("ff4a6e"), "BLD", "BLEEDING"], "shock": [Color("4fc3ff"), "SHK", "SHOCKED"],
	"freeze": [Color("a6ecff"), "FRZ", "FROZEN"], "stasis": [Color("9a7bff"), "STS", "STASIS"],
	"stun": [Color("ffa040"), "STN", "STUNNED"], "shield": [Color("ffd75a"), "SHD", "SHIELDED"],
}

var card: Dictionary = {}
var uid := -1
var side := "player"
var face_up := false
var downed := false: set = set_downed
var show_badge := false: set = set_show_badge
var glow := 0.0: set = set_glow
var badge_text := "": set = set_badge_text   # replaces the ATK/DEF badge (e.g. a leader's Influence)
var statuses: Array = []: set = set_statuses  # keyword statuses, e.g. ["poison", "stasis"]
var glow_color := Color("f4d35e")
var home := Vector2.ZERO
var home_rot := 0.0
var home_scale := 1.0
var busy := false   # flying / animating: ignore hover and layout
var hovered := false            # lean toward the mouse
var rest_tilt := Vector2.ZERO   # resting lean in screen space: (turn, lean back), degrees

var _body := Node2D.new()   # flips (scale.x) independently of the node's own scale
var _status_layer := Node2D.new()   # status tags, drawn over the art
var _front := Sprite2D.new()
var _back := Sprite2D.new()
var _fallback: Label
var _badge: RichTextLabel
var _stats := []
var _tw: Tween
var _mat := ShaderMaterial.new()
var _back_mat: ShaderMaterial = null   # the back's own material when its galaxy turns
var _spin_angle := randf() * TAU        # how far the back's animation has turned
var _spin_speed := 0.09
var _spin_idle := 0.09                  # radians per second at rest...
var _spin_hover := 1.6                  # ...and while a face-down card is hovered (it also glows)
## Speeds per moving back (CardDB.BACK_STYLES): [at rest, hovered]
const BACK_SPEEDS := {"galaxy": [0.09, 1.6], "radar": [1.5, 4.8]}
var _tilt := Vector2.ZERO        # current (y_rot, x_rot) in the card's own frame
var _kick := Vector2.ZERO        # recoil from hits, decays
var _flip_deg := 0.0             # extra turn while flipping over
var _flash := 0.0
var _last_pos := Vector2.INF
var _holo := 0.0                 # hover shimmer on Epic/Legendary cards
var _status_fx := {}             # status -> particle emitter (embers, drips)
var _sparkle: CPUParticles2D     # golden sparkles around a hovered Legendary


func setup(c: Dictionary, owner_side: String, up: bool) -> CardView:
	side = owner_side
	add_child(_body)
	_body.add_child(_back)
	_body.add_child(_front)
	_mat.shader = _shader
	_front.material = _mat
	_back.material = _mat
	_back.texture = CardDB.back()
	_fit(_back)
	add_child(_status_layer)
	_status_layer.draw.connect(_draw_statuses)

	_badge = RichTextLabel.new()
	_badge.top_level = true
	_badge.bbcode_enabled = true
	_badge.scroll_active = false
	_badge.fit_content = true
	_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.custom_minimum_size = Vector2(SIZE.x + 6, 0)
	_badge.size = Vector2(SIZE.x + 6, 26)
	_badge.add_theme_font_size_override("normal_font_size", 17)
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.08, 0.88)
	sb.set_corner_radius_all(5)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_badge.add_theme_stylebox_override("normal", sb)
	_badge.visible = false
	add_child(_badge)

	set_card(c)
	set_face(up)
	return self


## Show a different card back (a clan's own); style = how it moves (CardDB.back_style).
func set_back(tex: Texture2D, style := "") -> void:
	if tex and tex != _back.texture:
		_back.texture = tex
		_fit(_back)
	if BACK_SPEEDS.has(style) and _back_mat == null:
		_back_mat = _mat.duplicate()
		_back_mat.set_shader_parameter(style, 1.0)
		_back_mat.set_shader_parameter("foil", 0.0)
		_back.material = _back_mat
		_spin_idle = BACK_SPEEDS[style][0]
		_spin_hover = BACK_SPEEDS[style][1]
		_spin_speed = _spin_idle


func set_card(c: Dictionary) -> void:
	card = c
	uid = int(c.get("uid", uid))
	var tex: Texture2D = null
	if not c.is_empty():
		tex = CardDB.art(str(c.get("art_url", c.get("id", ""))))
	_front.texture = tex
	_fit(_front)
	if tex == null and not c.is_empty():
		if _fallback == null:
			_fallback = Label.new()
			_fallback.size = SIZE - Vector2(12, 12)
			_fallback.position = -_fallback.size / 2
			_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_fallback.autowrap_mode = TextServer.AUTOWRAP_WORD
			_body.add_child(_fallback)
		_fallback.text = str(c.get("name", "?"))
	set_face(face_up)


func set_face(up: bool) -> void:
	face_up = up
	_front.visible = up and _front.texture != null
	_back.visible = not up
	_mat.set_shader_parameter("foil", 1.0 if up and int(card.get("rarity", 1)) >= 4 else 0.0)
	if _fallback:
		_fallback.visible = up and _front.texture == null
	queue_redraw()


## Turn the card over in 3D (awaitable).
func flip(up: bool, duration := 0.3) -> void:
	if up == face_up:
		return
	Sfx.play("flip", randf_range(0.9, 1.15))
	await _turn_over(set_face.bind(up), duration, Tween.TRANS_SINE)


## Turn the card edge-on, swap what it shows, and turn it back (used by promotion).
func swap_to(c: Dictionary, duration := 0.36) -> void:
	await _turn_over(func():
		set_card(c)
		set_face(true), duration, Tween.TRANS_BACK)


func _turn_over(at_edge: Callable, duration: float, settle: Tween.TransitionType) -> void:
	var t := create_tween()
	t.tween_property(self, "_flip_deg", 90.0, duration * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		at_edge.call()
		_flip_deg = -90.0)
	t.tween_property(self, "_flip_deg", 0.0, duration * 0.55).from(-90.0).set_trans(settle).set_ease(Tween.EASE_OUT)
	await t.finished


## Recoil from a hit travelling in direction `dir` (screen space): the struck edge is pushed away.
func kick(dir: Vector2, degrees := 22.0) -> void:
	var d := dir.normalized().rotated(-rotation)
	_kick += Vector2(d.x, -d.y) * degrees


## Tween to a position/scale/rotation, replacing any move already running (awaitable via .finished).
func move_to(pos: Vector2, s: float, rot: float, duration := 0.22,
		trans := Tween.TRANS_CUBIC, ease_type := Tween.EASE_OUT) -> Tween:
	stop_moving()
	_tw = create_tween().set_parallel().set_trans(trans).set_ease(ease_type)
	_tw.tween_property(self, "position", pos, duration)
	_tw.tween_property(self, "scale", Vector2.ONE * s, duration)
	_tw.tween_property(self, "rotation", rot, duration)
	return _tw


func go_home(duration := 0.22) -> Tween:
	return move_to(home, home_scale, home_rot, duration)


func stop_moving() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()


## A quick white hit-flash over the card.
func flash() -> void:
	_flash = 0.9
	var t := create_tween()
	t.tween_property(self, "_flash", 0.0, 0.3)


func stats() -> Array:
	return _stats


func set_stats(atk: int, def: int, base_atk: int, base_def: int) -> void:
	_stats = [atk, def, base_atk, base_def]
	_update_badge()


func set_downed(v: bool) -> void:
	downed = v
	_body.modulate = Color(1.0, 0.5, 0.5) if v else Color.WHITE
	_update_badge()


func set_show_badge(v: bool) -> void:
	show_badge = v
	_update_badge()


func set_glow(v: float) -> void:
	glow = v
	queue_redraw()


func hit(p_global: Vector2) -> bool:
	return Rect2(-SIZE / 2, SIZE).has_point(to_local(p_global))


func _update_badge() -> void:
	if _badge == null:
		return
	_badge.visible = _badge_wanted()
	if not _badge.visible:
		return
	if badge_text != "":
		_badge.text = badge_text
		return
	var atk_col := _stat_color(_stats[0], _stats[2], "ffd86b")
	var def_col := _stat_color(_stats[1], _stats[3], "9ddcff")
	var tag := "[color=#ff5a5a]DOWNED[/color]  " if downed else ""
	_badge.text = "[center]%s[color=#%s]%d[/color] [color=#777]/[/color] [color=#%s]%d[/color][/center]" \
		% [tag, atk_col, _stats[0], def_col, _stats[1]]


static func _stat_color(v: int, base: int, normal: String) -> String:
	if v > base:
		return "5dff8f"
	if v < base:
		return "ff5a5a"
	return normal


## Shown on the field, hidden while flying, and never for the opponent's face-down cards.
func _badge_wanted() -> bool:
	return show_badge and not busy and (badge_text != "" or not _stats.is_empty()) and (face_up or side == "player")


func _process(delta: float) -> void:
	_update_tilt(delta)
	if not statuses.is_empty():
		_status_layer.queue_redraw()
	for e in _status_fx.values():
		e.emitting = not busy
	# Hovering an Epic or Legendary: a holographic shimmer; a Legendary also sparkles
	var rare := int(card.get("rarity", 1))
	var shine := hovered and face_up and rare >= 4
	_holo = lerpf(_holo, 1.0 if shine else 0.0, 1.0 - exp(-8.0 * delta))
	_mat.set_shader_parameter("holo", _holo)
	if shine and rare >= 5 and _sparkle == null:
		_sparkle = CPUParticles2D.new()
		_sparkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_sparkle.emission_rect_extents = SIZE / 2 + Vector2(6, 6)
		_sparkle.amount = 18
		_sparkle.lifetime = 0.9
		_sparkle.direction = Vector2.UP
		_sparkle.spread = 180.0
		_sparkle.initial_velocity_min = 6.0
		_sparkle.initial_velocity_max = 24.0
		_sparkle.gravity = Vector2(0, -20)
		_sparkle.scale_amount_min = 1.5
		_sparkle.scale_amount_max = 3.5
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
		g.set_color(1, Color(1.0, 0.8, 0.3, 0.0))
		_sparkle.color_ramp = g
		_sparkle.z_index = 3
		add_child(_sparkle)
	if _sparkle:
		_sparkle.emitting = shine and rare >= 5
	if _badge.visible != _badge_wanted():
		_update_badge()
	if _badge.visible:
		var sideways := absf(sin(rotation)) > 0.7
		var half_h: float = (SIZE.x if sideways else SIZE.y) * scale.y / 2.0
		_badge.global_position = global_position + Vector2(-_badge.size.x / 2.0, half_h - 12.0)
		_badge.z_index = z_index + 1


func _update_tilt(delta: float) -> void:
	var pos := global_position
	var vel := Vector2.ZERO if _last_pos == Vector2.INF or delta <= 0.0 else (pos - _last_pos) / delta
	_last_pos = pos
	# Screen-space lean: the leading edge drags back as the card flies, plus any resting lean
	var screen := rest_tilt + Vector2(clampf(-vel.x * 0.012, -MAX_TILT, MAX_TILT), clampf(vel.y * 0.012, -MAX_TILT, MAX_TILT))
	# ...turned into the card's own frame (a sideways DEF card leans the same way on screen)
	var w := Vector2(screen.y, screen.x).rotated(-rotation)
	var target := Vector2(w.y, w.x) + _kick
	if hovered and not busy:
		var m := (to_local(get_global_mouse_position()) / (SIZE / 2.0)).clamp(-Vector2.ONE, Vector2.ONE)
		target += Vector2(-m.x, m.y) * 14.0
	target = target.clamp(-Vector2.ONE * MAX_TILT * 1.5, Vector2.ONE * MAX_TILT * 1.5)
	_tilt = _tilt.lerp(target, 1.0 - exp(-14.0 * delta))
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))
	if _back_mat:
		# The back's animation speeds up while a face-down card is hovered, and eases back after
		var want := _spin_hover if hovered and not face_up else _spin_idle
		_spin_speed = lerpf(_spin_speed, want, 1.0 - exp(-4.0 * delta))
		_spin_angle = fmod(_spin_angle + _spin_speed * delta, TAU)
		_back_mat.set_shader_parameter("galaxy_angle", _spin_angle)
		_back_mat.set_shader_parameter("galaxy_glow", clampf((_spin_speed - _spin_idle) / (_spin_hover - _spin_idle), 0.0, 1.0))
	for m in [_mat, _back_mat]:
		if m:
			m.set_shader_parameter("y_rot", _tilt.x + _flip_deg)
			m.set_shader_parameter("x_rot", _tilt.y)
			m.set_shader_parameter("glare", clampf(_tilt.length() / 16.0, 0.0, 1.0))
			m.set_shader_parameter("flash", _flash)


func _draw() -> void:
	var r := Rect2(-SIZE / 2, SIZE)
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.45))
	if glow > 0.01:
		for i in 3:
			draw_rect(r.grow(3.0 + i * 4.0), Color(glow_color, glow * (0.6 - i * 0.18)), false, 4.0)
	if face_up and _front.texture == null:
		draw_rect(r, Color("161a30"))
		draw_rect(r, Color("b388c9"), false, 2.0)


func _fit(s: Sprite2D) -> void:
	if s.texture:
		s.scale = SIZE / s.texture.get_size()


func set_statuses(v: Array) -> void:
	statuses = v.duplicate()
	_status_layer.queue_redraw()
	if not is_inside_tree():
		return
	# Particles for the statuses that have them: embers rise off a BURNING card, POISON and BLEED drip
	for k in _status_fx.keys():
		if not statuses.has(k):
			_status_fx[k].emitting = false
			_status_fx[k].get_tree().create_timer(1.2).timeout.connect(_status_fx[k].queue_free)
			_status_fx.erase(k)
	for k in statuses:
		if _status_fx.has(k) or not STATUS_PARTICLES.has(k):
			continue
		_status_fx[k] = _make_emitter(k)


## Particles per status: [colour, emit from (offset, half-size), velocity, gravity, amount, lifetime, size]
const STATUS_PARTICLES := {
	"burn": [Color("ff7a3a"), Vector2(0, 30), Vector2(54, 50), 46.0, Vector2(0, -90), 14, 0.9, 3.2],
	"poison": [Color("6ee26a"), Vector2(0, 86), Vector2(54, 3), 8.0, Vector2(0, 260), 6, 0.8, 3.6],
	"bleed": [Color("e0284f"), Vector2(0, 86), Vector2(50, 3), 5.0, Vector2(0, 200), 4, 0.9, 3.0],
}


func _make_emitter(kind: String) -> CPUParticles2D:
	var p: Array = STATUS_PARTICLES[kind]
	var e := CPUParticles2D.new()
	e.position = p[1]
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.emission_rect_extents = p[2]
	e.direction = Vector2.UP if kind == "burn" else Vector2.DOWN
	e.spread = 25.0
	e.initial_velocity_min = p[3] * 0.5
	e.initial_velocity_max = p[3]
	e.gravity = p[4]
	e.amount = p[5]
	e.lifetime = p[6]
	e.scale_amount_min = p[7] * 0.6
	e.scale_amount_max = p[7]
	var ramp := Gradient.new()
	ramp.set_color(0, Color(p[0].lightened(0.3), 0.95))
	ramp.set_color(1, Color(p[0], 0.0))
	e.color_ramp = ramp
	e.local_coords = false   # drips fall straight down, whatever way the card faces
	e.z_index = 2
	add_child(e)
	return e


func _draw_statuses() -> void:
	if statuses.is_empty() or busy:
		return
	var r := Rect2(-SIZE / 2, SIZE)
	var t := Time.get_ticks_msec() / 1000.0
	var L := _status_layer
	if statuses.has("burn"):
		for i in 4:   # heat glowing up from the bottom edge
			L.draw_rect(Rect2(r.position.x, r.end.y - 12.0 - i * 12.0, r.size.x, 12.0), Color(1.0, 0.42, 0.15, (0.22 - i * 0.05) * (0.8 + 0.2 * sin(t * 7.0 + i))))
	if statuses.has("poison"):
		for i in 3:
			L.draw_rect(Rect2(r.position.x, r.end.y - 10.0 - i * 10.0, r.size.x, 10.0), Color(0.43, 0.89, 0.42, 0.16 - i * 0.04))
		for i in 3:   # bubbles rising and popping
			var ph := fmod(t * 0.7 + i * 0.37, 1.0)
			var bx := r.position.x + 22.0 + i * 38.0 + sin(t * 2.0 + i) * 4.0
			L.draw_arc(Vector2(bx, r.end.y - 8.0 - ph * 60.0), 3.0 + ph * 3.0, 0.0, TAU, 12, Color(0.6, 1.0, 0.5, 0.7 * (1.0 - ph)), 1.5, true)
	if statuses.has("bleed"):
		L.draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0), Color(0.88, 0.16, 0.3, 0.3))
	if statuses.has("freeze"):
		_draw_frost(L, r, t)
	if statuses.has("shock"):
		_draw_crackle(L, r, t)
	if statuses.has("shield"):
		var a := 0.45 + 0.3 * sin(t * 3.0)
		L.draw_rect(r.grow(3.0), Color(1.0, 0.85, 0.35, a), false, 2.5)
		L.draw_rect(r.grow(7.0), Color(1.0, 0.85, 0.35, a * 0.35), false, 2.0)
	if statuses.has("stun"):
		for i in 3:   # little stars circling over its head
			var ang := t * 3.2 + i * TAU / 3.0
			_star(L, Vector2(cos(ang) * 34.0, r.position.y - 4.0 + sin(ang) * 8.0), 6.0, Color(1.0, 0.75, 0.3, 0.9))
	if statuses.has("stasis"):
		_draw_time_bubble(L, r, t)
	var font := ThemeDB.fallback_font
	var x := r.position.x + 4.0
	var y := r.position.y + 4.0
	for k in statuses:
		if not STATUS_STYLE.has(k):
			continue
		var col: Color = STATUS_STYLE[k][0]
		var pill := Rect2(x, y, 34, 17)
		if pill.end.x > r.end.x - 2.0:
			x = r.position.x + 4.0
			y += 20.0
			pill = Rect2(x, y, 34, 17)
		_status_layer.draw_rect(pill, Color(0.03, 0.03, 0.08, 0.9))
		_status_layer.draw_rect(pill, col, false, 1.5)
		_status_layer.draw_string(font, Vector2(x, y + 13), STATUS_STYLE[k][1], HORIZONTAL_ALIGNMENT_CENTER, 34, 11, col)
		x += 38.0


## STASIS: frozen in time inside a slowly turning purple bubble, with a clock face on it.
func _draw_time_bubble(L: Node2D, r: Rect2, t: float) -> void:
	var col: Color = STATUS_STYLE.stasis[0]
	var R := r.size.y * 0.6
	L.draw_rect(r, Color(col, 0.16))
	L.draw_circle(Vector2.ZERO, R, Color(col, 0.08))
	L.draw_arc(Vector2.ZERO, R, 0.0, TAU, 64, Color(col.lightened(0.3), 0.7), 2.0, true)
	for i in 12:   # rune dashes turning one way...
		var a := t * 0.5 + i * TAU / 12.0
		L.draw_arc(Vector2.ZERO, R - 7.0, a, a + 0.28, 6, Color(col.lightened(0.4), 0.55), 3.0, true)
	for i in 6:    # ...and an inner ring turning the other
		var a := -t * 0.8 + i * TAU / 6.0
		L.draw_arc(Vector2.ZERO, R * 0.78, a, a + 0.5, 8, Color(col, 0.4), 2.0, true)
	for i in 12:   # clock ticks
		var d := Vector2.from_angle(i * TAU / 12.0)
		L.draw_line(d * (R - 2.0), d * (R - 11.0), Color(1, 1, 1, 0.45), 1.5, true)
	L.draw_line(Vector2.ZERO, Vector2.from_angle(t * 0.35 - PI / 2) * R * 0.55, Color(1, 1, 1, 0.5), 2.0, true)
	L.draw_line(Vector2.ZERO, Vector2.from_angle(t * 0.03 - PI / 2) * R * 0.35, Color(1, 1, 1, 0.5), 3.0, true)
	L.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.7))


## FREEZE: an icy frame, frost crystals growing from the corners, a glint sliding across.
func _draw_frost(L: Node2D, r: Rect2, t: float) -> void:
	var ice: Color = STATUS_STYLE.freeze[0]
	L.draw_rect(r, Color(ice, 0.16))
	L.draw_rect(r.grow(-2.0), Color(0.9, 0.98, 1.0, 0.45), false, 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = uid * 7919 + 13
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var inward: Vector2 = (Vector2.ZERO - corner).normalized()
		for k in 3:
			var dir := inward.rotated(rng.randf_range(-0.7, 0.7))
			var length := rng.randf_range(16.0, 30.0)
			var tip: Vector2 = corner + dir * length
			L.draw_line(corner, tip, Color(0.92, 0.99, 1.0, 0.8), 1.6, true)
			for side in [-1.0, 1.0]:   # little branches
				var mid: Vector2 = corner + dir * length * 0.55
				L.draw_line(mid, mid + dir.rotated(0.8 * side) * length * 0.35, Color(0.92, 0.99, 1.0, 0.6), 1.2, true)
	var x := r.position.x + fmod(t * 60.0, r.size.x + 80.0) - 40.0   # a glint
	L.draw_line(Vector2(clampf(x, r.position.x, r.end.x), r.position.y), Vector2(clampf(x - 40.0, r.position.x, r.end.x), r.end.y), Color(1, 1, 1, 0.22), 6.0, true)


## SHOCK: jagged lightning crackling across the card in short bursts.
func _draw_crackle(L: Node2D, r: Rect2, t: float) -> void:
	var tick := int(t * 14.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = tick * 31 + uid
	if rng.randf() > 0.45:
		return
	var col: Color = STATUS_STYLE.shock[0]
	for b in rng.randi_range(1, 2):
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), r.position.y)
		var pts := PackedVector2Array([p])
		while p.y < r.end.y:
			p += Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(14.0, 26.0))
			p.x = clampf(p.x, r.position.x, r.end.x)
			pts.append(p)
		L.draw_polyline(pts, Color(col, 0.35), 6.0, true)
		L.draw_polyline(pts, Color(0.9, 0.97, 1.0, 0.95), 1.6, true)


func _star(L: Node2D, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(c + Vector2.from_angle(i * PI / 4.0 - PI / 2) * (s if i % 2 == 0 else s * 0.4))
	L.draw_colored_polygon(pts, col)


func set_badge_text(v: String) -> void:
	badge_text = v
	_update_badge()
