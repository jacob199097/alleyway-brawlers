class_name CardView
extends Node2D
## One card on screen: art or card back, a glow outline, and an ATK/DEF badge on the field.
## Holds no rules state; the duel screen updates it from event snapshots.

const SIZE := Vector2(124, 175)   # field size; hand and zoom views scale the node

var card: Dictionary = {}
var uid := -1
var side := "player"
var face_up := false
var downed := false: set = set_downed
var show_badge := false: set = set_show_badge
var glow := 0.0: set = set_glow
var glow_color := Color("f4d35e")
var home := Vector2.ZERO
var home_rot := 0.0
var home_scale := 1.0
var busy := false   # flying / animating: ignore hover and layout

var _body := Node2D.new()   # flips (scale.x) independently of the node's own scale
var _front := Sprite2D.new()
var _back := Sprite2D.new()
var _fallback: Label
var _badge: RichTextLabel
var _stats := []
var _tw: Tween


func setup(c: Dictionary, owner_side: String, up: bool) -> CardView:
	side = owner_side
	add_child(_body)
	_body.add_child(_back)
	_body.add_child(_front)
	_back.texture = CardDB.back()
	_fit(_back)

	_badge = RichTextLabel.new()
	_badge.top_level = true
	_badge.bbcode_enabled = true
	_badge.scroll_active = false
	_badge.fit_content = true
	_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.custom_minimum_size = Vector2(SIZE.x + 6, 0)
	_badge.size = Vector2(SIZE.x + 6, 26)
	_badge.add_theme_font_size_override("normal_font_size", 17)
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.08, 0.88)
	sb.set_corner_radius_all(5)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_badge.add_theme_stylebox_override("normal", sb)
	_badge.visible = false
	add_child(_badge)

	set_card(c)
	set_face(up)
	return self


func set_card(c: Dictionary) -> void:
	card = c
	uid = int(c.get("uid", uid))
	var tex: Texture2D = null
	if not c.is_empty():
		tex = CardDB.art(str(c.get("art_url", c.get("id", ""))))
	_front.texture = tex
	_fit(_front)
	if tex == null and not c.is_empty():
		if _fallback == null:
			_fallback = Label.new()
			_fallback.size = SIZE - Vector2(12, 12)
			_fallback.position = -_fallback.size / 2
			_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_fallback.autowrap_mode = TextServer.AUTOWRAP_WORD
			_body.add_child(_fallback)
		_fallback.text = str(c.get("name", "?"))
	set_face(face_up)


func set_face(up: bool) -> void:
	face_up = up
	_front.visible = up and _front.texture != null
	_back.visible = not up
	if _fallback:
		_fallback.visible = up and _front.texture == null
	queue_redraw()


## Turn the card over (awaitable).
func flip(up: bool, duration := 0.24) -> void:
	if up == face_up:
		return
	Sfx.play("flip", randf_range(0.9, 1.15))
	var t := create_tween()
	t.tween_property(_body, "scale:x", 0.0, duration / 2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(set_face.bind(up))
	t.tween_property(_body, "scale:x", 1.0, duration / 2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished


## Squash the card edge-on, swap what it shows, and open it again (used by promotion).
func swap_to(c: Dictionary, duration := 0.3) -> void:
	var t := create_tween()
	t.tween_property(_body, "scale:x", 0.0, duration / 2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		set_card(c)
		set_face(true))
	t.tween_property(_body, "scale:x", 1.0, duration / 2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished


## Tween to a position/scale/rotation, replacing any move already running (awaitable via .finished).
func move_to(pos: Vector2, s: float, rot: float, duration := 0.22,
		trans := Tween.TRANS_CUBIC, ease_type := Tween.EASE_OUT) -> Tween:
	stop_moving()
	_tw = create_tween().set_parallel().set_trans(trans).set_ease(ease_type)
	_tw.tween_property(self, "position", pos, duration)
	_tw.tween_property(self, "scale", Vector2.ONE * s, duration)
	_tw.tween_property(self, "rotation", rot, duration)
	return _tw


func go_home(duration := 0.22) -> Tween:
	return move_to(home, home_scale, home_rot, duration)


func stop_moving() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()


## A quick white hit-flash over the card.
func flash() -> void:
	var r := ColorRect.new()
	r.size = SIZE
	r.position = -SIZE / 2
	r.color = Color(1, 1, 1, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.0, 0.28)
	t.tween_callback(r.queue_free)


func stats() -> Array:
	return _stats


func set_stats(atk: int, def: int, base_atk: int, base_def: int) -> void:
	_stats = [atk, def, base_atk, base_def]
	_update_badge()


func set_downed(v: bool) -> void:
	downed = v
	_body.modulate = Color(1.0, 0.5, 0.5) if v else Color.WHITE
	_update_badge()


func set_show_badge(v: bool) -> void:
	show_badge = v
	_update_badge()


func set_glow(v: float) -> void:
	glow = v
	queue_redraw()


func hit(p_global: Vector2) -> bool:
	return Rect2(-SIZE / 2, SIZE).has_point(to_local(p_global))


func _update_badge() -> void:
	if _badge == null:
		return
	_badge.visible = _badge_wanted()
	if not _badge.visible:
		return
	var atk_col := _stat_color(_stats[0], _stats[2], "ffd86b")
	var def_col := _stat_color(_stats[1], _stats[3], "9ddcff")
	var tag := "[color=#ff5a5a]DOWNED[/color]  " if downed else ""
	_badge.text = "[center]%s[color=#%s]%d[/color] [color=#777]/[/color] [color=#%s]%d[/color][/center]" \
		% [tag, atk_col, _stats[0], def_col, _stats[1]]


static func _stat_color(v: int, base: int, normal: String) -> String:
	if v > base:
		return "5dff8f"
	if v < base:
		return "ff5a5a"
	return normal


## Shown on the field, hidden while flying, and never for the opponent's face-down cards.
func _badge_wanted() -> bool:
	return show_badge and not busy and not _stats.is_empty() and (face_up or side == "player")


func _process(_delta: float) -> void:
	if _badge.visible != _badge_wanted():
		_update_badge()
	if _badge.visible:
		var sideways := absf(sin(rotation)) > 0.7
		var half_h: float = (SIZE.x if sideways else SIZE.y) * scale.y / 2.0
		_badge.global_position = global_position + Vector2(-_badge.size.x / 2.0, half_h - 12.0)
		_badge.z_index = z_index + 1


func _draw() -> void:
	var r := Rect2(-SIZE / 2, SIZE)
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.45))
	if glow > 0.01:
		for i in 3:
			draw_rect(r.grow(3.0 + i * 4.0), Color(glow_color, glow * (0.6 - i * 0.18)), false, 4.0)
	if face_up and _front.texture == null:
		draw_rect(r, Color("161a30"))
		draw_rect(r, Color("b388c9"), false, 2.0)


func _fit(s: Sprite2D) -> void:
	if s.texture:
		s.scale = SIZE / s.texture.get_size()
