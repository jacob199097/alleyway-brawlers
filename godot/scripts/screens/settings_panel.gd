class_name SettingsPanel
extends Control
## Settings overlay (menu gear, or Esc in a duel): Audio, Display, Gameplay, Controls, Account and Server tabs.
## Changes apply and save immediately (Game.set_setting).

const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const WINDOW_MODES := [["windowed", "WINDOWED"], ["fullscreen", "BORDERLESS FULLSCREEN"], ["exclusive", "EXCLUSIVE FULLSCREEN"]]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]
const ANIM_SPEEDS := [1.0, 1.5, 2.0]
## Duel keyboard shortcuts (scripts/duel/duel.gd, _unhandled_input), listed on the Gameplay tab
const SHORTCUTS := [["Space / Enter", "Next phase / end turn"], ["Esc", "Cancel, or open the menu"],
	["Right-click", "Cancel what you're doing"], ["L", "Battle log"], ["E", "Emotes (against players)"],
	["F11", "Fullscreen"]]
## Controller buttons (scripts/pad.gd), listed on the Controls tab
const PAD_BUTTONS := [["Left stick", "Move the pointer"], ["D-pad", "Jump to the next button or card"],
	["A", "Select (hold and move to drag)"], ["X", "Zoom in on a card"], ["B", "Back / cancel"],
	["Y", "Next phase / end turn"], ["Start", "Menu"], ["LB / RB", "Pages, Striver levels"],
	["Right stick", "Scroll"], ["LT", "Emotes"], ["View / Select", "Battle log"]]

var allow_logout := true
var _tab := "audio"
var _body: VBoxContainer
var _tabs := {}


static func open(parent: Node, logout := true) -> SettingsPanel:
	var s := SettingsPanel.new()
	s.allow_logout = logout
	parent.add_child(s)
	return s


func _ready() -> void:
	theme = UI.theme()
	size = Vector2(1920, 1080)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.72)
	veil.size = size
	add_child(veil)
	var p := UI.panel(UI.BLUE, Color(0.05, 0.05, 0.12, 0.98))
	p.position = Vector2(360, 140)
	p.custom_minimum_size = Vector2(1200, 800)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	p.add_child(col)
	var h := UI.label("SETTINGS", 48, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 16)
	col.add_child(tabs)
	for t in [["audio", "AUDIO"], ["display", "DISPLAY"], ["gameplay", "GAMEPLAY"], ["controls", "CONTROLS"], ["account", "ACCOUNT"], ["server", "SERVER"]]:
		var b := UI.button(t[1], _show.bind(t[0]), Vector2(176, 52))
		b.toggle_mode = true
		tabs.add_child(b)
		_tabs[t[0]] = b
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	_body.custom_minimum_size = Vector2(1100, 480)
	col.add_child(_body)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 30)
	col.add_child(bottom)
	bottom.add_child(UI.button("CLOSE", close, Vector2(260, 60)))
	if allow_logout and not Game.player.is_empty():
		bottom.add_child(UI.button("LOG OUT", func():
			Game.sign_out()
			Game.go("login"), Vector2(260, 60), UI.RED))
	_show("audio")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	queue_free()


