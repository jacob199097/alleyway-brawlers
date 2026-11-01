extends Screen
## THE TURF MAP (backend/economy/territory.js, GET /api/territory): the city's districts are the
## arenas. Every match is fought in one and wins influence there for your deck's clan; each week a
## district goes to the clan with the most influence in it, if that beats the local gang running it.
## When the week ends, everyone who fought for a clan in a district it took is paid Karat, and the
## district's boss (its top fighter) more: CLAIM. A district's FIGHT HERE starts a CPU match in it.

const COLS := 6
const TILE := Vector2(290, 236)
const GAP := Vector2(15, 16)
const GRID := Vector2(52, 232)
const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")

var _data := {}
var _clan := {}             # clan id -> {name, color}
var _detail: Control = null  # the open district
var _banner: Control = null  # last week's Karat, waiting
var _starting := false
var _spin: Label = null
var _arena: Control = null   # the arena roulette while the match starts


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.66)
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
	var sub := UI.label("Every match wins influence for your deck's clan in the district it's fought in  ·  week ends in %s" % _ends_in(), 21, UI.MUTED)
	sub.size = Vector2(1920, 30)
	sub.position = Vector2(0, 98)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	if _data.get("reward") is Dictionary:
		_reward_banner(_data.reward)
	var districts: Array = _data.get("districts", [])
	for i in districts.size():
		_tile(districts[i], GRID + Vector2(i % COLS, i / COLS) * (TILE + GAP))
	var free := districts.size()
	if free < COLS * 3:   # the spare slot: who holds how much this week
		_summary(GRID + Vector2(free % COLS, free / COLS) * (TILE + GAP))
	var k: Dictionary = _data.get("karat", {}) if _data.get("karat") is Dictionary else {}
	var how := UI.label("Online win +3  ·  online loss +1  ·  Ranked or Hard CPU win +2  ·  CPU win +1  ·  Turf Defense win +3.   When the week ends, the clan's fighters in each district it holds earn %d Karat, its boss %d more." % [int(k.get("district", 50)), int(k.get("boss", 50))], 17, UI.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size = Vector2(1560, 50)
	how.position = Vector2(290, 990)
	add_child(how)


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
	left.add_child(UI.label("A CPU match in this district: win it to push your clan's influence here.", 17, UI.MUTED))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(660, 0)
	row.add_child(right)
	right.add_child(UI.label(str(d.get("name", "")).to_upper(), 46, Color.WHITE, true))
	var gang: Dictionary = d.get("locals", {}) if d.get("locals") is Dictionary else {}
	right.add_child(UI.label(("HELD BY %s" % _clan_name(holder).to_upper()) if holder != "" else "RUN BY %s" % str(gang.get("name", "the locals")).to_upper(), 24, col, true))
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


func _close() -> void:
	if _detail and is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null


# ── Last week's Karat ────────────────────────────────────────────────────────

func _reward_banner(rw: Dictionary) -> void:
	var p := UI.panel(UI.GREEN, Color(0.03, 0.08, 0.05, 0.95))
	p.position = Vector2(560, 136)
	p.custom_minimum_size = Vector2(800, 76)
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
	var l := UI.label(text, 22, UI.GREEN, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	row.add_child(UI.button("CLAIM %d KARAT" % int(rw.get("karat", 0)), _claim, Vector2(260, 60), UI.GREEN))


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
	var difficulty := await _pick_difficulty()
	if difficulty == "":
		return
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
	_close()
	_spin = UI.spinner(self, Vector2(960, 1000), "STARTING MATCH…")
	_arena = ArenaRoulette.spin(self, str(d.get("id", "")), Vector2(1460, 784))
	var why := await Game.request_cpu_match(false, difficulty, false, str(d.get("id", "")))
	if why != "":
		on_online_error(why)
		return
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree() and _starting:
		on_online_error("The server didn't start the match. Try again in a moment.")


## Easy / Normal / Hard (as VS CPU); "" when cancelled.
func _pick_difficulty() -> String:
	var choice := [""]
	UI.dialog(self, "CHOOSE DIFFICULTY",
		"Easy and Normal wins are worth +1 influence here, Hard wins +2.\nRewards scale with difficulty, as in VS CPU.",
		[["EASY", func(): choice[0] = "easy", UI.GREEN], ["NORMAL", func(): choice[0] = "normal", UI.BLUE],
		["HARD", func(): choice[0] = "hard", UI.RED], ["CANCEL", func(): choice[0] = "cancel"]], Color("b388ff"))
	while choice[0] == "":
		await get_tree().process_frame
	return "" if choice[0] == "cancel" else choice[0]


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
