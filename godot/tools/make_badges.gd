extends SceneTree
## Draws the level emblems (assets/levels/level_01.png … level_50.png) and the ranked-tier emblems
## (assets/ranks/<tier>.png) in the card-frame style: gunmetal plates, neon trim, dark tinted faces.
## Every level has its own centrepiece (street gear early on, cosmic and royal ones at the top); the
## frame changes with each title bracket in ui.gd (1-4, 5-9 … 45-49, 50) and grows crests, spikes
## and wings as it climbs.
## Run:  godot --headless --path godot --script res://tools/make_badges.gd   then tools/sync_assets.

const MAX_LEVEL := 50
## One per title bracket, the last for level 50.
const TIER_COLORS := ["9aa7b8", "4ade80", "2dd4bf", "38bdf8", "6d7cff", "a46bff", "e05cff", "ff4d8d",
	"ff3b3b", "ff9a3c", "ffd34d"]
## Ranked tiers (backend/economy/postMatch.js RANK_TIERS): name, colour, chevrons, star, crown, wings.
const RANKS := [
	["rookie", "9aa7b8", 1, false, false, false],
	["street_tough", "4ade80", 2, false, false, false],
	["enforcer", "38bdf8", 3, false, false, false],
	["underboss", "a46bff", 2, true, false, false],
	["kingpin", "ff3b3b", 2, false, true, false],
	["legend", "ffd34d", 3, false, true, true],
]

const SPADE := "M0,-20 C-6,-8 -22,-2 -18,9 C-15,17 -6,17 -2,10 L-6,22 L6,22 L2,10 C6,17 15,17 18,9 C22,-2 6,-8 0,-20 Z"
const FLAME := "M0,-48 C14,-28 34,-14 30,12 C28,34 14,46 0,46 C-14,46 -30,34 -30,14 C-30,-2 -18,-10 -14,-24 C-8,-14 -6,-8 -2,-4 C2,-18 2,-34 0,-48 Z"
const FLAME_CORE := "M0,0 C8,10 14,18 12,28 C10,38 4,42 0,42 C-6,42 -12,36 -12,28 C-12,18 -4,12 0,0 Z"
const CROWN := "M-40,26 L-42,-20 L-20,-2 L0,-36 L20,-2 L42,-20 L40,26 Z"
const WING := "M-8,8 C-22,-16 -38,-30 -52,-34 C-48,-26 -47,-20 -46,-14 C-51,-12 -53,-6 -53,-1 C-47,-1 -45,3 -44,6 C-47,10 -47,14 -45,18 C-32,22 -18,20 -8,8 Z"
const HEART := "M0,40 C-30,18 -44,2 -44,-16 C-44,-34 -22,-42 0,-24 C22,-42 44,-34 44,-16 C44,2 30,18 0,40 Z"

var _col := ""   # the colour of the emblem being drawn


func _init() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../assets")
	DirAccess.make_dir_recursive_absolute(root.path_join("levels"))
	DirAccess.make_dir_recursive_absolute(root.path_join("ranks"))
	for lv in range(1, MAX_LEVEL + 1):
		if FileAccess.file_exists(root.path_join("levels/chatgpt/level_%02d.png" % lv)):
			continue   # drawn in ChatGPT instead (tools/import_level_icons.gd)
		_save(_level_svg(lv), root.path_join("levels/level_%02d.png" % lv), 1.0)
	for r in RANKS:
		_save(_rank_svg(r), root.path_join("ranks/%s.png" % r[0]), 2.0)
	print("Emblems written to ", root.simplify_path())
	quit()


func _save(svg: String, path: String, scale: float) -> void:
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		push_error("SVG failed for %s" % path)
		return
	img.save_png(path)


# ── Level emblems (256×256) ───────────────────────────────────────────────────

func _level_svg(lv: int) -> String:
	var t := lv / 5
	_col = TIER_COLORS[t]
	var f := _frame(t)
	var s: String = _head(256) + f.behind
	s += _glow(f.outer)
	s += '<path d="%s" fill="url(#metal)" stroke="#0a0a12" stroke-width="3"/>' % f.outer
	s += '<path d="%s" fill="url(#face)"/>' % f.inner
	s += _neon(f.inner, 3)
	s += f.front
	s += _g("translate(128,%s) scale(%s)" % [f.cy, f.scale], _symbol(lv))
	return s + "</svg>"


