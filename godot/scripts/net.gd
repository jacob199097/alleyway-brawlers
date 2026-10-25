extends Node
## Realtime connection to the game server: a minimal Socket.io client over Godot's WebSocket
## (Engine.IO v4), authenticated with the player's login token.
##   Net.connect_to_server()   Net.send("mp:queue")   Net.event.connect(func(name, data): ...)
## Also handles things that can happen on any screen: friend challenges, a match starting,
## achievements unlocking (show_achievements).

signal opened
signal closed
signal event(name: String, data)

var is_open := false
## Match messages ([name, data]) waiting for the duel screen; it reads them every frame, so
## nothing is lost while the screen is still loading.
var inbox: Array = []
var rps_inbox: Array = []   # Scissors Paper Rock messages for screens/rps.gd
var rematch_inbox: Array = []   # rematch messages for screens/post_match.gd (may arrive before it opens)
var ffa_inbox: Array = []       # free-for-all lobby messages for screens/ffa_lobby.gd (backend/socket/ffaMatch.js)
var coop_inbox: Array = []      # Turf Defense queue messages for screens/turf_defense.gd (backend/socket/coopMatch.js)
## Turf Defense: a "join them" pop-up asked to queue for this boss level ({boss, level}); the
## Turf Defense screen picks it up when it opens
var coop_join := {}
var _rejoin := false        # ask the server for a match still in progress once connected
var _ws := WebSocketPeer.new()
var _connecting := false
var _want := false
var _retry_in := 0.0
var _retry_delay := 1.0
var _banners: Array = []      # achievements waiting to be shown, one banner at a time
var _banner_layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	event.connect(_on_global_event)


func connect_to_server() -> void:
	_want = true
	if _connecting or is_open or Api.token == "":
		return
	var url := Api.base_url().replace("https://", "wss://").replace("http://", "ws://") \
		+ "/socket.io/?EIO=4&transport=websocket"
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 8 * 1024 * 1024   # a full board update can exceed the 64 KB default
	_ws.max_queued_packets = 4096
	if _ws.connect_to_url(url) != OK:
		_retry_later()
		return
	_connecting = true


func disconnect_from_server() -> void:
	_want = false
	_ws.close()
	_connecting = false
	if is_open:
		is_open = false
		closed.emit()


## Back in a match that's still running (the game was closed or crashed mid-match): the server
## keeps the seat for 45 seconds, and answers mp:resync with mp:start (which opens the duel) or
## mp:none. The main menu calls this.
func rejoin() -> void:
	if not send("mp:resync"):
		_rejoin = true
	else:
		send("ffa:resync")   # (a free-for-all in progress: ffa:start, or ffa:none)
		send("coop:resync")  # (Turf Defense: coop:start, or coop:none)


func send(name: String, data := {}) -> bool:
	if not is_open:
		return false
	_ws.send_text("42" + JSON.stringify([name, data]))
	return true


