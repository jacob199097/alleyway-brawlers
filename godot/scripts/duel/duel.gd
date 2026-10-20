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
## Free-for-all: the crossroads (arena_ffa.png) fills the screen with its manhole at FFA_MID, and the
## four boards sit close round it (their slots painted by the game, like the 1v1 mat's). The two on top
## are the 1v1 opponent's layout (centred on OPP_C); yours and the one beside it (below) are your
## layout (centred on PLAYER_C), facing up. Plates (name, Morale) face each other across the middle.
const OPP_C := Vector2(1080, 216)
const PLAYER_C := Vector2(1080, 632)
const FFA_MID := Vector2(1028, 440)      # between the four boards (and between the side panels: x 403-1651)
const FFA_MANHOLE := Vector2(768, 508)   # the steaming manhole in the middle of the crossroads (image pixels)
const FFA_CARD_K := 0.6                  # a card's size on an FFA board
const FFA_STEP := Vector2(83, 117)       # lane to lane, row to row
const FFA_GAP := Vector2(24, 60)         # between boards side by side; between the plates across the middle
const PLATE_H := 90.0
const PAINT_K := 0.65      # the painted slot outline (arena_paint.png) against a full-size slot
const FOE_COLORS := [Color("e63946"), Color("ff9f43"), Color("b388ff")]
const FOE_HAND := 0.22     # an opponent's hand: a small fan of card backs on their plate

const BLUE := Color("4cc9f0")
const RED := Color("e63946")
const GOLD := Color("f4d35e")
const GREEN := Color("3ddc84")
const TEAL := Color("3ee6d0")   # a character with an Activate ability ready
const SWAP := Color("ff9f43")   # one of your characters a card can be deployed over
const PICKED := Color("b388ff")   # a character already chosen as a Heavy's sacrifice
const INK := Color(0.03, 0.03, 0.08, 0.92)
const AttackArrow := preload("res://scripts/duel/attack_arrow.gd")
const Tutorial := preload("res://scripts/duel/tutorial.gd")
const Keywords := preload("res://scripts/keywords.gd")
const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")
const ONLINE_TURN_SECS := 90.0   # matches TURN_SECS in backend/socket/onlineMatch.js
## Emotes in online matches against players (keys match EMOTES in backend/socket/onlineMatch.js)
const EMOTES := [["hello", "Hey!"], ["nice", "Nice move!"], ["wp", "Well played"], ["thinking", "Hmm…"],
	["oops", "Oops!"], ["hurry", "Your move…"], ["gotcha", "Gotcha!"], ["gg", "GG"]]
const EMOTE_GAP_MS := 2600
const REPLAY_GAP := 0.35   # seconds between moves when watching a replay
## A clan's own animations. attack "laser": dark purple laser beams instead of charging in;
## summon "warp": arrives through a swirling portal; ko "stardust": dissolves into stardust.
## attack "guns": rapid gunfire, with muzzle flashes, tracers and bullet hits (Militia).
const CLAN_STYLE := {"nebula": {"attack": "laser", "summon": "warp", "ko": "stardust"}, "militia": {"attack": "guns", "summon": "airdrop"}}
const LASER_GLOW := Color(0.62, 0.32, 1.0)
const LASER_CORE := Color(0.16, 0.03, 0.3)

const TYPE_NAMES := {"gang_member": "CHARACTER", "hustle": "HUSTLE", "ambush": "AMBUSH", "leader": "LEADER"}
const PHASE_NAMES := {"deployment": "DEPLOYMENT", "brawl": "BRAWL", "regroup": "REGROUP"}

var ai_sides := ["opponent"]

@onready var cards_layer: Node2D = $Cards
var _pile_backs := {}       # "side:pile" (deck, hideout) -> the moving back on top of it (_update_pile_backs)
var _pile_ink: Node2D       # their counts and names, drawn over them
@onready var fx: Node2D = $FX
@onready var camera: Camera2D = $Camera
@onready var ui: Control = $HUD/UI
@onready var overlay: Control = $HUD/UI/Overlay

var duel: DuelState
var hand := {"player": [], "opponent": []}     # CardViews, in hand order
var field := {"player": {}, "opponent": {}}    # slot -> CardView
var leaders := {}                              # side -> CardView
var counts := {}                               # pile sizes from the last event
var _detail_spin := ""                         # the large preview's moving card back style ("" = none)
var _detail_angle := 0.0

var _queue: Array = []
var _playing := false
var _shake := 0.0
var _hovered: CardView = null
var _detail_key := ""
var _mode := "idle"   # idle | menu | place | target | discard | over
var _selected: CardView = null
var _selected_slot := -1
var _place_kind := ""
var _tribute_picks: Array = []   # a Heavy's sacrifices chosen so far (the first is its lane)
var _valid := {}      # "side:slot" -> highlight colour
var _press: CardView = null
var _press_pos := Vector2.ZERO
var _dragging := false
var _menu: Control = null
var _direct_btn: Button = null
var _arrow: AttackArrow              # the curved targeting arrow
var _tutorial: Node = null          # the guided first duel (Game.duel_setup.mode == "tutorial")
var _tip_box: Control = null
var _dim_rect: ColorRect = null
var _match_id := ""
var _cards_played := 0
var _damage_log := {}     # "side:uid" -> {card, owner, damage}
var _last_hit := {}
var _online := false      # a server-run match (Game.duel_setup.online)
var _replay := {}         # watching a recorded match: {start, updates, over, complete}
var _spectating := false  # watching a friend's match live (mp:spectate): their side is "player"
var _names := {}          # side -> name, for a spectator's texts
var _chosen_back := {"player": "", "opponent": ""}   # side -> card back the player chose ("" = their clan's)
var _replay_next := 0     # next update to play
var _replay_wait := 0.0
var _emote_ready_at := 0
var _emotes_muted := false
var _awaiting := false    # sent a move, waiting for the server's answer
var _away_warned := false # told the player a move was played for them (server move clock)
var _base_speed := 1.0    # Engine.time_scale outside hit-stops: Settings → Animation Speed, or replay speed
var _catch_up := 1.0      # faster while a backlog of events waits (a free-for-all's CPUs move quickly)
var _replay_seek := -1    # replay: jump to this update once the current one has finished animating
var _log_text: RichTextLabel   # the battle log (L)
var _log_lines := 0
var _over := {}           # mp:over from the server
var _clock_left := 0.0
var _post: ColorRect                # full-screen hit effects (shaders/post.gdshader)
var _post_mat: ShaderMaterial
var _post_fx := {"aberration": 0.0, "wave_strength": 0.0, "impact": 0.0}
var _danger := 0.0                  # 0..1, the player's Morale is low
var _cam_tw: Tween
var _streak_tex: Texture2D
var _strike_at := Vector2.INF       # where the last clash landed (damage flies from there)
var _strike_time := 0.0              # game time of that clash
var _game_time := 0.0
var _end_reason := "morale"         # from game_over: "morale" or "deck_out"
var _end_snap: Texture2D = null      # the board as the match ended, before anything covers it (post-match background)

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
var _ffa := false          # a free-for-all (backend/socket/ffaMatch.js): 3-4 players, every board on screen
var _sides: Array = ["player", "opponent"]   # every side ("player" first)
var _foes: Array = ["opponent"]              # everyone else (FFA: foe1, foe2, foe3 in turn order)
var _boards := {}          # FFA: side -> {c: centre, s: card scale, p: spacing scale, rows, plate}
var _paint := {}           # the slots painted on the mat (front, back, pile), when there's a mat
var _neon := {}            # the mat whose neon stutters now and then: {mat: ShaderMaterial, zones: [{zone, at}]}
var _tense := false        # the music has turned tense (someone is close to losing)
var _out := {}             # FFA: side -> finishing place, once they're out
var _direct_btns: Array = []


func _ready() -> void:
	randomize()
	if "--autoplay" in OS.get_cmdline_user_args():
		ai_sides = ["player", "opponent"]
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	_make_resources()
	ui.theme = _make_theme()
	# The floor: the match's 1v1 arena (data/arenas.json; the server's pick online, the roulette's
	# offline; the slots are painted on it in _draw), or the old backdrop
	var bg := "res://assets/arena_1v1.png" if not _paint.is_empty() else "res://assets/duel_background.png"
	if not _paint.is_empty():
		var start_arena = Game.duel_setup.get("start", {}).get("arena") if Game.duel_setup.get("start") is Dictionary else null
		var roof = Game.duel_setup.get("rooftop")   # (tests can pick: true / false)
		var arena_id := str(start_arena) if start_arena is String else str(Game.duel_setup.get("arena", ""))
		if roof is bool:
			arena_id = "rooftop" if roof else "alley"
		elif arena_id == "" and str(Game.duel_setup.get("mode", "")) != "tutorial":
			arena_id = ArenaRoulette.random_id()
		var arena := ArenaRoulette.find(arena_id)
		if not arena.is_empty():
			bg = "res://assets/" + str(arena.image)
	if ResourceLoader.exists(bg):
		$BackLayer/Background.texture = load(bg)
		if not _paint.is_empty():
			$BackLayer/Background.modulate = Color(0.85, 0.85, 0.92)
			$BackLayer/Background.material = _alive($BackLayer/Background.texture.get_size())
			_neon = {"mat": $BackLayer/Background.material, "zones": _find_neon($BackLayer/Background.texture, _cover_point.bind($BackLayer/Background.texture.get_size()))}
	_build_detail()
	var me := Game.player
	var online_start: Dictionary = Game.duel_setup.get("start", {}) if Game.duel_setup.get("online", false) else {}
	if str(online_start.get("mode", "")) == "ffa":
		_setup_ffa_sides(online_start)
		if ResourceLoader.exists("res://assets/arena_ffa.png"):   # the crossroads, covering the screen
			var mat := TextureRect.new()
			mat.texture = load("res://assets/arena_ffa.png")
			var px := mat.texture.get_size()
			# Scaled so it covers the screen with its manhole at FFA_MID
			var k := maxf(maxf(FFA_MID.x / FFA_MANHOLE.x, (1920.0 - FFA_MID.x) / (px.x - FFA_MANHOLE.x)),
				maxf(FFA_MID.y / FFA_MANHOLE.y, (1080.0 - FFA_MID.y) / (px.y - FFA_MANHOLE.y)))
			mat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mat.position = FFA_MID - FFA_MANHOLE * k
			mat.size = px * k
			mat.modulate = Color(0.9, 0.9, 0.95)
			mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mat.material = _alive(px)
			$BackLayer.add_child(mat)
			var at := mat.position
			_neon = {"mat": mat.material, "zones": _find_neon(mat.texture, func(p: Vector2) -> Vector2: return at + p * k)}
			$BackLayer.add_child(_steam(FFA_MID))
	# Card backs players chose (achievements): a clan, or none = their deck's clan back
	_chosen_back.player = str(me.get("card_back")) if me.get("card_back") is String else ""
	if _ffa:
		for side in _foes:
			var b = online_start.get("players", {}).get(side, {}).get("card_back")
			_chosen_back[side] = str(b) if b is String else ""
	elif not online_start.is_empty():
		for pair in [["player", "you"], ["opponent", "opponent"]]:
			var prof = online_start.get(pair[1], {})
			var b = prof.get("card_back") if prof is Dictionary else null
			_chosen_back[pair[0]] = str(b) if b is String else ""
	_build_panel("player", $HUD/UI/PlayerPanel, str(me.get("username", "YOU")).to_upper().left(14),
		str(me.get("avatar_url", "")),
		"LV %d  ·  %s" % [int(me.get("level", 1)), UI.shown_title(me).to_upper()], int(me.get("level", 1)))
	if online_start.is_empty():
		var tut: bool = Game.duel_setup.get("mode") == "tutorial"
		_build_panel("opponent", $HUD/UI/OppPanel, "RIVAL" if tut else "CPU", "cpu", "TUTORIAL OPPONENT" if tut else "CPU OPPONENT")
	elif _ffa:
		$HUD/UI/OppPanel.visible = false
		_build_foe_plates(online_start.get("players", {}))
	else:
		if online_start.get("spectate", false):
			var you: Dictionary = online_start.get("you", {})
			_build_panel("player", $HUD/UI/PlayerPanel, str(you.get("username", "PLAYER")).to_upper().left(14),
				str(you.get("avatar_url")) if you.get("avatar_url") else "",
				"LV %d  ·  WATCHING" % int(you.get("level", 1)), int(you.get("level", 1)))
		var opp: Dictionary = online_start.get("opponent", {})
		var opp_title = opp.get("title")
		_build_panel("opponent", $HUD/UI/OppPanel, str(opp.get("username", "RIVAL")).to_upper().left(12),
			str(opp.get("avatar_url")) if opp.get("avatar_url") else "",
			"LV %d  ·  %s" % [int(opp.get("level", 1)), str(opp_title).to_upper() if opp_title is String and opp_title != "" else "ONLINE"], int(opp.get("level", 1)))
	_build_phase_bar()
	_build_turn_box()
	_build_log()
	# The HUD is glass: the arena shows through it
	for p in [$HUD/UI/Detail, $HUD/UI/OppPanel, $HUD/UI/PlayerPanel, $HUD/UI/PhaseBar, $HUD/UI/TurnBox]:
		UI.glass(p, Color(0.03, 0.03, 0.08, 0.66), 8.0)
	_play_music()
	_emotes_muted = not Game.settings.get("rival_emotes", true)
	_base_speed = float(Game.settings.get("anim_speed", 1.0))
	Engine.time_scale = _base_speed

	_build_post()
	_arrow = AttackArrow.new()
	_arrow.z_index = 60
	fx.add_child(_arrow)

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

	var chosen: Dictionary = Game.duel_setup
	if chosen.get("mode") == "tutorial":
		# A staged match with a coach (scripts/duel/tutorial.gd); nothing is recorded
		_tutorial = Tutorial.new()
		add_child(_tutorial)
		duel = _tutorial.make_duel(self)
		_set_morale("opponent", duel.sides.opponent.morale)   # the rival starts roughed up
	else:
		# The player's saved deck from Fight Mode (Game.duel_setup); the CPU uses the starter deck.
		var setup := DuelAI.test_setup()
		if chosen.has("deck"):
			setup.decks.player = chosen.deck
			setup.hideouts.player = chosen.get("hideout", [])
			setup.leaders.player = chosen.get("leader", "")
		duel = DuelState.new(setup.decks, setup.hideouts, setup.leaders, str(chosen.get("first", "player")))
		_start_match_session(chosen.get("ranked", false))
	_make_leader_views()
	counts = duel._counts()
	_refresh_hud()
	Sfx.play("shuffle", 1.0, -8.0)
	duel.start()
	_queue.append_array(duel.take_events())
	_pump()


func _make_leader_views() -> void:
	for side in _sides:
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
	Net.rematch_inbox.clear()
	_spectating = start.get("spectate", false)
	_names = {"player": str(start.get("you", {}).get("username", "Player")), "opponent": str(start.get("opponent", {}).get("username", "Opponent"))}
	if _ffa:
		for side in _foes:
			_names[side] = str(start.get("players", {}).get(side, {}).get("username", side))
	ai_sides = []
	_match_id = str(start.get("matchId", ""))
	duel = DuelState.new({"player": [], "opponent": []}, {}, {}, "player", -1)
	duel.load_view(start.get("view", {}))
	if not start.get("resync", false):
		Sfx.play("shuffle", 1.0, -8.0)
	_make_leader_views()
	counts = duel._counts()
	if start.get("resync", false):
		_build_from_view()
	_refresh_hud()
	if Game.duel_setup.has("replay"):
		_setup_replay(Game.duel_setup.replay)
		return
	if _spectating:
		_build_spectate_bar()
	elif not str(start.get("mode", "")).begins_with("cpu") and not _ffa:
		_build_emote_button()
	_ui.clock = _label(22, GOLD, true)
	_ui.clock.position = Vector2(150, 96)
	$HUD/UI/TurnBox.add_child(_ui.clock)
	_clock_left = float(start.get("clock", ONLINE_TURN_SECS))
	if not start.get("resync", false) and not _spectating:
		Game.alert()
	if start.get("challenge") is Dictionary and not start.get("resync", false):   # this week's twist
		_tip_panel("WEEKLY CHALLENGE  ·  %s" % str(start.challenge.get("name", "")).to_upper(), str(start.challenge.get("text", "")), RED)
	Net.opened.connect(_on_net_opened)
	Net.closed.connect(_on_net_closed)
	_after_events()


# ── Spectating (a friend's match, live) ─────────────────────────────────────

func _build_spectate_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(820, 36)
	bar.z_index = 30
	var tag := _label(28, GOLD, true)
	tag.text = "👁 WATCHING %s" % _names.player.to_upper()
	bar.add_child(tag)
	bar.add_child(UI.button("STOP WATCHING", _stop_watching, Vector2(220, 44), RED))
	ui.add_child(bar)


func _stop_watching() -> void:
	Net.send("mp:unspectate")
	Game.go("social")


## Only watching: a replay or a friend's match. Nothing can be played.
func _watching() -> bool:
	return _spectating or not _replay.is_empty()


## "YOUR TURN", or the player's name for a spectator (FFA: whose turn it is).
func _turn_text(mine: bool, side := "") -> String:
	if _ffa and not mine:
		return "%s'S TURN" % str(_names.get(side if side != "" else duel.active, "THEIR")).to_upper()
	if _spectating:
		return "%s'S TURN" % str(_names.player if mine else _names.opponent).to_upper()
	return "YOUR TURN" if mine else "OPPONENT'S TURN"


# ── Replays (routes/replays.js on the server rebuilds what you saw) ─────────

func _setup_replay(r: Dictionary) -> void:
	_replay = r
	_over = r.get("over", {})
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(820, 36)
	bar.z_index = 30
	var tag := _label(28, GOLD, true)
	tag.text = "▶ REPLAY"
	bar.add_child(tag)
	_base_speed = 1.0
	Engine.time_scale = 1.0
	bar.add_child(UI.button("◀◀ TURN", func(): _seek_turn(-1), Vector2(140, 44), BLUE))
	var speed := UI.button("SPEED 1×", func(): pass, Vector2(150, 44), BLUE)
	speed.pressed.connect(func():
		_base_speed = {1.0: 2.0, 2.0: 4.0}.get(_base_speed, 1.0)
		Engine.time_scale = _base_speed
		speed.text = "SPEED %d×" % int(_base_speed))
	bar.add_child(speed)
	bar.add_child(UI.button("TURN ▶▶", func(): _seek_turn(1), Vector2(140, 44), BLUE))
	bar.add_child(UI.button("EXIT", func(): Game.go("profile"), Vector2(120, 44), RED))
	ui.add_child(bar)
	if not r.get("complete", true):
		UI.toast(overlay, "This replay is from an older version of the game, so it stops early.", GOLD)
	_after_events()


## Feed the recorded updates one at a time, waiting for each to finish animating.
func _step_replay(delta: float) -> void:
	if _playing or not _queue.is_empty() or _mode == "over":
		return
	var updates: Array = _replay.get("updates", [])
	if _replay_seek >= 0:
		_jump_to(_replay_seek)
		_replay_seek = -1
	if _replay_next >= updates.size():
		if _mode != "over":
			_on_net_event("mp:over", _over)   # a concede or disconnect ends without a game_over event
			if _mode != "over":
				_mode = "over"
				_sweep_banner("END OF REPLAY", GOLD)
				_finish_match(false)
		return
	_replay_wait -= delta
	if _replay_wait > 0.0:
		return
	_replay_wait = REPLAY_GAP
	_on_net_event("mp:update", updates[_replay_next])
	_replay_next += 1


## The updates where a turn starts.
func _turn_starts() -> Array:
	var out: Array = []
	var updates: Array = _replay.get("updates", [])
	for i in updates.size():
		if updates[i].get("events", []).any(func(e): return e.get("type") == "turn"):
			out.append(i)
	return out


## ◀◀ goes back to the start of the turn before the one on screen, ▶▶ on to the next turn.
func _seek_turn(dir: int) -> void:
	if _mode == "over":
		return
	var starts := _turn_starts()
	var here := _replay_next - 1 if _replay_seek < 0 else _replay_seek
	var to := -1
	if dir < 0:
		for k in starts:
			if k < here:
				to = k
		to = maxi(to, 0)
	else:
		for k in starts:
			if k > here:
				to = k
				break
	if to < 0:
		UI.toast(overlay, "That's the last turn.", GOLD)
		return
	_replay_seek = to
	_queue.clear()


## Lay the board out as it was just before update `i`, then carry on playing from there.
func _jump_to(i: int) -> void:
	var updates: Array = _replay.get("updates", [])
	var view: Dictionary = _replay.start.view if i == 0 else updates[i - 1].view
	_cancel_interaction()
	_clear_attack_line()
	_hovered = null
	for side in ["player", "opponent"]:
		for v in hand[side]:
			v.queue_free()
		hand[side].clear()
		for slot in field[side]:
			field[side][slot].queue_free()
		field[side].clear()
	for side in leaders:
		leaders[side].queue_free()
	leaders.clear()
	duel.load_view(view)
	_make_leader_views()
	counts = duel._counts()
	_build_from_view()
	_refresh_hud()
	_replay_next = i
	_replay_wait = 0.0
	_log("⏩ Skipped to turn %d" % duel.turn, "")


# ── Battle log ───────────────────────────────────────────────────────────────

func _build_log() -> void:
	var b := UI.button("LOG", _toggle_log, Vector2(100, 48), GOLD)
	b.position = Vector2(440, 1004)   # left of the hand, even when it's full
	b.tooltip_text = "Battle log (L)"
	ui.add_child(b)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.98), GOLD, 2, 10))
	p.position = Vector2(20, 250)
	p.size = Vector2(560, 640)
	p.visible = false
	p.z_index = 40
	var col := VBoxContainer.new()
	p.add_child(col)
	var head := _label(26, GOLD, true)
	head.text = "BATTLE LOG"
	col.add_child(head)
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.custom_minimum_size = Vector2(530, 580)
	_log_text.add_theme_font_size_override("normal_font_size", 19)
	_log_text.add_theme_font_size_override("bold_font_size", 19)
	col.add_child(_log_text)
	ui.add_child(p)
	_ui.log = p


func _toggle_log() -> void:
	_ui.log.visible = not _ui.log.visible
	# (the log covers the card panel; hidden, its frosted glass can't show through the log)
	$HUD/UI/Detail.visible = not _ui.log.visible
	Sfx.play("click")


## A line in the battle log, coloured by whose it is ("player", "opponent" or "").
func _log(text: String, side: String) -> void:
	if _log_text == null:
		return
	var color := "#8fd3ff" if side == "player" else "#ff8a94" if side != "" else "#f4d35e"
	_log_text.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "[lb]")])
	_log_lines += 1
	if _log_lines > 400:
		_log_text.remove_paragraph(0)
		_log_lines -= 1


func _who(side: String) -> String:
	if _spectating or (_ffa and side != "player"):
		return str(_names.get(side, side))
	return "You" if side == "player" else "Opponent"


func _whose(side: String) -> String:
	if _spectating or (_ffa and side != "player"):
		return "%s's" % _names.get(side, side)
	return "Your" if side == "player" else "Opponent's"


func _cname(c) -> String:
	if not c is Dictionary or not c.has("name") or c.get("face_down", false) and not c.has("attack"):
		return "a face-down card"
	return str(c.name)


