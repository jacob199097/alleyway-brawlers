extends Screen
## Online queue: waits for another player, then the match starts (Net handles mp:start).

var _status: Label
var _clock: Label
var _waited := 0.0
var _queued := false
var _sent := false       # mp:queue sent on the current connection
var _cpu: Button


func _ready() -> void:
	back_to = ""
	UI.background(self, "duel_background.png", 0.62)
	UI.title(self, "CASUAL BRAWL")
	var p := UI.panel(UI.BLUE, Color(0.04, 0.04, 0.12, 0.94))
	p.position = Vector2(560, 300)
	p.custom_minimum_size = Vector2(800, 420)
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
	var deck := await Game.load_duel_deck()
	if deck.has("error"):
		UI.dialog(self, "CAN'T START DUEL", deck.error, [["CLOSE", func(): pass]], UI.RED)
		return
	deck.mode = "cpu"
	Game.duel_setup = deck
	Game.go("rps")
