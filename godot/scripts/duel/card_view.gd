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
	"silence": [Color("b8b4cc"), "SIL", "SILENCED"], "suppress": [Color("b5e655"), "SUP", "SUPPRESSED"],
	"equipped": [Color("ffc46b"), "EQP", "EQUIPPED"],
	"charm": [Color("ff6fb5"), "CHM", "CHARMED"], "undead": [Color("8dffb0"), "UND", "UNDEAD"],
	"resting": [Color("c9c6e0"), "ZZZ", "CAN'T ATTACK YET"],
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
var cost_now := -1: set = set_cost_now        # a lowered Authority cost, shown over the printed one (-1: none)
var glow_color := Color("f4d35e")
## A second glow colour the outline breathes toward (an ability is ready); cleared whenever glow is set
var pulse_color := Color(0, 0, 0, 0): set = set_pulse_color
var home := Vector2.ZERO
var home_rot := 0.0
var home_scale := 1.0
## Free-for-all: an opponent's board is drawn smaller; every scale this card is moved to is times this
var board_scale := 1.0
var busy := false   # flying / animating: ignore hover and layout
var hovered := false            # lean toward the mouse
var rest_tilt := Vector2.ZERO   # resting lean in screen space: (turn, lean back), degrees

var _body := Node2D.new()   # flips (scale.x) independently of the node's own scale
var _status_layer := Node2D.new()   # status tags, drawn over the art
var _front := Sprite2D.new()
var _back := Sprite2D.new()
var _fallback: Label
var _badge: RichTextLabel
var _badge_box: StyleBoxFlat
const BADGE_W := 112.0
const BADGE_OVERLAP := 4.0   # how far the badge tucks under the card's bottom edge
var _stats := []
var _tw: Tween
var _mat := ShaderMaterial.new()
var _back_mat: ShaderMaterial = null   # the back's own material when its galaxy turns
var _spin_angle := randf() * TAU        # how far the back's animation has turned
var _spin_speed := 0.09
var _spin_idle := 0.09                  # radians per second at rest...
var _spin_hover := 1.6                  # ...and while a face-down card is hovered (it also glows)
## Speeds per moving back (CardDB.BACK_STYLES): [at rest, hovered]
const BACK_SPEEDS := {"galaxy": [0.09, 1.6], "radar": [1.5, 4.8], "roulette": [0.22, 1.4], "hellfire": [0.5, 2.0]}
var _tilt := Vector2.ZERO        # current (y_rot, x_rot) in the card's own frame
var _kick := Vector2.ZERO        # recoil from hits, decays
var _flip_deg := 0.0             # extra turn while flipping over
var _flash := 0.0
var _last_pos := Vector2.INF
var _holo := 0.0                 # hover shimmer on Epic/Legendary cards
var holo_boost := 0.0            # 0..1: a holographic sweep set from outside (an evolving card's reveal)
var _status_fx := {}             # status -> particle emitter (embers, drips)
var _sparkle: CPUParticles2D     # golden sparkles around a hovered Legendary
var _lift := 0.0                 # 0..1: how far above its resting place (scale over home): the shadow falls away
var reveal := 1.0                # 0..1: the face burning into view from the bottom up (shaders/card.gdshader)
var reveal_color := Color(0.75, 0.35, 1.0)


func setup(c: Dictionary, owner_side: String, up: bool) -> CardView:
	side = owner_side
	add_child(_body)
	_body.add_child(_back)
	_body.add_child(_front)
	_mat.shader = _shader
	_mat.set_shader_parameter("roulette_tex", UI.ROULETTE_TEX)   # (the Wildcard back's turning wheel)
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
	# A slim pill just under the card (the rows are 17 px apart), so it never covers the art
	_badge.custom_minimum_size = Vector2(BADGE_W, 0)
	_badge.size = Vector2(BADGE_W, 20)
	_badge.add_theme_font_size_override("normal_font_size", 15)
	_badge.add_theme_font_size_override("bold_font_size", 15)
	_badge.add_theme_constant_override("outline_size", 3)
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_badge_box = StyleBoxFlat.new()
	_badge_box.bg_color = Color(0.045, 0.04, 0.085, 0.94)
	_badge_box.set_corner_radius_all(10)
	_badge_box.set_border_width_all(1)
	_badge_box.border_color = Color(1, 1, 1, 0.16)
	_badge_box.shadow_color = Color(0, 0, 0, 0.55)
	_badge_box.shadow_size = 4
	_badge_box.shadow_offset = Vector2(0, 2)
	_badge_box.content_margin_top = 0
	_badge_box.content_margin_bottom = 0
	_badge.add_theme_stylebox_override("normal", _badge_box)
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
		UI.rarity_fx(_back_mat, 1)   # the back doesn't shimmer like a rare front
		_back.material = _back_mat
		_spin_idle = BACK_SPEEDS[style][0]
		_spin_hover = BACK_SPEEDS[style][1]
		_spin_speed = _spin_idle


