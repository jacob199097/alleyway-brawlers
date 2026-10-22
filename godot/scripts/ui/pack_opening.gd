extends Control
## The pack opening, full screen, for the cards the server rolled (shop.gd buys the pack; nothing here
## decides what's in it):
##   1. The pack flies to centre stage and floats there, leaning toward the mouse. Light leaks from its
##      seam in the colour of the best card inside, and a pack holding an Epic trembles.
##   2. The player tears it open: swipe across it (the top strip peels off as they go, sparks at the
##      tear), or click it. Light pours out, the pack shakes, then bursts.
##   3. The cards fly out face down, each glowing by rarity. The player turns each over: Commons flip,
##      Rares charge up and burst, Epics and Legendaries take centre stage. REVEAL ALL turns the rest.
##   4. NEW on cards they didn't have, the clan's collection filling up, and OPEN ANOTHER (free packs
##      first), which buys the next one without leaving this screen.
## Keys: SPACE/ENTER tears the pack, turns the next card, then opens another. ESC: reveal all, then done.
## No class_name (patches can't add one):
##   load("res://scripts/ui/pack_opening.gd").open(parent, pack, data, currency, from_rect)
## signal another(currency): the shop buys one more and calls next_pack(data), or buy_failed().

signal another(currency: String)
signal closed

const CARD := Vector2(300, 424)
const PACK := Vector2(396, 528)
const STAGE := Vector2(960, 470)
const STRIP := 0.105                 # how much of the pack's height tears off (below the crimp)
const COST := {"karat": 200, "contraband": 100, "free": 1}
const BIG_WORD := {3: "RARE", 4: "EPIC!", 5: "LEGENDARY!"}
## How strongly a face-down card glows by rarity (a wide halo and a tight neon rim), and once it's turned over
const AURA := {1: 0.08, 2: 0.3, 3: 0.6, 4: 0.9, 5: 1.0}
const AURA_SHOWN := {1: 0.0, 2: 0.08, 3: 0.18, 4: 0.32, 5: 0.42}
const RIM := {1: 0.0, 2: 0.45, 3: 0.8, 4: 1.0, 5: 1.0}
const RIM_SHOWN := {1: 0.0, 2: 0.12, 3: 0.3, 4: 0.5, 5: 0.6}

enum Phase { ENTER, READY, TEARING, OPENING, PICK, MOMENT, DONE }

var pack: Dictionary = {}
var currency := "karat"
var from_rect := Rect2()

var _phase := Phase.ENTER
var _result: Dictionary = {}
var _best := 1
var _tease := Color.WHITE           # the colour of the best card inside
var _clan_col := Color("b388ff")
var _add: CanvasItemMaterial
var _bg: ColorRect
var _stage_mat: ShaderMaterial
var _layer: Control                 # pack and cards (this is what shakes)
var _ui: Control                    # words and buttons
var _zoom_host: Control             # a card zoomed in (UI.card_zoom), over everything
var _post_mat: ShaderMaterial
var _post: ColorRect
var _fx := {"wave_strength": 0.0, "aberration": 0.0, "impact": 0.0}
var _shake := 0.0
var _time := 0.0
var _music_db := 0.0
var _music_bus := -1
var _buying := false
var _closing := false
var _balance: Label

# The pack
var _pack_root: Control
var _pack_whole: TextureRect
var _pack_mat: ShaderMaterial
var _pack_glow: TextureRect
var _strip: TextureRect
var _body: TextureRect
var _seam: TextureRect
var _sparks: CPUParticles2D
var _swipe: TextureRect
var _span := Vector2(0, PACK.x)     # the pack's visible left and right edges, in its own coordinates
var _tilt := Vector2.ZERO
var _tear := 0.0
var _tear_dir := 1.0
var _tear_snd := 0.0
var _dragging := false
var _drag_last := Vector2.ZERO
var _moved := 0.0
var _auto := false
var _hint: Label
var _hint_sub: Label

# The cards: {c, rarity, root, art, mat, aura, motes, home, rot, revealed, busy, lift, tilt, style, seed}
var _cards: Array = []
var _queue: Array = []
var _running := false
var _fast := false
var _skip_hold := false
var _reveal_btn: Button
var _bottom: Control

static var _tex := {}


static func open(parent: Control, pack_: Dictionary, data: Dictionary, currency_: String, from := Rect2()) -> Control:
	var o: Control = load("res://scripts/ui/pack_opening.gd").new()
	o.pack = pack_
	o.currency = currency_
	o.from_rect = from
	parent.add_child(o)
	o.start(data)
	return o


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if pack.get("color") is Color:
		_clan_col = pack.color
	_bg = ColorRect.new()
	_bg.size = size
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_mat = ShaderMaterial.new()
	_stage_mat.shader = preload("res://shaders/pack_stage.gdshader")
	_stage_mat.set_shader_parameter("glow_color", _clan_col)
	_stage_mat.set_shader_parameter("glow", 0.0)
	_stage_mat.set_shader_parameter("rays", 0.0)
	_bg.material = _stage_mat
	_bg.modulate.a = 0.0
	add_child(_bg)
	create_tween().tween_property(_bg, "modulate:a", 1.0, 0.35)
	_ambient()
	_layer = _full_layer()
	_ui = _full_layer()
	_zoom_host = _full_layer()
	var title := UI.label("%s  PACK" % str(pack.get("label", "")).to_upper(), 40, _clan_col.lightened(0.25), true)
	title.size = Vector2(1920, 56)
	title.position = Vector2(0, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(title)
	_balance = UI.label("", 22, UI.GOLD, true)
	_balance.size = Vector2(1920, 30)
	_balance.position = Vector2(0, 84)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_balance)
	_refresh_balance()
	# Full-screen hit effects over everything (shaders/post.gdshader, as in the duel)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_post = ColorRect.new()
	_post.size = size
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = preload("res://shaders/post.gdshader")
	_post.material = _post_mat
	_post.visible = false
	layer.add_child(_post)
	# The music steps back while a pack is open
	_music_bus = AudioServer.get_bus_index("Music")
	if _music_bus >= 0:
		_music_db = AudioServer.get_bus_volume_db(_music_bus)
		var bus := _music_bus
		create_tween().tween_method(func(v: float): AudioServer.set_bus_volume_db(bus, v), _music_db, _music_db - 10.0, 0.6)


func _exit_tree() -> void:
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _music_db)


func _full_layer() -> Control:
	var c := Control.new()
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# ── A round: one pack ────────────────────────────────────────────────────────

func start(data: Dictionary) -> void:
	_result = data
	_best = 1
	for c in data.get("cardsReceived", []):
		_best = maxi(_best, int(c.get("rarity", 1)))
	_tease = UI.rarity_color(_best) if _best >= 3 else Color(1.0, 0.95, 0.85)
	_stage_mat.set_shader_parameter("ray_color", _tease)
	_stage_mat.set_shader_parameter("glow_color", _clan_col)
	_tear = 0.0
	_tear_snd = 0.0
	_auto = false
	_dragging = false
	_fast = false
	_phase = Phase.ENTER
	_stage_to(0.6, 0.12, 0.6)
	_build_pack()
	await _pack_entrance()
	if not is_inside_tree():
		return
	_phase = Phase.READY
	_show_hint("SWIPE ACROSS THE PACK TO TEAR IT OPEN", "or click it  ·  SPACE")