## The frame for a title bracket: {behind, outer, inner, front, cy, scale}.
func _frame(t: int) -> Dictionary:
	var f := {"behind": "", "front": "", "cy": 128, "scale": 1.0}
	match t:
		0:   # plain disc
			f.outer = _c(128, 128, 82)
			f.inner = _c(128, 128, 70)
		1:   # cut-corner plate, like the card's cost box
			f.outer = _oct(128, 128, 82, 82, 26)
			f.inner = _oct(128, 128, 70, 70, 21)
			f.front = _stripes(128 - 76, 128) + _stripes(128 + 76, 128)
		2:   # riveted hexagon
			f.outer = _poly(128, 128, 6, 94, -90)
			f.inner = _poly(128, 128, 6, 80, -90)
			for i in 6:
				var a := deg_to_rad(-90 + i * 60)
				f.front += _part(_c(128 + cos(a) * 87, 128 + sin(a) * 87, 5))
		3:   # shield
			f.outer = "M48,34 L208,34 L208,122 C208,174 168,210 128,232 C88,210 48,174 48,122 Z"
			f.inner = "M60,46 L196,46 L196,122 C196,166 162,198 128,218 C94,198 60,166 60,122 Z"
			f.front = _stripes(54, 90) + _stripes(202, 90)
			f.cy = 122
			f.scale = 0.95
		4:   # diamond with side blades
			var blade := _part("M6,128 L44,108 L64,128 L44,148 Z")
			f.behind = blade + _g("translate(256,0) scale(-1,1)", blade)
			f.outer = _poly(128, 128, 4, 104, -90)
			f.inner = _poly(128, 128, 4, 88, -90)
			f.scale = 1.0
		5:   # octagon with a crest and short wings
			f.behind = _mirror(_part("M60,80 L18,58 L30,104 L58,116 Z")) + _part("M96,44 L106,12 L150,12 L160,44 Z")
			f.outer = _poly(128, 128, 8, 90, 22.5)
			f.inner = _poly(128, 128, 8, 77, 22.5)
			f.front = _neon("M116,30 L128,22 L140,30", 4)
		6:   # spiked starburst
			f.behind = _part(_starp(128, 128, 8, 116, 84, -90))
			f.outer = _c(128, 128, 82)
			f.inner = _c(128, 128, 70)
		7:   # winged shield with a crest
			f.behind = _mirror(_part("M60,70 L12,46 L26,98 L56,112 Z") + _part("M58,118 L10,112 L30,150 L64,160 Z"))
			f.behind += _part("M100,40 L110,8 L146,8 L156,40 Z")
			f.outer = "M48,34 L208,34 L208,122 C208,174 168,210 128,232 C88,210 48,174 48,122 Z"
			f.inner = "M60,46 L196,46 L196,122 C196,166 162,198 128,218 C94,198 60,166 60,122 Z"
			f.front = _neon("M118,24 L128,16 L138,24", 4)
			f.cy = 122
			f.scale = 0.95
		8:   # spiked ring with a bottom tab and wings
			f.behind = _mirror(_part("M56,96 L6,72 L18,124 L50,136 Z"))
			f.behind += _part(_starp(128, 128, 12, 112, 86, -90)) + _part("M100,206 L156,206 L146,244 L110,244 Z")
			f.outer = _c(128, 128, 80)
			f.inner = _c(128, 128, 68)
			f.front = _neon("M118,224 L128,232 L138,224", 4)
		9:   # crowned hexagon with great wings
			f.behind = _mirror(_part("M58,74 L8,40 L16,100 L48,114 Z") + _part("M52,120 L2,108 L18,154 L56,164 Z")
				+ _part("M62,164 L20,174 L50,200 L84,194 Z"))
			f.behind += _part("M92,52 L88,8 L108,26 L128,2 L148,26 L168,8 L164,52 Z")
			f.outer = _poly(128, 132, 6, 88, 0)
			f.inner = _poly(128, 132, 6, 75, 0)
			f.cy = 132
			f.scale = 0.9
		_:   # level 50: rays, double wings, crown
			f.behind = _part(_starp(128, 128, 16, 126, 92, -90))
			f.behind += _mirror(_part("M58,74 L4,36 L12,100 L48,114 Z") + _part("M52,120 L0,108 L16,156 L56,166 Z")
				+ _part("M62,166 L18,180 L50,206 L86,196 Z"))
			f.behind += _part("M90,54 L84,4 L106,24 L128,2 L150,24 L172,4 L166,54 Z")
			f.outer = _poly(128, 132, 8, 86, 22.5)
			f.inner = _poly(128, 132, 8, 73, 22.5)
			f.cy = 132
			f.scale = 0.9
	return f