func set_card(c: Dictionary) -> void:
	card = c
	uid = int(c.get("uid", uid))
	var tex: Texture2D = null
	if not c.is_empty():
		tex = CardDB.art_for(c)   # (a token picks one of its artworks)
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
	# Rare and up shimmer face-up (staggered by the card's uid so they don't all glint together)
	UI.rarity_fx(_mat, int(card.get("rarity", 1)) if up else 1, fposmod(float(uid) * 0.618, 1.0))
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
	_tw.tween_property(self, "scale", Vector2.ONE * s * board_scale, duration)
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
	_body.modulate = Color(0.78, 0.5, 0.5) if v else Color.WHITE
	_status_layer.queue_redraw()
	_update_badge()


func set_show_badge(v: bool) -> void:
	show_badge = v
	_update_badge()


func set_glow(v: float) -> void:
	glow = v
	pulse_color = Color(0, 0, 0, 0)
	queue_redraw()
	_status_layer.queue_redraw()


func set_pulse_color(c: Color) -> void:
	pulse_color = c
	queue_redraw()
	_status_layer.queue_redraw()   # (its colour-blind symbol)


func hit(p_global: Vector2) -> bool:
	return Rect2(-SIZE / 2, SIZE).has_point(to_local(p_global))


func _update_badge() -> void:
	if _badge == null:
		return
	_badge.visible = _badge_wanted()
	if not _badge.visible:
		return
	if badge_text != "":
		_badge_box.border_color = Color(1.0, 0.85, 0.42, 0.5)
		_badge.text = badge_text
		return
	# Small ATK / DEF labels, the numbers coloured when raised (green) or lowered (red);
	# a Downed card's badge gets a red edge
	_badge_box.border_color = Color(1.0, 0.36, 0.36, 0.85) if downed else Color(1, 1, 1, 0.16)
	var atk_col := _stat_color(_stats[0], _stats[2], "ffe6a8")
	var def_col := _stat_color(_stats[1], _stats[3], "cfe9ff")
	_badge.text = "[center][font_size=10][color=#ff8f80]ATK[/color][/font_size] [b][color=#%s]%d[/color][/b]   [font_size=10][color=#7fb6ff]DEF[/color][/font_size] [b][color=#%s]%d[/color][/b][/center]" \
		% [atk_col, _stats[0], def_col, _stats[1]]


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
	var lift := clampf(scale.x / maxf(home_scale, 0.01) - 1.0, 0.0, 1.0)
	if absf(lift - _lift) > 0.01:
		_lift = lift
		queue_redraw()
	if pulse_color.a > 0.0 and glow > 0.01:
		queue_redraw()
	if not statuses.is_empty() or downed:
		_status_layer.queue_redraw()
	for e in _status_fx.values():
		e.emitting = not busy
	# Hovering an Epic or Legendary: a holographic shimmer; a Legendary also sparkles
	var rare := int(card.get("rarity", 1))
	var shine := hovered and face_up and rare >= 4
	_holo = lerpf(_holo, 1.0 if shine else 0.0, 1.0 - exp(-8.0 * delta))
	_mat.set_shader_parameter("holo", maxf(_holo, holo_boost))
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
		_badge.scale = Vector2.ONE * board_scale   # (its own top-level node: it doesn't inherit the card's scale)
		_badge.global_position = global_position + Vector2(-_badge.size.x * board_scale / 2.0, half_h - BADGE_OVERLAP * board_scale)
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
		var m := (to_local(Game.pad.pointer(self)) / (SIZE / 2.0)).clamp(-Vector2.ONE, Vector2.ONE)
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
	_mat.set_shader_parameter("reveal", reveal)
	_mat.set_shader_parameter("reveal_color", reveal_color)