## The shop bought another one: clear the table and open it.
func next_pack(data: Dictionary) -> void:
	_buying = false
	await _clear_round()
	_refresh_balance()
	start(data)


func buy_failed() -> void:
	_buying = false


func _clear_round() -> void:
	_hide_hint()
	var gone: Array = []
	for k in _cards:
		gone.append(k.root)
		gone.append_array(k.get("labels", []))
	if _bottom:
		gone.append(_bottom)
	if _reveal_btn:
		gone.append(_reveal_btn)
	for n in gone:
		if is_instance_valid(n):
			n.create_tween().tween_property(n, "modulate:a", 0.0, 0.25)
	for k in _cards:
		k.root.create_tween().tween_property(k.root, "position:y", k.root.position.y + 140.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.27).timeout
	for n in gone:
		if is_instance_valid(n):
			n.queue_free()
	_cards.clear()
	_queue.clear()
	_bottom = null
	_reveal_btn = null


func _refresh_balance() -> void:
	var text := "KARAT  %d     ·     CONTRABAND  %d" % [int(Game.player.get("karat", 0)), int(Game.player.get("contraband", 0))]
	var free := int(Game.player.get("free_packs", 0))
	if free > 0:
		text += "     ·     FREE PACKS  %d" % free
	_balance.text = text


# ── The pack ─────────────────────────────────────────────────────────────────

func _build_pack() -> void:
	var tex: Texture2D = UI.tex(str(pack.get("image", "")))
	if tex == null:
		tex = CardDB.back()
	_pack_root = Control.new()
	_pack_root.size = PACK
	_pack_root.pivot_offset = PACK / 2
	_pack_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_pack_root)
	_pack_glow = _glow(Color(_tease, 0.0), PACK * Vector2(1.7, 1.4))
	_pack_glow.position = PACK / 2 - _pack_glow.size / 2
	_pack_root.add_child(_pack_glow)
	_pack_whole = UI.texture_rect(tex, PACK)
	_pack_mat = UI.card_material(PACK)
	_pack_whole.material = _pack_mat
	_pack_root.add_child(_pack_whole)
	# The two pieces it tears into: shown when the tear starts (the pack is flat by then)
	var ts := tex.get_size()
	var cut := roundf(ts.y * STRIP)
	var top := AtlasTexture.new()
	top.atlas = tex
	top.region = Rect2(0, 0, ts.x, cut)
	var low := AtlasTexture.new()
	low.atlas = tex
	low.region = Rect2(0, cut, ts.x, ts.y - cut)
	var sh := PACK.y * cut / ts.y
	_body = UI.texture_rect(low, Vector2(PACK.x, PACK.y - sh))
	_body.position = Vector2(0, sh)
	_body.pivot_offset = _body.size / 2
	_body.visible = false
	_pack_root.add_child(_body)
	_span = _visible_span(tex)
	# Light leaking from the seam (brighter as it tears)
	_seam = _glow(Color(_tease, 0.0), Vector2(_span.y - _span.x, 44), _line_tex())
	_seam.position = Vector2(_span.x, sh - 22)
	_pack_root.add_child(_seam)
	_strip = UI.texture_rect(top, Vector2(PACK.x, sh))
	_strip.visible = false
	_pack_root.add_child(_strip)
	# A glint sliding along the seam: swipe here
	_swipe = _glow(Color(1, 1, 1, 0.0), Vector2(90, 90))
	_swipe.position = Vector2(_span.x - 45, sh - 45)
	_pack_root.add_child(_swipe)


## Where the pack's art actually is across its texture (packs can have empty space at the sides).
func _visible_span(tex: Texture2D) -> Vector2:
	var key := "span:%d" % tex.get_instance_id()
	if not _tex.has(key):
		var span := Vector2(PACK.x * 0.04, PACK.x * 0.96)
		var img := tex.get_image()
		if img and (not img.is_compressed() or img.decompress() == OK):
			var r := img.get_used_rect()
			if r.size.x > 0:
				span = Vector2(r.position.x + r.size.x * 0.03, r.end.x - r.size.x * 0.03) * PACK.x / img.get_width()
		_tex[key] = span
	return _tex[key]


func _pack_entrance() -> void:
	var home := STAGE - PACK / 2
	if from_rect.size.x > 0:
		# The first pack lifts off the shop's shelf
		_pack_root.position = from_rect.get_center() - PACK / 2
		_pack_root.scale = Vector2.ONE * (from_rect.size.x / PACK.x)
		from_rect = Rect2()
	else:
		_pack_root.position = Vector2(home.x, 1200)
		_pack_root.rotation = 0.35
		_pack_root.scale = Vector2.ONE * 0.8
	Sfx.play("whoosh", 0.75)
	var t := create_tween().set_parallel()
	t.tween_property(_pack_root, "position", home, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_pack_root, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_pack_root, "rotation", 0.0, 0.5)
	t.tween_property(_pack_glow, "modulate:a", 0.3, 0.8)
	await t.finished
	Sfx.play("boom", 1.5, -10.0)
	_ring(STAGE, Color(_clan_col, 0.5), 160.0, 460.0, 0.6, 4.0)
	# The swipe hint glides along the seam, again and again
	var s := _swipe.create_tween().set_loops()
	s.tween_property(_swipe, "modulate:a", 0.9, 0.15)
	s.parallel().tween_property(_swipe, "position:x", _span.y - 45, 0.9).from(_span.x - 45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	s.tween_property(_swipe, "modulate:a", 0.0, 0.2)
	s.tween_interval(0.7)


func _process(delta: float) -> void:
	_time += delta
	var fx := clampf(float(Game.settings.get("screen_fx", 1.0)), 0.0, 1.0)   # (Settings → Screen Shake & Flashes)
	if _shake * fx > 0.15:
		_layer.position = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)) * fx
		_shake *= exp(-delta * 7.0)
	else:
		_shake = 0.0
		_layer.position = Vector2.ZERO
	for k in _fx:
		_post_mat.set_shader_parameter(k, _fx[k])
	_post.visible = _fx.values().any(func(x): return x > 0.002)
	if _phase == Phase.READY or _phase == Phase.TEARING:
		_idle_pack(delta)
	_idle_cards(delta)