## The centrepiece for a level, drawn around (0, 0) in about ±50.
func _symbol(lv: int) -> String:
	match lv:
		1: return _fist()
		2: return _knuckles()
		3: return _g("translate(-6,4)", _spray())
		4: return _g("rotate(35)", _bat())
		5: return _g("rotate(-30)", _switchblade())
		6: return _g("translate(-26,-14) rotate(-35)", _link()) + _g("rotate(35)", _link()) + _g("translate(26,14) rotate(-35)", _link())
		7: return _padlock()
		8: return _g("translate(-18,-8) rotate(-14)", _die([[-10, -10], [10, -10], [0, 0], [-10, 10], [10, 10]])) \
			+ _g("translate(20,12) rotate(12)", _die([[-10, -10], [0, 0], [10, 10]]))
		9: return _card()
		10: return _skull()
		11: return _g("rotate(-35)", _bat()) + _g("rotate(35)", _bat())
		12: return _fill("M8,-48 L-26,6 L-4,6 L-12,48 L26,-8 L4,-8 Z")
		13: return _flame()
		14: return _fill(_starp(0, 0, 5, 48, 20, -90)) + _light(_starp(0, 0, 5, 18, 8, -90), 0.7)
		15: return _neon(_c(0, 0, 30), 6) + _neon("M0,-48 L0,-14 M0,14 L0,48 M-48,0 L-14,0 M14,0 L48,0", 6) + _fill(_c(0, 0, 6))
		16: return _eight_ball()
		17: return _g("translate(0,-2) scale(2.3)", _fill(SPADE))
		18: return _gem()
		19: return _fill(HEART) + _g("rotate(35)", _dagger())
		20: return _g("translate(0,10) scale(1.25)", _dagger())
		21: return _g("translate(0,6) rotate(-38)", _dagger()) + _g("translate(0,6) rotate(38)", _dagger())
		22: return _g("rotate(-35)", _bone()) + _g("rotate(35)", _bone()) + _g("translate(0,-4) scale(0.8)", _skull())
		23: return _crown()
		24: return _wings() + _fill(_c(0, 4, 10))
		25: return _bomb()
		26: return _molotov()
		27: return _planet()
		28: return _g("rotate(35)", _rocket())
		29: return _comet()
		30: return _fill("M8,-43.3 A44,44 0 1,0 8,43.3 A50,50 0 0,1 8,-43.3 Z") + _fill(_starp(26, -4, 5, 15, 6, -90))
		31: return _eye()
		32: return _g("rotate(20)", _fill("M0,-48 L10,-10 L48,0 L10,10 L0,48 L-10,10 L-48,0 L-10,-10 Z") + _dark(_c(0, 0, 7)))
		33: return _demon()
		34: return _fill("M-36,-42 L36,-42 L36,0 C36,22 18,38 0,46 C-18,38 -36,22 -36,0 Z") \
			+ _light(_rr(-6, -32, 12, 62, 2), 0.9) + _light(_rr(-24, -16, 48, 12, 2), 0.9)
		35: return _anchor()
		36: return _hourglass()
		37: return _g("rotate(-8)", _key())
		38: return _gear()
		39: return _atom()
		40: return _fill(_starp(-28, 12, 5, 19, 8, -90)) + _fill(_starp(28, 12, 5, 19, 8, -90)) + _fill(_starp(0, -18, 5, 25, 10, -90))
		41: return _fill(_starp(0, 0, 12, 48, 30, -90)) + _dark(_c(0, 0, 21)) + _fill(_c(0, 0, 14))
		42: return _g("translate(0,4) scale(1.05)", _wings()) + _g("translate(0,-2) scale(0.75)", _flame())
		43: return _slashes()
		44: return _g("rotate(-40)", _sword()) + _g("rotate(40)", _sword())
		45: return _trident()
		46: return _g("translate(0,10) scale(0.85)", _skull()) + _g("translate(0,-36) scale(0.5)", _crown())
		47: return _galaxy()
		48: return _g("translate(0,6) scale(1.1)", _crown()) + _gemmed(0, -30, 9)
		49: return _g("scale(1.1)", _wings()) + _g("translate(0,2) scale(0.7)", _skull())
		_: return _g("scale(1.05)", _wings()) + _fill(_starp(0, 4, 5, 32, 13, -90)) \
			+ _light(_starp(0, 4, 5, 12, 5, -90), 0.85) + _g("translate(0,-38) scale(0.42)", _crown())


