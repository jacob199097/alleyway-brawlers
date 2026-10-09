extends Node2D
## Duel screen, desktop layout (1920×1080) in the style of PC card games like Link Evolution:
## card detail on the left, opponent plate top-right, player plate bottom-left, a flat hand
## along the bottom, and deck / gutter / hideout piles with counts beside the board.
##
## The rules live in DuelState. This script only shows them: every rules change arrives as an
## event, and _play() animates each one in turn, so draws, summons, attacks and effects each
## get their own readable, punchy moment.
##
## Controls: click a hand card for options (or drag it onto a slot), click a ready character in
## the Brawl phase then a target, Space/Enter = next phase, right-click/Esc = cancel,
## Esc = menu, F11 = fullscreen.

const CARD := CardView.SIZE
const HAND_SCALE := 1.2
const HOVER_SCALE := 1.55
const OPP_HAND_SCALE := 0.66
const COLS := [780.0, 930.0, 1080.0, 1230.0, 1380.0]
const ROWS := {"player": [536.0, 728.0], "opponent": [312.0, 120.0]}   # [front, back]
const DIVIDER_Y := 424.0
const LEFT_X := 610.0
const RIGHT_X := 1550.0
const HAND_Y := 992.0
const HAND_LIFT_Y := 872.0
const HAND_CX := 1080.0
const HAND_SPAN := 900.0
const OPP_HAND_Y := -22.0

const BLUE := Color("4cc9f0")
const RED := Color("e63946")
const GOLD := Color("f4d35e")
const GREEN := Color("3ddc84")
const INK := Color(0.03, 0.03, 0.08, 0.92)
const ONLINE_TURN_SECS := 90.0   # matches TURN_SECS in backend/socket/onlineMatch.js

const TYPE_NAMES := {"gang_member": "GANG MEMBER", "hustle": "HUSTLE", "ambush": "AMBUSH", "leader": "LEADER"}
const PHASE_NAMES := {"deployment": "DEPLOYMENT", "brawl": "BRAWL", "regroup": "REGROUP"}

var ai_sides := ["opponent"]

@onready var cards_layer: Node2D = $Cards
@onready var fx: Node2D = $FX
@onready var camera: Camera2D = $Camera
@onready var ui: Control = $HUD/UI
@onready var overlay: Control = $HUD/UI/Overlay

var duel: DuelState
var hand := {"player": [], "opponent": []}     # CardViews, in hand order
var field := {"player": {}, "opponent": {}}    # slot -> CardView
var leaders := {}                              # side -> CardView
var counts := {}                               # pile sizes from the last event

var _queue: Array = []
var _playing := false
var _shake := 0.0
var _hovered: CardView = null
var _detail_key := ""
var _mode := "idle"   # idle | menu | place | target | discard | over
var _selected: CardView = null
var _selected_slot := -1
var _place_kind := ""
var _valid := {}      # "side:slot" -> highlight colour
var _press: CardView = null
var _press_pos := Vector2.ZERO
var _dragging := false
var _menu: Control = null
var _direct_btn: Button = null
var _attack_line: Line2D = null
var _dim_rect: ColorRect = null
var _match_id := ""
var _cards_played := 0
var _damage_log := {}     # "side:uid" -> {card, owner, damage}
var _last_hit := {}
var _online := false      # a server-run match (Game.duel_setup.online)
var _awaiting := false    # sent a move, waiting for the server's answer
var _over := {}           # mp:over from the server
var _clock_left := 0.0

var _font: SystemFont
var _dot: Texture2D
var _ring_tex: Texture2D
var _column_tex: Texture2D
var _add_mat: CanvasItemMaterial
var _slot_box: StyleBoxFlat
var _slot_box_back: StyleBoxFlat
var _pile_box: StyleBoxFlat
var _ui := {}
var _panels := {}


func _ready() -> void:
	randomize()
	if "--autoplay" in OS.get_cmdline_user_args():
		ai_sides = ["player", "opponent"]
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	_make_resources()
	ui.theme = _make_theme()
	if ResourceLoader.exists("res://assets/duel_background.png"):
		$BackLayer/Background.texture = load("res://assets/duel_background.png")
	_build_detail()
	var me := Game.player
	_build_panel("player", $HUD/UI/PlayerPanel, str(me.get("username", "YOU")).to_upper().left(14),
		str(me.get("avatar_url", "profile_001")),
		"LV %d  ·  %s" % [int(me.get("level", 1)), UI.player_title(int(me.get("level", 1))).to_upper()])
	var online_start: Dictionary = Game.duel_setup.get("start", {}) if Game.duel_setup.get("online", false) else {}
	if online_start.is_empty():
		_build_panel("opponent", $HUD/UI/OppPanel, "CPU", "profile_002", "CPU OPPONENT")
	else:
		var opp: Dictionary = online_start.get("opponent", {})
		_build_panel("opponent", $HUD/UI/OppPanel, str(opp.get("username", "RIVAL")).to_upper().left(12),
			str(opp.get("avatar_url", "profile_002")) if opp.get("avatar_url") else "profile_002",
			"LV %d  ·  ONLINE" % int(opp.get("level", 1)))
	_build_phase_bar()
	_build_turn_box()
	_play_music()

	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0, 0, 0, 0)
	_dim_rect.position = Vector2(-100, -100)
	_dim_rect.size = Vector2(2120, 1280)
	_dim_rect.z_index = 410
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_layer.add_child(_dim_rect)

	if not online_start.is_empty():
		_setup_online(online_start)
		return

	# The player's saved deck from Fight Mode (Game.duel_setup); the CPU uses the starter deck.
	var setup := DuelAI.test_setup()
	var chosen: Dictionary = Game.duel_setup
	if chosen.has("deck"):
		setup.decks.player = chosen.deck
		setup.hideouts.player = chosen.get("hideout", [])
		setup.leaders.player = chosen.get("leader", "")
	duel = DuelState.new(setup.decks, setup.hideouts, setup.leaders, str(chosen.get("first", "player")))
	_start_match_session(chosen.get("ranked", false))
	_make_leader_views()
	counts = duel._counts()
	_refresh_hud()
	duel.start()
	_queue.append_array(duel.take_events())
	_pump()


func _make_leader_views() -> void:
	for side in ["player", "opponent"]:
		var l = duel.sides[side].leader
		if l != null and duel.sides[side].get("leader_state", "dormant") == "dormant":
			var v := _new_view(l, side, true)
			v.position = pile_pos(side, "leader")
			v.home = v.position
			v.badge_text = _influence_text(int(l.get("influence", l.get("base_defense", 0))))
			v.show_badge = true
			leaders[side] = v


# ── Online matches ───────────────────────────────────────────────────────────
# The server runs the rules (backend/socket/onlineMatch.js). This screen mirrors the board it
# sends (duel.load_view), animates its events, and sends the player's moves as actions.

func _setup_online(start: Dictionary) -> void:
	_online = true
	ai_sides = []
	_match_id = str(start.get("matchId", ""))
	duel = DuelState.new({"player": [], "opponent": []}, {}, {}, "player", -1)
	duel.load_view(start.get("view", {}))
	_make_leader_views()
	counts = duel._counts()
	if start.get("resync", false):
		_build_from_view()
	_refresh_hud()
	_ui.clock = _label(22, GOLD, true)
	_ui.clock.position = Vector2(150, 96)
	$HUD/UI/TurnBox.add_child(_ui.clock)
	Net.opened.connect(_on_net_opened)
	Net.closed.connect(_on_net_closed)
	_after_events()


## Rejoining a match (reconnect or correction): lay the board out straight from the view.
func _build_from_view() -> void:
	for side in ["player", "opponent"]:
		var s: Dictionary = duel.sides[side]
		for c in s.hand:
			var hv := _new_view(c, side, side == "player")
			hand[side].append(hv)
		_layout_hand(side)
		for v in hand[side]:
			v.position = v.home
			v.scale = Vector2.ONE * v.home_scale
		for slot in 10:
			var c = s.field[slot]
			if c == null:
				continue
			var v := _new_view(c, side, not c.get("face_down", false))
			v.position = slot_pos(side, slot)
			v.home = v.position
			v.home_rot = PI / 2 if slot < 5 and (c.get("position") == "def" or c.get("downed", false)) else 0.0
			v.rotation = v.home_rot
			v.downed = c.get("downed", false)
			v.z_index = 10
			if slot < 5:
				v.show_badge = true
				if c.has("attack"):
					v.set_stats(int(c.attack), int(c.defense), int(c.get("base_attack", c.attack)), int(c.get("base_defense", c.defense)))
			field[side][slot] = v
		var p: Dictionary = _panels[side]
		p.shown = float(s.morale)
		p.morale.text = str(int(s.morale))
		p.bar.size.x = p.bar.get_parent().size.x * clampf(float(s.morale) / DuelState.START_MORALE, 0.0, 1.0)
	_ui.turn_num.text = "TURN %d" % duel.turn
	_ui.turn_who.text = "YOUR TURN" if duel.active == "player" else "OPPONENT'S TURN"
	_set_phase_ui(duel.phase)


