class_name ArenaLife
extends Node2D
## An arena coming alive, one layer at a time, from its data/arenas.json "fx" list (positions and
## rectangles in the picture's pixels; the picture covers the screen, cropped). duel.gd's _arena_fx
## makes the older kinds (pool, dust, embers, twinkle, ...) and hands these ones here:
##   flame / glow   a light with its own rhythm ("mode": flame, breathe, pulse, screen, blink)
##   fog            mist, smoke or cloud shadows drifting over a rectangle ("frame": hugging its edges)
##   water / heat / sway / glitter   part of the picture moving: rippling water, shimmering heat,
##                  cloth and leaves swaying, ice and snow glittering (shaders/arena_warp.gdshader)
##   beam           a floodlight sweeping back and forth
##   rain / snow / sand / leaves     weather blowing across
##   motes          fireflies, spores or ghost lights wandering and blinking
##   bubbles        rising in a tank
##   bats           a few bats flapping across now and then
##   lightning      a far-off flash, now and then
##   koi            fish swimming under the water, wandering, their tails swishing
##   ripples        rings spreading on water: where a spout pours in, and now and then anywhere in "rect"
## The screen effects setting (Game.settings.screen_fx) thins the particles out.

const GLOW := preload("res://shaders/arena_glow.gdshader")
const FOG := preload("res://shaders/arena_fog.gdshader")
const WARP := preload("res://shaders/arena_warp.gdshader")
const BEAM := preload("res://shaders/arena_beam.gdshader")
const GLOW_MODES := {"breathe": 0, "flame": 1, "pulse": 2, "screen": 3, "blink": 4}
const WARP_MODES := {"water": 0, "heat": 1, "sway": 2, "glitter": 3}

var _tex: Texture2D
var _ts := Vector2(1536, 1024)
var _k := 1.0
var _tint := Color.WHITE
var _level := 1.0
var _add: CanvasItemMaterial

static var _textures := {}


func setup(tex: Texture2D, tint: Color, level: float) -> ArenaLife:
	_tex = tex
	_ts = tex.get_size()
	_k = maxf(1920.0 / _ts.x, 1080.0 / _ts.y)
	_tint = tint
	_level = level
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return self


static func handles(kind: String) -> bool:
	return kind in ["flame", "glow", "fog", "water", "heat", "sway", "glitter", "beam", "rain", "snow", "sand",
		"leaves", "motes", "bubbles", "bats", "lightning", "koi", "ripples"]


func add(e: Dictionary) -> void:
	match str(e.get("kind", "")):
		"flame":
			_glow(e, "flame")
		"glow":
			_glow(e, str(e.get("mode", "breathe")))
		"fog":
			_fog(e)
		"water", "heat", "sway", "glitter":
			_warp(e)
		"beam":
			_beam(e)
		"rain":
			_rain(e)
		"snow":
			_snow(e)
		"sand":
			_sand(e)
		"leaves":
			_leaves(e)
		"motes":
			_motes(e)
		"bubbles":
			_bubbles(e)
		"bats":
			_bats(e)
		"lightning":
			_lightning(e)
		"koi":
			_koi(e)
		"ripples":
			_ripples(e)


# ── Where things are ────────────────────────────────────────────────────────

func _pt(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) * _k - (_ts * _k - Vector2(1920, 1080)) / 2.0


func _rect(r) -> Rect2:
	return Rect2(_pt([r[0], r[1]]), Vector2(float(r[2]), float(r[3])) * _k)


## The whole screen (weather that isn't tied to one spot).
func _screen_rect(e: Dictionary) -> Rect2:
	return _rect(e.rect) if e.has("rect") else Rect2(Vector2(-60, -60), Vector2(2040, 1200))


func _col(e: Dictionary, fallback := "#ffffff") -> Color:
	return Color(str(e.get("color", fallback)))


func _rect_node(r: Rect2, mat: ShaderMaterial) -> ColorRect:
	var n := ColorRect.new()
	n.position = r.position
	n.size = r.size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.material = mat
	add_child(n)
	return n


# ── Lights ──────────────────────────────────────────────────────────────────

