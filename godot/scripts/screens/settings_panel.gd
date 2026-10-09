class_name SettingsPanel
extends Control
## Settings overlay (menu gear, or Esc in a duel): Audio, Display and Server tabs.
## Changes apply and save immediately (Game.set_setting).

const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const WINDOW_MODES := [["windowed", "WINDOWED"], ["fullscreen", "BORDERLESS FULLSCREEN"], ["exclusive", "EXCLUSIVE FULLSCREEN"]]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]

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
	for t in [["audio", "AUDIO"], ["display", "DISPLAY"], ["server", "SERVER"]]:
		var b := UI.button(t[1], _show.bind(t[0]), Vector2(240, 52))
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
		"display":
			_cycle("Window Mode", WINDOW_MODES.map(func(m): return m[0]), WINDOW_MODES.map(func(m): return m[1]), "window_mode")
			_cycle("Resolution (windowed)", RESOLUTIONS, RESOLUTIONS.map(func(r): return r.replace("x", " × ")), "resolution")
			_cycle("V-Sync", [true, false], ["ON", "OFF"], "vsync")
			_cycle("FPS Cap", FPS_CAPS, FPS_CAPS.map(func(f): return "UNLIMITED" if f == 0 else str(f)), "fps_cap")
			_cycle("Show FPS", [true, false], ["ON", "OFF"], "show_fps")
		"server":
			_server_tab()


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
