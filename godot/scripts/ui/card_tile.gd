class_name CardTile
extends Control
## A card in a menu grid: art with a rarity border, name, and optional corner badges.
## Left-click → pressed, right-click → zoomed. Lifts slightly on hover with a glow in its rarity's
## colour, and the art tilts in 3D toward the mouse (Epic and Legendary cards shimmer with foil);
## a light runs round the border of Rare and better cards. CardTile.cascade() deals a grid in.

signal pressed(tile: CardTile)
signal zoomed(tile: CardTile)
signal hovered(tile: CardTile)

var card: Dictionary = {}
var badge := ""          # top-right, e.g. "1/3"
var count_badge := ""    # bottom-left, e.g. "×2"
var dimmed := false: set = set_dimmed
var selected := false: set = set_selected   # outlined in gold (the Card Library's crafting pick)
var rest_rotation := 0.0: set = set_rest_rotation   # degrees: laid by hand on a table; it straightens on hover

var _art: TextureRect
var _name: Label
var _hover := false
var _overlay: Control
var _mat: ShaderMaterial
var _tilt := Vector2.ZERO
var _glow := 0.0          # 0..1: the hover glow
var _sweep: Control       # Rare+: the light running round the border

## A soft round dot (white, fading out): the sweep's streak is drawn with it, since textured rects
## batch into one draw call where circles each cost one (a grid of tiles redraws them every frame).
static var _dot: Texture2D = null


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.85))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 32
		t.height = 32
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_dot = t
	return _dot


## Deals tiles in one after another (a grid just filled or refiltered): each rises and fades in.
static func cascade(tiles: Array, delay := 0.0) -> void:
	var i := 0
	for t in tiles:
		if not t is Control or not is_instance_valid(t):
			continue
		var c: Control = t
		c.modulate.a = 0.0
		c.scale = Vector2.ONE * 0.86
		var tw := c.create_tween().set_parallel()
		var at := delay + minf(i * 0.022, 0.6)
		tw.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(at)
		tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


