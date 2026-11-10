extends Node
## Phones and tablets without black bars. Every screen is laid out on a 1920×1080 frame; a phone is
## wider than that (20:9) and a tablet taller (4:3). On mobile (Game.mobile()) the view grows to fill
## the screen instead of leaving bars: the frame sits in the middle (the root's global canvas transform
## moves every layer, and the input with it), and full-screen backgrounds, dimmers and fades reach the
## edges. The duel's camera adds `margin` back so its board stays on the frame (duel.gd _process).
## On a PC nothing changes: the window keeps 16:9 with bars, as before.
## Made by game.gd (not an autoload: patches can't add one).

const FRAME := Vector2(1920, 1080)
const FILLED := "wide_filled"   # (group of the nodes stretched to the edges, redone when the screen changes size)

var active := false
var margin := Vector2.ZERO   # where the frame's top-left corner is on the screen


func _ready() -> void:
	active = Game.mobile()
	if not active:
		return
	# Landscape only, either way up (as the APK's manifest says: project.godot window/handheld/orientation)
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	var root := get_tree().root
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size_changed.connect(_fit)
	get_tree().node_added.connect(func(n: Node):
		if n is Control:
			_reach.call_deferred(n))   # (deferred: its size and children are set once it's in)
	_fit()


func _fit() -> void:
	var root := get_tree().root
	margin = ((root.get_visible_rect().size - FRAME) / 2).floor().max(Vector2.ZERO)
	root.global_canvas_transform = Transform2D(0, margin)
	for n in get_tree().get_nodes_in_group(FILLED):
		_fill(n)


## A control covering the whole frame (a background, a dimmer, a fade) reaches the screen's edges.
func _reach(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree() or c.is_in_group(FILLED):
		return
	if not (c is ColorRect or c is TextureRect or c.has_method("fill_frame")):
		return
	var r = _frame_rect(c)
	if r == null or r.position.x > 1 or r.position.y > 1 or r.end.x < FRAME.x - 1 or r.end.y < FRAME.y - 1:
		return
	var kids := c.get_children().any(func(k): return k is CanvasItem)
	if c is ColorRect and (kids or c.material == null):
		# A dimmer under a dialog: its content is its children, so it stays put and paints the sides
		c.draw.connect(_bleed.bind(c))
	elif c is TextureRect and kids:
		return
	else:
		c.set_meta(FILLED, Rect2(c.position, c.size))
		if c is TextureRect and c.stretch_mode == TextureRect.STRETCH_SCALE:
			c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # (not stretched out of shape)
	c.add_to_group(FILLED)
	_fill(c)


func _fill(c: Control) -> void:
	if c.has_method("fill_frame"):
		c.fill_frame(margin)
	elif c.has_meta(FILLED):
		var r: Rect2 = c.get_meta(FILLED)
		c.position = r.position - margin
		c.size = r.size + margin * 2
	else:
		c.queue_redraw()


func _bleed(c: ColorRect) -> void:
	var m := margin
	var s := c.size
	c.draw_rect(Rect2(-m.x, -m.y, m.x, s.y + m.y * 2), c.color)
	c.draw_rect(Rect2(s.x, -m.y, m.x, s.y + m.y * 2), c.color)
	if m.y > 0:
		c.draw_rect(Rect2(0, -m.y, s.x, m.y), c.color)
		c.draw_rect(Rect2(0, s.y, s.x, m.y), c.color)


## Where a control is on the frame (scale ignored: screens zoom in as they open), or null when it's
## inside something that clips it, or in the duel's world (the camera's, not the frame's).
func _frame_rect(c: Control) -> Variant:
	var p := Vector2.ZERO
	var n: Control = c
	while true:
		p += n.position
		var parent := n.get_parent()
		if parent is Control:
			if parent.clip_contents:
				return null
			n = parent
		elif parent is CanvasLayer or parent is Window:
			return Rect2(p, c.size)
		else:
			return null
	return null
