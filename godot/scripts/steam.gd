extends Node
## Steam, through GodotSteam (addons/godotsteam): sign-in tickets the server checks
## (backend/routes/steam.js), achievements, the overlay, Steam wallet purchases and the Steam
## Deck's on-screen keyboard. Game.steam is this node (game.gd makes it: patches can't add autoloads).
##
## It only switches on in the Steam build (the "Windows Steam" export preset adds the feature
## "steam") or with --steam on the command line (testing against the Steam client). Anywhere else,
## and wherever the GodotSteam library isn't there (an older install updated by a patch), active is
## false and every call here does nothing, so callers never need to check.

signal purchase_answered(order_id: String, authorized: bool)   # Steam's purchase prompt was answered

## Valve's test app (Spacewar) until AlleyWay Brawlers has its own App ID: then put it here, in the
## server's STEAM_APP_ID and in tools/steam_build.mjs (docs/STEAM.md)
const APP_ID := 480
const IDENTITY := "alleyway"   # the server checks tickets made for this (backend/utils/steam.js)
const FLOATING_SINGLE_LINE := 0   # Steam's EFloatingGamepadTextInputMode

var active := false
var steam_id := ""
var persona := ""
var _steam: Object = null


## The Steam build (a Steam-only Windows export): Steam updates it, so no in-game patches.
static func build() -> bool:
	return OS.has_feature("steam")


func wanted() -> bool:
	return build() or "--steam" in OS.get_cmdline_user_args()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not wanted() or not Engine.has_singleton("Steam"):
		return
	_steam = Engine.get_singleton("Steam")
	# Started outside Steam: Steam starts it again (only with the game's own App ID)
	if build() and APP_ID != 480 and _steam.restartAppIfNecessary(APP_ID):
		get_tree().quit()
		return
	var r = _steam.steamInitEx(APP_ID, false)
	if not r is Dictionary or int(r.get("status", 1)) != 0:
		push_warning("Steam didn't start: %s" % str(r.get("verbal", r) if r is Dictionary else r))
		return
	active = true
	steam_id = str(_steam.getSteamID())
	persona = str(_steam.getPersonaName())
	_steam.microtransaction_auth_response.connect(func(_app, order, authorized):
		purchase_answered.emit(str(order), bool(authorized)))
	# The Steam Deck's keyboard comes up for text boxes (no physical keyboard there)
	get_viewport().gui_focus_changed.connect(_on_focus)


func _process(_delta: float) -> void:
	if active:
		_steam.run_callbacks()


## A sign-in ticket for the server, as hex ("" if Steam isn't there or didn't give one).
func web_ticket() -> String:
	if not active:
		return ""
	var box := {"handle": -1, "done": false, "hex": ""}
	var on := func(handle, result, _size, buffer):
		if int(handle) == int(box.handle):
			box.done = true
			box.hex = PackedByteArray(buffer).hex_encode() if int(result) == 1 else ""
	_steam.get_ticket_for_web_api.connect(on)
	var give_up := Time.get_ticks_msec() + 10000
	while int(box.handle) <= 0 and Time.get_ticks_msec() < give_up:   # (0 right after start-up: Steam isn't ready yet)
		box.handle = int(_steam.getAuthTicketForWebApi(IDENTITY))
		if int(box.handle) <= 0:
			await get_tree().create_timer(0.3).timeout
	while not box.done and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	_steam.get_ticket_for_web_api.disconnect(on)
	return str(box.hex)


## Unlocks a Steam achievement (its API name: the game's own achievement id, docs/STEAM.md).
func unlock(api_name: String) -> void:
	if active and api_name != "":
		_steam.setAchievement(api_name)
		_steam.storeStats()


## Steam's language for the player, as the two-letter code the server's purchases use.
func language() -> String:
	if not active:
		return "en"
	var codes := {"english": "en", "german": "de", "french": "fr", "spanish": "es", "italian": "it",
		"portuguese": "pt", "brazilian": "pt", "russian": "ru", "polish": "pl", "japanese": "ja", "koreana": "ko",
		"schinese": "zh", "tchinese": "zh", "dutch": "nl", "turkish": "tr", "swedish": "sv"}
	return str(codes.get(str(_steam.getCurrentGameLanguage()), "en"))


## A web page in the Steam overlay (the browser when there's no Steam).
func open_url(url: String) -> void:
	if active and _steam.isOverlayEnabled():
		_steam.activateGameOverlayToWebPage(url)
	else:
		OS.shell_open(url)


static func on_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"


func _on_focus(c: Control) -> void:
	if active and on_deck() and c is LineEdit and c.editable:
		var r := c.get_global_rect()
		var k := get_viewport().get_final_transform()   # (the game is drawn scaled to the window)
		var at: Vector2 = k * r.position
		var size: Vector2 = k.basis_xform(r.size)
		_steam.showFloatingGamepadTextInput(FLOATING_SINGLE_LINE, int(at.x), int(at.y), int(size.x), int(size.y))
