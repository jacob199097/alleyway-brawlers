extends CanvasLayer
## Friends chat anywhere in the game, in the menus and in a match: a CHAT tab tucked into the bottom-right
## corner (only its edge and unread count show until the mouse comes near) opens
## a panel with your friends (unread and online first) and a conversation with one of them. A message
## that comes in while it isn't open pops up at the bottom right (Net.corner_toast: click to reply) and
## counts on the tab; ones sent while you were away (GET /api/social/unread) are counted when you
## connect, with one pop-up saying so. Made by Net (scripts/net.gd) as Net.chat; no class_name
## (patches can't add one). The server: chat:message / chat:read in backend/server.js.

const W := 460.0
const H := 600.0
const TAB := Vector2(118, 48)
const TAB_Y := 1080.0 - 48.0 - 22.0   # (the bottom-right corner)
const PEEK := 14.0       # how much of the tab shows while it's tucked away
const NEAR := Vector2(190, 150)   # the mouse this close to the corner brings it out
const HIDDEN_ON := ["boot", "login", "clan_select"]   # (not signed in yet)
const ME := Color(0.16, 0.34, 0.66)
const THEM := Color(0.17, 0.17, 0.26)

var unread := {}             # friend id -> {count, name, avatar}
var _root: Control
var _tab: Button
var _badge: PanelContainer
var _badge_text: Label
var _panel: PanelContainer
var _title: Label
var _back: Button
var _body: VBoxContainer     # the friends list, or a conversation
var _with := {}              # the conversation open: {id, name, avatar}; {} = the list
var _lines: VBoxContainer
var _scroll: ScrollContainer
var _edit: LineEdit
var _open := false
var _told_missed := false
var _load_id := 0            # (a newer load replaces an older one still waiting)
var _tab_x := -1.0           # where the tab is heading (tucked away or out)


## The chat's font: a clean semi-bold sans-serif (the headline font is for headlines).
static func font() -> Font:
	return UI.font_of("strong")


func _ready() -> void:
	layer = 85   # (over every screen and the duel; under Net's banners and pop-ups)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.size = Vector2(1920, 1080)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_tab()
	_build_panel()
	Net.event.connect(_on_event)
	Net.opened.connect(_on_opened)


