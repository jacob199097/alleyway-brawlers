extends Control
## A band of dark glass drawn in code, for words that cross the table (YOUR TURN, a phase, an ability going
## off): it can lean, fade out at its ends, open from its middle, carry a line of the accent's colour along
## its top and bottom, a solid block of it at its left end, and a gleam that runs across it.
## Tween `open` and `sheen` to bring it in.

var accent := Color.WHITE: set = _set_accent
var fill := Color(0.02, 0.025, 0.06, 0.9): set = _set_fill
## How far the top edge sits to the right of the bottom edge, px (0: upright)
var skew := 0.0: set = _set_skew
## How much of each end fades out, px (0: a clean slanted end)
var fade_l := 0.0: set = _set_fade_l
var fade_r := 0.0: set = _set_fade_r
## The accent line along the top and the bottom: its thickness (0: none)
var edge := 2.0: set = _set_edge
## A solid block of the accent at the left end: its width (0: none)
var cap := 0.0: set = _set_cap
## 0..1: how far the band has opened from its middle
var open := 1.0: set = _set_open
## Where the gleam is, 0..1 along the band (outside that: none)
var sheen := -1.0: set = _set_sheen


func _set_accent(v: Color) -> void: accent = v; queue_redraw()
func _set_fill(v: Color) -> void: fill = v; queue_redraw()
func _set_skew(v: float) -> void: skew = v; queue_redraw()
func _set_fade_l(v: float) -> void: fade_l = v; queue_redraw()
func _set_fade_r(v: float) -> void: fade_r = v; queue_redraw()
func _set_edge(v: float) -> void: edge = v; queue_redraw()
func _set_cap(v: float) -> void: cap = v; queue_redraw()
func _set_open(v: float) -> void: open = v; queue_redraw()
func _set_sheen(v: float) -> void: sheen = v; queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The x of the band's edge at height y, for a point x along its middle line.
func _lean(x: float, y: float) -> float:
	return x + skew * (0.5 - y / maxf(1.0, size.y))


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0 or open <= 0.0:
		return
	var x0 := w / 2.0 - (w / 2.0) * open
	var x1 := w / 2.0 + (w / 2.0) * open
	# The stops along the band and how solid it is at each
	var stops := [[x0, 0.0 if fade_l > 0.0 else 1.0]]
	if fade_l > 0.0:
		stops.append([minf(x0 + fade_l * open, (x0 + x1) / 2.0), 1.0])
	if fade_r > 0.0:
		stops.append([maxf(x1 - fade_r * open, (x0 + x1) / 2.0), 1.0])
	stops.append([x1, 0.0 if fade_r > 0.0 else 1.0])
	var top := Color(fill.lightened(0.06), fill.a)
	var bottom := Color(fill.darkened(0.3), fill.a)
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if b[0] - a[0] < 0.5:
			continue
		if fill.a > 0.0:
			_strip(a[0], b[0], 0.0, h, Color(top, top.a * a[1]), Color(top, top.a * b[1]), Color(bottom, bottom.a * a[1]), Color(bottom, bottom.a * b[1]))
		if edge > 0.0:
			var ca := Color(accent, accent.a * a[1])
			var cb := Color(accent, accent.a * b[1])
			_strip(a[0], b[0], 0.0, edge, ca, cb, ca, cb)
			_strip(a[0], b[0], h - edge, h, ca, cb, ca, cb)
	if cap > 0.0 and fade_l <= 0.0:
		var lit := Color(accent.lightened(0.25), accent.a)
		_strip(x0, minf(x0 + cap, x1), 0.0, h, lit, lit, accent, accent)
	# The gleam: a soft slanted streak of light, strongest on the accent lines
	if sheen > -0.2 and sheen < 1.2:
		var sx := lerpf(x0, x1, sheen)
		var half := minf(90.0, w * 0.14)
		var clear := Color(1, 1, 1, 0)
		var body := Color(1, 1, 1, 0.1)
		var l := maxf(x0, sx - half)
		var r := minf(x1, sx + half)
		var m := clampf(sx, l, r)
		if r - l > 1.0:
			_strip(l, m, 0.0, h, clear, body, clear, body)
			_strip(m, r, 0.0, h, body, clear, body, clear)
			if edge > 0.0:
				var hot := Color(1, 1, 1, 0.85)
				for y in [0.0, h - edge]:
					_strip(l, m, y, y + edge, clear, hot, clear, hot)
					_strip(m, r, y, y + edge, hot, clear, hot, clear)


## A leaning four-sided piece between two x on the middle line, from y0 to y1, a colour at each corner.
func _strip(xa: float, xb: float, y0: float, y1: float, tl: Color, tr: Color, bl: Color, br: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(_lean(xa, y0), y0), Vector2(_lean(xb, y0), y0), Vector2(_lean(xb, y1), y1), Vector2(_lean(xa, y1), y1)]),
		PackedColorArray([tl, tr, br, bl]))
