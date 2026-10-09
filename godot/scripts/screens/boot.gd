extends Screen
## First screen: resume a saved session, otherwise go to login.


func _ready() -> void:
	UI.background(self, "menu_background.png", 0.4)
	var logo := UI.texture_rect(UI.tex("title_alleyway.png"), Vector2(1000, 545))
	logo.position = Vector2(460, 180)
	add_child(logo)
	UI.spinner(self, Vector2(960, 820), "CONNECTING…")
	Game.play_menu_music()
	await get_tree().process_frame
	if "--autoplay" in OS.get_cmdline_user_args():
		Game.play_offline()
		Game.duel_setup = {}
		Game.go("duel")
		return
	if Api.token == "":
		Game.go("login")
		return
	if await Game.refresh_player():
		Game.go("main_menu" if Game.player.get("chosen_clan") else "clan_select")
	else:
		Game.go("login")
