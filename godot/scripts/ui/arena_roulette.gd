extends Control
## The arena for a 1v1 match, picked like a slot machine: a box that flicks through the arenas
## (data/arenas.json), slows down and lands on the one the match is played in, with a flash.
##   const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")   (no class_name: patches can't add one)
##   var r = ArenaRoulette.spin(parent, "rooftop", Vector2(1500, 820)); await r.landed
## The duel shows the same arena (Game.duel_setup.arena, or the server's start.arena). with_effect: the match
## has the arena's effect (not Ranked, not the weekly challenge): it's shown above the box once it lands.
## It shows the arenas' small copies (thumb: assets/arena_thumbs, 640 wide; a 4K arena picture is ~40 MB
## loaded), loading in the background (ResourceLoader's threads): the spin shows only those ready, so a first
## spin after starting the game never waits on a picture.

signal landed(id: String)

const SIZE := Vector2(440, 290)
const PIC := Vector2(412, 204)

var _final := ""
var _pic: TextureRect
var _name: Label
var _frame: Panel
var done := false
var instant := false   # the arena is known (a turf map district): show it, no spin
var ffa := false       # a free-for-all's spin: the Crossroads is in it too
var with_effect := false   # the match has the arena's effect: say what it is once it lands
var _pics := {}        # picture path -> Texture2D, this spin's (_pic_of)
## The free-for-all's own arena (not a 1v1 one, so not in arenas.json or on the turf map)
const CROSSROADS := {"id": "crossroads", "name": "The Crossroads", "image": "arena_ffa.jpg"}


## Every 1v1 arena: [{id, name, image}] (with_crossroads: and the free-for-all's Crossroads).
static func arenas(with_crossroads := false) -> Array:
	var f := FileAccess.open("res://data/arenas.json", FileAccess.READ)
	var list = JSON.parse_string(f.get_as_text()) if f else null
	var out: Array = []
	if list is Array:
		for a in list:
			if a is Dictionary and ResourceLoader.exists("res://assets/" + str(a.get("image", ""))):
				out.append(a)
	if with_crossroads and ResourceLoader.exists("res://assets/" + CROSSROADS.image):
		out.append(CROSSROADS)
	return out


## Where an arena picture's small copy is (tools/make_arena_thumbs.gd), else the picture itself.
static func thumb_path(image: String) -> String:
	var small := "res://assets/arena_thumbs/" + image
	return small if ResourceLoader.exists(small) else "res://assets/" + image


## An arena picture for showing it small (a tile, a panel): its small copy, else the picture.
static func thumb(image: String) -> Texture2D:
	var path := thumb_path(image)
	return load(path) if path.contains("/arena_thumbs/") else UI.tex(image)


static func find(id: String) -> Dictionary:
	for a in arenas(true):
		if str(a.id) == id:
			return a
	return {}


## An arena's effect in words (its data/arenas.json "bonus", the server's rules.arena_bonus): a sentence for
## each thing it changes, e.g. "Every BURN and STOKE effect is 100 stronger." ("" without one).
static func bonus_text(b: Dictionary) -> String:
	var out: Array = []
	var kinds: Array = b.boost if b.get("boost") is Array else ([b.boost] if str(b.get("boost", "")) != "" else [])
	var n := int(b.get("amount", 0))
	var named: Array = []
	for k in kinds:
		match str(k):
			"damage":   # (a card's "loses 600 Morale")
				out.append("Every card effect that makes a player lose Morale takes %d more (not BURN or DRAIN)." % n)
			"plunder":
				out.append("Every PLUNDER from a hand or deck takes %d more card%s." % [n, "" if n == 1 else "s"])
			_:
				named.append(str(k).to_upper())
	if not named.is_empty():
		var list: String = ", ".join(named.slice(0, -1)) + " and " + str(named[-1]) if named.size() > 1 else str(named[0])
		out.push_front("Every %s effect is %d stronger." % [list, n])
	var stats: Array = []
	for k in ["atk", "def"]:
		if int(b.get(k, 0)) != 0:
			stats.append("%+d %s" % [int(b[k]), k.to_upper()])
	if not stats.is_empty():
		out.append("Every character gets %s." % " and ".join(stats))
	if int(b.get("direct", 0)) > 0:
		out.append("Direct attacks deal %d more Morale damage." % int(b.direct))
	if int(b.get("authority", 0)) > 0:
		out.append("Every player gets %d extra Authority each turn." % int(b.authority))
	if int(b.get("draw", 0)) > 0:
		out.append("Every player draws %d extra card%s each turn." % [int(b.draw), "" if int(b.draw) == 1 else "s"])
	var m := int(b.get("morale", 0))
	if m != 0:
		out.append("Every player %s %d Morale at the start of their turn." % ["regains" if m > 0 else "loses", absi(m)])
	return " ".join(out)


static func random_id() -> String:
	var list := arenas()
	return str(list.pick_random().id) if not list.is_empty() else ""


