extends Screen
## THE TURF MAP (backend/economy/territory.js, GET /api/territory): the city's districts are the
## arenas. Every match is fought in one and wins influence there for your deck's clan; each week a
## district goes to the clan with the most influence in it, if that beats the local gang running it.
## When the week ends, everyone who fought for a clan in a district it took is paid Karat, and the
## district's boss (its top fighter) more: CLAIM. A district's FIGHT HERE starts a CPU match in it
## against the gang that runs it, as tough as the gang's star rating this week (1 to 5 stars).
## Drawn on the city itself once data/turf_city.json and its picture are in the game: each district a
## marker where it is in the city, glowing in its holder's colour, the city alive around them
## (ArenaLife fx). Until then, a grid of the arenas.

const CITY_FILE := "res://data/turf_city.json"
const COLS := 6
const TILE := Vector2(290, 236)
const GAP := Vector2(15, 16)
const GRID := Vector2(52, 232)
const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")
## A gang's star rating: how it plays and what beating it is worth (index = stars; the server's
## GANG_STARS in backend/economy/territory.js and TURF_STAR_REWARD_SCALE in economy/postMatch.js).
const STAR_INFO := ["",
	"PUSHOVERS: an Easy CPU. A win is +1 influence, small rewards.",
	"SCRAPPERS: a Normal CPU. A win is +1 influence.",
	"A TOUGH CREW: a Hard CPU. A win is +2 influence and better rewards.",
	"HEAVY HITTERS: a Hard CPU with 9000 Morale. A win is +2 influence and big rewards.",
	"KINGPINS: a Hard CPU with 9000 Morale and +1 Authority every turn. A win is +3 influence and the best rewards in VS CPU.",
]

var _data := {}
var _clan := {}             # clan id -> {name, color}
var _detail: Control = null  # the open district
var _banner: Control = null  # last week's Karat, waiting
var _starting := false
var _spin: Label = null
var _arena: Control = null   # the arena roulette while the match starts
var _city := {}              # data/turf_city.json, when its picture is in the game ({}: the grid)
var _hint: Control = null    # the district under the mouse, in brief


## The city map (data/turf_city.json): {image, anchors: {district: [x, y]}, fx: [...]}, positions in
## the picture's pixels; fx as an arena's (ArenaLife). {} until its picture is in the game.
static func city() -> Dictionary:
	var f := FileAccess.open(CITY_FILE, FileAccess.READ)
	var c = JSON.parse_string(f.get_as_text()) if f else null
	return c if c is Dictionary and c.get("anchors") is Dictionary and UI.tex(str(c.get("image", ""))) != null else {}


func _ready() -> void:
	back_to = "main_menu"
	_city = city()
	if _city.is_empty():
		UI.background(self, "menu_background.jpg", 0.66)
	else:
		_city_backdrop()
	Game.sound.ambience("city_rain")
	UI.title(self, "TURF MAP")
	UI.back_button(self, func(): Game.go("main_menu"))
	if not needs_server("The turf map"):
		return
	var spin := UI.spinner(self, Vector2(960, 540), "LOADING THE CITY…")
	await _load()
	spin.queue_free()
	if _data.is_empty() or not is_inside_tree():
		return
	_build()
	_intro()


func _load() -> void:
	var r := await Api.request("GET", "/api/territory")
	if not is_inside_tree():
		return
	if not r.ok or not (r.data is Dictionary):
		UI.toast(self, r.error if r.error != "" else "Couldn't load the turf map.", UI.RED)
		return
	_data = r.data
	_clan = {}
	for c in _data.get("clans", []):
		if c is Dictionary:
			_clan[str(c.id)] = {"name": str(c.get("name", c.id)), "color": CardDB.clan_color(str(c.get("color", "#ffffff")))}