func _process(_delta: float) -> void:
	# The tab hides in the corner and slides out when the mouse comes near it (or the chat is open)
	var m := _root.get_local_mouse_position()
	var near := _open or (m.x > _edge() - NEAR.x and m.y > 1080.0 - NEAR.y)
	var want := _edge() - TAB.x if near else _edge() - PEEK
	if want != _tab_x:
		_tab_x = want
		_tab.create_tween().tween_property(_tab, "position:x", want, 0.16 if near else 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var scene := get_tree().current_scene
	var shown := Api.token != "" and scene != null and not HIDDEN_ON.any(func(s): return scene.scene_file_path == Game.SCREENS[s])
	if _root.visible != shown:
		_root.visible = shown
		if not shown and _open:
			close()


func _input(e: InputEvent) -> void:
	if _open and _root.visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# ── The tab and the panel ────────────────────────────────────────────────────

## The right edge of the screen: the frame's, or further out on a wide phone (scripts/widescreen.gd).
func _edge() -> float:
	return 1920.0 + Game.wide.margin.x


func _build_tab() -> void:
	_tab = Button.new()
	_tab.text = "CHAT"
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.size = TAB
	_tab.position = Vector2(_edge() - PEEK, TAB_Y)
	_tab.add_theme_font_override("font", font())
	_tab.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed"]:
		var sb := UI.box(Color(0.06, 0.07, 0.16, 0.94) if state == "normal" else Color(0.1, 0.13, 0.28, 0.97), UI.BLUE, 2, 12)
		sb.content_margin_right = 14
		_tab.add_theme_stylebox_override(state, sb)
	_tab.tooltip_text = "Chat with your friends"
	_tab.pressed.connect(func():
		Sfx.play("click")
		if _open:
			close()
		else:
			open_list())
	_root.add_child(_tab)
	_badge = PanelContainer.new()
	var sb := UI.box(UI.RED, Color.WHITE, 2, 13)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	_badge.add_theme_stylebox_override("panel", sb)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_text = Label.new()
	_badge_text.add_theme_font_override("font", font())
	_badge_text.add_theme_font_size_override("font_size", 16)
	_badge.add_child(_badge_text)
	_badge.position = Vector2(-12, -12)
	_badge.visible = false
	_tab.add_child(_badge)


func _build_panel() -> void:
	_panel = UI.panel(UI.BLUE, Color(0.04, 0.04, 0.12, 0.97))
	_panel.custom_minimum_size = Vector2(W, H)
	_panel.size = Vector2(W, H)
	_panel.position = Vector2(_edge() + 20, TAB_Y - H - 14)
	_panel.visible = false
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_back = _small_button("◀", func(): open_list())
	head.add_child(_back)
	_title = UI.label("FRIENDS", 26, UI.BLUE, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	head.add_child(_small_button("✕", func(): close()))
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	col.add_child(_body)


func _small_button(text: String, fn: Callable) -> Button:
	var b := UI.button(text, func():
		Sfx.play("click")
		fn.call(), Vector2(46, 42), UI.BLUE)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _show_panel() -> void:
	if _open and _panel.visible:
		return
	_open = true
	Net.clear_corner_toasts()   # (they'd sit over the chat's typing box)
	_panel.visible = true
	_panel.modulate.a = 0.0
	var t := _panel.create_tween().set_parallel()
	t.tween_property(_panel, "position:x", _edge() - W - 16, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "modulate:a", 1.0, 0.18)


func close() -> void:
	if not _open:
		return
	_open = false
	_with = {}
	if _edit and is_instance_valid(_edit):
		_edit.release_focus()
	var t := _panel.create_tween().set_parallel()
	t.tween_property(_panel, "position:x", _edge() + 20, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_panel, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(func():
		if not _open:
			_panel.visible = false)


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_lines = null
	_scroll = null
	_edit = null


# ── The friends list ─────────────────────────────────────────────────────────

func open_list() -> void:
	_show_panel()
	_with = {}
	_back.visible = false
	_title.text = "FRIENDS"
	_clear()
	var wait := _note("Loading…")
	_load_id += 1
	var mine := _load_id
	var r := await Api.request("GET", "/api/social/friends")
	if mine != _load_id or not _with.is_empty():
		return
	wait.queue_free()
	if not r.ok or not r.data is Array:
		_note(r.error if not r.ok else "Couldn't load your friends.", UI.RED)
		return
	var friends: Array = r.data.filter(func(f): return f is Dictionary and str(f.get("status", "")) == "accepted")
	if friends.is_empty():
		_note("No friends yet. Add some from the Social screen.")
		return
	# Unread first, then who's online, then by name
	friends.sort_custom(func(a, b):
		var ua := int(unread.get(str(a.friend_id), {}).get("count", 0))
		var ub := int(unread.get(str(b.friend_id), {}).get("count", 0))
		if (ua > 0) != (ub > 0):
			return ua > 0
		if bool(a.get("is_online")) != bool(b.get("is_online")):
			return bool(a.get("is_online"))
		return str(a.friend_username).to_lower() < str(b.friend_username).to_lower())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for f in friends:
		list.add_child(_friend_row(f))


func _friend_row(f: Dictionary) -> Control:
	var id := str(f.friend_id)
	var row := PanelContainer.new()
	var normal := UI.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 1, 10)
	var hover := UI.box(Color(0.3, 0.5, 1.0, 0.16), UI.BLUE, 1, 10)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", normal))
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			open_with(id, str(f.friend_username), f.get("friend_avatar")))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var pic := UI.texture_rect(UI.avatar(f.get("friend_avatar")), Vector2(48, 48), true)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	col.add_child(_text(str(f.friend_username), 20, Color.WHITE))
	var online := bool(f.get("is_online"))
	var status := "● In a match" if f.get("in_match", false) else "● Online" if online else "Offline"
	col.add_child(_text(status, 15, UI.GOLD if f.get("in_match", false) else UI.GREEN if online else UI.MUTED))
	var n := int(unread.get(id, {}).get("count", 0))
	if n > 0:
		var b := PanelContainer.new()
		var sb := UI.box(UI.RED, UI.RED, 0, 12)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		b.add_theme_stylebox_override("panel", sb)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(_text(str(mini(n, 99)), 16, Color.WHITE))
		h.add_child(b)
	return row


# ── A conversation ───────────────────────────────────────────────────────────

## Open the chat with a friend (the tab, a message pop-up, the Social screen's CHAT button).
func open_with(id: String, name: String, avatar = null) -> void:
	_show_panel()
	_with = {"id": id, "name": name, "avatar": avatar}
	_back.visible = true
	_title.text = name.to_upper()
	_clear()
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 6)
	_scroll.add_child(_lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Message %s…" % name
	_edit.max_length = 500
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 48)
	_edit.add_theme_font_override("font", font())
	_edit.add_theme_font_size_override("font_size", 19)
	row.add_child(_edit)
	var send := UI.button("SEND", _send, Vector2(96, 48), UI.BLUE)
	send.focus_mode = Control.FOCUS_NONE
	row.add_child(send)
	_edit.text_submitted.connect(func(_t): _send())
	_edit.grab_focus.call_deferred()
	unread.erase(id)
	_update_badge()
	_load_id += 1
	var mine := _load_id
	var r := await Api.request("GET", "/api/social/messages/%s" % id)   # (marks theirs read)
	if mine != _load_id or str(_with.get("id", "")) != id or _lines == null:
		return
	if not r.ok or not r.data is Array:
		_line("Couldn't load your messages.", false, UI.RED)
		return
	if r.data.is_empty():
		_line("No messages yet. Say hi!", false, UI.MUTED)
	for m in r.data:
		if m is Dictionary:
			_line(str(m.get("body", "")), str(m.get("sender_id", "")) != id)