## One light, or one per point ("at": [x, y] or "points": [[x, y], ...]), "r" its radius.
func _glow(e: Dictionary, mode: String) -> void:
	var points: Array = e.get("points", [e.get("at", [0, 0])])
	var r := float(e.get("r", 70)) * _k
	var col := _col(e, "#ffb85c")
	for p in points:
		var m := ShaderMaterial.new()
		m.shader = GLOW
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("mode", int(GLOW_MODES.get(mode, 0)))
		m.set_shader_parameter("strength", float(e.get("strength", 0.42 if mode == "flame" else 0.3)))
		m.set_shader_parameter("speed", float(e.get("speed", 1.0)) * randf_range(0.85, 1.15))
		m.set_shader_parameter("seed", randf() * 100.0)
		m.set_shader_parameter("core", float(e.get("core", 0.35 if mode == "flame" else 0.0)))
		var rr: float = r * float(p[2]) if p.size() > 2 else r   # ([x, y, size] for one bigger or smaller)
		_rect_node(Rect2(_pt(p) - Vector2.ONE * rr, Vector2.ONE * rr * 2.0), m)


func _beam(e: Dictionary) -> void:
	var len := float(e.get("length", 700)) * _k
	var m := ShaderMaterial.new()
	m.shader = BEAM
	m.set_shader_parameter("color", _col(e, "#fff4d6"))
	m.set_shader_parameter("strength", float(e.get("strength", 0.16)))
	m.set_shader_parameter("angle", deg_to_rad(float(e.get("angle", 90))))
	m.set_shader_parameter("sweep", deg_to_rad(float(e.get("sweep", 14))))
	m.set_shader_parameter("speed", float(e.get("speed", 0.25)))
	m.set_shader_parameter("width", deg_to_rad(float(e.get("width", 13))))
	m.set_shader_parameter("seed", randf() * 10.0)
	_rect_node(Rect2(_pt(e.at) - Vector2.ONE * len, Vector2.ONE * len * 2.0), m)


func _lightning(e: Dictionary) -> void:
	var flash := ColorRect.new()
	flash.size = Vector2(1920, 1080)
	flash.color = Color(_col(e, "#c9d4ff"), 0.0)
	flash.material = _add
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var every := float(e.get("every", 14.0))
	while is_inside_tree():
		await get_tree().create_timer(randf_range(every * 0.5, every * 1.5)).timeout
		if not is_inside_tree():
			return
		var peak := float(e.get("strength", 0.35)) * clampf(_level, 0.3, 1.0)
		var t := flash.create_tween()
		t.tween_property(flash, "color:a", peak, 0.05)
		t.tween_property(flash, "color:a", peak * 0.2, 0.08)
		t.tween_property(flash, "color:a", peak * 0.8, 0.05)   # (the second, brighter stroke)
		t.tween_property(flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# ── Mist and moving picture ─────────────────────────────────────────────────

func _fog(e: Dictionary) -> void:
	var r := _rect(e.get("rect", [0, 0, _ts.x, _ts.y]))
	var m := ShaderMaterial.new()
	m.shader = FOG
	m.set_shader_parameter("color", _col(e, "#9a98b8"))
	m.set_shader_parameter("density", float(e.get("density", 0.35)))
	var d: Array = e.get("drift", [0.03, 0.008])
	m.set_shader_parameter("drift", Vector2(float(d[0]), float(d[1])))
	m.set_shader_parameter("scale", float(e.get("scale", 1.0)))
	m.set_shader_parameter("rect_size", r.size)
	m.set_shader_parameter("frame", float(e.get("frame", 0.0)))
	m.set_shader_parameter("seed", randf() * 10.0)
	_rect_node(r, m)


func _warp(e: Dictionary) -> void:
	var reg: Array = e.rect
	var m := ShaderMaterial.new()
	m.shader = WARP
	m.set_shader_parameter("picture", _tex)
	m.set_shader_parameter("tex_size", _ts)
	m.set_shader_parameter("region", Vector4(float(reg[0]), float(reg[1]), float(reg[2]), float(reg[3])))
	m.set_shader_parameter("tint", _tint)
	m.set_shader_parameter("mode", int(WARP_MODES.get(str(e.kind), 0)))
	m.set_shader_parameter("amp", float(e.get("amp", {"water": 3.0, "heat": 1.6, "sway": 2.5, "glitter": 0.0}.get(str(e.kind), 2.0))))
	m.set_shader_parameter("speed", float(e.get("speed", 1.0)))
	var f: Array = e.get("flow", [0, 0])
	m.set_shader_parameter("flow", Vector2(float(f[0]), float(f[1])))
	if e.has("key"):
		m.set_shader_parameter("key", Color(str(e.key)))
		m.set_shader_parameter("tol", float(e.get("tol", 0.2)))
	if e.has("cool"):
		m.set_shader_parameter("cool", float(e.cool))
	m.set_shader_parameter("sparkle", float(e.get("sparkle", 0.35 if str(e.kind) == "glitter" else 0.0)))
	m.set_shader_parameter("spark_color", _col(e, "#e8f4ff"))
	m.set_shader_parameter("anchor", float(e.get("anchor", 0.0)))
	m.set_shader_parameter("feather", float(e.get("feather", 24.0)))
	m.set_shader_parameter("seed", randf() * 10.0)
	_rect_node(_rect(reg), m)


# ── Particles ───────────────────────────────────────────────────────────────

static func _soft_dot() -> Texture2D:
	if not _textures.has("dot"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.width = 64
		t.height = 64
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.gradient = g
		_textures.dot = t
	return _textures.dot


## A soft streak (rain, blowing sand), pointing along +x so particles can align with their flight.
static func _streak() -> Texture2D:
	if not _textures.has("streak"):
		var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 64:
				var ax := 1.0 - absf(x - 40.0) / (40.0 if x < 40 else 24.0)
				var ay := 1.0 - absf(y - 3.5) / 4.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(ax, 0, 1) * clampf(ay, 0, 1)))
		_textures.streak = ImageTexture.create_from_image(img)
	return _textures.streak