# ── Centrepieces ──────────────────────────────────────────────────────────────

func _fist() -> String:
	var s := _fill(_rr(-34, -8, 68, 42, 12))
	for i in 4:
		s += _fill(_rr(-34 + i * 17, -36, 17, 32, 7))
	return s + _fill(_rr(-40, 2, 48, 16, 8))


func _knuckles() -> String:
	var s := _fill("M-30,18 C-20,42 20,42 30,18 Z")
	for x in [-33, -11, 11, 33]:
		s += _fill("M%d,-18 L%d,-34 L%d,-18 Z" % [x - 6, x, x + 6])
	s += _fill(_rr(-46, -20, 92, 40, 14))
	for x in [-33, -11, 11, 33]:
		s += _dark(_c(x, -4, 8.5))
	return s


func _spray() -> String:
	var s := ""
	for p in [[18, -44, 4], [28, -36, 3], [34, -48, 3.5], [24, -54, 2.5], [42, -40, 2.5]]:
		s += _light(_c(p[0], p[1], p[2]), 0.9)
	s += _fill(_rr(-4, -46, 8, 10, 2)) + _fill(_rr(-13, -38, 26, 14, 4)) + _fill(_rr(-17, -26, 34, 70, 7))
	return s + _darkline("M-14,4 L14,4", 8) + _light(_rr(-11, -20, 5, 54, 2), 0.35)


func _bat() -> String:
	return _fill(_rr(-8, 40, 16, 8, 3)) \
		+ _fill("M-4,42 L-4,14 C-6,0 -13,-16 -13,-32 C-13,-42 -7,-48 0,-48 C7,-48 13,-42 13,-32 C13,-16 6,0 4,14 L4,42 Z") \
		+ _lightline("M-4,26 L4,22 M-4,34 L4,30", 2)


func _switchblade() -> String:
	return _fill("M-7,-6 L-7,-52 C4,-46 10,-30 8,-6 Z") + _fill(_rr(-10, -8, 20, 54, 7)) \
		+ _dark(_c(0, 2, 3)) + _dark(_c(0, 38, 3)) + _lightline("M-3,10 L-3,30", 2)


func _link() -> String:
	return _neon(_rr(-20, -10, 40, 20, 10), 6)


func _padlock() -> String:
	return _neon("M-17,-4 L-17,-22 C-17,-48 17,-48 17,-22 L17,-4", 8) + _fill(_rr(-30, -8, 60, 50, 9)) \
		+ _dark(_c(0, 10, 7)) + _dark("M-4,12 L4,12 L6,30 L-6,30 Z")


func _die(pips: Array) -> String:
	var s := _fill(_rr(-20, -20, 40, 40, 8))
	for p in pips:
		s += _dark(_c(p[0], p[1], 4))
	return s


func _card() -> String:
	return _g("rotate(-10) translate(-6,0)", _fill(_rr(-30, -44, 60, 88, 7))) + _fill(_rr(-24, -42, 60, 88, 7)) \
		+ _g("translate(6,0) scale(1.3)", _dark(SPADE)) + _lightline(_rr(-19, -37, 50, 78, 4), 1.5)


func _skull() -> String:
	return _fill(_rr(-19, 12, 38, 26, 7)) + _fill(_c(0, -10, 34)) + _dark(_c(-13, -8, 10)) + _dark(_c(13, -8, 10)) \
		+ _dark("M0,6 L-6,16 L6,16 Z") + _darkline("M-7,25 L-7,38 M0,25 L0,38 M7,25 L7,38", 2.5)


