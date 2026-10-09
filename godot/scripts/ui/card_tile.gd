class_name CardTile
extends Control
## A card in a menu grid: art with a rarity border, name, and optional corner badges.
## Left-click → pressed, right-click → zoomed. Lifts slightly on hover.

signal pressed(tile: CardTile)
signal zoomed(tile: CardTile)
signal hovered(tile: CardTile)

var card: Dictionary = {}
var badge := ""          # top-right, e.g. "1/3"
var count_badge := ""    # bottom-left, e.g. "×2"
var dimmed := false: set = set_dimmed

var _art: TextureRect
var _name: Label
var _hover := false
var _overlay: Control


static func make(c: Dictionary, size := Vector2(150, 212)) -> CardTile:
	var t := CardTile.new()
	t.card = c
	t.custom_minimum_size = size
	t.size = size
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size / 2
	var art_tex := UI.card_art(card)
	_art = UI.texture_rect(art_tex, size - Vector2(8, 8))
	_art.position = Vector2(4, 4)
	add_child(_art)
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
	mouse_entered.connect(func():
		_hover = true
		hovered.emit(self)
		create_tween().tween_property(self, "scale", Vector2.ONE * 1.05, 0.08)
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.1)
		queue_redraw())
	set_dimmed(dimmed)


func set_dimmed(v: bool) -> void:
	dimmed = v
	modulate = Color(0.45, 0.45, 0.5) if v else Color.WHITE
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
			elif _down_at.distance_to(e.position) < 12 and not get_viewport().gui_is_dragging():
				pressed.emit(self)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			zoomed.emit(self)
			accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.4))
	draw_rect(r, Color("0d1020"))
	var col := UI.rarity_color(card.get("rarity"))
	draw_rect(r, UI.GOLD if _hover else col, false, 4.0 if _hover else 3.0)


func _draw_overlay() -> void:
	var f := UI.font()
	if badge != "":
		var br := Rect2(size.x - 64, 6, 58, 28)
		_overlay.draw_rect(br, Color(0, 0, 0, 0.85))
		_overlay.draw_string(f, br.position + Vector2(0, 22), badge, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 20, UI.GOLD)
	if count_badge != "":
		var cr := Rect2(6, size.y - 34, 56, 28)
		_overlay.draw_rect(cr, Color(0, 0, 0, 0.85))
		_overlay.draw_rect(cr, UI.BLUE, false, 2.0)
		_overlay.draw_string(f, cr.position + Vector2(0, 22), count_badge, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 20, UI.BLUE)