func _idle_pack(delta: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * (2.5 + _best))
	if _phase == Phase.READY:
		_pack_root.position.y = STAGE.y - PACK.y / 2 + sin(_time * 1.8) * 7.0
		var m := ((get_local_mouse_position() - STAGE) / (PACK * 0.6)).clamp(-Vector2.ONE, Vector2.ONE)
		_tilt = _tilt.lerp(Vector2(-m.x, m.y) * 16.0, 1.0 - exp(-8.0 * delta))
		_pack_mat.set_shader_parameter("y_rot", _tilt.x)
		_pack_mat.set_shader_parameter("x_rot", _tilt.y)
		_pack_mat.set_shader_parameter("glare", clampf(_tilt.length() / 16.0, 0.0, 1.0))
		# Something special inside: the pack trembles now and then, and sparks spit from the seam
		if _best >= 4:
			var k := pow(maxf(0.0, sin(_time * 2.2)), 30.0)
			_pack_root.rotation = sin(_time * 70.0) * 0.025 * k * (_best - 3)
			if k > 0.7 and randf() < 0.25:
				_sparkle(_pack_root.position + Vector2(randf_range(_span.x, _span.y), _seam.position.y + 22), _tease, 3, 0.4)
		_pack_glow.modulate.a = 0.22 + 0.06 * _best + 0.12 * pulse
		_seam.modulate.a = (0.12 + 0.2 * pulse) * (1.0 if _best >= 3 else 0.5)
	else:
		_pack_glow.modulate.a = 0.4 + 0.5 * _tear + 0.1 * pulse


# ── Tearing ──────────────────────────────────────────────────────────────────

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if _phase == Phase.READY or _phase == Phase.TEARING:
			if e.pressed and Rect2(_pack_root.position, PACK).grow(40).has_point(e.position):
				_dragging = true
				_drag_last = e.position
				_moved = 0.0
			elif not e.pressed and _dragging:
				_dragging = false
				if _moved < 12.0 or _tear >= 0.5:
					_auto_tear()
		elif _phase == Phase.MOMENT and e.pressed:
			_skip_hold = true
	elif e is InputEventMouseMotion and _dragging:
		var dx: float = e.position.x - _drag_last.x
		_moved += e.relative.length()
		_drag_last = e.position
		if _moved > 12.0 and absf(dx) > 0.0 and not _auto:
			if _phase == Phase.READY:
				_begin_tear(signf(dx))
			_tear_to(_tear + absf(dx) / ((_span.y - _span.x) * 0.95))


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if _zoom_host.get_child_count() > 0:
		if e.keycode == KEY_ESCAPE:
			for z in _zoom_host.get_children():
				z.queue_free()
			get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			match _phase:
				Phase.READY, Phase.TEARING:
					_auto_tear()
				Phase.PICK:
					_reveal_next()
				Phase.MOMENT:
					_skip_hold = true
				Phase.DONE:
					_again()
		KEY_ESCAPE:
			if _phase == Phase.DONE:
				_close()
			elif _phase == Phase.READY or _phase == Phase.TEARING:
				_fast = true
				_auto_tear()
			else:
				_skip_hold = true
				reveal_all()
		_:
			return
	get_viewport().set_input_as_handled()


func _begin_tear(dir: float) -> void:
	_phase = Phase.TEARING
	_tear_dir = dir if dir != 0.0 else 1.0
	_pack_root.rotation = 0.0
	_pack_whole.visible = false
	_strip.visible = true
	_body.visible = true
	# The strip stays attached at the far end and peels up from where the tear started
	_strip.pivot_offset = Vector2(_span.y if _tear_dir > 0.0 else _span.x, _strip.size.y)
	_seam.size.x = 0.0
	_swipe.queue_free()
	_hide_hint()
	_sparks = _emitter(_tease, 26, 0.45)
	_sparks.position = Vector2(_span.x if _tear_dir > 0.0 else _span.y, _strip.size.y)
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 140.0
	_sparks.initial_velocity_max = 380.0
	_sparks.gravity = Vector2(0, 700)
	_pack_root.add_child(_sparks)
	Sfx.play("tear", 0.8)


func _tear_to(v: float) -> void:
	if _phase != Phase.TEARING:
		return
	_tear = clampf(v, _tear, 1.0)
	var w := _span.y - _span.x
	var head := _span.x + w * _tear if _tear_dir > 0.0 else _span.y - w * _tear
	_strip.rotation = _tear_dir * _tear * _tear * 0.4
	_strip.position.y = -_tear * 12.0
	_seam.size.x = w * _tear
	_seam.position.x = _span.x if _tear_dir > 0.0 else head
	_seam.modulate.a = 0.5 + 0.5 * _tear
	_sparks.position.x = head
	_body.rotation = randf_range(-0.01, 0.01) * _tear
	_shake = maxf(_shake, 2.0 + 3.0 * _tear)
	_stage_mat.set_shader_parameter("rays", 0.12 + 0.6 * _tear)
	while _tear - _tear_snd >= 0.07:
		_tear_snd += 0.07
		Sfx.play("tear", randf_range(0.85, 1.25), -3.0)
	if _tear >= 1.0:
		_finish_tear()


