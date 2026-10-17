extends Screen
## Free-for-all lobby (backend/socket/ffaMatch.js): up to four players, each readies up. It starts
## as soon as four are ready, or when the timer runs out: anyone not ready drops out and CPUs take
## the empty seats (always four players). Net opens the duel when the match starts (ffa:start).

const SEAT := Vector2(330, 400)
const ACCENT := Color("ff9f43")

var _seats: Array = []          # four seat panels: {root, avatar, name, sub, badge, you}
var _clock: Label
var _ring: Control
var _ready_btn: Button
var _status: Label
var _sent := false              # ffa:queue sent on this connection
var _ready_now := false
var _secs := 0.0
var _total := 60.0
var _count := 0                 # players in the lobby (for the join sound)
var _last_tick := -1


func _ready() -> void:
	back_to = ""
	UI.background(self, "arena_lobby.png" if UI.tex("arena_lobby.png") else "duel_background.png", 0.62)   # (the crowd waiting for a fight)
	UI.title(self, "FREE-FOR-ALL", ACCENT)
	var sub := UI.label("4 players · every one for themselves · last one standing wins", 24, UI.MUTED)
	sub.size = Vector2(1920, 32)
	sub.position = Vector2(0, 96)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	for i in 4:
		_seats.append(_seat(Vector2(960 - 2 * SEAT.x - 45 + i * (SEAT.x + 30), 170)))
	# The countdown: a ring that empties, and the seconds left
	_ring = Control.new()
	_ring.position = Vector2(960, 700)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_clock = UI.label("", 52, Color.WHITE, true)
	_clock.size = Vector2(200, 64)
	_clock.position = Vector2(860, 668)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_clock)
	_status = UI.label("CONNECTING…", 24, UI.MUTED, true)
	_status.size = Vector2(1920, 34)
	_status.position = Vector2(0, 790)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	var rules := UI.label("Starts when all 4 are ready, or when the timer runs out. Anyone not ready drops out; CPUs take any empty seats.", 18, UI.MUTED)
	rules.size = Vector2(1920, 26)
	rules.position = Vector2(0, 830)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(rules)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	add_child(row)
	_ready_btn = UI.button("READY", _toggle_ready, Vector2(360, 76), UI.GREEN)
	_ready_btn.disabled = true
	row.add_child(_ready_btn)
	row.add_child(UI.button("LEAVE", _leave, Vector2(240, 76), UI.RED))
	row.reset_size()
	row.position = Vector2(960 - row.size.x / 2, 900)
	Net.connect_to_server()


## (Net goes to this screen on ffa:lobby unless it's already showing)
func on_ffa_lobby() -> void:
	pass


func _process(delta: float) -> void:
	if Net.is_open and not _sent:
		_sent = true
		Net.send("ffa:queue")
	elif not Net.is_open:
		_sent = false
	while not Net.ffa_inbox.is_empty():
		var m: Array = Net.ffa_inbox.pop_front()
		_on_message(m[0], m[1])
	if _secs > 0.0:
		_secs = maxf(0.0, _secs - delta)
		_clock.text = "%d" % ceili(_secs)
		_clock.label_settings.font_color = UI.RED if _secs <= 10.0 else Color.WHITE
		var whole := ceili(_secs)
		if whole <= 10 and whole != _last_tick:
			_last_tick = whole
			Sfx.play("click", 1.6 if whole <= 3 else 1.2, -4.0)
		_ring.queue_redraw()


func _on_message(name: String, data) -> void:
	if not data is Dictionary:
		return
	match name:
		"ffa:lobby":
			_render(data)
		"ffa:left":
			var why := str(data.get("reason", ""))
			if why != "":
				UI.dialog(self, "OUT OF THE LOBBY", why, [["BACK", func(): Game.go("fight_mode")]], UI.RED)


