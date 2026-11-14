extends Node
## Phone notifications (Android): the AlleywayPush plugin (android/alleyway_push, only in the Android
## build) gets this phone's Firebase Cloud Messaging token, and the game hands it to the server, which
## sends the notifications (backend/utils/push.js: invites, the daily reward, results, updates). Each kind
## is a notification channel, so players can turn any of them off in the phone's settings; Settings →
## Gameplay → Phone Notifications turns them all off (the token leaves the server). Net owns this node
## (Net.push) and starts it once the connection is up, so it runs for every signed-in session.

## [id, name, what it's for, importance (2 low, 3 default, 4 high)]: the server's kinds
const CHANNELS := [
	["invites", "Invites and challenges", "A friend challenges you or needs a Turf Defense partner", 4],
	["daily", "Daily reward", "Your daily reward is ready", 3],
	["results", "Season and turf results", "A season or a turf map week ended with rewards to claim", 3],
	["updates", "Game updates", "A new version of the game or new cards", 2],
]

var _plugin: Object = null
var _token := ""
var _sent_for := ""   # the session token the phone's token was last sent with


func _ready() -> void:
	if Engine.has_singleton("AlleywayPush"):
		_plugin = Engine.get_singleton("AlleywayPush")
		_plugin.connect("token", _on_token)
		for c in CHANNELS:
			_plugin.createChannel(c[0], c[1], c[2], c[3])


## Whether this game can get notifications (an Android build with the plugin).
func available() -> bool:
	return _plugin != null


## Signed in and connected (Net): ask the phone for permission once (Android 13 and newer; older ones
## don't ask), then for its token, which goes to the server.
func start() -> void:
	if _plugin == null or Game.offline or Api.token == "" or not Game.settings.get("phone_notifications", true):
		return
	if _token != "":
		_register()
		return
	OS.request_permission("android.permission.POST_NOTIFICATIONS")
	_plugin.requestToken()


## Signing out, or turned off in Settings: the server forgets this phone.
func stop() -> void:
	if _token != "" and Api.token != "":
		Api.request("DELETE", "/api/push/token", {"token": _token})
	_sent_for = ""


## Settings → Phone Notifications.
func set_enabled(on: bool) -> void:
	Game.set_setting("phone_notifications", on)
	if on:
		start()
	else:
		stop()


func _on_token(token: String) -> void:
	_token = token
	_register()


func _register() -> void:
	if _token == "" or Api.token == "" or _sent_for == Api.token or not Game.settings.get("phone_notifications", true):
		return
	_sent_for = Api.token
	# (the phone clock's offset from UTC, so reminders come in its daytime)
	var tz := int(Time.get_time_zone_from_system().get("bias", 0))
	var r: Dictionary = await Api.request("POST", "/api/push/token", {"token": _token, "platform": "android", "tz_minutes": tz})
	if not r.ok:
		_sent_for = ""   # (tried again the next time the connection comes up)
