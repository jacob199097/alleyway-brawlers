extends StyleBox
## The game's panel and button look, drawn in code: a machined plate with two cut corners (as the menu's
## metal signs have), a fill that falls from light to dark, a lit top edge, an edge that catches the light
## at the top, and a bright chip on each cut. UI.box() makes them; it takes the place of StyleBoxFlat and
## keeps its names (bg_color, border_color, shadow_*, set_border_width_all, set_corner_radius_all), so the
## screens set them as before.
##   radius 0-3: a plain rectangle · radius ≥ half the box: a pill or a circle (bars, dots, badges) ·
##   anything else: the cut plate, its cuts growing with the radius

@export var bg_color := Color(0.03, 0.03, 0.08, 0.92): set = _set_bg
@export var border_color := Color(1, 1, 1, 0.12): set = _set_border
@export var border_width := 2.0: set = _set_width
@export var radius := 10.0: set = _set_radius
@export var shadow_color := Color(0, 0, 0, 0): set = _set_shadow_color
@export var shadow_size := 0: set = _set_shadow_size
@export var shadow_offset := Vector2.ZERO: set = _set_shadow_offset
@export var draw_center := true: set = _set_center
## A bar of the edge's colour along the bottom (buttons): its height
@export var bar := 0.0: set = _set_bar
## How strongly the fill falls from light to dark (0: flat)
@export var depth := 1.0: set = _set_depth
## The bright chips on the cuts and the lit top edge (off for bars and small marks)
@export var trim := true: set = _set_trim

## StyleBoxFlat's name for the radius (glass() reads it)
var corner_radius_top_left: int:
	get: return int(radius)
	set(v): radius = v


func _set_bg(v: Color) -> void: bg_color = v; emit_changed()
func _set_border(v: Color) -> void: border_color = v; emit_changed()
func _set_width(v: float) -> void: border_width = v; emit_changed()
func _set_radius(v: float) -> void: radius = v; emit_changed()
func _set_shadow_color(v: Color) -> void: shadow_color = v; emit_changed()
func _set_shadow_size(v: int) -> void: shadow_size = v; emit_changed()
func _set_shadow_offset(v: Vector2) -> void: shadow_offset = v; emit_changed()
func _set_center(v: bool) -> void: draw_center = v; emit_changed()
func _set_bar(v: float) -> void: bar = v; emit_changed()
func _set_depth(v: float) -> void: depth = v; emit_changed()
func _set_trim(v: bool) -> void: trim = v; emit_changed()


func set_border_width_all(w: float) -> void:
	border_width = w


func set_corner_radius_all(r: float) -> void:
	radius = r


## The big cut (top-left and bottom-right) of a plate this size.
static func cut_for(r: float, size: Vector2) -> float:
	var m := minf(size.x, size.y)
	if r < 4.0 or r * 2.0 >= m - 1.0:
		return 0.0
	return minf(r + 4.0, m * 0.3)


## The plate's outline, clockwise from the top-left; g grows it (negative: inset).
func _outline(rect: Rect2, g: float) -> PackedVector2Array:
	var r := rect.grow(g)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var m := minf(rect.size.x, rect.size.y)
	var pts := PackedVector2Array()
	if radius * 2.0 >= m - 1.0 and radius >= 2.0:   # a pill or a circle
		var rad := maxf(0.5, m / 2.0 + g)
		for corner in [[x0 + rad, y0 + rad, PI], [x1 - rad, y0 + rad, PI * 1.5], [x1 - rad, y1 - rad, 0.0], [x0 + rad, y1 - rad, PI * 0.5]]:
			for i in 7:
				var a: float = corner[2] + PI * 0.5 * i / 6.0
				pts.append(Vector2(corner[0] + cos(a) * rad, corner[1] + sin(a) * rad))
		return pts
	var big := cut_for(radius, rect.size)
	var small := 0.0 if big <= 0.0 else minf(radius * 0.3, m * 0.12)
	if big > 0.0:   # (a cut keeps its angle as the outline grows)
		big = maxf(0.0, big + g * 0.586)
		small = maxf(0.0, small + g * 0.586)
	for c in [[x0, y0, big, Vector2(0, 1), Vector2(1, 0)], [x1, y0, small, Vector2(-1, 0), Vector2(0, 1)],
			[x1, y1, big, Vector2(0, -1), Vector2(-1, 0)], [x0, y1, small, Vector2(1, 0), Vector2(0, -1)]]:
		var at := Vector2(c[0], c[1])
		if c[2] < 0.75:
			pts.append(at)
		else:
			pts.append(at + c[3] * c[2])
			pts.append(at + c[4] * c[2])
	return pts