func _log_event(ev: Dictionary) -> void:
	var side: String = str(ev.get("side", ""))
	match ev.type:
		"turn":
			_log("── TURN %d · %s ──" % [int(ev.turn), _who(side).to_upper()], "")
		"mulligan":
			_log("%s redrew %d card(s)" % [_who(side), int(ev.get("count", 0))], side)
		"summon":
			if ev.card.get("face_down", false):
				_log("%s set a card face down" % _who(side), side)
			else:
				_log("%s deployed %s" % [_who(side), _cname(ev.card)], side)
		"set":
			_log("%s set a card face down" % _who(side), side)
		"shuffle":
			_log("%s deck was shuffled" % _whose(side), side)
		"hustle", "lasting":
			_log("%s %s %s" % [_who(side), "activated" if ev.get("set", false) else "played", _cname(ev.card)], side)
		"equip":
			_log("%s equipped %s" % [_who(side), _cname(ev.card)], side)
		"tribute":
			_log("%s %s %s for %s" % [_who(side), "replaced" if ev.get("replace", false) else "sacrificed", _cname(ev.card), _cname(ev.get("for"))], side)
		"attack":
			var target := "directly"
			if int(ev.target) == DuelState.LEADER:
				target = "the dormant leader"
			elif int(ev.target) >= 0:
				var tv: CardView = field.get(str(ev.get("foe", DuelState.other(side))), {}).get(int(ev.target))
				target = _cname(tv.card if tv and tv.face_up else {})
			_log("%s attacked %s" % [_cname(ev.card), target], side)
		"clash":
			if int(ev.target) >= 0:
				_log("   %d vs %d" % [int(ev.att), int(ev.def)], side)
		"flip":
			_log("%s was revealed" % _cname(ev.card), side)
		"ambush":
			_log("%s sprang %s!" % [_who(side), _cname(ev.card)], side)
		"blocked":
			_log("The attack was blocked", side)
		"downed":
			_log("%s went Down" % _cname(ev.card), side)
		"ko":
			_log("%s was %s" % [_cname(ev.card), "removed from the game" if ev.get("exiled", false) else "KO'd"], side)
		"topdeck":
			_log("%s went back on top of the deck" % _cname(ev.card), side)
		"cleanse":
			_log("%s was cleansed" % _cname(ev.card), side)
		"rewind":
			_log("%s was rewound to its printed stats" % _cname(ev.card), side)
		"jam":
			_log("%s Ambushes are JAMMED" % _whose(side), side)
		"barricade":
			if int(ev.get("held", 0)) > 0:
				_log("%s BARRICADE held off %d Morale damage" % [_whose(side), int(ev.held)], side)
			elif int(ev.amount) > 0:
				_log("%s BARRICADE: %d" % [_whose(side), int(ev.amount)], side)
		"damage":
			_log("%s lost %d Morale (%d left)" % [_who(side), int(ev.amount), int(ev.morale)], side)
		"heal":
			_log("%s gained %d Morale (%d)" % [_who(side), int(ev.amount), int(ev.morale)], side)
		"status":
			_log("%s: %s" % [_cname(ev.card), STATUS_WORDS.get(str(ev.kind), str(ev.kind).to_upper())], side)
		"status_tick":
			_log("%s: %s %d" % [_cname(ev.card), STATUS_WORDS.get(str(ev.kind), str(ev.kind).to_upper()), int(ev.get("amount", 0))], side)
		"bounce":
			_log("%s went back to the hand" % _cname(ev.card), side)
		"mill":
			_log("%s was sent from the deck to the Gutter" % _cname(ev.card), side)
		"recover":
			_log("%s got %s back from the Gutter" % [_who(side), _cname(ev.card)], side)
		"promote":
			_log("%s promoted to %s" % [_cname(ev.get("from")), _cname(ev.card)], side)
		"effect":   # ("Megan Downs Kade", not "Megan: Megan Downs Kade")
			var said := str(ev.get("text", ""))
			var who := _cname(ev.card)
			var body := said.trim_prefix(who + ": ").trim_prefix(who + " ") if said.begins_with(who) else ""
			_log(said if body != "" else "%s: %s" % [who, said], side)
		"stand":
			_log("%s stood back up" % _cname(ev.card), side)
		"discard":
			_log("%s discarded %s" % [_who(side), _cname(ev.card)], side)
		"position":
			_log("%s switched to %s" % [_cname(ev.card), "DEF" if ev.card.get("position") == "def" else "ATK"], side)
		"awaken":
			_log("%s awakened!" % _cname(ev.card), side)
		"leader_hit":
			_log("%s leader took %d" % [_whose(side), int(ev.amount)], side)
		"leader_heal":
			_log("%s leader regained %d Influence" % [_whose(side), int(ev.amount)], side)
		"leader_down":
			_log("%s leader %s fell" % [_whose(side), _cname(ev.card)], side)
		"game_over":
			_log("%s won!" % ("You" if ev.winner == "player" else "Your opponent"), str(ev.winner))
		"notice":
			var note := str(ev.text).to_lower()   # (in sentence case: "No attacks on turn 1")
			_log(note.left(1).to_upper() + note.substr(1), "")


# ── Emotes ───────────────────────────────────────────────────────────────────

func _build_emote_button() -> void:
	var b := UI.button("EMOTE", _toggle_emote_menu, Vector2(130, 48), BLUE)
	b.position = Vector2(420, 1004)
	ui.add_child(b)


func _toggle_emote_menu() -> void:
	if _ui.has("emotes") and is_instance_valid(_ui.emotes):
		_ui.emotes.queue_free()
		_ui.erase("emotes")
		return
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(INK, BLUE, 2, 10))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for e in EMOTES:
		var key: String = e[0]
		grid.add_child(UI.button(e[1], func(): _send_emote(key), Vector2(170, 46), BLUE))
	var mute := UI.button("UNMUTE RIVAL" if _emotes_muted else "MUTE RIVAL", func():
		_emotes_muted = not _emotes_muted
		_toggle_emote_menu(), Vector2(170, 46), RED)
	grid.add_child(mute)
	ui.add_child(box)
	box.reset_size()
	box.position = Vector2(420, 1000 - box.get_combined_minimum_size().y - 8)
	_ui.emotes = box


func _send_emote(key: String) -> void:
	if _ui.has("emotes") and is_instance_valid(_ui.emotes):
		_ui.emotes.queue_free()
		_ui.erase("emotes")
	if Time.get_ticks_msec() < _emote_ready_at:
		return
	_emote_ready_at = Time.get_ticks_msec() + EMOTE_GAP_MS
	Net.send("mp:emote", {"matchId": _match_id, "key": key})
	_show_emote("player", key)


## A speech bubble by the player's or the opponent's panel.
func _show_emote(side: String, key: String) -> void:
	if side == "opponent" and _emotes_muted:
		return
	var text := ""
	for e in EMOTES:
		if e[0] == key:
			text = e[1]
	if text == "":
		return
	var old: String = "emote_" + side
	if _ui.has(old) and is_instance_valid(_ui[old]):
		_ui[old].queue_free()
	var bubble := PanelContainer.new()
	var accent := BLUE if side == "player" else RED
	bubble.add_theme_stylebox_override("panel", _box(Color(0.96, 0.96, 1.0, 0.97), accent, 3, 14))
	var l := _label(26, Color("101020"), true)
	l.text = text
	bubble.add_child(l)
	ui.add_child(bubble)
	bubble.reset_size()
	var sz := bubble.get_combined_minimum_size()
	bubble.position = Vector2(40, 760 - sz.y) if side == "player" else Vector2(1896 - sz.x, 242)
	bubble.pivot_offset = Vector2(0 if side == "player" else sz.x, sz.y if side == "player" else 0.0)
	bubble.scale = Vector2.ONE * 0.4
	_ui[old] = bubble
	Sfx.play("click", 1.25 if side == "player" else 0.9)
	var t := bubble.create_tween()
	t.tween_property(bubble, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.4)
	t.tween_property(bubble, "modulate:a", 0.0, 0.4)
	t.tween_callback(bubble.queue_free)


## Rejoining a match (reconnect or correction): lay the board out straight from the view.
func _build_from_view() -> void:
	for side in _sides:
		var s: Dictionary = duel.sides[side]
		for c in s.hand:
			var hv := _new_view(c, side, side == "player" and not _spectating)
			hand[side].append(hv)
		_layout_hand(side)
		for v in hand[side]:
			v.position = v.home
			v.scale = Vector2.ONE * v.home_scale * v.board_scale
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
					v.statuses = duel.statuses(c)
			field[side][slot] = v
		var p: Dictionary = _panels[side]
		p.shown = float(s.morale)
		p.morale.text = str(int(s.morale))
		p.bar.size.x = p.bar.get_parent().size.x * clampf(float(s.morale) / DuelState.START_MORALE, 0.0, 1.0)
	_ui.turn_num.text = "TURN %d" % duel.turn
	_ui.turn_who.text = _turn_text(duel.active == "player")
	_set_phase_ui(duel.phase)


func _on_net_event(name: String, data) -> void:
	if not data is Dictionary or str(data.get("matchId", _match_id)) != _match_id:
		return
	match name:
		"mp:update", "ffa:update":
			duel.load_view(data.view)
			_awaiting = false
			_clock_left = float(data.get("clock", ONLINE_TURN_SECS))
			_on_away(data.get("away", false))
			_queue.append_array(data.events)
			_pump()
		"mp:over":
			_over = data
			if str(data.get("reason", "")) != "morale" and _mode != "over":
				_mode = "over"
				_cancel_interaction()
				var won: bool = data.get("result") == "win"
				var why: String = {"concede": "CONCEDED", "disconnect": "DISCONNECTED", "afk": "WENT AWAY"}.get(str(data.reason), "LEFT")
				_log("%s %s" % ["Your opponent" if won else "You", why.to_lower()], "opponent" if won else "player")
				var who := ("OPPONENT " if won else "YOU ") if not _spectating else "%s " % str(_names.opponent if won else _names.player).to_upper()
				_sweep_banner(who + why, GOLD if won else RED)
				await _wait(1.6)
				_finish_match(won)
		"ffa:over":
			_over = data
		"ffa:out":
			_over = data
			_show_out_panel(data)
		"mp:emote":
			_show_emote("opponent", str(data.get("key", "")))
		"mp:spectators":
			if not _ui.has("watchers"):
				_ui.watchers = _label(20, Color(1, 1, 1, 0.75), true)
				_ui.watchers.position = Vector2(1400, 1040)
				ui.add_child(_ui.watchers)
			var n := int(data.get("count", 0))
			_ui.watchers.text = "" if n == 0 else "👁 %d WATCHING" % n
		"mp:opponent":
			if data.get("status") == "disconnected":
				_show_net_banner("OPPONENT DISCONNECTED — THEY HAVE %ds TO RETURN" % int(data.get("graceSecs", 45)))
			else:
				_hide_net_banner()
				UI.toast(overlay, "Your opponent is back.", BLUE)


## The server played a move for whoever has to act (they let their clock run out): from now on
## they get a short clock, and lose if they keep not playing (backend/socket/onlineMatch.js).
func _on_away(away: bool) -> void:
	var side: String = duel.pending.side if not duel.pending.is_empty() else duel.active
	_ui.away = away
	if not away:
		_away_warned = false
		return
	if side == "player" and not _away_warned and not _spectating:
		_away_warned = true
		Game.alert()
		UI.toast(overlay, "A move was played for you. Keep playing, or you'll lose for being away.", RED)


## Net calls this when the server (re)sends the whole match, e.g. after a reconnect.
func on_online_start(_data: Dictionary) -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func on_online_error(message: String) -> void:
	_awaiting = false
	UI.toast(overlay, message, RED)


func _on_net_opened() -> void:
	_hide_net_banner()
	Net.send("ffa:resync" if _ffa else "mp:resync")


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
	_game_time += delta
	if _shake > 0.3:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0))
	else:
		camera.offset = Vector2.ZERO
	_update_post()
	_update_aim()
	_update_pile_backs(delta)
	if _tutorial:
		_tutorial.update()
	if _ui.has("detail_art"):
		# The featured card floats gently, catching the light
		var tm := Time.get_ticks_msec() / 1000.0
		var m: ShaderMaterial = _ui.detail_art.material
		m.set_shader_parameter("y_rot", sin(tm * 0.7) * 7.0)
		m.set_shader_parameter("x_rot", cos(tm * 0.55) * 4.0)
		m.set_shader_parameter("glare", 0.35 + 0.25 * sin(tm * 0.7))
		if _detail_spin != "":   # a hovered back turns at the field's hover speed
			_detail_angle = fmod(_detail_angle + CardView.BACK_SPEEDS[_detail_spin][1] * delta, TAU)
			m.set_shader_parameter("galaxy_angle", _detail_angle)
			m.set_shader_parameter("galaxy_glow", 0.8)
	if not _valid.is_empty():
		queue_redraw()
	if _dragging and _press:
		_press.position = _press.position.lerp(get_global_mouse_position(), minf(1.0, delta * 25.0))
	if not _replay.is_empty():
		_step_replay(delta)
	elif _online:
		while not Net.inbox.is_empty():
			var msg: Array = Net.inbox.pop_front()
			_on_net_event(msg[0], msg[1])
		# Whoever has to act has the server's clock (data.clock) before it plays a safe move for them
		if duel.winner == "" and _mode != "over" and _ui.has("clock"):
			_clock_left = maxf(0.0, _clock_left - delta / maxf(Engine.time_scale, 0.01))   # real seconds
			_ui.clock.text = "⏱ %d%s" % [ceili(_clock_left), "  AWAY" if _ui.get("away", false) else ""]
			_ui.clock.label_settings.font_color = RED if _clock_left < 15.0 else GOLD


# ── Board geometry ───────────────────────────────────────────────────────────

func slot_pos(side: String, slot: int) -> Vector2:
	var col := slot % 5
	if _row_side(side) != "player":
		col = 4 - col   # mirrored, like sitting across the table
	return _xf(side, Vector2(COLS[col], ROWS[_row_side(side)][0 if slot < 5 else 1]))


func pile_pos(side: String, pile: String) -> Vector2:
	var mine := _row_side(side) == "player"
	var near := LEFT_X if mine else RIGHT_X   # leader + hideout
	var far := RIGHT_X if mine else LEFT_X    # gutter + deck
	var rows: Array = ROWS[_row_side(side)]
	match pile:
		"leader":
			return _xf(side, Vector2(near, rows[0]))
		"hideout":
			return _xf(side, Vector2(near, rows[1]))
		"gutter":
			return _xf(side, Vector2(far, rows[0]))
	return _xf(side, Vector2(far, rows[1]))


## Where a side's rows are laid out: yours, or the opponent's (FFA: the boards on the bottom row
## are laid out like yours).
func _row_side(side: String) -> String:
	return str(_boards.get(side, {}).get("rows", "player" if side == "player" else "opponent"))


## FFA: a point on the 1v1 board (yours, or the opponent's) → the same point on this side's board in the grid.
func _xf(side: String, p: Vector2) -> Vector2:
	var b: Dictionary = _boards.get(side, {})
	if b.is_empty():
		return p
	return b.c + (p - (PLAYER_C if _row_side(side) == "player" else OPP_C)) * (b.get("p", Vector2.ONE * float(b.s)) as Vector2)


## How big this side's board is drawn (FFA opponents' are smaller).
func _sc(side: String) -> float:
	return float(_boards.get(side, {}).get("s", 1.0))


## The area a side's board covers (its piles, lanes and leader).
func _board_rect(side: String) -> Rect2:
	var rows: Array = ROWS[_row_side(side)]
	var top := minf(rows[0], rows[1]) - CARD.y / 2
	var bottom := maxf(rows[0], rows[1]) + CARD.y / 2
	var a := _xf(side, Vector2(LEFT_X - CARD.x / 2, top))
	var b := _xf(side, Vector2(RIGHT_X + CARD.x / 2, bottom))
	return Rect2(a, b - a)


func _target_pos(side: String, slot: int) -> Vector2:
	if slot == DuelState.LEADER:
		return pile_pos(side, "leader")
	if slot >= 0:
		return slot_pos(side, slot)
	# A direct attack hits the player: their Morale panel (not a card that happens to be in the middle lane)
	if _panels.has(side):
		var root: Control = _panels[side].root
		if _ffa and side != "player":
			return root.position + root.size / 2
		return get_viewport().get_canvas_transform().affine_inverse() * root.get_global_rect().get_center()
	return _xf(side, Vector2(1080, ROWS[_row_side(side)][0]))


func _slot_at(side: String, p: Vector2) -> int:
	var size := CARD * _sc(side)
	for slot in 10:
		if Rect2(slot_pos(side, slot) - size / 2, size).grow(10).has_point(p):
			return slot
	return -1


func _draw() -> void:
	if not _ffa:
		draw_line(Vector2(560, DIVIDER_Y), Vector2(1600, DIVIDER_Y), Color(1, 1, 1, 0.14), 2.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	for side in _sides:
		var size := CARD * _sc(side)
		if not _paint.is_empty():
			_draw_paint(Rect2(pile_pos(side, "leader") - size / 2, size), "pile", _sc(side))
		for slot in 10:
			var r := Rect2(slot_pos(side, slot) - size / 2, size)
			if _paint.is_empty():
				draw_style_box(_slot_box if slot < 5 else _slot_box_back, r)
			else:
				_draw_paint(r, "front" if slot < 5 else "back", _sc(side))
			var key := "%s:%d" % [side, slot]
			if _valid.has(key):
				var c: Color = _valid[key]
				draw_rect(r, Color(c, 0.2 * pulse))
				draw_rect(r.grow(4), Color(c, 0.95 * pulse), false, 4.0)
				if bool(Game.settings.get("glow_symbols", false)):
					_draw_slot_symbol(r.get_center(), c, side)
		for pile in ["deck", "gutter", "hideout"]:
			_draw_pile(side, pile)
		_draw_zone_label(pile_pos(side, "leader"), "LEADER", _sc(side))
		if _out.has(side):   # FFA: out of the game
			var area := _board_rect(side)
			draw_rect(area, Color(0.02, 0.02, 0.05, 0.72))
			var fs := int(64 * _sc(side))
			var text := "OUT · %s" % _place_text(int(_out[side]))
			var at := Vector2(area.position.x, area.get_center().y + fs * 0.35)
			draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, 10, Color(0, 0, 0, 0.9))
			draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, RED)


## Colour-blind help (Settings): what a highlighted lane is for, as a shape. Green +: put a card
## here; orange arrows: deploy over this one; red X: sacrifice it (yours) or a crosshair: attack
## it (theirs); purple tick: chosen; gold ring: choose it.
func _draw_slot_symbol(at: Vector2, c: Color, side: String) -> void:
	draw_circle(at, 24.0, Color(0.03, 0.03, 0.08, 0.85))
	draw_arc(at, 24.0, 0.0, TAU, 32, c, 3.0, true)
	var ink := Color.WHITE
	if c == GREEN:
		draw_line(at + Vector2(-11, 0), at + Vector2(11, 0), ink, 4.0)
		draw_line(at + Vector2(0, -11), at + Vector2(0, 11), ink, 4.0)
	elif c == SWAP:
		for d: float in [-1.0, 1.0]:   # two arrows passing each other
			var y := d * 6.0
			draw_line(at + Vector2(-11 * d, y), at + Vector2(11 * d, y), ink, 3.0)
			draw_line(at + Vector2(11 * d, y), at + Vector2(5 * d, y - 5), ink, 3.0)
			draw_line(at + Vector2(11 * d, y), at + Vector2(5 * d, y + 5), ink, 3.0)
	elif c == RED and side == "player":
		draw_line(at + Vector2(-9, -9), at + Vector2(9, 9), ink, 4.0)
		draw_line(at + Vector2(-9, 9), at + Vector2(9, -9), ink, 4.0)
	elif c == RED:
		draw_arc(at, 11.0, 0.0, TAU, 24, ink, 2.5, true)
		draw_line(at + Vector2(-16, 0), at + Vector2(16, 0), ink, 2.5)
		draw_line(at + Vector2(0, -16), at + Vector2(0, 16), ink, 2.5)
	elif c == PICKED:
		draw_polyline(PackedVector2Array([at + Vector2(-10, 1), at + Vector2(-3, 8), at + Vector2(11, -8)]), ink, 4.0, true)
	else:
		draw_arc(at, 10.0, 0.0, TAU, 24, ink, 3.0, true)
		draw_circle(at, 3.5, ink)


## A mat's living layer (shaders/mat_alive.gdshader): its neon pulses and flickers, a wet sheen
## drifts, rain rings spread and a haze rolls across.
func _alive(tex_size: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/mat_alive.gdshader")
	m.set_shader_parameter("tex_size", tex_size)
	return m


## Where a point of the full-screen mat image is on the screen (it covers the screen, cropped).
static func _cover_point(p: Vector2, tex_size: Vector2) -> Vector2:
	var k := maxf(1920.0 / tex_size.x, 1080.0 / tex_size.y)
	return p * k - (tex_size * k - Vector2(1920, 1080)) / 2.0


## The mat's neon: the 160 px patches of the image with lit tubes in them (bright, saturated
## pixels), and where each is on the screen; only ones between the side panels.
func _find_neon(tex: Texture2D, to_screen: Callable) -> Array:
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		return []   # (headless)
	if img.is_compressed():
		img.decompress()
	var out: Array = []
	var zone := 160
	for zy in range(0, img.get_height(), zone):
		for zx in range(0, img.get_width(), zone):
			var lit := 0
			var n := 0
			for y in range(zy, mini(zy + zone, img.get_height()), 8):
				for x in range(zx, mini(zx + zone, img.get_width()), 8):
					var c := img.get_pixel(x, y)
					n += 1
					if c.v > 0.55 and c.s > 0.45:
						lit += 1
			if n == 0 or float(lit) / n < 0.05:
				continue
			var at: Vector2 = to_screen.call(Vector2(zx + zone / 2.0, zy + zone / 2.0))
			if at.x > 420.0 and at.x < 1650.0 and at.y > -40.0 and at.y < 1120.0:
				out.append({"zone": Vector2(zx / zone, zy / zone), "at": at})
	return out


## Now and then one of the mat's neon lights stutters, buzzing from where it is.
func _neon_loop() -> void:
	while is_inside_tree() and not _neon.is_empty() and not (_neon.zones as Array).is_empty():
		await get_tree().create_timer(randf_range(5.0, 12.0), true, false, true).timeout
		if not is_inside_tree():
			return
		var z: Dictionary = (_neon.zones as Array).pick_random()
		var m: ShaderMaterial = _neon.mat
		m.set_shader_parameter("stutter_zone", z.zone)
		Sfx.play_at("neon_buzz", z.at, self, -8.0, randf_range(0.94, 1.06))
		var t := create_tween().set_ignore_time_scale(true)
		t.tween_method(func(k: float): m.set_shader_parameter("stutter_k", k), 0.0, 1.0, 0.7)
		t.tween_callback(func(): m.set_shader_parameter("stutter_k", -1.0))


## The music turns tense once someone still in is down to a third of their Morale.
func _tension() -> void:
	if _tense or _mode == "over" or duel == null:
		return
	for side in _sides:
		if not _out.has(side) and duel.sides.has(side) and int(duel.sides[side].get("morale", DuelState.START_MORALE)) <= DuelState.START_MORALE / 3:
			_tense = true
			if Game.sound.has_track("duel_tense"):
				Game.sound.music("duel_tense", 2.5)
			return


## Steam rising from a manhole (soft puffs that grow, drift and fade).
func _steam(at: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 26
	p.lifetime = 4.0
	p.preprocess = 4.0   # (already steaming when the duel opens)
	var dot := GradientTexture2D.new()
	dot.width = 64
	dot.height = 64
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = soft
	p.texture = dot
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 16.0
	p.direction = Vector2(0.15, -1.0)
	p.spread = 22.0
	p.gravity = Vector2(6, -10)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 28.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	var grow := Curve.new()
	grow.max_value = 2.5
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.2))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.76, 0.95, 0.0))
	fade.set_color(1, Color(0.8, 0.76, 0.95, 0.0))
	fade.add_point(0.25, Color(0.8, 0.76, 0.95, 0.2))
	p.color_ramp = fade
	return p