## A click (or SPACE): the tear runs the rest of the way by itself.
func _auto_tear() -> void:
	if _auto or not (_phase == Phase.READY or _phase == Phase.TEARING):
		return
	_auto = true
	_dragging = false
	if _phase == Phase.READY:
		_begin_tear(1.0)
	var t := create_tween()
	t.tween_method(_tear_to, _tear, 1.0, (0.12 if _fast else 0.2) + 0.4 * (1.0 - _tear)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Tears it open without waiting for the player (tests and the screen tour).
func tear_now() -> void:
	_auto_tear()


func _finish_tear() -> void:
	_phase = Phase.OPENING
	_sparks.emitting = false
	Sfx.play("pack_open")
	var fly := create_tween().set_parallel()
	fly.tween_property(_strip, "position", _strip.position + Vector2(_tear_dir * 360.0, -420.0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fly.tween_property(_strip, "rotation", _tear_dir * 2.8, 0.75)
	fly.tween_property(_strip, "modulate:a", 0.0, 0.5).set_delay(0.25)
	_open_up()


## Light pours out of the open pack, it shakes harder and harder (longer for a better card), then bursts.
func _open_up() -> void:
	var mouth := _pack_root.position + Vector2(PACK.x / 2, _strip.size.y)
	var beam := _glow(Color(_tease, 0.0), Vector2((_span.y - _span.x) * 0.9, 1100), _beam_tex())
	beam.pivot_offset = Vector2(beam.size.x / 2, beam.size.y)
	beam.position = mouth - Vector2(beam.size.x / 2, beam.size.y)
	_layer.add_child(beam)
	_layer.move_child(beam, _pack_root.get_index())
	var build := 0.45 if _best <= 3 else 0.85 if _best == 4 else 1.2
	if _fast:
		build *= 0.4
	Sfx.play("charge", 1.2 / build, -4.0)
	var t := create_tween().set_parallel()
	t.tween_property(beam, "modulate:a", 0.95, build).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(beam, "scale:x", 1.25, build)
	t.tween_property(_pack_glow, "scale", Vector2.ONE * 1.5, build)
	t.tween_method(func(v: float):
		_shake = maxf(_shake, v)
		_fx.aberration = v * 0.4
		_stage_mat.set_shader_parameter("rays", 0.7 + v * 0.03), 3.0, 6.0 + 4.0 * _best, build).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if not is_inside_tree():
		return
	# Burst
	Sfx.play("burst")
	Sfx.play("boom", 1.0, -3.0)
	_flash(Color.WHITE, 0.85, 0.45)
	_shockwave(mouth, 1.0)
	_pulse("aberration", 9.0, 0.5)
	_shake = maxf(_shake, 18.0)
	_ring(mouth, _tease, 60.0, 720.0, 0.65, 10.0)
	_ring(mouth, Color.WHITE, 30.0, 420.0, 0.45, 5.0)
	_confetti(mouth, [_clan_col, _tease, UI.GOLD, Color.WHITE], 110)
	_sparkle(mouth, _tease, 70)
	_stage_to(0.6, 0.15, 0.8)
	var away := create_tween().set_parallel()
	away.tween_property(_body, "position:y", _body.position.y + 320.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	away.tween_property(_body, "rotation", _tear_dir * 0.25, 0.55)
	away.tween_property(_pack_root, "modulate:a", 0.0, 0.45).set_delay(0.1)
	away.tween_property(beam, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(0.08).timeout
	await _deal(mouth)
	if not is_inside_tree():
		return
	beam.queue_free()
	_pack_root.queue_free()
	_phase = Phase.PICK
	_show_hint("CLICK A CARD TO TURN IT OVER", "SPACE turns the next one")
	_reveal_btn = UI.button("REVEAL ALL", reveal_all, Vector2(240, 56), UI.PURPLE)
	_reveal_btn.position = Vector2(1648, 996)
	_ui.add_child(_reveal_btn)


# ── The cards ────────────────────────────────────────────────────────────────

## The cards fly out of the pack face down and land in a row.
func _deal(from: Vector2) -> void:
	var cards: Array = _result.get("cardsReceived", [])
	var n := cards.size()
	var gap := minf(400.0, 1600.0 / maxf(1.0, n))
	for i in n:
		var off := i - (n - 1) / 2.0
		var home := Vector2(STAGE.x + off * gap, STAGE.y + absf(off) * 22.0)
		var k := _make_card(cards[i], home, off * 0.05)
		var root: Control = k.root
		var start := from - CARD / 2
		var end := home - CARD / 2
		var peak := Vector2(lerpf(start.x, end.x, 0.5), minf(start.y, end.y) - 260.0)
		root.position = start
		root.scale = Vector2.ONE * 0.25
		root.rotation = randf_range(-1.4, 1.4)
		var t := create_tween().set_parallel()
		t.tween_method(func(v: float): root.position = start.lerp(peak, v).lerp(peak.lerp(end, v), v), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(root, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(root, "rotation", float(k.rot), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play("whoosh", 1.3 + i * 0.12, -7.0)
		var land_at := home + Vector2(0, CARD.y / 2 - 10)
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_inside_tree():
				Sfx.play("set", 1.0 + i * 0.06)
				_dust(land_at))
		await get_tree().create_timer(0.12).timeout
	await get_tree().create_timer(0.55).timeout


func _make_card(c: Dictionary, home: Vector2, rot: float) -> Dictionary:
	var r := clampi(int(c.get("rarity", 1)), 1, 5)
	var tag := str(c.get("clanTag", c.get("clan_tag", "")))
	var root := Control.new()
	root.size = CARD
	root.pivot_offset = CARD / 2
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	var aura := _glow(Color(UI.rarity_color(r), AURA[r]), CARD * Vector2(1.9, 1.55))
	aura.position = CARD / 2 - aura.size / 2
	aura.pivot_offset = aura.size / 2
	root.add_child(aura)
	var shadow := TextureRect.new()
	shadow.texture = _soft_tex()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.size = CARD * 1.15
	shadow.position = CARD / 2 - shadow.size / 2 + Vector2(10, 26)
	shadow.modulate = Color(0, 0, 0, 0.6)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shadow)
	var rim := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(14)
	sb.shadow_color = UI.rarity_color(r).lightened(0.15)
	sb.shadow_size = 14 + 8 * r
	rim.add_theme_stylebox_override("panel", sb)
	rim.size = CARD
	rim.material = _add
	rim.modulate.a = RIM[r]
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rim)
	var art := UI.texture_rect(CardDB.back(tag), CARD)
	var mat := UI.card_material(CARD)
	var style := CardDB.back_style(tag)
	if style != "":
		mat.set_shader_parameter(style, 1.0)
	art.material = mat
	root.add_child(art)
	var motes: CPUParticles2D = null
	if r >= 4:
		# Light rising off it
		motes = _emitter(UI.rarity_color(r), 18 if r == 4 else 30, 1.4)
		motes.one_shot = false
		motes.explosiveness = 0.0
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(CARD.x * 0.45, 10)
		motes.position = Vector2(CARD.x / 2, CARD.y * 0.85)
		motes.direction = Vector2.UP
		motes.spread = 10.0
		motes.gravity = Vector2(0, -60)
		motes.initial_velocity_min = 40.0
		motes.initial_velocity_max = 120.0
		motes.emitting = true
		root.add_child(motes)
	var k := {"c": c, "rarity": r, "root": root, "art": art, "mat": mat, "aura": aura, "motes": motes,
		"rim": rim, "home": home, "rot": rot, "revealed": false, "busy": false, "lift": 0.0, "tilt": Vector2.ZERO,
		"style": style, "seed": randf() * TAU, "labels": []}
	root.gui_input.connect(_on_card_input.bind(k))
	root.mouse_entered.connect(func():
		if not k.revealed and not k.busy and _phase == Phase.PICK:
			Sfx.play("phase", 0.55 + 0.15 * r, -12.0))
	_cards.append(k)
	return k


func _on_card_input(e: InputEvent, k: Dictionary) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	if _phase == Phase.MOMENT:
		_skip_hold = true
	elif e.button_index == MOUSE_BUTTON_LEFT and not k.revealed:
		if _phase == Phase.PICK:
			_enqueue(k)
	elif k.revealed:
		UI.card_zoom(_zoom_host, k.c)
	accept_event()


## Hover lift and tilt, auras breathing, card backs turning.
func _idle_cards(delta: float) -> void:
	var mouse := get_local_mouse_position()
	for k in _cards:
		if k.busy or not is_instance_valid(k.root):
			continue
		var root: Control = k.root
		var mat: ShaderMaterial = k.mat
		var r: int = k.rarity
		var hot: bool = _phase in [Phase.PICK, Phase.DONE] and Rect2(k.home - CARD / 2, CARD).has_point(mouse) \
			and _zoom_host.get_child_count() == 0
		k.lift = lerpf(k.lift, -20.0 if hot else 0.0, 1.0 - exp(-14.0 * delta))
		var bob := 0.0 if k.revealed else sin(_time * 1.7 + k.seed) * 5.0
		root.position = k.home - CARD / 2 + Vector2(0, k.lift + bob)
		root.scale = root.scale.lerp(Vector2.ONE * (1.06 if hot else 1.0), 1.0 - exp(-14.0 * delta))
		var target := Vector2.ZERO
		if hot:
			var m: Vector2 = ((mouse - k.home) / (CARD / 2)).clamp(-Vector2.ONE, Vector2.ONE)
			target = Vector2(-m.x, m.y) * 14.0
		k.tilt = k.tilt.lerp(target, 1.0 - exp(-12.0 * delta))
		mat.set_shader_parameter("y_rot", k.tilt.x)
		mat.set_shader_parameter("x_rot", k.tilt.y)
		mat.set_shader_parameter("glare", clampf(k.tilt.length() / 14.0, 0.0, 1.0))
		var aura: TextureRect = k.aura
		var base: float = AURA_SHOWN[r] if k.revealed else AURA[r]
		var breath := 0.8 + 0.2 * sin(_time * (2.0 + r) + k.seed)
		aura.modulate.a = base * breath + (0.15 if hot else 0.0)
		var rim: Panel = k.rim
		rim.modulate.a = (RIM_SHOWN[r] if k.revealed else RIM[r]) * breath + (0.2 if hot and r >= 2 else 0.0)
		if not k.revealed:
			root.rotation = k.rot + (sin(_time * 60.0 + k.seed) * 0.006 * (r - 3) if r >= 4 else 0.0)
			if k.style != "":
				mat.set_shader_parameter("galaxy_angle", _time * {"galaxy": 0.4, "roulette": 0.5}.get(k.style, 1.6) + k.seed)
				mat.set_shader_parameter("galaxy_glow", 1.0 if hot else 0.0)


func _enqueue(k: Dictionary) -> void:
	if k.revealed or k.busy or _queue.has(k):
		return
	_queue.append(k)
	if not _running:
		_run_queue()


func _run_queue() -> void:
	_running = true
	while not _queue.is_empty() and is_inside_tree():
		await _reveal(_queue.pop_front())
	_running = false
	if is_inside_tree() and not _cards.is_empty() and _cards.all(func(x): return x.revealed):
		_summary()


func _reveal_next() -> void:
	var rest := _cards.filter(func(k): return not k.revealed and not k.busy and not _queue.has(k))
	if rest.is_empty():
		return
	rest.sort_custom(func(a, b): return a.rarity < b.rarity)
	_enqueue(rest[0])


## Turns over every card still face down, lowest rarity first, quicker than by hand.
func reveal_all() -> void:
	if _phase != Phase.PICK and _phase != Phase.MOMENT:
		return
	_fast = true
	var rest := _cards.filter(func(k): return not k.revealed and not k.busy and not _queue.has(k))
	rest.sort_custom(func(a, b): return a.rarity < b.rarity)
	_queue.append_array(rest)
	if _reveal_btn:
		_reveal_btn.disabled = true
	if not _running:
		_run_queue()


func _reveal(k: Dictionary) -> void:
	k.busy = true
	_hide_hint()
	var r: int = k.rarity
	if r >= 4:
		await _big_reveal(k)
	elif r == 3:
		await _rare_reveal(k)
	else:
		await _plain_reveal(k)
	if not is_inside_tree():
		return
	k.revealed = true
	k.busy = false
	_after_reveal(k)
	await get_tree().create_timer(0.06 if _fast else 0.12).timeout


## Turn the card over: edge-on, swap the back for the front, and swing round.
func _flip(k: Dictionary, half: float) -> void:
	var mat: ShaderMaterial = k.mat
	mat.set_shader_parameter("x_rot", 0.0)
	mat.set_shader_parameter("glare", 0.0)
	var t := create_tween()
	t.tween_method(func(d: float): mat.set_shader_parameter("y_rot", d), float(k.tilt.x), 90.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(_show_face.bind(k))
	t.tween_method(func(d: float): mat.set_shader_parameter("y_rot", d), -90.0, 0.0, half * 1.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	k.tilt = Vector2.ZERO


func _show_face(k: Dictionary) -> void:
	var tex := UI.card_art(k.c)
	var art: TextureRect = k.art
	if tex:
		art.texture = tex
	var mat: ShaderMaterial = k.mat
	mat.set_shader_parameter("galaxy", 0.0)
	mat.set_shader_parameter("radar", 0.0)
	mat.set_shader_parameter("galaxy_glow", 0.0)
	UI.rarity_fx(mat, k.rarity, randf())
	if k.motes:
		k.motes.emitting = false


## Common and Uncommon: a quick flip and a puff of light.
func _plain_reveal(k: Dictionary) -> void:
	var root: Control = k.root
	var col := UI.rarity_color(k.rarity)
	root.create_tween().tween_property(root, "scale", Vector2.ONE * 1.08, 0.08)
	await _flip(k, 0.07 if _fast else 0.1)
	Sfx.play("flip", 1.1)
	if k.rarity >= 2:
		Sfx.play("shimmer", 1.3, -8.0)
	_ring(k.home, Color(col, 0.7), 90.0, 260.0, 0.35, 4.0)
	_sparkle(k.home, col.lightened(0.3), 16 if k.rarity == 1 else 28, 0.7)
	root.create_tween().tween_property(root, "scale", Vector2.ONE, 0.2)


## Rare: it lifts, light rushes in, then it flips with a burst and "RARE".
func _rare_reveal(k: Dictionary) -> void:
	var root: Control = k.root
	var aura: TextureRect = k.aura
	var col := UI.rarity_color(3)
	var charge := 0.25 if _fast else 0.55
	Sfx.play("charge", 1.2 / charge, -6.0)
	_converge(k.home, col, 40, charge)
	var t := create_tween().set_parallel()
	t.tween_property(root, "position:y", root.position.y - 36.0, charge).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector2.ONE * 1.12, charge)
	t.tween_property(aura, "modulate:a", 1.0, charge)
	t.tween_property(aura, "scale", Vector2.ONE * 1.25, charge)
	t.tween_method(func(v: float): root.rotation = k.rot + sin(_time * 50.0) * 0.02 * v, 0.0, 1.0, charge)
	await t.finished
	root.rotation = k.rot
	await _flip(k, 0.07)
	Sfx.play("reveal_rare")
	Sfx.play("boom", 1.8, -12.0)
	_flash(col, 0.3, 0.3)
	_shockwave(k.home, 0.6)
	_pulse("aberration", 4.0, 0.35)
	_shake = maxf(_shake, 8.0)
	_ring(k.home, col, 110.0, 540.0, 0.55, 7.0)
	_sparkle(k.home, col, 60)
	_pop_word("RARE", col, k.home + Vector2(0, -CARD.y / 2 - 70), 64)
	var s := create_tween().set_parallel()
	s.tween_property(root, "position:y", k.home.y - CARD.y / 2, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	s.tween_property(root, "scale", Vector2.ONE, 0.35)
	s.tween_property(aura, "scale", Vector2.ONE, 0.4)
	await s.finished


## Epic and Legendary: the rest of the table dims, the card takes centre stage and charges up
## (trembling harder and harder, light rushing in, the screen's edges pulsing), almost turns, snaps
## back, then turns with an impact frame, a shockwave, confetti and the word slamming in.
func _big_reveal(k: Dictionary) -> void:
	_phase = Phase.MOMENT
	_skip_hold = false
	var r: int = k.rarity
	var col := UI.rarity_color(r)
	var clan := _clan_of(k.c)
	var root: Control = k.root
	var aura: TextureRect = k.aura
	var mat: ShaderMaterial = k.mat
	var at := Vector2(960, 440)
	_layer.move_child(root, -1)
	var others := _cards.filter(func(x): return x != k)
	for o in others:
		for n in [o.root] + o.labels:
			n.create_tween().tween_property(n, "modulate", Color(0.3, 0.3, 0.36, 0.35 if n != o.root else 1.0), 0.35)
	_stage_mat.set_shader_parameter("ray_color", col)
	_stage_mat.set_shader_parameter("glow_color", col.lerp(clan, 0.4))
	_stage_to(0.9, 0.8, 0.5)
	Sfx.play("riser", 0.6)
	var up := create_tween().set_parallel()
	up.tween_property(root, "position", at - CARD / 2, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(root, "scale", Vector2.ONE * 1.45, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(root, "rotation", 0.0, 0.4)
	up.tween_property(aura, "modulate:a", 1.0, 0.5)
	await up.finished
	var charge := (1.3 if r == 4 else 1.8) * (0.4 if _fast else 1.0)
	Sfx.play("charge", 1.2 / charge, -2.0)
	if not _fast:
		Sfx.play("heartbeat", 1.0, -3.0)
	_converge(at, col, 90, charge)
	_converge(at, clan, 50, charge)
	var c := create_tween().set_parallel()
	c.tween_method(func(v: float):
		root.rotation = sin(_time * 55.0) * 0.03 * v
		_shake = maxf(_shake, 7.0 * v)
		_fx.aberration = 6.0 * v
		_stage_mat.set_shader_parameter("pulse", v * (0.6 + 0.4 * sin(_time * 18.0))), 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	c.tween_property(aura, "scale", Vector2.ONE * 1.5, charge)
	await c.finished
	root.rotation = 0.0
	if not _fast:
		# Fake-out: it almost turns, and snaps back
		var f := create_tween()
		var turn := func(d: float): mat.set_shader_parameter("y_rot", d)
		f.tween_method(turn, 0.0, 62.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		f.tween_method(turn, 62.0, -12.0, 0.18).set_trans(Tween.TRANS_BACK)
		f.tween_method(turn, -12.0, 0.0, 0.1)
		Sfx.play("flip", 0.8)
		await f.finished
		await get_tree().create_timer(0.22).timeout
	k.tilt = Vector2.ZERO
	await _flip(k, 0.07)
	# Impact
	Sfx.play("reveal_epic" if r == 4 else "reveal_legendary")
	Sfx.play("boom", 0.9)
	_post_mat.set_shader_parameter("impact_tint", col.lightened(0.6))
	_pulse("impact", 1.0, 0.22)
	_flash(Color.WHITE, 0.9, 0.5)
	_shockwave(at, 1.3)
	_pulse("aberration", 12.0, 0.6)
	_shake = maxf(_shake, 24.0)
	_stage_mat.set_shader_parameter("pulse", 0.0)
	_ring(at, col, 120.0, 900.0, 0.7, 12.0)
	_ring(at, clan, 80.0, 650.0, 0.6, 7.0)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_inside_tree():
			_ring(at, Color.WHITE, 60.0, 500.0, 0.5, 5.0))
	_confetti(at, [col, clan, UI.GOLD, Color.WHITE], 170)
	_sparkle(at, col, 90)
	mat.set_shader_parameter("holo", 1.0)
	create_tween().tween_method(func(v: float): mat.set_shader_parameter("holo", v), 1.0, 0.0, 2.5)
	var words := _slam(str(BIG_WORD.get(r, "EPIC!")), col, clan, k.c)
	var hold := (1.8 if r == 4 else 2.4) * (0.35 if _fast else 1.0)
	var waited := 0.0
	while waited < hold and not _skip_hold and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not is_inside_tree():
		return
	# Back into the row
	var back := create_tween().set_parallel()
	back.tween_property(root, "position", k.home - CARD / 2, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	back.tween_property(root, "scale", Vector2.ONE, 0.4)
	back.tween_property(root, "rotation", float(k.rot), 0.4)
	back.tween_property(aura, "scale", Vector2.ONE, 0.4)
	for o in others:
		for n in [o.root] + o.labels:
			back.tween_property(n, "modulate", Color.WHITE, 0.4)
	for w in words:
		back.tween_property(w, "modulate:a", 0.0, 0.3)
	await back.finished
	for w in words:
		w.queue_free()
	_stage_mat.set_shader_parameter("ray_color", _tease)
	_stage_mat.set_shader_parameter("glow_color", _clan_col)
	_stage_to(0.6, 0.15, 0.5)
	_phase = Phase.PICK


## Name and rarity under the card, and NEW (or how many they own now).
func _after_reveal(k: Dictionary) -> void:
	var r: int = k.rarity
	var col := UI.rarity_color(r)
	var home: Vector2 = k.home
	var name := UI.label(str(k.c.get("name", "?")).strip_edges(), 26, col.lightened(0.3), true)
	name.size = Vector2(380, 34)
	name.position = home + Vector2(-190, CARD.y / 2 + 16)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rl := UI.label(str(UI.RARITY_LABEL.get(r, "Common")).to_upper(), 17, col)
	rl.size = Vector2(380, 24)
	rl.position = name.position + Vector2(0, 36)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var labels: Array = [name, rl]
	if not k.c.get("isNew", false) and k.c.get("owned") != null:
		var own := UI.label("OWNED  ×%d" % int(k.c.owned), 15, UI.MUTED)
		own.size = Vector2(380, 22)
		own.position = rl.position + Vector2(0, 26)
		own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.append(own)
	for l in labels:
		l.modulate.a = 0.0
		_ui.add_child(l)
		l.create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
	k.labels = labels
	if k.c.get("isNew", false):
		_new_badge(k)


## A gold NEW! ribbon pops onto the card's corner.
func _new_badge(k: Dictionary) -> void:
	var root: Control = k.root
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.GOLD
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.shadow_color = Color(UI.GOLD, 0.6)
	sb.shadow_size = 12
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label("NEW!", 26, Color("1a1200"), true)
	l.label_settings.outline_size = 0
	badge.add_child(l)
	root.add_child(badge)
	badge.reset_size()
	badge.pivot_offset = badge.size / 2
	badge.position = Vector2(-22, -18)
	badge.rotation = -0.22
	badge.scale = Vector2.ZERO
	var t := badge.create_tween()
	t.tween_property(badge, "scale", Vector2.ONE * 1.25, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(badge, "scale", Vector2.ONE, 0.12)
	var glint := badge.create_tween().set_loops()
	glint.tween_property(badge, "modulate", Color(1.35, 1.3, 1.1), 0.5)
	glint.tween_property(badge, "modulate", Color.WHITE, 0.5)
	Sfx.play("new_card")
	_sparkle(root.position + Vector2(20, 10), UI.GOLD, 24, 0.7)


# ── After the last card ──────────────────────────────────────────────────────

func _summary() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	_hide_hint()
	if _reveal_btn:
		_reveal_btn.visible = false
	_refresh_balance()
	_bottom = Control.new()
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bottom)
	var fresh := 0
	for k in _cards:
		if k.c.get("isNew", false):
			fresh += 1
	var y := 868.0
	var col: Dictionary = _result.get("collection", {}) if _result.get("collection") is Dictionary else {}
	if int(col.get("total", 0)) > 0:
		_collection_bar(int(col.owned) - fresh, int(col.owned), int(col.total), fresh, y)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_bottom.add_child(row)
	var cur := _pick_currency()
	if cur != "":
		var label := "OPEN ANOTHER  ·  %s" % ("FREE (%d LEFT)" % int(Game.player.get("free_packs", 0)) if cur == "free"
			else "%d KARAT" % COST.karat if cur == "karat" else "%d CB" % COST.contraband)
		var again := UI.button(label, _again, Vector2(560, 70), UI.GOLD)
		row.add_child(again)
		var pulse := again.create_tween().set_loops()
		pulse.tween_property(again, "modulate", Color(1.25, 1.2, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(again, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		row.add_child(UI.button("GET CONTRABAND", func(): Game.go("contraband"), Vector2(400, 70), UI.PURPLE))
	row.add_child(UI.button("DONE", _close, Vector2(240, 70)))
	row.reset_size()
	row.position = Vector2(960 - row.size.x / 2, y + 86)
	_bottom.modulate.a = 0.0
	create_tween().tween_property(_bottom, "modulate:a", 1.0, 0.3)


## The clan's collection: the bar fills from before to after, ticking for each new card.
func _collection_bar(before: int, after: int, total: int, fresh: int, y: float) -> void:
	var w := 760.0
	var x := 960.0 - w / 2
	var head := UI.label("%s COLLECTION" % str(pack.get("label", "")).to_upper(), 20, _clan_col.lightened(0.3), true)
	head.position = Vector2(x, y)
	_bottom.add_child(head)
	var count := UI.label("%d / %d" % [before, total], 20, Color.WHITE, true)
	count.size = Vector2(200, 28)
	count.position = Vector2(x + w - 200, y)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bottom.add_child(count)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.1)
	track.position = Vector2(x, y + 32)
	track.size = Vector2(w, 14)
	_bottom.add_child(track)
	var fill := ColorRect.new()
	fill.color = _clan_col
	fill.size = Vector2(w * before / maxf(1.0, total), 14)
	track.add_child(fill)
	if fresh <= 0:
		count.text = "%d / %d" % [after, total]
		return
	var plus := UI.label("+%d NEW" % fresh, 20, UI.GOLD, true)
	plus.position = Vector2(x + w + 18, y + 24)
	plus.modulate.a = 0.0
	_bottom.add_child(plus)
	var t := create_tween()
	t.tween_interval(0.3)
	for i in fresh:
		var n := before + i + 1
		t.tween_property(fill, "size:x", w * n / maxf(1.0, total), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_callback(func():
			count.text = "%d / %d" % [n, total]
			Sfx.play("click", 1.0 + 0.2 * i, -4.0))
	t.tween_property(plus, "modulate:a", 1.0, 0.2)
	if after >= total:
		t.tween_callback(func():
			_pop_word("COLLECTION COMPLETE!", UI.GOLD, Vector2(960, y - 40), 48)
			_confetti(Vector2(960, y), [_clan_col, UI.GOLD, Color.WHITE], 120)
			Sfx.play("victory"))


## Free packs first, then the currency they just used, then whatever they can afford ("" if none).
func _pick_currency() -> String:
	var can := {
		"free": int(Game.player.get("free_packs", 0)) > 0,
		"karat": int(Game.player.get("karat", 0)) >= COST.karat,
		"contraband": int(Game.player.get("contraband", 0)) >= COST.contraband,
	}
	for c in ["free", currency, "karat", "contraband"]:
		if can.get(c, false):
			return c
	return ""


func _again() -> void:
	if _phase != Phase.DONE or _buying:
		return
	var cur := _pick_currency()
	if cur == "":
		return
	_buying = true
	currency = cur
	Sfx.play("click")
	another.emit(cur)


func _close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25)
	await t.finished
	closed.emit()
	queue_free()


# ── Words on screen ──────────────────────────────────────────────────────────

func _show_hint(text: String, sub: String) -> void:
	_hide_hint()
	_hint = UI.label(text, 30, Color.WHITE, true)
	_hint.size = Vector2(1920, 40)
	_hint.position = Vector2(0, 852)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_sub = UI.label(sub, 18, UI.MUTED)
	_hint_sub.size = Vector2(1920, 26)
	_hint_sub.position = Vector2(0, 894)
	_hint_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [_hint, _hint_sub]:
		l.modulate.a = 0.0
		_ui.add_child(l)
		var t: Tween = l.create_tween()
		t.tween_property(l, "modulate:a", 1.0, 0.3)
	var breathe := _hint.create_tween().set_loops()
	breathe.tween_property(_hint, "modulate:a", 0.55, 0.9).set_delay(0.3)
	breathe.tween_property(_hint, "modulate:a", 1.0, 0.9)


func _hide_hint() -> void:
	for l in [_hint, _hint_sub]:
		if l and is_instance_valid(l):
			var t: Tween = l.create_tween()
			t.tween_property(l, "modulate:a", 0.0, 0.2)
			t.tween_callback(l.queue_free)
	_hint = null
	_hint_sub = null


## "RARE" pops up over a card and floats away.
func _pop_word(text: String, col: Color, at: Vector2, font_size: int) -> void:
	var l := UI.label(text, font_size, col.lightened(0.2), true)
	l.size = Vector2(900, font_size + 20)
	l.position = at - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.label_settings.outline_size = 8
	l.scale = Vector2.ONE * 2.2
	_ui.add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(l, "position:y", l.position.y - 40.0, 0.5)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


## EPIC! slams in under the card (with a clan-coloured echo behind it) and the card's clan and name.
func _slam(word: String, col: Color, clan: Color, c: Dictionary) -> Array:
	var y := 836.0
	var echo := UI.label(word, 140, Color(clan, 0.7), true)
	var main := UI.label(word, 140, col.lightened(0.35), true)
	for l in [echo, main]:
		l.size = Vector2(1920, 160)
		l.position = Vector2(0, y - 80)
		l.pivot_offset = l.size / 2
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.label_settings.outline_size = 14
		l.scale = Vector2.ONE * 2.6
		_ui.add_child(l)
	echo.position += Vector2(8, 6)
	var info := CardDB.get_card(str(c.get("art_url", c.get("cardId", ""))))
	var clan_name := str(info.get("clanName", ""))
	var name := str(c.get("name", "")).strip_edges().to_upper()
	var sub := UI.label(("%s  ·  %s" % [clan_name.to_upper(), name]) if clan_name != "" else name, 34, clan.lightened(0.35), true)
	sub.size = Vector2(1920, 44)
	sub.position = Vector2(0, y + 84)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.0
	_ui.add_child(sub)
	var t := create_tween().set_parallel()
	t.tween_property(main, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(echo, "scale", Vector2.ONE * 1.04, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(sub, "modulate:a", 1.0, 0.3).set_delay(0.15)
	t.chain().tween_property(main, "scale", Vector2.ONE * 1.06, 2.0)
	return [echo, main, sub]


func _clan_of(c: Dictionary) -> Color:
	var hex := str(CardDB.get_card(str(c.get("art_url", c.get("cardId", "")))).get("clanColor", ""))
	return Color(hex) if hex.begins_with("#") else _clan_col


# ── Effects ──────────────────────────────────────────────────────────────────

func _stage_to(glow: float, rays: float, secs: float) -> void:
	var g0: float = _stage_mat.get_shader_parameter("glow")
	var r0: float = _stage_mat.get_shader_parameter("rays")
	var t := create_tween().set_parallel()
	t.tween_method(func(v: float): _stage_mat.set_shader_parameter("glow", v), g0, glow, secs)
	t.tween_method(func(v: float): _stage_mat.set_shader_parameter("rays", v), r0, rays, secs)


## Spike a full-screen effect and let it fall back to zero.
func _pulse(param: String, peak: float, secs: float) -> void:
	_fx[param] = maxf(_fx[param], peak)
	create_tween().tween_method(func(x: float): _fx[param] = x, _fx[param], 0.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A ripple of distortion racing out from a point.
func _shockwave(at: Vector2, strength: float) -> void:
	var uv := (get_viewport().get_canvas_transform() * (global_position + at)) / get_viewport().get_visible_rect().size
	_post_mat.set_shader_parameter("wave_center", uv)
	_fx.wave_strength = strength
	var t := create_tween().set_parallel()
	t.tween_method(func(v: float): _post_mat.set_shader_parameter("wave_radius", v), 0.0, 1.3, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): _fx.wave_strength = v, strength, 0.0, 0.75)


func _flash(col: Color, alpha: float, secs: float) -> void:
	var fx := clampf(float(Game.settings.get("screen_fx", 1.0)), 0.0, 1.0)
	if fx <= 0.0:
		return
	var r := ColorRect.new()
	r.color = Color(col, alpha * fx)
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(r)
	_ui.move_child(r, 0)
	var t := r.create_tween()
	t.tween_property(r, "color:a", 0.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(r.queue_free)


func _ring(at: Vector2, col: Color, r0: float, r1: float, secs: float, width: float) -> void:
	var ring := Control.new()
	ring.position = at
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.material = _add
	var st := {"r": r0, "a": 1.0}
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, st.r, 0.0, TAU, 96, Color(col, col.a * st.a), maxf(1.0, width * st.a), true))
	_layer.add_child(ring)
	var t := ring.create_tween()
	t.tween_method(func(v: float):
		st.r = lerpf(r0, r1, v)
		st.a = 1.0 - v
		ring.queue_redraw(), 0.0, 1.0, secs).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_callback(ring.queue_free)


## A one-shot burst of glowing dots.
func _emitter(col: Color, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot_tex()
	p.material = _add
	p.amount = amount
	p.lifetime = life
	p.one_shot = false
	p.explosiveness = 0.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.5))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	p.emitting = true
	return p


func _sparkle(at: Vector2, col: Color, amount: int, speed := 1.0) -> void:
	var p := _emitter(col, amount, 0.9)
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 160.0 * speed
	p.initial_velocity_max = 560.0 * speed
	p.damping_min = 250.0
	p.damping_max = 450.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_max = 1.3
	_layer.add_child(p)
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## Light rushing in to a point from all around, for `secs`.
func _converge(at: Vector2, col: Color, amount: int, secs: float) -> void:
	var p := _emitter(col, amount, 0.55)
	p.position = at
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 360.0
	p.gravity = Vector2.ZERO
	p.radial_accel_min = -2500.0
	p.radial_accel_max = -2100.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.85, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), col.lightened(0.4), col.lightened(0.6), Color(col, 0.0)])
	p.color_ramp = g
	_layer.add_child(p)
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false)
	get_tree().create_timer(secs + 0.7).timeout.connect(p.queue_free)


func _confetti(at: Vector2, colors: Array, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = _confetti_tex()
	p.position = at
	p.amount = amount
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.92
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 450.0
	p.initial_velocity_max = 1150.0
	p.gravity = Vector2(0, 1100)
	p.damping_min = 60.0
	p.damping_max = 160.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var pick := Gradient.new()
	pick.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / colors.size())
		cols.append(colors[i])
	pick.offsets = offs
	pick.colors = cols
	p.color_initial_ramp = pick
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.emitting = true
	_layer.add_child(p)
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


## A puff where a card lands.
func _dust(at: Vector2) -> void:
	var p := _emitter(Color(0.8, 0.8, 0.9), 14, 0.6)
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(CARD.x * 0.45, 4)
	p.direction = Vector2.UP
	p.spread = 60.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2.ZERO
	p.damping_min = 120.0
	p.damping_max = 200.0
	_layer.add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Motes of light drifting up through the dark, all the time.
func _ambient() -> void:
	var p := _emitter(Color(_clan_col, 0.45), 70, 9.0)
	p.position = Vector2(960, 1110)
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1000, 30)
	p.direction = Vector2.UP
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 130.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.7
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = g
	p.color = Color(_clan_col.lightened(0.3), 0.5)
	add_child(p)


## An additive glow: a soft light of this colour (alpha = brightness).
func _glow(col: Color, sz: Vector2, tex: Texture2D = null) -> TextureRect:
	var g := TextureRect.new()
	g.texture = tex if tex else _soft_tex()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.size = sz
	g.pivot_offset = sz / 2
	g.modulate = col
	g.material = _add
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


static func _gradient_tex(key: String, fill: int, from: Vector2, to: Vector2, w: int, h: int, stops: Array) -> Texture2D:
	if not _tex.has(key):
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for s in stops:
			offs.append(s[0])
			cols.append(Color(1, 1, 1, s[1]))
		g.offsets = offs
		g.colors = cols
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = fill
		t.fill_from = from
		t.fill_to = to
		t.width = w
		t.height = h
		_tex[key] = t
	return _tex[key]


static func _soft_tex() -> Texture2D:
	return _gradient_tex("soft", GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.0, 0.5), 128, 128, [[0.0, 1.0], [0.3, 0.4], [1.0, 0.0]])


static func _dot_tex() -> Texture2D:
	return _gradient_tex("dot", GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.0, 0.5), 32, 32, [[0.0, 1.0], [0.25, 0.8], [1.0, 0.0]])


## Bright along its middle, fading up and down (the seam).
static func _line_tex() -> Texture2D:
	return _gradient_tex("line", GradientTexture2D.FILL_LINEAR, Vector2(0.5, 0.0), Vector2(0.5, 1.0), 8, 64, [[0.0, 0.0], [0.5, 1.0], [1.0, 0.0]])


## Brightest at the middle of its bottom edge, fading up and to the sides (the light out of the pack).
static func _beam_tex() -> Texture2D:
	return _gradient_tex("beam", GradientTexture2D.FILL_RADIAL, Vector2(0.5, 1.0), Vector2(0.5, 0.0), 64, 128, [[0.0, 1.0], [0.4, 0.3], [1.0, 0.0]])


static func _confetti_tex() -> Texture2D:
	if not _tex.has("confetti"):
		var img := Image.create(12, 7, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_tex["confetti"] = ImageTexture.create_from_image(img)
	return _tex["confetti"]