func _process(delta: float) -> void:
	if not _connecting and not is_open:
		if _want:
			_retry_in -= delta
			if _retry_in <= 0.0:
				connect_to_server()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				_handle(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_connecting = false
			if is_open:
				is_open = false
				closed.emit()
			_retry_later()


func _retry_later() -> void:
	_retry_in = _retry_delay
	_retry_delay = minf(_retry_delay * 2.0, 15.0)


## Engine.IO: "0" open, "2" ping, "4" message. Socket.IO inside "4": "0" connected,
## "4" connect error, "2" event ["name", data].
func _handle(msg: String) -> void:
	if msg.is_empty():
		return
	match msg[0]:
		"0":
			_ws.send_text("40" + JSON.stringify({"token": Api.token}))
		"2":
			_ws.send_text("3")
		"4":
			var kind := msg.substr(1, 1)
			if kind == "0":
				_connecting = false
				is_open = true
				_retry_delay = 1.0
				opened.emit()
				if _rejoin:
					_rejoin = false
					send("mp:resync")
					send("ffa:resync")
					send("coop:resync")
			elif kind == "4":
				push_warning("Realtime login refused: " + msg.substr(2))
				_want = false
				_ws.close()
			elif kind == "2":
				var start := msg.find("[")
				var arr = JSON.parse_string(msg.substr(start)) if start >= 0 else null
				if arr is Array and not arr.is_empty():
					event.emit(str(arr[0]), normalize(arr[1] if arr.size() > 1 else null))


## JSON numbers arrive as floats and object keys as strings; the rules use ints for both
## (card stats, slots, uids). Whole-number floats → int; digit-only keys → int.
static func normalize(v):
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	if v is Array:
		return v.map(func(x): return normalize(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			var key = int(k) if k is String and k.is_valid_int() else k
			out[key] = normalize(v[k])
		return out
	return v


# ── Things that can happen on any screen ─────────────────────────────────────

func _on_global_event(name: String, data) -> void:
	match name:
		"mp:update", "mp:over", "mp:opponent", "mp:emote", "mp:spectators", "ffa:update", "ffa:over", "ffa:out", \
				"coop:update", "coop:over", "coop:emote":
			inbox.append([name, data])
			if inbox.size() > 500:
				inbox.pop_front()
		"mp:rps", "mp:rps_result", "mp:rps_choose", "mp:rps_decided", "mp:rps_cancel":
			rps_inbox.append([name, data])
			var on_rps: bool = get_tree().current_scene != null and get_tree().current_scene.has_method("on_rps")
			if name == "mp:rps":
				Game.alert()
			if name == "mp:rps" and not on_rps:
				Game.duel_setup = {"online_rps": true}
				Game.go("rps")
		"mp:rematch_offer", "mp:rematch_sent", "mp:rematch_declined":
			rematch_inbox.append([name, data])
		"ffa:lobby", "ffa:left":
			ffa_inbox.append([name, data])
			var scene := get_tree().current_scene
			if name == "ffa:lobby" and not (scene and scene.has_method("on_ffa_lobby")):
				Game.go("ffa_lobby")   # (rejoining a lobby from another screen)
		"coop:queue", "coop:left":
			coop_inbox.append([name, data])
			var scene := get_tree().current_scene
			if name == "coop:queue" and not (scene and scene.has_method("on_coop_queue")):
				Game.go("turf_defense")   # (still waiting for a partner, from another screen)
		"coop:looking":
			if data is Dictionary:
				_coop_looking(data)
		"coop:start":
			inbox.clear()
			coop_inbox.clear()
			coop_join = {}
			Game.duel_setup = {"online": true, "start": data}
			Game.alert()
			if get_tree().current_scene and get_tree().current_scene.has_method("on_online_start"):
				get_tree().current_scene.on_online_start(data)
			else:
				if data is Dictionary and data.get("resync", false):
					_toast("Rejoining Turf Defense…", UI.GOLD)
				Game.go("duel")
		"ffa:start":
			inbox.clear()
			ffa_inbox.clear()
			Game.duel_setup = {"online": true, "start": data}
			Game.alert()
			if get_tree().current_scene and get_tree().current_scene.has_method("on_online_start"):
				get_tree().current_scene.on_online_start(data)
			else:
				if data is Dictionary and data.get("resync", false):
					_toast("Rejoining your free-for-all…", UI.GOLD)
				Game.go("duel")
		"mp:start":
			inbox.clear()
			rps_inbox.clear()
			rematch_inbox.clear()
			Game.duel_setup = {"online": true, "start": data}
			if get_tree().current_scene and get_tree().current_scene.has_method("on_online_start"):
				get_tree().current_scene.on_online_start(data)
			else:
				if data is Dictionary and data.get("resync", false) and not data.get("spectate", false):
					_toast("Rejoining your match…", UI.GOLD)
				Game.go("duel")
		"friend:online":
			if data is Dictionary:
				_friend_online(data)
		"mp:challenge":
			_show_challenge(data)
		"mp:declined":
			_toast("%s declined your challenge." % data.get("byUsername", "Your friend"), UI.RED)
		"achievements":
			if data is Dictionary and data.get("unlocked") is Array:
				show_achievements(data.unlocked)
				Game.refresh_player()   # their Karat or Dust may have gone up
		"mp:error", "ffa:error", "coop:error":
			var scene := get_tree().current_scene
			if not (scene and scene.has_method("on_online_error")):
				_toast(str(data.get("message", "Something went wrong.")), UI.RED)
			else:
				scene.on_online_error(str(data.get("message", "")))


## "Friend is now online" pop-ups in the bottom-right corner (like Steam's): each slides in with
## the friend's picture, stacks above the ones still showing, and slides away after a few seconds.
var _friend_toasts: Array[Control] = []

func _friend_online(f: Dictionary) -> void:
	if _banner_layer == null:
		_banner_layer = CanvasLayer.new()
		_banner_layer.layer = 90
		add_child(_banner_layer)
	var p := UI.panel(UI.GREEN, Color(0.05, 0.07, 0.09, 0.96))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(400, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	p.add_child(row)
	var pic := UI.texture_rect(UI.avatar(f.get("avatar")), Vector2(72, 72), true)
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(UI.label(str(f.get("username", "A friend")), 26, Color.WHITE, true))
	col.add_child(UI.label("● is now online", 18, UI.GREEN))
	if f.get("level") != null:
		col.add_child(UI.label("Level %d" % int(f.level), 15, UI.MUTED))
	_banner_layer.add_child(p)
	await get_tree().process_frame   # (its size, before it's placed)
	var h: float = p.size.y + 12.0
	for t in _friend_toasts:   # the ones still up move up to make room
		if is_instance_valid(t):
			t.create_tween().tween_property(t, "position:y", t.position.y - h, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_friend_toasts.append(p)
	var home := Vector2(1920 - p.size.x - 24, 1080 - p.size.y - 24)
	p.position = Vector2(1940, home.y)
	Sfx.play("friend_online", 1.0, -8.0)
	var t := p.create_tween()
	t.tween_property(p, "position:x", home.x, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(4.5)
	t.tween_property(p, "position:x", 1940.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		_friend_toasts.erase(p)
		p.queue_free())


## "Achievement unlocked" banners, one after another at the top of the screen. They sit on their
## own layer, so they stay up while the screen changes.
func show_achievements(list: Array) -> void:
	var idle := _banners.is_empty()
	for a in list:
		if a is Dictionary:
			_banners.append(a)
	if idle:
		_next_banner()


func _next_banner() -> void:
	if _banners.is_empty():
		return
	var a: Dictionary = _banners[0]
	if _banner_layer == null:
		_banner_layer = CanvasLayer.new()
		_banner_layer.layer = 90
		add_child(_banner_layer)
	var p := UI.panel(UI.GOLD, Color(0.06, 0.05, 0.02, 0.96))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var cup := UI.achievement_icon(true, 72, UI.GOLD)
	row.add_child(cup)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	col.add_child(UI.label(str(a.get("heading", "ACHIEVEMENT UNLOCKED")), 16, UI.MUTED, true))
	col.add_child(UI.label(str(a.get("name", "")).to_upper(), 30, UI.GOLD, true))
	var gift := UI.reward_text(a.get("reward", {}) if a.get("reward") is Dictionary else {})
	if gift != "":
		col.add_child(UI.label(gift, 18, Color(0.92, 0.92, 1.0)))
	_banner_layer.add_child(p)
	await get_tree().process_frame
	var sz := p.get_combined_minimum_size()
	p.size = sz
	var y := 24.0
	p.position = Vector2(960 - sz.x / 2, -sz.y - 20)
	Sfx.play("achievement", 1.0, -2.0)
	var t := p.create_tween()
	t.tween_property(p, "position:y", y, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.2)
	t.tween_property(p, "position:y", -sz.y - 20, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		p.queue_free()
		_banners.pop_front()
		_next_banner())


## Turf Defense: someone is waiting for a partner to fight a boss. A pop-up (not mid-match) offers
## to join them: the Turf Defense screen opens and queues for the same boss level.
func _coop_looking(data: Dictionary) -> void:
	var scene := get_tree().current_scene
	if not (scene is Control) or Game.BUSY_SCREENS.any(func(s): return scene.scene_file_path == Game.SCREENS[s]):
		if scene and scene.has_method("on_coop_looking"):
			scene.on_coop_looking(data)
		return
	Game.alert(false)
	Sfx.play("ambush", 1.3, -4.0)
	var who := str(data.get("username", "A player"))
	UI.dialog(scene, "🛡  TURF DEFENSE", "%s needs a partner to fight %s (%s). Join them?" % [who, str(data.get("boss_name", "a boss")), str(data.get("level_name", ""))], [
		["JOIN", func():
			coop_join = {"boss": str(data.get("boss", "")), "level": int(data.get("level", 1))}
			Game.go("turf_defense"), UI.GREEN],
		["NOT NOW", func(): pass],
	], UI.GOLD)


func _show_challenge(data: Dictionary) -> void:
	var scene := get_tree().current_scene
	if not (scene is Control) or scene.name == "Duel":
		send("mp:decline", {"fromPlayerId": data.fromPlayerId})
		return
	Game.alert(false)
	Sfx.play("ambush", 1.2)
	UI.dialog(scene, "⚔  CHALLENGE!", "%s wants to brawl. Use your active deck?" % data.get("fromUsername", "A friend"), [
		["ACCEPT", func(): send("mp:accept", {"fromPlayerId": data.fromPlayerId}), UI.GREEN],
		["DECLINE", func(): send("mp:decline", {"fromPlayerId": data.fromPlayerId}), UI.RED],
	], UI.GOLD)


func _toast(msg: String, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene is Control:
		UI.toast(scene, msg, color)