func _bone() -> String:
	return _fill(_c(-42, -5, 7) + " " + _c(-42, 5, 7) + " " + _c(42, -5, 7) + " " + _c(42, 5, 7)) + _fill(_rr(-42, -5, 84, 10, 4))


func _flame() -> String:
	return _fill(FLAME) + _light(FLAME_CORE, 0.9)


func _eight_ball() -> String:
	return _fill(_c(0, 0, 44)) + _light(_c(-4, -8, 18), 0.95) + _darkline(_c(-4, -15, 5) + " " + _c(-4, -3, 6.5), 3) \
		+ _light(_c(18, 20, 5), 0.4)


func _gem() -> String:
	return _fill("M-42,-12 L-24,-34 L24,-34 L42,-12 L0,42 Z") \
		+ _lightline("M-42,-12 L42,-12 M-24,-34 L-12,-12 L0,-34 L12,-12 L24,-34 M-12,-12 L0,42 L12,-12", 2)


func _gemmed(x: float, y: float, r: float) -> String:
	return _g("translate(%s,%s) scale(%s)" % [x, y, r / 42.0], _gem())


func _dagger() -> String:
	return _fill("M-5,-12 L0,-50 L5,-12 Z") + _fill(_rr(-16, -14, 32, 7, 3)) + _fill(_rr(-4, -7, 8, 24, 3)) \
		+ _fill(_c(0, 21, 6)) + _lightline("M0,-42 L0,-15", 1.5)


func _sword() -> String:
	return _fill("M0,-54 L6,-44 L6,16 L-6,16 L-6,-44 Z") + _lightline("M0,-46 L0,14", 1.5) \
		+ _fill(_rr(-18, 16, 36, 7, 3)) + _fill(_rr(-3.5, 23, 7, 18, 2)) + _fill(_c(0, 45, 5))


func _crown() -> String:
	var s := _fill(CROWN) + _darkline("M-38,12 L38,12", 3)
	for p in [[-42, -22], [0, -38], [42, -22]]:
		s += _light(_c(p[0], p[1], 5.5), 0.95)
	for x in [-20, 0, 20]:
		s += _light("M%d,14 L%d,19 L%d,24 L%d,19 Z" % [x, x + 5, x, x - 5], 0.9)
	return s


func _wings() -> String:
	var w := _fill(WING) + _lightline("M-14,6 C-24,-6 -34,-14 -46,-14 M-16,12 C-26,6 -36,4 -44,6", 1.5)
	return w + _g("scale(-1,1)", w)


func _bomb() -> String:
	return _neon("M14,-22 C20,-36 32,-40 38,-36", 4) + _g("translate(14,-24) rotate(40)", _fill(_rr(-8, -6, 16, 12, 3))) \
		+ _fill(_c(-4, 10, 34)) + _light(_c(-16, -2, 7), 0.5) + _fill(_starp(40, -38, 6, 12, 5, -90)) \
		+ _light(_c(40, -38, 4), 0.95)


func _molotov() -> String:
	return _g("translate(0,-34) scale(0.38)", _flame()) \
		+ _fill("M-13,46 L-13,2 C-13,-8 -6,-12 -6,-20 L-6,-28 L6,-28 L6,-20 C6,-12 13,-8 13,2 L13,46 Z") \
		+ _light(_rr(-13, 18, 26, 26, 2), 0.35) + _fill("M-7,-30 L7,-30 L4,-20 L-4,-20 Z")


func _planet() -> String:
	var ring := "rotate(-20)"
	return _g(ring, _neon("M-50,0 A50,14 0 0,1 50,0", 5)) + _fill(_c(0, 0, 27)) \
		+ _g(ring, _lightline("M-24,-6 L24,-6 M-26,6 L26,6", 2)) + _g(ring, _neon("M50,0 A50,14 0 0,1 -50,0", 5))


func _rocket() -> String:
	var fin := _fill("M-13,2 L-28,30 L-12,24 Z")
	return _g("translate(0,34) rotate(180) scale(0.32)", _flame()) + fin + _g("scale(-1,1)", fin) \
		+ _fill("M0,-50 C14,-36 16,-10 13,24 L-13,24 C-16,-10 -14,-36 0,-50 Z") + _dark(_c(0, -14, 8)) + _light(_c(-2, -16, 3), 0.8)