## A slot painted on the mat: the paint (arena_paint.png) nine-sliced at its own scale.
func _draw_paint(r: Rect2, kind: String, k: float) -> void:
	var f := PAINT_K * k
	draw_set_transform(r.position, 0.0, Vector2(f, f))
	draw_style_box(_paint[kind], Rect2(Vector2.ZERO, r.size / f))
	draw_set_transform(Vector2.ZERO)


func _draw_pile(side: String, pile: String) -> void:
	var p := pile_pos(side, pile)
	var k := _sc(side)
	var size := CARD * k
	if _paint.is_empty():
		draw_style_box(_pile_box, Rect2(p - size / 2, size))
	else:
		_draw_paint(Rect2(p - size / 2, size), "pile", k)
	var c: Dictionary = counts.get(side, {})
	var n: int = c.get(pile, 0)
	if n <= 0:
		_draw_zone_label(p, pile.to_upper(), k)
		return
	var layers := mini(4, ceili(n / 8.0))
	var back := _back_for(side)
	for i in layers:
		var off := Vector2(-i * 2.0, -i * 3.0) * k
		var r := Rect2(p - size / 2 + off, size)
		var tex := back
		if i == layers - 1 and pile == "gutter":
			tex = CardDB.art(str(c.get("gutter_top", "")))
		if tex:
			draw_texture_rect(tex, r, false, Color(1, 1, 1) if i == layers - 1 else Color(0.55, 0.55, 0.6))
		else:
			draw_rect(r, Color("1d2140"))
			draw_rect(r, Color(1, 1, 1, 0.3), false, 2.0)
	if not _pile_backs.has("%s:%s" % [side, pile]):   # (a moving back has its count and name drawn over it)
		_draw_pile_text(self, side, pile)


## The deck and Hideout wear the side's moving back on top (like a face-down card): it turns
## slowly, and speeds up and glows while hovered. Their count and name are drawn over it.
func _update_pile_backs(delta: float) -> void:
	var m := get_global_mouse_position()
	for side in _sides:
		var style := CardDB.back_style(_back_clan(side))
		if not CardView.BACK_SPEEDS.has(style):
			continue
		for pile in ["deck", "hideout"]:
			var key := "%s:%s" % [side, pile]
			var n: int = counts.get(side, {}).get(pile, 0)
			if not _pile_backs.has(key):
				if n <= 0:
					continue
				_pile_backs[key] = _new_pile_back(side, style)
			var b: Dictionary = _pile_backs[key]
			var k := _sc(side)
			var size := CARD * k
			var layers := mini(4, ceili(n / 8.0))
			var r: TextureRect = b.rect
			r.visible = n > 0
			r.position = pile_pos(side, pile) - size / 2 + Vector2(-(layers - 1) * 2.0, -(layers - 1) * 3.0) * k
			r.size = size
			var want: float = b.hover if r.visible and Rect2(r.position, size).has_point(m) else b.idle
			b.speed = lerpf(b.speed, want, 1.0 - exp(-4.0 * delta))
			b.angle = fmod(b.angle + b.speed * delta, TAU)
			b.mat.set_shader_parameter("galaxy_angle", b.angle)
			b.mat.set_shader_parameter("galaxy_glow", clampf((b.speed - b.idle) / (b.hover - b.idle), 0.0, 1.0))
	if _pile_ink:
		_pile_ink.queue_redraw()


