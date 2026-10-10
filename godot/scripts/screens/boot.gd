extends Screen
## First screen: checks the game version and downloads any new cards from the server
## (scripts/content_sync.gd), then resumes a saved session or goes to login.

const ContentSync := preload("res://scripts/content_sync.gd")

var _status: Label
var _panel: PanelContainer
var _bar_fill: ColorRect
var _bar_label: Label
var _preview: TextureRect
var _preview_name: Label


func _ready() -> void:
	UI.background(self, "menu_background.png", 0.4)
	var logo := UI.texture_rect(UI.tex("title_alleyway.png"), Vector2(1000, 545))
	logo.position = Vector2(460, 120)
	add_child(logo)
	_status = UI.spinner(self, Vector2(960, 760), "CONNECTING…")
	var ver := UI.label("v%s" % ContentSync.game_version(), 16, UI.MUTED)
	ver.position = Vector2(20, 1050)
	add_child(ver)
	Game.play_menu_music()
	Patcher.boot_ok()   # the game (and any patch) started fine
	await get_tree().process_frame
	if "--autoplay" in OS.get_cmdline_user_args():
		Game.play_offline()
		Game.duel_setup = {}
		Game.go("duel")
		return
	if not await _check_content():
		return
	if Api.token == "":
		Game.go("login")
		return
	if await Game.refresh_player():
		Game.go("main_menu" if Game.player.get("chosen_clan") else "clan_select")
	else:
		Game.go("login")


## Version check, then new cards. Returns false when the player chose to quit or update.
func _check_content() -> bool:
	_status.text = "CHECKING FOR UPDATES…"
	var sync := ContentSync.new()
	var probe: Dictionary = await sync.run(false)
	if probe.reachable:
		var v: Dictionary = probe.version
		var mine := ContentSync.game_version()
		# A small in-place update when the server has one for this build (scripts/patcher.gd)
		var p = v.get("patch")
		if p is Dictionary and _can_patch(p, mine) and await _apply_patch(p):
			return false   # restarting into the new version
		if ContentSync.compare_versions(mine, str(v.get("minimum", "0"))) < 0:
			return await _update_required(v, mine)
		if ContentSync.compare_versions(mine, str(v.get("latest", "0"))) < 0:
			await _update_available(v, mine)
		sync.started.connect(_on_started)
		sync.progress.connect(_on_progress)
		var r: Dictionary = await sync.run()
		if r.downloaded > 0:
			_bar_label.text = "CARDS UP TO DATE"
			Sfx.play("promote", 1.2, -6.0)
			await get_tree().create_timer(0.8).timeout
		elif r.failed > 0:
			UI.toast(self, "Some new cards couldn't be downloaded. They'll be tried again next time.", UI.RED)
	_status.text = "CONNECTING…"
	return true


## This build is too old for the server: download the new one, or play offline.
func _update_required(v: Dictionary, mine: String) -> bool:
	_status.visible = false
	var url := str(v.get("downloadUrl", ""))
	var choice := [""]
	var buttons: Array = []
	if url != "":
		buttons.append(["DOWNLOAD", func(): choice[0] = "download", UI.GREEN])
	buttons.append(["PLAY OFFLINE", func(): choice[0] = "offline"])
	buttons.append(["QUIT", func(): choice[0] = "quit", UI.RED])
	UI.dialog(self, "UPDATE REQUIRED",
		"Version %s of Alleyway Brawlers is out (you have %s). Download the new version to keep playing online.%s"
			% [v.get("latest", "?"), mine, "" if url != "" else "\nAsk the person who runs the server for the new version."],
		buttons, UI.GOLD)
	while choice[0] == "":
		await get_tree().process_frame
	match choice[0]:
		"download":
			OS.shell_open(url)
			get_tree().quit()
		"quit":
			get_tree().quit()
		"offline":
			Game.go("login")
	return false


## A newer build exists but this one still works: offer the download, then carry on.
func _update_available(v: Dictionary, mine: String) -> void:
	var url := str(v.get("downloadUrl", ""))
	if url == "":
		UI.toast(self, "Version %s is available (you have %s)." % [v.get("latest", "?"), mine], UI.GOLD)
		return
	var choice := [""]
	UI.dialog(self, "NEW VERSION AVAILABLE",
		"Version %s is out (you have %s). You can keep playing, but it's worth updating." % [v.get("latest", "?"), mine],
		[["DOWNLOAD", func(): choice[0] = "download", UI.GREEN], ["LATER", func(): choice[0] = "later"]], UI.GOLD)
	while choice[0] == "":
		await get_tree().process_frame
	if choice[0] == "download":
		OS.shell_open(url)