func _draw() -> void:
	var r := Rect2(-SIZE / 2, SIZE)
	# Its shadow: tight under a card at rest, further off and softer the higher it's lifted
	var off := Vector2(6, 8) * (1.0 + _lift * 2.6)
	for i in 3:
		var a := (0.3 if i == 0 else 0.1) * (1.0 - _lift * 0.35) * reveal
		draw_rect(Rect2(r.position + off, r.size).grow(i * (1.5 + _lift * 5.0)), Color(0, 0, 0, a))
	if glow > 0.01:
		var col := glow_color
		var a := glow
		if pulse_color.a > 0.0:   # breathe toward the pulse colour
			var w := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.2)
			col = glow_color.lerp(pulse_color, w)
			a *= 0.7 + 0.3 * w
		for i in 3:
			draw_rect(r.grow(3.0 + i * 4.0), Color(col, a * (0.6 - i * 0.18)), false, 4.0)
	if face_up and _front.texture == null:
		draw_rect(r, Color("161a30"))
		draw_rect(r, Color("b388c9"), false, 2.0)


func _fit(s: Sprite2D) -> void:
	if s.texture:
		s.scale = SIZE / s.texture.get_size()


func set_cost_now(v: int) -> void:
	if v == cost_now:
		return
	cost_now = v
	_status_layer.queue_redraw()


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


## Colour-blind help (Settings): the glow's meaning as a shape on the card's top edge. Teal pulse:
## a bolt (an Activate ability); green: + (can be played); red: a crosshair; anything else
## (gold): ! (can act).
func _draw_glow_symbol(r: Rect2) -> void:
	var L := _status_layer
	var at := Vector2(0, r.position.y - 2.0)
	var col := pulse_color if pulse_color.a > 0.0 else glow_color
	L.draw_circle(at, 15.0, Color(0.03, 0.03, 0.08, 0.95))
	L.draw_arc(at, 15.0, 0.0, TAU, 24, col, 2.5, true)
	var ink := Color.WHITE
	if pulse_color.a > 0.0:
		L.draw_polyline(PackedVector2Array([at + Vector2(3, -9), at + Vector2(-4, 1), at + Vector2(2, 1), at + Vector2(-3, 9)]), ink, 3.0, true)
	elif glow_color.g > glow_color.r + 0.2:   # green
		L.draw_line(at + Vector2(-7, 0), at + Vector2(7, 0), ink, 3.0)
		L.draw_line(at + Vector2(0, -7), at + Vector2(0, 7), ink, 3.0)
	elif glow_color.r > glow_color.g + 0.4:   # red
		L.draw_arc(at, 7.0, 0.0, TAU, 16, ink, 2.0, true)
		L.draw_line(at + Vector2(-10, 0), at + Vector2(10, 0), ink, 2.0)
		L.draw_line(at + Vector2(0, -10), at + Vector2(0, 10), ink, 2.0)
	else:
		L.draw_line(at + Vector2(0, -8), at + Vector2(0, 3), ink, 3.0)
		L.draw_circle(at + Vector2(0, 8), 2.0, ink)


## A lowered Authority cost (in the hand): a small dark plate over the printed number in the
## top-left corner, the new cost in mint green, with a little ▼ to say it's cheaper.
func _draw_cost_now(r: Rect2) -> void:
	var L := _status_layer
	var font := ThemeDB.fallback_font
	var at := r.position + Vector2(8.6, 8.4)   # (the printed number's centre)
	var mint := Color(0.49, 1.0, 0.66)
	L.draw_circle(at, 7.6, Color(0.0, 0.0, 0.0, 0.35))   # a soft shadow
	L.draw_circle(at, 7.0, Color(0.04, 0.06, 0.06, 0.97))
	L.draw_arc(at, 7.0, 0.0, TAU, 32, Color(mint, 0.85), 0.9, true)
	L.draw_arc(at, 5.9, PI * 1.1, PI * 1.9, 12, Color(1, 1, 1, 0.12), 0.8, true)   # (a faint highlight on top)
	var txt := str(cost_now)
	var size := 10 if txt.length() < 2 else 8
	var base := at + Vector2(-8.0, size * 0.36)
	L.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_CENTER, 16.0, size, 2, Color(0, 0, 0, 0.9))
	L.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_CENTER, 16.0, size, mint)
	var c := at + Vector2(6.2, 5.6)   # the ▼, tucked under the plate's lower right
	L.draw_circle(c, 2.9, Color(0.04, 0.06, 0.06, 0.97))
	L.draw_colored_polygon(PackedVector2Array([c + Vector2(-1.7, -0.9), c + Vector2(1.7, -0.9), c + Vector2(0, 1.4)]), mint)