func _build() -> void:
	if _world == null:   # (on the city, the week's end is in the bottom row, clear of the districts)
		var sub := UI.label("Every match wins influence for your deck's clan in the district it's fought in  ·  week ends in %s" % _ends_in(), 21, UI.MUTED)
		sub.size = Vector2(1920, 30)
		sub.position = Vector2(0, 98)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(sub)
	if _data.get("reward") is Dictionary:
		_reward_banner(_data.reward)
	var districts: Array = _data.get("districts", [])
	if not _city.is_empty():
		_build_city(districts)
		return
	for i in districts.size():
		_tile(districts[i], GRID + Vector2(i % COLS, i / COLS) * (TILE + GAP))
	var free := districts.size()
	if free < COLS * 3:   # the spare slot: who holds how much this week
		_summary(GRID + Vector2(free % COLS, free / COLS) * (TILE + GAP))
	var how := UI.label(_rules_text(), 17, UI.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size = Vector2(1560, 50)
	how.position = Vector2(290, 990)
	add_child(how)


## The rules line along the bottom.
func _rules_text() -> String:
	var k: Dictionary = _data.get("karat", {}) if _data.get("karat") is Dictionary else {}
	return "Online win +3  ·  online loss +1  ·  Ranked or Hard CPU win +2  ·  CPU win +1  ·  Turf Defense win +3  ·  a gang win +1 to +3 by its stars.   When the week ends, the clan's fighters in each district it holds earn %d Karat, its boss %d more." % [int(k.get("district", 50)), int(k.get("boss", 50))]


# ── The city ─────────────────────────────────────────────────────────────────
# The city picture lives in _world, in its own pixels: the backdrop, its life (ArenaLife: rain,
# neon, searchlights, water, fog...), traffic on its streets, each district's turf glow and its
# marker. _world is scaled to fit the screen (_fit) times the zoom, and moved by the camera: scroll
# to zoom in on the mouse, drag to look around. Markers keep their size on screen at any zoom.

const ZOOM_MAX := 2.4

var _world: Control = null
var _fit := 1.0
var _zoom := 1.0
var _zoom_to := 1.0
var _pos := Vector2.ZERO       # _world's top-left corner on screen
var _pos_to := Vector2.ZERO
var _drag_from := Vector2.INF  # where a drag started (screen), and _pos then
var _drag_pos := Vector2.ZERO
var _pins: Array[Control] = []  # the markers' holders, counter-scaled to keep their size


## The city: a blurred, darkened copy filling the screen behind the picture (so its edges melt
## away), the picture in _world, alive, and shade at the top and bottom so the title and panels read.
func _city_backdrop() -> void:
	var tex := UI.tex(str(_city.image))
	var ts := tex.get_size()
	var small := tex.get_image()
	if small.is_compressed():   # (an exported game's textures are VRAM-compressed)
		small.decompress()
	var blur := TextureRect.new()
	if not small.is_compressed():
		small.clear_mipmaps()
		small.resize(int(ts.x / 24), int(ts.y / 24), Image.INTERPOLATE_BILINEAR)
		blur.texture = ImageTexture.create_from_image(small)
	else:   # (couldn't: the picture itself, dark, does the job)
		blur.texture = tex
	blur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	blur.size = Vector2(1920, 1080)
	blur.modulate = Color(0.34, 0.32, 0.42)
	blur.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blur)
	_world = Control.new()
	_world.size = ts
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.size = ts
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(bg)
	for side in [0.0, 1.0]:   # the picture's left and right edges fade into the blur
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.025, 0.06, 1.0 - side))
		g.set_color(1, Color(0.03, 0.025, 0.06, side))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		var fade := TextureRect.new()
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.size = Vector2(90, ts.y)
		fade.position = Vector2(0.0 if side == 0.0 else ts.x - 90.0, 0)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(fade)
	var life := ArenaLife.new().setup(tex, Color.WHITE, Game.arena_level(), ts)
	_world.add_child(life)
	for e in _city.get("fx", []):
		if e is Dictionary and ArenaLife.handles(str(e.get("kind", ""))):
			life.add(e)
	for path in _city.get("traffic", []):
		if path is Array and path.size() >= 2:
			_traffic(path)
	_fit = minf(1920.0 / ts.x, 1080.0 / ts.y)
	_pos = (Vector2(1920, 1080) - ts * _fit) / 2.0
	_pos_to = _pos
	_place_world()
	for edge in [[0.0, 150.0, 0.0], [1080.0 - 140.0, 140.0, 1.0]]:   # (top and bottom shade)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.78 if edge[2] == 0.0 else 0.0))
		g.set_color(1, Color(0, 0, 0, 0.0 if edge[2] == 0.0 else 0.85))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		var shade := TextureRect.new()
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.position = Vector2(0, edge[0])
		shade.size = Vector2(1920, edge[1])
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)