static func make(c: Dictionary, size := Vector2(150, 212)) -> CardTile:
	var t := CardTile.new()
	t.card = c
	t.custom_minimum_size = size
	t.size = size
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size / 2
	# (a grid lays its cells out straight, so the tilt goes back on after every layout)
	var box := get_parent() as Container
	if box and rest_rotation != 0.0:
		box.sort_children.connect(func(): if not _hover: rotation_degrees = rest_rotation)
	var art_tex := UI.card_art(card)
	_art = UI.texture_rect(art_tex, size - Vector2(8, 8))
	_art.position = Vector2(4, 4)
	add_child(_art)
	if art_tex:
		_mat = UI.card_material(_art.size, int(card.get("rarity", 1)))
		_art.material = _mat
	set_process(false)
	if art_tex == null:
		_name = UI.label(str(card.get("name", "?")), 18, Color.WHITE, true)
		_name.size = size - Vector2(16, 16)
		_name.position = Vector2(8, 8)
		_name.autowrap_mode = TextServer.AUTOWRAP_WORD
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_name)
	_overlay = Control.new()
	_overlay.size = size
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	if int(card.get("rarity", 1)) >= 3:
		_sweep = Control.new()
		_sweep.size = size
		_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sweep.draw.connect(_draw_sweep)
		add_child(_sweep)
		# (redrawn once a frame; asking for a redraw from inside its own draw would never end)
		get_tree().process_frame.connect(_sweep.queue_redraw)
	mouse_entered.connect(func():
		_hover = true
		hovered.emit(self)
		set_process(true)
		Sfx.play("hover", randf_range(1.15, 1.3), -14.0)
		create_tween().tween_property(self, "scale", Vector2.ONE * 1.06, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if rest_rotation != 0.0:
			create_tween().tween_property(self, "rotation_degrees", 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		create_tween().tween_property(self, "_glow", 1.0, 0.15)
		z_index = 2)
	mouse_exited.connect(func():
		_hover = false
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.14)
		if rest_rotation != 0.0:
			create_tween().tween_property(self, "rotation_degrees", rest_rotation, 0.3).set_trans(Tween.TRANS_SINE)
		var t := create_tween()
		t.tween_property(self, "_glow", 0.0, 0.2)
		t.tween_callback(func(): z_index = 0))
	set_dimmed(dimmed)


func _process(delta: float) -> void:
	queue_redraw()   # (the glow)
	if _mat == null:
		if not _hover and _glow <= 0.0:
			set_process(false)
		return
	var target := Vector2.ZERO
	if _hover:
		var m := ((get_local_mouse_position() - size / 2) / (size / 2)).clamp(-Vector2.ONE, Vector2.ONE)
		target = Vector2(-m.x, m.y) * 12.0
	_tilt = _tilt.lerp(target, 1.0 - exp(-12.0 * delta))
	_mat.set_shader_parameter("y_rot", _tilt.x)
	_mat.set_shader_parameter("x_rot", _tilt.y)
	_mat.set_shader_parameter("glare", clampf(_tilt.length() / 12.0, 0.0, 1.0))
	if not _hover and _tilt.length() < 0.05 and _glow <= 0.0:
		set_process(false)


## The light running round a Rare+ border: a streak brightest at its head.
func _draw_sweep() -> void:
	if not is_visible_in_tree():
		return
	var r := int(card.get("rarity", 1))
	var col := UI.rarity_color(r)
	var per := 2.0 * (size.x + size.y)
	var speed := 0.16 if r >= 5 else 0.12 if r == 4 else 0.08
	var head := fmod(Time.get_ticks_msec() / 1000.0 * speed + float(hash(str(card.get("id", "")))) / 4294967296.0, 1.0) * per
	var tail := 70.0 if r >= 4 else 50.0
	var dot := _soft_dot()
	for k in 10:
		var p := _perimeter_point(fposmod(head - k * tail / 10.0, per))
		var rad := (3.2 - k * 0.22) * 1.6   # (the dot fades out towards its edge, so it's drawn a little larger)
		_sweep.draw_texture_rect(dot, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false,
			Color(col.lightened(0.5), 0.9 * (1.0 - k / 10.0)))


## A point at distance d along the border, clockwise from the top-left corner.
func _perimeter_point(d: float) -> Vector2:
	var w := size.x
	var h := size.y
	if d < w:
		return Vector2(d, 0)
	d -= w
	if d < h:
		return Vector2(w, d)
	d -= h
	if d < w:
		return Vector2(w - d, h)
	return Vector2(0, h - (d - w))


func set_rest_rotation(v: float) -> void:
	rest_rotation = v
	rotation_degrees = v


func set_dimmed(v: bool) -> void:
	dimmed = v
	modulate = Color(0.45, 0.45, 0.5) if v else Color.WHITE
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func refresh() -> void:
	if _overlay:
		_overlay.queue_redraw()


var _down_at := Vector2(-1, -1)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			# A click is press + release in place (a drag doesn't count)
			if e.pressed:
				_down_at = e.position
				create_tween().tween_property(self, "scale", Vector2.ONE * 0.97, 0.05)
			elif _down_at.distance_to(e.position) < 12 and not get_viewport().gui_is_dragging():
				var t := create_tween()
				t.tween_property(self, "scale", Vector2.ONE * 1.1, 0.07)
				t.tween_property(self, "scale", Vector2.ONE * (1.06 if _hover else 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				pressed.emit(self)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			zoomed.emit(self)
			accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _glow > 0.0:   # the hover glow: soft rings in the rarity's colour
		var gc := UI.rarity_color(card.get("rarity"))
		for k in 6:
			draw_rect(r.grow(3.0 + k * 3.0), Color(gc, 0.1 * _glow * (1.0 - k / 6.0)), false, 3.0)
	draw_rect(Rect2(r.position + Vector2(4, 6 + 4 * _glow), r.size), Color(0, 0, 0, 0.4 + 0.2 * _glow))
	draw_rect(r, Color("0d1020"))
	var col := UI.rarity_color(card.get("rarity"))
	draw_rect(r, UI.GOLD if _hover or selected else col, false, 6.0 if selected else 4.0 if _hover else 3.0)
	if selected:
		draw_rect(r.grow(5), Color(UI.GOLD, 0.45), false, 3.0)


func _draw_overlay() -> void:
	var f := UI.font()
	UI.draw_level_stars(_overlay, Vector2(size.x / 2, 3.0), CardDB.striver_stage(card), clampf(size.x / 18.0, 6.0, 11.0))
	if badge != "":   # (on the art's top right corner, just under the name strip, so the name stays readable)
		var br := Rect2(size.x - 64, size.y * 0.135, 58, 28)
		_overlay.draw_style_box(_pill(UI.GOLD), br)
		_overlay.draw_string(f, br.position + Vector2(0, 22), badge, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 20, UI.GOLD)
	if count_badge != "":
		var cr := Rect2(6, size.y - 34, 56, 28)
		_overlay.draw_style_box(_pill(UI.BLUE), cr)
		_overlay.draw_string(f, cr.position + Vector2(0, 22), count_badge, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 20, UI.BLUE)


static func _pill(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.06, 0.88)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(col, 0.35)
	sb.shadow_size = 4
	return sb