# ── In-place update (patch) ──────────────────────────────────────────────────

func _can_patch(p: Dictionary, mine: String) -> bool:
	var version := str(p.get("version", ""))
	return not OS.has_feature("editor") and ContentSync.compare_versions(mine, version) < 0 \
		and ContentSync.compare_versions(Patcher.builtin, str(p.get("base", ""))) >= 0 \
		and not Patcher.failed(version) and str(p.get("path", "")) != ""


## Download the patch, check it, install it and restart. False if it couldn't be done
## (the normal "download the new version" offer follows).
func _apply_patch(p: Dictionary) -> bool:
	var version := str(p.version)
	var size := int(p.get("size", 0))
	_status.visible = false
	_build_panel("UPDATING TO v%s" % version, "Downloading a small update. The game restarts when it's done.", "0%")
	var http := HTTPRequest.new()
	http.timeout = 120.0
	add_child(http)
	var err := http.request(Api.base_url() + str(p.path))
	var result: Array = []
	http.request_completed.connect(func(r, code, _h, body): result.assign([r, code, body]))
	while err == OK and result.is_empty():
		var got := http.get_downloaded_bytes()
		var total := maxi(1, size if size > 0 else http.get_body_size())
		_bar_fill.size.x = 520.0 * clampf(float(got) / total, 0.0, 1.0)
		_bar_label.text = "%d%%  ·  %.1f / %.1f MB" % [int(100.0 * got / total), got / 1048576.0, total / 1048576.0]
		await get_tree().process_frame
	http.queue_free()
	var ok: bool = err == OK and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	if ok:
		var bytes: PackedByteArray = result[2]
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		ok = hash.finish().hex_encode() == str(p.get("sha256", "")) and Patcher.install(version, str(p.base), bytes)
	if not ok:
		_panel.queue_free()
		_panel = null
		_status.visible = true
		UI.toast(self, "The update couldn't be downloaded. Try again later.", UI.RED)
		return false
	_bar_fill.size.x = 520.0
	_bar_label.text = "RESTARTING…"
	Sfx.play("promote", 1.2, -6.0)
	await get_tree().create_timer(0.8).timeout
	Patcher.restart()
	return true


# ── Download screen ──────────────────────────────────────────────────────────

func _on_started(total: int) -> void:
	if total <= 0:
		return
	_status.visible = false
	_build_panel("NEW CARDS ARRIVING", "Getting the latest cards from the server…", "0 / %d" % total)


## The download panel: a card that flips as cards land, a heading, a line of text and a bar.
func _build_panel(heading: String, text: String, bar_text: String) -> void:
	_panel = UI.panel(UI.GOLD, Color(0.03, 0.03, 0.09, 0.95))
	_panel.custom_minimum_size = Vector2(760, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_panel.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(170, 240)
	row.add_child(holder)
	_preview = UI.texture_rect(CardDB.back(), Vector2(170, 240))
	_preview.pivot_offset = _preview.size / 2
	holder.add_child(_preview)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UI.label(heading, 34, UI.GOLD, true))
	_preview_name = UI.label(text, 20, UI.MUTED)
	col.add_child(_preview_name)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.1)
	track.custom_minimum_size = Vector2(520, 18)
	col.add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UI.GOLD
	_bar_fill.size = Vector2(0, 18)
	track.add_child(_bar_fill)
	_bar_label = UI.label(bar_text, 22, Color.WHITE, true)
	col.add_child(_bar_label)
	add_child(_panel)
	_panel.reset_size()
	_panel.position = Vector2(960 - _panel.size.x / 2, 700)
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.25)


func _on_progress(done: int, total: int, id: String, tex: Texture2D) -> void:
	if _panel == null:
		return
	create_tween().tween_property(_bar_fill, "size:x", 520.0 * done / maxi(1, total), 0.2)
	_bar_label.text = "%d / %d" % [done, total]
	if tex == null:
		return
	# Each new card flips in as it lands
	var c := CardDB.get_card(id)
	_preview_name.text = str(c.get("name", id)) if not c.is_empty() else id.replace("_", " ").capitalize()
	var t := create_tween()
	t.tween_property(_preview, "scale:x", 0.0, 0.08)
	t.tween_callback(func(): _preview.texture = tex)
	t.tween_property(_preview, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_BACK)
	Sfx.play("flip", 1.1, -8.0)