## Cars on a street: a pair of headlights one way, tail lights the other, now and then, with a
## glow on the wet road under them. `path`: points in the picture's pixels.
func _traffic(path: Array) -> void:
	var pts := PackedVector2Array()
	for p in path:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var length := 0.0
	for i in pts.size() - 1:
		length += pts[i].distance_to(pts[i + 1])
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var dot := ArenaLife._soft_dot()
	while is_inside_tree():
		var back := randf() < 0.5
		var car := Node2D.new()
		car.material = add
		var col := Color(1.0, 0.93, 0.75) if not back else Color(1.0, 0.22, 0.18)
		car.draw.connect(func():
			car.draw_texture_rect(dot, Rect2(Vector2(-14, -8), Vector2(28, 16)), false, Color(col, 0.25))
			for s in [-2.6, 2.6]:
				car.draw_texture_rect(dot, Rect2(Vector2(s - 2.4, -2.4), Vector2(4.8, 4.8)), false, col))
		_world.add_child(car)
		var dur := length / randf_range(55.0, 85.0)
		var along := func(f: float):
			var d := f * length
			for i in pts.size() - 1:
				var seg := pts[i].distance_to(pts[i + 1])
				if d <= seg or i == pts.size() - 2:
					car.position = pts[i].lerp(pts[i + 1], clampf(d / maxf(seg, 0.001), 0.0, 1.0))
					return
				d -= seg
		var t := car.create_tween()
		t.tween_method(along, 1.0 if back else 0.0, 0.0 if back else 1.0, dur)
		t.tween_callback(car.queue_free)
		await get_tree().create_timer(randf_range(1.2, 3.4)).timeout


func _place_world() -> void:
	if _world == null:
		return
	var s := _fit * _zoom
	_world.scale = Vector2.ONE * s
	_world.position = _pos
	for pin in _pins:
		pin.scale = Vector2.ONE / s * (0.94 + 0.12 * (_zoom - 1.0) / (ZOOM_MAX - 1.0))


## Where _world's corner may go at a zoom: centred while it fits the screen, else kept covering it.
func _clamp_pos(p: Vector2, zoom: float) -> Vector2:
	var size := _world.size * _fit * zoom
	for axis in 2:
		if size[axis] <= [1920.0, 1080.0][axis]:
			p[axis] = ([1920.0, 1080.0][axis] - size[axis]) / 2.0
		else:
			p[axis] = clampf(p[axis], [1920.0, 1080.0][axis] - size[axis], 0.0)
	return p


func _process(delta: float) -> void:
	if _world == null:
		return
	var w := 1.0 - exp(-10.0 * delta)
	var old := _fit * _zoom
	_zoom = lerpf(_zoom, _zoom_to, w)
	# (zooming keeps the point under the mouse where it is: _pos_to was set for that)
	_pos = _pos.lerp(_pos_to, w)
	if absf(_fit * _zoom - old) > 0.0001 or _pos.distance_to(_pos_to) > 0.05:
		_place_world()