func _on_net_event(name: String, data) -> void:
	if not data is Dictionary or str(data.get("matchId", _match_id)) != _match_id:
		return
	match name:
		"mp:update":
			duel.load_view(data.view)
			_awaiting = false
			_clock_left = ONLINE_TURN_SECS
			_queue.append_array(data.events)
			_pump()
		"mp:over":
			_over = data
			if str(data.get("reason", "")) != "morale" and _mode != "over":
				_mode = "over"
				_cancel_interaction()
				var won: bool = data.get("result") == "win"
				var why: String = {"concede": "CONCEDED", "disconnect": "DISCONNECTED"}.get(str(data.reason), "LEFT")
				_sweep_banner(("OPPONENT " if won else "YOU ") + why, GOLD if won else RED)
				await _wait(1.6)
				_finish_match(won)
		"mp:opponent":
			if data.get("status") == "disconnected":
				_show_net_banner("OPPONENT DISCONNECTED — THEY HAVE %ds TO RETURN" % int(data.get("graceSecs", 45)))
			else:
				_hide_net_banner()
				UI.toast(overlay, "Your opponent is back.", BLUE)


## Net calls this when the server (re)sends the whole match, e.g. after a reconnect.
func on_online_start(_data: Dictionary) -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func on_online_error(message: String) -> void:
	_awaiting = false
	UI.toast(overlay, message, RED)


func _on_net_opened() -> void:
	_hide_net_banner()
	Net.send("mp:resync")


func _on_net_closed() -> void:
	if _mode != "over":
		_show_net_banner("CONNECTION LOST — RECONNECTING…")


func _show_net_banner(text: String) -> void:
	if not _ui.has("net"):
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color(0.25, 0.02, 0.05, 0.92), RED, 2, 10))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label(24, Color.WHITE, true)
		p.add_child(l)
		overlay.add_child(p)
		_ui.net = p
	_ui.net.get_child(0).text = text
	_ui.net.visible = true
	_ui.net.reset_size()
	_ui.net.position = Vector2(1080 - _ui.net.size.x / 2, 236)


func _hide_net_banner() -> void:
	if _ui.has("net"):
		_ui.net.visible = false


func _process(delta: float) -> void:
	if _shake > 0.3:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0))
	else:
		camera.offset = Vector2.ZERO
	if not _valid.is_empty():
		queue_redraw()
	if _dragging and _press:
		_press.position = _press.position.lerp(get_global_mouse_position(), minf(1.0, delta * 25.0))
	if _online:
		while not Net.inbox.is_empty():
			var msg: Array = Net.inbox.pop_front()
			_on_net_event(msg[0], msg[1])
		# Whoever has to act has ONLINE_TURN_SECS before the server plays a safe move for them
		if duel.winner == "" and _mode != "over" and _ui.has("clock"):
			_clock_left = maxf(0.0, _clock_left - delta)
			_ui.clock.text = "⏱ %d" % ceili(_clock_left)
			_ui.clock.label_settings.font_color = RED if _clock_left < 15.0 else GOLD


# ── Board geometry ───────────────────────────────────────────────────────────

func slot_pos(side: String, slot: int) -> Vector2:
	var col := slot % 5
	if side == "opponent":
		col = 4 - col   # mirrored, like sitting across the table
	return Vector2(COLS[col], ROWS[side][0 if slot < 5 else 1])


func pile_pos(side: String, pile: String) -> Vector2:
	var near := LEFT_X if side == "player" else RIGHT_X   # leader + hideout
	var far := RIGHT_X if side == "player" else LEFT_X    # gutter + deck
	match pile:
		"leader":
			return Vector2(near, ROWS[side][0])
		"hideout":
			return Vector2(near, ROWS[side][1])
		"gutter":
			return Vector2(far, ROWS[side][0])
	return Vector2(far, ROWS[side][1])


func _target_pos(side: String, slot: int) -> Vector2:
	if slot == DuelState.LEADER:
		return pile_pos(side, "leader")
	return slot_pos(side, slot) if slot >= 0 else Vector2(1080, ROWS[side][0])


func _slot_at(side: String, p: Vector2) -> int:
	for slot in 10:
		if Rect2(slot_pos(side, slot) - CARD / 2, CARD).grow(10).has_point(p):
			return slot
	return -1