## A leaf: a pointed oval with a darker vein.
static func _leaf() -> Texture2D:
	if not _textures.has("leaf"):
		var img := Image.create(24, 12, false, Image.FORMAT_RGBA8)
		for y in 12:
			for x in 24:
				var u := (x - 11.5) / 12.0
				var v := (y - 5.5) / 6.0
				var w := 1.0 - u * u
				var inside := absf(v) < w * 0.95
				if inside:
					var shade := 0.8 if absf(v) < 0.12 else 1.0
					img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
		_textures.leaf = ImageTexture.create_from_image(img)
	return _textures.leaf


## A bubble: a thin bright ring with a highlight.
static func _ring() -> Texture2D:
	if not _textures.has("ring"):
		var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		for y in 24:
			for x in 24:
				var d := Vector2(x - 11.5, y - 11.5).length() / 11.5
				var a := clampf(1.0 - absf(d - 0.85) / 0.15, 0.0, 1.0) * 0.9 + clampf(1.0 - Vector2(x - 8.0, y - 8.0).length() / 3.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_textures.ring = ImageTexture.create_from_image(img)
	return _textures.ring


func _particles(area: Rect2, amount: int, tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.position = area.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = area.size / 2
	p.amount = maxi(1, roundi(amount * clampf(_level, 0.25, 1.0)))
	add_child(p)
	return p


func _fade(col: Color, peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.add_point(0.15, Color(col, peak))
	g.add_point(0.8, Color(col, peak))
	g.set_color(1, Color(col, 0.0))
	return g


## Rain streaking down at a slant (falls from above the screen, wraps in from the side the wind blows from).
func _rain(e: Dictionary) -> void:
	var wind := float(e.get("wind", 0.18))
	var area := Rect2(Vector2(-300, -140), Vector2(2520, 60))
	var p := _particles(area, int(e.get("amount", 150)), _streak())
	p.lifetime = 0.9
	p.preprocess = 1.0
	p.direction = Vector2(wind, 1.0).normalized()
	p.spread = 2.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 1300.0
	p.initial_velocity_max = 1650.0
	p.particle_flag_align_y = false
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.0
	p.color_ramp = _fade(_col(e, "#b8c4ff"), float(e.get("alpha", 0.28)))
	p.material = _add
	# (the streak points along +x: turn each to its flight)
	p.angle_min = rad_to_deg(Vector2(wind, 1.0).angle())
	p.angle_max = p.angle_min


func _snow(e: Dictionary) -> void:
	var wind := float(e.get("wind", 0.35))
	for layer in [0, 1]:   # far flakes: small and slow; near: bigger, softer, faster
		var area := Rect2(Vector2(-500, -80), Vector2(2700, 40))
		var p := _particles(area, int(e.get("amount", 160)) / (1 if layer == 0 else 3), _soft_dot())
		p.lifetime = 9.0 if layer == 0 else 5.5
		p.preprocess = p.lifetime
		p.direction = Vector2(wind, 1.0).normalized()
		p.spread = 14.0
		p.gravity = Vector2(0, 6)
		p.initial_velocity_min = 90.0 if layer == 0 else 180.0
		p.initial_velocity_max = 150.0 if layer == 0 else 260.0
		p.tangential_accel_min = -12.0
		p.tangential_accel_max = 12.0
		p.scale_amount_min = 0.05 if layer == 0 else 0.12
		p.scale_amount_max = 0.1 if layer == 0 else 0.22
		p.color_ramp = _fade(_col(e, "#f2f8ff"), 0.75 if layer == 0 else 0.5)


## Sand (or dust) blowing across in quick streaks.
func _sand(e: Dictionary) -> void:
	var r := _screen_rect(e)
	var dir := Vector2(1.0, float(e.get("rise", 0.05))).normalized()
	var p := _particles(Rect2(Vector2(r.position.x - 200, r.position.y), Vector2(40, r.size.y)), int(e.get("amount", 60)), _streak())
	p.lifetime = 2.6
	p.preprocess = 2.6
	p.direction = dir
	p.spread = 4.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 700.0
	p.initial_velocity_max = 1000.0
	p.angle_min = rad_to_deg(dir.angle())
	p.angle_max = p.angle_min
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.1
	p.color_ramp = _fade(_col(e, "#f5d29a"), float(e.get("alpha", 0.35)))


func _leaves(e: Dictionary) -> void:
	var r := _screen_rect(e)
	var p := _particles(Rect2(Vector2(r.position.x - 120, r.position.y), Vector2(40, r.size.y)), int(e.get("amount", 10)), _leaf())
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.direction = Vector2(1.0, 0.2).normalized()
	p.spread = 18.0
	p.gravity = Vector2(0, 8)
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 360.0
	p.tangential_accel_min = -30.0
	p.tangential_accel_max = 30.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var g := Gradient.new()   # (autumn colours, each leaf its own)
	g.set_color(0, Color(str(e.get("color", "#c9622e"))))
	g.set_color(1, Color(str(e.get("color2", "#7a3b1c"))))
	p.color_initial_ramp = g


## Fireflies, spores or ghost lights: wandering slowly, swelling and fading.
func _motes(e: Dictionary) -> void:
	var r := _screen_rect(e)
	var p := _particles(r, int(e.get("amount", 30)), _soft_dot())
	var life := float(e.get("life", 4.0))
	p.lifetime = life
	p.preprocess = life
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, -float(e.get("rise", 4.0)))
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = float(e.get("speed", 22.0))
	p.tangential_accel_min = -18.0
	p.tangential_accel_max = 18.0
	p.damping_min = 2.0
	p.damping_max = 6.0
	var size := float(e.get("size", 0.12))
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var col := _col(e, "#d9ff8a")
	var g := Gradient.new()   # (a blink or two in its life)
	g.set_color(0, Color(col, 0.0))
	g.add_point(0.2, Color(col, 1.0))
	g.add_point(0.35, Color(col, 0.15))
	g.add_point(0.55, Color(col, 0.95))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	p.material = _add


func _bubbles(e: Dictionary) -> void:
	for reg in e.get("rects", [e.get("rect", [0, 0, 10, 10])]):
		var r := _rect(reg)
		var p := _particles(Rect2(Vector2(r.position.x, r.end.y - 10), Vector2(r.size.x, 10)), int(e.get("amount", 10)), _ring())
		p.lifetime = r.size.y / 55.0
		p.preprocess = p.lifetime
		p.direction = Vector2(0, -1)
		p.spread = 6.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 70.0
		p.tangential_accel_min = -10.0
		p.tangential_accel_max = 10.0
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.6
		p.color_ramp = _fade(_col(e, "#c8ffd8"), 0.7)
		p.material = _add


# ── Creatures ───────────────────────────────────────────────────────────────

## Now and then a few bats flap across the screen, dark against the ground.
func _bats(e: Dictionary) -> void:
	var every := float(e.get("every", 16.0))
	while is_inside_tree():
		await get_tree().create_timer(randf_range(every * 0.5, every * 1.4)).timeout
		if not is_inside_tree():
			return
		var left := randf() < 0.5
		var y0 := randf_range(80, 1000)
		var y1 := clampf(y0 + randf_range(-380, 380), 40, 1040)
		for i in randi_range(1, 3):
			var bat := Node2D.new()
			var flap := randf() * TAU
			var size := randf_range(0.8, 1.25)
			bat.draw.connect(func():
				var w := sin(Time.get_ticks_msec() / 1000.0 * 16.0 + flap)   # wings up and down
				var tip := Vector2(30, -6 - 14 * w) * size
				var mid := Vector2(14, -2 - 6 * w) * size
				var body := Color(0.04, 0.03, 0.06, 0.85)
				for s in [-1.0, 1.0]:
					bat.draw_colored_polygon(PackedVector2Array([Vector2(0, -3) * size, Vector2(mid.x * s, mid.y), Vector2(tip.x * s, tip.y),
						Vector2(22 * s, 2) * size, Vector2(12 * s, 0) * size, Vector2(5 * s, 4) * size]), body)
				bat.draw_circle(Vector2(0, 0), 4.5 * size, body))
			bat.position = Vector2(-80.0 if left else 2000.0, y0 + i * randf_range(-50, 50))
			add_child(bat)
			var to := Vector2(2000.0 if left else -80.0, y1 + i * randf_range(-60, 60))
			var dur := randf_range(3.2, 4.6)
			var path := bat.create_tween().set_parallel()
			path.tween_property(bat, "position:x", to.x, dur).set_delay(i * 0.25)
			path.tween_property(bat, "position:y", to.y, dur).set_trans(Tween.TRANS_SINE).set_delay(i * 0.25)
			path.chain().tween_callback(bat.queue_free)
			_redraw_while(bat)


## Koi: "amount" fish wandering about "rect" (the pond), each one swimming to a new spot now and then.
func _koi(e: Dictionary) -> void:
	var area := _rect(e.rect)
	var palettes := [[Color("f7efe2"), Color("ff6a2a")], [Color("f7efe2"), Color("e8381f")], [Color("ffb03a"), Color("f7efe2")],
		[Color("f7efe2"), Color("1d1a22")], [Color("ff7a2e"), Color("ffd1a0")]]
	for i in int(e.get("amount", 4)):
		var fish := Koi.new()
		fish.area = area
		fish.k = _k
		fish.size = randf_range(0.8, 1.15) * float(e.get("size", 1.0))
		fish.colors = palettes[i % palettes.size()]
		fish.position = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		fish.heading = randf() * TAU
		add_child(fish)


class Koi extends Node2D:
	var area: Rect2
	var k := 1.0
	var size := 1.0
	var colors: Array = []
	var heading := 0.0
	var _goal := Vector2.ZERO
	var _speed := 0.0
	var _phase := randf() * TAU
	var _rest := 0.0
	var _marks: Array = []   # [where along it, how far off its middle, how big]

	func _ready() -> void:
		for j in randi_range(2, 3):
			_marks.append(Vector3(randf_range(0.12, 0.62), randf_range(-0.35, 0.35), randf_range(0.32, 0.5)))
		_pick()

	func _pick() -> void:
		var m := 60.0 * k
		_goal = Vector2(randf_range(area.position.x + m, area.end.x - m), randf_range(area.position.y + m, area.end.y - m))

	func _process(delta: float) -> void:
		var to := _goal - position
		if to.length() < 30.0 * k:
			_rest = randf_range(0.0, 2.5)   # (it idles a moment, then swims off)
			_pick()
		_rest = maxf(0.0, _rest - delta)
		var want := to.angle()
		heading = lerp_angle(heading, want, minf(1.0, delta * 0.9))
		var cruise := (0.0 if _rest > 0.0 else 34.0) * k * size
		_speed = lerpf(_speed, cruise, minf(1.0, delta * 0.8))
		position += Vector2.from_angle(heading) * _speed * delta
		_phase += delta * (2.0 + _speed / (8.0 * k))
		rotation = heading
		queue_redraw()

	## Its body, nose to tail along the x axis (head at +x), bending with the swish of its tail.
	func _spine(s: float) -> Vector2:
		var length := 64.0 * k * size
		return Vector2(length * (0.5 - s), sin(_phase - s * 3.2) * s * s * 7.0 * k * size)

	func _draw() -> void:
		var width := 11.0 * k * size
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in 13:
			var s := i / 12.0
			var c := _spine(s)
			var w := width * pow(sin(PI * clampf(s * 0.92 + 0.06, 0.0, 1.0)), 0.75) * (1.0 - s * 0.45)
			var n := (_spine(minf(1.0, s + 0.02)) - _spine(maxf(0.0, s - 0.02))).orthogonal().normalized()
			left.append(c + n * w)
			right.append(c - n * w)
		right.reverse()
		var body := left + right
		# its shadow on the pond floor, then the tail fin, the body and its patches
		var shade := PackedVector2Array()
		for p in body:
			shade.append(p + Vector2(5, 9) * k)
		draw_colored_polygon(shade, Color(0.05, 0.12, 0.12, 0.22))
		var tail := _spine(1.0)
		var bend := sin(_phase - 3.4) * 9.0 * k * size
		draw_colored_polygon(PackedVector2Array([_spine(0.9), tail + Vector2(-13 * k * size, -11 * k * size + bend),
			tail + Vector2(-6 * k * size, bend * 0.5), tail + Vector2(-13 * k * size, 11 * k * size + bend)]), Color(colors[0], 0.78))
		for side in [-1.0, 1.0]:   # pectoral fins, flapping a little
			var base := _spine(0.3)
			var flap := sin(_phase * 1.3) * 3.0 * k
			draw_colored_polygon(PackedVector2Array([base, base + Vector2(-9 * k * size, side * (14 * k * size + flap)), base + Vector2(-14 * k * size, side * 6 * k * size)]), Color(colors[0], 0.6))
		draw_colored_polygon(body, Color(colors[0], 0.8))
		for j in _marks.size():   # its markings: soft oval patches along its back
			var m: Vector3 = _marks[j]
			var at := _spine(m.x)
			draw_set_transform(at + Vector2(0, m.y * width), (_spine(m.x + 0.02) - _spine(m.x - 0.02)).angle(), Vector2(1.8, 0.85))
			draw_circle(Vector2.ZERO, width * m.z, Color(colors[1], 0.82))
			draw_set_transform(Vector2.ZERO)
		draw_circle(_spine(0.06) + Vector2(0, -3.5 * k * size), 1.4 * k, Color(0.05, 0.05, 0.08, 0.8))
		draw_circle(_spine(0.06) + Vector2(0, 3.5 * k * size), 1.4 * k, Color(0.05, 0.05, 0.08, 0.8))
		draw_polyline(left, Color(1, 1, 1, 0.18), 1.0, true)   # (light catching its back)


## Rings spreading on water: steadily where water pours in ("points"), and now and then anywhere in "rect"
## (a petal landing, a fish rising).
func _ripples(e: Dictionary) -> void:
	var col := _col(e, "#ffffff")
	var r := float(e.get("r", 40.0)) * _k
	for p in e.get("points", []):
		_ripple_loop(_pt(p), r, col, float(e.get("every", 0.9)), 0.0)
	if e.has("rect"):
		var area := _rect(e.rect)
		_ripple_loop(Vector2.ZERO, r * 0.8, col, float(e.get("drops", 2.2)) / maxf(0.25, _level), 1.0, area)


func _ripple_loop(at: Vector2, radius: float, col: Color, every: float, jitter: float, area := Rect2()) -> void:
	while is_inside_tree():
		var where := at if area.size == Vector2.ZERO else Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		var ring := Node2D.new()
		ring.position = where + Vector2(randf_range(-4, 4), randf_range(-3, 3)) * _k
		ring.scale = Vector2(1.0, 0.62)   # (seen from above at a slant)
		ring.material = _add
		var grow := [0.0]
		ring.draw.connect(func():
			for j in 2:
				var t: float = clampf(grow[0] - j * 0.18, 0.0, 1.0)
				if t > 0.0:
					ring.draw_arc(Vector2.ZERO, radius * t, 0.0, TAU, 40, Color(col, 0.42 * (1.0 - t)), 2.2, true))
		add_child(ring)
		var tw := ring.create_tween()
		tw.tween_method(func(v: float):
			grow[0] = v
			ring.queue_redraw(), 0.0, 1.25, 1.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(ring.queue_free)
		await get_tree().create_timer(every * randf_range(0.7, 1.3) + jitter * randf()).timeout


func _redraw_while(n: CanvasItem) -> void:
	while is_instance_valid(n) and n.is_inside_tree():
		n.queue_redraw()
		await get_tree().process_frame