func _gui_input(e: InputEvent) -> void:
	if _world == null:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var z := clampf(_zoom_to * (1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 1.0, ZOOM_MAX)
		var at: Vector2 = e.position
		var p := (at - _pos_to) / (_fit * _zoom_to)   # the picture point under the mouse
		_zoom_to = z
		_pos_to = _clamp_pos(at - p * _fit * z, z)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag_from = e.position if e.pressed else Vector2.INF
		_drag_pos = _pos_to
	elif e is InputEventMouseMotion and _drag_from != Vector2.INF:
		_pos_to = _clamp_pos(_drag_pos + (e.position - _drag_from), _zoom_to)
		_pos = _pos_to
		_place_world()


func _build_city(districts: Array) -> void:
	var anchors: Dictionary = _city.anchors
	var i := 0
	for d in districts:
		if anchors.get(str(d.get("id", ""))) is Array:
			_marker(d, anchors[str(d.id)], i)
			i += 1
	_place_world()
	# Who holds how much, along the bottom
	var held := {}
	var locals := 0
	for d in districts:
		var who := str(d.get("holder", ""))
		if who == "":
			locals += 1
		else:
			held[who] = int(held.get(who, 0)) + 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(260, 966)
	row.size = Vector2(1400, 34)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var order: Array = held.keys()
	order.sort_custom(func(a, b): return held[a] > held[b])
	row.add_child(UI.label("THIS WEEK", 22, UI.GOLD, true))
	for id in order:
		row.add_child(UI.label("%s %d" % [_clan_name(id).to_upper(), held[id]], 22, _clan_col(id), true))
	row.add_child(UI.label("LOCAL GANGS %d" % locals, 22, UI.MUTED, true))
	row.add_child(UI.label("·   WEEK ENDS IN %s" % _ends_in().to_upper(), 22, Color(0.85, 0.85, 0.95), true))
	var how := UI.label(_rules_text() + "   ·   Scroll to zoom, drag to look around.", 15, Color(0.8, 0.8, 0.9))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.size = Vector2(1400, 44)
	how.position = Vector2(260, 1006)
	how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(how)


## A district on the city: its turf glowing in the holder's colour under a round badge (the clan's
## emblem, or a skull while a local gang runs it), its name, and its standings in a thin bar. A
## contested district's ring flickers; yours wear a gold star. Under it, its gang's star rating.
## Hover for the standings, click to open.
## `anchor`: [x, y] in the picture's pixels, or [x, y, turf size] (1 = normal).
func _marker(d: Dictionary, anchor: Array, n: int) -> void:
	var at := Vector2(float(anchor[0]), float(anchor[1]))
	var holder := str(d.get("holder", ""))
	var col := _clan_col(holder) if holder != "" else Color(0.6, 0.6, 0.68)
	var clans: Array = d.get("clans", [])
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	var top := int(clans[0].get("points", 0)) if not clans.is_empty() else 0
	var contested := (clans.size() >= 2 and top - int(clans[1].get("points", 0)) <= 2) \
		or (top > 0 and absi(top - int(gang.get("strength", 0))) <= 2)
	var mine: Dictionary = d.get("mine", {}) if d.get("mine") is Dictionary else {}
	# The turf: a soft glow on the city in the holder's colour, breathing
	var zone := Sprite2D.new()
	zone.texture = ArenaLife._soft_dot()
	zone.position = at
	zone.scale = Vector2.ONE * (5.0 if holder != "" else 3.5) * (float(anchor[2]) if anchor.size() > 2 else 1.0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	zone.material = add
	zone.modulate = Color(col, 0.0)
	_world.add_child(zone)
	var breathe := zone.create_tween().set_loops()
	breathe.tween_property(zone, "modulate:a", 0.38 if holder != "" else 0.12, 1.6 + randf() * 0.8).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(zone, "modulate:a", 0.18 if holder != "" else 0.05, 1.6 + randf() * 0.8).set_trans(Tween.TRANS_SINE)
	# The marker, on a pin that keeps its size on screen at any zoom
	var pin := Control.new()
	pin.position = at
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(pin)
	_pins.append(pin)
	var m := Control.new()
	m.size = Vector2(150, 132)
	m.position = Vector2(-75, -36)
	m.pivot_offset = Vector2(75, 36)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pin.add_child(m)
	var badge := Control.new()
	badge.size = Vector2(72, 72)
	badge.position = Vector2(39, 0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(badge)
	var emblem := UI.clan_emblem(holder) if holder != "" else null
	badge.draw.connect(func():
		var c := Vector2(36, 36)
		var t := Time.get_ticks_msec() / 1000.0
		var ring := col
		if contested:   # flickering between its colour and alarm red (Photosensitive mode: a steady red)
			ring = col.lerp(UI.RED, 0.6 if Game.photosafe() else 0.5 + 0.5 * sin(t * 6.0 + n))
		badge.draw_circle(c + Vector2(2, 3), 34, Color(0, 0, 0, 0.5))
		badge.draw_circle(c, 33, Color(0.04, 0.035, 0.08, 0.95))
		badge.draw_arc(c, 32, 0, TAU, 40, ring, 4.0, true)
		if emblem:
			badge.draw_texture_rect(emblem, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false)
		else:
			badge.draw_string(UI.font(), Vector2(0, 47), "☠", HORIZONTAL_ALIGNMENT_CENTER, 72, 34, Color(0.75, 0.75, 0.82))
		if not mine.is_empty():
			badge.draw_string(UI.font(), Vector2(50, 18), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.GOLD))
	if contested:
		get_tree().process_frame.connect(badge.queue_redraw)
	var name := UI.label(str(d.get("name", "")).to_upper(), 16, Color.WHITE, true)
	name.size = Vector2(150, 22)
	name.position = Vector2(0, 74)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.label_settings.outline_size = 6
	name.label_settings.outline_color = Color(0, 0, 0, 0.9)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(name)
	var bars := Control.new()
	bars.position = Vector2(30, 100)
	bars.size = Vector2(90, 8)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars.bind(bars, d))
	m.add_child(bars)
	var rating := Control.new()
	rating.position = Vector2(25, 108)
	rating.size = Vector2(100, 24)
	rating.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rating.draw.connect(func():
		for i in 5:
			var spot := Vector2(i * 20, 19)
			rating.draw_string(UI.font(), spot + Vector2(1, 1), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.85))
			rating.draw_string(UI.font(), spot, "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.GOLD if i < _stars_of(d) else Color(1, 1, 1, 0.3)))
	m.add_child(rating)
	m.mouse_entered.connect(func():
		Sfx.play("hover", 1.2, -14.0)
		m.create_tween().tween_property(m, "scale", Vector2.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pin.z_index = 5
		_show_hint(d, m))
	m.mouse_exited.connect(func():
		m.create_tween().tween_property(m, "scale", Vector2.ONE, 0.14)
		pin.z_index = 0
		if _hint:
			_hint.queue_free()
			_hint = null)
	m.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			Sfx.play("click")
			_open(d)
		elif e is InputEventMouseButton:   # (scrolling over a marker still zooms the map)
			_gui_input(e))
	# Dropped onto the city one after another
	m.modulate.a = 0.0
	m.scale = Vector2.ONE * 1.6
	var drop := m.create_tween().set_parallel()
	drop.tween_property(m, "modulate:a", 1.0, 0.2).set_delay(0.3 + n * 0.05)
	drop.tween_property(m, "scale", Vector2.ONE, 0.32).set_delay(0.3 + n * 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The standings by a hovered district: who holds it, each clan's influence, the gang's strength.
func _show_hint(d: Dictionary, m: Control) -> void:
	if _hint:
		_hint.queue_free()
	var holder := str(d.get("holder", ""))
	var p := UI.panel(_clan_col(holder) if holder != "" else UI.MUTED, Color(0.03, 0.03, 0.07, 0.94))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 20
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	v.add_child(UI.label(("HELD BY %s" % _clan_name(holder).to_upper()) if holder != "" else "RUN BY %s" % str(gang.get("name", "the locals")).to_upper(), 18, _clan_col(holder) if holder != "" else UI.MUTED, true))
	for c in d.get("clans", []):
		v.add_child(UI.label("%s  %d" % [_clan_name(str(c.clan)).to_upper(), int(c.get("points", 0))], 16, _clan_col(str(c.clan)), true))
	v.add_child(UI.label("%s  %d to beat" % [str(gang.get("name", "Locals")), int(gang.get("strength", 0))], 15, UI.MUTED))
	v.add_child(_stars_row(_stars_of(d), 20))
	var boss = d.get("boss")
	if boss is Dictionary:
		v.add_child(UI.label("👑 %s" % str(boss.get("username", "")), 15, UI.GOLD))
	v.add_child(UI.label("Click to open", 14, UI.MUTED))
	add_child(p)
	_hint = p
	p.modulate.a = 0.0
	await get_tree().process_frame   # (its size, once laid out)
	if not is_instance_valid(p) or _hint != p:
		return
	var r := m.get_global_rect()
	var at := Vector2(r.end.x + 6, r.position.y - 6)
	if at.x + p.size.x > 1900:
		at.x = r.position.x - p.size.x - 6
	at.y = clampf(at.y, 120, 940 - p.size.y)
	p.position = at
	p.modulate.a = 1.0


## "3d 14h" until the week's map resets (Monday 00:00 UTC).
func _ends_in() -> String:
	var ends := Time.get_unix_time_from_datetime_string(str(_data.get("endsAt", "")).trim_suffix("Z"))
	var left := maxi(0, int(ends - Time.get_unix_time_from_system()))
	var d := left / 86400
	var h := (left % 86400) / 3600
	return "%dd %dh" % [d, h] if d > 0 else "%dh %dm" % [h, (left % 3600) / 60]


func _clan_name(id: String) -> String:
	return str(_clan.get(id, {}).get("name", id.capitalize()))


func _clan_col(id: String) -> Color:
	return _clan.get(id, {}).get("color", Color(0.62, 0.62, 0.7))


# ── The districts ────────────────────────────────────────────────────────────

func _tile(d: Dictionary, at: Vector2) -> void:
	var holder := str(d.get("holder", ""))
	var col := _clan_col(holder) if holder != "" else Color(0.55, 0.55, 0.62)
	var b := Button.new()
	b.position = at
	b.size = TILE
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UI.box(Color(0.03, 0.03, 0.07, 0.92), Color(col, 0.9), 3, 12))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.07, 0.06, 0.12, 0.95), UI.GOLD, 3, 12))
	b.add_theme_stylebox_override("pressed", UI.box(Color(0.07, 0.06, 0.12, 0.95), UI.GOLD, 4, 12))
	b.pressed.connect(func():
		Sfx.play("click")
		_open(d))
	b.mouse_entered.connect(func(): Sfx.play("hover", 1.2, -14.0))
	add_child(b)
	var img := UI.texture_rect(UI.tex(str(d.get("image", ""))), TILE - Vector2(8, 8), true)
	img.position = Vector2(4, 4)
	img.modulate = Color(0.62, 0.62, 0.68) if holder != "" else Color(0.42, 0.42, 0.48)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(img)
	if holder != "":   # the holding clan's colour washed over it
		var wash := ColorRect.new()
		wash.color = Color(col, 0.16)
		wash.position = Vector2(4, 4)
		wash.size = TILE - Vector2(8, 8)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(wash)
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.66)
	strip.position = Vector2(4, 4)
	strip.size = Vector2(TILE.x - 8, 40)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(strip)
	var name := UI.label(str(d.get("name", "")).to_upper(), 21, Color.WHITE, true)
	name.size = Vector2(TILE.x - 16, 34)
	name.position = Vector2(8, 8)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name)
	var foot := ColorRect.new()
	foot.color = Color(0, 0, 0, 0.72)
	foot.position = Vector2(4, TILE.y - 98)
	foot.size = Vector2(TILE.x - 8, 94)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(foot)
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	var who := UI.label(("%s HOLD IT" % _clan_name(holder).to_upper()) if holder != "" else str(gang.get("name", "Locals")).to_upper(), 18, col, true)
	who.size = Vector2(TILE.x - 16, 24)
	who.position = Vector2(8, TILE.y - 94)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.clip_text = true
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(who)
	var bars := Control.new()
	bars.position = Vector2(16, TILE.y - 66)
	bars.size = Vector2(TILE.x - 32, 22)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars.bind(bars, d))
	b.add_child(bars)
	var bits: Array = []
	var boss = d.get("boss")
	if boss is Dictionary:
		bits.append("👑 %s" % str(boss.get("username", "")))
	var mine: Dictionary = d.get("mine", {}) if d.get("mine") is Dictionary else {}
	var yours := 0
	for v in mine.values():
		yours += int(v)
	if yours > 0:
		bits.append("you +%d" % yours)
	if bits.is_empty():
		bits.append("strength %d to beat" % int(gang.get("strength", 0)) if holder == "" else "")
	var foot_text := UI.label("  ·  ".join(bits), 16, UI.GOLD if yours > 0 else UI.MUTED)
	foot_text.size = Vector2(TILE.x - 16, 22)
	foot_text.position = Vector2(8, TILE.y - 36)
	foot_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot_text.clip_text = true
	foot_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(foot_text)