func _draw() -> void:
	draw_line(Vector2(560, DIVIDER_Y), Vector2(1600, DIVIDER_Y), Color(1, 1, 1, 0.14), 2.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	for side in ["player", "opponent"]:
		for slot in 10:
			var r := Rect2(slot_pos(side, slot) - CARD / 2, CARD)
			draw_style_box(_slot_box if slot < 5 else _slot_box_back, r)
			var key := "%s:%d" % [side, slot]
			if _valid.has(key):
				var c: Color = _valid[key]
				draw_rect(r, Color(c, 0.2 * pulse))
				draw_rect(r.grow(4), Color(c, 0.95 * pulse), false, 4.0)
		for pile in ["deck", "gutter", "hideout"]:
			_draw_pile(side, pile)
		_draw_zone_label(pile_pos(side, "leader"), "LEADER")


func _draw_pile(side: String, pile: String) -> void:
	var p := pile_pos(side, pile)
	draw_style_box(_pile_box, Rect2(p - CARD / 2, CARD))
	var c: Dictionary = counts.get(side, {})
	var n: int = c.get(pile, 0)
	if n <= 0:
		_draw_zone_label(p, pile.to_upper())
		return
	var layers := mini(4, ceili(n / 8.0))
	var back := CardDB.back()
	for i in layers:
		var off := Vector2(-i * 2.0, -i * 3.0)
		var r := Rect2(p - CARD / 2 + off, CARD)
		var tex := back
		if i == layers - 1 and pile == "gutter":
			tex = CardDB.art(str(c.get("gutter_top", "")))
		if tex:
			draw_texture_rect(tex, r, false, Color(1, 1, 1) if i == layers - 1 else Color(0.55, 0.55, 0.6))
		else:
			draw_rect(r, Color("1d2140"))
			draw_rect(r, Color(1, 1, 1, 0.3), false, 2.0)
	var at := Vector2(p.x - 60, p.y + 16)
	draw_string_outline(_font, at, str(n), HORIZONTAL_ALIGNMENT_CENTER, 120, 46, 10, Color(0, 0, 0, 0.9))
	draw_string(_font, at, str(n), HORIZONTAL_ALIGNMENT_CENTER, 120, 46, Color.WHITE)
	_draw_zone_label(p, pile.to_upper())


## Zone name on a dark strip along the bottom of the zone (stays readable over pile art).
func _draw_zone_label(p: Vector2, text: String) -> void:
	var strip := Rect2(p.x - CARD.x / 2, p.y + CARD.y / 2 - 24, CARD.x, 24)
	draw_rect(strip, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(strip.position.x, strip.position.y + 18), text, HORIZONTAL_ALIGNMENT_CENTER,
		CARD.x, 16, Color(1, 1, 1, 0.7))


# ── Event playback ───────────────────────────────────────────────────────────

func _act(side: String, action: Dictionary) -> bool:
	if _online:
		# The server applies the move and sends back what happened (mp:update)
		if _awaiting or side != "player" or not Net.send("mp:action", {"matchId": _match_id, "action": action}):
			return false
		_awaiting = true
		_clear_highlights()
		_update_next_btn()
		return true
	if not duel.do_action(side, action):
		return false
	_queue.append_array(duel.take_events())
	_pump()
	return true


func _pump() -> void:
	if _playing:
		return
	_playing = true
	_clear_highlights()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await _play(ev)
		counts = ev.counts
		_refresh_hud()
	_playing = false
	_after_events()


func _after_events() -> void:
	if duel.winner != "":
		return
	var side: String = duel.pending.side if not duel.pending.is_empty() else duel.active
	if _online:
		if side == "player" and not _awaiting and "--autoplay" in OS.get_cmdline_user_args():
			# Test bot (tests/online_bot.tscn): the CPU plays this side's moves through the server
			await _wait(0.25)
			if not _playing and not _awaiting:
				var a := DuelAI.choose(duel, "player")
				if not a.is_empty():
					_act("player", a)
		elif side == "player" and not _awaiting:
			_player_ready()
		else:
			_clear_highlights()
			_update_next_btn()
		return
	if side in ai_sides:
		_update_next_btn()
		await _wait(0.4)
		if _playing:
			return
		var a := DuelAI.choose(duel, side)
		if a.is_empty() or not _act(side, a):
			if not _act(side, {"kind": "next"}):
				push_warning("CPU has no legal action: %s" % a)
	else:
		_player_ready()


## Solo matches run here, so the server issues a session that the post-match screen
## completes to get rewards (the server decides what a session can pay out).
func _start_match_session(ranked: bool) -> void:
	if Game.offline or Game.player.is_empty() or "player" in ai_sides:
		return
	var r := await Api.request("POST", "/api/match/start", {"ranked": ranked})
	if r.ok and r.data is Dictionary:
		_match_id = str(r.data.get("matchId", ""))


## Bookkeeping for the post-match screen: cards the player played and morale dealt per card.
func _track(ev: Dictionary) -> void:
	match ev.type:
		"summon", "set", "hustle":
			if ev.side == "player":
				_cards_played += 1
		"clash":
			var v: CardView = field[ev.side].get(ev.from)
			_last_hit = {"side": ev.side, "card": v.card if v else {}}
		"damage":
			if not _last_hit.is_empty() and _last_hit.side != ev.side and not _last_hit.card.is_empty():
				var key := "%s:%s" % [_last_hit.side, _last_hit.card.get("uid", 0)]
				var entry: Dictionary = _damage_log.get(key, {"card": _last_hit.card, "owner": _last_hit.side, "damage": 0})
				entry.damage += int(ev.amount)
				_damage_log[key] = entry
		"attack", "turn":
			_last_hit = {}


func _play(ev: Dictionary) -> void:
	_track(ev)
	match ev.type:
		"draw":
			await _ev_draw(ev)
		"turn":
			await _ev_turn(ev)
		"phase":
			await _ev_phase(ev)
		"authority":
			_ev_authority(ev)
		"summon":
			await _ev_summon(ev)
		"set":
			await _ev_set(ev)
		"hustle":
			await _ev_hustle(ev)
		"attack":
			await _ev_attack(ev)
		"flip":
			await _ev_flip(ev)
		"ambush":
			await _ev_ambush(ev)
		"clash":
			await _ev_clash(ev)
		"blocked":
			await _ev_blocked(ev)
		"downed":
			await _ev_downed(ev)
		"ko":
			await _ev_ko(ev)
		"damage":
			await _ev_damage(ev)
		"promote":
			await _ev_promote(ev)
		"effect":
			await _ev_effect(ev)
		"stand":
			await _ev_stand(ev)
		"discard":
			await _ev_discard(ev)
		"stats":
			_ev_stats(ev)
		"notice":
			await _notice(ev.text)
		"game_over":
			await _ev_game_over(ev)
		"move":
			await _ev_move(ev)
		"retarget":
			_ev_retarget(ev)
		"position":
			await _ev_position(ev)
		"awaken":
			await _ev_awaken(ev)
		"leader_hit":
			await _ev_leader_hit(ev)
		"leader_down":
			await _ev_leader_down(ev)
		"prompt":
			if ev.side == "opponent" or ev.side in ai_sides:
				_float_text(Vector2(1080, DIVIDER_Y), "OPPONENT IS DECIDING…" if _online else "CPU IS DECIDING…", Color(1, 1, 1, 0.8), 30)
				await _wait(0.35)


func _ev_draw(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _new_view(ev.card, side, false)
	v.position = pile_pos(side, "deck")
	v.busy = true
	v.z_index = 400
	hand[side].append(v)
	_layout_hand(side)
	Sfx.play("draw", randf_range(0.92, 1.12))
	var start := v.position
	var end_scale: float = HAND_SCALE if side == "player" else OPP_HAND_SCALE
	var t := create_tween()
	t.tween_method(func(k: float):
		v.position = start.lerp(v.home, k) + Vector2(0, -110.0 * sin(PI * k))
		v.scale = Vector2.ONE * lerpf(1.0, end_scale, k)
	, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if side == "player":
		get_tree().create_timer(0.12).timeout.connect(func():
			if is_instance_valid(v):
				v.flip(true))
	t.finished.connect(func():
		v.busy = false
		_layout_hand(side))
	if ev.opening:
		await _wait(0.09)
	else:
		await t.finished


func _ev_turn(ev: Dictionary) -> void:
	var mine: bool = ev.side == "player"
	_cancel_interaction()
	_ui.turn_num.text = "TURN %d" % ev.turn
	_ui.turn_who.text = "YOUR TURN" if mine else "OPPONENT'S TURN"
	_ui.turn_who.label_settings.font_color = BLUE if mine else RED
	Sfx.play("turn", 1.0 if mine else 0.84)
	await _sweep_banner("YOUR TURN" if mine else "OPPONENT'S TURN", BLUE if mine else RED)


func _ev_phase(ev: Dictionary) -> void:
	_set_phase_ui(ev.phase)
	if not PHASE_NAMES.has(ev.phase):
		return
	Sfx.play("phase")
	await _phase_flash("%s PHASE" % PHASE_NAMES[ev.phase], BLUE if ev.side == "player" else RED)


func _ev_authority(ev: Dictionary) -> void:
	var p: Dictionary = _panels[ev.side]
	p.auth.text = "AUTHORITY   %d / %d" % [ev.value, ev.max]
	var delta: int = ev.delta
	var at: Vector2 = p.auth.global_position + Vector2(200, 0)
	_float_text(at, ("+%d" % delta) if delta > 0 else str(delta), BLUE if delta > 0 else GOLD, 30)
	var t := create_tween()
	t.tween_property(p.auth, "scale", Vector2.ONE * 1.15, 0.08)
	t.tween_property(p.auth, "scale", Vector2.ONE, 0.18)


func _ev_summon(ev: Dictionary) -> void:
	var side: String = ev.side
	var c: Dictionary = ev.card
	var slot: int = ev.slot
	var v := _take_from_hand(side, c.uid, c)
	var target := slot_pos(side, slot)
	field[side][slot] = v
	v.busy = true
	v.z_index = 420
	v.home = target
	v.home_scale = 1.0
	v.home_rot = PI / 2 if c.position == "def" else 0.0
	if c.face_down:
		# A quiet set: slide in face-down and turn sideways
		if v.face_up:
			v.flip(false)
		Sfx.play("set")
		await v.move_to(target, 1.0, v.home_rot, 0.3).finished
		_ring(target, Color(0.6, 0.7, 1.0), 0.7)
	else:
		var heavy: bool = c.authority >= 6
		_show_detail(c)
		if heavy:
			_dim(0.55, 0.2)
			_splash_name(c.name, BLUE if side == "player" else RED)
		if not v.face_up:
			v.flip(true)
		var rise := Vector2(0, -70 if side == "player" else 70)
		await v.move_to(target + rise, 1.75, 0.0, 0.4 if heavy else 0.24).finished
		await _wait(0.24 if heavy else 0.05)
		await v.move_to(target, 1.0, 0.0, 0.11, Tween.TRANS_QUAD, Tween.EASE_IN).finished
		await _impact(target, heavy)
		if heavy:
			_dim(0.0, 0.35)
	v.busy = false
	v.z_index = 10
	v.show_badge = true


func _ev_set(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _take_from_hand(side, ev.card.uid, ev.card)
	var target := slot_pos(side, ev.slot)
	field[side][ev.slot] = v
	v.home = target
	v.home_scale = 1.0
	v.home_rot = 0.0
	v.z_index = 420
	if v.face_up:
		v.flip(false)
	Sfx.play("set")
	await v.move_to(target, 1.0, 0.0, 0.3).finished
	_ring(target, Color(0.75, 0.5, 1.0), 0.6)
	v.z_index = 10


func _ev_hustle(ev: Dictionary) -> void:
	var side: String = ev.side
	var c: Dictionary = ev.card
	var v := _take_from_hand(side, c.uid, c)
	v.z_index = 450
	_show_detail(c)
	if not v.face_up:
		v.flip(true)
	var center := Vector2(1080, DIVIDER_Y)
	Sfx.play("effect", 0.8)
	await v.move_to(center, 2.1, 0.0, 0.3, Tween.TRANS_BACK).finished
	_ring(center, BLUE, 1.5)
	_burst(center, BLUE, 32, 420, 0.8, -250.0)
	_float_text(center + Vector2(0, 215), "HUSTLE", BLUE, 40)
	await _wait(0.75)
	await _to_gutter(v, side)


func _ev_attack(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.from)
	if v == null:
		return
	var tpos := _target_pos(DuelState.other(side), ev.target)
	_clear_attack_line()
	var line := Line2D.new()
	line.points = PackedVector2Array([v.home, tpos])
	line.width = 0.0
	line.default_color = Color(RED, 0.85)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.material = _add_mat
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(26, 0), Vector2(-14, -18), Vector2(-14, 18)])
	head.color = RED
	head.position = tpos
	head.rotation = (tpos - v.home).angle()
	line.add_child(head)
	fx.add_child(line)
	_attack_line = line
	create_tween().tween_property(line, "width", 10.0, 0.15)
	Sfx.play("whoosh", 0.7)
	v.z_index = 430
	v.move_to(v.home, 1.15, v.home_rot, 0.16)
	_float_text(v.home + Vector2(0, 110 if side == "player" else -110), "BRAWL!", GOLD, 34)
	await _wait(0.35)


func _ev_flip(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	v.set_card(ev.card)
	await v.flip(true)
	await _wait(0.15)


func _ev_ambush(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.slot)
	field[side].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, side, false)
		v.position = slot_pos(side, ev.slot)
	v.set_card(ev.card)
	v.z_index = 460
	_show_detail(ev.card)
	Sfx.play("ambush")
	_screen_flash(RED, 0.3)
	shake(10)
	var center := v.position.lerp(Vector2(1080, DIVIDER_Y), 0.65)
	v.flip(true)
	await v.move_to(center, 1.9, 0.0, 0.25, Tween.TRANS_BACK).finished
	_ring(center, RED, 1.7)
	_burst(center, RED, 36, 520)
	_float_text(center + Vector2(0, -200), "AMBUSH!", RED, 64)
	await _wait(0.8)
	await _to_gutter(v, side)


func _ev_clash(ev: Dictionary) -> void:
	var side: String = ev.side
	var foe := DuelState.other(side)
	var a: CardView = field[side].get(ev.from)
	if a == null:
		_clear_attack_line()
		return
	var direct: bool = ev.target == DuelState.DIRECT
	var d: CardView = null
	if ev.target == DuelState.LEADER:
		d = leaders.get(foe)
	elif ev.target >= 0:
		d = field[foe].get(ev.target)
	var tpos := _target_pos(foe, ev.target)
	_float_text(a.home, str(ev.att), GOLD, 54)
	if d:
		_float_text(d.home, "%s %d" % [ev.vs, ev.def], RED if ev.vs == "ATK" else BLUE, 44)
	elif direct:
		_float_text(tpos + Vector2(0, -60 if foe == "opponent" else 60), "DIRECT ATTACK", RED, 44)
	await _wait(0.42)
	a.stop_moving()
	var dir := (tpos - a.home).normalized()
	Sfx.play("whoosh")
	var t := create_tween()
	t.tween_property(a, "position", a.home - dir * 36, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home.lerp(tpos, 0.8), 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await t.finished
	Sfx.play("hit", 0.85 if direct else 1.0)
	shake(22.0 if direct else 13.0)
	_burst(tpos, Color(1, 0.85, 0.45), 30, 560)
	_ring(tpos, Color.WHITE, 1.3)
	if d:
		d.flash()
	await _hit_stop(0.08)
	_clear_attack_line()
	a.go_home(0.25)
	await _wait(0.2)
	a.z_index = 10


func _ev_blocked(ev: Dictionary) -> void:
	Sfx.play("set", 0.7)
	_float_text(slot_pos(ev.side, ev.slot), "BLOCKED", BLUE, 40)
	await _wait(0.45)


func _ev_downed(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	v.downed = true
	v.home_rot = PI / 2
	Sfx.play("down")
	shake(6)
	_stamp(v.home, "DOWNED", RED)
	await v.move_to(v.home, 1.0, PI / 2, 0.3, Tween.TRANS_BACK).finished
	v.z_index = 10
	await _wait(0.2)


func _ev_ko(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.slot)
	field[side].erase(ev.slot)
	if v == null:
		return
	v.show_badge = false
	v.z_index = 440
	v.flash()
	Sfx.play("ko")
	shake(15)
	_burst(v.position, Color(1.0, 0.45, 0.15), 44, 650, 0.8)
	_burst(v.position, Color.WHITE, 18, 350, 0.5)
	_stamp(v.position, "K.O.", Color(1, 0.35, 0.2))
	await _hit_stop(0.06)
	var t := create_tween()
	t.tween_property(v, "rotation", v.rotation + randf_range(-0.6, 0.6), 0.16)
	await t.finished
	await _to_gutter(v, side)


func _ev_damage(ev: Dictionary) -> void:
	var side: String = ev.side
	var amount: int = ev.amount
	var p: Dictionary = _panels[side]
	Sfx.play("damage")
	shake(clampf(amount / 60.0, 8.0, 28.0))
	_set_morale(side, ev.morale)
	var root: Control = p.root
	_float_text(root.position + root.size / 2 + Vector2(0, 40 if side == "opponent" else -40),
		"-%d" % amount, RED, 72)
	if side == "player":
		_screen_flash(RED, 0.22)
	await _wait(0.6)


func _ev_promote(ev: Dictionary) -> void:
	var side: String = ev.side
	var slot: int = ev.slot
	var c: Dictionary = ev.card
	var pos := slot_pos(side, slot)
	var v: CardView = field[side].get(slot)
	if v == null:
		v = _new_view(ev.from, side, true)
		v.position = pos
		field[side][slot] = v
	v.z_index = 440
	v.show_badge = false
	v.busy = true
	Sfx.play("promote")
	_light_column(pos)
	_burst(pos + Vector2(0, 60), GOLD, 40, 300, 1.1, -500.0)
	await v.move_to(pos + Vector2(0, -30 if side == "player" else 30), 1.4, 0.0, 0.3, Tween.TRANS_BACK).finished
	v.downed = false
	await v.swap_to(c, 0.36)
	_ring(pos, GOLD, 1.8)
	shake(10)
	_show_detail(c)
	_float_text(pos + Vector2(0, -175 if side == "player" else 175), "PROMOTED!", GOLD, 58)
	v.home = pos
	v.home_rot = PI / 2 if c.position == "def" else 0.0
	v.home_scale = 1.0
	await _wait(0.5)
	await v.move_to(pos, 1.0, v.home_rot, 0.16, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	await _impact(pos, false)
	v.busy = false
	v.z_index = 10
	v.show_badge = true


func _ev_effect(ev: Dictionary) -> void:
	var side: String = ev.side
	Sfx.play("effect")
	if ev.slot >= 0:
		var v: CardView = field[side].get(ev.slot)
		if v:
			_pulse_glow(v, GOLD)
	_callout(ev.card, ev.text, side)
	await _wait(0.9)


func _ev_stand(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	v.downed = false
	v.home_rot = PI / 2 if ev.card.position == "def" else 0.0
	_burst(v.home, GOLD, 24, 260, 0.8, -300.0)
	Sfx.play("promote", 1.3, -6.0)
	await v.move_to(v.home, 1.0, v.home_rot, 0.3, Tween.TRANS_BACK).finished


func _ev_discard(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _take_from_hand(side, ev.card.uid, ev.card)
	v.z_index = 440
	if not v.face_up:
		v.flip(true)
	await v.move_to(v.position + Vector2(0, -90 if side == "player" else 90), 1.3, 0.0, 0.2).finished
	await _to_gutter(v, side)


func _ev_stats(ev: Dictionary) -> void:
	for side in ev.values:
		var vals: Dictionary = ev.values[side]
		for slot in vals:
			var v: CardView = field[side].get(slot)
			if v:
				var s: Array = vals[slot]
				v.set_stats(s[0], s[1], s[2], s[3])


func _ev_move(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.from)
	if v == null:
		return
	field[side].erase(ev.from)
	field[side][ev.to] = v
	var to := slot_pos(side, ev.to)
	v.home = to
	Sfx.play("whoosh", 1.3)
	if _attack_line and is_instance_valid(_attack_line):
		_attack_line.set_point_position(0, to)
	_burst(v.position, BLUE, 12, 220, 0.4, 0.0)
	await v.move_to(to, v.scale.x, v.home_rot, 0.22, Tween.TRANS_BACK).finished
	_float_text(to + Vector2(0, -110 if side == "player" else 110), "LANE SHIFT", BLUE, 30)


func _ev_retarget(ev: Dictionary) -> void:
	if _attack_line and is_instance_valid(_attack_line):
		var tpos := _target_pos(DuelState.other(ev.side), ev.target)
		_attack_line.set_point_position(1, tpos)
		var head: Polygon2D = _attack_line.get_child(0)
		head.position = tpos
		head.rotation = (tpos - _attack_line.get_point_position(0)).angle()
	var be: CardView = field[DuelState.other(ev.side)].get(ev.target)
	if be:
		_ring(be.home, BLUE, 1.4)
		be.flash()


func _ev_position(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	var c: Dictionary = ev.card
	v.set_card(c)
	v.home_rot = PI / 2 if c.position == "def" else 0.0
	if not v.face_up:
		v.flip(true)
	Sfx.play("set", 1.2)
	_float_text(v.home + Vector2(0, -110 if ev.side == "player" else 110),
		"DEF POSITION" if c.position == "def" else "ATK POSITION", BLUE if c.position == "def" else GOLD, 30)
	await v.move_to(v.home, 1.0, v.home_rot, 0.28, Tween.TRANS_BACK).finished


func _ev_awaken(ev: Dictionary) -> void:
	var side: String = ev.side
	var slot: int = ev.slot
	var c: Dictionary = ev.card
	var v: CardView = leaders.get(side)
	leaders.erase(side)
	if v == null:
		v = _new_view(c, side, true)
		v.position = pile_pos(side, "leader")
	v.badge_text = ""
	v.set_card(c)
	field[side][slot] = v
	var target := slot_pos(side, slot)
	v.home = target
	v.home_rot = 0.0
	v.home_scale = 1.0
	v.busy = true
	v.z_index = 440
	_show_detail(c)
	_dim(0.6, 0.25)
	Sfx.play("promote", 0.8)
	_light_column(v.position)
	_splash_name("%s AWAKENS" % c.name, GOLD)
	await v.move_to(v.position + Vector2(0, -40 if side == "player" else 40), 1.6, 0.0, 0.4, Tween.TRANS_BACK).finished
	await _wait(0.3)
	await v.move_to(target + Vector2(0, -60 if side == "player" else 60), 1.9, 0.0, 0.3).finished
	await v.move_to(target, 1.0, 0.0, 0.12, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	await _impact(target, true)
	_dim(0.0, 0.35)
	v.busy = false
	v.z_index = 10
	v.show_badge = true


func _ev_leader_hit(ev: Dictionary) -> void:
	var v: CardView = leaders.get(ev.side)
	if v == null:
		return
	v.badge_text = _influence_text(ev.influence)
	_float_text(v.home + Vector2(0, -40), "-%d" % ev.amount, RED, 56)
	Sfx.play("damage", 1.2)
	await _wait(0.35)


func _ev_leader_down(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = leaders.get(side)
	leaders.erase(side)
	if v == null:
		return
	v.badge_text = ""
	v.z_index = 440
	v.flash()
	Sfx.play("ko", 0.8)
	shake(20)
	_burst(v.position, Color(1.0, 0.45, 0.15), 50, 700, 0.9)
	_stamp(v.position, "LEADER DOWN", RED)
	await _hit_stop(0.1)
	await _to_gutter(v, side)


static func _influence_text(influence: int) -> String:
	return "[center][color=#ffd86b]INFLUENCE %d[/color][/center]" % influence


func _ev_game_over(ev: Dictionary) -> void:
	_mode = "over"
	_cancel_interaction()
	var won: bool = ev.winner == "player"
	await _wait(0.5)
	Sfx.play("victory" if won else "defeat")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = Vector2(1920, 1080)
	overlay.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.7, 0.4)
	var title := _label(170, GOLD if won else RED, true)
	title.text = "VICTORY" if won else "DEFEAT"
	title.size = Vector2(1920, 220)
	title.position = Vector2(0, 330)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.pivot_offset = title.size / 2
	title.scale = Vector2.ONE * 2.2
	overlay.add_child(title)
	create_tween().tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shake(18)
	if not "player" in ai_sides:
		await _wait(1.6)
		_finish_match(won)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.position = Vector2(960 - 290, 600)
	for label in ["REMATCH", "QUIT"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(260, 64)
		b.pressed.connect(_on_menu_choice.bind(label))
		row.add_child(b)
	overlay.add_child(row)


## Hand the result (and a snapshot of the board for the background) to the post-match screen.
func _finish_match(won: bool) -> void:
	var mvp := {}
	for key in _damage_log:
		if mvp.is_empty() or _damage_log[key].damage > mvp.damage:
			mvp = _damage_log[key]
	var snap: Texture2D = null
	if DisplayServer.get_name() != "headless":
		snap = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	Game.match_result = {
		"result": "win" if won else "loss",
		"player_morale": duel.sides.player.morale, "opponent_morale": duel.sides.opponent.morale,
		"turns": duel.turn, "cards_played": _cards_played, "mvp": mvp,
		"match_id": _match_id, "snapshot": snap,
	}
	if _online:
		# The server records the match and sends the rewards (mp:over)
		var waited := 0.0
		while _over.is_empty() and waited < 10.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		Game.match_result.online = true
		Game.match_result.match_id = ""
		Game.match_result.reason = str(_over.get("reason", "morale"))
		Game.match_result.rewards = _over.get("rewards")
		if _over.has("result"):
			Game.match_result.result = _over.result
	Game.go("post_match")


# ── View helpers ─────────────────────────────────────────────────────────────

func _new_view(c: Dictionary, side: String, up: bool) -> CardView:
	var v := CardView.new()
	cards_layer.add_child(v)
	v.setup(c, side, up)
	return v


func _take_from_hand(side: String, uid: int, c: Dictionary) -> CardView:
	var views: Array = hand[side]
	var v: CardView = null
	for x in views:
		if x.uid == uid:
			v = x
			break
	if v == null and not views.is_empty():
		v = views.back()
	if v == null:
		v = _new_view(c, side, false)
		v.position = pile_pos(side, "deck")
	else:
		views.erase(v)
	if v == _hovered:
		_hovered = null
	v.stop_moving()
	v.set_card(c)
	v.glow = 0.0
	_layout_hand(side)
	return v


func _layout_hand(side: String) -> void:
	var views: Array = hand[side]
	var n := views.size()
	var s: float = HAND_SCALE if side == "player" else OPP_HAND_SCALE
	var w := CARD.x * s
	var span := HAND_SPAN if side == "player" else 640.0
	var gap := 0.0
	if n > 1:
		gap = minf(w + (10.0 if side == "player" else 4.0), (span - w) / (n - 1))
	for i in n:
		var v: CardView = views[i]
		v.home = Vector2(HAND_CX - (n - 1) * gap / 2.0 + i * gap, HAND_Y if side == "player" else OPP_HAND_Y)
		v.home_scale = s
		v.home_rot = 0.0
		if v.busy or (v == _press and _dragging):
			continue
		if v == _hovered or v == _selected:
			v.z_index = 300
			v.move_to(Vector2(v.home.x, HAND_LIFT_Y), HOVER_SCALE, 0.0, 0.14)
			continue
		v.z_index = 100 + i
		v.go_home(0.22)


func _to_gutter(v: CardView, side: String) -> void:
	v.show_badge = false
	v.stop_moving()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(v, "position", pile_pos(side, "gutter"), 0.32)
	t.tween_property(v, "scale", Vector2.ONE, 0.32)
	t.tween_property(v, "rotation", 0.0, 0.32)
	t.tween_property(v, "modulate:a", 0.0, 0.2).set_delay(0.14)
	await t.finished
	if v == _hovered:
		_hovered = null
	v.queue_free()


# ── Effects (juice) ──────────────────────────────────────────────────────────

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Freeze the action for a split second on big hits.
func _hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.08
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0


func _impact(pos: Vector2, heavy: bool) -> void:
	Sfx.play("heavy" if heavy else "slam", randf_range(0.95, 1.05))
	shake(24.0 if heavy else 8.0)
	_ring(pos, GOLD if heavy else Color(0.85, 0.9, 1.0), 2.2 if heavy else 1.2)
	_burst(pos + Vector2(0, CARD.y / 2 - 10), Color(0.75, 0.7, 0.65), 26 if heavy else 14, 380.0, 0.5, 900.0)
	if heavy:
		_burst(pos, GOLD, 40, 700, 0.9)
		_screen_flash(Color.WHITE, 0.25)
		await _hit_stop(0.1)


func _burst(pos: Vector2, color: Color, amount: int, speed: float, life := 0.6, gravity := 700.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
	p.texture = _dot
	p.material = _add_mat
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func _ring(pos: Vector2, color: Color, size_to: float) -> void:
	var s := Sprite2D.new()
	s.texture = _ring_tex
	s.material = _add_mat
	s.modulate = color
	s.position = pos
	s.scale = Vector2.ONE * 0.2
	fx.add_child(s)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "scale", Vector2.ONE * size_to, 0.45)
	t.tween_property(s, "modulate:a", 0.0, 0.45)
	t.chain().tween_callback(s.queue_free)


func _light_column(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _column_tex
	s.material = _add_mat
	s.modulate = Color(GOLD, 0.0)
	s.centered = false
	s.scale = Vector2(190.0 / 64.0, (pos.y + 100.0) / 256.0)
	s.position = Vector2(pos.x - 95.0, 0)
	fx.add_child(s)
	var t := create_tween()
	t.tween_property(s, "modulate:a", 0.9, 0.2)
	t.tween_interval(0.5)
	t.tween_property(s, "modulate:a", 0.0, 0.5)
	t.tween_callback(s.queue_free)


func _pulse_glow(v: CardView, color: Color) -> void:
	v.glow_color = color
	var t := create_tween()
	t.tween_property(v, "glow", 1.3, 0.15)
	t.tween_property(v, "glow", 0.0, 0.5)


func _dim(alpha: float, seconds: float) -> void:
	create_tween().tween_property(_dim_rect, "color:a", alpha, seconds)


func _screen_flash(color: Color, alpha: float) -> void:
	var r := ColorRect.new()
	r.color = Color(color, alpha)
	r.size = Vector2(1920, 1080)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.0, 0.35)
	t.tween_callback(r.queue_free)


func _clear_attack_line() -> void:
	if _attack_line and is_instance_valid(_attack_line):
		var l := _attack_line
		var t := create_tween()
		t.tween_property(l, "modulate:a", 0.0, 0.15)
		t.tween_callback(l.queue_free)
	_attack_line = null


# ── Text, banners and callouts ───────────────────────────────────────────────

func _label(font_size: int, color: Color, heading := false) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	if heading:
		ls.font = _font
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = maxi(4, font_size / 9)
	ls.outline_color = Color(0, 0, 0, 0.9)
	ls.shadow_size = 0
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Pop-in text that drifts up and fades (world coordinates = screen coordinates here).
func _float_text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var l := _label(font_size, color, true)
	l.text = text
	l.size = Vector2(700, font_size * 1.4)
	l.position = pos - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.scale = Vector2.ONE * 1.7
	overlay.add_child(l)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.set_parallel()
	t.tween_property(l, "position:y", l.position.y - 50, 0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(l.queue_free)


func _stamp(pos: Vector2, text: String, color: Color) -> void:
	var l := _label(46, color, true)
	l.text = text
	l.size = Vector2(400, 70)
	l.position = pos - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.rotation = -0.18
	l.scale = Vector2.ONE * 2.6
	overlay.add_child(l)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_interval(0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


func _notice(text: String) -> void:
	_float_text(Vector2(1080, DIVIDER_Y), text, Color.WHITE, 40)
	await _wait(0.7)


func _phase_flash(text: String, color: Color) -> void:
	var l := _label(60, color, true)
	l.text = text
	l.size = Vector2(1100, 90)
	l.position = Vector2(1080 - 550, DIVIDER_Y - 45)
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	l.scale = Vector2.ONE * 1.3
	overlay.add_child(l)
	var t := create_tween().set_parallel()
	t.tween_property(l, "modulate:a", 1.0, 0.12)
	t.tween_property(l, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(0.35)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(l.queue_free)
	await _wait(0.45)


func _sweep_banner(text: String, color: Color) -> void:
	var band := Control.new()
	band.size = Vector2(1920, 150)
	band.position = Vector2(-1920, DIVIDER_Y - 75)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.88)
	bg.size = band.size
	band.add_child(bg)
	for y in [0.0, 146.0]:
		var edge := ColorRect.new()
		edge.color = color
		edge.size = Vector2(1920, 4)
		edge.position.y = y
		band.add_child(edge)
	var l := _label(96, Color.WHITE, true)
	l.text = text
	l.size = band.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.label_settings.outline_color = Color(color, 0.9)
	band.add_child(l)
	overlay.add_child(band)
	var t := create_tween()
	t.tween_property(band, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.55)
	t.tween_property(band, "position:x", 1920.0, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_callback(band.queue_free)
	await t.finished


func _splash_name(card_name: String, color: Color) -> void:
	var l := _label(84, Color.WHITE, true)
	l.text = card_name.to_upper()
	l.size = Vector2(1200, 110)
	l.position = Vector2(1080 - 600, DIVIDER_Y - 55)
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.label_settings.outline_color = color
	l.label_settings.outline_size = 14
	l.modulate.a = 0.0
	overlay.add_child(l)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(l, "modulate:a", 1.0, 0.15)
	t.tween_property(l, "position:x", l.position.x - 40, 0.9)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(l.queue_free)


## An effect call-out: card art, name and what the effect just did.
func _callout(c: Dictionary, text: String, side: String) -> void:
	if _ui.has("callout") and is_instance_valid(_ui.callout):
		_ui.callout.queue_free()
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.95), BLUE if side == "player" else RED, 2, 10))
	box.custom_minimum_size = Vector2(620, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(76, 107)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = CardDB.art(str(c.get("art_url", c.get("id", "")))) if not c.is_empty() else null
	row.add_child(art)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var n := _label(26, GOLD, true)
	n.text = str(c.get("name", "Effect")).to_upper()
	col.add_child(n)
	var t := _label(20, Color.WHITE)
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(480, 0)
	col.add_child(t)
	overlay.add_child(box)
	_ui.callout = box
	var y := DIVIDER_Y - 62 + (70.0 if side == "player" else -70.0)
	box.position = Vector2(1080 - 310 - 60, y)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(box, "position:x", 1080.0 - 310.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.chain().tween_interval(1.1)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(box.queue_free)


# ── HUD ──────────────────────────────────────────────────────────────────────

func _build_detail() -> void:
	var p: Panel = $HUD/UI/Detail
	var art := TextureRect.new()
	art.position = Vector2(20, 18)
	art.size = Vector2(340, 482)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.add_child(art)
	var title := _label(30, Color.WHITE, true)
	title.position = Vector2(20, 506)
	title.size = Vector2(340, 40)
	p.add_child(title)
	var kind := _label(15, Color(0.62, 0.66, 0.82))
	kind.position = Vector2(20, 546)
	kind.size = Vector2(340, 22)
	p.add_child(kind)
	var stats := RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.scroll_active = false
	stats.position = Vector2(20, 572)
	stats.size = Vector2(340, 34)
	stats.add_theme_font_override("normal_font", _font)
	stats.add_theme_font_size_override("normal_font_size", 24)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stats)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.position = Vector2(20, 610)
	text.size = Vector2(340, 152)
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("italics_font_size", 15)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(text)
	_ui.detail_art = art
	_ui.detail_title = title
	_ui.detail_kind = kind
	_ui.detail_stats = stats
	_ui.detail_text = text
	_show_detail({})


func _show_detail(c: Dictionary, live_stats := []) -> void:
	var key := "%s:%s" % [c.get("uid", c.get("id", "")), live_stats]
	if key == _detail_key:
		return
	_detail_key = key
	if c.is_empty():
		_ui.detail_art.texture = CardDB.back()
		_ui.detail_title.text = ""
		_ui.detail_kind.text = ""
		_ui.detail_stats.text = ""
		_ui.detail_text.text = "[color=#8a8aa0]Hover a card to see it here.[/color]"
		return
	var tex := CardDB.art(str(c.get("art_url", c.get("id", ""))))
	_ui.detail_art.texture = tex if tex else CardDB.back()
	_ui.detail_title.text = str(c.get("name", "?"))
	var parts: Array = [TYPE_NAMES.get(c.get("cardType", ""), "CARD")]
	if c.get("subtype") is String:
		parts.append(str(c.subtype).to_upper())
	if DuelState.is_lion(c):
		parts.append("LIONS")
	parts.append("AUTHORITY %d" % int(c.get("authority", 0)))
	_ui.detail_kind.text = "  ·  ".join(parts)
	if c.get("cardType") in ["gang_member", "leader"]:
		var base_atk := int(c.get("base_attack", c.get("attack", 0)))
		var base_def := int(c.get("base_defense", c.get("defense", 0)))
		var atk: int = live_stats[0] if live_stats.size() >= 2 else base_atk
		var def: int = live_stats[1] if live_stats.size() >= 2 else base_def
		_ui.detail_stats.text = "[color=#%s]ATK %d[/color]   [color=#%s]DEF %d[/color]" % [
			CardView._stat_color(atk, base_atk, "ffd86b"), atk, CardView._stat_color(def, base_def, "9ddcff"), def]
	else:
		_ui.detail_stats.text = ""
	var body := str(c.get("effectText", ""))
	if c.get("flavourText") is String:
		body += "\n\n[i][color=#8a8aa0]%s[/color][/i]" % c.flavourText
	_ui.detail_text.text = body


func _build_panel(side: String, p: Panel, display_name: String, avatar: String, subtitle: String) -> void:
	var accent := BLUE if side == "player" else RED
	p.add_theme_stylebox_override("panel", _box(INK, accent, 2, 10))
	var av := TextureRect.new()
	av.position = Vector2(14, 14)
	av.size = Vector2(64, 64)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var av_path := "res://assets/%s.png" % avatar
	if ResourceLoader.exists(av_path):
		av.texture = load(av_path)
	p.add_child(av)
	var n := _label(26, Color.WHITE, true)
	n.text = display_name
	n.position = Vector2(92, 10)
	p.add_child(n)
	var sub := _label(14, accent)
	sub.text = subtitle
	sub.position = Vector2(92, 46)
	p.add_child(sub)
	var cap := _label(13, Color(0.55, 0.57, 0.7))
	cap.text = "MORALE"
	cap.position = Vector2(14, 92)
	p.add_child(cap)
	var morale := _label(50, Color.WHITE, true)
	morale.text = str(DuelState.START_MORALE)
	morale.label_settings.outline_color = Color(accent, 0.8)
	morale.size = Vector2(p.size.x - 28, 60)
	morale.position = Vector2(14, 72)
	morale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(morale)
	var track := ColorRect.new()
	track.position = Vector2(14, 136)
	track.size = Vector2(p.size.x - 28, 10)
	track.color = Color(1, 1, 1, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(track)
	var bar := ColorRect.new()   # fill width = morale share
	bar.size = track.size
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	var auth := _label(18, GOLD, true)
	auth.position = Vector2(14, 152)
	auth.pivot_offset = Vector2(0, 12)
	p.add_child(auth)
	var piles := _label(15, Color(0.62, 0.66, 0.82))
	piles.position = Vector2(14, 180)
	p.add_child(piles)
	var flash := ColorRect.new()
	flash.color = Color(1, 0.15, 0.15, 0)
	flash.size = p.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(flash)
	_panels[side] = {"root": p, "morale": morale, "bar": bar, "auth": auth, "piles": piles,
		"flash": flash, "shown": float(DuelState.START_MORALE), "base": p.position}


func _set_morale(side: String, value: int) -> void:
	var p: Dictionary = _panels[side]
	var from: float = p.shown
	p.shown = float(value)
	var label: Label = p.morale
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(func(x: float): label.text = str(int(x)), from, float(value), 0.7)
	var bar: ColorRect = p.bar
	var full: float = bar.get_parent().size.x
	t.tween_property(bar, "size:x", full * clampf(float(value) / DuelState.START_MORALE, 0.0, 1.0), 0.7)
	if value < from:
		var flash: ColorRect = p.flash
		flash.color.a = 0.5
		t.tween_property(flash, "color:a", 0.0, 0.45)
		var root: Control = p.root
		var base: Vector2 = p.base
		var s := create_tween()
		for off in [Vector2(12, 0), Vector2(-10, 4), Vector2(7, -3), Vector2(-4, 0), Vector2.ZERO]:
			s.tween_property(root, "position", base + off, 0.045)


func _refresh_hud() -> void:
	for side in _panels:
		var c: Dictionary = counts.get(side, {})
		if c.is_empty():
			continue
		var p: Dictionary = _panels[side]
		p.auth.text = "AUTHORITY   %d / %d" % [c.authority, c.authority_max]
		p.piles.text = "HAND %d    ·    DECK %d" % [c.hand, c.deck]
	queue_redraw()


func _build_phase_bar() -> void:
	var p: Panel = $HUD/UI/PhaseBar
	var cap := _label(13, Color(0.55, 0.57, 0.7))
	cap.text = "PHASE"
	cap.position = Vector2(16, 12)
	p.add_child(cap)
	_ui.phase_labels = {}
	var i := 0
	for key in PHASE_NAMES:
		var l := _label(26, Color(1, 1, 1, 0.3), true)
		l.text = PHASE_NAMES[key]
		l.position = Vector2(16, 38 + i * 42)
		p.add_child(l)
		_ui.phase_labels[key] = l
		i += 1
	var next := Button.new()
	next.position = Vector2(14, p.size.y - 92)
	next.size = Vector2(p.size.x - 28, 76)
	next.add_theme_font_size_override("font_size", 24)
	next.pressed.connect(_on_next)
	p.add_child(next)
	var hint := _label(12, Color(0.55, 0.57, 0.7))
	hint.text = "SPACE"
	hint.position = Vector2(p.size.x - 62, p.size.y - 112)
	p.add_child(hint)
	_ui.next = next
	_update_next_btn()


func _set_phase_ui(phase: String) -> void:
	for key in _ui.phase_labels:
		var l: Label = _ui.phase_labels[key]
		var on: bool = key == phase
		l.text = ("▸ " if on else "") + str(PHASE_NAMES[key])
		l.label_settings.font_color = GOLD if on else Color(1, 1, 1, 0.3)
	_update_next_btn()


func _update_next_btn() -> void:
	if not _ui.has("next") or duel == null:
		return
	var b: Button = _ui.next
	var mine := duel.active == "player" and not "player" in ai_sides
	b.disabled = not mine or duel.winner != "" or not duel.pending.is_empty() or _awaiting
	if not mine:
		b.text = "OPPONENT'S TURN"
	else:
		match duel.phase:
			"deployment":
				b.text = "TO REGROUP  ▶" if duel.turn == 1 else "TO BRAWL  ▶"
			"brawl":
				b.text = "TO REGROUP  ▶"
			_:
				b.text = "END TURN  ▶"


func _build_turn_box() -> void:
	var p: Panel = $HUD/UI/TurnBox
	var num := _label(46, Color.WHITE, true)
	num.text = "TURN 1"
	num.position = Vector2(16, 18)
	p.add_child(num)
	var who := _label(20, BLUE, true)
	who.position = Vector2(18, 88)
	p.add_child(who)
	_ui.turn_num = num
	_ui.turn_who = who


func _play_music() -> void:
	var path := "res://assets/duel_theme.mp3"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		stream.loop = true
	Game.stop_music()
	var music := AudioStreamPlayer.new()
	music.bus = "Music"
	music.stream = stream
	music.volume_db = -14.0
	add_child(music)
	music.play()


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var panel := _box(INK, Color(1, 1, 1, 0.12), 2, 10)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _box(Color("1c2040"), Color(BLUE, 0.7), 2, 8))
	th.set_stylebox("hover", "Button", _box(Color("28305e"), GOLD, 2, 8))
	th.set_stylebox("pressed", "Button", _box(Color("12162e"), GOLD, 2, 8))
	th.set_stylebox("disabled", "Button", _box(Color("0d0f1e"), Color(1, 1, 1, 0.1), 2, 8))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", GOLD)
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	th.set_font("font", "Button", _font)
	th.set_font_size("font_size", "Button", 20)
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.9, 1.0))
	return th


func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_resources() -> void:
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var dot_g := Gradient.new()
	dot_g.set_color(0, Color(1, 1, 1, 1))
	dot_g.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = dot_g
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	_dot = dot

	var ring_g := Gradient.new()
	ring_g.offsets = PackedFloat32Array([0.0, 0.6, 0.8, 1.0])
	ring_g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ring := GradientTexture2D.new()
	ring.gradient = ring_g
	ring.fill = GradientTexture2D.FILL_RADIAL
	ring.fill_from = Vector2(0.5, 0.5)
	ring.fill_to = Vector2(1.0, 0.5)
	ring.width = 256
	ring.height = 256
	_ring_tex = ring

	var col_g := Gradient.new()
	col_g.offsets = PackedFloat32Array([0.0, 0.85, 1.0])
	col_g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var column := GradientTexture2D.new()
	column.gradient = col_g
	column.fill_from = Vector2(0.5, 0.0)
	column.fill_to = Vector2(0.5, 1.0)
	column.width = 64
	column.height = 256
	_column_tex = column

	_slot_box = _box(Color(0.55, 0.4, 0.85, 0.07), Color(0.72, 0.56, 0.95, 0.4), 2, 8)
	_slot_box_back = _box(Color(0.4, 0.55, 0.85, 0.06), Color(0.5, 0.66, 0.95, 0.32), 2, 8)
	_pile_box = _box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.16), 2, 8)


# ── Player input ─────────────────────────────────────────────────────────────

func _player_ready() -> void:
	_clear_highlights()
	_update_next_btn()
	if duel.winner != "":
		return
	if not duel.pending.is_empty():
		if duel.pending.side == "player":
			if duel.pending.kind == "discard":
				_mode = "discard"
				_show_prompt(duel.pending.prompt)
				for v in hand.player:
					v.glow_color = RED
					v.glow = 0.8
			else:
				_show_choice(duel.pending)
		return
	_hide_prompt()
	if duel.active != "player":
		return
	_mode = "idle"
	if duel.can_deploy_now("player"):
		for v in hand.player:
			if _playable(v.card):
				v.glow_color = GREEN
				v.glow = 0.75
	for slot in field.player:
		var ready := duel.can_attack_with("player", slot) or duel.can_promote("player", slot) \
			or duel.can_use_ability("player", slot)
		if ready:
			field.player[slot].glow_color = GOLD
			field.player[slot].glow = 0.9


## A prompt from a card effect: buttons for each option, and the cards it refers to light up
## (click one of those to choose it too).
func _show_choice(p: Dictionary) -> void:
	_cancel_interaction()
	_mode = "choose"
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.96), GOLD, 3, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(124, 175)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var c: Dictionary = p.get("card", {})
	art.texture = CardDB.art(str(c.get("art_url", c.get("id", "")))) if not c.is_empty() else null
	row.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	var title := _label(22, Color.WHITE, true)
	title.text = p.prompt
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.custom_minimum_size = Vector2(420, 0)
	col.add_child(title)
	for o in p.options:
		var b := Button.new()
		b.text = o.label
		b.custom_minimum_size = Vector2(420, 44)
		b.pressed.connect(_pick.bind(str(o.id)))
		col.add_child(b)
		if o.has("slot"):
			_valid["%s:%d" % [o.side, o.slot]] = GOLD
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, clampf(DIVIDER_Y - sz.y / 2, 10, 1070 - sz.y))
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.15)
	_menu = box
	Sfx.play("effect", 1.3, -6.0)
	queue_redraw()


func _pick(option: String) -> void:
	Sfx.play("click")
	_cancel_interaction()
	_act("player", {"kind": "choose", "option": option})


func _playable(c: Dictionary) -> bool:
	match c.get("cardType", ""):
		"gang_member":
			return DuelState.FRONT.any(func(s): return duel.can_summon("player", c, s))
		"ambush":
			return DuelState.BACK.any(func(s): return duel.can_set("player", c, s))
		"hustle":
			return duel.can_hustle("player", c)
	return false


func _clear_highlights() -> void:
	for v in hand.player:
		v.glow = 0.0
	for side in field:
		for slot in field[side]:
			field[side][slot].glow = 0.0
	for side in leaders:
		leaders[side].glow = 0.0
	_valid.clear()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _press and not _dragging and get_global_mouse_position().distance_to(_press_pos) > 14.0:
			_start_drag()
		if not _dragging:
			_update_hover()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_press()
			else:
				_on_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_and_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_on_next()
			KEY_ESCAPE:
				if _mode in ["menu", "place", "target"]:
					_cancel_and_refresh()
				else:
					_toggle_menu()
			KEY_F11:
				var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _view_at(p: Vector2) -> CardView:
	var hv := _hand_view_at(p)
	if hv:
		return hv
	for side in field:
		for slot in field[side]:
			var v: CardView = field[side][slot]
			if is_instance_valid(v) and v.hit(p):
				return v
	for side in leaders:
		if leaders[side].hit(p):
			return leaders[side]
	return null


func _hand_view_at(p: Vector2) -> CardView:
	var best: CardView = null
	for v in hand.player:
		if not v.busy and v.hit(p) and (best == null or v.z_index > best.z_index):
			best = v
	return best


func _update_hover() -> void:
	var m := get_global_mouse_position()
	var v := _view_at(m)
	if v != _hovered:
		var old := _hovered
		_hovered = v
		if old and is_instance_valid(old) and old in hand.player and old != _selected:
			_layout_hand("player")
		if v and v in hand.player and _mode != "place":
			v.z_index = 300
			v.move_to(Vector2(v.home.x, HAND_LIFT_Y), HOVER_SCALE, 0.0, 0.14)
			Sfx.play("click", 1.4, -12.0)
	if v:
		if v.side == "opponent" and not v.face_up:
			_show_detail({"name": "Face-down card", "cardType": "", "uid": -v.uid})
		else:
			_show_detail(v.card, v.stats())
		return
	for side in ["player", "opponent"]:
		if Rect2(pile_pos(side, "gutter") - CARD / 2, CARD).has_point(m):
			var top: String = counts.get(side, {}).get("gutter_top", "")
			if top != "":
				_show_detail(CardDB.get_card(top))


func _on_press() -> void:
	if _mode == "over":
		return
	var m := get_global_mouse_position()
	if _mode == "menu":
		_cancel_and_refresh()
		return
	if _playing or _awaiting:
		return
	match _mode:
		"choose":
			for side in ["player", "opponent"]:
				var slot := _slot_at(side, m)
				if slot >= 0 and _valid.has("%s:%d" % [side, slot]):
					for o in duel.pending.get("options", []):
						if o.get("side") == side and o.get("slot") == slot:
							_pick(str(o.id))
							return
			return
		"discard":
			var hv := _hand_view_at(m)
			if hv:
				_act("player", {"kind": "discard", "uid": hv.uid})
			return
		"place":
			var slot := _slot_at("player", m)
			if _valid.has("player:%d" % slot):
				_place(slot)
			else:
				_cancel_and_refresh()
			return
		"target":
			var slot := _slot_at("opponent", m)
			var leader: CardView = leaders.get("opponent")
			if leader and leader.glow > 0.0 and leader.hit(m):
				slot = DuelState.LEADER
			if _valid.has("opponent:%d" % slot) or slot == DuelState.LEADER:
				var from := _selected_slot
				_cancel_interaction()
				_act("player", {"kind": "attack", "from": from, "target": slot})
			else:
				_cancel_and_refresh()
			return
	if not duel.can_act("player") or "player" in ai_sides:
		return
	var hv := _hand_view_at(m)
	if hv:
		_press = hv
		_press_pos = m
		return
	var slot := _slot_at("player", m)
	if slot >= 0 and field.player.has(slot):
		_on_field_click(slot)


func _on_release() -> void:
	if _dragging:
		_end_drag()
		return
	if _press:
		var v := _press
		_press = null
		if is_instance_valid(v) and v.hit(get_global_mouse_position()):
			_open_hand_menu(v)


## Click your own character: attack right away when that's the only option, otherwise a menu
## (attack, change position, promote, ability).
func _on_field_click(slot: int) -> void:
	var v: CardView = field.player[slot]
	var c := v.card
	var opts: Array = []
	var can_attack := duel.can_attack_with("player", slot)
	if can_attack:
		opts.append(["ATTACK", true, _begin_target.bind(slot)])
	if duel.can_change_position("player", slot):
		var to_def: bool = duel.card_at("player", slot).position == "atk"
		opts.append(["CHANGE TO DEF" if to_def else "CHANGE TO ATK  (FLIP FACE-UP)" if duel.card_at("player", slot).face_down else "CHANGE TO ATK",
			true, _field_action.bind({"kind": "position", "slot": slot})])
	if duel.can_promote("player", slot):
		opts.append(["PROMOTE", true, _field_action.bind({"kind": "promote", "slot": slot})])
	if duel.can_use_ability("player", slot):
		opts.append(["BUFF A LIONS ALLY  (+400 / +400)", true, _field_action.bind({"kind": "ability", "slot": slot})])
	if opts.is_empty():
		return
	if opts.size() == 1 and can_attack:
		_begin_target(slot)
		return
	_clear_highlights()
	_mode = "menu"
	v.glow_color = GOLD
	v.glow = 1.2
	opts.append(["CANCEL", true, _cancel_and_refresh])
	_menu = _make_menu(opts, "", v.home + Vector2(0, -CARD.y / 2 - 12))


func _field_action(action: Dictionary) -> void:
	_cancel_interaction()
	_act("player", action)


func _begin_target(slot: int) -> void:
	_cancel_interaction()
	_clear_highlights()
	_mode = "target"
	_selected_slot = slot
	field.player[slot].glow_color = GOLD
	field.player[slot].glow = 1.2
	var targets := duel.attack_targets("player")
	for t in targets:
		if t >= 0:
			_valid["opponent:%d" % t] = RED
	if DuelState.DIRECT in targets:
		_show_direct_button(slot)
	if DuelState.LEADER in targets and leaders.has("opponent"):
		leaders.opponent.glow_color = RED
		leaders.opponent.glow = 1.0
		_show_prompt("Attack directly, or click the dormant leader to hit its Influence")
	else:
		_show_prompt("Choose a target  ·  right-click to cancel")
	queue_redraw()


func _open_hand_menu(v: CardView) -> void:
	if not duel.can_deploy_now("player"):
		return
	_clear_highlights()
	_selected = v
	_mode = "menu"
	v.z_index = 300
	v.move_to(Vector2(v.home.x, HAND_LIFT_Y), HOVER_SCALE, 0.0, 0.12)
	var c := v.card
	var s: Dictionary = duel.sides.player
	var opts: Array = []
	var reason := ""
	if s.authority < int(c.get("authority", 0)):
		reason = "Needs %d Authority (you have %d)" % [c.authority, s.authority]
	match c.get("cardType", ""):
		"gang_member":
			var ok := _playable(c)
			if ok == false and reason == "":
				reason = "No free front-row slot"
			opts.append(["SUMMON  ·  ATK", ok, func(): _begin_place(v, "summon_atk")])
			opts.append(["SET  ·  DEF (FACE-DOWN)", ok, func(): _begin_place(v, "summon_def")])
		"ambush":
			var ok := _playable(c)
			if ok == false and reason == "":
				reason = "No free back-row slot"
			opts.append(["SET AMBUSH", ok, func(): _begin_place(v, "set")])
		"hustle":
			var ok := duel.can_hustle("player", c)
			if ok == false and reason == "":
				reason = "Requirements not met"
			opts.append(["ACTIVATE", ok, func():
				_cancel_interaction()
				_act("player", {"kind": "hustle", "uid": v.uid})])
	opts.append(["CANCEL", true, _cancel_and_refresh])
	_menu = _make_menu(opts, reason, Vector2(v.home.x, HAND_LIFT_Y - CARD.y * HOVER_SCALE / 2 - 12))


func _make_menu(opts: Array, reason: String, anchor: Vector2) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.97), GOLD, 2, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)
	if reason != "":
		var r := _label(15, Color("ff8a8a"))
		r.text = reason
		col.add_child(r)
	for o in opts:
		var b := Button.new()
		b.text = o[0]
		b.disabled = not o[1]
		b.custom_minimum_size = Vector2(300, 46)
		b.pressed.connect(func():
			Sfx.play("click")
			o[2].call())
		col.add_child(b)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(clampf(anchor.x - sz.x / 2, 420, 1640 - sz.x), maxf(10.0, anchor.y - sz.y))
	return box


func _begin_place(v: CardView, kind: String) -> void:
	_close_menu()
	_selected = v
	_place_kind = kind
	_mode = "place"
	_valid.clear()
	var c := v.card
	for slot in 10:
		var ok := duel.can_set("player", c, slot) if kind == "set" else duel.can_summon("player", c, slot)
		if ok:
			_valid["player:%d" % slot] = GREEN
	_show_prompt("Choose a slot  ·  right-click to cancel")
	queue_redraw()


func _place(slot: int) -> void:
	var v := _selected
	var kind := _place_kind
	_cancel_interaction()
	match kind:
		"summon_atk":
			_act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk"})
		"summon_def":
			_act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "def"})
		"set":
			_act("player", {"kind": "set", "uid": v.uid, "slot": slot})