func _comet() -> String:
	return _neon("M6,-6 L-44,44", 10) + _neon("M18,2 L-26,48", 5) + _neon("M-2,-16 L-48,24", 5) \
		+ _fill(_c(20, -20, 17)) + _light(_c(16, -24, 6), 0.8)


func _eye() -> String:
	var s := _lightline("M-30,-30 L-36,-40 M-15,-36 L-18,-48 M0,-38 L0,-50 M15,-36 L18,-48 M30,-30 L36,-40", 3)
	return s + _fill("M-48,0 C-28,-30 28,-30 48,0 C28,30 -28,30 -48,0 Z") + _dark(_c(0, 0, 18)) + _fill(_c(0, 0, 9)) \
		+ _light(_c(-4, -4, 3.5), 0.95)


func _demon() -> String:
	var horn := _fill("M-12,6 C-36,0 -44,-26 -32,-50 C-30,-30 -20,-16 -2,-8 Z")
	return horn + _g("scale(-1,1)", horn) + _fill(_c(0, 14, 26)) \
		+ _dark("M-18,6 L-4,12 L-6,16 L-18,12 Z") + _dark("M18,6 L4,12 L6,16 L18,12 Z") + _darkline("M-10,28 L-5,24 L0,28 L5,24 L10,28", 2.5)


func _anchor() -> String:
	return _neon(_c(0, -38, 8), 5) + _neon("M0,-30 L0,40 M-20,-16 L20,-16", 7) \
		+ _neon("M-36,16 C-30,36 -12,42 0,42 C12,42 30,36 36,16", 7) + _fill("M-36,6 L-44,20 L-28,20 Z") + _fill("M36,6 L44,20 L28,20 Z")


func _hourglass() -> String:
	return _fill("M-24,-38 L24,-38 C24,-14 6,-8 6,0 C6,8 24,14 24,38 L-24,38 C-24,14 -6,8 -6,0 C-6,-8 -24,-14 -24,-38 Z") \
		+ _light("M-14,-24 L14,-24 L0,-4 Z", 0.9) + _light("M-17,34 L17,34 L0,16 Z", 0.9) \
		+ _fill(_rr(-32, -48, 64, 10, 3)) + _fill(_rr(-32, 38, 64, 10, 3))


func _key() -> String:
	return _neon(_c(-22, -22, 16), 9) + _neon("M-11,-11 L36,36 M24,24 L33,15 M32,32 L41,23", 8) + _fill(_c(-22, -22, 5))


func _gear() -> String:
	var pts := PackedStringArray()
	for i in 8:
		var a := i * 45.0
		for p in [[36.0, a - 15.0], [47.0, a - 9.0], [47.0, a + 9.0], [36.0, a + 15.0]]:
			var r := deg_to_rad(float(p[1]))
			pts.append("%.2f,%.2f" % [cos(r) * p[0], sin(r) * p[0]])
	return _fill("M" + " L".join(pts) + " Z") + _dark(_c(0, 0, 14)) + _lightline(_c(0, 0, 25), 2)


func _atom() -> String:
	var s := ""
	for a in [0, 60, 120]:
		s += _g("rotate(%d)" % a, _neon("M-48,0 A48,17 0 1,0 48,0 A48,17 0 1,0 -48,0", 4))
	return s + _fill(_c(0, 0, 9))


func _slashes() -> String:
	var s := ""
	for x in [-22, 0, 22]:
		s += _fill("M%d,-48 C%d,-16 %d,16 %d,48 C%d,16 %d,-16 %d,-48 Z" % [x - 12, x + 6, x + 6, x - 6, x + 16, x + 14, x - 12])
	return _g("skewX(-12)", s)


func _trident() -> String:
	var prong := _neon("M-24,-36 L-24,-14 C-24,-4 -10,-2 0,-2", 6) + _fill("M-24,-52 L-31,-36 L-17,-36 Z")
	return prong + _g("scale(-1,1)", prong) + _fill("M0,-54 L8,-38 L3,-38 L3,48 L-3,48 L-3,-38 L-8,-38 Z") \
		+ _fill(_rr(-9, 10, 18, 7, 3))