static func spin(parent: Node, id: String, at: Vector2, known := false, for_ffa := false, effect := false) -> Control:
	var r: Control = load("res://scripts/ui/arena_roulette.gd").new()
	r._final = id
	r.instant = known
	r.ffa = for_ffa
	r.with_effect = effect
	r.position = at
	parent.add_child(r)
	return r


func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	_frame = Panel.new()
	_frame.size = SIZE
	_frame.add_theme_stylebox_override("panel", UI._shadowed(UI.box(Color(0.03, 0.03, 0.08, 0.94), UI.STEEL, 2, 12)))
	add_child(_frame)
	var head := UI.label("ARENA", 18, UI.GOLD, true)
	head.position = Vector2(14, 8)
	add_child(head)
	_pic = UI.texture_rect(null, PIC, true)
	_pic.position = Vector2((SIZE.x - PIC.x) / 2, 36)
	_pic.clip_contents = true
	add_child(_pic)
	_name = UI.label("", 26, Color.WHITE, true)
	_name.size = Vector2(SIZE.x, 34)
	_name.position = Vector2(0, 246)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	modulate.a = 0.0
	position.y += 40
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.25)
	t.tween_property(self, "position:y", position.y - 40, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_run()


func _show(a: Dictionary, wait := false) -> bool:
	var t := _pic_of(a, wait)
	if t == null and not wait:
		return false
	_pic.texture = t
	_name.text = str(a.get("name", "")).to_upper()
	return true


## An arena's picture: loaded in the background (asked for in _run); null while it isn't ready yet, unless
## wait (the one it lands on: waits for it).
func _pic_of(a: Dictionary, wait := false) -> Texture2D:
	var path := thumb_path(str(a.get("image", "")))
	if _pics.has(path):
		return _pics[path]
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_LOADED or (wait and st == ResourceLoader.THREAD_LOAD_IN_PROGRESS):
		_pics[path] = ResourceLoader.load_threaded_get(path)
	elif wait or ResourceLoader.has_cached(path):
		_pics[path] = load(path) if ResourceLoader.exists(path) else null
	return _pics.get(path)


## Flicks through the arenas, quick then slowing, ending on the chosen one.
func _run() -> void:
	var list := arenas(ffa)
	if list.is_empty():
		done = true
		landed.emit(_final)
		return
	var final := find(_final)
	if final.is_empty():
		final = list[0]
	UI.prefetch(str(final.get("image", "")))   # (the match's floor, full size, ready for the duel)
	if not instant:   # every picture starts loading now, in the background
		for a in list + [final]:
			var path := thumb_path(str(a.get("image", "")))
			if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)
	var steps := 0 if instant else 18 + randi() % 4
	var at := randi() % list.size()
	for i in steps:
		for tries in list.size():   # the next arena whose picture is ready (else the one showing stays)
			at = (at + 1) % list.size()
			if _show(list[at]):
				break
		var k := float(i) / steps
		_pic.modulate = Color(0.95, 0.95, 1.05)
		Sfx.play("click", 1.5 - 0.4 * k, -10.0)
		await get_tree().create_timer(lerpf(0.05, 0.3, k * k)).timeout
		if not is_inside_tree():
			return
	# The landing
	_show(final, true)
	_pic.modulate = Color(1.3, 1.25, 1.3)   # (the arenas are dark in the middle: lift it so it reads)
	Sfx.play("coin_land", 1.1, -4.0)
	pivot_offset = SIZE / 2
	scale = Vector2.ONE * 1.12
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var flash := ColorRect.new()
	flash.size = SIZE
	flash.color = Color(1, 0.95, 0.75, 0.7)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "color:a", 0.0, 0.45)
	ft.tween_callback(flash.queue_free)
	_frame.add_theme_stylebox_override("panel", UI._glow(UI.box(Color(0.05, 0.04, 0.02, 0.96), UI.GOLD, 3, 12), UI.GOLD, 1.4))
	if with_effect and final.get("bonus") is Dictionary:
		_effect_box(final.bonus)
	await get_tree().create_timer(0.6).timeout
	done = true
	landed.emit(str(final.id))


## The arena's effect, above the box: its title and what it does, for both sides.
func _effect_box(b: Dictionary) -> void:
	var p := UI.panel(UI.GOLD, Color(0.03, 0.03, 0.08, 0.94))
	p.custom_minimum_size = Vector2(SIZE.x, 0)
	p.size = Vector2(SIZE.x, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	col.add_child(UI.label("ARENA EFFECT  ·  %s" % str(b.get("title", "")), 18, UI.GOLD, true))
	var what := UI.label(bonus_text(b) + " (Both sides.)", 17, Color(0.9, 0.9, 0.95))
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	col.add_child(what)
	p.modulate.a = 0.0
	add_child(p)
	await get_tree().process_frame   # (its height once laid out: it sits on top of the box)
	if not is_instance_valid(p):
		return
	p.position = Vector2(0, -p.size.y - 10)
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.3)