func _draw(item: RID, rect: Rect2) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var rs := RenderingServer
	var h := rect.size.y
	var y0 := rect.position.y
	var pts := _outline(rect, 0.0)
	# The shadow (or, in a colour, the glow): two rings fading out, and the box's own shape under it
	if shadow_size > 0 and shadow_color.a > 0.0:
		var off := Rect2(rect.position + shadow_offset, rect.size)
		var a := _outline(off, 0.0)
		var b := _outline(off, shadow_size * 0.4)
		var c := _outline(off, float(shadow_size))
		var mid := Color(shadow_color, shadow_color.a * 0.4)
		var out := Color(shadow_color, 0.0)
		_ring(item, a, b, shadow_color, mid)
		_ring(item, b, c, mid, out)
		if draw_center and bg_color.a < 0.999 and shadow_offset != Vector2.ZERO:
			rs.canvas_item_add_polygon(item, a, PackedColorArray([Color(shadow_color, shadow_color.a * (1.0 - bg_color.a))]))
	var top := Color(bg_color.lightened(0.075 * depth), bg_color.a)
	var bottom := Color(bg_color.darkened(0.24 * depth), bg_color.a)
	if draw_center and bg_color.a > 0.0:
		var cols := PackedColorArray()
		for p in pts:
			cols.append(top.lerp(bottom, clampf((p.y - y0) / h, 0.0, 1.0)))
		rs.canvas_item_add_polygon(item, pts, cols)
	var m := minf(rect.size.x, rect.size.y)
	var big := cut_for(radius, rect.size)
	var bw := border_width if border_color.a > 0.0 else 0.0
	var detail := trim and big > 0.0 and m >= 34.0
	# The bar along the bottom (buttons)
	if bar > 0.0 and big > 0.0:
		var by := rect.end.y - bw
		var left := rect.position.x + bw + minf(radius * 0.3, m * 0.12)
		var right := rect.end.x - bw - big
		rs.canvas_item_add_polygon(item, PackedVector2Array([Vector2(left, by - bar), Vector2(right + bar, by - bar), Vector2(right, by), Vector2(left, by)]),
			PackedColorArray([Color(border_color, minf(1.0, border_color.a * 1.25))]))
	# The lit top edge
	if detail and draw_center and bg_color.a > 0.4 and rect.size.x > big + 24.0:
		var ly := y0 + bw + 0.5
		rs.canvas_item_add_line(item, Vector2(rect.position.x + big + 2.0, ly), Vector2(rect.end.x - bw - 4.0, ly), Color(1, 1, 1, 0.09), 1.0)
	# The edge: brighter where the light falls, on top
	if bw > 0.0:
		var line := _outline(rect, -bw / 2.0)
		var hi := Color(border_color.lightened(0.22), border_color.a)
		var lo := Color(border_color.darkened(0.28), border_color.a * 0.85)
		_loop(item, line, hi, lo, y0, h, bw)
	elif draw_center and bg_color.a > 0.0 and m >= 10.0:   # (no edge: a feathered line keeps the cuts smooth)
		_loop(item, _outline(rect, -0.5), top, bottom, y0, h, 1.0)
	# The chips on the two cuts
	if detail and bw > 0.0:
		var chip := Color(border_color.lightened(0.35), clampf(border_color.a * 1.6, 0.3, 1.0))
		var w := bw + 2.0
		var i := w * 0.5
		var p := rect.position
		var e := rect.end
		rs.canvas_item_add_line(item, Vector2(p.x + i, p.y + big + i * 0.4), Vector2(p.x + big + i * 0.4, p.y + i), chip, w, true)
		rs.canvas_item_add_line(item, Vector2(e.x - i, e.y - big - i * 0.4), Vector2(e.x - big - i * 0.4, e.y - i), chip, w, true)


## A band between two outlines of the same shape, one colour at the inner edge and one at the outer.
func _ring(item: RID, inner: PackedVector2Array, outer: PackedVector2Array, c_in: Color, c_out: Color) -> void:
	var n := inner.size()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		pts.append(inner[i])
		pts.append(outer[i])
		cols.append(c_in)
		cols.append(c_out)
		var a := i * 2
		var b := ((i + 1) % n) * 2
		idx.append_array([a, a + 1, b + 1, a, b + 1, b])
	RenderingServer.canvas_item_add_triangle_array(item, idx, pts, cols)


## A closed line round an outline, coloured by height. It starts halfway along the top edge, where the
## join can't be seen.
func _loop(item: RID, pts: PackedVector2Array, hi: Color, lo: Color, y0: float, h: float, width: float) -> void:
	var n := pts.size()
	if n < 3:
		return
	# The top edge: the two points with the smallest y that follow one another
	var start := 0
	for i in n:
		if is_equal_approx(pts[i].y, pts[(i + 1) % n].y) and pts[i].y <= pts[start].y + 0.01 and pts[(i + 1) % n].x > pts[i].x:
			start = i
			break
	var mid := (pts[start] + pts[(start + 1) % n]) / 2.0
	var line := PackedVector2Array([mid])
	for i in n:
		line.append(pts[(start + 1 + i) % n])
	line.append(mid)
	var cols := PackedColorArray()
	for p in line:
		cols.append(hi.lerp(lo, clampf((p.y - y0) / h, 0.0, 1.0)))
	RenderingServer.canvas_item_add_polyline(item, line, cols, width, true)


func _get_draw_rect(rect: Rect2) -> Rect2:
	if shadow_size <= 0:
		return rect
	return rect.grow(shadow_size).merge(Rect2(rect.position + shadow_offset, rect.size).grow(shadow_size))


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