func _render(data: Dictionary) -> void:
	var players: Array = data.get("players", [])
	_secs = float(data.get("secs", 0))
	_total = maxf(_total, _secs)
	_ready_btn.disabled = false
	if players.size() > _count:
		Sfx.play("phase", 1.0, -4.0)   # someone joined
	_count = players.size()
	var ready := 0
	for i in 4:
		var p: Dictionary = players[i] if i < players.size() else {}
		_fill_seat(_seats[i], p)
		if p.get("ready", false):
			ready += 1
		if p.get("you", false):
			_ready_now = p.get("ready", false)
	_ready_btn.text = "✓  READY" if _ready_now else "READY"
	_status.text = "%d / 4 PLAYERS  ·  %d READY" % [players.size(), ready]
	_status.label_settings.font_color = UI.GREEN if ready == players.size() and ready > 0 else UI.MUTED


func _seat(at: Vector2) -> Dictionary:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.04, 0.1, 0.9), Color(1, 1, 1, 0.15), 2, 12))
	p.position = at
	p.size = SEAT
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	var av := UI.texture_rect(null, Vector2(180, 180), true)
	av.position = Vector2((SEAT.x - 180) / 2.0, 30)
	p.add_child(av)
	var name := UI.label("", 30, Color.WHITE, true)
	name.size = Vector2(SEAT.x, 40)
	name.position = Vector2(0, 226)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(name)
	var sub := UI.label("", 18, UI.MUTED)
	sub.size = Vector2(SEAT.x, 26)
	sub.position = Vector2(0, 268)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(sub)
	var badge := UI.label("", 28, UI.MUTED, true)
	badge.size = Vector2(SEAT.x, 40)
	badge.position = Vector2(0, 330)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(badge)
	var you := UI.label("YOU", 18, ACCENT, true)
	you.position = Vector2(14, 10)
	p.add_child(you)
	return {"root": p, "avatar": av, "name": name, "sub": sub, "badge": badge, "you": you, "filled": false}


func _fill_seat(seat: Dictionary, p: Dictionary) -> void:
	var root: Panel = seat.root
	var empty := p.is_empty()
	seat.you.visible = p.get("you", false)
	if empty:
		seat.avatar.texture = null
		seat.name.text = "OPEN SEAT"
		seat.name.label_settings.font_color = Color(1, 1, 1, 0.25)
		seat.sub.text = "a CPU takes it if nobody does"
		seat.badge.text = ""
		root.modulate = Color(1, 1, 1, 0.6)
		seat.filled = false
		return
	if not seat.filled:   # someone sat down: the seat pops in
		root.pivot_offset = SEAT / 2
		root.scale = Vector2.ONE * 0.9
		root.create_tween().tween_property(root, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	seat.filled = true
	root.modulate = Color.WHITE
	seat.avatar.texture = UI.avatar(str(p.get("avatar_url", "")) if p.get("avatar_url") else "")
	seat.name.text = str(p.get("username", "PLAYER")).to_upper().left(14)
	seat.name.label_settings.font_color = Color.WHITE
	var title = p.get("title")
	seat.sub.text = "LV %d%s" % [int(p.get("level", 1)), "  ·  %s" % str(title).to_upper() if title is String and title != "" else ""]
	var ready: bool = p.get("ready", false)
	seat.badge.text = "✓ READY" if ready else "NOT READY"
	seat.badge.label_settings.font_color = UI.GREEN if ready else UI.MUTED
	root.add_theme_stylebox_override("panel", UI._glow(UI.box(Color(0.04, 0.04, 0.1, 0.92), UI.GREEN if ready else ACCENT, 2, 12), UI.GREEN if ready else ACCENT, 0.6 if ready else 0.3))


func _draw_ring() -> void:
	var k := clampf(_secs / maxf(1.0, _total), 0.0, 1.0)
	_ring.draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 64, Color(1, 1, 1, 0.1), 10.0, true)
	if k > 0.0:
		_ring.draw_arc(Vector2.ZERO, 70.0, -PI / 2, -PI / 2 + TAU * k, 64, UI.RED if _secs <= 10.0 else ACCENT, 10.0, true)


func _toggle_ready() -> void:
	Sfx.play("click")
	Net.send("ffa:ready", {"ready": not _ready_now})


func _leave() -> void:
	Net.send("ffa:leave")
	Game.go("fight_mode")


func on_online_error(message: String) -> void:
	_status.text = "CAN'T JOIN"
	_status.label_settings.font_color = UI.RED
	UI.dialog(self, "CAN'T JOIN THE FREE-FOR-ALL", message, [["BACK", func(): Game.go("fight_mode")]], UI.RED)
