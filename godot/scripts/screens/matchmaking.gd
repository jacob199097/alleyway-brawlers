extends Screen
## Online queue: waits for another player, then the match starts (Net handles mp:start).

var _status: Label
var _clock: Label
var _waited := 0.0
var _queued := false
var _sent := false       # mp:queue sent on the current connection
var _cpu: Button
var _scan: TextureRect      # the opponent's frame: faces flicker through it while searching
var _scan_faces: Array = []
var _scan_at := 0.0
var _vs: Label


func _ready() -> void:
	back_to = ""
	UI.background(self, "arena_lobby.png" if UI.tex("arena_lobby.png") else "duel_background.png", 0.62)   # (the crowd waiting for a fight)
	Game.sound.ambience("crowd")
	UI.title(self, "CASUAL BRAWL")
	_face_off()
	var p := UI.glass(UI.panel(UI.BLUE, Color(0.04, 0.04, 0.12, 0.94)), Color(0.02, 0.03, 0.1, 0.62))
	p.position = Vector2(560, 640)
	p.custom_minimum_size = Vector2(800, 380)
	add_child(p)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	p.add_child(col)
	_status = UI.label("CONNECTING…", 44, UI.BLUE, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	_clock = UI.label("", 30, UI.MUTED, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_clock)
	var hint := UI.label("You'll play another player with your active deck.\nCasual matches don't change your Rank Points.", 22, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	row.add_child(UI.button("CANCEL", _cancel, Vector2(260, 64), UI.RED))
	_cpu = UI.button("PLAY THE CPU INSTEAD", _play_cpu, Vector2(360, 64), Color("b388ff"))
	_cpu.visible = false
	row.add_child(_cpu)
	Net.event.connect(_on_event)
	Net.connect_to_server()


func _exit_tree() -> void:
	if Net.event.is_connected(_on_event):
		Net.event.disconnect(_on_event)


func _process(delta: float) -> void:
	# Join as soon as the connection is up (and again after a reconnect)
	if Net.is_open and not _sent:
		_join()
	elif not Net.is_open:
		_sent = false
		_queued = false
	if not _queued:
		_waited += delta
		if _waited > 8.0 and not Net.is_open:
			_status.text = "CAN'T REACH THE SERVER"
			_status.label_settings.font_color = UI.RED
		return
	_waited += delta
	_clock.text = "%d:%02d" % [int(_waited) / 60, int(_waited) % 60]
	var t := Time.get_ticks_msec() / 400 % 4
	_status.text = "SEARCHING" + ".".repeat(t)
	_cpu.visible = _waited > 20.0
	# The opponent's frame flickers through faces, faster than you can read them
	_scan_at += delta
	if _scan and not _scan_faces.is_empty() and _scan_at > 0.09:
		_scan_at = 0.0
		_scan.texture = _scan_faces[randi() % _scan_faces.size()]
		_scan.modulate = Color(0.55, 0.75, 1.0, randf_range(0.45, 0.8))


## You and an unknown rival in frames either side of a pulsing VS.
func _face_off() -> void:
	var you := _frame(UI.avatar(Game.player.get("avatar_url")), str(Game.player.get("username", "YOU")).to_upper(), UI.BLUE)
	you.position = Vector2(380, 140)
	add_child(you)
	var rival := _frame(null, "???", UI.RED)
	rival.position = Vector2(1220, 140)
	add_child(rival)
	_scan = rival.get_meta("art")
	for id in CardDB.all():   # (the faces it flickers through: every character's art)
		var c: Dictionary = CardDB.get_card(id)
		if c.get("cardType") in ["gang_member", "leader"] and not c.get("token", false) and _scan_faces.size() < 40:
			var t := UI.card_crop(id)
			if t:
				_scan_faces.append(t)
	_vs = UI.label("VS", 120, UI.GOLD, true)
	_vs.size = Vector2(300, 160)
	_vs.position = Vector2(960 - 150, 240)
	_vs.pivot_offset = _vs.size / 2
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.label_settings.outline_color = Color(UI.RED, 0.8)
	_vs.label_settings.outline_size = 16
	add_child(_vs)
	var pulse := _vs.create_tween().set_loops()
	pulse.tween_property(_vs, "scale", Vector2.ONE * 1.1, 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_vs, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	# Both slide in from their sides
	for pair in [[you, -400.0], [rival, 400.0]]:
		var n: Control = pair[0]
		var to := n.position
		n.position.x += pair[1]
		n.modulate.a = 0.0
		var t := n.create_tween().set_parallel()
		t.tween_property(n, "position", to, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(n, "modulate:a", 1.0, 0.3)


## A fighter's frame: a picture edged in their side's colour, their name under it.
func _frame(picture: Texture2D, name: String, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var frame := PanelContainer.new()
	var fb := UI.box(Color(0, 0, 0, 0.6), col, 4, 14)
	for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		fb.set(m, 6)
	frame.add_theme_stylebox_override("panel", UI._glow(fb, col, 1.0))
	var art := UI.texture_rect(picture, Vector2(300, 300), true)
	frame.add_child(art)
	box.add_child(frame)
	box.set_meta("art", art)
	var l := UI.label(name, 34, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _join() -> void:
	_sent = true
	Net.send("mp:queue")


func _on_event(name: String, _data) -> void:
	if name == "mp:queued":
		_queued = true
		_waited = 0.0
		Sfx.play("phase")


func on_online_error(message: String) -> void:
	_queued = false
	_status.text = "CAN'T JOIN"
	_status.label_settings.font_color = UI.RED
	UI.dialog(self, "CAN'T JOIN THE QUEUE", message, [["BACK", func(): Game.go("fight_mode")]], UI.RED)


func _cancel() -> void:
	Net.send("mp:cancel")
	Game.go("fight_mode")


func _play_cpu() -> void:
	Net.send("mp:cancel")
	_queued = false
	_cpu.visible = false
	_status.text = "STARTING A CPU MATCH…"
	var why := await Game.request_cpu_match(false)
	if why != "":
		on_online_error(why)
