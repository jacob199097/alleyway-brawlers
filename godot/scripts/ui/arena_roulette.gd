extends Control
## The arena for a 1v1 match, picked like a slot machine: a box that flicks through the arenas
## (data/arenas.json), slows down and lands on the one the match is played in, with a flash.
##   const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")   (no class_name: patches can't add one)
##   var r = ArenaRoulette.spin(parent, "rooftop", Vector2(1500, 820)); await r.landed
## The duel shows the same arena (Game.duel_setup.arena, or the server's start.arena).

signal landed(id: String)

const SIZE := Vector2(440, 290)
const PIC := Vector2(412, 204)

var _final := ""
var _pic: TextureRect
var _name: Label
var _frame: Panel
var done := false


## Every 1v1 arena: [{id, name, image}].
static func arenas() -> Array:
	var f := FileAccess.open("res://data/arenas.json", FileAccess.READ)
	var list = JSON.parse_string(f.get_as_text()) if f else null
	var out: Array = []
	if list is Array:
		for a in list:
			if a is Dictionary and ResourceLoader.exists("res://assets/" + str(a.get("image", ""))):
				out.append(a)
	return out


static func find(id: String) -> Dictionary:
	for a in arenas():
		if str(a.id) == id:
			return a
	return {}


static func random_id() -> String:
	var list := arenas()
	return str(list.pick_random().id) if not list.is_empty() else ""


static func spin(parent: Node, id: String, at: Vector2) -> Control:
	var r: Control = load("res://scripts/ui/arena_roulette.gd").new()
	r._final = id
	r.position = at
	parent.add_child(r)
	return r


func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	_frame = Panel.new()
	_frame.size = SIZE
	_frame.add_theme_stylebox_override("panel", UI._glow(UI.box(Color(0.03, 0.03, 0.08, 0.94), UI.GOLD, 2, 12), UI.GOLD, 0.6))
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


func _show(a: Dictionary) -> void:
	_pic.texture = UI.tex(str(a.get("image", "")))
	_name.text = str(a.get("name", "")).to_upper()


## Flicks through the arenas, quick then slowing, ending on the chosen one.
func _run() -> void:
	var list := arenas()
	if list.is_empty():
		done = true
		landed.emit(_final)
		return
	var final := find(_final)
	if final.is_empty():
		final = list[0]
	var steps := 18 + randi() % 4
	var at := randi() % list.size()
	for i in steps:
		at = (at + 1) % list.size()
		_show(list[at])
		var k := float(i) / steps
		_pic.modulate = Color(0.95, 0.95, 1.05)
		Sfx.play("click", 1.5 - 0.4 * k, -10.0)
		await get_tree().create_timer(lerpf(0.05, 0.3, k * k)).timeout
		if not is_inside_tree():
			return
	# The landing
	_show(final)
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
	await get_tree().create_timer(0.6).timeout
	done = true
	landed.emit(str(final.id))
