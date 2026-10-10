extends Node
## Shared by every screen: the signed-in player, screen changes (with a fade), settings
## (audio, display, server address), menu music, and loading the player's deck for a duel.

const SETTINGS_PATH := "user://settings.cfg"
const SESSION_PATH := "user://session.cfg"
const SCREENS := {
	"boot": "res://scenes/boot.tscn",
	"login": "res://scenes/login.tscn",
	"clan_select": "res://scenes/clan_select.tscn",
	"main_menu": "res://scenes/main_menu.tscn",
	"fight_mode": "res://scenes/fight_mode.tscn",
	"rps": "res://scenes/rps.tscn",
	"matchmaking": "res://scenes/matchmaking.tscn",
	"duel": "res://scenes/duel.tscn",
	"post_match": "res://scenes/post_match.tscn",
	"shop": "res://scenes/shop.tscn",
	"contraband": "res://scenes/contraband.tscn",
	"deck_builder": "res://scenes/deck_builder.tscn",
	"card_library": "res://scenes/card_library.tscn",
	"profile": "res://scenes/profile.tscn",
	"social": "res://scenes/social.tscn",
	"mailbox": "res://scenes/mailbox.tscn",
}
const DEFAULT_SETTINGS := {
	"music_volume": 0.5,
	"sfx_volume": 0.8,
	"window_mode": "windowed",      # windowed | fullscreen (borderless) | exclusive
	"resolution": "1600x900",
	"vsync": true,
	"fps_cap": 0,                   # 0 = unlimited
	"show_fps": false,
	"server_url": "https://alleywaybrawlers.duckdns.org",   # LAN: http://192.168.0.200:3000
	"tutorial_done": false,         # finished or skipped the guided first duel
	"tutorial_offered": false,      # the main menu has suggested it once
}
const MENU_MUSIC := "res://assets/main_menu_theme_loop.mp3"

var settings := DEFAULT_SETTINGS.duplicate()
var player := {}            # /api/profile/me
var offline := false        # no server: CPU duels with the starter deck only, nothing is saved
var last_email := ""
var duel_setup := {}        # fight mode → rock-paper-scissors → duel
var match_result := {}      # duel → post-match

var _music: AudioStreamPlayer
var _music_path := ""
var _fade: ColorRect
var _fps: Label
var _going := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.size = Vector2(1920, 1080)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wipe := ShaderMaterial.new()
	wipe.shader = preload("res://shaders/wipe.gdshader")
	_fade.material = wipe
	layer.add_child(_fade)
	_fps = Label.new()
	_fps.position = Vector2(1840, 4)
	_fps.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	layer.add_child(_fps)

	_load_settings()
	apply_settings()
	var session := ConfigFile.new()
	if session.load(SESSION_PATH) == OK:
		Api.token = session.get_value("auth", "token", "")
		last_email = session.get_value("auth", "email", "")


func _process(_delta: float) -> void:
	_fps.visible = settings.show_fps
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


# ── Screens ──────────────────────────────────────────────────────────────────

func go(screen: String) -> void:
	if _going:
		return
	_going = true
	# A slanted panel sweeps across, the scene changes behind it, and it sweeps on off
	var wipe: ShaderMaterial = _fade.material
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks while switching
	Sfx.play("whoosh", 1.15, -8.0)
	var t := create_tween()
	t.tween_method(func(p: float): wipe.set_shader_parameter("progress", p), 0.0, 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await t.finished
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(SCREENS[screen])
	await get_tree().process_frame
	_going = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t = create_tween()
	t.tween_method(func(p: float): wipe.set_shader_parameter("progress", p), 1.0, 2.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): wipe.set_shader_parameter("progress", 0.0))


# ── Session ──────────────────────────────────────────────────────────────────

func sign_in(token: String, profile: Dictionary, email: String) -> void:
	Api.token = token
	player = profile
	offline = false
	last_email = email
	_save_session()
	Net.connect_to_server()


func sign_out() -> void:
	Net.disconnect_from_server()
	Api.token = ""
	player = {}
	offline = false
	_save_session()


## A match against the server's CPU (VS CPU, or Ranked). CPU matches run on the server so
## the result, and the rewards, can be trusted. mp:start then opens the duel (net.gd).
## Returns "" once requested, or why it couldn't be.
func request_cpu_match(ranked: bool, difficulty := "normal") -> String:
	Net.connect_to_server()
	var give_up := Time.get_ticks_msec() + 8000   # real time, not game time
	while not Net.is_open and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	if not Net.is_open:
		return "Can't reach the game server. CPU matches run on the server so their rewards count; check your connection, or play offline from the login screen."
	Net.send("mp:cpu", {"ranked": ranked, "difficulty": difficulty})
	return ""


