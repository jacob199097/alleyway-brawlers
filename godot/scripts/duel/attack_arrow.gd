extends Node2D
## The curved targeting arrow: a chain of glowing chevrons that arcs from the attacker to its
## target and flows toward it. It follows the mouse while the player aims, and is shown for
## every declared attack.

const SPACING := 30.0
const FLOW := 90.0   # px per second

var from := Vector2.ZERO
var to := Vector2.ZERO
var color := Color("e63946")
var grow := 0.0      # 0..1, how much of the arc is drawn
var locked := false  # snapped onto a valid target (drawn bolder)
var _fade := 1.0
var _tw: Tween


func _ready() -> void:
	visible = false
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


## Show the arrow for a declared attack, drawing it out from the attacker.
func show_attack(a: Vector2, b: Vector2, c: Color) -> void:
	from = a
	to = b
	color = c
	locked = true
	_start()
	_tw = create_tween()
	_tw.tween_property(self, "grow", 1.0, 0.18).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Follow the mouse while the player picks a target.
func aim(a: Vector2, b: Vector2, c: Color, snapped: bool) -> void:
	if not visible or _fade < 1.0:
		_start()
		grow = 1.0
	from = a
	to = b
	color = c
	locked = snapped


func hide_arrow(seconds := 0.15) -> void:
	if not visible:
		return
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "_fade", 0.0, seconds)
	_tw.tween_callback(func(): visible = false)


func _start() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_fade = 1.0
	visible = true


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _point(t: float, ctrl: Vector2) -> Vector2:
	return from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t)


func _draw() -> void:
	var span := to - from
	var length := span.length()
	if length < 10.0:
		return
	# Arc upward on screen, more for longer shots
	var lift := Vector2(0, -1) * clampf(length * 0.32, 40.0, 260.0)
	var ctrl := from.lerp(to, 0.5) + lift
	var steps := int(length * 1.2 / SPACING) + 2
	var shift := fmod(Time.get_ticks_msec() / 1000.0 * FLOW, SPACING) / (length * 1.2)
	var a := _fade * (1.0 if locked else 0.8)
	for i in steps:
		var t := float(i) / steps + shift
		if t > grow * 0.93 or t < 0.06:
			continue
		var p := _point(t, ctrl)
		var dir := (_point(t + 0.01, ctrl) - p).normalized()
		var side := dir.orthogonal()
		var w := lerpf(7.0, 15.0, t) * (1.2 if locked else 1.0)
		var tip := p + dir * w * 0.9
		var c := Color(color, a * lerpf(0.35, 1.0, t))
		draw_colored_polygon(PackedVector2Array([tip, p - dir * w * 0.3 + side * w, p, p - dir * w * 0.3 - side * w]), c)
	# Head and a target ring at the end of the arc
	var end_t := grow * 0.96
	var hp := _point(end_t, ctrl)
	var hd := (hp - _point(end_t - 0.02, ctrl)).normalized()
	var hs := hd.orthogonal()
	var hw := 26.0 if locked else 22.0
	var head := PackedVector2Array([hp + hd * hw * 1.2, hp - hd * hw * 0.5 + hs * hw, hp - hd * hw * 0.1, hp - hd * hw * 0.5 - hs * hw])
	draw_colored_polygon(head, Color(color, a))
	draw_colored_polygon(head, Color(1, 1, 1, a * 0.35))
	if grow >= 0.99:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 110.0)
		draw_arc(to, 46.0 + pulse * 6.0, 0, TAU, 40, Color(color, a * 0.8), 4.0 if locked else 2.5)