## Downed: a bloodied wash, a pulsing red edge and a small DOWNED tag that reads level however the
## card lies.
func _draw_downed(r: Rect2) -> void:
	var L := _status_layer
	var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 2.6)
	L.draw_rect(r, Color(0.3, 0.0, 0.02, 0.3))
	L.draw_rect(r.grow(-2.0), Color(1.0, 0.22, 0.18, 0.5 + 0.4 * p), false, 4.0)
	# The tag, turned back against the card's own turn so it stays level on screen
	var tag := Rect2(-34, -10, 68, 20)
	L.draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	L.draw_rect(tag, Color(0.12, 0.01, 0.02, 0.8))
	L.draw_rect(tag, Color(1.0, 0.35, 0.3, 0.7), false, 1.5)
	L.draw_string(ThemeDB.fallback_font, Vector2(tag.position.x, 5), "DOWNED", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 13, Color(1.0, 0.85, 0.82))
	L.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_statuses() -> void:
	if busy:
		return
	var r := Rect2(-SIZE / 2, SIZE)
	if cost_now >= 0 and face_up:
		_draw_cost_now(r)
	if downed and face_up:
		_draw_downed(r)
	if face_up:   # a Striver's level stars, across the top edge
		UI.draw_level_stars(_status_layer, Vector2(0, r.position.y + 1.0), CardDB.striver_stage(card), 6.0)
	if glow > 0.01 and bool(Game.settings.get("glow_symbols", false)):
		_draw_glow_symbol(r)
	if statuses.is_empty():
		return
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
	if statuses.has("suppress"):
		for i in 3:   # tracer fire streaking past, pinning it down
			var ph := fmod(t * 1.6 + i * 0.33, 1.0)
			var ty := r.position.y + r.size.y * (0.2 + i * 0.12)
			var tx := r.position.x - 30.0 + ph * (r.size.x + 60.0)
			L.draw_line(Vector2(tx - 26.0, ty), Vector2(tx, ty), Color(0.71, 0.9, 0.33, 0.85 * (1.0 - ph)), 2.0, true)
	if statuses.has("silence"):
		_draw_silenced(L, r, t)
	if statuses.has("charm"):   # little pink hearts drifting up off it: it fights for the other side this turn
		for i in 4:
			var ph := fmod(t * 0.5 + i * 0.25, 1.0)
			var hp := Vector2(r.position.x + 18.0 + i * 28.0 + sin(t * 2.0 + i) * 4.0, r.end.y - 20.0 - ph * (r.size.y - 30.0))
			_heart(L, hp, 5.0 + 2.0 * sin(t * 4.0 + i), Color(1.0, 0.45, 0.75, 0.85 * (1.0 - ph)))
	if statuses.has("equipped"):   # a gold chain link at the bottom corner: something is attached to it
		var at := Vector2(r.position.x + 14.0, r.end.y - 30.0)
		var glint := 0.7 + 0.3 * sin(t * 2.4)
		for k in 2:
			var c := at + Vector2(k * 8.0, -k * 5.0)
			L.draw_set_transform(c, -0.6, Vector2(1.0, 0.6))
			L.draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(0.1, 0.06, 0.02, 0.8), 4.5, true)
			L.draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(1.0, 0.78, 0.35, glint), 2.5, true)
		L.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if statuses.has("stasis"):
		_draw_time_bubble(L, r, t)
	if statuses.has("bounty"):
		_draw_wanted(L, r, t)
	if statuses.has("resting"):
		for i in 3:   # "z"s drifting up off its top corner: it can't attack this turn
			var ph := fmod(t * 0.45 + i / 3.0, 1.0)
			var at := Vector2(r.end.x - 26.0 + ph * 18.0 + sin(t * 2.0 + i) * 3.0, r.position.y + 6.0 - ph * 46.0)
			L.draw_string(ThemeDB.fallback_font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 + ph * 10), Color(0.85, 0.85, 1.0, 0.9 * (1.0 - ph)))
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


