extends Screen
## Mailbox: message list on the left, the open message on the right.

var _messages: Array = []
var _list: VBoxContainer
var _body: VBoxContainer
var _open_id = null


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.72)
	Game.play_menu_music()
	UI.title(self, "MAILBOX")
	UI.back_button(self, func(): Game.go("main_menu"))
	if not needs_server("The mailbox"):
		return
	var lp := UI.panel(Color(UI.BLUE, 0.6), Color(0.06, 0.06, 0.18, 0.95))
	lp.position = Vector2(40, 130)
	lp.size = Vector2(700, 820)
	add_child(lp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var bp := UI.panel(Color(UI.BLUE, 0.6), Color(0.06, 0.06, 0.18, 0.95))
	bp.position = Vector2(760, 130)
	bp.size = Vector2(1120, 820)
	add_child(bp)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	bp.add_child(_body)
	var read_all := UI.button("MARK ALL READ", func():
		await Api.request("POST", "/api/mail/read-all")
		_load(), Vector2(260, 56))
	read_all.position = Vector2(1620, 996)
	add_child(read_all)
	_load()


func _load() -> void:
	var r := await Api.request("GET", "/api/mail")
	if not r.ok:
		_empty(r.error)
		return
	_messages = r.data.get("messages", [])
	_render_list()
	if _messages.is_empty():
		_empty("Inbox empty.")
	else:
		_open(_messages[0])


func _render_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	if _messages.is_empty():
		_list.add_child(UI.label("No messages.", 22, UI.MUTED))
		return
	for m in _messages:
		var unread: bool = m.get("read_at") == null
		var b := Button.new()
		b.custom_minimum_size = Vector2(660, 92)
		var selected: bool = m.id == _open_id
		b.add_theme_stylebox_override("normal", UI.box(Color("1d2742") if unread else Color("14141e"),
			UI.GOLD if selected else UI.BLUE if unread else Color("334466"), 2, 8))
		var sender := UI.label(str(m.get("sender", "System")), 18, Color("aaccff"), true)
		sender.position = Vector2(30, 10)
		b.add_child(sender)
		var subject := UI.label(str(m.get("subject", "(no subject)")), 24, Color.WHITE if unread else Color(0.8, 0.8, 0.85), true)
		subject.position = Vector2(30, 42)
		subject.size = Vector2(600, 34)
		subject.clip_text = true
		b.add_child(subject)
		var date := UI.label(_date(str(m.get("created_at", "")), false), 16, UI.MUTED)
		date.position = Vector2(520, 12)
		b.add_child(date)
		if unread:
			var dot := ColorRect.new()
			dot.color = UI.BLUE
			dot.size = Vector2(10, 10)
			dot.position = Vector2(12, 42)
			b.add_child(dot)
		b.pressed.connect(func():
			Sfx.play("click")
			_open(m))
		_list.add_child(b)


func _open(m: Dictionary) -> void:
	_open_id = m.id
	if m.get("read_at") == null:
		m.read_at = Time.get_datetime_string_from_system(true)
		Api.request("POST", "/api/mail/%s/read" % m.id)
	_render_list()
	for c in _body.get_children():
		c.queue_free()
	var s := UI.label(str(m.get("subject", "(no subject)")), 36, UI.GOLD, true)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD
	s.custom_minimum_size = Vector2(1060, 0)
	_body.add_child(s)
	_body.add_child(UI.label("From %s  ·  %s" % [m.get("sender", "System"), _date(str(m.get("created_at", "")), true)], 18, UI.MUTED))
	_body.add_child(HSeparator.new())
	var text := RichTextLabel.new()
	text.text = str(m.get("body", ""))
	text.custom_minimum_size = Vector2(1060, 560)
	text.add_theme_font_size_override("normal_font_size", 22)
	_body.add_child(text)
	_body.add_child(UI.button("DELETE", _delete.bind(m), Vector2(200, 52), UI.RED))


func _delete(m: Dictionary) -> void:
	var r := await Api.request("DELETE", "/api/mail/%s" % m.id)
	if not r.ok:
		UI.toast(self, r.error, UI.RED)
		return
	_messages = _messages.filter(func(x): return x.id != m.id)
	_render_list()
	if _messages.is_empty():
		_empty("Inbox empty.")
	else:
		_open(_messages[0])


func _empty(text: String) -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(UI.label(text, 26, UI.MUTED))


## ISO timestamp → "HH:MM" today / "YYYY-MM-DD", or the full local date and time.
static func _date(iso: String, full: bool) -> String:
	if iso.length() < 16:
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso.left(19))
	var local := Time.get_datetime_dict_from_unix_time(int(unix) + Time.get_time_zone_from_system().bias * 60)
	var stamp := "%04d-%02d-%02d" % [local.year, local.month, local.day]
	var clock := "%02d:%02d" % [local.hour, local.minute]
	if full:
		return "%s %s" % [stamp, clock]
	var now := Time.get_datetime_dict_from_system()
	return clock if now.year == local.year and now.month == local.month and now.day == local.day else stamp