func _galaxy() -> String:
	var s := ""
	for arm in 2:
		var pts := PackedStringArray()
		for k in 41:
			var u := k / 40.0
			var a := u * 2.4 * PI + arm * PI
			var r := 6.0 + 40.0 * u
			pts.append("%.2f,%.2f" % [cos(a) * r, sin(a) * r * 0.8])
		s += _neon("M" + " L".join(pts), 6)
	for p in [[-36, -30], [38, 26], [30, -36], [-40, 30], [4, -44]]:
		s += _light(_starp(p[0], p[1], 4, 5, 1.5, -90), 0.95)
	return s + _fill(_c(0, 0, 9))


# ── Ranked-tier emblems (256 drawn, saved at 512) ─────────────────────────────

func _rank_svg(r: Array) -> String:
	_col = r[1]
	var s := _head(256)
	if r[5]:   # wings
		s += _mirror(_part("M54,84 L8,60 L22,112 L48,124 Z") + _part("M50,130 L4,126 L24,160 L60,170 Z"))
	var outer := "M64,30 L192,30 L214,52 L214,150 L128,232 L42,150 L42,52 Z"
	s += _glow(outer)
	s += '<path d="%s" fill="url(#metal)" stroke="#0a0a12" stroke-width="3"/>' % outer
	var inner := "M72,44 L184,44 L200,60 L200,144 L128,214 L56,144 L56,60 Z"
	s += '<path d="%s" fill="url(#face)"/>' % inner
	s += _neon(inner, 3) + _stripes(49, 80) + _stripes(207, 80)
	# Emblem on top, chevrons below it, kept centred in the shield
	var top := 0.0
	if r[4]:   # crown
		s += '<path d="M94,96 L94,62 L111,78 L128,54 L145,78 L162,62 L162,96 Z" fill="#%s" stroke="#ffffff" stroke-width="3" stroke-linejoin="miter"/>' % _col
		s += '<path d="M94,96 L162,96" stroke="#0a0a12" stroke-width="4"/>'
		top = 104.0
	elif r[3]:   # star
		s += _g("translate(128,82)", _fill(_starp(0, 0, 5, 24, 10, -90)))
		top = 110.0
	var n: int = r[2]
	var start := top + 18 if top > 0 else 118 - (n - 1) * 13.0
	for i in n:
		var y := start + i * 26
		s += _neon("M88,%f L128,%f L168,%f" % [y + 16, y - 6, y + 16], 9)
	return s + "</svg>"


# ── Pieces ────────────────────────────────────────────────────────────────────

func _head(size: int) -> String:
	var c := Color(_col)
	return ('<svg xmlns="http://www.w3.org/2000/svg" width="{s}" height="{s}" viewBox="0 0 {s} {s}"><defs>'
		+ '<linearGradient id="metal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5d6474"/>'
		+ '<stop offset="0.45" stop-color="#2c303b"/><stop offset="1" stop-color="#16181f"/></linearGradient>'
		+ '<radialGradient id="face" cx="0.5" cy="0.4" r="0.7"><stop offset="0" stop-color="#{c}" stop-opacity="0.38"/>'
		+ '<stop offset="0.6" stop-color="#15122a"/><stop offset="1" stop-color="#0b0a16"/></radialGradient>'
		+ '<linearGradient id="sym" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#{hi}"/>'
		+ '<stop offset="0.5" stop-color="#{c}"/><stop offset="1" stop-color="#{lo}"/></linearGradient>'
		+ '</defs>').format({"s": size, "c": _col, "hi": c.lightened(0.55).to_html(false), "lo": c.darkened(0.35).to_html(false)})


func _g(transform: String, inner: String) -> String:
	return '<g transform="%s">%s</g>' % [transform, inner]


## The same markup again, mirrored across the middle of the 256 canvas.
func _mirror(inner: String) -> String:
	return inner + _g("translate(256,0) scale(-1,1)", inner)


## A gunmetal piece (wing, crest, spike, rivet) with neon trim.
func _part(d: String) -> String:
	return _glow(d) + '<path d="%s" fill="url(#metal)" stroke="#%s" stroke-width="2.5" stroke-linejoin="miter"/>' % [d, _col]


## A solid centrepiece shape: halo, dark outline, colour gradient, bright edge.
func _fill(d: String) -> String:
	return ('<path d="{d}" fill="none" stroke="#{c}" stroke-opacity="0.22" stroke-width="13" stroke-linejoin="round"/>'
		+ '<path d="{d}" fill="none" stroke="#07060f" stroke-width="7" stroke-linejoin="round"/>'
		+ '<path d="{d}" fill="url(#sym)" stroke="#ffffff" stroke-opacity="0.45" stroke-width="1.5" stroke-linejoin="round"/>').format({"d": d, "c": _col})