func _heart(L: Node2D, at: Vector2, size: float, col: Color) -> void:
	L.draw_circle(at + Vector2(-size * 0.5, 0), size * 0.6, col)
	L.draw_circle(at + Vector2(size * 0.5, 0), size * 0.6, col)
	L.draw_colored_polygon(PackedVector2Array([at + Vector2(-size * 1.05, size * 0.15), at + Vector2(size * 1.05, size * 0.15), at + Vector2(0, size * 1.4)]), col)


## SILENCE: a speech bubble over its art with a red cross through it, bobbing gently; its effects are muted.
func _draw_silenced(L: Node2D, r: Rect2, t: float) -> void:
	L.draw_rect(r, Color(0.45, 0.43, 0.55, 0.16))   # a faint grey hush over the card
	var at := Vector2(r.position.x + 26.0, r.position.y + 44.0 + sin(t * 2.0) * 2.0)
	var bubble := Rect2(at - Vector2(17, 12), Vector2(34, 24))
	L.draw_rect(Rect2(bubble.position + Vector2(2, 2), bubble.size), Color(0, 0, 0, 0.35))
	L.draw_rect(bubble, Color(0.95, 0.95, 0.98, 0.95))
	L.draw_colored_polygon(PackedVector2Array([at + Vector2(-8, 11), at + Vector2(-1, 11), at + Vector2(-11, 19)]), Color(0.95, 0.95, 0.98, 0.95))   # its tail
	for i in 3:   # the words it can't say
		L.draw_circle(at + Vector2(-8 + i * 8, 0), 2.2, Color(0.35, 0.35, 0.45))
	var red := Color(0.9, 0.12, 0.15, 0.95)
	L.draw_line(at + Vector2(-13, -9), at + Vector2(13, 9), red, 3.2, true)
	L.draw_line(at + Vector2(13, -9), at + Vector2(-13, 9), red, 3.2, true)


## BOUNTY: a little WANTED poster pinned to the card's right edge, swaying, with what it pays out
## (the cards whoever put it there draws when it's KO'd).
func _draw_wanted(L: Node2D, r: Rect2, t: float) -> void:
	var font := ThemeDB.fallback_font
	var pin := Vector2(r.end.x - 20.0, r.position.y + 40.0)
	var sway := sin(t * 1.7) * 0.06 - 0.1
	L.draw_set_transform(pin, sway, Vector2.ONE * 0.82)
	var paper := Rect2(-15, 0, 30, 38)
	L.draw_rect(Rect2(paper.position + Vector2(2, 2), paper.size), Color(0, 0, 0, 0.4))   # its shadow
	L.draw_rect(paper, Color(0.92, 0.83, 0.62))
	L.draw_rect(paper, Color(0.45, 0.3, 0.14), false, 1.2)
	for i in 3:   # a little wear on the paper
		L.draw_line(Vector2(-13 + i * 9, 1), Vector2(-11 + i * 9, 6), Color(0.6, 0.45, 0.25, 0.35), 0.8)
	var ink := Color(0.25, 0.12, 0.05)
	L.draw_string(font, Vector2(-15, 8), "WANTED", HORIZONTAL_ALIGNMENT_CENTER, 30, 7, ink)
	L.draw_circle(Vector2(0, 16), 4.0, ink)   # the outlaw's silhouette
	L.draw_colored_polygon(PackedVector2Array([Vector2(-8, 27), Vector2(-6, 21), Vector2(6, 21), Vector2(8, 27)]), ink)
	var b = card.get("bounty")
	var n := int(b.get("n", 1)) if b is Dictionary else 1
	L.draw_string(font, Vector2(-15, 35), "%d CARD%s" % [n, "" if n == 1 else "S"], HORIZONTAL_ALIGNMENT_CENTER, 30, 6, Color(0.6, 0.08, 0.06))
	L.draw_circle(Vector2(0, 0), 2.4, Color(0.85, 0.15, 0.12))   # the pin
	L.draw_circle(Vector2(-0.7, -0.7), 0.8, Color(1, 0.7, 0.65))
	L.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
