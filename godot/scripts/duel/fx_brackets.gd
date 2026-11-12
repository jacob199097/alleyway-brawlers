extends Node2D
## Four corner brackets that lock on to a card as its ability goes off (duel.gd _activate): they close in on
## it, hold, then open out and fade.

var half := Vector2(62, 88)       # half the card's size
var color := Color.WHITE
var arm := 26.0                   # the length of each bracket's arms
var width := 3.0
## How far out from the card the brackets sit, px
var gap := 0.0: set = _set_gap


func _set_gap(v: float) -> void:
	gap = v
	queue_redraw()


func _draw() -> void:
	var h := half + Vector2(gap, gap)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := Vector2(h.x * s.x, h.y * s.y)
		draw_polyline(PackedVector2Array([c - Vector2(arm * s.x, 0), c, c - Vector2(0, arm * s.y)]), color, width, true)