func _light(d: String, opacity: float) -> String:
	return '<path d="%s" fill="#%s" fill-opacity="%s"/>' % [d, Color(_col).lightened(0.75).to_html(false), opacity]


func _lightline(d: String, w: float) -> String:
	return '<path d="%s" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="%s" stroke-linecap="round"/>' % [d, w]


func _dark(d: String) -> String:
	return '<path d="%s" fill="#0d0b18"/>' % d


func _darkline(d: String, w: float) -> String:
	return '<path d="%s" fill="none" stroke="#0d0b18" stroke-width="%s" stroke-linecap="round"/>' % [d, w]


## Soft neon halo: wide faint strokes under the shape.
func _glow(d: String) -> String:
	var s := ""
	for wo in [[18, 0.08], [11, 0.14], [6, 0.22]]:
		s += '<path d="%s" fill="none" stroke="#%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round"/>' % [d, _col, wo[1], wo[0]]
	return s


## A neon tube: halo, dark outline, colour, bright core.
func _neon(d: String, w: float) -> String:
	var core := Color(_col).lightened(0.65).to_html(false)
	var s := ""
	for layer in [[w + 10, _col, 0.18], [w + 4, "07060f", 0.85], [w, _col, 1.0], [w * 0.4, core, 1.0]]:
		s += '<path d="%s" fill="none" stroke="#%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"/>' % [
			d, layer[1], layer[2], layer[0]]
	return s


## Three short slanted bars, like the stripes on the card frame's edges.
func _stripes(x: float, y: float) -> String:
	var s := ""
	for dy in [-10, 0, 10]:
		s += '<path d="M%.2f,%.2f L%.2f,%.2f" stroke="#%s" stroke-width="3" stroke-linecap="square"/>' % [x - 3, y + dy + 3, x + 3, y + dy - 3, _col]
	return s


func _c(x: float, y: float, r: float) -> String:
	return "M%.2f,%.2f A%.2f,%.2f 0 1,0 %.2f,%.2f A%.2f,%.2f 0 1,0 %.2f,%.2f Z" % [x - r, y, r, r, x + r, y, r, r, x - r, y]


func _rr(x: float, y: float, w: float, h: float, r: float) -> String:
	return ("M{a},{y} L{b},{y} A{r},{r} 0 0,1 {x2},{c} L{x2},{d} A{r},{r} 0 0,1 {b},{y2} L{a},{y2} A{r},{r} 0 0,1 {x},{d} L{x},{c} A{r},{r} 0 0,1 {a},{y} Z"
		.format({"x": x, "y": y, "x2": x + w, "y2": y + h, "a": x + r, "b": x + w - r, "c": y + r, "d": y + h - r, "r": r}))


## Octagon with cut corners, centred on (cx, cy).
func _oct(cx: float, cy: float, w: float, h: float, c: float) -> String:
	var pts := [[cx - w + c, cy - h], [cx + w - c, cy - h], [cx + w, cy - h + c], [cx + w, cy + h - c],
		[cx + w - c, cy + h], [cx - w + c, cy + h], [cx - w, cy + h - c], [cx - w, cy - h + c]]
	var parts := PackedStringArray()
	for p in pts:
		parts.append("%.2f,%.2f" % p)
	return "M" + " L".join(parts) + " Z"


func _poly(cx: float, cy: float, n: int, r: float, rot: float) -> String:
	var parts := PackedStringArray()
	for i in n:
		var a := deg_to_rad(rot + i * 360.0 / n)
		parts.append("%.2f,%.2f" % [cx + cos(a) * r, cy + sin(a) * r])
	return "M" + " L".join(parts) + " Z"


func _starp(cx: float, cy: float, n: int, ro: float, ri: float, rot: float) -> String:
	var parts := PackedStringArray()
	for i in n * 2:
		var a := deg_to_rad(rot + i * 180.0 / n)
		var r := ro if i % 2 == 0 else ri
		parts.append("%.2f,%.2f" % [cx + cos(a) * r, cy + sin(a) * r])
	return "M" + " L".join(parts) + " Z"
