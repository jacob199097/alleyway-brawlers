extends Node
## Realtime connection to the game server: a minimal Socket.io client over Godot's WebSocket
## (Engine.IO v4), authenticated with the player's login token.
##   Net.connect_to_server()   Net.send("mp:queue")   Net.event.connect(func(name, data): ...)
## Also handles things that can happen on any screen: friend challenges, a match starting.

signal opened
signal closed
signal event(name: String, data)

var is_open := false
## Match messages ([name, data]) waiting for the duel screen; it reads them every frame, so
## nothing is lost while the screen is still loading.
var inbox: Array = []
var _ws := WebSocketPeer.new()
var _connecting := false
var _want := false
var _retry_in := 0.0
var _retry_delay := 1.0


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
		"mp:update", "mp:over", "mp:opponent":
			inbox.append([name, data])
			if inbox.size() > 500:
				inbox.pop_front()
		"mp:start":
			inbox.clear()
			Game.duel_setup = {"online": true, "start": data}
			if get_tree().current_scene and get_tree().current_scene.has_method("on_online_start"):
				get_tree().current_scene.on_online_start(data)
			else:
				Game.go("duel")
		"mp:challenge":
			_show_challenge(data)
		"mp:declined":
			_toast("%s declined your challenge." % data.get("byUsername", "Your friend"), UI.RED)
		"mp:error":
			var scene := get_tree().current_scene
			if not (scene and scene.has_method("on_online_error")):
				_toast(str(data.get("message", "Something went wrong.")), UI.RED)
			else:
				scene.on_online_error(str(data.get("message", "")))


func _show_challenge(data: Dictionary) -> void:
	var scene := get_tree().current_scene
	if not (scene is Control) or scene.name == "Duel":
		send("mp:decline", {"fromPlayerId": data.fromPlayerId})
		return
	Sfx.play("ambush", 1.2)
	UI.dialog(scene, "⚔  CHALLENGE!", "%s wants to brawl. Use your active deck?" % data.get("fromUsername", "A friend"), [
		["ACCEPT", func(): send("mp:accept", {"fromPlayerId": data.fromPlayerId}), UI.GREEN],
		["DECLINE", func(): send("mp:decline", {"fromPlayerId": data.fromPlayerId}), UI.RED],
	], UI.GOLD)


func _toast(msg: String, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene is Control:
		UI.toast(scene, msg, color)
