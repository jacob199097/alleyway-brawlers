extends Screen
## Social club: friends, requests, add a friend, and chat history.
## Challenges and live chat go over the realtime connection (Net).

var _list: VBoxContainer
var _search: LineEdit
var _chat: Control


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.62)
	Game.play_menu_music()
	UI.title(self, "SOCIAL CLUB")
	UI.back_button(self, func(): Game.go("main_menu"))
	if not needs_server("Social"):
		return
	var add := HBoxContainer.new()
	add.position = Vector2(560, 120)
	add.add_theme_constant_override("separation", 12)
	add_child(add)
	_search = LineEdit.new()
	_search.placeholder_text = "Username to add…"
	_search.custom_minimum_size = Vector2(560, 56)
	_search.text_submitted.connect(func(_t): _add_friend())
	add.add_child(_search)
	add.add_child(UI.button("+ ADD FRIEND", _add_friend, Vector2(230, 56), UI.GREEN))
	var p := UI.panel(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0.5))
	p.position = Vector2(260, 200)
	p.size = Vector2(1400, 760)
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_load()


func _load() -> void:
	for c in _list.get_children():
		c.queue_free()
	var r := await Api.request("GET", "/api/social/friends")
	if not r.ok:
		_list.add_child(UI.label(r.error, 24, UI.RED))
		return
	if r.data.is_empty():
		_list.add_child(UI.label("No friends yet. Add some!", 26, UI.MUTED, true))
		return
	_list.add_child(UI.label("FRIENDS", 20, UI.MUTED, true))
	for f in r.data:
		_list.add_child(_row(f))


func _row(f: Dictionary) -> Control:
	var pending: bool = f.get("status") == "pending"
	var p := UI.panel(UI.GOLD if pending else Color("333355"), Color("1a1a2e"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var dot := ColorRect.new()
	dot.color = UI.GREEN if f.get("is_online", false) else Color("555555")
	dot.custom_minimum_size = Vector2(16, 16)
	var dot_box := CenterContainer.new()
	dot_box.add_child(dot)
	row.add_child(dot_box)
	var av_key := str(f.get("friend_avatar", "profile_001"))
	row.add_child(UI.texture_rect(UI.tex("%s.png" % av_key) if UI.tex("%s.png" % av_key) else UI.tex("profile_001.png"), Vector2(64, 64), true))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UI.label(str(f.get("friend_username", "?")), 28, Color.WHITE, true))
	info.add_child(UI.label("(Pending)" if pending else "Lv.%d  ·  %s" % [int(f.get("level", 1)), "Online" if f.get("is_online", false) else "Offline"],
		18, UI.GOLD if pending else UI.MUTED))
	if pending:
		row.add_child(UI.button("✓ ACCEPT", func():
			var r := await Api.request("PATCH", "/api/social/friends/%s/accept" % f.friendship_id)
			if r.ok:
				_load()
			else:
				UI.toast(self, r.error, UI.RED), Vector2(200, 56), UI.GREEN))
	else:
		var online: bool = f.get("is_online", false)
		var vs := UI.button("⚔ CHALLENGE", func():
			if Net.send("mp:challenge", {"targetPlayerId": f.friend_id}):
				UI.toast(self, "Challenge sent to %s — waiting for them to accept." % f.friend_username, UI.GOLD)
			else:
				UI.toast(self, "Not connected to the server.", UI.RED), Vector2(220, 56), UI.RED)
		vs.disabled = not online
		vs.tooltip_text = "" if online else "%s is offline" % f.friend_username
		row.add_child(vs)
		row.add_child(UI.button("💬 CHAT", _open_chat.bind(f), Vector2(180, 56)))
	return p


func _add_friend() -> void:
	var name := _search.text.strip_edges()
	if name == "":
		return
	var r := await Api.request("POST", "/api/social/friends/request", {"targetUsername": name})
	UI.toast(self, "Friend request sent!" if r.ok else r.error, UI.GREEN if r.ok else UI.RED)
	if r.ok:
		_search.text = ""
		_load()


func _open_chat(f: Dictionary) -> void:
	if _chat:
		_chat.queue_free()
	_chat = UI.panel(UI.BLUE, Color(0.04, 0.04, 0.12, 0.98))
	_chat.position = Vector2(360, 160)
	_chat.custom_minimum_size = Vector2(1200, 800)
	add_child(_chat)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_chat.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var h := UI.label("CHAT — %s" % str(f.friend_username).to_upper(), 34, UI.BLUE, true)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	head.add_child(UI.button("✕", func():
		_chat.queue_free()
		_chat = null, Vector2(64, 56)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1160, 580)
	col.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 8)
	scroll.add_child(lines)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 12)
	col.add_child(input_row)
	var edit := LineEdit.new()
	edit.placeholder_text = "Message…"
	edit.max_length = 500
	edit.custom_minimum_size = Vector2(1000, 56)
	input_row.add_child(edit)
	var add_line := func(body: String, mine: bool):
		var l := UI.label(body, 22, UI.BLUE if mine else Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(1120, 0)
		lines.add_child(l)
		await get_tree().process_frame
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	var send_msg := func():
		var body := edit.text.strip_edges()
		if body == "":
			return
		if not Net.send("chat:message", {"toPlayerId": f.friend_id, "body": body}):
			UI.toast(self, "Not connected to the server.", UI.RED)
			return
		edit.text = ""
		add_line.call(body, true)
	edit.text_submitted.connect(func(_t): send_msg.call())
	input_row.add_child(UI.button("SEND", send_msg, Vector2(140, 56)))
	# Live messages from this friend while the chat is open
	var listener := func(name: String, data):
		if name == "chat:message" and data is Dictionary and data.get("fromPlayerId") == f.friend_id:
			add_line.call(str(data.get("body", "")), false)
	Net.event.connect(listener)
	_chat.tree_exiting.connect(func(): Net.event.disconnect(listener))
	edit.grab_focus()
	var r := await Api.request("GET", "/api/social/messages/%s" % f.friend_id)
	if not r.ok:
		lines.add_child(UI.label(r.error, 22, UI.RED))
		return
	if r.data.is_empty():
		lines.add_child(UI.label("No messages yet.", 22, UI.MUTED))
	for m in r.data:
		add_line.call(str(m.get("body", "")), m.get("sender_id") != f.friend_id)