func _new_pile_back(side: String, style: String) -> Dictionary:
	var r := TextureRect.new()
	r.texture = _back_for(side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := UI.card_material(CARD * _sc(side))
	mat.set_shader_parameter(style, 1.0)
	r.material = mat
	add_child(r)
	move_child(r, cards_layer.get_index())   # (under the cards, over the board)
	if _pile_ink == null:
		_pile_ink = Node2D.new()
		_pile_ink.draw.connect(func():
			for key in _pile_backs:
				if _pile_backs[key].rect.visible:
					var part: PackedStringArray = str(key).split(":")
					_draw_pile_text(_pile_ink, part[0], part[1]))
		add_child(_pile_ink)
	move_child(_pile_ink, cards_layer.get_index())
	var speeds: Array = CardView.BACK_SPEEDS[style]
	return {"rect": r, "mat": mat, "angle": randf() * TAU, "speed": speeds[0], "idle": speeds[0], "hover": speeds[1]}


## A pile's count and name (on: the board, or the layer over the moving backs).
func _draw_pile_text(on: CanvasItem, side: String, pile: String) -> void:
	var p := pile_pos(side, pile)
	var k := _sc(side)
	var n: int = counts.get(side, {}).get(pile, 0)
	var at := Vector2(p.x - 60, p.y + 16 * k)
	on.draw_string_outline(_font, at, str(n), HORIZONTAL_ALIGNMENT_CENTER, 120, int(46 * k), 10, Color(0, 0, 0, 0.9))
	on.draw_string(_font, at, str(n), HORIZONTAL_ALIGNMENT_CENTER, 120, int(46 * k), RED if pile == "deck" and n <= 5 else Color.WHITE)
	_draw_zone_label(p, pile.to_upper(), k, on)


## Zone name on a dark strip along the bottom of the zone (stays readable over pile art).
func _draw_zone_label(p: Vector2, text: String, k := 1.0, on: CanvasItem = null) -> void:
	var c: CanvasItem = on if on else self
	var w := CARD.x * k
	var strip := Rect2(p.x - w / 2, p.y + CARD.y * k / 2 - 24 * k, w, 24 * k)
	c.draw_rect(strip, Color(0, 0, 0, 0.6))
	c.draw_string(_font, Vector2(strip.position.x, strip.position.y + 18 * k), text, HORIZONTAL_ALIGNMENT_CENTER,
		w, maxi(8, int(16 * k)), Color(1, 1, 1, 0.7))


# ── Event playback ───────────────────────────────────────────────────────────

func _act(side: String, action: Dictionary) -> bool:
	if _watching():
		return false   # a replay or a friend's match
	if _tutorial and side == "player" and not _tutorial.allow(action):
		return false
	if _online:
		# The server applies the move and sends back what happened (mp:update)
		if _awaiting or side != "player" or not Net.send("ffa:action" if _ffa else "mp:action", {"matchId": _match_id, "action": action}):
			return false
		_awaiting = true
		_clear_highlights()
		_update_next_btn()
		return true
	if not duel.do_action(side, action):
		if side == "player":
			Sfx.play("error", 1.0, -4.0)
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
		_pace()
		await _play(ev)
		counts = ev.counts
		_refresh_hud()
	_playing = false
	_after_events()


func _after_events() -> void:
	if duel.winner != "":
		return
	var side: String = duel.pending.side if not duel.pending.is_empty() else duel.active
	if _watching():
		_clear_highlights()
		return
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
		var a: Dictionary = _tutorial.opponent_move() if _tutorial and side == "opponent" else {}
		if a.is_empty():
			a = DuelAI.choose(duel, side, str(Game.duel_setup.get("difficulty", "normal")))
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
			if ev.side == "player" and not ev.get("set", false):
				_cards_played += 1
		"clash":
			var v: CardView = field[ev.side].get(ev.from)
			_last_hit = {"side": ev.side, "card": v.card if v else {}}
		"damage":
			if not _last_hit.is_empty() and _last_hit.side != ev.side and not _last_hit.card.is_empty():
				var key := "%s:%s" % [_last_hit.side, _last_hit.card.get("uid", 0)]
				var entry: Dictionary = _damage_log.get(key, {"card": _last_hit.card, "owner": _last_hit.side, "damage": 0, "kos": 0})
				entry.damage += int(ev.amount)
				_damage_log[key] = entry
		"ko":   # (the MVP's KOs: the card whose brawl it was)
			if not _last_hit.is_empty() and _last_hit.side != ev.side and not _last_hit.card.is_empty():
				var key := "%s:%s" % [_last_hit.side, _last_hit.card.get("uid", 0)]
				var entry: Dictionary = _damage_log.get(key, {"card": _last_hit.card, "owner": _last_hit.side, "damage": 0, "kos": 0})
				entry.kos = int(entry.get("kos", 0)) + 1
				_damage_log[key] = entry
		"attack", "turn":
			_last_hit = {}


func _play(ev: Dictionary) -> void:
	if ev.type == "effect" and ev.has("public_text") and ev.side != "player":
		ev = ev.duplicate()   # (another player's search, in a game run here: what it found stays hidden)
		ev.text = ev.public_text
	_track(ev)
	_log_event(ev)
	match ev.type:
		"draw":
			await _ev_draw(ev)
		"mulligan":
			await _ev_mulligan(ev)
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
		"shuffle":
			await _ev_shuffle(ev)
		"hustle":
			await _ev_hustle(ev)
		"lasting":
			await _ev_lasting(ev)
		"equip":
			await _ev_equip(ev)
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
		"heal":
			await _ev_heal(ev)
		"tribute":
			await _ev_tribute(ev)
		"status":
			await _ev_status(ev)
		"status_tick":
			await _ev_status_tick(ev)
		"bounce":
			await _ev_bounce(ev)
		"topdeck":
			await _ev_topdeck(ev)
		"cleanse":
			await _ev_cleanse(ev)
		"rewind":
			await _ev_rewind(ev)
		"jam":
			await _ev_jam(ev)
		"barricade":
			await _ev_barricade(ev)
		"mill":
			await _ev_mill(ev)
		"recover":
			await _ev_recover(ev)
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
		"luck":
			await _ev_luck(ev)
		"leader_hit":
			await _ev_leader_hit(ev)
		"leader_heal":
			await _ev_leader_heal(ev)
		"leader_down":
			await _ev_leader_down(ev)
		"eliminated":
			await _ev_eliminated(ev)
		"prompt":
			if ev.side != "player" or ev.side in ai_sides:
				var who: String = ("%s IS DECIDING…" % str(_names.get(ev.side, "OPPONENT")).to_upper()) if _ffa \
					else "OPPONENT IS DECIDING…" if _online else "CPU IS DECIDING…"
				var out_up: bool = _ui.has("out_panel") and is_instance_valid(_ui.out_panel)
				_float_text(Vector2(1080, DIVIDER_Y - (170 if out_up else 0)), who, Color(1, 1, 1, 0.8), 30)
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
	var end_scale: float = v.home_scale
	var t := create_tween()
	t.tween_method(func(k: float):
		v.position = start.lerp(v.home, k) + Vector2(0, -110.0 * sin(PI * k) * v.board_scale)
		v.scale = Vector2.ONE * lerpf(1.0, end_scale, k) * v.board_scale
	, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if side == "player" and not _spectating:
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


## A redrawn opening hand: the cards sweep back into the deck (the new ones arrive as draws).
func _ev_mulligan(ev: Dictionary) -> void:
	var side: String = ev.side
	var mine := side == "player"
	Sfx.play("whoosh", 0.9)
	_float_text(Vector2(1080, DIVIDER_Y), "NEW HAND" if mine else ("%s REDRAWS" % str(_names.get(side, "OPPONENT")).to_upper() if _ffa else "OPPONENT REDRAWS"), BLUE if mine else RED, 40)
	var views: Array = hand[side].duplicate()
	hand[side].clear()
	for v in views:
		if v == _hovered:
			_hovered = null
		v.busy = true
		v.z_index = 400
		if v.face_up:
			v.flip(false)
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(v, "position", pile_pos(side, "deck"), 0.3)
		t.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.3)
		t.chain().tween_callback(v.queue_free)
		await _wait(0.05)
	await _wait(0.35)


func _ev_turn(ev: Dictionary) -> void:
	var mine: bool = ev.side == "player"
	_cancel_interaction()
	_ui.turn_num.text = "TURN %d" % ev.turn
	_ui.turn_who.text = _turn_text(mine, ev.side)
	_ui.turn_who.label_settings.font_color = BLUE if mine else _side_color(ev.side)
	Sfx.play("turn_yours" if mine else "turn_theirs")
	# A Downed look the rules no longer have goes (only cleared here: the rules may be ahead of
	# what is shown, and a card about to be Downed gets its look from that event)
	for side in field:
		for slot in field[side]:
			var c = duel.card_at(side, slot) if slot < 5 else null
			var v = field[side][slot]
			if is_instance_valid(v) and v.downed and not (c is Dictionary and c.get("downed", false)):
				v.downed = false
	if mine and not _watching():
		Game.alert(false)
	await _sweep_banner(_turn_text(mine, ev.side), BLUE if mine else _side_color(ev.side))


func _ev_phase(ev: Dictionary) -> void:
	_set_phase_ui(ev.phase)
	if not PHASE_NAMES.has(ev.phase):
		return
	Sfx.play("phase_" + str(ev.phase), 1.0, -2.0)
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
	var target := slot_pos(side, slot)
	var v: CardView
	match str(ev.get("from", "")):
		"deck":   # called in from the deck
			v = _new_view(c, side, false)
			v.position = pile_pos(side, "deck")
		"token":   # made by an effect: it fades in where it stands
			v = _new_view(c, side, true)
			v.position = target
			v.modulate.a = 0.0
			create_tween().tween_property(v, "modulate:a", 1.0, 0.3)
			_ring(target, _clan_color(c), 0.9)
		_:
			v = _take_from_hand(side, c.uid, c)
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
		var heavy: bool = c.authority >= 6 or int(c.get("rarity", 1)) >= 5
		_show_detail(c)
		if int(c.get("rarity", 1)) >= 5:   # a Legendary makes an entrance
			if not v.face_up:
				v.flip(true)
			await _legendary_entrance(v, c)
		elif heavy:
			_dim(0.6, 0.2)
			if not v.face_up:
				v.flip(true)
			await _showcase(v, c, BLUE if side == "player" else RED)
		elif not v.face_up:
			v.flip(true)
		if _clan_style(c, "summon") == "warp":
			await _warp_in(v, target, _clan_color(c), heavy)
		elif _clan_style(c, "summon") == "airdrop":
			await _airdrop(v, target, _clan_color(c), heavy)
		else:
			var rise := Vector2(0, -70 if side == "player" else 70)
			await v.move_to(target + rise, 1.75, v.home_rot, 0.3 if heavy else 0.24).finished
			if heavy:
				_cam_focus(target, 1.07, 0.3)
			await _wait(0.16 if heavy else 0.05)
			await v.move_to(target, 1.0, v.home_rot, 0.1, Tween.TRANS_QUAD, Tween.EASE_IN).finished
			v.kick(Vector2(0, 1 if side == "player" else -1), 16.0)
			await _impact(target, heavy)
			if heavy:
				_cam_reset(0.45)
				_dim(0.0, 0.35)
	if absf(v.rotation - v.home_rot) > 0.01:   # summoned in DEF: lay it sideways
		await v.move_to(target, 1.0, v.home_rot, 0.2, Tween.TRANS_BACK).finished
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


## A searched deck is shuffled: a few backs riffle out of the deck pile and back in.
func _ev_shuffle(ev: Dictionary) -> void:
	var side: String = ev.side
	var at := pile_pos(side, "deck")
	var k := _sc(side)
	var backs: Array = []
	for i in 3:
		var v := _new_view({}, side, false)
		v.position = at
		v.z_index = 40 + i
		backs.append(v)
	Sfx.play("shuffle", 1.1, -4.0)
	for i in backs.size():
		var v: CardView = backs[i]
		v.move_to(at + Vector2((i - 1) * 46.0 * k, -14.0 * k), 1.0, (i - 1) * 0.12, 0.12)
	await _wait(0.16)
	Sfx.play("shuffle", 1.3, -6.0)
	for v in backs:
		v.move_to(at, 1.0, 0.0, 0.14)
	_float_text(at + Vector2(0, -CARD.y * k * 0.7), "SHUFFLED", BLUE, int(maxf(18.0, 26.0 * k)))
	await _wait(0.18)
	for v in backs:
		v.queue_free()


## A Hustle activated where it was set face-down in the back row: its card, now shown.
func _from_set(ev: Dictionary) -> CardView:
	var side: String = ev.side
	var v: CardView = field[side].get(int(ev.slot))
	field[side].erase(int(ev.slot))
	if v == null:
		v = _new_view(ev.card, side, false)
		v.position = slot_pos(side, int(ev.slot))
	v.set_card(ev.card)
	return v


func _ev_hustle(ev: Dictionary) -> void:
	var side: String = ev.side
	var c: Dictionary = ev.card
	var v := _from_set(ev) if ev.get("set", false) else _take_from_hand(side, c.uid, c)
	v.z_index = 450
	_show_detail(c)
	if not v.face_up:
		v.flip(true)
	var center := Vector2(1080, DIVIDER_Y)
	var legendary := int(c.get("rarity", 1)) >= 5
	if legendary:
		await _legendary_entrance(v, c)
	Sfx.play("effect", 0.8)
	await v.move_to(center, 2.1, 0.0, 0.3, Tween.TRANS_BACK).finished
	if legendary:
		_dim(0.0, 0.35)
	_ring(center, BLUE, 1.5)
	_burst(center, BLUE, 32, 420, 0.8, -250.0)
	_float_text(center + Vector2(0, 215), "HUSTLE", BLUE, 40)
	await _wait(0.75)
	await _to_gutter(v, side)


## A Continuous / Equip Hustle: shown, then it takes its place face-up in the back row.
func _ev_lasting(ev: Dictionary) -> void:
	var side: String = ev.side
	var c: Dictionary = ev.card
	var v := _from_set(ev) if ev.get("set", false) else _take_from_hand(side, c.uid, c)
	var target := slot_pos(side, ev.slot)
	field[side][ev.slot] = v
	v.home = target
	v.home_scale = 1.0
	v.home_rot = 0.0
	v.z_index = 450
	_show_detail(c)
	if not v.face_up:
		v.flip(true)
	var center := Vector2(1080, DIVIDER_Y)
	Sfx.play("effect", 0.8)
	await v.move_to(center, 2.1, 0.0, 0.3, Tween.TRANS_BACK).finished
	_ring(center, GOLD, 1.5)
	_float_text(center + Vector2(0, 215), "EQUIP" if str(c.get("subtype", "")) == "equip" else "CONTINUOUS", GOLD, 40)
	await _wait(0.6)
	await v.move_to(target, 1.0, 0.0, 0.3).finished
	_ring(target, GOLD, 0.8)
	v.z_index = 10


## An Equip attaches to a character: a beam from the card to it.
func _ev_equip(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	var t: CardView = field[str(ev.target_side)].get(int(ev.target_slot))
	if v == null or t == null:
		return
	Sfx.play("promote", 1.2, -6.0)
	_burst(t.home, GOLD, 28, 300, 0.7, -260.0)
	_ring(t.home, GOLD, 1.1)
	_float_text(t.home + Vector2(0, -120 if ev.target_side == "player" else 120), "EQUIPPED", GOLD, 32)
	await _wait(0.4)


func _ev_attack(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.from)
	if v == null:
		return
	var tpos := _target_pos(str(ev.get("foe", DuelState.other(side))), ev.target)
	_arrow.show_attack(v.home, tpos, RED)
	Sfx.play("whoosh", 0.7)
	v.z_index = 430
	v.move_to(v.home, 1.15, v.home_rot, 0.16)
	v.kick(-(tpos - v.home), 10.0)
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
	_shockwave(center, 0.7)
	_post_pulse("aberration", 9.0, 0.35)
	_float_text(center + Vector2(0, -200), "AMBUSH!", RED, 64)
	await _wait(0.8)
	if ev.get("stays", false):   # a Continuous Ambush goes back to its place, face-up
		field[side][ev.slot] = v
		v.home = slot_pos(side, ev.slot)
		await v.move_to(v.home, 1.0, 0.0, 0.3).finished
		v.z_index = 10
		return
	await _to_gutter(v, side)


func _ev_clash(ev: Dictionary) -> void:
	var side: String = ev.side
	var foe := str(ev.get("foe", DuelState.other(side)))
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
		_float_text(tpos + Vector2(0, -60 if foe != "player" else 60), "DIRECT ATTACK", RED, 44)
	# A big swing: direct hits, hits on a leader, and attacks that clearly overpower the target
	var big: bool = direct or ev.target == DuelState.LEADER or int(ev.att) - int(ev.def) >= 800
	await _wait(0.36)
	a.stop_moving()
	var dir := (tpos - a.home).normalized()
	if _clan_style(a.card, "attack") == "laser":
		await _laser_strike(a, d, tpos, dir, big, direct)
	elif _clan_style(a.card, "attack") == "guns":
		await _gun_strike(a, d, tpos, dir, big, direct)
	else:
		# Wind-up: rear back toward the camera while the view leans in
		Sfx.play("riser", 1.0 if big else 1.15, -4.0)
		_cam_focus(a.home.lerp(tpos, 0.5), 1.08 if big else 1.04, 0.32)
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(a, "position", a.home - dir * 54, 0.24)
		t.tween_property(a, "scale", Vector2.ONE * 1.32 * a.board_scale, 0.24)
		await t.finished
		await _wait(0.07)
		# Strike
		Sfx.play("whoosh", 1.3)
		t = create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_property(a, "position", a.home.lerp(tpos, 0.8), 0.09)
		t.tween_property(a, "scale", Vector2.ONE * 1.12 * a.board_scale, 0.09)
		await t.finished
		# Contact
		_strike_at = tpos
		_strike_time = _game_time
		Sfx.play("hit", 0.85 if direct else 1.0)
		Sfx.play("boom", 1.0 if big else 1.25, 0.0 if big else -5.0)
		shake(26.0 if big else 14.0)
		_shockwave(tpos, 1.0 if big else 0.55)
		_post_pulse("aberration", 14.0 if big else 6.0, 0.4)
		_sparks(tpos, dir, Color(1, 0.86, 0.5), 46 if big else 26)
		_burst(tpos, Color(1, 0.85, 0.45), 30, 560)
		_ring(tpos, Color.WHITE, 1.6 if big else 1.3)
		a.kick(-dir, 18.0)
		if d:
			d.flash()
			d.kick(dir, 34.0 if big else 26.0)
			var push := create_tween()
			push.tween_property(d, "position", d.home + dir * (34.0 if big else 20.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		if big:
			_impact_frame(0.06)
	await _hit_stop(0.11 if big else 0.07)
	_clear_attack_line()
	_cam_reset(0.4)
	a.go_home(0.28)
	await _wait(0.2)
	a.z_index = 10


func _clan_style(c: Dictionary, what: String) -> String:
	return str(CLAN_STYLE.get(_clan_key(c), {}).get(what, ""))


## The clan's colour (from the Card Forge), or gold.
func _clan_color(c: Dictionary) -> Color:
	var hex := str(c.get("clanColor", ""))
	return Color(hex) if hex.begins_with("#") else GOLD


func _clan_key(c: Dictionary) -> String:
	var tag := str(c.get("clanTag", ""))
	return tag if tag != "" else str(c.get("clan", ""))


## A ranged attack: an orb charges in front of the card, two quick zaps, then a sustained dark
## purple beam into the target (sparks where it hits), and a full impact as it ends.
func _laser_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var muzzle := a.home + dir * 96.0
	# Charge
	Sfx.play("riser", 0.8, -4.0)
	_cam_focus(a.home.lerp(tpos, 0.35), 1.05 if big else 1.03, 0.3)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 30.0, 0.26)
	t.tween_property(a, "scale", Vector2.ONE * 1.22 * a.board_scale, 0.26)
	var orb := LaserOrb.new()
	orb.glow = LASER_GLOW
	orb.core = LASER_CORE
	orb.position = muzzle
	orb.radius = 2.0
	orb.z_index = 71
	fx.add_child(orb)
	create_tween().tween_property(orb, "radius", 16.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_burst(muzzle, LASER_GLOW, 10, -140, 0.3, 0.0)   # sparks drawn inward
	await t.finished
	# Two quick zaps, a little off target (the targeting arrow gives way to the beams)
	_clear_attack_line()
	for i in 2:
		var off := dir.orthogonal() * (-18.0 if i == 0 else 18.0)
		_beam(muzzle, tpos + off, 14.0, 0.09)
		Sfx.play("laser", 0.9 + i * 0.1, -4.0)
		a.kick(-dir, 10.0)
		_burst(tpos + off, LASER_GLOW, 10, 320, 0.35, 150.0)
		shake(5.0)
		if d:
			d.kick(dir, 8.0)
		await _wait(0.13)
	# The beam: held on the target, flickering, sparks spraying from the hit
	Sfx.play("laser_beam", 0.85, -3.0)
	var hold := 0.34 if big else 0.26
	_beam(muzzle, tpos, 28.0 if big else 24.0, hold)
	a.kick(-dir, 16.0)
	var held := 0.0
	while held < hold:
		_sparks(tpos, dir, LASER_GLOW.lightened(0.35), 6, 70.0)
		shake(4.0)
		if d:
			d.kick(dir, 5.0)
		await _wait(0.06)
		held += 0.06
	orb.fade()
	# Impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("hit", 0.85 if direct else 1.0)
	Sfx.play("boom", 0.9 if big else 1.1, 0.0 if big else -5.0)
	shake(22.0 if big else 12.0)
	_shockwave(tpos, 0.9 if big else 0.5)
	_post_pulse("aberration", 12.0 if big else 5.0, 0.4)
	_sparks(tpos, dir, LASER_GLOW.lightened(0.3), 40 if big else 24)
	_burst(tpos, LASER_GLOW, 24, 520)
	_ring(tpos, LASER_GLOW.lightened(0.4), 1.5 if big else 1.2)
	if d:
		d.flash()
		d.kick(dir, 30.0 if big else 22.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (30.0 if big else 18.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)


## Nebula summon: a portal opens at the slot, the card comes through it spinning out of the dark,
## and the portal collapses behind it.
func _warp_in(v: CardView, target: Vector2, col: Color, heavy: bool) -> void:
	var portal := WarpPortal.new()
	portal.glow = col
	portal.position = target
	portal.z_index = 8
	cards_layer.add_child(portal)
	Sfx.play("riser", 0.75, -4.0)
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	var open := create_tween().set_parallel()
	open.tween_property(portal, "radius", 96.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	open.tween_property(portal, "spin", 9.0, 0.28)
	# The card dives into the portal...
	await v.move_to(target, 0.08, PI * 1.5, 0.22, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	await open.finished
	v.modulate.a = 0.0
	await _wait(0.08)
	# ...and comes out the other side
	v.modulate.a = 1.0
	Sfx.play("whoosh", 0.7)
	_burst(target, col.lightened(0.35), 30, 420, 0.7, 0.0)
	_ring(target, col.lightened(0.3), 1.5)
	await v.move_to(target, 1.0, v.home_rot, 0.34, Tween.TRANS_BACK, Tween.EASE_OUT).finished
	v.kick(Vector2(0, 1), 14.0)
	shake(14.0 if heavy else 8.0)
	_shockwave(target, 0.6 if heavy else 0.35)
	var close := create_tween().set_parallel()
	close.tween_property(portal, "radius", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	close.tween_property(portal, "spin", 2.0, 0.3)
	close.chain().tween_callback(portal.queue_free)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## Militia arrival: a targeting reticle locks onto the lane, the card goes up out of sight and is
## dropped in from above, landing hard in a cloud of dust. Lands in its final position (DEF: sideways).
func _airdrop(v: CardView, target: Vector2, col: Color, heavy: bool) -> void:
	var reticle := TargetReticle.new()
	reticle.glow = col
	reticle.position = target
	reticle.z_index = 8
	cards_layer.add_child(reticle)
	var lock := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lock.tween_property(reticle, "radius", 66.0, 0.3)
	lock.tween_property(reticle, "turn", PI / 2, 0.3)
	lock.tween_property(reticle, "alpha", 0.95, 0.12)
	Sfx.play("lockon", 1.0, -4.0)
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	# Up and out of sight...
	var up := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up.tween_property(v, "position", v.position + Vector2(0, -260), 0.16)
	up.tween_property(v, "modulate:a", 0.0, 0.16)
	await lock.finished
	Sfx.play("airdrop", 0.9 if heavy else 1.0, -2.0)   # the jet passes over; the drop follows it in
	await _wait(0.18)
	if up.is_running():
		await up.finished
	# ...and dropped in from above
	v.position = target + Vector2(0, -420)
	v.rotation = v.home_rot
	v.scale = Vector2.ONE * (1.7 if heavy else 1.5) * v.board_scale
	v.modulate.a = 1.0
	await v.move_to(target, 1.0, v.home_rot, 0.2 if heavy else 0.16, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	v.kick(Vector2(0, 1), 18.0)
	_burst(target + Vector2(0, CARD.y / 2 - 10), Color(0.55, 0.5, 0.36), 34 if heavy else 22, 460.0, 0.6, 900.0)   # dust
	_ring(target, col.lightened(0.25), 1.6 if heavy else 1.2)
	var gone := create_tween()
	gone.tween_property(reticle, "alpha", 0.0, 0.25)
	gone.tween_callback(reticle.queue_free)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## The Militia targeting reticle: rings and crosshair ticks, turning as it locks on.
class TargetReticle extends Node2D:
	var glow := Color.GREEN
	var radius := 120.0
	var turn := 0.0
	var alpha := 0.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := Color(glow.lightened(0.2), alpha)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, c, 3.0, true)
		draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 32, Color(c, alpha * 0.6), 2.0, true)
		for i in 4:
			var d := Vector2.from_angle(turn + i * PI / 2)
			draw_line(d * (radius - 18.0), d * (radius + 16.0), c, 3.0, true)
		draw_circle(Vector2.ZERO, 4.0, c)


## Nebula KO: the card shatters into stardust that drifts up and away.
func _stardust(v: CardView, col: Color) -> void:
	v.flash()
	Sfx.play("ko", 1.25)
	Sfx.play("effect", 0.6, -2.0)
	shake(12)
	_post_pulse("aberration", 8.0, 0.35)
	_stamp(v.position, "K.O.", col.lightened(0.3))
	var dust := CPUParticles2D.new()
	dust.position = v.position
	dust.one_shot = true
	dust.explosiveness = 0.75
	dust.amount = 140
	dust.lifetime = 1.4
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = CardView.SIZE / 2.0 * v.scale.x
	dust.direction = Vector2.UP
	dust.spread = 180.0
	dust.initial_velocity_min = 20.0
	dust.initial_velocity_max = 140.0
	dust.gravity = Vector2(0, -70)
	dust.damping_min = 20.0
	dust.damping_max = 40.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 4.0
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.add_point(0.35, col.lightened(0.25))
	g.set_color(g.get_point_count() - 1, Color(col, 0.0))
	dust.color_ramp = g
	dust.material = _add_mat
	dust.z_index = 450
	fx.add_child(dust)
	dust.emitting = true
	get_tree().create_timer(2.0).timeout.connect(dust.queue_free)
	_ring(v.position, col.lightened(0.4), 1.6)
	var t := create_tween().set_parallel()
	t.tween_property(v, "modulate:a", 0.0, 0.45)
	t.tween_property(v, "scale", v.scale * 1.15, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.2)


## Promotion: chevrons stream up through the card.
func _level_chevrons(pos: Vector2, col: Color) -> void:
	for i in 5:
		var ch := Node2D.new()
		ch.position = pos + Vector2(0, 80)
		ch.z_index = 445
		ch.material = _add_mat
		ch.draw.connect(func():
			ch.draw_polyline(PackedVector2Array([Vector2(-34, 12), Vector2(0, -12), Vector2(34, 12)]), col.lightened(0.35), 7.0, true))
		fx.add_child(ch)
		var t := create_tween().set_parallel()
		t.tween_property(ch, "position:y", pos.y - 110.0, 0.55).set_delay(i * 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(ch, "modulate:a", 0.0, 0.55).set_delay(i * 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(ch.queue_free)


## A Legendary enters (summoned, called in or played): the screen darkens, the card trembles in a
## pillar of gold light, rises to centre stage under turning rays with "LEGENDARY" and its name,
## and lands with a shockwave (like a leader awakening).
func _legendary_entrance(v: CardView, c: Dictionary) -> void:
	var col := UI.rarity_color(5)
	_dim(0.82, 0.3)
	Sfx.play("riser", 0.6)
	_light_column(v.position, col)
	for i in 6:   # it stirs
		v.kick(Vector2(randf_range(-1, 1), randf_range(-1, 1)), 10.0 + i * 3.0)
		shake(2.0 + i)
		if i % 2 == 0:
			_sparks(v.position, Vector2.UP, col.lightened(0.3), 6, 120.0)
		await _wait(0.07)
	Sfx.play("ambush", 0.9)
	await _showcase(v, c, col, "LEGENDARY · %s" % str(c.get("name", "")).to_upper())
	var center := Vector2(1080, DIVIDER_Y)
	_shockwave(center, 1.0)
	_impact_frame(0.06)
	shake(20)
	_post_pulse("aberration", 12.0, 0.45)
	_burst(center, col.lightened(0.4), 50, 700, 1.0, -100.0)
	_ring(center, Color.WHITE, 2.8)
	Sfx.play("legendary")
	await _wait(0.35)


## Luck: a coin flips (or a die tumbles) over the card, then lands on the result: outlined green
## if the effect happens, red if it doesn't.
func _ev_luck(ev: Dictionary) -> void:
	var side: String = ev.side
	var v = field.get(side, {}).get(int(ev.get("slot", -1)))
	var at: Vector2 = v.position if v is CardView and is_instance_valid(v) else Vector2(1080, DIVIDER_Y)
	var coin: bool = ev.get("kind") == "coin"
	var value := int(ev.get("value", 1))
	var won: bool = ev.get("won", false)
	var tok := LuckToken.new()
	tok.kind = "coin" if coin else "die"
	tok.font = _font
	tok.z_index = 600
	tok.position = at
	tok.scale = Vector2.ONE * 0.4
	cards_layer.add_child(tok)
	if ev.get("again", false):   # LOADED DICE: the lost one is tried again
		_float_text(at + Vector2(0, -230), "LOADED DICE!", GOLD, 34)
		_burst(at + Vector2(0, -150), GOLD, 16, 240, 0.5, 0.0)
		Sfx.play("promote", 1.4, -8.0)
	var up := create_tween().set_parallel()
	up.tween_property(tok, "position", at + Vector2(0, -150), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_property(tok, "scale", Vector2.ONE * 1.3, 0.28)
	for i in 10:   # a coin turns edge-on and over; a die tumbles through its faces
		if i == 0:
			Sfx.play("coin_flip" if coin else "dice_roll")
		if coin:
			tok.scale.x = 1.3 * absf(cos(i * 1.2))
			tok.face = i % 2
		else:
			tok.face = randi_range(1, 6)
			tok.rotation = randf_range(-0.6, 0.6)
		tok.queue_redraw()
		await _wait(0.055)
	tok.face = value
	tok.rotation = 0.0
	tok.scale = Vector2.ONE * 1.7
	tok.edge = Color("6ef08a") if won else RED
	tok.queue_redraw()
	create_tween().tween_property(tok, "scale", Vector2.ONE * 1.3, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("coin_land" if coin else "dice_land", 1.0, -2.0)
	_burst(tok.position, tok.edge, 18, 260, 0.6, 0.0)
	var need := int(ev.get("need", 1))
	var text := ("HEADS!" if value == 1 else "TAILS") if coin else ("ROLLED %d" % value + ((" · SUCCESS" if won else " · FAILED") if need > 1 else ""))
	if ev.get("double", false):   # DOUBLE OR NOTHING: the stakes, and a bigger win
		text = "HEADS · DOUBLE!" if won else "TAILS · NOTHING"
		if won:
			_burst(tok.position, GOLD, 34, 420, 0.8, 0.0)
			_ring(tok.position, GOLD, 1.6)
			Sfx.play("legendary", 1.5, -10.0)
	_float_text(tok.position + Vector2(0, -80), text, tok.edge, 30)
	await _wait(0.55)
	var out := create_tween()
	out.tween_property(tok, "modulate:a", 0.0, 0.25)
	out.tween_callback(tok.queue_free)


## A coin (a star for heads, plain for tails) or a die with its pips, for luck effects.
class LuckToken extends Node2D:
	const PIPS := {1: [Vector2(0, 0)], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]}
	var kind := "coin"
	var face := 1          # coin: 1 heads, 0 tails; die: 1-6
	var edge := Color(0, 0, 0, 0)   # once it lands: green if the effect happens, red if not
	var font: Font

	func _draw() -> void:
		if kind == "coin":
			var metal := Color("f4c542") if face == 1 else Color("c3c7d1")
			if edge.a > 0.0:
				draw_circle(Vector2.ZERO, 52, edge)
			draw_circle(Vector2.ZERO, 46, metal.darkened(0.4))
			draw_circle(Vector2.ZERO, 41, metal)
			draw_arc(Vector2.ZERO, 34, 0.0, TAU, 40, metal.darkened(0.25), 3.0, true)
			if face == 1:   # heads: a star
				var pts := PackedVector2Array()
				for k in 10:
					pts.append(Vector2.from_angle(-PI / 2 + k * PI / 5) * (24.0 if k % 2 == 0 else 10.0))
				draw_colored_polygon(pts, metal.darkened(0.45))
			elif font:
				draw_string(font, Vector2(-40, 13), "T", HORIZONTAL_ALIGNMENT_CENTER, 80, 36, metal.darkened(0.5))
		else:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("f5f3ee")
			sb.set_corner_radius_all(14)
			sb.set_border_width_all(5 if edge.a > 0.0 else 2)
			sb.border_color = edge if edge.a > 0.0 else Color("8a8a96")
			draw_style_box(sb, Rect2(-40, -40, 80, 80))
			for p in PIPS.get(face, []):
				draw_circle(p * 21.0, 7.5, Color("1c1c28"))


## Leader awakening: the leader trembles while the screen darkens, rises to centre stage with
## rays, a lens-shaking shockwave and its name, then holds for a beat before it takes the field.
func _awaken_cinematic(v: CardView, c: Dictionary, side: String) -> void:
	var col := _clan_color(c)
	_dim(0.82, 0.3)
	_cam_focus(v.position, 1.12, 0.45)
	Sfx.play("riser", 0.6)
	_light_column(v.position, col)
	for i in 7:   # it stirs
		v.kick(Vector2(randf_range(-1, 1), randf_range(-1, 1)), 12.0 + i * 3.0)
		shake(3.0 + i)
		if i % 2 == 0:
			_sparks(v.position, Vector2.UP, col.lightened(0.3), 6, 120.0)
		await _wait(0.07)
	_cam_reset(0.3)
	Sfx.play("ambush", 0.8)
	await _showcase(v, c, col, "%s AWAKENS" % str(c.get("name", "")).to_upper())
	var center := Vector2(1080, DIVIDER_Y)
	_shockwave(center, 1.2)
	_impact_frame(0.07)
	shake(26)
	_post_pulse("aberration", 16.0, 0.5)
	_burst(center, col.lightened(0.4), 60, 760, 1.1, -100.0)
	_ring(center, Color.WHITE, 3.2)
	Sfx.play("boom", 0.7)
	var tag := _label(30, col.lightened(0.35), true)
	tag.text = "THE LEADER TAKES THE FIELD"
	tag.size = Vector2(1920, 40)
	tag.position = Vector2(0, center.y + 330)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.modulate.a = 0.0
	overlay.add_child(tag)
	var tt := create_tween()
	tt.tween_property(tag, "modulate:a", 1.0, 0.2)
	tt.tween_interval(0.9)
	tt.tween_property(tag, "modulate:a", 0.0, 0.3)
	tt.tween_callback(tag.queue_free)
	await _wait(0.75)


## The Nebula portal: spiral arms turning around a dark centre.
class WarpPortal extends Node2D:
	var glow := Color.PURPLE
	var radius := 0.0
	var spin := 3.0
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle += spin * delta
		queue_redraw()

	func _draw() -> void:
		if radius < 1.0:
			return
		draw_circle(Vector2.ZERO, radius * 1.15, Color(glow, 0.14))
		draw_circle(Vector2.ZERO, radius * 0.75, Color(0.05, 0.01, 0.1, 0.85))
		for arm in 5:
			var pts := PackedVector2Array()
			for k in 18:
				var f := k / 17.0
				var a := _angle + arm * TAU / 5.0 + f * 2.6
				pts.append(Vector2.from_angle(a) * radius * (0.15 + 0.95 * f))
			draw_polyline(pts, Color(glow.lightened(0.3), 0.75), 3.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(glow.lightened(0.45), 0.9), 2.5, true)


## Militia: brace, then a burst of gunfire (muzzle flashes, tracers, bullet sparks on the
## target), and a full impact on the last round.
func _gun_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var muzzle := a.home + dir * 92.0
	var flash_col := Color(1.0, 0.9, 0.5)
	_cam_focus(a.home.lerp(tpos, 0.35), 1.04, 0.25)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 18.0, 0.18)
	t.tween_property(a, "scale", Vector2.ONE * 1.18 * a.board_scale, 0.18)
	await t.finished
	_clear_attack_line()
	var shots := 9 if big else 7
	for i in shots:
		var last := i == shots - 1
		var hit := tpos + Vector2(randf_range(-26, 26), randf_range(-34, 34)) * (0.3 if last else 1.0)
		Sfx.play("gunshot", randf_range(0.92, 1.12), -2.0 if last else -6.0)
		_muzzle_flash(muzzle + dir.orthogonal() * randf_range(-6, 6), dir, flash_col)
		_tracer(muzzle, hit, flash_col)
		a.kick(-dir, 6.0)
		a.position = a.home - dir * (18.0 + randf_range(4.0, 9.0))   # recoil
		_sparks(hit, -dir, Color(1.0, 0.75, 0.35), 8, 70.0)
		if d:
			d.kick(dir, 4.0)
		shake(4.0)
		await _wait(0.06)
	# The last round lands: full impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("hit", 0.85 if direct else 1.0)
	Sfx.play("boom", 1.0 if big else 1.2, 0.0 if big else -5.0)
	shake(20.0 if big else 11.0)
	_shockwave(tpos, 0.8 if big else 0.45)
	_post_pulse("aberration", 10.0 if big else 4.0, 0.35)
	_sparks(tpos, dir, Color(1, 0.86, 0.5), 36 if big else 22)
	_burst(tpos, Color(1, 0.8, 0.4), 22, 480)
	_ring(tpos, Color.WHITE, 1.4 if big else 1.15)
	if d:
		d.flash()
		d.kick(dir, 28.0 if big else 20.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (26.0 if big else 16.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)


## A star-shaped flash at the muzzle, gone in a blink.
func _muzzle_flash(at: Vector2, dir: Vector2, col: Color) -> void:
	var f := Node2D.new()
	f.position = at
	f.rotation = dir.angle()
	f.z_index = 72
	f.material = _add_mat
	f.draw.connect(func():
		f.draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(34, 0), Vector2(0, 9), Vector2(-6, 0)]), col)
		f.draw_colored_polygon(PackedVector2Array([Vector2(4, -16), Vector2(16, 0), Vector2(4, 16)]), Color(col, 0.7))
		f.draw_circle(Vector2(6, 0), 9.0, Color(1, 1, 1, 0.9)))
	fx.add_child(f)
	var t := f.create_tween()
	t.tween_property(f, "modulate:a", 0.0, 0.07)
	t.tween_callback(f.queue_free)


## A bullet's tracer: a bright streak from the gun to where it hits, fading fast.
func _tracer(from: Vector2, to: Vector2, col: Color) -> void:
	var l := Line2D.new()
	l.points = PackedVector2Array([from, from.lerp(to, 0.35), to])
	l.width = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_color(1, Color(1, 1, 0.9, 1.0))
	l.gradient = g
	l.material = _add_mat
	l.z_index = 71
	fx.add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", 0.0, 0.08)
	t.tween_callback(l.queue_free)


## A laser beam from `from` to `to` that lasts `secs`, then narrows away.
func _beam(from: Vector2, to: Vector2, width: float, secs: float) -> void:
	var b := LaserBeam.new()
	b.glow = LASER_GLOW
	b.core = LASER_CORE
	b.position = from
	b.target = to - from
	b.width = width
	b.z_index = 70
	fx.add_child(b)
	var t := b.create_tween()
	t.tween_interval(secs)
	t.tween_property(b, "width", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(b.queue_free)


## The beam: a wide soft glow, bright violet edges and a dark core, flickering a little.
class LaserBeam extends Node2D:
	var glow := Color.PURPLE
	var core := Color.BLACK
	var target := Vector2.ZERO
	var width := 12.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if width <= 0.2:
			return
		var w := width * randf_range(0.85, 1.12)
		draw_line(Vector2.ZERO, target, Color(glow, 0.14), w * 3.2, true)
		draw_line(Vector2.ZERO, target, Color(glow, 0.35), w * 1.9, true)
		draw_line(Vector2.ZERO, target, glow.lightened(0.35), w, true)
		draw_line(Vector2.ZERO, target, core, w * 0.5, true)
		draw_line(Vector2.ZERO, target, Color(glow.lightened(0.6), 0.5), maxf(1.0, w * 0.08), true)
		draw_circle(target, w * 0.9, Color(glow.lightened(0.4), 0.8))
		draw_circle(target, w * 0.45, core)
		draw_circle(Vector2.ZERO, w * 0.7, glow.lightened(0.3))


## The charge at the muzzle: a dark core in a glowing shell.
class LaserOrb extends Node2D:
	var glow := Color.PURPLE
	var core := Color.BLACK
	var radius := 11.0:
		set(v):
			radius = v
			queue_redraw()

	func fade() -> void:
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.15)
		t.tween_callback(queue_free)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius * 2.1, Color(glow, 0.16))
		draw_circle(Vector2.ZERO, radius * 1.45, Color(glow, 0.38))
		draw_circle(Vector2.ZERO, radius, glow.lightened(0.25))
		draw_circle(Vector2.ZERO, radius * 0.66, core)
		draw_arc(Vector2.ZERO, radius * 0.66, 0.0, TAU, 24, glow.lightened(0.55), 1.5, true)


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
	Sfx.play("boom", 1.5, -8.0)
	shake(8)
	v.kick(Vector2(0, -1 if ev.side == "player" else 1), 20.0)
	_shockwave(v.home, 0.35)
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
	if ev.card.get("token", false):   # a token doesn't go to the Gutter: it dissolves
		Sfx.play("whoosh", 0.8)
		_burst(v.position, _clan_color(v.card), 24, 300, 0.6)
		var t := create_tween().set_parallel()
		t.tween_property(v, "modulate:a", 0.0, 0.35)
		t.tween_property(v, "scale", Vector2.ONE * 0.7 * v.board_scale, 0.35)
		await t.finished
		if v == _hovered:
			_hovered = null
		v.queue_free()
		return
	if _clan_style(v.card, "ko") == "stardust" and v.face_up:
		await _stardust(v, _clan_color(v.card))
		return
	v.flash()
	Sfx.play("ko")
	Sfx.play("boom", 0.9)
	shake(18)
	_shockwave(v.position, 0.8)
	_post_pulse("aberration", 10.0, 0.35)
	_burst(v.position, Color(1.0, 0.45, 0.15), 44, 650, 0.8)
	_burst(v.position, Color.WHITE, 18, 350, 0.5)
	_sparks(v.position, Vector2.UP, Color(1.0, 0.6, 0.25), 30, 180.0)
	_stamp(v.position, "K.O.", Color(1, 0.35, 0.2))
	v.kick(Vector2(randf_range(-1, 1), -1), 40.0)
	await _hit_stop(0.07)
	var t := create_tween().set_parallel()
	t.tween_property(v, "rotation", v.rotation + randf_range(-0.6, 0.6), 0.16)
	t.tween_property(v, "scale", Vector2.ONE * 1.12 * v.board_scale, 0.16)
	await t.finished
	await _to_gutter(v, side)


func _ev_damage(ev: Dictionary) -> void:
	var side: String = ev.side
	var amount: int = ev.amount
	var p: Dictionary = _panels[side]
	var lethal: bool = int(ev.morale) <= 0
	var root: Control = p.root
	if _strike_at != Vector2.INF and _game_time - _strike_time < 2.5:
		await _comet(_strike_at, root.position + root.size / 2, RED if side == "player" else GOLD)
		_strike_at = Vector2.INF
	Sfx.play("damage")
	Sfx.play("boom", 0.8 if lethal else 1.0, 0.0 if lethal or amount >= 1000 else -6.0)
	shake(clampf(amount / 60.0, 8.0, 28.0) * (1.4 if lethal else 1.0))
	_set_morale(side, ev.morale)
	if lethal:
		_finisher(_panels[side].root)
	elif side == "player" and int(ev.morale) <= DuelState.START_MORALE / 4:
		Sfx.play("heartbeat", 1.0, -2.0)
	_float_text(root.position + root.size / 2 + Vector2(0, 40 if side != "player" else -40),
		"-%d" % amount, RED, 72)
	if side == "player":
		_screen_flash(RED, 0.22)
	await _wait(0.6)


## A keyword effect lands on a character (POISON, BURN, BLEED, SHOCK, FREEZE, STASIS).
func _ev_status(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	var style: Array = CardView.STATUS_STYLE.get(ev.kind, [GOLD, "", str(ev.kind).to_upper()])
	var col: Color = style[0]
	if ev.kind != "shock" and not v.statuses.has(ev.kind):
		var st := v.statuses.duplicate()
		st.append(ev.kind)
		v.statuses = st
	Sfx.play("effect")
	v.flash()
	_pulse_glow(v, col)
	_float_text(v.position + Vector2(0, -110 if ev.side == "player" else 110), style[2], col, 34)
	match ev.kind:
		"shock":
			_burst(v.position, col, 40, 520, 0.45, 0.0)
			shake(8)
		"stasis":
			_ring(v.position, col, 1.4)
			_burst(v.position, col, 30, 160, 1.2, -60.0)
		"freeze":
			_burst(v.position, col, 30, 220, 0.9, 120.0)
		"burn":
			_burst(v.position, col, 30, 260, 0.8, -420.0)
		_:
			_burst(v.position, col, 26, 240, 0.8, -200.0)
	await _wait(0.45)


## POISON / BURN tick at the start of the owner's turn; BLEED after a brawl.
func _ev_status_tick(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	var col: Color = CardView.STATUS_STYLE.get(ev.kind, [GOLD])[0]
	var text := "-%d ATK" % int(ev.amount)
	if ev.kind == "burn":
		text = "BURN -%d" % int(ev.amount)
	elif ev.kind == "bleed":
		text = "-%d ATK/DEF" % int(ev.amount)
	if ev.kind != "bleed" and not ev.card.has(ev.kind):
		v.statuses = v.statuses.filter(func(k): return k != ev.kind)
	Sfx.play("down", 1.3, -6.0)
	v.flash()
	_float_text(v.position + Vector2(0, -90 if ev.side == "player" else 90), text, col, 30)
	_burst(v.position, col, 18, 200, 0.7, -150.0)
	await _wait(0.35)


## A character is sacrificed so a Heavy can take its lane.
func _ev_tribute(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.slot)
	field[side].erase(ev.slot)
	if v == null:
		return
	v.show_badge = false
	v.z_index = 440
	_show_detail(ev.get("for", {}))
	Sfx.play("down", 0.6)
	_float_text(v.position + Vector2(0, -110 if side == "player" else 110), "REPLACED" if ev.get("replace", false) else "SACRIFICED", Color("b388ff"), 34)
	_burst(v.position, Color("b388ff"), 36, 420, 0.8, -250.0)
	_light_column(v.position)
	v.flash()
	await _wait(0.35)
	await _to_gutter(v, side)


## A card effect sends a character back to its owner's hand.
func _ev_bounce(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.slot)
	field[side].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, side, side == "player")
		v.position = slot_pos(side, ev.slot)
	v.show_badge = false
	v.downed = false
	v.glow = 0.0
	v.set_card(ev.card)
	Sfx.play("whoosh", 1.2)
	_ring(v.position, BLUE, 1.2)
	_float_text(v.position + Vector2(0, -110 if side == "player" else 110), "BACK TO HAND", BLUE, 30)
	if side == "opponent" and v.face_up:
		v.flip(false)
	elif side == "player" and not v.face_up:
		v.flip(true)
	hand[side].append(v)
	_layout_hand(side)
	await _wait(0.4)


## A character goes back on top of its owner's deck: it turns face-down and slides onto the pile.
func _ev_topdeck(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.slot)
	field[side].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, side, true)
		v.position = slot_pos(side, ev.slot)
	v.show_badge = false
	v.downed = false
	v.glow = 0.0
	v.busy = true
	v.z_index = 420
	Sfx.play("whoosh", 0.9)
	_ring(v.position, GOLD, 1.1)
	_float_text(v.position + Vector2(0, -110 if side == "player" else 110), "TOP OF THE DECK", GOLD, 30)
	if v.face_up:
		v.flip(false)
	await v.move_to(pile_pos(side, "deck"), 1.0, 0.0, 0.35, Tween.TRANS_CUBIC).finished
	v.queue_free()


## CLEANSE: a wash of white light rises through the card and its statuses fall away.
func _ev_cleanse(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	v.set_card(ev.card)
	v.statuses = []
	Sfx.play("cleanse")
	_light_column(v.position, Color(0.8, 1.0, 1.0))
	_sparks(v.position + Vector2(0, 60), Vector2.UP, Color(0.85, 1.0, 1.0), 24, 260.0)
	_ring(v.position, Color.WHITE, 1.1)
	v.flash()
	_float_text(v.position + Vector2(0, -110 if ev.side == "player" else 110), "CLEANSED", Color(0.75, 1.0, 1.0), 30)
	await _wait(0.45)


## REWIND: a character's ATK / DEF changes unwind (a clock spins back over it).
func _ev_rewind(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	Sfx.play("cleanse", 0.7)
	var violet := Color(0.72, 0.55, 1.0)
	for i in 3:
		_ring(v.position, violet.lerp(Color.WHITE, i * 0.3), 1.0 + i * 0.35)
	var spin := create_tween()
	spin.tween_property(v, "rotation", -TAU * 0.06, 0.18).set_trans(Tween.TRANS_SINE)
	spin.tween_property(v, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	v.set_card(ev.card)
	v.flash()
	_float_text(v.position + Vector2(0, -110 if ev.side == "player" else 110), "REWOUND", violet.lightened(0.3), 30)
	await _wait(0.5)


## JAM: the side's face-down cards are locked (static crackles over its back row).
func _ev_jam(ev: Dictionary) -> void:
	var p: Dictionary = _panels.get(ev.side, {})
	Sfx.play("slam", 1.3, -4.0)
	var lime := Color(0.7, 1.0, 0.3)
	for v in field.get(ev.side, {}).values():
		if v is CardView and v.card.get("face_down", false):
			_sparks(v.position, Vector2.UP, lime, 14, 180.0)
			_ring(v.position, lime, 0.8)
	if p.has("root"):
		var root: Control = p.root
		_float_text(root.position + root.size / 2 + Vector2(0, 40 if ev.side != "player" else -40), "AMBUSHES JAMMED", lime, 34)
	await _wait(0.45)


## BARRICADE: raised (a badge on the Morale panel), holding damage back, or falling at its owner's turn.
func _ev_barricade(ev: Dictionary) -> void:
	var p: Dictionary = _panels.get(ev.side, {})
	if not p.has("root"):
		return
	var root: Control = p.root
	var steel := Color(0.62, 0.85, 1.0)
	var badge: Label = p.get("barricade")
	if badge == null:
		badge = UI.label("", 20, steel)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 6)
		badge.position = Vector2(root.size.x - 150, -26 if ev.side == "player" else root.size.y + 2)
		root.add_child(badge)
		p["barricade"] = badge
	var amount := int(ev.amount)
	badge.text = "BARRICADE %d" % amount if amount > 0 else ""
	var mid := root.position + root.size / 2
	if int(ev.get("held", 0)) > 0:
		Sfx.play("slam", 0.8)
		shake(6.0)
		_ring(mid, steel, 1.6)
		_float_text(mid + Vector2(0, 40 if ev.side != "player" else -40), "BLOCKED %d" % int(ev.held), steel, 54)
		await _wait(0.45)
	elif amount > 0:
		Sfx.play("promote", 0.8, -4.0)
		_ring(mid, steel, 1.3)
		_float_text(mid + Vector2(0, 40 if ev.side != "player" else -40), "BARRICADE", steel, 40)
		await _wait(0.4)


## The top card of a deck goes straight to the Gutter.
func _ev_mill(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _new_view(ev.card, side, true)
	v.position = pile_pos(side, "deck")
	v.z_index = 420
	Sfx.play("flip", 0.8)
	await v.move_to(v.position + Vector2(0, -40 if side == "player" else 40), 1.2, 0.0, 0.15).finished
	await _to_gutter(v, side)


## A card comes back from the Gutter to its owner's hand.
func _ev_recover(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _new_view(ev.card, side, side == "player")
	v.position = pile_pos(side, "gutter")
	v.z_index = 420
	Sfx.play("promote", 1.3, -6.0)
	_burst(v.position, GREEN, 20, 240, 0.6, -200.0)
	_float_text(v.position + Vector2(0, -110), "RECOVERED", GREEN, 28)
	hand[side].append(v)
	_layout_hand(side)
	await _wait(0.4)


## A card effect restores Morale.
func _ev_heal(ev: Dictionary) -> void:
	var side: String = ev.side
	var root: Control = _panels[side].root
	_set_morale(side, ev.morale)
	Sfx.play("promote", 1.4, -4.0)
	_float_text(root.position + root.size / 2, "+%d" % int(ev.amount), GREEN, 64)
	_burst(get_viewport().get_canvas_transform().affine_inverse() * (root.position + root.size / 2), GREEN, 26, 260, 0.8, -300.0)
	await _wait(0.5)


## A Striver evolves. Gathering: the board falls to a vignette, the camera leans in and the card rises
## into a pillar of light as energy rings orbit it and motes spiral in. The cocoon: it becomes pure light,
## its silhouette morphing between the old and new forms on a quickening heartbeat, swelling. The break:
## a white-out, shards of light, and the new form spins in as the light drains off it, a foil sweep
## across its art. The reveal: rays, EVOLVED!, its level stars filling one by one and its ATK / DEF
## counting up. Then it lands back in its lane.
func _ev_promote(ev: Dictionary) -> void:
	var side: String = ev.side
	var slot: int = ev.slot
	var c: Dictionary = ev.card
	var old: Dictionary = ev.get("from", {})
	var pos := slot_pos(side, slot)
	var v: CardView = field[side].get(slot)
	if v == null:
		v = _new_view(old if not old.is_empty() else c, side, true)
		v.position = pos
		field[side][slot] = v
	v.z_index = 440
	v.show_badge = false
	v.busy = true
	v.downed = false
	var col := _clan_color(c)
	var bright := col.lerp(Color.WHITE, 0.45)
	var fxk := _fx_level()
	var stage := FFA_MID if _ffa else Vector2(1080, DIVIDER_Y)
	var big := 2.7 / maxf(v.board_scale, 0.01)
	var card_size := CARD * 2.7
	# 1. Gathering
	_dim(0.86, 0.4)
	_cam_focus(stage, 1.08, 0.8)
	Sfx.play("riser", 0.7)
	_light_column(pos, col)
	v.move_to(stage, big * 0.94, 0.0, 0.55, Tween.TRANS_BACK)
	var aura := EvoAura.new()
	aura.size = card_size
	aura.col = bright
	aura.position = stage
	aura.z_index = 436
	aura.material = _add_mat
	aura.modulate.a = 0.0
	cards_layer.add_child(aura)
	aura.create_tween().tween_property(aura, "modulate:a", 1.0, 0.6)
	var rings: Array = []
	for i in 3:   # three tilted orbits, each a back half (behind the card) and a front half (over it)
		for front in [false, true]:
			var r := EvoRing.new()
			r.rx = card_size.x * (0.95 + i * 0.16)
			r.ry = card_size.y * (0.16 + i * 0.03)
			r.tilt = [-0.35, 0.3, 0.05][i]
			r.phase = i * 2.1
			r.speed = 2.2 + i * 0.6
			r.col = bright if i != 1 else Color.WHITE.lerp(col, 0.25)
			r.front = front
			r.position = stage
			r.z_index = 452 if front else 434
			r.material = _add_mat
			r.modulate.a = 0.0
			cards_layer.add_child(r)
			r.create_tween().tween_property(r, "modulate:a", 1.0, 0.5).set_delay(0.15 * i)
			rings.append(r)
	_converge(stage, col, 60, 1.2)
	create_tween().tween_property(v, "_flash", 0.7, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in 10:
		v.kick(Vector2(randf_range(-1, 1), randf_range(-1, 1)), 3.0 + i * 1.4)
		if i % 3 == 0:
			_sparks(stage, Vector2.UP, bright, 6, 170.0)
		await _wait(0.1)
	# 2. The cocoon: light, the art glowing through it, morphing between the forms on a quickening heartbeat, swelling
	var beats := [0.3, 0.25, 0.2, 0.165, 0.135, 0.11, 0.09, 0.075, 0.062, 0.052, 0.045, 0.04, 0.036]
	for i in beats.size():
		var t := float(i) / (beats.size() - 1)
		if not old.is_empty():
			v.set_card(c if i % 2 == 0 else old)
			v.set_face(true)
		v._flash = lerpf(0.66, 0.84, t) if i % 2 == 0 else lerpf(0.86, 0.95, t)   # (the new form shows through a little more)
		var swell := big * lerpf(0.96, 1.1, t)
		v.scale = Vector2.ONE * swell * v.board_scale * 1.07
		v.create_tween().tween_property(v, "scale", Vector2.ONE * swell * v.board_scale, beats[i] * 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		aura.pulse = 1.0
		aura.create_tween().tween_property(aura, "pulse", 0.0, beats[i])
		for r in rings:
			r.speed *= 1.13
		Sfx.play("hover", 0.7 + t * 0.9, -8.0 + t * 4.0)
		if fxk > 0.0 and i % 2 == 0:
			shake((1.0 + t * 4.0) * fxk)
		await _wait(beats[i])
	# 3. The break
	v.set_card(c)
	v.set_face(true)
	for r in rings:   # the rings collapse inward and vanish
		var rt: Tween = r.create_tween().set_parallel()
		rt.tween_property(r, "rx", 4.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		rt.tween_property(r, "modulate:a", 0.0, 0.22)
		rt.chain().tween_callback(r.queue_free)
	await _wait(0.18)
	if fxk > 0.0:
		var flash := ColorRect.new()
		flash.color = Color(1, 1, 1, 0.95 * fxk)
		flash.position = Vector2(-100, -100)
		flash.size = Vector2(2120, 1280)
		flash.z_index = 470
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards_layer.add_child(flash)
		var ft := flash.create_tween()
		ft.tween_property(flash, "color:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ft.tween_callback(flash.queue_free)
		_impact_frame(0.05)
		shake(18 * fxk)
		_post_pulse("aberration", 12.0, 0.6)
	_evo_shards(stage, bright, card_size)
	_shockwave(stage, 1.0)
	_ring(stage, Color.WHITE, 2.8)
	_ring(stage, bright, 1.9)
	_burst(stage, bright, 70, 760, 1.2, -120.0)
	Sfx.play("boom", 1.1, -2.0)
	Sfx.play("promote")
	Sfx.play("legendary", 1.2, -6.0)
	aura.create_tween().tween_property(aura, "modulate:a", 0.0, 0.5)
	# The new form spins in (two quick half-turns, settling), the light draining off it, foil sweeping across
	create_tween().tween_property(v, "_flash", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	v.move_to(stage, big, 0.0, 0.5, Tween.TRANS_BACK)
	var spin := create_tween()
	spin.tween_property(v, "_flip_deg", 90.0, 0.09)
	spin.tween_callback(func(): v._flip_deg = -90.0)
	spin.tween_property(v, "_flip_deg", 90.0, 0.16)
	spin.tween_callback(func(): v._flip_deg = -90.0)
	spin.tween_property(v, "_flip_deg", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	v.holo_boost = 1.0
	v.create_tween().tween_property(v, "holo_boost", 0.0, 1.6).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	_show_detail(c)
	# 4. The reveal
	var rays := Node2D.new()
	rays.position = stage
	rays.z_index = 415
	rays.material = _add_mat
	rays.modulate.a = 0.0
	rays.draw.connect(func():
		for k in 20:
			var a := k * TAU / 20.0
			var w := 0.06 if k % 2 == 0 else 0.03
			rays.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * 1200.0, Vector2.from_angle(a + w) * 1200.0]),
				PackedColorArray([Color(bright, 0.55), Color(col, 0.0), Color(col, 0.0)])))
	cards_layer.add_child(rays)
	var rt2 := create_tween().set_parallel()
	rt2.tween_property(rays, "modulate:a", 1.0, 0.3)
	rt2.tween_property(rays, "rotation", 0.6, 2.2)
	_splash_name("EVOLVED!", bright, stage.y - card_size.y / 2 - 105.0)
	var lv_old := CardDB.striver_stage(old)
	var lv_new := CardDB.striver_stage(c)
	var stars := _evo_stars(stage + Vector2(0, card_size.y / 2 + 30), lv_old if lv_old.y > 0 else Vector2i(maxi(1, lv_new.x - 1), lv_new.y))
	await _wait(0.45)
	if lv_new.y > 0:   # the new star pops in
		stars.level = lv_new
		stars.pop = 1.0
		stars.queue_redraw()
		stars.create_tween().tween_property(stars, "pop", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_ring(stars.position, GOLD, 0.9)
		_burst(stars.position, GOLD, 22, 300, 0.7, 0.0)
		Sfx.play("coin_land", 1.4, -6.0)
	# ATK / DEF counting up from the old form's to the new one's
	var a0 := int(old.get("attack", old.get("base_attack", 0)))
	var d0 := int(old.get("defense", old.get("base_defense", 0)))
	var a1 := int(c.get("attack", c.get("base_attack", 0)))
	var d1 := int(c.get("defense", c.get("base_defense", 0)))
	var tally := _label(34, GOLD, true)
	tally.size = Vector2(900, 44)
	tally.position = stage + Vector2(-450, card_size.y / 2 + 62)
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally.z_index = 460
	tally.modulate.a = 0.0
	cards_layer.add_child(tally)
	var lvl_text := ("LV%d  ▶  LV%d     " % [maxi(1, lv_new.x - 1), lv_new.x]) if lv_new.x > 0 else ""
	var show_tally := func(k: float):
		tally.text = "%sATK %d   DEF %d" % [lvl_text, int(lerpf(a0, a1, k)), int(lerpf(d0, d1, k))]
	show_tally.call(0.0)
	var tt := create_tween()
	tt.tween_property(tally, "modulate:a", 1.0, 0.2)
	tt.tween_method(show_tally, 0.0, 1.0, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tt.tween_callback(func():
		Sfx.play("click", 1.6, -6.0)
		tally.pivot_offset = tally.size / 2
		tally.scale = Vector2.ONE * 1.15
		tally.create_tween().tween_property(tally, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	await _wait(1.35)
	# 5. The landing
	var out := create_tween().set_parallel()
	for n in [rays, stars, tally]:
		out.tween_property(n, "modulate:a", 0.0, 0.3)
	out.chain().tween_callback(func():
		for n in [rays, stars, tally, aura]:
			if is_instance_valid(n):
				n.queue_free())
	_dim(0.0, 0.4)
	_cam_reset(0.5)
	v.home = pos
	v.home_rot = PI / 2 if c.position == "def" else 0.0
	v.home_scale = 1.0
	await v.move_to(pos, 1.0, v.home_rot, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	await _impact(pos, false)
	v.busy = false
	v.z_index = 10
	v.show_badge = true


## Shards of light flying out from an evolving card as its cocoon breaks.
func _evo_shards(at: Vector2, col: Color, card_size: Vector2) -> void:
	for i in 22:
		var sh := Node2D.new()
		sh.material = _add_mat
		sh.z_index = 465
		var l := randf_range(18.0, 46.0)
		var w := randf_range(5.0, 12.0)
		var tint := col.lerp(Color.WHITE, randf_range(0.3, 0.9))
		sh.draw.connect(func():
			sh.draw_colored_polygon(PackedVector2Array([Vector2(-l * 0.5, 0), Vector2(0, -w), Vector2(l * 0.5, 0), Vector2(0, w * 0.6)]), tint))
		var dir := Vector2.from_angle(randf() * TAU)
		sh.position = at + Vector2(dir.x * card_size.x * 0.35, dir.y * card_size.y * 0.35)
		sh.rotation = dir.angle()
		fx.add_child(sh)
		var t := sh.create_tween().set_parallel()
		var dur := randf_range(0.5, 0.85)
		t.tween_property(sh, "position", sh.position + dir * randf_range(380.0, 720.0), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(sh, "rotation", sh.rotation + randf_range(-3.0, 3.0), dur)
		t.tween_property(sh, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(sh.queue_free)


## A soft glow round an evolving card (a blurred shadow box), swelling on each heartbeat.
class EvoAura extends Node2D:
	var size := Vector2(285, 400)
	var col := Color.WHITE
	var pulse := 0.0:
		set(v):
			pulse = v
			queue_redraw()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, 0.0)
		sb.shadow_color = Color(col, 0.55 + 0.4 * pulse)
		sb.shadow_size = int(40 + 40 * pulse)
		sb.set_corner_radius_all(18)
		var grow := 6.0 + 10.0 * pulse
		draw_style_box(sb, Rect2(-size / 2 - Vector2(grow, grow), size + Vector2(grow, grow) * 2))


## One half of a tilted orbit of energy round an evolving card: the back half is drawn behind it, the
## front half over it, with a bright comet running round.
class EvoRing extends Node2D:
	var rx := 300.0
	var ry := 60.0
	var tilt := 0.0
	var phase := 0.0
	var speed := 2.0
	var col := Color.WHITE
	var front := true

	func _process(delta: float) -> void:
		phase = fmod(phase + speed * delta, TAU)
		queue_redraw()

	func _point(a: float) -> Vector2:
		return Vector2(cos(a) * rx, sin(a) * ry).rotated(tilt)

	func _draw() -> void:
		var pts := PackedVector2Array()
		for k in 33:   # the half of the ellipse nearer the viewer (front) or further (back)
			var a := (0.0 if front else PI) + PI * k / 32.0
			pts.append(_point(a))
		draw_polyline(pts, Color(col, 0.35 if front else 0.18), 3.0 if front else 2.0, true)
		for k in 18:   # the comet: a head and a fading tail, where it falls in this half
			var a := phase - k * 0.07
			var s := sin(a)
			if (s >= 0.0) != front:
				continue
			draw_circle(_point(a), maxf(1.0, 6.5 - k * 0.32), Color(col, (1.0 - k / 18.0) * (1.0 if front else 0.55)))


## Motes of energy spiralling in from all round to a point, over seconds.
func _converge(at: Vector2, col: Color, amount: int, seconds: float) -> void:
	for i in amount:
		var mote := Node2D.new()
		mote.z_index = 450
		mote.material = _add_mat
		var r0 := randf_range(300.0, 620.0)
		var a0 := randf() * TAU
		var spin := randf_range(1.6, 2.8) * (1.0 if i % 2 == 0 else -1.0)
		var size := randf_range(2.5, 6.0)
		var tint := col.lerp(Color.WHITE, randf_range(0.2, 0.7))
		mote.draw.connect(func():
			mote.draw_circle(Vector2.ZERO, size * 2.4, Color(tint, 0.18))
			mote.draw_circle(Vector2.ZERO, size, tint))
		mote.position = at + Vector2.from_angle(a0) * r0
		mote.modulate.a = 0.0
		fx.add_child(mote)
		var delay := randf() * seconds * 0.45
		var t := create_tween()
		t.tween_interval(delay)
		t.tween_property(mote, "modulate:a", 1.0, 0.12)
		t.parallel().tween_method(func(k: float):
			mote.position = at + Vector2.from_angle(a0 + spin * k) * r0 * pow(1.0 - k, 1.6)
			mote.scale = Vector2.ONE * (1.0 - 0.6 * k), 0.0, 1.0, seconds - delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(mote.queue_free)


## The level stars under an evolving card (UI.draw_level_stars, large); pop swells them for a moment.
func _evo_stars(at: Vector2, level: Vector2i) -> EvoStars:
	var n := EvoStars.new()
	n.position = at
	n.level = level
	n.z_index = 452
	cards_layer.add_child(n)
	n.modulate.a = 0.0
	n.create_tween().tween_property(n, "modulate:a", 1.0, 0.2)
	return n


class EvoStars extends Node2D:
	var level := Vector2i.ZERO
	var pop := 0.0

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (1.0 + 0.35 * pop))
		UI.draw_level_stars(self, Vector2.ZERO, level, 22.0)
		draw_set_transform(Vector2.ZERO)

	func _process(_delta: float) -> void:
		if pop > 0.0:
			queue_redraw()


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
	_float_text(v.home + Vector2(0, -120 if ev.side == "player" else 120), "%s STANDS UP" % str(ev.card.get("name", "")).to_upper(), GREEN, 32)
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
				if s.size() > 5:
					v.statuses = s[5]


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
	_arrow.from = to
	_burst(v.position, BLUE, 12, 220, 0.4, 0.0)
	await v.move_to(to, v.scale.x, v.home_rot, 0.22, Tween.TRANS_BACK).finished
	_float_text(to + Vector2(0, -110 if side == "player" else 110), "LANE SHIFT", BLUE, 30)


func _ev_retarget(ev: Dictionary) -> void:
	var foe := str(ev.get("foe", DuelState.other(ev.side)))
	_arrow.to = _target_pos(foe, ev.target)
	var be: CardView = field.get(foe, {}).get(ev.target)
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
	await _awaken_cinematic(v, c, side)
	await v.move_to(target + Vector2(0, -60 if side == "player" else 60), 1.9, 0.0, 0.26).finished
	await v.move_to(target, 1.0, 0.0, 0.12, Tween.TRANS_QUAD, Tween.EASE_IN).finished
	await _impact(target, true)
	_cam_reset(0.4)
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


func _ev_leader_heal(ev: Dictionary) -> void:
	var v: CardView = leaders.get(ev.side)
	if v == null:
		return
	v.badge_text = _influence_text(ev.influence)
	_float_text(v.home + Vector2(0, -40), "+%d" % ev.amount, Color(1.0, 0.85, 0.42), 56)
	Sfx.play("heal", 1.1)
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
	Sfx.play("boom", 0.75)
	shake(22)
	_shockwave(v.position, 1.0)
	_impact_frame(0.07)
	_post_pulse("aberration", 14.0, 0.45)
	_burst(v.position, Color(1.0, 0.45, 0.15), 50, 700, 0.9)
	_stamp(v.position, "LEADER DOWN", RED)
	await _hit_stop(0.1)
	await _to_gutter(v, side)


static func _influence_text(influence: int) -> String:
	return "[center][font_size=10][color=#e8c77a]INFLUENCE[/color][/font_size] [b][color=#ffd86b]%d[/color][/b][/center]" % influence


func _ev_game_over(ev: Dictionary) -> void:
	_mode = "over"
	_cancel_interaction()
	var won: bool = ev.winner == "player"
	_end_reason = str(ev.get("reason", "morale"))
	if _end_reason == "deck_out" and not _ffa:
		var loser := "opponent" if won else "player"
		_stamp(pile_pos(loser, "deck"), "DECKED OUT", RED)
		shake(12)
		Sfx.play("down", 0.7)
		await _wait(0.9)
	await _wait(0.5)
	if DisplayServer.get_name() != "headless":
		_end_snap = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	# Your own matches get their big reveal on the post-match screen; spectators, replays and
	# CPU-only matches don't go there, so they see it here
	var reveal_here: bool = _spectating or not _replay.is_empty() or "player" in ai_sides
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = Vector2(1920, 1080)
	overlay.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.7 if reveal_here else 1.0, 0.4 if reveal_here else 0.8)
	if not reveal_here:
		shake(14)
		_post_pulse("aberration", 10.0, 0.4)
		Sfx.play("boom", 0.8, -4.0)
		Game.sound.music("", 0.8)
		await _wait(0.9)
		_finish_match(won)
		return
	Game.sound.music("", 0.6)
	Game.sound.sting("victory" if won else "defeat")
	var title := _label(170, GOLD if won else RED, true)
	title.text = ("VICTORY" if won else "DEFEAT") if not _spectating else "%s WINS" % str(_names.player if won else _names.opponent).to_upper()
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


## The MVP: Morale dealt, and a KO is worth 800 of it.
static func _mvp_score(e: Dictionary) -> int:
	return int(e.get("damage", 0)) + 800 * int(e.get("kos", 0))


## Hand the result (and a snapshot of the board for the background) to the post-match screen.
func _finish_match(won: bool) -> void:
	var mvp := {}
	for key in _damage_log:
		if mvp.is_empty() or _mvp_score(_damage_log[key]) > _mvp_score(mvp):
			mvp = _damage_log[key]
	var snap: Texture2D = _end_snap
	if snap == null and DisplayServer.get_name() != "headless":
		snap = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	Game.match_result = {
		"result": "win" if won else "loss",
		"player_morale": duel.sides.player.morale, "opponent_morale": duel.sides.get("opponent", {}).get("morale", "—"),
		"turns": duel.turn, "cards_played": _cards_played, "mvp": mvp,
		"match_id": _match_id, "snapshot": snap, "tutorial": _tutorial != null, "reason": _end_reason,
	}
	if not _replay.is_empty():
		await _wait(1.2)
		Game.go("profile")
		return
	if _spectating:
		await _wait(1.5)
		Game.go("social")
		return
	if _online:
		# The server records the match and sends the rewards (mp:over)
		var waited := 0.0
		while _over.is_empty() and waited < 10.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		Game.match_result.online = true
		Game.match_result.mode = str(Game.duel_setup.get("start", {}).get("mode", ""))
		Game.match_result.match_id = ""
		Game.match_result.reason = str(_over.get("reason", "morale"))
		Game.match_result.rewards = _over.get("rewards")
		Game.match_result.achievements = _over.get("achievements", [])
		Game.match_result.mastery = _over.get("mastery")
		if _over.has("result"):
			Game.match_result.result = _over.result
		if _ffa:
			_ffa_result_into(Game.match_result, _over)
	Game.go("post_match")


# ── View helpers ─────────────────────────────────────────────────────────────

func _new_view(c: Dictionary, side: String, up: bool) -> CardView:
	var v := CardView.new()
	cards_layer.add_child(v)
	v.board_scale = _sc(side)
	v.setup(c, side, up)
	v.scale = Vector2.ONE * v.board_scale   # (starts at its board's size: FFA opponents' are smaller)
	v.set_back(_back_for(side), CardDB.back_style(_back_clan(side)))
	return v


## A side's cards wear its leader's clan back (CardDB.back), e.g. the Nebula back.
func _back_for(side: String) -> Texture2D:
	return CardDB.back(_back_clan(side))


## Whose card back a side shows: the one its player chose, else its clan's ("default", the retired
## Classic back, counts as no choice).
func _back_clan(side: String) -> String:
	var chosen: String = _chosen_back.get(side, "")
	return chosen if chosen != "" and chosen != "default" else _clan_of(side)


func _clan_of(side: String) -> String:
	var leader = duel.sides[side].get("leader") if duel != null else null
	return str(leader.get("clanTag", "")) if leader is Dictionary else ""


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
	v.board_scale = _sc(side)   # (FFA: your hand is full size, your board smaller)
	_layout_hand(side)
	return v


func _layout_hand(side: String) -> void:
	var views: Array = hand[side]
	var n := views.size()
	if _ffa and side != "player":
		_layout_foe_hand(side, views)
		return
	var s: float = HAND_SCALE if side == "player" else OPP_HAND_SCALE
	var w := CARD.x * s
	var span := HAND_SPAN if side == "player" else 640.0
	var gap := 0.0
	if n > 1:
		gap = minf(w + (10.0 if side == "player" else 4.0), (span - w) / (n - 1))
	for i in n:
		var v: CardView = views[i]
		v.board_scale = 1.0
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
	t.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.32)
	t.tween_property(v, "rotation", 0.0, 0.32)
	t.tween_property(v, "modulate:a", 0.0, 0.2).set_delay(0.14)
	await t.finished
	if v == _hovered:
		_hovered = null
	v.queue_free()


# ── Effects (juice) ──────────────────────────────────────────────────────────

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * _fx_level())


## Settings → Screen Shake & Flashes: 1 full, 0.5 reduced, 0 off.
func _fx_level() -> float:
	return clampf(float(Game.settings.get("screen_fx", 1.0)), 0.0, 1.0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Freeze the action for a split second on big hits.
func _hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.08
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = _base_speed * _catch_up


## Events waiting to be shown: play a little faster until they're caught up (x1.5 from 40 waiting,
## x2.5 from 80). The server's CPUs wait for the animations, so this is only for a real backlog.
func _pace() -> void:
	var waiting := _queue.size()
	_catch_up = 1.0 if waiting < 40 else 1.5 if waiting < 80 else 2.5
	if Engine.time_scale >= _base_speed * 0.99:   # (not in the middle of a hit-stop)
		Engine.time_scale = _base_speed * _catch_up


func _impact(pos: Vector2, heavy: bool) -> void:
	Sfx.play("heavy" if heavy else "slam", randf_range(0.95, 1.05))
	shake(24.0 if heavy else 8.0)
	_shockwave(pos, 0.9 if heavy else 0.35)
	if heavy:
		Sfx.play("boom", 0.85)
		_post_pulse("aberration", 12.0, 0.45)
		_impact_frame(0.05)
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


func _light_column(pos: Vector2, color := GOLD) -> void:
	var s := Sprite2D.new()
	s.texture = _column_tex
	s.material = _add_mat
	s.modulate = Color(color, 0.0)
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
	if _fx_level() <= 0.0:
		return
	var r := ColorRect.new()
	r.color = Color(color, alpha * _fx_level())
	r.size = Vector2(1920, 1080)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.0, 0.35)
	t.tween_callback(r.queue_free)


func _clear_attack_line() -> void:
	_arrow.hide_arrow()


## While the player aims an attack, the arrow follows the mouse and locks onto valid targets.
func _update_aim() -> void:
	if _mode != "target" or not field.player.has(_selected_slot):
		if _arrow.visible and not _playing:
			_arrow.hide_arrow()
		return
	var m := get_global_mouse_position()
	var end := m
	var snapped := false
	var slot := _slot_at("opponent", m)
	if slot >= 0 and _valid.has("opponent:%d" % slot):
		end = slot_pos("opponent", slot)
		snapped = true
	elif leaders.has("opponent") and leaders.opponent.glow > 0.0 and leaders.opponent.hit(m):
		end = leaders.opponent.home
		snapped = true
	elif _direct_btn and is_instance_valid(_direct_btn) and _direct_btn.get_global_rect().has_point(m):
		end = _direct_btn.get_global_rect().get_center()
		snapped = true
	_arrow.aim(field.player[_selected_slot].home, end, RED if snapped else GOLD, snapped)


# ── Screen effects and camera ────────────────────────────────────────────────

func _build_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_post = ColorRect.new()
	_post.size = Vector2(1920, 1080)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = preload("res://shaders/post.gdshader")
	_post.material = _post_mat
	_post.visible = false
	layer.add_child(_post)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var streak := GradientTexture2D.new()
	streak.gradient = g
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	streak.width = 6
	streak.height = 48
	_streak_tex = streak


func _update_post() -> void:
	if duel and _panels.has("player"):
		var low: bool = duel.winner == "" and _panels.player.shown <= DuelState.START_MORALE / 4.0
		_danger = move_toward(_danger, 1.0 if low else 0.0, get_process_delta_time() * 1.5)
	var beat := 0.0
	if _danger > 0.0:
		var ph := fmod(Time.get_ticks_msec() / 1000.0, 1.1)
		beat = _danger * (0.22 + 0.2 * exp(-ph * 9.0) + 0.12 * exp(-maxf(ph - 0.2, 0.0) * 9.0) * float(ph > 0.2))
	_post_mat.set_shader_parameter("danger", beat)
	for k in _post_fx:
		_post_mat.set_shader_parameter(k, _post_fx[k])
	_post.visible = beat > 0.002 or _post_fx.values().any(func(x): return x > 0.002)


## Spike a post effect and let it fall back to zero.
func _post_pulse(param: String, peak: float, seconds: float) -> void:
	peak *= _fx_level()
	_post_fx[param] = maxf(_post_fx[param], peak)
	var t := create_tween()
	t.tween_method(func(x: float): _post_fx[param] = x, _post_fx[param], 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _screen_uv(world: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform() * world) / get_viewport().get_visible_rect().size


## A ripple of distortion racing out from a point.
func _shockwave(world: Vector2, strength: float) -> void:
	_post_mat.set_shader_parameter("wave_center", _screen_uv(world))
	_post_fx.wave_strength = strength
	var t := create_tween().set_parallel()
	t.tween_method(func(r: float): _post_mat.set_shader_parameter("wave_radius", r), 0.02, 0.75, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(x: float): _post_fx.wave_strength = x, strength, 0.0, 0.55)


## Damage made visible: a glowing bolt flies from the point of impact to a Morale plate.
func _comet(from: Vector2, to_screen: Vector2, color: Color) -> void:
	var to := get_viewport().get_canvas_transform().affine_inverse() * to_screen
	var head := Sprite2D.new()
	head.texture = _dot
	head.material = _add_mat
	head.modulate = color.lerp(Color.WHITE, 0.5)
	head.scale = Vector2.ONE * 3.0
	head.position = from
	fx.add_child(head)
	var trail := CPUParticles2D.new()
	trail.amount = 40
	trail.lifetime = 0.3
	trail.local_coords = false
	trail.texture = _dot
	trail.material = _add_mat
	trail.gravity = Vector2.ZERO
	trail.spread = 180.0
	trail.initial_velocity_max = 60.0
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	trail.color_ramp = g
	head.add_child(trail)
	trail.scale = Vector2.ONE / head.scale
	Sfx.play("whoosh", 1.6, -4.0)
	var ctrl := from.lerp(to, 0.5) + (to - from).orthogonal().normalized() * 140.0
	var t := create_tween()
	t.tween_method(func(k: float): head.position = from.lerp(ctrl, k).lerp(ctrl.lerp(to, k), k), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	_burst(to, color, 30, 500, 0.5, 0.0)
	_ring(to, color.lerp(Color.WHITE, 0.4), 1.4)
	trail.emitting = false
	head.modulate.a = 0.0
	get_tree().create_timer(0.4).timeout.connect(head.queue_free)


## A big card's entrance: it rises to centre stage in front of turning light rays, holds for a
## beat so its art and foil can be seen, and then the caller slams it into its slot.
func _showcase(v: CardView, c: Dictionary, color: Color, title := "") -> void:
	var center := Vector2(1080, DIVIDER_Y)
	var rays := Node2D.new()
	rays.position = center
	rays.z_index = 415
	rays.material = _add_mat
	rays.modulate.a = 0.0
	rays.scale = Vector2.ONE * 0.3
	rays.draw.connect(func():
		for i in 16:
			var a := i * TAU / 16.0
			var w := 0.07 if i % 2 == 0 else 0.04
			rays.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * 1100.0, Vector2.from_angle(a + w) * 1100.0]),
				PackedColorArray([Color(color.lerp(Color.WHITE, 0.4), 0.45), Color(color, 0.0), Color(color, 0.0)])))
	cards_layer.add_child(rays)
	var t := create_tween().set_parallel()
	t.tween_property(rays, "modulate:a", 1.0, 0.25)
	t.tween_property(rays, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(rays, "rotation", 0.35, 0.95)
	Sfx.play("riser", 0.7)
	_splash_name(title if title != "" else str(c.get("name", "")), color, center.y + 265.0)
	await v.move_to(center, 2.5, 0.0, 0.34, Tween.TRANS_BACK).finished
	v.kick(Vector2(1, -0.4), 18.0)
	_ring(center, color.lerp(Color.WHITE, 0.3), 2.6)
	_burst(center, color.lerp(Color.WHITE, 0.5), 40, 600, 0.9, -200.0)
	_post_pulse("aberration", 6.0, 0.5)
	Sfx.play("effect", 0.7, -2.0)
	await _wait(0.6)
	# Rays fade as the card leaves centre stage
	var out := create_tween()
	out.tween_property(rays, "modulate:a", 0.0, 0.25)
	out.tween_callback(rays.queue_free)


## A split-second stark black-and-white frame at the moment of contact (real time).
func _impact_frame(seconds: float) -> void:
	if _fx_level() < 1.0:   # (the black-and-white frame is the harshest flash of all)
		return
	_post_fx.impact = 1.0
	await get_tree().create_timer(seconds, true, false, true).timeout
	_post_fx.impact = 0.0


## Lean the camera toward a point and zoom in a little.
func _cam_focus(world: Vector2, zoom: float, seconds: float) -> void:
	if _cam_tw and _cam_tw.is_valid():
		_cam_tw.kill()
	_cam_tw = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cam_tw.tween_property(camera, "position", Vector2(960, 540).lerp(world, 0.22), seconds)
	_cam_tw.tween_property(camera, "zoom", Vector2.ONE * zoom, seconds)


func _cam_reset(seconds: float) -> void:
	if _cam_tw and _cam_tw.is_valid():
		_cam_tw.kill()
	_cam_tw = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cam_tw.tween_property(camera, "position", Vector2(960, 540), seconds)
	_cam_tw.tween_property(camera, "zoom", Vector2.ONE, seconds)


## Fast streaks of light thrown out along the direction of a hit.
func _sparks(pos: Vector2, dir: Vector2, color: Color, amount: int, spread := 38.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.38
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = 700.0
	p.initial_velocity_max = 1600.0
	p.damping_min = 1800.0
	p.damping_max = 2600.0
	p.gravity = Vector2.ZERO
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.texture = _streak_tex
	p.material = _add_mat
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.add_point(0.25, color)
	g.set_color(g.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = g
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


## The blow that ends the match: time slows, the screen whites out, the loser's plate shatters.
func _finisher(panel: Control) -> void:
	var at := panel.position + panel.size / 2
	_impact_frame(0.12)
	_post_pulse("aberration", 18.0, 1.2)
	_shockwave(get_viewport().get_canvas_transform().affine_inverse() * at, 1.4)
	_screen_flash(Color.WHITE, 0.6)
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.7, true, false, true).timeout
	Engine.time_scale = _base_speed * _catch_up


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


func _splash_name(card_name: String, color: Color, y := DIVIDER_Y) -> void:
	var l := _label(84, Color.WHITE, true)
	l.text = card_name.to_upper()
	l.size = Vector2(1200, 110)
	l.position = Vector2(1080 - 600, y - 55)
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
	art.visible = art.texture != null   # no art slot when the prompt is not about a card
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
	art.material = UI.card_material(art.size)
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
	text.add_theme_font_size_override("bold_font_size", 16)
	text.meta_underlined = false
	text.mouse_filter = Control.MOUSE_FILTER_PASS   # keywords explain themselves when hovered
	p.add_child(text)
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", _box(INK, Color(0.6, 0.55, 0.9), 2, 8))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.z_index = 50
	var tip_text := RichTextLabel.new()
	tip_text.bbcode_enabled = true
	tip_text.fit_content = true
	tip_text.scroll_active = false
	tip_text.custom_minimum_size = Vector2(300, 0)
	tip_text.add_theme_font_size_override("normal_font_size", 15)
	tip_text.add_theme_font_size_override("bold_font_size", 17)
	tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(tip_text)
	p.add_child(tip)
	text.meta_hover_started.connect(func(meta): _show_keyword_tip(p, tip, tip_text, str(meta)))
	text.meta_hover_ended.connect(func(_meta): tip.visible = false)
	_ui.detail_art = art
	_ui.detail_title = title
	_ui.detail_kind = kind
	_ui.detail_stats = stats
	_ui.detail_text = text
	_show_detail({})


## The hover box for a keyword in the card text, placed above the mouse inside the panel.
func _show_keyword_tip(p: Control, tip: PanelContainer, tip_text: RichTextLabel, kw: String) -> void:
	var desc := Keywords.describe(kw)
	if desc == "":
		return
	tip_text.text = desc
	tip.reset_size()
	tip.visible = true
	await get_tree().process_frame
	var m := p.get_local_mouse_position()
	tip.position = Vector2(clampf(m.x - tip.size.x / 2.0, 4.0, p.size.x - tip.size.x - 4.0), maxf(4.0, m.y - tip.size.y - 14.0))


## A card's statuses for the hover panel: DOWNED first when it is Downed.
func _live_statuses(v: CardView) -> Array:
	return (["downed"] if v.downed else []) + v.statuses

const STATUS_WORDS := {"poison": "POISON", "burn": "BURN", "bleed": "BLEED", "freeze": "FREEZE",
	"stasis": "STASIS", "stun": "STUN", "shield": "SHIELD", "suppress": "SUPPRESS", "downed": "DOWNED",
	"resting": "CAN'T ATTACK THIS TURN (just promoted or Awakened)", "bounty": "BOUNTY"}
## Statuses that aren't keywords (keywords use their own colour, and explain themselves when hovered)
const STATUS_COLORS := {"downed": "ff5a5a", "resting": "ffb35a"}


## A status in the card panel, in its colour: "DOWNED" red, "STASIS" violet...
func _status_word(k) -> String:
	var word: String = STATUS_WORDS.get(k, str(k).to_upper())
	var kw := Keywords.find(word)
	if kw != "" and STATUS_COLORS.get(k) == null:
		return "[url=%s][b][color=#%s]%s[/color][/b][/url]" % [kw, Keywords.LIST[kw][0].to_html(false), word]
	return "[b][color=#%s]%s[/color][/b]" % [STATUS_COLORS.get(k, "e6e6f0"), Keywords._escape(word)]


func _show_detail(c: Dictionary, live_stats := [], live_status := []) -> void:
	var key := "%s:%s:%s" % [c.get("uid", c.get("id", "")), live_stats, live_status]
	if key == _detail_key:
		return
	_detail_key = key
	if c.is_empty():
		_detail_spin = ""
		for style in CardDB.BACK_STYLES.values():
			_ui.detail_art.material.set_shader_parameter(style, 0.0)
		UI.rarity_fx(_ui.detail_art.material, 1)
		_ui.detail_art.texture = CardDB.back()
		_ui.detail_title.text = ""
		_ui.detail_kind.text = ""
		_ui.detail_stats.text = ""
		_ui.detail_text.text = "[color=#8a8aa0]Hover a card to see it here. Right-click it to zoom in.[/color]"
		return
	var tex := CardDB.art(str(c.get("art_url", c.get("id", ""))))
	# A face-down card shows its side's card back (its clan's, or the one its player chose)
	var back: Texture2D = _back_for(str(c.back_side)) if c.has("back_side") else CardDB.back()
	_ui.detail_art.texture = tex if tex else back
	var dm: ShaderMaterial = _ui.detail_art.material
	UI.rarity_fx(dm, int(c.get("rarity", 1)) if tex else 1, 0.37)
	# A clan back moves here too, like on the field (the Nebula galaxy turns, the Militia radar sweeps)
	_detail_spin = CardDB.back_style(_back_clan(str(c.back_side))) if not tex and c.has("back_side") else ""
	for style in CardDB.BACK_STYLES.values():
		dm.set_shader_parameter(style, 1.0 if style == _detail_spin else 0.0)
	_ui.detail_title.text = str(c.get("name", "?"))
	var parts: Array = [TYPE_NAMES.get(c.get("cardType", ""), "CARD")]
	if c.get("subtype") is String:
		parts.append(str(c.subtype).to_upper())
	if str(c.get("clanName", "")) != "":
		parts.append(str(c.clanName).to_upper())
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
	var body := Keywords.markup(str(c.get("effectText", "")))
	if not live_status.is_empty():
		var words: Array = live_status.map(_status_word)
		body = "[color=#8a8aa0]Status:[/color] %s\n\n%s" % ["[color=#8a8aa0]  ·  [/color]".join(words), body]
	if c.get("flavourText") is String:
		body += "\n\n[i][color=#8a8aa0]%s[/color][/i]" % c.flavourText
	if c.get("note") is String:   # (where the card is: shown above its text, not part of it)
		body = "[color=#8a8aa0]%s[/color]\n\n%s" % [Keywords._escape(c.note), body]
	_ui.detail_text.text = body


func _build_panel(side: String, p: Panel, display_name: String, avatar: String, subtitle: String, level := 0) -> void:
	var accent := BLUE if side == "player" else RED
	# Player plates glow in their side's colour
	p.add_theme_stylebox_override("panel", UI._glow(_box(INK, accent, 2, 10), accent, 0.8))
	var av := TextureRect.new()
	av.position = Vector2(14, 14)
	av.size = Vector2(64, 64)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture = UI.avatar(avatar)
	p.add_child(av)
	var n := _label(26, Color.WHITE, true)
	n.text = display_name
	n.position = Vector2(92, 10)
	p.add_child(n)
	var sub := _label(14, accent)
	sub.text = subtitle
	sub.position = Vector2(92, 46)
	if level > 0:   # their level emblem just before the "LV n" text
		var emblem := UI.texture_rect(UI.level_icon(level), Vector2(24, 24))
		emblem.position = Vector2(92, 43)
		p.add_child(emblem)
		sub.position.x = 120
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
	_tension.call_deferred()
	var p: Dictionary = _panels[side]
	var from: float = p.shown
	p.shown = float(value)
	var label: Label = p.morale
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(func(x: float): label.text = str(int(x)), from, float(value), 0.7)
	var bar: ColorRect = p.bar
	var full: float = bar.get_parent().size.x
	var to_w := full * clampf(float(value) / DuelState.START_MORALE, 0.0, 1.0)
	# The ghost: a pale chunk where the lost Morale was, which drains after a beat
	var ghost: ColorRect = p.get("ghost")
	if ghost == null:
		ghost = ColorRect.new()
		ghost.size = bar.size
		ghost.color = Color(1.0, 0.92, 0.8, 0.8)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.get_parent().add_child(ghost)
		bar.get_parent().move_child(ghost, bar.get_index())
		p["ghost"] = ghost
	if value < from:
		ghost.size.x = maxf(ghost.size.x, bar.size.x)
		t.tween_property(bar, "size:x", to_w, 0.14)
		var g := create_tween()
		g.tween_interval(0.4)
		g.tween_property(ghost, "size:x", to_w, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		ghost.size.x = to_w
		t.tween_property(bar, "size:x", to_w, 0.7)
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
	if _watching():
		b.disabled = true   # a replay or a friend's match: only watching
		b.text = "WATCHING" if _spectating else "REPLAY"
		return
	var mine := duel.active == "player" and not "player" in ai_sides
	b.disabled = not mine or duel.winner != "" or not duel.pending.is_empty() or _awaiting
	if b.disabled:
		_nudge_next(false)
	if _out.has("player"):
		b.text = "YOU'RE OUT · %s" % _place_text(int(_out.player))
	elif not mine:
		b.text = ("%s'S TURN" % str(_names.get(duel.active, "THEIR")).to_upper()) if _ffa else "OPPONENT'S TURN"
	else:
		match duel.phase:
			"deployment":
				b.text = "TO REGROUP  ▶" if duel.no_attacks_yet() else "TO BRAWL  ▶"
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


## The duel's music and the street around it (Game.sound); the neon starts acting up.
func _play_music() -> void:
	Game.sound.music("duel", 2.0)
	Game.sound.ambience("city_rain")
	_neon_loop()


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
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
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
	# On the alley mat the slots are painted lines like its parking bays (one bay's paint, nine-sliced)
	if ResourceLoader.exists("res://assets/arena_paint.png") and ResourceLoader.exists("res://assets/arena_1v1.png"):
		var paint: Texture2D = load("res://assets/arena_paint.png")
		for kind in ["front", "back", "pile"]:
			var sb := StyleBoxTexture.new()
			sb.texture = paint
			sb.set_texture_margin_all(30)
			sb.draw_center = false
			sb.modulate_color = {"front": Color(1, 1, 1, 0.8), "back": Color(0.72, 0.82, 1.0, 0.55), "pile": Color(1, 1, 1, 0.38)}[kind]
			_paint[kind] = sb


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
	var moves := 0   # (none left: the next-phase button breathes, see _nudge_next)
	for v in hand.player:   # cards a passive makes cheaper show their new cost
		var cost: int = duel.cost_of("player", v.card)
		v.cost_now = cost if cost < int(v.card.get("authority", 0)) else -1
	if duel.can_deploy_now("player"):
		for v in hand.player:
			if _playable(v.card):
				v.glow_color = GREEN
				v.glow = 0.75
				moves += 1
	for slot in field.player:
		var ready := duel.can_attack_with("player", slot) or duel.can_promote("player", slot) \
			or duel.can_use_ability("player", slot)
		var can_activate := not duel.activations("player", slot).is_empty() or _set_ready(slot)
		if ready or can_activate:
			# Gold: can act. Teal pulse: an ability can be activated (gold to teal when both)
			field.player[slot].glow_color = GOLD if ready else TEAL
			field.player[slot].glow = 0.9
			if can_activate:
				field.player[slot].pulse_color = TEAL
			moves += 1
	_nudge_next(moves == 0)


var _next_pulse: Tween = null


## Nothing left to do this phase: the next-phase / End Turn button breathes gold; anything to do: it's still.
func _nudge_next(on: bool) -> void:
	if not _ui.has("next"):
		return
	var b: Button = _ui.next
	if _next_pulse and _next_pulse.is_valid():
		_next_pulse.kill()
	_next_pulse = null
	b.modulate = Color.WHITE
	if not on or b.disabled:
		return
	_next_pulse = b.create_tween().set_loops()
	_next_pulse.tween_property(b, "modulate", Color(1.35, 1.2, 0.75), 0.7).set_trans(Tween.TRANS_SINE)
	_next_pulse.tween_property(b, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)



## A note over the bottom of the card panel (this week's challenge): GOT IT or 30 seconds.
func _tip_panel(heading: String, text: String, accent: Color) -> void:
	_close_tip()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.96), accent, 2, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var head := _label(20, accent, true)
	head.text = heading
	col.add_child(head)
	var body := _label(16, Color.WHITE)
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(340, 0)
	col.add_child(body)
	var ok := Button.new()
	ok.text = "GOT IT"
	ok.custom_minimum_size = Vector2(120, 34)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func():
		Sfx.play("click")
		_close_tip())
	col.add_child(ok)
	overlay.add_child(box)
	# Over the bottom of the card panel on the left, out of the way of the board
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(34, 790 - sz.y)
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.25)
	_tip_box = box
	Sfx.play("effect", 1.5, -10.0)
	get_tree().create_timer(30.0).timeout.connect(func():
		if _tip_box == box:
			_close_tip())


func _close_tip() -> void:
	var box := _tip_box
	_tip_box = null
	if box and is_instance_valid(box):
		var t := create_tween()
		t.tween_property(box, "modulate:a", 0.0, 0.2)
		t.tween_callback(box.queue_free)


## A prompt from a card effect: buttons for each option, and the cards it refers to light up
## (click one of those to choose it too).
func _show_choice(p: Dictionary) -> void:
	# Choosing a card on the field (an effect's target): click it there, no list over the board
	var on_field: Array = p.options.filter(func(o): return o.has("slot"))
	var rest: Array = p.options.filter(func(o): return not o.has("slot"))
	if not on_field.is_empty() and str(p.get("key", "")) != "ambush" and rest.all(func(o): return str(o.id) == "skip"):
		_show_target_choice(p)
		return
	# Choosing a card from a pile (a deck search, the Gutter): the cards themselves, to click
	if p.options.any(func(o): return o.get("card") is Dictionary):
		_show_card_choice(p)
		return
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
	art.visible = art.texture != null   # no art slot when the prompt is not about a card
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
		if _ffa and str(p.get("key", "")) == "foe" and o.has("side"):   # "choose an opponent": their name and Morale
			b.text = "%s  ·  %d MORALE" % [str(_names.get(o.side, o.label)).to_upper(), int(duel.sides.get(o.side, {}).get("morale", 0))]
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


## A search (or Gutter) pick: the cards laid out to choose from, like a pile's view. Hovering one
## shows it in the card panel; click to take it, or SKIP.
func _show_card_choice(p: Dictionary) -> void:
	_cancel_interaction()
	_mode = "choose"
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.97), GOLD, 3, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var title := _label(24, Color.WHITE, true)
	title.text = str(p.get("prompt", "Choose a card"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.custom_minimum_size = Vector2(560, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var cards: Array = p.options.filter(func(o): return o.get("card") is Dictionary)
	var grid := GridContainer.new()
	grid.columns = mini(cards.size(), 4)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var center := CenterContainer.new()
	center.add_child(grid)
	col.add_child(center)
	var size := CARD * 1.25
	for o in cards:
		var c: Dictionary = o.card
		var b := TextureButton.new()
		b.texture_normal = CardDB.art(str(c.get("art_url", c.get("id", ""))))
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = size
		b.pivot_offset = size / 2
		b.tooltip_text = str(o.get("label", ""))
		b.mouse_entered.connect(func():
			_show_detail(c)
			Sfx.play("click", 1.4, -12.0)
			b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.08, 0.1))
		b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
		b.pressed.connect(_pick.bind(str(o.id)))
		grid.add_child(b)
	var hint := _label(15, Color(0.7, 0.72, 0.85))
	hint.text = "Hover a card to read it  ·  click to take it"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	for o in p.options:   # (SKIP, and any option that isn't a card)
		if o.get("card") is Dictionary:
			continue
		var b := Button.new()
		b.text = str(o.label)
		b.custom_minimum_size = Vector2(220, 44)
		b.pressed.connect(_pick.bind(str(o.id)))
		var row := CenterContainer.new()
		row.add_child(b)
		col.add_child(row)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, clampf(DIVIDER_Y - sz.y / 2, 10, 1070 - sz.y))
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.15)
	_menu = box
	Sfx.play("draw", 1.2, -6.0)


## A slim bar in the gap between the rows: what to choose (and SKIP); the targets glow on the field.
func _show_target_choice(p: Dictionary) -> void:
	_cancel_interaction()
	_mode = "choose"
	for o in p.options:
		if o.has("slot"):
			_valid["%s:%d" % [o.side, o.slot]] = GOLD
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.94), GOLD, 2, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var title := _label(18, Color.WHITE, true)
	title.text = "%s  ·  click a glowing card" % p.prompt
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	for o in p.options:
		if not o.has("slot"):
			var b := Button.new()
			b.text = o.label
			b.custom_minimum_size = Vector2(110, 30)
			b.pressed.connect(_pick.bind(str(o.id)))
			row.add_child(b)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, DIVIDER_Y - sz.y / 2)
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.15)
	_menu = box
	Sfx.play("effect", 1.3, -6.0)
	queue_redraw()


## A prompt that picks a card on the field: the glowing card at p (if any) is the answer.
func _choose_at(p: Vector2) -> bool:
	for side in _sides:
		var slot := _slot_at(side, p)
		if slot >= 0 and _valid.has("%s:%d" % [side, slot]):
			for o in duel.pending.get("options", []):
				if o.get("side") == side and o.get("slot") == slot:
					_pick(str(o.id))
					return true
	return false


func _pick(option: String) -> void:
	Sfx.play("click")
	_cancel_interaction()
	_act("player", {"kind": "choose", "option": option})


## Whether card c from the hand can be set face-down somewhere in the back row (an Ambush, a Hustle).
func _settable(c: Dictionary) -> bool:
	return DuelState.BACK.any(func(s): return duel.can_set("player", c, s))


## Whether the Hustle set in slot can be activated now.
func _set_ready(slot: int) -> bool:
	var c = duel.card_at("player", slot)
	return c != null and duel.set_hustle_slot("player", c) == slot and duel.can_hustle("player", c)


func _playable(c: Dictionary) -> bool:
	match c.get("cardType", ""):
		"gang_member":
			return duel.can_summon_somewhere("player", c)
		"ambush":
			return _settable(c)
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_toggle_log()
		return
	if _spectating and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_menu()
		return
	# Right-click a card you can see (when not in the middle of a play): zoom in, with a Striver's levels
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed 			and not _dragging and not _mode in ["menu", "place", "target", "choose", "discard"] and _zoom_hovered():
		return
	if _watching() and not event is InputEventMouseMotion:
		return   # watching a replay or a friend's match: hovering shows cards, nothing else
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
			KEY_E:
				if _online and not str(Game.duel_setup.get("start", {}).get("mode", "")).begins_with("cpu"):
					_toggle_emote_menu()
			KEY_F11:
				var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Opens the big view of the card under the mouse (face-up ones, and your own face-down ones).
func _zoom_hovered() -> bool:
	var v := _view_at(get_global_mouse_position())
	if v == null or v.card.is_empty() or not (v.face_up or v.side == "player"):
		return false
	var base := CardDB.get_card(str(v.card.get("id", "")))
	UI.card_zoom($HUD/UI, base if not base.is_empty() else v.card)
	return true


func _view_at(p: Vector2) -> CardView:
	var hv := _hand_view_at(p)
	if hv:
		return hv
	for s in hand:   # an opponent's hand: a hovered card's back comes alive, like a face-down card's
		if s == "player":
			continue
		var top: CardView = null
		for v in hand[s]:
			if is_instance_valid(v) and not v.busy and v.hit(p) and (top == null or v.z_index > top.z_index):
				top = v
		if top:
			return top
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
		if old and is_instance_valid(old):
			old.hovered = false
		if v:
			v.hovered = true
		if old and is_instance_valid(old) and old in hand.player and old != _selected:
			_layout_hand("player")
		if v and v in hand.player and _mode != "place":
			v.z_index = 300
			v.move_to(Vector2(v.home.x, HAND_LIFT_Y), HOVER_SCALE, 0.0, 0.14)
			Sfx.play("click", 1.4, -12.0)
	if v:
		if not v.face_up and v.side == "player" and not v.card.is_empty():
			_show_detail(v.card, v.stats(), _live_statuses(v))   # your own face-down card: you know what it is
		elif not v.face_up:
			_show_detail({"name": "Face-down card", "cardType": "", "uid": -v.uid, "back_side": v.side})
		else:
			_show_detail(v.card, v.stats(), _live_statuses(v))
		return
	for side in _sides:
		if Rect2(pile_pos(side, "gutter") - CARD * _sc(side) / 2, CARD * _sc(side)).has_point(m):
			var top: String = counts.get(side, {}).get("gutter_top", "")
			if top != "":
				var shown: Dictionary = CardDB.get_card(top).duplicate()
				shown.note = "Top of the Gutter · click to see every card in it"
				shown.uid = "gutter:%s:%s" % [side, top]
				_show_detail(shown)
		# The deck and Hideout show that side's card back, with how many cards are in them
		for pile in ["deck", "hideout"]:
			if Rect2(pile_pos(side, pile) - CARD * _sc(side) / 2, CARD * _sc(side)).has_point(m):
				var n: int = counts.get(side, {}).get(pile, 0)
				var whose := "Your" if side == "player" else ("%s's" % _names.get(side, "Their")) if _ffa else "Their"
				_show_detail({"name": "%s %s" % [whose, "Deck" if pile == "deck" else "Hideout"], "cardType": "",
					"uid": "%s:%s:%d" % [side, pile, n], "back_side": side,
					"effectText": "%d card%s%s" % [n, "" if n == 1 else "s",
						"  ·  click to see them" if pile == "hideout" and side == "player" and n > 0 else ""]})


func _on_press() -> void:
	if _mode == "over":
		return
	var m := get_global_mouse_position()
	if _mode == "menu":
		_cancel_and_refresh()
		return
	if _playing or _awaiting:
		return
	if _mode == "idle" and _pile_at(m) != []:
		var at: Array = _pile_at(m)
		_show_pile(at[0], at[1])
		return
	match _mode:
		"choose":
			_choose_at(m)
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
			if _ffa:
				_target_ffa(m)
				return
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


## "ACTIVATE  (2 AUTHORITY)": the menu entry for the card's k-th activated ability (Card Forge).
func _activate_label(slot: int, k: int, numbered: bool) -> String:
	var e: Dictionary = duel._fx(duel.card_at("player", slot), "activate")[k - 1]
	var n: int = maxi(1, int(e.get("cost_n", 1)))
	var cost: String = {"authority": "%d AUTHORITY" % n, "morale": "%d MORALE" % n, "discard": "DISCARD %d" % n,
		"sacrifice": "SACRIFICE AN ALLY", "exhaust": "NO ATTACK THIS TURN"}.get(str(e.get("cost", "")), "")
	return "ACTIVATE%s%s" % [" %d" % k if numbered else "", "  (%s)" % cost if cost != "" else ""]


## Click your own character: attack right away when that's the only option, otherwise a menu
## (attack, change position, promote, ability, activate).
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
	var abilities: Array = duel.activations("player", slot)
	for k in abilities:
		opts.append([_activate_label(slot, k, abilities.size() > 1), true, _field_action.bind({"kind": "activate", "slot": slot, "fx": k})])
	var reason := ""
	var set_card = duel.card_at("player", slot)
	if set_card != null and duel.set_hustle_slot("player", set_card) == slot:
		# A Hustle you set face-down: activate it, paying for it now
		var cost: int = duel.cost_of("player", set_card)
		var ok: bool = duel.can_hustle("player", set_card)
		if not ok:
			if duel.sides.player.authority < cost:
				reason = "Needs %d Authority (you have %d)" % [cost, duel.sides.player.authority]
			else:
				reason = "Requirements not met"
		opts.append(["ACTIVATE %s%s" % [str(set_card.name).to_upper(), "  (%d AUTHORITY)" % cost if cost > 0 else ""], ok,
			_field_action.bind({"kind": "hustle", "uid": int(set_card.uid)})])
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
	_menu = _make_menu(opts, reason, v.home + Vector2(0, -CARD.y / 2 - 12))


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
	if _ffa:
		_begin_target_ffa(slot)
		return
	var targets := duel.attack_targets("player")
	for t in targets:
		if t >= 0:
			_valid["opponent:%d" % t] = RED
	if DuelState.DIRECT in targets:
		_show_direct_button(slot)
	var parts: Array = []
	if targets.any(func(t): return t >= 0):
		parts.append("choose a character")
	if DuelState.DIRECT in targets:
		parts.append("attack directly")
	if DuelState.LEADER in targets and leaders.has("opponent"):
		leaders.opponent.glow_color = RED
		leaders.opponent.glow = 1.0
		parts.append("hit the dormant leader's Influence")
	var text := ", ".join(parts)
	_show_prompt(text.left(1).to_upper() + text.substr(1) + "  ·  right-click to cancel")
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
	if s.authority < duel.cost_of("player", c):
		reason = "Needs %d Authority (you have %d)" % [duel.cost_of("player", c), s.authority]
	match c.get("cardType", ""):
		"gang_member":
			var ok := _playable(c)
			var heavy := DuelState.needs_tribute(c)
			var need := DuelState.tributes_for(c)
			if ok == false and reason == "":
				reason = ("Needs %d of your characters to sacrifice" % need if need > 1 else "Needs one of your characters to sacrifice") if heavy else "No free front-row slot"
			var cost := "  ·  SACRIFICE %d" % need if heavy else ""
			opts.append(["SUMMON  ·  ATK" + cost, ok, func(): _begin_place(v, "summon_atk")])
			opts.append(["SUMMON  ·  DEF" + cost, ok, func(): _begin_place(v, "summon_def")])
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
			# Or face-down in the back row, to activate when you choose (paid for then)
			opts.append(["SET FACE DOWN", _settable(c), func(): _begin_place(v, "set")])
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
	if kind != "set" and DuelState.needs_tribute(c):
		_tribute_picks = []
		_show_tribute_pick(c)
		return
	var over := false
	for slot in 10:
		if kind == "set":
			if duel.can_set("player", c, slot):
				_valid["player:%d" % slot] = GREEN
		elif duel.can_summon("player", c, slot):
			_valid["player:%d" % slot] = GREEN
		elif duel.can_summon("player", c, slot, slot):
			_valid["player:%d" % slot] = SWAP   # deploy over it: it goes to the Gutter
			over = true
	_show_prompt("Choose a slot%s  ·  right-click to cancel" % (", or one of your characters to deploy over (it goes to the Gutter)" if over else ""))
	queue_redraw()


## A Heavy's sacrifices, one click each (click again to take one back); it takes the first one's lane.
func _show_tribute_pick(c: Dictionary) -> void:
	_valid.clear()
	for slot in DuelState.FRONT:
		if duel.can_sacrifice("player", slot):
			_valid["player:%d" % slot] = PICKED if slot in _tribute_picks else RED
	var need := DuelState.tributes_for(c)
	if need <= 1:
		_show_prompt("Choose a character to sacrifice: %s takes its lane  ·  right-click to cancel" % c.name)
	else:
		_show_prompt("Choose %d characters to sacrifice for %s (%d chosen): it takes the first one's lane  ·  right-click to cancel" % [need, c.name, _tribute_picks.size()])
	queue_redraw()


func _place(slot: int) -> void:
	var v := _selected
	var kind := _place_kind
	var tributes: Array = []
	if kind != "set" and DuelState.needs_tribute(v.card):
		if slot in _tribute_picks:
			_tribute_picks.erase(slot)   # taken back
		else:
			_tribute_picks.append(slot)
		if _tribute_picks.size() < DuelState.tributes_for(v.card):
			_show_tribute_pick(v.card)
			return
		tributes = _tribute_picks.duplicate()
		slot = tributes[0]
	elif kind != "set" and duel.sides.player.field[slot] != null:
		tributes = [slot]   # deployed over one of your characters
	_cancel_interaction()
	match kind:
		"summon_atk":
			_act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk", "tributes": tributes})
		"summon_def":
			_act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "def", "tributes": tributes})
		"set":
			_act("player", {"kind": "set", "uid": v.uid, "slot": slot})


func _start_drag() -> void:
	var v := _press
	if not is_instance_valid(v) or not (_playable(v.card) or _settable(v.card)):
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
	var over := false
	for slot in 10:
		if DuelState.needs_tribute(c):
			if slot in DuelState.FRONT and duel.can_sacrifice("player", slot):
				_valid["player:%d" % slot] = RED   # drop a Heavy on a character to sacrifice
		elif duel.can_summon("player", c, slot) or duel.can_set("player", c, slot):
			_valid["player:%d" % slot] = GREEN
		elif duel.can_summon("player", c, slot, slot):
			_valid["player:%d" % slot] = SWAP   # drop it on one of your characters to deploy over it
			over = true
	if DuelState.needs_tribute(c):
		var need := DuelState.tributes_for(c)
		_show_prompt("Drop %s on one of your characters to sacrifice it%s" % [c.name, " (then choose %d more)" % (need - 1) if need > 1 else ""])
	elif over and not _valid.values().has(GREEN):
		_show_prompt("Drop %s on one of your characters to deploy over it (it goes to the Gutter)" % c.name)
	if c.cardType == "hustle":
		_show_prompt("Release on the board, then activate it or set it face down")
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
	if c.cardType == "gang_member" and DuelState.needs_tribute(c) and duel.can_sacrifice("player", slot) and duel.can_summon_somewhere("player", c):
		# Dropping a Heavy on one of your characters sacrifices it (and any more it needs: choose them)
		if DuelState.tributes_for(c) <= 1:
			done = _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk", "tributes": [slot]})
		else:
			_layout_hand("player")
			_selected = v
			_place_kind = "summon_atk"
			_mode = "place"
			_tribute_picks = [slot]
			_show_tribute_pick(c)
			return
	elif c.cardType == "gang_member" and (duel.can_summon("player", c, slot) or duel.can_summon("player", c, slot, slot)):
		_ask_position(v, slot)   # ATK or DEF? (and over one of your characters: it goes to the Gutter)
		return
	elif c.cardType == "ambush" and duel.can_set("player", c, slot):
		done = _act("player", {"kind": "set", "uid": v.uid, "slot": slot})
	elif c.cardType == "hustle" and m.y < HAND_Y - 140 and (duel.can_hustle("player", c) or _settable(c)):
		_ask_hustle(v, slot)   # activate it now, or set it face-down?
		return
	if not done:
		_layout_hand("player")
		_player_ready()


## A Hustle dropped on the board: ACTIVATE it now, or SET it face-down to use when you choose (in the
## back-row slot it was dropped on, else the first free one), or put it back.
func _ask_hustle(v: CardView, slot: int) -> void:
	_mode = "menu"
	_selected = v   # (cancelling puts it back in the hand)
	var c := v.card
	var at := get_global_mouse_position()
	v.move_to(at, 1.0, 0.0, 0.15)
	var back := slot if slot in DuelState.BACK and duel.can_set("player", c, slot) else -1
	for s in DuelState.BACK:
		if back < 0 and duel.can_set("player", c, s):
			back = s
	var put_back := func():
		_cancel_interaction()
		_layout_hand("player")
		_player_ready()
	var can_play: bool = duel.can_hustle("player", c)
	var cost: int = duel.cost_of("player", c)
	var reason := ""
	if not can_play:
		reason = "Needs %d Authority to activate (you have %d)" % [cost, duel.sides.player.authority] if duel.sides.player.authority < cost \
			else "Can't be activated right now"
	_menu = _make_menu([
		["ACTIVATE%s" % ("  (%d AUTHORITY)" % cost if cost > 0 else ""), can_play, func():
			_cancel_interaction()
			if not _act("player", {"kind": "hustle", "uid": v.uid}):
				put_back.call()],
		["SET FACE DOWN", back >= 0, func():
			_cancel_interaction()
			if not _act("player", {"kind": "set", "uid": v.uid, "slot": back}):
				put_back.call()],
		["CANCEL", true, put_back],
	], reason, at + Vector2(0, -CARD.y / 2 - 12))


## A character dropped on the board: summon it in ATK or DEF (or put it back).
func _ask_position(v: CardView, slot: int) -> void:
	_mode = "menu"
	_selected = v   # (cancelling puts it back in the hand)
	v.move_to(slot_pos("player", slot) + Vector2(0, 40), 1.0, 0.0, 0.15)
	var put_back := func():
		_cancel_interaction()
		_layout_hand("player")
		_player_ready()
	var over = duel.sides.player.field[slot]   # deployed over: it goes to the Gutter
	var tributes: Array = [slot] if over != null else []
	_menu = _make_menu([
		["SUMMON · ATK", true, func():
			_cancel_interaction()
			if not _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk", "tributes": tributes}):
				put_back.call()],
		["SUMMON · DEF", true, func():
			_cancel_interaction()
			if not _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "def", "tributes": tributes}):
				put_back.call()],
		["CANCEL", true, put_back],
	], "Replaces %s: it goes to the Gutter" % over.name if over != null else "", slot_pos("player", slot) + Vector2(0, -CARD.y / 2 - 12))


func _show_direct_button(slot: int) -> void:
	var b := Button.new()
	b.text = "DIRECT ATTACK  ⚔"
	b.custom_minimum_size = Vector2(340, 62)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", _box(Color("4a0d14"), RED, 3, 10))
	# Up by the opponent's hand, away from the board, so it isn't clicked by mistake
	b.position = Vector2(1080 - 170, 8)
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
	for b in _direct_btns:
		if is_instance_valid(b):
			b.queue_free()
	_direct_btns.clear()
	_valid.clear()
	_tribute_picks = []
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


## The pile under p that can be looked through: [side, "gutter" | "hideout"] (your own Hideout only), or [].
func _pile_at(p: Vector2) -> Array:
	for side in _sides:
		for pile in ["gutter", "hideout"]:
			if pile == "hideout" and side != "player":
				continue   # the opponent's Hideout stays secret
			if Rect2(pile_pos(side, pile) - CARD * _sc(side) / 2, CARD * _sc(side)).has_point(p):
				return [side, pile]
	return []


## Every card in a Gutter (newest first) or your Hideout; hover one to read it, click away to close.
func _show_pile(side: String, pile: String) -> void:
	var cards: Array = duel.sides[side].get(pile, []).filter(func(c): return c is Dictionary and c.has("id"))
	if pile == "gutter":
		cards.reverse()
	_cancel_interaction()
	_mode = "menu"
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.97), GOLD, 2, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)
	var title := _label(26, Color.WHITE, true)
	title.text = "%s %s  ·  %d card%s" % ["YOUR" if side == "player" else "THEIR", pile.to_upper(), cards.size(), "" if cards.size() == 1 else "s"]
	col.add_child(title)
	if cards.is_empty():
		var none := _label(18, Color("8a8aa0"))
		none.text = "Nothing here yet."
		col.add_child(none)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(6 * 132, minf(2.0, ceilf(cards.size() / 6.0)) * 183)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		for c in cards:
			var t := TextureRect.new()
			t.texture = CardDB.art(str(c.get("art_url", c.get("id", ""))))
			t.custom_minimum_size = CARD
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.mouse_filter = Control.MOUSE_FILTER_PASS
			t.tooltip_text = str(c.get("name", ""))
			var card: Dictionary = c
			t.mouse_entered.connect(func(): _show_detail(card))
			grid.add_child(t)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(200, 40)
	close.pressed.connect(func():
		Sfx.play("click")
		_cancel_and_refresh())
	col.add_child(close)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, clampf(DIVIDER_Y - sz.y / 2, 10, 1070 - sz.y))
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.15)
	_menu = box
	Sfx.play("draw", 1.2, -6.0)


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
	for label in ["RESUME", "HOW TO PLAY", "SETTINGS", "STOP WATCHING" if _spectating else "CONCEDE" if _online else "LEAVE DUEL"]:
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
		"HOW TO PLAY":
			_toggle_menu()
			load("res://scripts/ui/how_to_play.gd").open(overlay)
		"SETTINGS":
			_toggle_menu()
			SettingsPanel.open(overlay, false)
		"CONCEDE":
			_toggle_menu()
			if _ffa:
				UI.dialog(overlay, "LEAVE THE FREE-FOR-ALL?", "You're out, in the last place still open, and the others play on.", [
					["CONCEDE", func(): Net.send("ffa:concede", {"matchId": _match_id}), RED], ["KEEP FIGHTING", func(): pass]])
				return
			UI.dialog(overlay, "CONCEDE THE MATCH?", "Your opponent wins and the match is recorded as a loss.", [
				["CONCEDE", func(): Net.send("mp:concede", {"matchId": _match_id}), RED], ["KEEP FIGHTING", func(): pass]])
		"STOP WATCHING":
			_stop_watching()
		"LEAVE DUEL":
			UI.dialog(overlay, "LEAVE THE DUEL?", "You'll lose this match's progress and get no rewards.", [
				["LEAVE", func(): Game.go("main_menu"), RED], ["STAY", func(): pass]])
		"REMATCH":
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		"QUIT":
			get_tree().quit()


# ── Free-for-all (3-4 players) ───────────────────────────────────────────────
# Every board is on screen: yours as in a duel, each opponent's smaller along the top (their plate
# above it), in turn order after you (foe1, foe2, foe3). Attacks and card choices can go at any of
# them; a player who goes out has their board darkened with their place.

## Who's at the table, and where each opponent's board goes.
func _setup_ffa_sides(start: Dictionary) -> void:
	_ffa = true
	var view: Dictionary = start.get("view", {})
	var seats: Array = view.get("seats", []) if view.get("seats") is Array else []
	_foes = seats.filter(func(x): return x != "player")
	_foes.sort()
	_sides = ["player"]
	_sides.append_array(_foes)
	hand = {}
	field = {}
	for side in _sides:
		hand[side] = []
		field[side] = {}
	# Four boards close round the middle of the crossroads: the first two opponents (in turn order,
	# clockwise from you) on top, you bottom-left, the third bottom-right. Plates sit on the side toward
	# the middle, facing each other across it.
	var k := FFA_CARD_K
	var p := Vector2(FFA_STEP.x / (COLS[1] - COLS[0]), FFA_STEP.y / absf(ROWS.player[1] - ROWS.player[0]))
	var half_w := (RIGHT_X - LEFT_X) * p.x / 2.0 + CARD.x * k / 2.0
	var half_h := FFA_STEP.y / 2.0 + CARD.y * k / 2.0
	var place := func(side: String, lot: String) -> void:
		var top := lot.begins_with("t")
		var c := FFA_MID + Vector2((half_w + FFA_GAP.x / 2.0) * (-1.0 if lot.ends_with("l") else 1.0),
			(FFA_GAP.y / 2.0 + PLATE_H + 8.0 + half_h) * (-1.0 if top else 1.0))
		_boards[side] = {"c": c, "s": k, "p": p, "rows": "opponent" if top else "player",
			"plate": c.y + half_h + 8.0 if top else c.y - half_h - 8.0 - PLATE_H}
	var lots := ["tl", "tr", "br"]
	for i in _foes.size():
		place.call(_foes[i], lots[mini(i, 2)])
	place.call("player", "bl")


## FFA: a side's plate, as wide as its board (piles and all).
func _plate_rect(side: String) -> Rect2:
	var b: Dictionary = _boards[side]
	var half: float = (RIGHT_X - LEFT_X) / 2.0 * (b.get("p", Vector2.ONE * float(b.s)) as Vector2).x + CARD.x / 2.0 * float(b.s)
	return Rect2(b.c.x - half, float(b.plate), half * 2.0, PLATE_H)


## Each opponent's plate (on the board, under the cards, so their hand fan shows on it).
func _build_foe_plates(players: Dictionary) -> void:
	for i in _foes.size():
		var side: String = _foes[i]
		var p := Panel.new()
		p.position = _plate_rect(side).position
		p.size = _plate_rect(side).size
		p.z_index = 2
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards_layer.add_child(p)
		_build_plate(side, p, players.get(side, {}) if players.get(side) is Dictionary else {}, FOE_COLORS[i % FOE_COLORS.size()])
	# Yours: a name tag over your board, like theirs (your Morale is on your panel)
	var mine: Dictionary = _boards.get("player", {})
	if mine.is_empty():
		return
	var prof: Dictionary = players.get("player", {}) if players.get("player") is Dictionary else {}
	var tag := Panel.new()
	tag.position = _plate_rect("player").position
	tag.size = _plate_rect("player").size
	tag.z_index = 2
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", UI._glow(_box(INK, BLUE, 2, 8), BLUE, 0.6))
	cards_layer.add_child(tag)
	var av := TextureRect.new()
	av.position = Vector2(8, 8)
	av.size = Vector2(52, 52)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture = UI.avatar(str(prof.get("avatar_url", "")) if prof.get("avatar_url") else "")
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(av)
	var n := _label(20, Color.WHITE, true)
	n.text = str(prof.get("username", Game.player.get("username", "YOU"))).to_upper().left(14)
	n.position = Vector2(68, 4)
	tag.add_child(n)
	var sub := _label(12, BLUE)
	sub.text = "YOU"
	sub.position = Vector2(68, 30)
	tag.add_child(sub)


## A compact plate: picture, name, Morale (and its bar), Authority, hand and deck.
func _build_plate(side: String, p: Panel, prof: Dictionary, accent: Color) -> void:
	p.add_theme_stylebox_override("panel", UI._glow(_box(INK, accent, 2, 8), accent, 0.6))
	var av := TextureRect.new()
	av.position = Vector2(8, 8)
	av.size = Vector2(52, 52)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture = UI.avatar("cpu" if prof.get("cpu", false) else str(prof.get("avatar_url", "")) if prof.get("avatar_url") else "")
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(av)
	var n := _label(20, Color.WHITE, true)
	n.text = str(prof.get("username", "PLAYER")).to_upper().left(14)
	n.position = Vector2(68, 4)
	p.add_child(n)
	var sub := _label(12, accent)
	sub.text = "CPU" if prof.get("cpu", false) else "LV %d" % int(prof.get("level", 1))
	sub.position = Vector2(68, 30)
	p.add_child(sub)
	var morale := _label(30, Color.WHITE, true)
	morale.text = str(DuelState.START_MORALE)
	morale.label_settings.outline_color = Color(accent, 0.8)
	morale.size = Vector2(p.size.x - 16, 36)
	morale.position = Vector2(8, 2)
	morale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(morale)
	var track := ColorRect.new()
	track.position = Vector2(68, 50)
	track.size = Vector2(p.size.x - 76 - 110, 6)
	track.color = Color(1, 1, 1, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(track)
	var bar := ColorRect.new()
	bar.size = track.size
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	var auth := _label(13, GOLD, true)
	auth.position = Vector2(8, 64)
	auth.pivot_offset = Vector2(0, 8)
	p.add_child(auth)
	var piles := _label(12, Color(0.62, 0.66, 0.82))
	piles.position = Vector2(150, 66)
	p.add_child(piles)
	var flash := ColorRect.new()
	flash.color = Color(1, 0.15, 0.15, 0)
	flash.size = p.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(flash)
	_panels[side] = {"root": p, "morale": morale, "bar": bar, "auth": auth, "piles": piles,
		"flash": flash, "shown": float(DuelState.START_MORALE), "base": p.position, "accent": accent}


## An opponent's colour (their plate's): red, orange, violet. You: blue.
func _side_color(side: String) -> Color:
	if side == "player":
		return BLUE
	return _panels.get(side, {}).get("accent", RED) if _ffa else RED


## FFA: an opponent's hand is a small fan of card backs on the right of their plate.
func _layout_foe_hand(side: String, views: Array) -> void:
	var p: Control = _panels[side].root if _panels.has(side) else null
	var right: float = p.position.x + p.size.x - 26.0 if p else _board_rect(side).end.x
	var y: float = p.position.y + 62.0 if p else _board_rect(side).position.y
	var n := views.size()
	var gap := minf(11.0, 100.0 / maxf(1.0, n))
	for i in n:
		var v: CardView = views[i]
		v.home = Vector2(right - (n - 1 - i) * gap, y)
		v.home_scale = FOE_HAND / maxf(0.01, v.board_scale)
		v.home_rot = 0.0
		v.z_index = 20 + i
		if not v.busy:
			v.go_home(0.22)


static func _place_text(place: int) -> String:
	return {1: "1ST", 2: "2ND", 3: "3RD"}.get(place, "%dTH" % place)


## Attack: the targets glow on every opponent's board; DIRECT buttons on the plates of those who
## have nobody standing; a dormant leader glows too.
func _begin_target_ffa(slot: int) -> void:
	var parts := {}
	for foe in duel.foes_of("player"):
		var targets: Array = duel.attack_targets("player", foe)
		for t in targets:
			if t >= 0:
				_valid["%s:%d" % [foe, t]] = RED
				parts["choose a character"] = true
		if DuelState.LEADER in targets and leaders.has(foe):
			leaders[foe].glow_color = RED
			leaders[foe].glow = 1.0
			parts["hit a dormant leader's Influence"] = true
		if DuelState.DIRECT in targets and _panels.has(foe):
			var root: Control = _panels[foe].root
			var b := Button.new()
			b.text = "DIRECT ⚔"
			b.custom_minimum_size = Vector2(150, 40)
			b.add_theme_font_size_override("font_size", 20)
			b.add_theme_stylebox_override("normal", _box(Color("4a0d14"), RED, 2, 8))
			b.position = Vector2(root.position.x + root.size.x / 2 - 75, root.position.y + root.size.y + 2)
			b.z_index = 60
			b.pressed.connect(func():
				_cancel_interaction()
				_act("player", {"kind": "attack", "from": slot, "target": DuelState.DIRECT, "foe": foe}))
			cards_layer.add_child(b)
			_direct_btns.append(b)
			parts["attack someone directly"] = true
	var text := ", ".join(parts.keys())
	_show_prompt(text.left(1).to_upper() + text.substr(1) + "  ·  right-click to cancel")
	queue_redraw()


func _target_ffa(m: Vector2) -> void:
	var from := _selected_slot
	for foe in duel.foes_of("player"):
		var slot := _slot_at(foe, m)
		var leader: CardView = leaders.get(foe)
		if leader and leader.glow > 0.0 and leader.hit(m):
			slot = DuelState.LEADER
		if _valid.has("%s:%d" % [foe, slot]) or slot == DuelState.LEADER:
			_cancel_interaction()
			_act("player", {"kind": "attack", "from": from, "target": slot, "foe": foe})
			return
	_cancel_and_refresh()


## A player is out (their place): their cards leave and their board goes dark.
func _ev_eliminated(ev: Dictionary) -> void:
	var side: String = ev.side
	_out[side] = int(ev.place)
	Sfx.play("ko", 0.7)
	Sfx.play("boom", 0.8, -4.0)
	shake(16)
	for slot in field.get(side, {}).keys():
		var v: CardView = field[side][slot]
		if is_instance_valid(v):
			var t := v.create_tween()
			t.tween_property(v, "modulate:a", 0.0, 0.5)
			t.tween_callback(v.queue_free)
	field[side] = {}
	for v in hand.get(side, []):
		if is_instance_valid(v):
			v.queue_free()
	hand[side] = []
	if leaders.has(side):
		leaders[side].queue_free()
		leaders.erase(side)
	if _panels.has(side):
		_panels[side].root.modulate = Color(0.55, 0.55, 0.6, 0.85)
	var at := _board_rect(side).get_center()
	_float_text(at, "%s OUT · %s" % ["YOU'RE" if side == "player" else str(_names.get(side, "")).to_upper(), _place_text(int(ev.place))], RED, 48)
	_log("%s %s out (%s)" % [_who(side), "are" if side == "player" else "is", _place_text(int(ev.place))], side)
	queue_redraw()
	_update_next_btn()
	await _wait(0.9)


## You're out (ffa:out): your place and rewards, and keep watching or leave.
func _show_out_panel(data: Dictionary) -> void:
	if _ui.has("out_panel") and is_instance_valid(_ui.out_panel):
		return
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.96), RED, 3, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var title := _label(48, RED, true)
	title.text = "YOU FINISHED %s" % _place_text(int(data.get("place", 0)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var r: Dictionary = data.get("rewards", {}) if data.get("rewards") is Dictionary else {}
	if not r.is_empty():
		var gain := _label(22, GOLD, true)
		gain.text = "+%d XP    ·    +%d KARAT" % [int(r.get("xpEarned", 0)), int(r.get("karatEarned", 0))]
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(gain)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	row.add_child(UI.button("KEEP WATCHING", func():
		if is_instance_valid(box):
			box.queue_free(), Vector2(240, 56)))
	row.add_child(UI.button("LEAVE", func():
		Net.send("ffa:quit")
		Game.match_result = {"result": "loss", "online": true, "mode": "ffa", "turns": duel.turn,
			"player_morale": 0, "opponent_morale": "—", "cards_played": _cards_played, "mvp": {}, "reason": "morale"}
		_ffa_result_into(Game.match_result, data)
		Game.go("post_match"), Vector2(200, 56), RED))
	overlay.add_child(box)
	box.z_index = 50   # (over the words that float up mid-board while the others play on)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, DIVIDER_Y - sz.y / 2)
	_ui.out_panel = box


## FFA results for the post-match screen: place, everyone's places and who they were, rewards.
func _ffa_result_into(r: Dictionary, data: Dictionary) -> void:
	r.ffa = true
	r.mode = "ffa"
	r.place = int(data.get("place", 0))
	r.places = data.get("places", {})
	r.players = data.get("players", {})
	r.result = "win" if r.place == 1 else "loss"
	if data.get("rewards") is Dictionary:
		r.rewards = data.rewards
	if data.get("achievements") is Array:
		r.achievements = data.achievements
	if data.get("mastery") is Dictionary:
		r.mastery = data.mastery