func _start_drag() -> void:
	var v := _press
	if not is_instance_valid(v) or not _playable(v.card):
		_press = null
		return
	_cancel_interaction()
	_press = v
	_dragging = true
	_hovered = null
	v.stop_moving()
	v.z_index = 500
	create_tween().tween_property(v, "scale", Vector2.ONE * 1.1, 0.1)
	var c := v.card
	for slot in 10:
		if duel.can_summon("player", c, slot) or duel.can_set("player", c, slot):
			_valid["player:%d" % slot] = GREEN
	if c.cardType == "hustle":
		_show_prompt("Release on the board to activate")
	queue_redraw()


func _end_drag() -> void:
	var v := _press
	_press = null
	_dragging = false
	var m := get_global_mouse_position()
	var c := v.card
	var slot := _slot_at("player", m)
	var done := false
	_valid.clear()
	_hide_prompt()
	if c.cardType == "gang_member" and duel.can_summon("player", c, slot):
		done = _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk"})
	elif c.cardType == "ambush" and duel.can_set("player", c, slot):
		done = _act("player", {"kind": "set", "uid": v.uid, "slot": slot})
	elif c.cardType == "hustle" and m.y < HAND_Y - 140 and duel.can_hustle("player", c):
		done = _act("player", {"kind": "hustle", "uid": v.uid})
	if not done:
		_layout_hand("player")
		_player_ready()


