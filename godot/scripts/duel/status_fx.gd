extends RefCounted
## Status icons and badges: each status as a small picture drawn in code (a flame for BURN, a snowflake for
## FREEZE...), so a card in play, the battle log and the card panel all show the same mark.
## (No class_name: a patch can't add one. Use it through a preload.)

const INK := Color(0.035, 0.04, 0.085, 0.96)


static func _pts(c: Vector2, r: float, raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(c + Vector2(p[0], p[1]) * r)
	return out


## The picture for a status, inside a circle of radius r around c.
static func icon(L: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	var lite := col.lightened(0.55)
	var w := maxf(1.2, r * 0.2)
	match kind:
		"burn":
			L.draw_colored_polygon(_pts(c, r, [[0.05, -1.0], [0.3, -0.5], [0.68, -0.05], [0.66, 0.5], [0.34, 0.92], [-0.34, 0.92], [-0.66, 0.5], [-0.6, 0.0], [-0.34, -0.3], [-0.22, 0.05], [-0.1, -0.45]]), col)
			L.draw_colored_polygon(_pts(c, r, [[0.04, -0.15], [0.32, 0.38], [0.2, 0.8], [-0.2, 0.8], [-0.32, 0.42]]), lite)
		"poison":   # a flask, bubbling
			L.draw_colored_polygon(_pts(c, r, [[-0.24, -0.92], [0.24, -0.92], [0.24, -0.3], [0.8, 0.72], [0.62, 0.92], [-0.62, 0.92], [-0.8, 0.72], [-0.24, -0.3]]), col)
			L.draw_line(c + Vector2(-0.4, -0.92) * r, c + Vector2(0.4, -0.92) * r, lite, w, true)
			L.draw_circle(c + Vector2(-0.2, 0.5) * r, r * 0.17, INK)
			L.draw_circle(c + Vector2(0.22, 0.24) * r, r * 0.12, INK)
		"bleed":   # a drop
			L.draw_colored_polygon(_pts(c, r, [[0.0, -1.0], [0.5, -0.1], [0.62, 0.3], [0.5, 0.68], [0.22, 0.9], [-0.22, 0.9], [-0.5, 0.68], [-0.62, 0.3], [-0.5, -0.1]]), col)
			L.draw_arc(c + Vector2(0.0, 0.3) * r, r * 0.36, 0.3, 1.5, 8, lite, w * 0.8, true)
		"shock":
			L.draw_colored_polygon(_pts(c, r, [[0.28, -1.0], [-0.55, 0.12], [-0.06, 0.12], [-0.3, 1.0], [0.58, -0.2], [0.08, -0.2]]), col.lerp(Color.WHITE, 0.25))
		"freeze":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0 + PI / 2.0)
				L.draw_line(c - d * r * 0.95, c + d * r * 0.95, lite, w, true)
				for sgn in [-1.0, 1.0]:
					var tip: Vector2 = c + d * r * 0.6 * sgn
					for turn in [-0.75, 0.75]:
						L.draw_line(tip, tip + d.rotated(turn) * r * 0.34 * sgn, lite, w * 0.75, true)
		"stasis":   # an hourglass
			L.draw_colored_polygon(_pts(c, r, [[-0.6, -0.85], [0.6, -0.85], [0.0, 0.0]]), col)
			L.draw_colored_polygon(_pts(c, r, [[-0.6, 0.85], [0.6, 0.85], [0.0, 0.0]]), lite)
			for y in [-0.92, 0.92]:
				L.draw_line(c + Vector2(-0.75, y) * r, c + Vector2(0.75, y) * r, lite, w, true)
		"stun":
			var star := PackedVector2Array()
			for i in 10:
				star.append(c + Vector2.from_angle(i * PI / 5.0 - PI / 2.0) * r * (1.0 if i % 2 == 0 else 0.45))
			L.draw_colored_polygon(star, col)
		"shield":
			L.draw_colored_polygon(_pts(c, r, [[0.0, -0.95], [0.75, -0.62], [0.75, 0.1], [0.45, 0.65], [0.0, 0.98], [-0.45, 0.65], [-0.75, 0.1], [-0.75, -0.62]]), col)
			L.draw_colored_polygon(_pts(c, r, [[0.0, -0.6], [0.0, 0.62], [-0.3, 0.42], [-0.48, 0.05], [-0.48, -0.42]]), lite)
		"blind":   # an eye, struck through
			L.draw_arc(c + Vector2(0, 0.62) * r, r * 1.1, PI * 1.19, PI * 1.81, 14, lite, w, true)
			L.draw_arc(c + Vector2(0, -0.62) * r, r * 1.1, PI * 0.19, PI * 0.81, 14, lite, w, true)
			L.draw_circle(c, r * 0.3, lite)
			L.draw_line(c + Vector2(-0.75, 0.8) * r, c + Vector2(0.75, -0.8) * r, INK, w * 2.4, true)
			L.draw_line(c + Vector2(-0.75, 0.8) * r, c + Vector2(0.75, -0.8) * r, col, w, true)
		"silence":   # a speech bubble, crossed out
			L.draw_colored_polygon(_pts(c, r, [[-0.85, -0.7], [0.85, -0.7], [0.85, 0.35], [-0.1, 0.35], [-0.55, 0.9], [-0.5, 0.35], [-0.85, 0.35]]), col)
			L.draw_line(c + Vector2(-0.38, -0.5) * r, c + Vector2(0.38, 0.14) * r, INK, w, true)
			L.draw_line(c + Vector2(0.38, -0.5) * r, c + Vector2(-0.38, 0.14) * r, INK, w, true)
		"suppress":   # a crosshair
			L.draw_arc(c, r * 0.62, 0.0, TAU, 24, lite, w, true)
			for i in 4:
				var d := Vector2.from_angle(i * PI / 2.0)
				L.draw_line(c + d * r * 0.35, c + d * r, lite, w, true)
			L.draw_circle(c, r * 0.14, lite)
		"equipped":   # two links of a chain
			for k in [-1.0, 1.0]:   # (as points: a draw transform here would undo the caller's)
				var link := PackedVector2Array()
				for i in 21:
					var a := i * TAU / 20.0
					link.append(c + Vector2(k * 0.34, -k * 0.2) * r + (Vector2(cos(a), sin(a) * 0.62) * r * 0.56).rotated(-0.6))
				L.draw_polyline(link, lite, w, true)
		"charm":
			var hs := r * 0.5
			L.draw_circle(c + Vector2(-hs * 0.95, -hs * 0.45), hs, col)
			L.draw_circle(c + Vector2(hs * 0.95, -hs * 0.45), hs, col)
			L.draw_colored_polygon(PackedVector2Array([c + Vector2(-hs * 1.9, -hs * 0.1), c + Vector2(hs * 1.9, -hs * 0.1), c + Vector2(0, hs * 1.9)]), col)
		"undead":   # a skull
			L.draw_circle(c + Vector2(0, -0.18) * r, r * 0.72, lite)
			L.draw_rect(Rect2(c + Vector2(-0.4, 0.3) * r, Vector2(0.8, 0.55) * r), lite)
			for k in [-1.0, 1.0]:
				L.draw_circle(c + Vector2(k * 0.3, -0.18) * r, r * 0.2, INK)
			for k in [-0.14, 0.14]:
				L.draw_line(c + Vector2(k, 0.5) * r, c + Vector2(k, 0.85) * r, INK, w * 0.6)
		"resting":   # a Z
			L.draw_polyline(_pts(c, r, [[-0.5, -0.65], [0.5, -0.65], [-0.5, 0.65], [0.5, 0.65]]), lite, w * 1.2, true)
		"guarded":   # a padlock
			L.draw_arc(c + Vector2(0, -0.25) * r, r * 0.42, PI, TAU, 12, lite, w, true)
			L.draw_rect(Rect2(c + Vector2(-0.62, -0.22) * r, Vector2(1.24, 1.0) * r), col)
			L.draw_circle(c + Vector2(0, 0.22) * r, r * 0.17, INK)
		"downed":   # an arrow driven down
			L.draw_colored_polygon(_pts(c, r, [[-0.28, -0.9], [0.28, -0.9], [0.28, 0.05], [0.72, 0.05], [0.0, 0.92], [-0.72, 0.05], [-0.28, 0.05]]), col)
		# The battle log's own marks (what happened, where no status says it)
		"attack":   # a blade
			L.draw_colored_polygon(_pts(c, r, [[0.95, -0.95], [0.42, -0.74], [-0.42, 0.1], [-0.1, 0.42], [0.74, -0.42]]), lite)
			L.draw_line(c + Vector2(-0.72, -0.12) * r, c + Vector2(0.12, 0.72) * r, col, w * 1.3, true)
			L.draw_line(c + Vector2(-0.36, 0.36) * r, c + Vector2(-0.86, 0.86) * r, col, w * 1.3, true)
		"hit":   # Morale lost: a heart, cracked
			var hs := r * 0.5
			L.draw_circle(c + Vector2(-hs * 0.95, -hs * 0.45), hs, col)
			L.draw_circle(c + Vector2(hs * 0.95, -hs * 0.45), hs, col)
			L.draw_colored_polygon(PackedVector2Array([c + Vector2(-hs * 1.9, -hs * 0.1), c + Vector2(hs * 1.9, -hs * 0.1), c + Vector2(0, hs * 1.9)]), col)
			L.draw_polyline(_pts(c, r, [[0.12, -0.6], [-0.18, -0.15], [0.16, 0.12], [-0.04, 0.7]]), INK, w, true)
		"plus":
			L.draw_line(c + Vector2(-0.78, 0) * r, c + Vector2(0.78, 0) * r, lite, w * 1.7)
			L.draw_line(c + Vector2(0, -0.78) * r, c + Vector2(0, 0.78) * r, lite, w * 1.7)
		"spark":   # a four-point star: a card's effect
			var spark := PackedVector2Array()
			for i in 8:
				spark.append(c + Vector2.from_angle(i * PI / 4.0 - PI / 2.0) * r * (1.05 if i % 2 == 0 else 0.3))
			L.draw_colored_polygon(spark, lite)
		"up":   # an arrow driven up
			L.draw_colored_polygon(_pts(c, r, [[-0.28, 0.9], [0.28, 0.9], [0.28, -0.05], [0.72, -0.05], [0.0, -0.92], [-0.72, -0.05], [-0.28, -0.05]]), col)
		"crown":
			L.draw_colored_polygon(_pts(c, r, [[-0.85, 0.7], [-0.92, -0.5], [-0.42, 0.02], [0.0, -0.82], [0.42, 0.02], [0.92, -0.5], [0.85, 0.7]]), col)
			L.draw_line(c + Vector2(-0.85, 0.72) * r, c + Vector2(0.85, 0.72) * r, lite, w, true)
		"ko":   # crossed out
			L.draw_line(c + Vector2(-0.7, -0.7) * r, c + Vector2(0.7, 0.7) * r, col, w * 1.7, true)
			L.draw_line(c + Vector2(0.7, -0.7) * r, c + Vector2(-0.7, 0.7) * r, col, w * 1.7, true)
		"card":   # a card, its back to you
			L.draw_rect(Rect2(c + Vector2(-0.58, -0.82) * r, Vector2(1.16, 1.64) * r), col)
			L.draw_rect(Rect2(c + Vector2(-0.34, -0.56) * r, Vector2(0.68, 1.12) * r), INK, false, maxf(1.0, w * 0.7))
		"back":   # an arrow turning back
			L.draw_arc(c + Vector2(0.0, 0.1) * r, r * 0.6, -PI * 0.5, PI * 0.75, 12, lite, w * 1.2, true)
			L.draw_colored_polygon(_pts(c, r, [[0.0, -0.95], [0.0, -0.05], [-0.62, -0.5]]), lite)
		_:
			L.draw_circle(c, r * 0.45, col)


## A badge: the icon on a dark disc ringed in its colour. `parts` cuts the ring into that many arcs (the
## turns a timed status has left; 0: a whole ring). `text` sits on a plate to its right, in the game's
## lettering. Returns the badge's full width.
static func badge(L: CanvasItem, kind: String, at: Vector2, r: float, col: Color, text := "", parts := 0, pop := 0.0, open := 1.0) -> float:
	var font: Font = UI.font_of("label")
	var fs := int(round(r * 1.25))
	var width := r * 2.0
	if text != "" and open > 0.01:
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pw := (tw + r * 1.9) * open
		var plate := StyleBoxFlat.new()
		plate.bg_color = INK
		plate.border_color = Color(col, 0.55)
		plate.set_border_width_all(1)
		plate.set_corner_radius_all(int(r * 0.8))
		plate.anti_aliasing = true
		var h := r * 1.5
		L.draw_style_box(plate, Rect2(at.x, at.y - h / 2.0, pw + r * 0.2, h))
		if open > 0.85:
			L.draw_string(font, Vector2(at.x + r * 1.3, at.y + fs * 0.34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.6), (open - 0.85) / 0.15))
		width = r + pw + r * 0.2
	var rr := r * (1.0 + 0.45 * pop)
	L.draw_circle(at + Vector2(0, 1.5), rr + 1.5, Color(0, 0, 0, 0.45))
	L.draw_circle(at, rr, INK)
	if pop > 0.01:
		L.draw_circle(at, rr, Color(col, 0.45 * pop))
	if parts <= 1:
		L.draw_arc(at, rr, 0.0, TAU, 32, col, maxf(1.5, r * 0.16), true)
	else:   # (one arc per turn left)
		var gap := 0.42
		for i in parts:
			var a0 := -PI / 2.0 + i * TAU / parts + gap / 2.0
			L.draw_arc(at, rr, a0, a0 + TAU / parts - gap, 10, col, maxf(1.8, r * 0.2), true)
	icon(L, kind, at, rr * 0.6, col)
	return width