## The guided first duel (scripts/duel/tutorial.gd). Works signed in or offline.
func start_tutorial() -> void:
	duel_setup = {"mode": "tutorial"}
	go("duel")


func play_offline() -> void:
	offline = true
	player = {"username": "Guest", "level": 1, "xp": 0, "karat": 0, "contraband": 0,
		"rank": "rookie", "rank_points": 0, "wins": 0, "losses": 0, "avatar_url": "profile_001"}


## Refresh the player from the server. Returns false if the session is no longer valid.
func refresh_player() -> bool:
	if offline:
		return true
	var r := await Api.request("GET", "/api/profile/me")
	if r.ok:
		player = r.data
		Net.connect_to_server()
	return r.ok


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", Api.token)
	cfg.set_value("auth", "email", last_email)
	cfg.save(SESSION_PATH)


# ── Settings ─────────────────────────────────────────────────────────────────

func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	_save_settings()


func apply_settings() -> void:
	_set_bus("Music", settings.music_volume)
	_set_bus("SFX", settings.sfx_volume)
	Engine.max_fps = int(settings.fps_cap)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	match settings.window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var parts: PackedStringArray = str(settings.resolution).split("x")
			if parts.size() == 2:
				var size := Vector2i(int(parts[0]), int(parts[1]))
				if DisplayServer.window_get_size() != size:
					DisplayServer.window_set_size(size)
					var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
					DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _set_bus(bus: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(idx, volume <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in DEFAULT_SETTINGS:
		settings[key] = cfg.get_value("settings", key, DEFAULT_SETTINGS[key])


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)


# ── Music ────────────────────────────────────────────────────────────────────

## Keeps the menu track playing across menu screens (restarting only when it changes).
func play_music(path: String, volume_db := -8.0) -> void:
	if path == _music_path and _music.playing:
		return
	_music_path = path
	_music.stop()
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		stream.loop = true
	_music.stream = stream
	_music.volume_db = volume_db
	_music.play()


func play_menu_music() -> void:
	play_music(MENU_MUSIC)


func stop_music() -> void:
	_music_path = ""
	_music.stop()


# ── Duel decks ───────────────────────────────────────────────────────────────

## The player's active deck, ready for DuelState:
##   {deck: [card specs], hideout: [ids], leader: id, name}  or  {error, gate: bool}
## Stats come from the server's card rows; rules data from data/cards.json (matched by art key).
func load_duel_deck() -> Dictionary:
	var r := await Api.request("GET", "/api/deck")
	if not r.ok:
		return {"error": r.error}
	var decks: Array = r.data if r.data is Array else []
	var active = null
	for d in decks:
		if d.get("is_active", false):
			active = d
	if active == null and not decks.is_empty():
		active = decks[0]
	if active == null or int(active.get("card_count", 0)) < 40:
		var msg := "No active deck. Open the Deck Editor and build a 40-card deck first."
		if active != null:
			msg = "Active deck \"%s\" has %d/40 cards. Edit your deck before starting." % [active.name, int(active.card_count)]
		return {"error": msg, "gate": true}

	var dr := await Api.request("GET", "/api/deck/%s" % active.id)
	if not dr.ok:
		return {"error": dr.error}
	var ir := await Api.request("GET", "/api/profile/inventory")
	var owned := {}
	if ir.ok and ir.data is Array:
		for row in ir.data:
			owned[str(row.get("art_url", ""))] = row

	var deck: Array = []
	for row in dr.data.get("cards", []):
		var id := str(row.get("art_url", ""))
		if CardDB.get_card(id).is_empty():
			continue   # not playable by the rules yet
		for i in int(row.get("copies", 1)):
			deck.append(_card_spec(id, row))
	var hideout: Array = []
	var seen := {}
	for row in dr.data.get("cards", []):
		var next := CardDB.next_form(str(row.get("art_url", "")))
		while next != "" and not seen.has(next):
			seen[next] = true
			if owned.has(next):
				for i in mini(3, int(owned[next].get("quantity", 0))):
					hideout.append(_card_spec(next, owned[next]))
			next = CardDB.next_form(next)
	var leader := ""
	var lrow = dr.data.get("leader")
	if lrow is Dictionary and not CardDB.get_card(str(lrow.get("art_url", ""))).is_empty():
		leader = str(lrow.art_url)
	return {"deck": deck, "hideout": hideout, "leader": leader, "name": str(active.name)}


static func _card_spec(id: String, row: Dictionary) -> Dictionary:
	var spec := {"id": id}
	for key in ["name", "authority", "attack", "defense", "rarity"]:
		if row.get(key) != null:
			spec[key] = row[key]
	return spec