func _send() -> void:
	if _edit == null or _with.is_empty():
		return
	var body := _edit.text.strip_edges()
	if body == "":
		return
	if not Net.send("chat:message", {"toPlayerId": str(_with.id), "body": body}):
		_line("Not connected to the server.", false, UI.RED)
		return
	_edit.text = ""
	_line(body, true)
	Sfx.play("click", 1.3, -6.0)


## A message bubble: yours on the right in blue, theirs on the left (note_color: a grey or red note).
func _line(body: String, mine: bool, note_color := Color(0, 0, 0, 0)) -> void:
	if _lines == null:
		return
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	_lines.add_child(holder)
	if note_color.a > 0.0:
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		holder.add_child(_text(body, 16, note_color))
	else:
		var bubble := PanelContainer.new()
		var sb := UI.box(ME if mine else THEM, ME.lightened(0.2) if mine else Color(1, 1, 1, 0.12), 1, 14)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 9
		bubble.add_theme_stylebox_override("panel", sb)
		var l := _text(body, 18, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var w := font().get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		l.custom_minimum_size = Vector2(minf(w + 2.0, 300.0), 0)
		bubble.add_child(l)
		holder.add_child(bubble)
		bubble.modulate.a = 0.0
		bubble.create_tween().tween_property(bubble, "modulate:a", 1.0, 0.15)
	await get_tree().process_frame
	if _scroll and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _text(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _note(t: String, color := UI.MUTED) -> Label:
	var l := _text(t, 18, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(W - 60, 0)
	_body.add_child(l)
	return l


# ── Messages coming in ───────────────────────────────────────────────────────

func _on_event(name: String, data) -> void:
	if not data is Dictionary:
		return
	match name:
		"chat:message":
			var id := str(data.get("fromPlayerId", ""))
			var who := str(data.get("fromUsername", "A friend"))
			if _open and str(_with.get("id", "")) == id:   # (reading their chat: it shows there, and is read)
				_line(str(data.get("body", "")), false)
				Net.send("chat:read", {"friendId": id})
				return
			var u: Dictionary = unread.get(id, {"count": 0, "name": who, "avatar": data.get("fromAvatar")})
			u.count = int(u.count) + 1
			unread[id] = u
			_update_badge()
			_message_toast(id, who, data.get("fromAvatar"), str(data.get("body", "")))
			if _open and _with.is_empty():
				open_list()
		"friend:online":
			if _open and _with.is_empty():
				open_list()


## A pop-up for a message that came in: who, what they said; click it to reply.
func _message_toast(id: String, who: String, avatar, body: String, heading := "") -> void:
	var p := UI.panel(UI.BLUE, Color(0.04, 0.05, 0.12, 0.97))
	p.custom_minimum_size = Vector2(420, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var pic := UI.texture_rect(UI.avatar(avatar), Vector2(60, 60), true)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_text(heading if heading != "" else who, 21, UI.BLUE))
	var preview := _text(body if body.length() <= 70 else body.left(68) + "…", 18, Color.WHITE)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(320, 0)
	col.add_child(preview)
	col.add_child(_text("Click to reply" if id != "" else "Click to read", 14, UI.MUTED))
	Net.corner_toast(p, "chat_message", func():
		if id != "":
			open_with(id, who, avatar)
		else:
			open_list(), 6.0)


## Connected (again): messages sent while you were away are counted, and said once a session.
func _on_opened() -> void:
	var r := await Api.request("GET", "/api/social/unread")
	if not r.ok or not r.data is Array:
		return
	for row in r.data:
		if row is Dictionary:
			unread[str(row.friend_id)] = {"count": int(row.get("count", 1)), "name": str(row.get("username", "")), "avatar": row.get("avatar_url")}
	_update_badge()
	if _told_missed or r.data.is_empty():
		return
	_told_missed = true
	var total := 0
	for row in r.data:
		total += int(row.get("count", 1))
	var first: Dictionary = r.data[0]
	var heading := "%d new message%s" % [total, "" if total == 1 else "s"]
	if r.data.size() == 1:
		_message_toast(str(first.friend_id), str(first.username), first.get("avatar_url"), str(first.get("last", "")), "%s · %s" % [str(first.username), heading])
	else:
		var names: Array = r.data.slice(0, 3).map(func(x): return str(x.username))
		_message_toast("", "", first.get("avatar_url"), "From " + ", ".join(names) + (" and more" if r.data.size() > 3 else ""), heading)


func _update_badge() -> void:
	var total := 0
	for id in unread:
		total += int(unread[id].get("count", 0))
	_badge.visible = total > 0
	_badge_text.text = str(mini(total, 99))
	if total > 0:   # (a little bounce as it changes)
		_badge.pivot_offset = _badge.size / 2
		_badge.scale = Vector2.ONE * 1.4
		_badge.create_tween().tween_property(_badge, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
