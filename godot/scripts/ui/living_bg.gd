extends Control
## Full-screen menu backdrop that never sits still: the art drifts and follows the mouse a
## little (parallax), rain streaks across it, warm embers float up, and a vignette pulls the
## eye to the middle. Built by UI.background().

const PARALLAX := 22.0   # px the art shifts toward the mouse at the screen edge
const OVERSCAN := 1.07   # art is drawn slightly larger so the drift never shows an edge

var _art: TextureRect
var _t := 0.0


func setup(texture: Texture2D, dim: float) -> Control:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_art = TextureRect.new()
	_art.texture = texture
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.size = size * OVERSCAN
	_art.position = -(_art.size - size) / 2
	_art.pivot_offset = _art.size / 2
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, dim)
	veil.size = size
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	add_child(_rain())
	add_child(_embers())
	add_child(_vignette())
	return self


func _process(delta: float) -> void:
	_t += delta
	var m := (get_global_mouse_position() / size - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	var target := -(_art.size - size) / 2 - m * PARALLAX * 2.0 + Vector2(sin(_t * 0.11), cos(_t * 0.07)) * 6.0
	_art.position = _art.position.lerp(target, 1.0 - exp(-3.0 * delta))
	_art.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 0.17))


func _rain() -> CPUParticles2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.8, 0.88, 1.0, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var streak := GradientTexture2D.new()
	streak.gradient = g
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	streak.width = 2
	streak.height = 46
	var p := CPUParticles2D.new()
	p.texture = streak
	p.amount = 140
	p.lifetime = 0.8
	p.preprocess = 1.0
	p.position = Vector2(1060, -60)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1300, 10)
	p.direction = Vector2(-0.22, 1.0)
	p.spread = 2.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 1300.0
	p.initial_velocity_max = 1800.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color = Color(1, 1, 1, 0.13)
	return p


func _embers() -> CPUParticles2D:
	var dot_g := Gradient.new()
	dot_g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var dot := GradientTexture2D.new()
	dot.gradient = dot_g
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 16
	dot.height = 16
	var p := CPUParticles2D.new()
	p.texture = dot
	p.amount = 26
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = Vector2(960, 1110)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(980, 10)
	p.direction = Vector2(0.15, -1.0)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 0.6, 0.25, 0.0), Color(1, 0.65, 0.3, 0.55), Color(1, 0.4, 0.6, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = ramp
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	return p


func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.62)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 256
	t.height = 144
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
