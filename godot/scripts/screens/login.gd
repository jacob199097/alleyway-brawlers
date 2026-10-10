extends Screen
## Sign in / register against the server, or play offline against the CPU.

var _register := false
var _email: LineEdit
var _password: LineEdit
var _username: LineEdit
var _error: Label
var _submit: Button
var _toggle: Button
var _busy := false


func _ready() -> void:
	UI.background(self, "menu_background.png", 0.35)
	Game.play_menu_music()
	var logo := UI.texture_rect(UI.tex("title_alleyway.png"), Vector2(840, 458))
	logo.position = Vector2(60, 300)
	add_child(logo)

	var p := UI.panel(UI.BLUE, Color(0.04, 0.04, 0.1, 0.9))
	p.position = Vector2(1080, 150)
	p.custom_minimum_size = Vector2(700, 780)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	var h := UI.label("WELCOME BACK", 44, UI.GOLD, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	_email = _field("Email")
	_email.text = Game.last_email
	col.add_child(_email)
	var pw_row := HBoxContainer.new()
	_password = _field("Password")
	_password.secret = true
	_password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pw_row.add_child(_password)
	pw_row.add_child(UI.button("👁", func(): _password.secret = not _password.secret, Vector2(64, 60)))
	col.add_child(pw_row)
	_username = _field("Username")
	_username.visible = false
	col.add_child(_username)
	_error = UI.label("", 20, UI.RED)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size = Vector2(640, 30)
	col.add_child(_error)
	_submit = UI.button("LOGIN", _do_submit, Vector2(640, 66), UI.RED)
	col.add_child(_submit)
	_toggle = UI.button("No account?  REGISTER", _toggle_mode, Vector2(640, 52))
	col.add_child(_toggle)
	col.add_child(UI.button("Forgot password?", _forgot, Vector2(640, 48)))
	var sep := HSeparator.new()
	col.add_child(sep)
	col.add_child(UI.button("PLAY OFFLINE  (VS CPU)", func():
		Game.play_offline()
		Game.go("main_menu"), Vector2(640, 60), UI.PURPLE))
	var server := UI.label("Server: %s" % Api.base_url(), 18, UI.MUTED)
	server.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(server)
	col.add_child(UI.button("SETTINGS", func(): SettingsPanel.open(self, false), Vector2(640, 48)))

	for e in [_email, _password, _username]:
		e.text_submitted.connect(func(_t): _do_submit())
	(_password if _email.text != "" else _email).grab_focus()


func _field(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(640, 60)
	return e


func _toggle_mode() -> void:
	_register = not _register
	_username.visible = _register
	_submit.text = "REGISTER" if _register else "LOGIN"
	_toggle.text = "Have an account?  LOGIN" if _register else "No account?  REGISTER"
	_error.text = ""


func _do_submit() -> void:
	if _busy:
		return
	var email := _email.text.strip_edges()
	var password := _password.text
	if email == "" or password == "":
		_error.text = "Email and password required."
		return
	_busy = true
	_error.text = ""
	_submit.text = "…"
	var body := {"email": email, "password": password}
	if _register:
		body.username = _username.text.strip_edges()
	var r := await Api.request("POST", "/api/auth/register" if _register else "/api/auth/login", body)
	_busy = false
	_submit.text = "REGISTER" if _register else "LOGIN"
	if not r.ok:
		_error.text = r.error
		if r.data is Dictionary and r.data.get("code") == "email_unverified":
			UI.dialog(self, "ACTIVATE YOUR ACCOUNT",
				"Click the link in the email we sent to %s. Can't find it? Check your spam or junk folder, or get a new one." % email,
				[["SEND AGAIN", _resend.bind(email), UI.GREEN], ["CLOSE", func(): pass]], UI.BLUE)
		return
	if _register:
		Game.last_email = email
		_toggle_mode()
		_password.text = ""
		UI.dialog(self, "EMAIL VERIFICATION SENT",
			"Check your inbox to confirm your account (if it isn't there, look in spam or junk). You can log in once your email is verified.",
			[["CLOSE", func(): pass], ["SEND AGAIN", _resend.bind(email)]], UI.BLUE)
		return
	Game.sign_in(str(r.data.token), r.data.player, email)
	Game.go("main_menu" if r.data.player.get("chosen_clan") else "clan_select")


## A new activation link (backend/routes/auth.js, resend-verification).
func _resend(email: String) -> void:
	var r := await Api.request("POST", "/api/auth/resend-verification", {"email": email})
	if r.ok:
		UI.toast(self, "New activation email sent. Check spam too.", UI.GREEN)
	else:
		_error.text = r.error


func _forgot() -> void:
	var email := _email.text.strip_edges()
	if email == "":
		_error.text = "Enter your email first."
		return
	var r := await Api.request("POST", "/api/auth/forgot-password", {"email": email})
	if r.ok:
		UI.dialog(self, "CHECK YOUR EMAIL", "If that account exists, a password reset link is on its way.",
			[["OK", func(): pass]], UI.BLUE)
	else:
		_error.text = r.error