## The standings in a bar: each clan's influence end to end in its colour, and a white tick where
## the local gang's strength is (a clan has to get past it).
func _draw_bars(c: Control, d: Dictionary) -> void:
	var clans: Array = d.get("clans", [])
	var strength := int(d.get("locals", {}).get("strength", 0)) if d.get("locals") is Dictionary else 0
	var top := strength
	for x in clans:
		top = maxi(top, int(x.get("points", 0)))
	var scale := c.size.x / maxf(1.0, top * 1.25)
	var h := c.size.y
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.08))
	var rows := mini(clans.size(), 2)
	for i in rows:
		var w := int(clans[i].get("points", 0)) * scale
		var y := (h / maxf(1, rows)) * i
		c.draw_rect(Rect2(0, y + 1, w, h / maxf(1, rows) - 2), _clan_col(str(clans[i].get("clan", ""))))
	var x := strength * scale
	c.draw_line(Vector2(x, -3), Vector2(x, h + 3), Color.WHITE, 2.0)


## The spare grid slot: how many districts each clan holds this week.
func _summary(at: Vector2) -> void:
	var p := UI.panel(UI.GOLD, Color(0.03, 0.03, 0.07, 0.9))
	p.position = at
	p.custom_minimum_size = TILE
	p.size = TILE
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var h := UI.label("THIS WEEK", 22, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var held := {}
	var locals := 0
	for d in _data.get("districts", []):
		var who := str(d.get("holder", ""))
		if who == "":
			locals += 1
		else:
			held[who] = int(held.get(who, 0)) + 1
	var order: Array = held.keys()
	order.sort_custom(func(a, b): return held[a] > held[b])
	for id in order:
		v.add_child(UI.label("%s  ·  %d" % [_clan_name(id).to_upper(), held[id]], 19, _clan_col(id), true))
	v.add_child(UI.label("LOCAL GANGS  ·  %d" % locals, 19, UI.MUTED, true))


# ── A district, opened ───────────────────────────────────────────────────────

func _open(d: Dictionary) -> void:
	_close()
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.82)
	veil.size = Vector2(1920, 1080)
	veil.z_index = 50
	veil.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(veil)
	_detail = veil
	var holder := str(d.get("holder", ""))
	var col := _clan_col(holder) if holder != "" else UI.MUTED
	var p := UI.panel(col, Color(0.04, 0.04, 0.09, 0.97))
	p.position = Vector2(300, 170)
	p.custom_minimum_size = Vector2(1320, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	p.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	var img := UI.texture_rect(UI.tex(str(d.get("image", ""))), Vector2(560, 373), true)
	left.add_child(img)
	var fight := UI.button("⚔  FIGHT HERE  (VS CPU)", _fight.bind(d), Vector2(560, 70), UI.RED)
	left.add_child(fight)
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	var against := UI.label("A CPU match against %s: win it to push your clan's influence here." % str(gang.get("name", "the locals")), 17, UI.MUTED)
	against.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	against.custom_minimum_size = Vector2(560, 0)
	left.add_child(against)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(660, 0)
	row.add_child(right)
	right.add_child(UI.label(str(d.get("name", "")).to_upper(), 46, Color.WHITE, true))
	right.add_child(UI.label(("HELD BY %s" % _clan_name(holder).to_upper()) if holder != "" else "RUN BY %s" % str(gang.get("name", "the locals")).to_upper(), 24, col, true))
	right.add_child(HSeparator.new())
	# The gang's star rating: how hard the fight is, and what it pays
	var stars := _stars_of(d)
	var rated := HBoxContainer.new()
	rated.add_theme_constant_override("separation", 16)
	rated.add_child(UI.label("%s  " % str(gang.get("name", "The locals")).to_upper(), 20, UI.MUTED, true))
	rated.add_child(_stars_row(stars, 34))
	right.add_child(rated)
	var info := UI.label(STAR_INFO[stars], 18, UI.GOLD if stars >= 4 else Color(0.85, 0.85, 0.9))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(660, 0)
	right.add_child(info)
	right.add_child(HSeparator.new())
	right.add_child(UI.label("INFLUENCE THIS WEEK", 20, UI.GOLD, true))
	var clans: Array = d.get("clans", [])
	if clans.is_empty():
		right.add_child(UI.label("Nobody has fought here this week.", 19, UI.MUTED))
	for c in clans:
		var id := str(c.get("clan", ""))
		right.add_child(UI.label("%s   %d" % [_clan_name(id).to_upper(), int(c.get("points", 0))], 22, _clan_col(id), true))
	right.add_child(UI.label("%s   %d  (beat it to take the district)" % [str(gang.get("name", "Locals")).to_upper(), int(gang.get("strength", 0))], 20, UI.MUTED, true))
	right.add_child(HSeparator.new())
	var boss = d.get("boss")
	if boss is Dictionary:
		right.add_child(UI.label("👑  BOSS OF THE DISTRICT: %s (%d)" % [str(boss.get("username", "")), int(boss.get("points", 0))], 20, UI.GOLD, true))
	var mine: Dictionary = d.get("mine", {}) if d.get("mine") is Dictionary else {}
	for id in mine:
		right.add_child(UI.label("YOU: +%d FOR %s" % [int(mine[id]), _clan_name(id).to_upper()], 20, _clan_col(id), true))
	var last := str(d.get("lastHolder", ""))
	right.add_child(UI.label("Last week: %s" % (("held by " + _clan_name(last)) if last != "" else "the locals kept it"), 18, UI.MUTED))
	var close := UI.button("CLOSE", _close, Vector2(200, 56))
	right.add_child(close)


## A district's gang rating this week, 1..5 (the server's, in its "locals").
func _stars_of(d: Dictionary) -> int:
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	return clampi(int(gang.get("stars", 1)), 1, 5)


## Five stars in a row, the gang's rating in gold and the rest dim.
func _stars_row(n: int, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for i in 5:
		var s := UI.label("★", font_size, UI.GOLD if i < n else Color(1, 1, 1, 0.2), true)
		row.add_child(s)
		if i < n:   # (they light up one after another)
			s.modulate.a = 0.0
			s.create_tween().tween_property(s, "modulate:a", 1.0, 0.18).set_delay(0.08 * i)
	return row


func _close() -> void:
	if _detail and is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null


# ── Last week's Karat ────────────────────────────────────────────────────────

func _reward_banner(rw: Dictionary) -> void:
	var p := UI.panel(UI.GREEN, Color(0.03, 0.08, 0.05, 0.95))
	p.position = Vector2(560, 136) if _world == null else Vector2(20, 14)   # (on the city: the top-left corner, over the skyline)
	p.custom_minimum_size = Vector2(800, 76) if _world == null else Vector2(660, 0)
	add_child(p)
	_banner = p
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var held := 0
	var bosses := 0
	for w in rw.get("weeks", []):
		for d in w.get("districts", []):
			held += 1
			if d.get("boss", false):
				bosses += 1
	var text := "YOUR CREWS TOOK %d DISTRICT%s" % [held, "" if held == 1 else "S"]
	if bosses > 0:
		text += "  ·  BOSS OF %d" % bosses
	var l := UI.label(text, 22 if _world == null else 18, UI.GREEN, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	row.add_child(UI.button("CLAIM %d KARAT" % int(rw.get("karat", 0)), _claim, Vector2(260, 60) if _world == null else Vector2(220, 50), UI.GREEN))


func _claim() -> void:
	var r := await Api.request("POST", "/api/territory/claim")
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(self, r.error if r.error != "" else "Couldn't claim it.", UI.RED)
		return
	if r.data.get("newKarat") != null:
		Game.player.karat = int(r.data.newKarat)
	Sfx.play("karat")
	UI.toast(self, "+%d KARAT" % int(r.data.get("karat", 0)), UI.GOLD)
	if _banner:
		_banner.queue_free()
		_banner = null


# ── FIGHT HERE ───────────────────────────────────────────────────────────────

func _fight(d: Dictionary) -> void:
	if _starting:
		return
	_close()   # (the district panel sits over everything: what follows goes on the map)
	_starting = true
	var spin := UI.spinner(self, Vector2(960, 980), "LOADING YOUR DECK…")
	var deck := await Game.load_duel_deck()
	spin.queue_free()
	if deck.has("error"):
		_starting = false
		var buttons := [["CLOSE", func(): pass]]
		if deck.get("gate", false):
			buttons.push_front(["DECK EDITOR", func(): Game.go("deck_builder"), UI.BLUE])
		UI.dialog(self, "CAN'T START DUEL", deck.error, buttons, UI.RED)
		return
	_spin = UI.spinner(self, Vector2(960, 1000), "STARTING MATCH…")
	_arena = ArenaRoulette.spin(self, str(d.get("id", "")), Vector2(1460, 784), true)   # (no spin: it's the district picked)
	var why := await Game.request_cpu_match(false, "", false, str(d.get("id", "")), true)   # (the gang's stars decide how it plays)
	if why != "":
		on_online_error(why)
		return
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree() and _starting:
		on_online_error("The server didn't start the match. Try again in a moment.")


## mp:start for the CPU match: the duel opens once the arena has landed.
func on_online_start(_data_in) -> void:
	if _arena and is_instance_valid(_arena) and not _arena.done:
		await _arena.landed
	Game.go("duel")


## mp:error while starting the CPU match (net.gd calls this on the current screen).
func on_online_error(message: String) -> void:
	if _spin and is_instance_valid(_spin):
		_spin.queue_free()
	_spin = null
	if _arena and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_starting = false
	UI.dialog(self, "CAN'T START DUEL", message, [["CLOSE", func(): pass]], UI.RED)