func _show_direct_button(slot: int) -> void:
	var b := Button.new()
	b.text = "DIRECT ATTACK  ⚔"
	b.custom_minimum_size = Vector2(340, 70)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", _box(Color("4a0d14"), RED, 3, 10))
	b.position = Vector2(1080 - 170, ROWS.opponent[0] - 35)
	b.pressed.connect(func():
		_cancel_interaction()
		_act("player", {"kind": "attack", "from": slot, "target": -1}))
	overlay.add_child(b)
	_direct_btn = b


func _on_next() -> void:
	if _playing or _awaiting or "player" in ai_sides or not duel.can_act("player"):
		return
	_cancel_interaction()
	Sfx.play("click")
	_act("player", {"kind": "next"})


func _close_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func _cancel_interaction() -> void:
	_close_menu()
	if _direct_btn and is_instance_valid(_direct_btn):
		_direct_btn.queue_free()
	_direct_btn = null
	_valid.clear()
	_hide_prompt()
	var sel := _selected
	_selected = null
	_selected_slot = -1
	_press = null
	_dragging = false
	if _mode != "over":
		_mode = "idle"
	if sel and is_instance_valid(sel) and sel in hand.player:
		_layout_hand("player")
	queue_redraw()


func _cancel_and_refresh() -> void:
	_cancel_interaction()
	if not _playing:
		_player_ready()


