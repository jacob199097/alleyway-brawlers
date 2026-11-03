extends Screen
## Social club: friends, requests, add a friend; CHAT opens the friends chat (Net.chat).
## Challenges and live chat go over the realtime connection (Net).

var _list: VBoxContainer
var _search: LineEdit


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.jpg", 0.62)
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
	var p := UI.glass(UI.panel(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0.5)))
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
	# Requests waiting on you first, then whoever's online (in a match last), then the rest by name
	var rank := func(x) -> int:
		if x.get("status") == "pending" and x.get("incoming", true):
			return 0
		if x.get("is_online", false):
			return 2 if x.get("in_match", false) else 1
		return 3
	var rows: Array = r.data.duplicate()
	rows.sort_custom(func(a, b): return rank.call(a) < rank.call(b) if rank.call(a) != rank.call(b) else str(a.get("username", "")).to_lower() < str(b.get("username", "")).to_lower())
	for f in rows:
		_list.add_child(_row(f))
	UI.stagger(_list.get_children())


func _row(f: Dictionary) -> Control:
	var pending: bool = f.get("status") == "pending"
	var incoming: bool = pending and f.get("incoming", true)
	var in_match: bool = f.get("in_match", false)
	var p := UI.panel(UI.GOLD if pending else Color("333355"), Color(0.1, 0.1, 0.18, 0.62))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var dot := ColorRect.new()
	dot.color = UI.GOLD if in_match else UI.GREEN if f.get("is_online", false) else Color("555555")
	dot.custom_minimum_size = Vector2(16, 16)
	var dot_box := CenterContainer.new()
	dot_box.add_child(dot)
	row.add_child(dot_box)
	row.add_child(UI.texture_rect(UI.avatar(f.get("friend_avatar")), Vector2(64, 64), true))
	if not pending:
		row.add_child(UI.texture_rect(UI.level_icon(int(f.get("level", 1))), Vector2(56, 56)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UI.label(str(f.get("friend_username", "?")), 28, Color.WHITE, true))
	var status := "In a match" if in_match else "Online" if f.get("is_online", false) else "Offline"
	info.add_child(UI.label(("Wants to be your friend" if incoming else "Request sent") if pending else "Lv.%d  ·  %s" % [int(f.get("level", 1)), status],
		18, UI.GOLD if pending or in_match else UI.MUTED))
	if incoming:
		row.add_child(UI.button("✓ ACCEPT", func():
			var r := await Api.request("PATCH", "/api/social/friends/%s/accept" % f.friendship_id)
			if r.ok:
				_load()
			else:
				UI.toast(self, r.error, UI.RED), Vector2(200, 56), UI.GREEN))
		row.add_child(UI.button("✕ DECLINE", _remove.bind(f), Vector2(200, 56), UI.RED))
	elif pending:
		row.add_child(UI.button("CANCEL", _remove.bind(f), Vector2(200, 56)))
	else:
		var online: bool = f.get("is_online", false)
		var vs := UI.button("⚔ CHALLENGE", func():
			if Net.send("mp:challenge", {"targetPlayerId": f.friend_id}):
				UI.toast(self, "Challenge sent to %s — waiting for them to accept." % f.friend_username, UI.GOLD)
			else:
				UI.toast(self, "Not connected to the server.", UI.RED), Vector2(220, 56), UI.RED)
		if in_match:
			var watch := UI.button("👁 WATCH", func():
				if not Net.send("mp:spectate", {"targetPlayerId": f.friend_id}):
					UI.toast(self, "Not connected to the server.", UI.RED), Vector2(180, 56), UI.GOLD)
			watch.tooltip_text = "Watch %s's match live" % f.friend_username
			row.add_child(watch)
		vs.disabled = not online or in_match
		vs.tooltip_text = "%s is offline" % f.friend_username if not online else "%s is in a match" % f.friend_username if in_match else ""
		row.add_child(vs)
		row.add_child(UI.button("👤 PROFILE", func():
			Game.view_player_id = str(f.friend_id)
			Game.go("profile"), Vector2(180, 56), UI.BLUE))
		row.add_child(UI.button("💬 CHAT", _open_chat.bind(f), Vector2(180, 56)))
		var rm := UI.button("✕", func():
			UI.dialog(self, "REMOVE FRIEND?", "Remove %s from your friends?" % f.friend_username,
				[["REMOVE", _remove.bind(f), UI.RED], ["CANCEL", func(): pass]]), Vector2(64, 56), UI.RED)
		rm.tooltip_text = "Remove friend"
		row.add_child(rm)
	return p


## Decline or cancel a request, or remove a friend.
func _remove(f: Dictionary) -> void:
	var r := await Api.request("DELETE", "/api/social/friends/%s" % f.friendship_id)
	if r.ok:
		_load()
	else:
		UI.toast(self, r.error, UI.RED)


func _add_friend() -> void:
	var name := _search.text.strip_edges()
	if name == "":
		return
	var r := await Api.request("POST", "/api/social/friends/request", {"targetUsername": name})
	UI.toast(self, "Friend request sent!" if r.ok else r.error, UI.GREEN if r.ok else UI.RED)
	if r.ok:
		_search.text = ""
		_load()


## The friends chat panel (Net.chat, scripts/ui/chat_dock.gd: the same one as on every screen).
func _open_chat(f: Dictionary) -> void:
	Net.chat.open_with(str(f.friend_id), str(f.friend_username), f.get("friend_avatar"))