func _show(tab: String) -> void:
	_tab = tab
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == tab)
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"audio":
			_slider("Music Volume", "music_volume")
			_slider("Sound Effects Volume", "sfx_volume")
			_slider("Ambience Volume", "ambience_volume")
		"display":
			_cycle("Window Mode", WINDOW_MODES.map(func(m): return m[0]), WINDOW_MODES.map(func(m): return m[1]), "window_mode")
			_cycle("Resolution (windowed)", RESOLUTIONS, RESOLUTIONS.map(func(r): return r.replace("x", " × ")), "resolution")
			_cycle("V-Sync", [true, false], ["ON", "OFF"], "vsync")
			_cycle("FPS Cap", FPS_CAPS, FPS_CAPS.map(func(f): return "UNLIMITED" if f == 0 else str(f)), "fps_cap")
			_cycle("Show FPS", [true, false], ["ON", "OFF"], "show_fps")
		"gameplay":
			_cycle("Animation Speed", ANIM_SPEEDS, ["NORMAL", "FAST (1.5×)", "FASTER (2×)"], "anim_speed")
			_cycle("Turn Alerts", [true, false], ["ON", "OFF"], "turn_alert")
			_cycle("Rival Emotes", [true, false], ["SHOW", "HIDE"], "rival_emotes")
			_cycle("Colour-Blind Symbols", [false, true], ["OFF", "ON"], "glow_symbols")
			_cycle("Screen Shake & Flashes", [1.0, 0.5, 0.0], ["FULL", "REDUCED", "OFF"], "screen_fx")
			var note := UI.label("Screen shake & flashes: how hard big hits shake and flash the screen in a duel. Turn alerts flash the game in the taskbar, with a sound, when it's your move and the game isn't in front. Colour-blind symbols add a shape to every glow in a duel: + can be played, ! can act, a bolt for an Activate ability, arrows to deploy over, X to sacrifice, a crosshair to attack.", 20, UI.MUTED)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD
			note.custom_minimum_size = Vector2(1000, 0)
			_body.add_child(note)
			_body.add_child(UI.button("HOW TO PLAY", func(): load("res://scripts/ui/how_to_play.gd").open(self), Vector2(320, 52), UI.GOLD))
		"controls":
			var cols := HBoxContainer.new()
			cols.add_theme_constant_override("separation", 60)
			_body.add_child(cols)
			cols.add_child(_key_list("KEYBOARD & MOUSE", SHORTCUTS))
			cols.add_child(_key_list("CONTROLLER", PAD_BUTTONS))
			var pad_note := UI.label("Xbox, PlayStation and Steam Deck controllers work everywhere in the game: the controller moves a pointer, and the D-pad jumps it between buttons and cards. Move the mouse to switch back. On Steam Deck, Steam + X opens the keyboard for typing.", 20, UI.MUTED)
			pad_note.autowrap_mode = TextServer.AUTOWRAP_WORD
			pad_note.custom_minimum_size = Vector2(1000, 0)
			_body.add_child(pad_note)
		"account":
			_account_tab()
		"server":
			_server_tab()


## A heading over two columns: the key or button, and what it does.
func _key_list(heading: String, rows: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UI.label(heading, 24, Color.WHITE, true))
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 24)
	keys.add_theme_constant_override("v_separation", 4)
	box.add_child(keys)
	for k in rows:
		keys.add_child(UI.label(k[0], 20, UI.GOLD, true))
		keys.add_child(UI.label(k[1], 20, Color.WHITE))
	return box


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := UI.label(text, 26, Color.WHITE, true)
	l.custom_minimum_size = Vector2(420, 0)
	row.add_child(l)
	_body.add_child(row)
	return row


func _slider(text: String, key: String) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.custom_minimum_size = Vector2(480, 40)
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Game.settings[key]
	row.add_child(s)
	var v := UI.label("%d%%" % roundi(s.value * 100), 24, UI.MUTED)
	row.add_child(v)
	s.value_changed.connect(func(x):
		v.text = "%d%%" % roundi(x * 100)
		Game.set_setting(key, x)
		if key == "sfx_volume":
			Sfx.play("click"))


func _cycle(text: String, values: Array, labels: Array, key: String) -> void:
	var row := _row(text)
	var idx := maxi(0, values.find(Game.settings[key]))
	var b := Button.new()
	b.custom_minimum_size = Vector2(480, 52)
	b.text = "◀   %s   ▶" % labels[idx]
	row.add_child(b)
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var step := 1 if e.button_index == MOUSE_BUTTON_LEFT else -1
			if e.button_index == MOUSE_BUTTON_LEFT and e.position.x < b.size.x / 3:
				step = -1
			idx = (idx + step + values.size()) % values.size()
			b.text = "◀   %s   ▶" % labels[idx]
			Sfx.play("click")
			Game.set_setting(key, values[idx]))