func _show_prompt(text: String) -> void:
	if not _ui.has("prompt"):
		var l := _label(24, Color.WHITE, true)
		l.size = Vector2(900, 40)
		l.position = Vector2(1080 - 450, 836)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay.add_child(l)
		_ui.prompt = l
	_ui.prompt.text = text
	_ui.prompt.visible = true


func _hide_prompt() -> void:
	if _ui.has("prompt"):
		_ui.prompt.visible = false


func _toggle_menu() -> void:
	if _ui.has("menu") and is_instance_valid(_ui.menu):
		_ui.menu.queue_free()
		_ui.erase("menu")
		return
	var box := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var title := _label(40, GOLD, true)
	title.text = "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for label in ["RESUME", "SETTINGS", "CONCEDE" if _online else "LEAVE DUEL"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(320, 60)
		b.pressed.connect(_on_menu_choice.bind(label))
		col.add_child(b)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(960, 540) - sz / 2
	_ui.menu = box


func _on_menu_choice(choice: String) -> void:
	match choice:
		"RESUME":
			_toggle_menu()
		"SETTINGS":
			_toggle_menu()
			SettingsPanel.open(overlay, false)
		"CONCEDE":
			_toggle_menu()
			UI.dialog(overlay, "CONCEDE THE MATCH?", "Your opponent wins and the match is recorded as a loss.", [
				["CONCEDE", func(): Net.send("mp:concede", {"matchId": _match_id}), RED], ["KEEP FIGHTING", func(): pass]])
		"LEAVE DUEL":
			UI.dialog(overlay, "LEAVE THE DUEL?", "You'll lose this match's progress and get no rewards.", [
				["LEAVE", func(): Game.go("main_menu"), RED], ["STAY", func(): pass]])
		"REMATCH":
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		"QUIT":
			get_tree().quit()
