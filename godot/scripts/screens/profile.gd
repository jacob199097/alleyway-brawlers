extends Screen
## Profile: avatar picker, name, title, rank, level/XP, and stats.

const ICONS := ["profile_001", "profile_002"]


func _ready() -> void:
	back_to = "main_menu"
	UI.background(self, "menu_background.png", 0.62)
	Game.play_menu_music()
	UI.back_button(self, func(): Game.go("main_menu"))
	await Game.refresh_player()
	_render(Game.player)


func _render(p: Dictionary) -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(150, 80)
	left.custom_minimum_size = Vector2(620, 0)
	left.add_theme_constant_override("separation", 14)
	add_child(left)
	var current := str(p.get("avatar_url", "profile_001"))
	var av := UI.texture_rect(UI.tex("%s.png" % current) if UI.tex("%s.png" % current) else UI.tex("profile_001.png"), Vector2(260, 260), true)
	var av_box := CenterContainer.new()
	av_box.add_child(av)
	left.add_child(av_box)
	if not Game.offline:
		var icons := HBoxContainer.new()
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		icons.add_theme_constant_override("separation", 14)
		left.add_child(icons)
		for key in ICONS:
			var b := TextureButton.new()
			b.texture_normal = UI.tex("%s.png" % key)
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
			b.custom_minimum_size = Vector2(80, 80)
			b.tooltip_text = "Use this icon"
			b.modulate = Color.WHITE if key == current else Color(0.6, 0.6, 0.7)
			b.pressed.connect(_set_icon.bind(key))
			icons.add_child(b)
		var hint := UI.label("CLICK AN ICON TO CHANGE", 16, UI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(hint)
	for spec in [[str(p.get("username", "")), 52, UI.GOLD], [UI.player_title(int(p.get("level", 1))), 28, UI.RED],
			[str(p.get("rank", "rookie")).replace("_", " ").to_upper(), 26, UI.BLUE]]:
		var l := UI.label(spec[0], spec[1], spec[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(l)
	var xp := UI.xp_progress(p)
	var lvl := UI.label("Level %d  —  %d / %d XP" % [int(p.get("level", 1)), xp.current, xp.needed], 24)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(lvl)
	var track := ColorRect.new()
	track.color = Color("1a1a3a")
	track.custom_minimum_size = Vector2(620, 16)
	left.add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.BLUE
	fill.size = Vector2(620 * xp.pct, 16)
	track.add_child(fill)
	var rp := UI.label("%d Rank Points" % int(p.get("rank_points", 0)), 22, UI.MUTED)
	rp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rp)
	var bio = p.get("profile_bio")
	if bio is String and bio != "":
		var b := UI.label("\"%s\"" % bio, 20, UI.MUTED)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(b)

	var wins := int(p.get("wins", 0))
	var losses := int(p.get("losses", 0))
	var stats := [
		["KARAT", str(int(p.get("karat", 0)))], ["CONTRABAND", str(int(p.get("contraband", 0)))],
		["WINS", str(wins)], ["LOSSES", str(losses)],
		["WIN RATE", "%.1f%%" % (100.0 * wins / (wins + losses)) if wins + losses > 0 else "—"],
		["COLLECTION", "%.1f%%" % float(p.get("collection_pct", 0) if p.get("collection_pct") != null else 0)],
	]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(900, 250)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	add_child(grid)
	for s in stats:
		var cell := UI.panel(UI.BLUE)
		cell.custom_minimum_size = Vector2(280, 200)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(v)
		var cap := UI.label(s[0], 20, UI.MUTED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cap)
		var val := UI.label(s[1], 52, UI.GOLD, true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(val)
		grid.add_child(cell)


func _set_icon(key: String) -> void:
	var r := await Api.request("PATCH", "/api/profile/me", {"avatarUrl": key})
	if r.ok:
		Game.player.avatar_url = key
		Game.go("profile")
	else:
		UI.toast(self, r.error, UI.RED)