## Who's signed in, the privacy policy and terms (pages on the server, backend/routes/legal.js), and
## deleting the account (backend/routes/account.js).
func _account_tab() -> void:
	var signed_in := not Game.player.is_empty() and not Game.offline
	var mail = Game.player.get("email")
	var how: String = str(mail) if mail is String and mail != "" else "Steam"
	var who := UI.label("Signed in as %s  ·  %s" % [Game.player.get("username", ""), how] if signed_in
		else ("Playing offline: nothing is saved on the server." if Game.offline else "Not signed in."), 24, Color.WHITE)
	_body.add_child(who)
	if signed_in and Game.steam.active:   # Steam: link this account so Steam signs you in (and can buy)
		var srow := _row("Steam")
		if Game.player.get("steam_linked", false):
			srow.add_child(UI.label("Linked to %s ✓" % Game.steam.persona, 22, UI.GREEN))
		else:
			var sstatus := UI.label("", 20, UI.RED)
			srow.add_child(UI.button("LINK STEAM ACCOUNT", func():
				sstatus.text = "Linking…"
				var why: String = await Game.link_steam()
				if why == "":
					_show("account")
				else:
					sstatus.text = why, Vector2(320, 52)))
			srow.add_child(sstatus)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 20)
	_body.add_child(links)
	links.add_child(UI.button("PRIVACY POLICY", func(): OS.shell_open(Api.base_url() + "/privacy"), Vector2(300, 52)))
	links.add_child(UI.button("TERMS OF SERVICE", func(): OS.shell_open(Api.base_url() + "/terms"), Vector2(300, 52)))
	if not signed_in:
		return
	var head := UI.label("DELETE ACCOUNT", 26, UI.RED, true)
	_body.add_child(head)
	var warn := UI.label("Deletes your account for good: your cards and packs, decks, Karat, Contraband and Dust, progress, achievements, friends, messages, mail and match recordings. Contraband you bought is lost and isn't refunded. This can't be undone.", 20, UI.MUTED)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	warn.custom_minimum_size = Vector2(1000, 0)
	_body.add_child(warn)
	# (a Steam player has no password: typing DELETE confirms it)
	var no_password: bool = Game.player.get("has_password", true) == false
	var row := _row("Type DELETE" if no_password else "Your password")
	var pw := LineEdit.new()
	pw.secret = not no_password
	pw.placeholder_text = "DELETE" if no_password else "Password"
	pw.custom_minimum_size = Vector2(420, 52)
	row.add_child(pw)
	var status := UI.label("", 22, UI.RED)
	var go := func():
		if pw.text == "" or (no_password and pw.text.strip_edges().to_upper() != "DELETE"):
			status.text = "Type DELETE first." if no_password else "Enter your password first."
			return
		UI.dialog(self, "DELETE YOUR ACCOUNT?", "%s and everything in it will be gone for good." % Game.player.get("username", "Your account"),
			[["KEEP IT", func(): pass], ["DELETE FOREVER", func():
				status.text = "Deleting…"
				status.label_settings.font_color = UI.MUTED
				var r := await Api.request("POST", "/api/account/delete", {"confirm": "DELETE"} if no_password else {"password": pw.text})
				if not r.ok:
					status.text = r.error
					status.label_settings.font_color = UI.RED
					return
				Game.sign_out()
				Game.go("login"), UI.RED]], UI.RED)
	row.add_child(UI.button("DELETE ACCOUNT", go, Vector2(300, 52), UI.RED))
	_body.add_child(status)


func _server_tab() -> void:
	var row := _row("Server Address")
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(560, 52)
	edit.text = Game.settings.server_url
	edit.placeholder_text = "http://192.168.0.200:3000"
	row.add_child(edit)
	var status := UI.label("", 22, UI.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size = Vector2(1000, 0)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	_body.add_child(buttons)
	_body.add_child(status)
	var save := func():
		Game.set_setting("server_url", edit.text.strip_edges())
		status.text = "Saved."
		status.label_settings.font_color = UI.GREEN
	edit.text_submitted.connect(func(_t): save.call())
	buttons.add_child(UI.button("SAVE", save, Vector2(200, 52)))
	buttons.add_child(UI.button("TEST CONNECTION", func():
		save.call()
		status.text = "Connecting…"
		status.label_settings.font_color = UI.MUTED
		var r := await Api.request("GET", "/health")
		if r.status == 0:
			status.text = r.error
			status.label_settings.font_color = UI.RED
		else:
			status.text = "Server reachable (%s)." % Api.base_url()
			status.label_settings.font_color = UI.GREEN, Vector2(300, 52)))
	var hint := UI.label("For friends playing over a VPN such as Tailscale, use the server PC's VPN address, e.g. http://100.x.y.z:3000.", 20, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size = Vector2(1000, 0)
	_body.add_child(hint)
