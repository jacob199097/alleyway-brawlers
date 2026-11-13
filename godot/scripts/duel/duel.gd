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
## Esc = menu, F11 = fullscreen. A controller works it like a mouse (scripts/pad.gd, pad_targets).

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
## Free-for-all: the crossroads (arena_ffa.jpg) fills the screen with its manhole at FFA_MID, and the
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
const GOLD := UI.GOLD
const PROMPT_EDGE := Color(0.62, 0.74, 1.0, 0.6)   # the edge of a prompt, a menu or the log: cool steel, lit
const GREEN := Color("3ddc84")
const TEAL := Color("3ee6d0")   # a character with an Activate ability ready
const SWAP := Color("ff9f43")   # one of your characters a card can be deployed over
const PICKED := Color("b388ff")   # a character already chosen as a Heavy's sacrifice
const INK := Color(0.03, 0.03, 0.08, 0.92)
const AttackArrow := preload("res://scripts/duel/attack_arrow.gd")
const Tutorial := preload("res://scripts/duel/tutorial.gd")
const Keywords := preload("res://scripts/keywords.gd")
const ArenaRoulette := preload("res://scripts/ui/arena_roulette.gd")
const Plate := preload("res://scripts/ui/plate.gd")
const Banner := preload("res://scripts/ui/banner.gd")
const FxBrackets := preload("res://scripts/duel/fx_brackets.gd")
const ONLINE_TURN_SECS := 90.0   # matches TURN_SECS in backend/socket/onlineMatch.js
## Emotes in online matches against players (keys match EMOTES in backend/socket/onlineMatch.js)
const EMOTES := [["hello", "Hey!"], ["nice", "Nice move!"], ["wp", "Well played"], ["thinking", "Hmm…"],
	["oops", "Oops!"], ["hurry", "Your move…"], ["gotcha", "Gotcha!"], ["gg", "GG"]]
const EMOTE_GAP_MS := 2600
## Turf Defense: quick messages to your partner (keys match EMOTES in backend/socket/coopMatch.js)
const COOP_EMOTES := [["boss", "Hit the boss!"], ["help", "Help me!"], ["nice", "Nice!"], ["tank", "I'll hold them"],
	["wait", "Hold on…"], ["thanks", "Thanks!"], ["go", "Go for it!"], ["gg", "GG"]]
const TurfShow := preload("res://scripts/duel/turf_show.gd")
const COOP_BOSS_K := 0.74   # the boss's board is bigger than yours and your ally's
const REPLAY_GAP := 0.35   # seconds between moves when watching a replay
## A clan's own animations. attack "laser": dark purple laser beams instead of charging in;
## summon "warp": arrives through a swirling portal; ko "stardust": dissolves into stardust.
## attack "guns": rapid gunfire, with muzzle flashes, tracers and bullet hits (Militia).
## attack "cards": a volley of spinning playing cards thrown at the target, a gold ace to finish (Wildcard);
## summon "deal": dealt in from the dealer's side of the table, spinning, landing in a burst of chips.
## attack "skulls": glowing purple skulls hurled at the target, a great skull to finish (Underworld);
## summon "grave": a tombstone bursts up out of the cracked ground and the character climbs out of the grave.
## attack "molotov": a lit Molotov lobbed across the board, smashing into burning fuel (Arsonists);
## summon "firewall": a wall of fire sweeps across the slot and the character walks out through it;
## ko "ash": the card catches fire and burns away from the top down, cinders and ash drifting off it.
## ko "blast": blown up, the card thrown spinning and blackened, a smoking scorch mark left (Militia);
## ko "fold": the card bursts into a hand of playing cards that fan out and scatter (Wildcard);
## ko "rift": the ground cracks open under the card and it's pulled down into it, souls escaping (Underworld).
## attack "cannon": a ship's cannon rolls up in front of the card, its fuse fizzes and it fires a cannonball
## across that smashes into the target in splinters and smoke (Pirates); summon "wave": a pool of sea water
## opens, a wave bursts up and the character rises out of it, streaming water; ko "sink": a whirlpool opens
## under the card and it spins down into it, bubbles rising, the water closing over it.
## Neutral cards (any deck) fight like the street: summon "spotlight" (a streetlamp flickers on and the card
## drops into its light), attack "brawl" (a charging haymaker, a comic-book POW! on contact), ko "knockout"
## (K.O.!, sent spinning, cartoon stars circling where it stood).
const CLAN_STYLE := {"nebula": {"attack": "laser", "summon": "warp", "ko": "stardust"}, "militia": {"attack": "guns", "summon": "airdrop", "ko": "blast"},
	"wildcard": {"attack": "cards", "summon": "deal", "ko": "fold"}, "underworld": {"attack": "skulls", "summon": "grave", "ko": "rift"},
	"arsonists": {"attack": "molotov", "summon": "firewall", "ko": "ash"}, "pirates": {"attack": "cannon", "summon": "wave", "ko": "sink"}, "neutral": {"attack": "brawl", "summon": "spotlight", "ko": "knockout"}}
const FX_RIFT := preload("res://shaders/fx_rift.gdshader")
const FX_FIRE := preload("res://shaders/fx_fire.gdshader")
const FX_COMET := preload("res://shaders/fx_comet.gdshader")
const FX_RUNES := preload("res://shaders/fx_runes.gdshader")
const FX_BEAM := preload("res://shaders/fx_beam.gdshader")
const FX_SMOKE := preload("res://shaders/fx_smoke.gdshader")
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
var _luck_wins := {}                           # side -> coin flips / die rolls won (a luck leader's Awaken)
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
var _vets := {}   # side -> that player's veteran cards {card id: tier} (the match's profiles): their marks
var _vet_xp := {}   # side -> that player's card XP {card id: xp} (the profiles' vet_xp; none from an older server)
var _replay_next := 0     # next update to play
var _replay_wait := 0.0
var _emote_ready_at := 0
var _emotes_muted := false
var _awaiting := false    # sent a move, waiting for the server's answer
var _away_warned := false # told the player a move was played for them (server move clock)
var _base_speed := 1.0    # Engine.time_scale outside hit-stops: Settings → Animation Speed, or replay speed
var _catch_up := 1.0      # faster while a backlog of events waits (a free-for-all's CPUs move quickly)
var _replay_seek := -1    # replay: jump to this update once the current one has finished animating
var _log_rows: VBoxContainer   # the battle log (L): a row a line, newest last
var _log_scroll: ScrollContainer
var _log_follow := true        # the log keeps to its newest line (until you scroll up to read)
var _log_lines := 0
var _recent: Array = []        # the last few log lines ([colour, text]): the card panel shows them when idle
var _last_played := {}        # {card, side}: the card panel shows it when nothing is hovered
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
var _strike_tint := Color(0, 0, 0, 0)   # the colour of the damage flying from _strike_at (clear: the side's own)
var _end_reason := "morale"         # from game_over: "morale" or "deck_out"
var _end_snap: Texture2D = null      # the board as the match ended, before anything covers it (post-match background)

var _font: Font
var _dot: Texture2D
var _ring_tex: Texture2D
var _column_tex: Texture2D
var _add_mat: CanvasItemMaterial
var _slot_box: Plate
var _slot_box_back: Plate
var _pile_box: Plate
var _ui := {}
var _panels := {}
var _right := 0.0          # how far the right-hand HUD column moved out on a wide phone (widescreen.gd)
var _ffa := false          # a free-for-all (backend/socket/ffaMatch.js): 3-4 players, every board on screen
var _sides: Array = ["player", "opponent"]   # every side ("player" first)
var _foes: Array = ["opponent"]              # everyone else (FFA: foe1, foe2, foe3 in turn order)
var _boards := {}          # FFA: side -> {c: centre, s: card scale, p: spacing scale, rows, plate}
var _paint := {}           # the slots painted on the mat (front, back, pile), when there's a mat
var _neon := {}            # the mat whose neon stutters now and then: {mat: ShaderMaterial, zones: [{zone, at}]}
var _tense := false        # the music has turned tense (someone is close to losing)
var _out := {}             # FFA: side -> finishing place, once they're out
var _direct_btns: Array = []
var _coop := false         # Turf Defense (backend/socket/coopMatch.js): you and your ally against a boss
var _boss := {}            # the boss as the server sent it (shared/turf.js bossInfo)
var _turf: TurfShow = null # its cutscenes, plate and intel (scripts/duel/turf_show.gd)


func _ready() -> void:
	randomize()
	if "--autoplay" in OS.get_cmdline_user_args():
		ai_sides = ["player", "opponent"]
	_font = UI.font()
	_make_resources()
	ui.theme = _make_theme()
	# The floor: the match's 1v1 arena (data/arenas.json; the server's pick online, the roulette's
	# offline; the slots are painted on it in _draw), else the Back Alley
	var bg := "res://assets/arena_1v1.jpg"
	var arena := {}
	var ffa_start: bool = Game.duel_setup.get("start") is Dictionary and str(Game.duel_setup.start.get("mode", "")) == "ffa"
	# (a free-for-all: its match's arena, any 1v1 one, or the Crossroads (below); an older server sends none)
	var crossroads: bool = ffa_start and str(Game.duel_setup.start.get("arena", "crossroads")) == "crossroads"
	if not _paint.is_empty() and not crossroads:
		var start_arena = Game.duel_setup.get("start", {}).get("arena") if Game.duel_setup.get("start") is Dictionary else null
		var roof = Game.duel_setup.get("rooftop")   # (tests can pick: true / false)
		var arena_id := str(start_arena) if start_arena is String else str(Game.duel_setup.get("arena", ""))
		if roof is bool:
			arena_id = "rooftop" if roof else "alley"
		elif arena_id == "" and str(Game.duel_setup.get("mode", "")) != "tutorial":
			arena_id = ArenaRoulette.random_id()
		arena = ArenaRoulette.find(arena_id)
		if not arena.is_empty():
			bg = "res://assets/" + str(arena.image)
			_ambience = str(arena.get("ambience", "city_rain"))   # (rain only where it rains)
	if ResourceLoader.exists(bg):
		$BackLayer/Background.texture = UI.tex(bg)
		if not _paint.is_empty():
			$BackLayer/Background.modulate = Color(0.85, 0.85, 0.92)
			$BackLayer/Background.material = _alive($BackLayer/Background.texture.get_size())
			_neon = {"mat": $BackLayer/Background.material, "zones": _find_neon($BackLayer/Background.texture, _cover_point.bind($BackLayer/Background.texture.get_size()))}
			if not arena.is_empty():   # the arena's own slots and life
				if arena.get("stutter", true) == false:   # (no neon signs to stutter)
					_neon = {}
				for k in arena.get("alive", {}):
					$BackLayer/Background.material.set_shader_parameter(k, float(arena.alive[k]))
				_style_board(arena.get("board", {}))
				_arena_fx(arena, $BackLayer/Background.texture)
	_build_detail()
	var me := Game.player
	var online_start: Dictionary = Game.duel_setup.get("start", {}) if Game.duel_setup.get("online", false) else {}
	if str(online_start.get("mode", "")) == "ffa":
		_setup_ffa_sides(online_start)
		if crossroads and ResourceLoader.exists("res://assets/arena_ffa.jpg"):   # the crossroads, covering the screen
			var mat := TextureRect.new()
			mat.texture = UI.tex("arena_ffa.jpg")
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
	elif str(online_start.get("mode", "")) == "coop":
		_setup_coop_sides(online_start)
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
	# Veteran cards (backend/economy/veterans.js): both players see each other's marks
	var profs = online_start.get("players") if online_start.get("players") is Dictionary else \
		({} if online_start.is_empty() else {"player": online_start.get("you", {}), "opponent": online_start.get("opponent", {})})
	for side in profs:
		var pv = profs[side].get("vets") if profs[side] is Dictionary else null
		if pv is Dictionary:
			_vets[side] = pv
		var px = profs[side].get("vet_xp") if profs[side] is Dictionary else null
		if px is Dictionary:
			_vet_xp[side] = px
	var watched: bool = online_start.get("spectate", false) or online_start.get("replay", false)
	if not watched:   # (watching or a replay: the watched player's plate, below)
		_build_panel("player", $HUD/UI/PlayerPanel, str(me.get("username", "YOU")).to_upper().left(14),
			str(me.get("avatar_url", "")),
			"LV %d  ·  %s" % [int(me.get("level", 1)), UI.shown_title(me).to_upper()], int(me.get("level", 1)))
	if online_start.is_empty():
		var tut: bool = Game.duel_setup.get("mode") == "tutorial"
		_build_panel("opponent", $HUD/UI/OppPanel, "RIVAL" if tut else "CPU", "cpu", "TUTORIAL OPPONENT" if tut else "CPU OPPONENT")
	elif _coop:
		_build_coop_plates(online_start.get("players", {}))
	elif _ffa:
		$HUD/UI/OppPanel.visible = false
		_build_foe_plates(online_start.get("players", {}))
	else:
		if watched:
			var you: Dictionary = online_start.get("you", {})
			_build_panel("player", $HUD/UI/PlayerPanel, str(you.get("username", "PLAYER")).to_upper().left(14),
				str(you.get("avatar_url")) if you.get("avatar_url") else "",
				"LV %d  ·  %s" % [int(you.get("level", 1)), "REPLAY" if online_start.get("replay", false) else "WATCHING"], int(you.get("level", 1)))
		var opp: Dictionary = online_start.get("opponent", {})
		var opp_title = opp.get("title")
		if opp.get("bot", false) or str(opp.get("avatar_url", "")) == "cpu":   # (a CPU: who it is, no level or "ONLINE")
			_build_panel("opponent", $HUD/UI/OppPanel, str(opp.get("username", "CPU")).to_upper().left(18),
				str(opp.get("avatar_url")) if opp.get("avatar_url") else "cpu", str(opp.get("subtitle", "CPU OPPONENT")).to_upper(), 0, int(opp.get("stars", 0)))
		else:
			_build_panel("opponent", $HUD/UI/OppPanel, str(opp.get("username", "RIVAL")).to_upper().left(12),
				str(opp.get("avatar_url")) if opp.get("avatar_url") else "",
				"LV %d  ·  %s" % [int(opp.get("level", 1)), str(opp_title).to_upper() if opp_title is String and opp_title != "" else "ONLINE"], int(opp.get("level", 1)))
	# Each player's mastery with their deck's clan, under their level and title (the server sends it)
	if not online_start.is_empty() and not _coop and not _ffa:
		_clan_line($HUD/UI/PlayerPanel, online_start.get("you", {}))
		_clan_line($HUD/UI/OppPanel, online_start.get("opponent", {}))
	_build_phase_bar()
	_build_turn_box()
	_build_status()
	_build_log()
	# The HUD is glass: the arena shows through it
	for p in [$HUD/UI/Detail, $HUD/UI/OppPanel, $HUD/UI/PlayerPanel, $HUD/UI/PhaseBar, $HUD/UI/TurnBox]:
		UI.glass(p, Color(0.03, 0.03, 0.08, 0.66), 8.0)
	# A wide phone: the right-hand column (rival, phases, whose move, turn) moves out to the edge of
	# the screen, as the card panel does on the left (_build_detail)
	_right = minf(Game.wide.margin.x, 240.0)
	for c in $HUD/UI.get_children():
		if c is Control and c.position.x >= 1600:
			c.position.x += _right
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
	if _coop:
		_names.boss = str(_boss.get("short", _boss.get("name", "The boss")))
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
	elif _coop or (not str(start.get("mode", "")).begins_with("cpu") and not _ffa):
		_build_emote_button()
	_clock_left = float(start.get("clock", ONLINE_TURN_SECS))
	if not start.get("resync", false) and not _spectating:
		Game.alert()
	if start.get("challenge") is Dictionary and not start.get("resync", false):   # this week's twist
		_tip_panel("WEEKLY CHALLENGE  ·  %s" % str(start.challenge.get("name", "")).to_upper(), str(start.challenge.get("text", "")), RED)
	Net.opened.connect(_on_net_opened)
	Net.closed.connect(_on_net_closed)
	if int(start.get("opponentGone", 0)) > 0:   # (back in a match whose opponent has dropped)
		_countdown_box("WAITING FOR OPPONENT TO RECONNECT", "If they don't come back in time, you win.", int(start.opponentGone), GOLD)
	if _coop and not start.get("resync", false):
		_coop_intro(start)
		return
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
	if _coop and not mine and (side if side != "" else duel.active) == "boss":
		return "%s STRIKES" % str(_names.get("boss", "THE BOSS")).to_upper()
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
	var b := UI.button("LOG", _toggle_log, Vector2(100, 48))
	b.position = Vector2(440, 1004)   # left of the hand, even when it's full
	if Game.mobile():   # (a thumb's size, grown to the left: the hand stays clear)
		b.custom_minimum_size = Vector2(136, 64)
		b.size = b.custom_minimum_size
		b.position = Vector2(404, 992)
	b.tooltip_text = "Battle log (L)"
	ui.add_child(b)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.98), PROMPT_EDGE, 2, 10))
	p.position = Vector2(20, 250)
	p.size = Vector2(560, 640)
	p.visible = false
	p.z_index = 40
	var col := VBoxContainer.new()
	p.add_child(col)
	var head := _label(26, GOLD, true)
	head.text = "BATTLE LOG"
	col.add_child(head)
	_log_scroll = ScrollContainer.new()
	_log_scroll.custom_minimum_size = Vector2(530, 580)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_rows = VBoxContainer.new()
	_log_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows.add_theme_constant_override("separation", 6)
	_log_scroll.add_child(_log_rows)
	col.add_child(_log_scroll)
	# It keeps to the newest line, unless you've scrolled up to read
	var bar := _log_scroll.get_v_scroll_bar()
	bar.value_changed.connect(func(v: float): _log_follow = v >= bar.max_value - bar.page - 8.0)
	bar.changed.connect(func():
		if _log_follow:
			bar.set_value_no_signal(bar.max_value))
	ui.add_child(p)
	_ui.log = p


func _toggle_log() -> void:
	_ui.log.visible = not _ui.log.visible
	# (the log covers the card panel; hidden, its frosted glass can't show through the log)
	$HUD/UI/Detail.visible = not _ui.log.visible
	if _ui.log.visible:   # (opens on the newest line)
		_log_follow = true
		var bar := _log_scroll.get_v_scroll_bar()
		bar.set_value_no_signal.call_deferred(bar.max_value)
	Sfx.play("click")


const LOG_MARK := 44.0   # a log row's picture, in pixels
const LOG_ICON_COLORS := {"attack": Color("ffd86b"), "hit": Color("ff5a5a"), "plus": Color("3ddc84"), "spark": Color("f4d35e"),
	"up": Color("f4d35e"), "crown": Color("f4d35e"), "ko": Color("ff5a5a"), "downed": Color("ff8a5a"),
	"card": Color("9aa3c7"), "back": Color("9aa3c7")}


## A line in the battle log, coloured by whose it is ("player", "opponent" or ""). With a card, its picture
## sits beside the line (edged in its side's colour); with a mark (a status, or one of StatusFx's log marks),
## that sits on the picture's corner, or alone when there's no card to show.
func _log(text: String, side: String, card = null, mark := "") -> void:
	if _log_rows == null:
		return
	var color := "#8fd3ff" if side == "player" else "#7af0de" if _coop and side == "ally" else "#ff8a94" if side != "" else "#f4d35e"
	if text.begins_with("──"):
		_log_rows.add_child(_log_heading(text.trim_prefix("──").trim_suffix("──").strip_edges()))
	else:
		_log_rows.add_child(_log_row(text, Color(color), card, mark))
	_log_lines += 1
	if not text.begins_with("──"):   # (a turn heading isn't news)
		_recent.append([color, text])
		if _recent.size() > 3:
			_recent.pop_front()
	if _detail_key.begins_with("idle:"):   # (the idle panel keeps up)
		_show_detail({})
	if _log_lines > 400:
		var old := _log_rows.get_child(0)
		_log_rows.remove_child(old)
		old.queue_free()
		_log_lines -= 1


## A turn's heading in the log: its words between two rules.
func _log_heading(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 34
	for i in 3:
		if i == 1:
			var l := _label(UI.text_size(17), GOLD, true)
			l.text = text
			row.add_child(l)
			continue
		var rule := ColorRect.new()
		rule.color = Color(GOLD, 0.4)
		rule.custom_minimum_size = Vector2(0, 2)
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rule)
	return row


func _log_row(text: String, color: Color, card, mark: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tex: Texture2D = null
	if card is Dictionary and card.has("name") and not (card.get("face_down", false) and not card.has("attack")):
		tex = CardDB.art_for(card)
	var sub := text.begins_with("   ")   # (a detail of the line above: the numbers of a clash)
	var m := Control.new()
	m.custom_minimum_size = Vector2(LOG_MARK, 24.0 if sub or (tex == null and mark == "") else LOG_MARK)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mark_col: Color = CardView.status_color(mark) if CardView.STATUS_STYLE.has(mark) else LOG_ICON_COLORS.get(mark, Color("9aa3c7"))
	m.draw.connect(func():
		var mid := m.size / 2.0
		if tex:
			var s := tex.get_size()
			m.draw_texture_rect_region(tex, Rect2(2, 2, LOG_MARK - 4, LOG_MARK - 4), Rect2(s.x * 0.18, s.y * 0.122, s.x * 0.64, s.x * 0.64))
			m.draw_rect(Rect2(1, 1, LOG_MARK - 2, LOG_MARK - 2), Color(color, 0.9), false, 2.0)
			if mark != "":
				CardView.StatusFx.badge(m, mark, Vector2(LOG_MARK - 8, LOG_MARK - 8), 10.0, mark_col)
		elif mark != "":
			CardView.StatusFx.badge(m, mark, mid, 14.0, mark_col)
		elif not sub:   # (nothing to picture: a small diamond in the line's colour)
			m.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 0), mid + Vector2(0, 5), mid + Vector2(-5, 0)]), Color(color, 0.8)))
	row.add_child(m)
	var l := _label(UI.text_size(18), Color(color, 0.75) if sub else color)
	l.text = text.strip_edges()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


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
			_log("%s redrew %d card(s)" % [_who(side), int(ev.get("count", 0))], side, null, "back")
		"summon":
			if ev.card.get("face_down", false):
				_log("%s set a card face down" % _who(side), side, null, "card")
			else:
				_log("%s deployed %s" % [_who(side), _cname(ev.card)], side, ev.card)
		"set":
			_log("%s set a card face down" % _who(side), side, null, "card")
		"shuffle":
			_log("%s deck was shuffled" % _whose(side), side, null, "card")
		"hustle", "lasting":
			_log("%s %s %s" % [_who(side), "activated" if ev.get("set", false) else "played", _cname(ev.card)], side, ev.card, "spark")
		"equip":
			_log("%s equipped %s" % [_who(side), _cname(ev.card)], side, ev.card, "equipped")
		"tribute":
			_log("%s %s %s for %s" % [_who(side), "replaced" if ev.get("replace", false) else "sacrificed", _cname(ev.card), _cname(ev.get("for"))], side, ev.card, "ko")
		"attack":
			var target := "directly"
			if int(ev.target) == DuelState.LEADER:
				target = "the dormant leader"
			elif int(ev.target) >= 0:
				var tv: CardView = field.get(str(ev.get("foe", DuelState.other(side))), {}).get(int(ev.target))
				target = _cname(tv.card if tv and tv.face_up else {})
			_log("%s attacked %s" % [_cname(ev.card), target], side, ev.card, "attack")
		"clash":
			if int(ev.target) >= 0:
				_log("   %d vs %d" % [int(ev.att), int(ev.def)], side)
		"flip":
			_log("%s was revealed" % _cname(ev.card), side, ev.card)
		"ambush":
			_log("%s sprang %s!" % [_who(side), _cname(ev.card)], side, ev.card, "spark")
		"blocked":
			_log("The attack was blocked", side, null, "shield")
		"downed":
			_log("%s went Down" % _cname(ev.card), side, ev.card, "downed")
		"ko":
			_log("%s was %s" % [_cname(ev.card), "removed from the game" if ev.get("exiled", false) else "KO'd"], side, ev.card, "ko")
		"topdeck":
			_log("%s went back on top of the deck" % _cname(ev.card), side, ev.card, "back")
		"cleanse":
			_log("%s was cleansed" % _cname(ev.card), side, ev.card, "plus")
		"rewind":
			_log("%s was rewound to its printed stats" % _cname(ev.card), side, ev.card, "back")
		"jam":
			_log("%s Ambushes are JAMMED" % _whose(side), side, null, "silence")
		"barricade":
			if int(ev.get("held", 0)) > 0:
				_log("%s BARRICADE held off %d Morale damage" % [_whose(side), int(ev.held)], side, null, "shield")
			elif int(ev.amount) > 0:
				_log("%s BARRICADE: %d" % [_whose(side), int(ev.amount)], side, null, "shield")
		"damage":
			_log("%s lost %d Morale (%d left)" % [_who(side), int(ev.amount), int(ev.morale)], side, null, "hit")
		"heal":
			_log("%s gained %d Morale (%d)" % [_who(side), int(ev.amount), int(ev.morale)], side, null, "plus")
		"status":
			_log("%s: %s" % [_cname(ev.card), STATUS_WORDS.get(str(ev.kind), str(ev.kind).to_upper())], side, ev.get("card"), str(ev.kind))
		"status_tick":
			_log("%s: %s %d" % [_cname(ev.card), STATUS_WORDS.get(str(ev.kind), str(ev.kind).to_upper()), int(ev.get("amount", 0))], side, ev.get("card"), str(ev.kind))
		"bounce":
			_log("%s went back to the hand" % _cname(ev.card), side, ev.card, "back")
		"mill":
			_log("%s was sent from the deck to the Gutter" % _cname(ev.card), side, ev.card, "card")
		"recover":
			_log("%s got %s back from the Gutter" % [_who(side), _cname(ev.card)], side, ev.card, "plus")
		"plunder":
			_log("%s PLUNDERED %s from %s %s" % [_who(side), _cname(ev.card), _whose(str(ev.get("from_side", ""))).to_lower(), str(ev.get("from", "hand"))], side, ev.card, "charm")
		"promote":
			_log("%s promoted to %s" % [_cname(ev.get("from")), _cname(ev.card)], side, ev.card, "up")
		"effect":   # ("Megan Downs Kade", not "Megan: Megan Downs Kade")
			var said := str(ev.get("text", ""))
			var who := _cname(ev.card)
			var body := said.trim_prefix(who + ": ").trim_prefix(who + " ") if said.begins_with(who) else ""
			_log(said if body != "" else "%s: %s" % [who, said], side, ev.get("card"), "spark")
		"stand":
			_log("%s stood back up" % _cname(ev.card), side, ev.card, "up")
		"discard":
			_log("%s discarded %s" % [_who(side), _cname(ev.card)], side, ev.card, "ko")
		"charm":
			if ev.get("back", false):
				_log("%s goes back to its owner" % _cname(ev.card), str(ev.to_side), ev.card, "back")
			elif ev.get("plunder", false):
				_log("%s is PLUNDERED" % _cname(ev.card), str(ev.to_side), ev.card, "charm")
			else:
				_log("%s is CHARMED" % _cname(ev.card), str(ev.to_side), ev.card, "charm")
		"position":
			_log("%s switched to %s" % [_cname(ev.card), "DEF" if ev.card.get("position") == "def" else "ATK"], side, ev.card)
		"awaken":
			_log("%s awakened!" % _cname(ev.card), side, ev.card, "crown")
		"leader_hit":
			_log("%s leader took %d" % [_whose(side), int(ev.amount)], side, ev.get("card"), "hit")
		"leader_heal":
			_log("%s leader regained %d Influence" % [_whose(side), int(ev.amount)], side, ev.get("card"), "plus")
		"leader_down":
			_log("%s leader %s fell" % [_whose(side), _cname(ev.card)], side, ev.card, "ko")
		"game_over":
			_log("%s won!" % ("You" if ev.winner == "player" else "Your opponent"), str(ev.winner), null, "crown")
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
	var buttons: Array[Button] = []
	for e in _emote_list():
		var key: String = e[0]
		buttons.append(UI.button(e[1], func(): _send_emote(key), Vector2(190, 50), BLUE))
	var who := "ALLY" if _coop else "RIVAL"
	buttons.append(UI.button(("Unmute " if _emotes_muted else "Mute ") + who.to_lower(), func():
		_emotes_muted = not _emotes_muted
		_toggle_emote_menu(), Vector2(190, 50), RED))
	for b in buttons:   # (the plain, readable emote font, not the chunky headline one)
		b.add_theme_font_override("font", _emote_font())
		b.add_theme_font_size_override("font_size", 21)
		grid.add_child(b)
	ui.add_child(box)
	box.reset_size()
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(420, 1000 - sz.y - 8)
	_ui.emotes = box
	# It opens up from the button, the choices fading in one after another
	box.pivot_offset = Vector2(0, sz.y)
	box.scale = Vector2(0.9, 0.7)
	box.modulate.a = 0.0
	var t := box.create_tween().set_parallel()
	t.tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(box, "modulate:a", 1.0, 0.12)
	for i in buttons.size():
		buttons[i].modulate.a = 0.0
		t.tween_property(buttons[i], "modulate:a", 1.0, 0.14).set_delay(0.05 + 0.025 * i)


func _send_emote(key: String) -> void:
	if _ui.has("emotes") and is_instance_valid(_ui.emotes):
		_ui.emotes.queue_free()
		_ui.erase("emotes")
	if Time.get_ticks_msec() < _emote_ready_at:
		return
	_emote_ready_at = Time.get_ticks_msec() + EMOTE_GAP_MS
	Net.send("coop:emote" if _coop else "mp:emote", {"matchId": _match_id, "key": key})
	_show_emote("player", key)


func _emote_list() -> Array:
	return COOP_EMOTES if _coop else EMOTES


## A speech bubble by the player's or the opponent's panel (Turf Defense: your ally's plate).
func _show_emote(side: String, key: String) -> void:
	if side != "player" and _emotes_muted:
		return
	var text := ""
	for e in _emote_list():
		if e[0] == key:
			text = e[1]
	if text == "":
		return
	var old: String = "emote_" + side
	if _ui.has(old) and is_instance_valid(_ui[old]):
		_ui[old].queue_free()
	var accent := BLUE if side == "player" else TEAL if side == "ally" else RED
	# A speech bubble: dark, plain text on white (no outline), a soft shadow, and a tail pointing at the
	# speaker's plate (down to yours or your ally's, up to the rival's)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _box(Color(0.98, 0.98, 1.0), accent, 3, 18)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 5)
	bubble.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _emote_font())
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color("17172c"))
	bubble.add_child(l)
	root.add_child(bubble)
	ui.add_child(root)
	bubble.reset_size()   # (measured once it's in the tree, with its font)
	var down := side != "opponent"
	var sz := bubble.get_combined_minimum_size()
	var tx := 40.0 if side == "player" else sz.x - 40.0
	var tip := Vector2(tx - 6.0 if side == "player" else tx + 6.0, sz.y + 20.0) if down else Vector2(tx + 6.0, -20.0)
	var edge := sz.y - 2.0 if down else 2.0
	var rim := Polygon2D.new()   # (the tail's outline, under the bubble; its white fill goes over the border)
	rim.color = accent
	rim.polygon = PackedVector2Array([Vector2(tx - 16, edge), Vector2(tx + 16, edge), tip + Vector2(0, 4 if down else -4)])
	root.add_child(rim)
	root.move_child(rim, 0)
	var fill := Polygon2D.new()
	fill.color = Color(0.98, 0.98, 1.0)
	fill.polygon = PackedVector2Array([Vector2(tx - 12, edge - (2 if down else -2)), Vector2(tx + 12, edge - (2 if down else -2)), tip])
	root.add_child(fill)
	root.size = sz
	root.position = Vector2(40, 740 - sz.y) if side == "player" else Vector2(1896 + _right - sz.x, 262)
	if side == "ally" and _panels.has("ally"):   # (over your ally's plate)
		var plate: Control = _panels.ally.root
		root.position = Vector2(plate.position.x + plate.size.x - sz.x, plate.position.y - sz.y - 24)
	_ui[old] = root
	Sfx.play("click", 1.25 if side == "player" else 0.9)
	# It pops out of the speaker with a little wobble, holds, then drifts away as it fades
	root.pivot_offset = tip
	root.scale = Vector2.ONE * 0.2
	root.modulate.a = 0.0
	var wob := 3.0 if side == "player" else -3.0
	var t := root.create_tween()
	t.tween_property(root, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(root, "modulate:a", 1.0, 0.14)
	t.parallel().tween_property(root, "rotation_degrees", wob, 0.17).set_trans(Tween.TRANS_SINE)
	t.tween_property(root, "rotation_degrees", -wob * 0.5, 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_property(root, "rotation_degrees", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	t.tween_interval(2.4)
	t.tween_property(root, "position:y", root.position.y + (-16.0 if down else 16.0), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(root, "modulate:a", 0.0, 0.45)
	t.tween_callback(root.queue_free)


## The emotes' font: a clean, semi-bold sans-serif that reads at a glance (the headline font is too heavy).
static func _emote_font() -> Font:
	return UI.font_of("strong")


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
		p.bar.size.x = p.bar.get_parent().size.x * clampf(float(s.morale) / _max_morale(side), 0.0, 1.0)
	_ui.turn_num.text = "TURN %d" % duel.turn
	CardView.turn_now = int(duel.turn)
	_ui.turn_who.text = _turn_text(duel.active == "player")
	_set_phase_ui(duel.phase, str(duel.active))
	_refresh_guards()


func _on_net_event(name: String, data) -> void:
	if not data is Dictionary or str(data.get("matchId", _match_id)) != _match_id:
		return
	match name:
		"mp:update", "ffa:update", "coop:update":
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
		"ffa:over", "coop:over":
			_over = data
		"ffa:out":
			_over = data
			await _when_idle()
			_show_out_panel(data)
		"mp:emote":
			_show_emote("opponent", str(data.get("key", "")))
		"coop:emote":
			_show_emote("ally", str(data.get("key", "")))
		"mp:spectators":
			if not _ui.has("watchers"):
				_ui.watchers = _label(20, Color(1, 1, 1, 0.75), true)
				_ui.watchers.position = Vector2(1400, 1040)
				ui.add_child(_ui.watchers)
			var n := int(data.get("count", 0))
			_ui.watchers.text = "" if n == 0 else "👁 %d WATCHING" % n
		"mp:opponent":
			var who := str(data.get("name", ""))   # (Turf Defense and free-for-all name them)
			if data.get("status") == "disconnected":
				var title := "WAITING FOR %s TO RECONNECT" % (who.to_upper() if who != "" else "OPPONENT")
				var sub := "If they don't come back in time, they're out of the fight." if _ffa else "If they don't come back in time, you win."
				_countdown_box(title, sub, int(data.get("graceSecs", 60)), GOLD)
			else:
				_close_countdown()
				UI.toast(overlay, ("%s is back." % who) if who != "" else "Your opponent is back.", BLUE)


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
	_close_countdown()
	Net.send("coop:resync" if _coop else "ffa:resync" if _ffa else "mp:resync")


func _on_net_closed() -> void:
	if _mode != "over" and not _spectating:   # (the server keeps the seat for 60 seconds: backend/socket/onlineMatch.js)
		_countdown_box("CONNECTION LOST — RECONNECTING…", "Your seat is kept for a minute. If the game closed, open it again to rejoin.", 60, RED)
	elif _mode != "over":
		_show_net_banner("CONNECTION LOST — RECONNECTING…")


## A panel at the top of the board counting down: someone dropped and has secs seconds to come back.
func _countdown_box(title: String, sub: String, secs: int, col: Color) -> void:
	_close_countdown()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.95), col, 3, 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 40
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := _label(26, col, true)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := _label(64, Color.WHITE, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var l := _label(18, Color(0.8, 0.8, 0.9))
	l.text = sub
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	overlay.add_child(p)
	_ui.countdown = p
	var ends := Time.get_ticks_msec() + secs * 1000
	var tick := func():
		var left := maxi(0, ceili((ends - Time.get_ticks_msec()) / 1000.0))
		n.text = "%d:%02d" % [left / 60, left % 60] if left > 0 else "TIME'S UP"
		n.modulate = Color(1, 0.45, 0.45) if left <= 10 else Color.WHITE
		p.reset_size()
		p.position = Vector2(1080 - p.size.x / 2, 200)
	tick.call()
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(tick)
	p.add_child(timer)
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.25)
	var pulse := t.create_tween().set_loops()
	pulse.tween_property(t, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(t, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _close_countdown() -> void:
	if _ui.has("countdown") and is_instance_valid(_ui.countdown):
		_ui.countdown.queue_free()
	_ui.erase("countdown")


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
	# (a phone wider than the frame: the camera centres the board on the screen, but the frame is
	# already moved to the middle, scripts/widescreen.gd, so it looks that much further over)
	var wide: Vector2 = Game.wide.margin / camera.zoom
	if _shake > 0.3:
		camera.offset = wide + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0))
	else:
		camera.offset = wide
	_update_post()
	_update_aim()
	_update_pile_backs(delta)
	if _tutorial:
		_tutorial.update()
	_update_peek()
	if _ui.has("detail_art"):
		if _detail_key.begins_with("idle::") and duel != null:   # (the match is here: show the player's own back)
			_show_detail({})
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
		_press.position = _press.position.lerp(Game.pad.pointer(self), minf(1.0, delta * 25.0))
	if not _replay.is_empty():
		_step_replay(delta)
	elif _online:
		while not Net.inbox.is_empty():
			var msg: Array = Net.inbox.pop_front()
			_on_net_event(msg[0], msg[1])
		# Whoever has to act has the server's clock (data.clock) before it plays a safe move for them
		if duel.winner == "" and _mode != "over":
			_clock_left = maxf(0.0, _clock_left - delta / maxf(Engine.time_scale, 0.01))   # real seconds
	_update_status()


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
			var text := "DOWN" if _coop else "OUT · %s" % _place_text(int(_out[side]))
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
## An arena's own slots (data/arenas.json "board"): its spray paint in a colour ("paint", "tint"),
## glowing outlines ("neon") or darker spots rimmed in gold on the felt ("felt"), frosted ice ("frost"),
## a lit hologram panel ("holo"), an engraved brass plate ("brass"), a sharp-edged mirror shard ("shard") or a
## pale ring on water ("water"), each in "color".
func _style_board(board: Dictionary) -> void:
	var style := str(board.get("style", "paint"))
	if style == "paint":
		var tint := Color(str(board.get("tint", "#ffffff")))
		for kind in _paint:
			if _paint[kind] is StyleBoxTexture:
				_paint[kind].modulate_color = _paint[kind].modulate_color * Color(tint, 1.0)
		return
	var col := Color(str(board.get("color", "#ffffff")))
	for kind in ["front", "back", "pile"]:
		var a: float = {"front": 1.0, "back": 0.7, "pile": 0.5}[kind]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		if style == "frost":   # frosted panes etched into the ice
			sb.bg_color = Color(col, 0.06 * a)
			sb.border_color = Color(col.lightened(0.5), 0.85 * a)
			sb.set_border_width_all(3)
			sb.shadow_color = Color(col, 0.22 * a)
			sb.shadow_size = 6
		elif style == "holo":   # a lit panel in the glass floor
			sb.bg_color = Color(col, 0.03 * a)
			sb.border_color = Color(col.lightened(0.25), 0.9 * a)
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(6)
			sb.shadow_color = Color(col, 0.14 * a)
			sb.shadow_size = 14
		elif style == "brass":   # an engraved plate set into the brass floor
			sb.bg_color = Color(col.darkened(0.72), 0.34 * a)
			sb.border_color = Color(col, 0.95 * a)
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(5)
			sb.shadow_color = Color(0, 0, 0, 0.45 * a)
			sb.shadow_size = 7
			sb.shadow_offset = Vector2(0, 3)
		elif style == "shard":   # a sliver of mirror floating in the void
			sb.bg_color = Color(col, 0.05 * a)
			sb.border_color = Color(col.lightened(0.45), 0.9 * a)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(0)
			sb.shadow_color = Color(col, 0.28 * a)
			sb.shadow_size = 16
		elif style == "water":   # a pale ring on the pond, like a lily pad's edge
			sb.bg_color = Color(1, 1, 1, 0.07 * a)
			sb.border_color = Color(col, 0.8 * a)
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(26)
			sb.shadow_color = Color(col, 0.2 * a)
			sb.shadow_size = 8
		elif style == "neon":
			sb.bg_color = Color(col, 0.03 * a)
			sb.border_color = Color(col.lightened(0.35), 0.95 * a)
			sb.set_border_width_all(4)
			sb.shadow_color = Color(col, 0.16 * a)   # (a soft halo: the stars still show through the slot)
			sb.shadow_size = 10
		else:   # felt
			sb.bg_color = Color(0, 0, 0, 0.17 * a)
			sb.border_color = Color(col, 0.92 * a)
			sb.set_border_width_all(5)
			sb.shadow_color = Color(0, 0, 0, 0.35 * a)
			sb.shadow_size = 8
		_paint[kind] = sb


## An arena coming alive (data/arenas.json "fx", positions in the picture's pixels): light pools that
## breathe (or flicker), drifting dust or embers, twinkling stars and shooting stars, camera flashes in
## the crowd, welding sparks, a turning roulette wheel, cigar smoke and glints on chips and glass.
## Flames, fog, water, weather, beams, creatures... are made by ArenaLife (scripts/duel/arena_life.gd).
func _arena_fx(arena: Dictionary, tex: Texture2D) -> void:
	var m: Vector2 = Game.wide.margin   # (a wide phone: the picture covers the whole screen round the frame, widescreen.gd)
	var life := ArenaLife.new().setup(tex, $BackLayer/Background.modulate, Game.arena_level(), Vector2(1920, 1080) + m * 2)
	life.position = -m
	$BackLayer.add_child(life)
	var ts := tex.get_size()
	var k := maxf((1920.0 + m.x * 2) / ts.x, (1080.0 + m.y * 2) / ts.y)
	var to_screen := func(p) -> Vector2: return _cover_point(Vector2(float(p[0]), float(p[1])), ts)
	var to_rect := func(r) -> Rect2:
		var a: Vector2 = to_screen.call([r[0], r[1]])
		return Rect2(a, Vector2(float(r[2]), float(r[3])) * k)
	for e in arena.get("fx", []):
		if not e is Dictionary:
			continue
		var col := Color(str(e.get("color", "#ffffff")))
		match str(e.get("kind", "")):
			"pool":
				_fx_pool(to_screen.call(e.at), float(e.get("r", 200)) * k, col, bool(e.get("flicker", false)))
			"dust", "embers":
				_fx_drift(to_rect.call(e.rect), col, str(e.kind) == "embers")
			"twinkle":
				_fx_twinkle(to_rect.call(e.rect), col)
			"shooting":
				_fx_shooting(to_rect.call(e.rect))
			"flashes":
				_fx_flashes(e.points.map(func(p): return to_screen.call(p)))
			"sparks":
				_fx_sparks(to_screen.call(e.at), float(e.get("every", 3.0)))
			"spin":
				_fx_spin(tex, Vector2(float(e.at[0]), float(e.at[1])), float(e.get("r", 100)), float(e.get("speed", 0.5)), to_screen.call(e.at), k)
			"smoke":
				var sm := _steam(to_screen.call(e.at))
				sm.modulate = Color(0.75, 0.72, 0.7, 0.55)
				sm.scale_amount_min *= 0.6
				sm.scale_amount_max *= 0.6
				$BackLayer.add_child(sm)
			"glints":
				_fx_glints(e.points.map(func(p): return to_screen.call(p)))
			var other:
				if ArenaLife.handles(str(other)):
					life.add(e)


static var _dot_tex: GradientTexture2D = null


## A soft round dot (white, fading to nothing), for light and particles.
static func _soft_dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.width = 64
		_dot_tex.height = 64
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)
		_dot_tex.gradient = g
	return _dot_tex


## A pool of light that breathes and drifts a little (or flickers like a failing floodlight).
func _fx_pool(at: Vector2, radius: float, col: Color, flicker: bool) -> void:
	var s := Sprite2D.new()
	s.texture = _soft_dot()
	s.position = at
	s.scale = Vector2.ONE * radius / 32.0
	s.material = _add_mat
	s.modulate = Color(col, 0.2)
	$BackLayer.add_child(s)
	var t := s.create_tween().set_loops()
	var dur := randf_range(2.2, 3.4)
	t.tween_property(s, "modulate:a", 0.32, dur).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(s, "position", at + Vector2(randf_range(-14, 14), randf_range(-10, 10)), dur).set_trans(Tween.TRANS_SINE)
	t.tween_property(s, "modulate:a", 0.18, dur).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(s, "position", at, dur).set_trans(Tween.TRANS_SINE)
	if flicker:
		_fx_flicker(s)


func _fx_flicker(s: Sprite2D) -> void:
	while is_instance_valid(s) and s.is_inside_tree():
		await get_tree().create_timer(randf_range(2.5, 7.0)).timeout
		if not is_instance_valid(s):
			return
		for i in randi_range(2, 4):   # a stutter: dark, on, dark...
			s.visible = false
			await get_tree().create_timer(randf_range(0.04, 0.1)).timeout
			if not is_instance_valid(s):
				return
			s.visible = true
			await get_tree().create_timer(randf_range(0.05, 0.14)).timeout
			if not is_instance_valid(s):
				return


## Motes drifting in the light: dust (slow, any way) or embers (rising, glowing).
func _fx_drift(area: Rect2, col: Color, embers: bool) -> void:
	var p := CPUParticles2D.new()
	p.texture = _soft_dot()
	p.position = area.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = area.size / 2
	p.amount = 18 if embers else 46
	p.lifetime = 2.6 if embers else 7.0
	p.preprocess = p.lifetime
	p.direction = Vector2(0, -1)
	p.spread = 35.0 if embers else 180.0
	p.gravity = Vector2(0, -26) if embers else Vector2.ZERO
	p.initial_velocity_min = 14.0 if embers else 3.0
	p.initial_velocity_max = 40.0 if embers else 12.0
	p.scale_amount_min = 0.05 if embers else 0.04
	p.scale_amount_max = 0.1 if embers else 0.08
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col, 0.0))
	ramp.add_point(0.25, Color(col, 0.9 if embers else 0.45))
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	p.material = _add_mat
	$BackLayer.add_child(p)


## Stars twinkling under a glass floor.
func _fx_twinkle(area: Rect2, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.texture = _soft_dot()
	p.position = area.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = area.size / 2
	p.amount = 70
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = col
	p.material = _add_mat
	$BackLayer.add_child(p)


## Now and then a shooting star streaks across.
func _fx_shooting(area: Rect2) -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(5.0, 11.0)).timeout
		if not is_inside_tree():
			return
		var from := area.position + Vector2(randf() * area.size.x, randf() * area.size.y * 0.5)
		var dir := Vector2.from_angle(randf_range(0.25, 0.75) * (1.0 if randf() < 0.5 else -1.0) + (0.0 if randf() < 0.5 else PI)).normalized()
		dir.y = absf(dir.y)
		var star := Node2D.new()
		star.position = from
		star.rotation = dir.angle()
		star.material = _add_mat
		star.draw.connect(func():
			for i in 14:
				star.draw_circle(Vector2(-i * 9.0, 0), maxf(0.6, 3.2 - i * 0.2), Color(0.95, 0.92, 1.0, 1.0 - i / 14.0)))
		$BackLayer.add_child(star)
		var t := star.create_tween().set_parallel()
		t.tween_property(star, "position", from + dir * randf_range(320.0, 520.0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(star, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(star.queue_free)


## Camera flashes popping in the crowd.
func _fx_flashes(points: Array) -> void:
	if points.is_empty():
		return
	while is_inside_tree():
		await get_tree().create_timer(randf_range(0.5, 2.2)).timeout
		if not is_inside_tree():
			return
		var at: Vector2 = points.pick_random() + Vector2(randf_range(-30, 30), randf_range(-20, 20))
		for i in (2 if randf() < 0.3 else 1):   # (sometimes a double flash)
			var f := Sprite2D.new()
			f.texture = _soft_dot()
			f.position = at
			f.scale = Vector2.ONE * randf_range(0.9, 1.5)
			f.material = _add_mat
			f.modulate = Color(1, 1, 1, 0.9 * _fx_level())
			$BackLayer.add_child(f)
			var t := f.create_tween()
			t.tween_property(f, "modulate:a", 0.0, 0.18)
			t.tween_callback(f.queue_free)
			await get_tree().create_timer(0.12).timeout
			if not is_inside_tree():
				return


## Welding sparks bursting from a spot, every few seconds.
func _fx_sparks(at: Vector2, every: float) -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(every * 0.6, every * 1.4)).timeout
		if not is_inside_tree():
			return
		var p := CPUParticles2D.new()
		p.texture = _soft_dot()
		p.position = at
		p.one_shot = true
		p.explosiveness = 0.9
		p.amount = 24
		p.lifetime = 0.8
		p.direction = Vector2(0, -1)
		p.spread = 75.0
		p.initial_velocity_min = 140.0
		p.initial_velocity_max = 330.0
		p.gravity = Vector2(0, 640)
		p.scale_amount_min = 0.05
		p.scale_amount_max = 0.09
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
		ramp.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
		p.color_ramp = ramp
		p.material = _add_mat
		$BackLayer.add_child(p)
		p.emitting = true
		var glow := Sprite2D.new()   # (the weld's own flash)
		glow.texture = _soft_dot()
		glow.position = at
		glow.scale = Vector2.ONE * 1.8
		glow.material = _add_mat
		glow.modulate = Color(1.0, 0.8, 0.45, 0.7)
		$BackLayer.add_child(glow)
		var t := glow.create_tween()
		t.tween_property(glow, "modulate:a", 0.0, 0.5)
		t.tween_callback(glow.queue_free)
		get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## A round part of the picture turning in place (the roulette wheel).
func _fx_spin(tex: Texture2D, centre: Vector2, radius: float, speed: float, at: Vector2, k: float) -> void:
	var disc := ColorRect.new()
	disc.size = Vector2.ONE * radius * 2.0 * k
	disc.position = at - disc.size / 2
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/spin_disc.gdshader")
	m.set_shader_parameter("picture", tex)
	m.set_shader_parameter("tex_size", tex.get_size())
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("tint", $BackLayer/Background.modulate)
	disc.material = m
	$BackLayer.add_child(disc)
	var t := disc.create_tween().set_loops()
	t.tween_method(func(a: float): m.set_shader_parameter("angle", a), 0.0, TAU, TAU / maxf(0.05, speed))


## Glints catching the light on chips and glass: a little four-point star, now here, now there.
func _fx_glints(points: Array) -> void:
	if points.is_empty():
		return
	while is_inside_tree():
		await get_tree().create_timer(randf_range(0.6, 1.8)).timeout
		if not is_inside_tree():
			return
		var g := Node2D.new()
		g.position = points.pick_random() + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		g.material = _add_mat
		g.scale = Vector2.ZERO
		g.draw.connect(func():
			for a in [0.0, PI / 2]:
				var d := Vector2.from_angle(a)
				var n := d.orthogonal()
				g.draw_colored_polygon(PackedVector2Array([d * 16, n * 2.2, -d * 16, -n * 2.2]), Color(1, 0.95, 0.8, 0.95))
			g.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.9)))
		$BackLayer.add_child(g)
		var t := g.create_tween()
		t.tween_property(g, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(g, "rotation", 0.6, 0.5)
		t.tween_property(g, "scale", Vector2.ZERO, 0.3)
		t.tween_callback(g.queue_free)


func _alive(tex_size: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/mat_alive.gdshader")
	m.set_shader_parameter("tex_size", tex_size)
	return m


## Where a point of the full-screen mat image is on the screen (it covers the screen, cropped).
static func _cover_point(p: Vector2, tex_size: Vector2) -> Vector2:
	var m: Vector2 = Game.wide.margin   # (a wide phone: the mat covers the whole screen round the frame, widescreen.gd)
	var screen := Vector2(1920, 1080) + m * 2
	var k := maxf(screen.x / tex_size.x, screen.y / tex_size.y)
	return p * k - (tex_size * k - screen) / 2.0 - m


## The mat's neon: the 160 px patches of the image with lit tubes in them (bright, saturated
## pixels), and where each is on the screen; only ones between the side panels.
func _find_neon(tex: Texture2D, to_screen: Callable) -> Array:
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		return []   # (headless)
	if img.is_compressed():
		img.decompress()
	var ts := Vector2i(tex.get_size())
	if img.get_size() != ts:   # (a backdrop sharper than the pixels it's drawn in: UI.tex)
		img.resize(ts.x, ts.y, Image.INTERPOLATE_BILINEAR)
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
		if not _out.has(side) and duel.sides.has(side) and int(duel.sides[side].get("morale", DuelState.START_MORALE)) <= _max_morale(side) / 3.0:
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
	if pile == "gutter" and side == "player" and _gutter_glow:   # (a Gutter ability is ready: click it)
		var top := layers - 1
		var r := Rect2(p - size / 2 + Vector2(-top * 2.0, -top * 3.0) * k, size).grow(5.0 * k)
		var a := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 260.0)
		draw_rect(r, Color(TEAL, a), false, 5.0 * k)
		draw_rect(r.grow(5.0 * k), Color(TEAL, a * 0.35), false, 4.0 * k)


## The deck and Hideout wear the side's moving back on top (like a face-down card): it turns
## slowly, and speeds up and glows while hovered. Their count and name are drawn over it.
func _update_pile_backs(delta: float) -> void:
	var m := Game.pad.pointer(self)
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
		if _awaiting or side != "player" or not Net.send("coop:action" if _coop else "ffa:action" if _ffa else "mp:action", {"matchId": _match_id, "action": action}):
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
		_refresh_guards()
	_playing = false
	_after_events()


## The "can't be attacked" marker (status "guarded"): on a character whose "can't be attacked while you
## control another character that can be" is working right now, the way attack_targets sees it.
func _refresh_guards() -> void:
	for side in field:
		if not duel.sides.has(side):
			continue
		var open := duel.characters(side).filter(func(e): return not duel.in_stasis(e.card) and duel._passive(side, e.slot, e.card, "elusive").is_empty())
		for slot in field[side]:
			var v: CardView = field[side][slot]
			if v == null or slot >= 5:
				continue
			var c = duel.card_at(side, slot)
			var on: bool = c != null and not open.is_empty() and not duel.in_stasis(c) and not duel._passive(side, slot, c, "elusive").is_empty()
			if on != v.statuses.has("guarded"):
				v.statuses = v.statuses.filter(func(k): return k != "guarded") + (["guarded"] if on else [])


func _after_events() -> void:
	if duel.winner != "":
		return
	_settle_board()
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
		"gutter_exile":
			await _ev_gutter_exile(ev)
		"promote":
			await _ev_promote(ev)
		"effect":
			await _ev_effect(ev)
		"stand":
			await _ev_stand(ev)
		"discard":
			await _ev_discard(ev)
		"charm":
			await _ev_charm(ev)
		"plunder":
			await _ev_plunder(ev)
		"absorb":
			await _ev_absorb(ev)
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
		"miss":
			await _ev_miss(ev)
		"leader_hit":
			await _ev_leader_hit(ev)
		"leader_heal":
			await _ev_leader_heal(ev)
		"leader_down":
			await _ev_leader_down(ev)
		"eliminated":
			await _ev_eliminated(ev)
		"boss_phase":
			await _ev_boss_phase(ev)
		"recycle":
			await _ev_recycle(ev)
		"prompt":
			pass   # (whoever is deciding: the status under the phase panel, _update_status)


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
	CardView.turn_now = int(ev.turn)
	_ui.turn_num.pivot_offset = Vector2(0, _ui.turn_num.size.y / 2)   # (the new number punches in)
	_ui.turn_num.scale = Vector2.ONE * 1.3
	_ui.turn_num.modulate = Color(1.6, 1.6, 1.6) if mine else Color(1.3, 1.1, 1.1)
	var punch: Tween = _ui.turn_num.create_tween().set_parallel()
	punch.tween_property(_ui.turn_num, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(_ui.turn_num, "modulate", Color.WHITE, 0.5)
	_ui.turn_who.text = _turn_text(mine, ev.side)
	_ui.turn_who.label_settings.font_color = BLUE if mine else _side_color(ev.side)
	_phase_side = str(ev.side)
	_ui.phase_track.queue_redraw()
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
	_set_phase_ui(ev.phase, str(ev.get("side", "")))
	if not PHASE_NAMES.has(ev.phase):
		return
	Sfx.play("phase_" + str(ev.phase), 1.0, -2.0)
	await _phase_flash("%s PHASE" % PHASE_NAMES[ev.phase], BLUE if ev.side == "player" else RED)


func _ev_authority(ev: Dictionary) -> void:
	var p: Dictionary = _panels[ev.side]
	# An opponent's Authority paid for a card set face-down isn't shown (DuelState hidden_spend)
	if ev.side != "player" and ev.has("shown") and not duel.reveals("player"):
		var hidden: bool = ev.get("hidden", false)
		ev = ev.duplicate()
		ev.value = ev.shown
		if hidden:
			p.auth.text = "AUTHORITY   %d / %d" % [ev.value, maxi(ev.max, ev.value)]
			return
	p.auth.text = "AUTHORITY   %d / %d" % [ev.value, maxi(ev.max, ev.value)]   # (going second: 2 / 2, not 2 / 1)
	var delta: int = ev.delta
	var at: Vector2 = p.auth.global_position + Vector2(200, 0)
	_float_text(at, ("+%d" % delta) if delta > 0 else str(delta), BLUE if delta > 0 else GOLD, 30)
	var t := create_tween()
	t.tween_property(p.auth, "scale", Vector2.ONE * 1.15, 0.08)
	t.tween_property(p.auth, "scale", Vector2.ONE, 0.18)


func _ev_summon(ev: Dictionary) -> void:
	var side: String = ev.side
	var c: Dictionary = ev.card
	_last_played = {"card": c, "side": side}
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
		"undead":   # UNDEAD: it climbs back out of its owner's Gutter, a pale green glow around it
			v = _new_view(c, side, true)
			v.position = pile_pos(side, "gutter")
			v.modulate = Color(0.75, 1.0, 0.8, 0.0)
			create_tween().tween_property(v, "modulate", Color.WHITE, 0.6)
			_ring(target, Color(0.6, 1.0, 0.7), 1.2)
			_float_text(target + Vector2(0, -110 if side == "player" else 110), "UNDEAD!", Color(0.7, 1.0, 0.75), 38)
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
		elif _clan_style(c, "summon") == "grave":
			await _grave_rise(v, target, heavy)
		elif _clan_style(c, "summon") == "deal":
			await _deal_in(v, target, heavy)
		elif _clan_style(c, "summon") == "firewall":
			await _firewall_in(v, target, heavy)
		elif _clan_style(c, "summon") == "wave":
			await _wave_in(v, target, heavy)
		elif _clan_style(c, "summon") == "spotlight":
			await _spotlight_in(v, target, heavy)
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
	_last_played = {"card": c, "side": side}
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
	_action_tag(center + Vector2(0, 250), "HUSTLE", BLUE, str(c.get("name", "")))
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
	_action_tag(center + Vector2(0, 250), "EQUIP" if str(c.get("subtype", "")) == "equip" else "CONTINUOUS", GOLD, str(c.get("name", "")))
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
	_action_tag(t.home + Vector2(0, -128 if ev.target_side == "player" else 128), "EQUIPPED", GOLD)
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


## A BLIND character's attack that missed (its coin came up tails): it swings past its target at nothing.
func _ev_miss(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(ev.from)
	if v == null:
		return
	var tpos := _target_pos(str(ev.get("foe", DuelState.other(side))), ev.target)
	var dir := (tpos - v.home).normalized()
	var col: Color = CardView.status_color("blind")
	Sfx.play("whoosh", 1.3, -2.0)
	v.z_index = 430
	v.move_to(v.home + dir * 110.0 + dir.orthogonal() * 54.0, 1.1, v.home_rot + 0.16, 0.14)
	await _wait(0.16)
	_float_text(v.position + Vector2(0, -130 if side == "player" else 130), "MISS!", col, 44)
	_burst(v.position + dir * 70.0, col, 14, 200, 0.4, 0.0)
	await _wait(0.4)
	v.z_index = 10
	v.go_home(0.24)
	await _wait(0.26)


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
	# A boost (or cut) for this brawl only ("+700 ATK for this Brawl"): it pops up over the card first
	var shown_a: Array = a.stats()
	if shown_a.size() >= 2 and int(ev.att) != int(shown_a[0]) and int(ev.att) > 0:
		await _brawl_boost(a, int(ev.att) - int(shown_a[0]), "ATK")
	if d is CardView and ev.vs in ["ATK", "DEF"]:
		var shown_d: Array = d.stats()
		var base_d: int = int(shown_d[1] if ev.vs == "DEF" else shown_d[0]) if shown_d.size() >= 2 else int(ev.def)
		if int(ev.def) != base_d:
			await _brawl_boost(d, int(ev.def) - base_d, ev.vs)
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
	elif _clan_style(a.card, "attack") == "cards":
		await _card_strike(a, d, tpos, dir, big, direct)
	elif _clan_style(a.card, "attack") == "skulls":
		await _skull_strike(a, d, tpos, dir, big, direct)
	elif _clan_style(a.card, "attack") == "molotov":
		await _molotov_strike(a, d, tpos, dir, big, direct)
	elif _clan_style(a.card, "attack") == "cannon":
		await _cannon_strike(a, d, tpos, dir, big, direct)
	elif _clan_style(a.card, "attack") == "brawl":
		await _brawl_strike(a, d, tpos, dir, big, direct)
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
	return CardDB.clan_color(str(c.get("clanColor", "")), GOLD)


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
	_flame_burst(tpos, 300.0 if big else 220.0, Color(0.95, 0.9, 1.0), LASER_GLOW, 0.5)   # (a bloom of plasma)
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
	_smoke_puff(target + Vector2(0, 40), 380.0 if heavy else 300.0, Color(0.55, 0.5, 0.42))   # (the dust it throws up)
	var gone := create_tween()
	gone.tween_property(reticle, "alpha", 0.0, 0.25)
	gone.tween_callback(reticle.queue_free)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## Underworld's summon: the ground splits open in a web of glowing violet cracks, spectral fire roars up
## out of it, and the character climbs out of the flames, burning into view from the feet up, with souls
## curling off it; the cracks cool behind it.
func _grave_rise(v: CardView, target: Vector2, heavy: bool) -> void:
	var violet := Color(0.72, 0.32, 1.0)
	var k := 1.25 if heavy else 1.0
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	v.modulate.a = 0.0
	# The ground splits
	var rift := _fx_rect(FX_RIFT, target + Vector2(0, 26), Vector2(300, 250) * k, {"color": violet, "seed": randf() * 50.0, "gain": 0.75}, cards_layer, v.z_index - 2)
	var rm: ShaderMaterial = rift.material
	Sfx.play("slam", 0.55, -3.0)
	Sfx.play("riser", 0.6, -8.0)
	shake(9.0 if heavy else 6.0)
	var crack := create_tween()
	crack.tween_method(func(x: float): rm.set_shader_parameter("open", x), 0.0, 1.0, 0.38).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_burst(target + Vector2(0, 40), Color(0.16, 0.13, 0.18), 22 if heavy else 14, 420.0, 0.7, 1100.0)   # earth thrown up
	_burst(target + Vector2(0, 40), violet, 16, 240.0, 0.6, -80.0)
	await _wait(0.2)
	# Spectral fire roars up out of it
	var fire := _fx_rect(FX_FIRE, target + Vector2(0, -40 * k), Vector2(240, 300) * k, {"life": 0.0, "seed": randf() * 50.0, "gain": 0.55}, cards_layer, v.z_index - 1)
	var fm: ShaderMaterial = fire.material
	var roar := create_tween()
	roar.tween_method(func(x: float): fm.set_shader_parameter("life", x), 0.0, 1.0, 0.14)
	roar.tween_interval(0.42)
	roar.tween_method(func(x: float): fm.set_shader_parameter("life", x), 1.0, 0.0, 0.5)
	roar.tween_callback(fire.queue_free)
	Sfx.play("whoosh", 0.6, -2.0)
	Sfx.play("ambush", 0.5, -10.0)
	# The character climbs out, burning into view from its feet up
	v.position = target + Vector2(0, 54)
	v.rotation = v.home_rot
	v.scale = Vector2.ONE * 0.9 * v.board_scale
	v.modulate = Color.WHITE
	v.reveal = 0.0
	v.reveal_color = violet.lightened(0.25)
	_souls(target, violet, 16 if heavy else 10)
	var climb := create_tween().set_parallel()
	climb.tween_property(v, "position", target + Vector2(0, -10), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	climb.tween_property(v, "scale", Vector2.ONE * 1.06 * v.board_scale, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	climb.tween_property(v, "reveal", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await climb.finished
	v.reveal = 1.0
	# It plants itself; the cracks cool
	var land := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(v, "position", target, 0.18)
	land.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.22)
	var cool := create_tween()
	cool.tween_interval(0.25)
	cool.tween_method(func(x: float): rm.set_shader_parameter("heat", x), 1.0, 0.0, 0.8)
	cool.tween_callback(rift.queue_free)
	_ring(target, violet, 1.5 if heavy else 1.15)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## A rectangle running one of the effect shaders, centred on at, under parent (z: its order there).
func _fx_rect(shader: Shader, at: Vector2, size: Vector2, params: Dictionary, parent: Node, z := 70) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.position = at - size / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = z
	var m := ShaderMaterial.new()
	m.shader = shader
	for key in params:
		m.set_shader_parameter(key, params[key])
	r.material = m
	parent.add_child(r)
	return r


## Souls curling up and away from a spot: pale violet wisps that swirl as they rise.
func _souls(at: Vector2, col: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = at + Vector2(0, 40)
	p.one_shot = true
	p.explosiveness = 0.55
	p.amount = amount
	p.lifetime = 1.3
	p.texture = ArenaLife._soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(70, 20)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2(0, -60)
	p.tangential_accel_min = -90.0
	p.tangential_accel_max = 90.0
	p.damping_min = 20.0
	p.damping_max = 50.0
	var size := Curve.new()
	size.add_point(Vector2(0, 0.4))
	size.add_point(Vector2(0.3, 1.0))
	size.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = size
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.15, Color(col.lightened(0.3), 0.55))
	g.set_color(g.get_point_count() - 1, Color(col, 0.0))
	p.color_ramp = g
	p.material = _add_mat
	p.z_index = 80
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Bone shards flying apart (a skull breaking on impact); palette: other colours (start, middle, end),
## e.g. a bottle's glass.
func _shards(at: Vector2, dir: Vector2, amount: int, palette: Array = []) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.8
	p.texture = ArenaLife._leaf()   # (a pointed sliver)
	p.direction = dir
	p.spread = 70.0
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 620.0
	p.gravity = Vector2(0, 1100)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	if palette.is_empty():
		palette = [Color(0.92, 0.88, 0.95, 1.0), Color(0.78, 0.7, 0.85, 0.8), Color(0.6, 0.5, 0.7, 0.0)]
	var g := Gradient.new()
	g.set_color(0, palette[0])
	g.add_point(0.7, palette[1])
	g.set_color(g.get_point_count() - 1, palette[2])
	p.color_ramp = g
	p.z_index = 82
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## A round burst of spectral flame, blooming and dying away.
func _flame_burst(at: Vector2, size: float, core: Color, outer: Color, secs := 0.45) -> void:
	if Game.photosafe():   # (Photosensitive mode: no bright core, and it comes and goes slower)
		outer = outer.darkened(0.35)
		core = outer.lerp(core, 0.2)
		secs = maxf(secs, 0.6)
	var f := _fx_rect(FX_FIRE, at, Vector2.ONE * size, {"shape": 1, "core": core, "outer": outer, "life": 1.0, "seed": randf() * 50.0, "speed": 2.4}, fx, 81)
	var m: ShaderMaterial = f.material
	f.pivot_offset = f.size / 2.0
	f.scale = Vector2.ONE * 0.4
	var t := create_tween().set_parallel()
	t.tween_property(f, "scale", Vector2.ONE * 1.15, secs).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_method(func(x: float): m.set_shader_parameter("life", x), 1.0, 0.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(f.queue_free)


## Wildcard's summon: dealt in from across the table, spinning flat, and landing with a burst of chips.
func _deal_in(v: CardView, target: Vector2, heavy: bool) -> void:
	var gold := Color(1.0, 0.82, 0.35)
	var from := Vector2(1080, DIVIDER_Y - 40)
	v.position = from
	v.scale = Vector2.ONE * 0.5 * v.board_scale
	v.rotation = v.home_rot - TAU * (2.0 if heavy else 1.5)
	v.modulate.a = 1.0
	Sfx.play("shuffle", 1.4, -2.0)
	if heavy:
		_cam_focus(target, 1.06, 0.3)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "position", target, 0.42 if heavy else 0.34)
	t.tween_property(v, "rotation", v.home_rot, 0.42 if heavy else 0.34)
	t.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.42 if heavy else 0.34)
	await t.finished
	v.kick(Vector2(0, 1), 12.0)
	Sfx.play("karat", 1.2, -6.0)
	for col in [Color(0.85, 0.1, 0.12), Color(0.1, 0.08, 0.1), gold]:   # chips scattering off it: red, black and gold
		_burst(target, col, 8 if heavy else 5, 340.0, 0.55, 500.0)
	_ring(target, gold, 1.3 if heavy else 1.0)
	_flame_burst(target, 280.0 if heavy else 220.0, Color(1.0, 0.97, 0.82), Color(1.0, 0.7, 0.18), 0.45)
	_suits(target, 8 if heavy else 6)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## A puff of dust or smoke that billows out and thins away (normal blend: it darkens what's behind).
func _smoke_puff(at: Vector2, size: float, col: Color) -> void:
	var s := _fx_rect(FX_SMOKE, at, Vector2.ONE * size, {"color": col, "seed": randf() * 50.0, "density": 0.75}, fx, 79)
	var m: ShaderMaterial = s.material
	s.pivot_offset = s.size / 2.0
	s.scale = Vector2.ONE * 0.45
	var t := create_tween().set_parallel()
	t.tween_property(s, "scale", Vector2.ONE * 1.25, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_method(func(x: float): m.set_shader_parameter("life", x), 1.0, 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(s.queue_free)


## A spent shell flicked out of the gun, tumbling to the floor.
func _casing(at: Vector2, dir: Vector2) -> void:
	var c := ColorRect.new()
	c.size = Vector2(4, 9)
	c.pivot_offset = c.size / 2.0
	c.color = Color(0.95, 0.75, 0.3)
	c.position = at - c.size / 2.0
	c.z_index = 73
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(c)
	var out := dir.orthogonal() * (1.0 if randf() < 0.5 else -1.0) * randf_range(50, 90) - dir * randf_range(10, 30)
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "position", c.position + out + Vector2(0, -20), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "rotation", randf_range(-10.0, 10.0), 0.45)
	t.chain().tween_property(c, "position", c.position + out * 1.3 + Vector2(0, 24), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_property(c, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(c.queue_free)


## Card suits flying out of a spot, spinning and fading (Wildcard's deal-in).
func _suits(at: Vector2, n: int) -> void:
	for i in n:
		var l := Label.new()
		var s: int = i % 4
		l.text = ["♠", "♥", "♣", "♦"][s]
		l.add_theme_font_size_override("font_size", randi_range(26, 38))
		l.add_theme_color_override("font_color", Color(0.9, 0.1, 0.12) if s % 2 == 1 else Color(0.1, 0.08, 0.1))
		l.add_theme_color_override("font_outline_color", Color(1.0, 0.85, 0.4))
		l.add_theme_constant_override("outline_size", 6)
		l.z_index = 83
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.add_child(l)
		l.pivot_offset = l.get_minimum_size() / 2.0
		l.position = at - l.pivot_offset
		var to := at + Vector2.from_angle(TAU * i / n + randf_range(-0.3, 0.3)) * randf_range(110, 170) - l.pivot_offset
		var t := l.create_tween().set_parallel()
		t.tween_property(l, "position", to, 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(l, "rotation", randf_range(-2.5, 2.5), 0.55)
		t.tween_property(l, "scale", Vector2.ONE * 1.3, 0.55)
		t.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.3)
		t.chain().tween_callback(l.queue_free)


## Underworld's attack: a summoning circle opens in front of the attacker and horned skulls of violet
## flame burst out of it one after another, trailing fire and embers, each breaking on the target in a
## bloom of flame and bone; a big hit ends with a great skull and the full impact.
func _skull_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var violet := Color(0.72, 0.32, 1.0)
	var hot := Color(1.0, 0.82, 1.0)
	var side_v := dir.orthogonal()
	var from := a.home + dir * 118.0
	_cam_focus(a.home.lerp(tpos, 0.35), 1.05 if big else 1.03, 0.3)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 26.0, 0.26)
	t.tween_property(a, "scale", Vector2.ONE * 1.16 * a.board_scale, 0.26)
	# The circle draws itself on
	var circle := _fx_rect(FX_RUNES, from, Vector2.ONE * (230.0 if big else 190.0), {"open": 0.0, "life": 1.0, "color": violet, "seed": randf() * 20.0}, fx, 71)
	var cm: ShaderMaterial = circle.material
	circle.pivot_offset = circle.size / 2.0
	circle.rotation = dir.angle()
	create_tween().tween_method(func(x: float): cm.set_shader_parameter("open", x), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	Sfx.play("riser", 1.2, -6.0)
	Sfx.play("ambush", 1.3, -10.0)
	_burst(from, violet, 14, -160.0, 0.4, 0.0)   # (motes drawn into it)
	await t.finished
	_clear_attack_line()
	var n := 3
	for i in n:
		var to := tpos + side_v * randf_range(-34.0, 34.0)
		var bend := side_v * (80.0 if i % 2 == 0 else -80.0) * randf_range(0.6, 1.1)
		_skull_fly(from, to, bend, 0.26, 1.0, func():
			_flame_burst(to, 170.0, hot, violet)
			_shards(to, dir, 10)
			_sparks(to, dir, Color(0.88, 0.62, 1.0), 10, 55.0)
			Sfx.play("hit", randf_range(0.8, 1.0), -7.0)
			shake(5.0)
			if d:
				d.kick(dir, 11.0))
		Sfx.play("whoosh", randf_range(1.2, 1.4), -6.0)
		a.kick(-dir, 7.0)
		await _wait(0.12)
	await _wait(0.22)
	if big:   # a great skull, thrown hard
		Sfx.play("laser", 0.55, -4.0)
		await _skull_fly(from, tpos, Vector2.ZERO, 0.2, 2.1, Callable())
	var fade := create_tween()
	fade.tween_method(func(x: float): cm.set_shader_parameter("life", x), 1.0, 0.0, 0.3)
	fade.tween_callback(circle.queue_free)
	# Impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("hit", 0.8 if direct else 0.95)
	Sfx.play("boom", 0.9 if big else 1.15, 0.0 if big else -5.0)
	shake(22.0 if big else 12.0)
	_shockwave(tpos, 0.9 if big else 0.5)
	_post_pulse("aberration", 12.0 if big else 5.0, 0.4)
	_flame_burst(tpos, 330.0 if big else 240.0, hot, violet, 0.6)
	_shards(tpos, dir, 26 if big else 14)
	_burst(tpos, violet, 26, 520.0)
	_burst(tpos, Color(1.0, 0.25, 0.35), 10, 360.0)
	_ring(tpos, violet, 1.5 if big else 1.2)
	if d:
		d.flash()
		d.kick(dir, 30.0 if big else 22.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (30.0 if big else 18.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)
	a.create_tween().tween_property(a, "rotation", a.home_rot, 0.2)


## One flaming skull flying from -> to along a curve (bend: how far it swings out), hit() when it lands.
func _skull_fly(from: Vector2, to: Vector2, bend: Vector2, secs: float, size: float, hit: Callable) -> void:
	var sk := FlameSkull.new()
	sk.position = from
	sk.z_index = 72
	sk.scale = Vector2.ONE * 0.2 * size
	fx.add_child(sk)
	sk.build(_add_mat, FX_COMET)
	sk.create_tween().tween_property(sk, "scale", Vector2.ONE * size, 0.08)
	var last := from
	var fly := sk.create_tween()
	fly.tween_method(func(k: float):
		var m := from.lerp(to, k) + bend * 4.0 * k * (1.0 - k)
		if m.distance_to(last) > 0.5:
			sk.rotation = (m - last).angle() + PI   # (its tail streams out behind)
		last = m
		sk.position = m, 0.0, 1.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fly.finished
	if hit.is_valid():
		hit.call()
	sk.burn_out()


## A horned skull wreathed in violet flame (Underworld's attack): the skull off the clan's card back,
## a comet's tail of fire behind it, a glow round it and embers shed along the way. Its local +x points
## back along the flight.
class FlameSkull extends Node2D:
	var _embers: CPUParticles2D
	var _tail: ColorRect

	func build(add_mat: Material, comet: Shader) -> void:
		var glow := Sprite2D.new()
		glow.texture = ArenaLife._soft_dot()
		glow.scale = Vector2.ONE * 2.2
		glow.modulate = Color(0.6, 0.25, 1.0, 0.4)
		glow.material = add_mat
		add_child(glow)
		_tail = ColorRect.new()
		_tail.size = Vector2(220, 60)
		_tail.position = Vector2(10, -30)
		_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = comet
		m.set_shader_parameter("seed", randf() * 30.0)
		_tail.material = m
		add_child(_tail)
		var skull := Sprite2D.new()
		if ResourceLoader.exists("res://assets/fx_skull.png"):
			skull.texture = load("res://assets/fx_skull.png")
		skull.scale = Vector2.ONE * 0.5
		skull.rotation = PI / 2   # (jaw first)
		add_child(skull)
		var hot := Sprite2D.new()   # its eyes and edges lit from within
		hot.texture = skull.texture
		hot.scale = skull.scale
		hot.rotation = skull.rotation
		hot.modulate = Color(0.75, 0.35, 1.0, 0.35)
		hot.material = add_mat
		add_child(hot)
		_embers = CPUParticles2D.new()
		_embers.local_coords = false
		_embers.amount = 40
		_embers.lifetime = 0.5
		_embers.texture = ArenaLife._soft_dot()
		_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_embers.emission_sphere_radius = 14.0
		_embers.direction = Vector2(1, 0)
		_embers.spread = 40.0
		_embers.initial_velocity_min = 30.0
		_embers.initial_velocity_max = 110.0
		_embers.gravity = Vector2(0, -60)
		_embers.scale_amount_min = 0.08
		_embers.scale_amount_max = 0.18
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.85, 1.0, 1.0))
		g.set_color(1, Color(0.55, 0.15, 1.0, 0.0))
		_embers.color_ramp = g
		_embers.material = add_mat
		add_child(_embers)

	## Hit: the skull is gone at once; its embers and tail die away behind it.
	func burn_out() -> void:
		for c in get_children():
			if c is Sprite2D:
				c.visible = false
		_embers.emitting = false
		var t := create_tween()
		t.tween_property(_tail, "modulate:a", 0.0, 0.15)
		t.tween_interval(0.45)
		t.tween_callback(queue_free)


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


## Arsonists' attack: the attacker rears back as the rag catches and lobs a lit Molotov high across
## the board, spinning and shedding embers; it smashes on the target (_splash). A big hit lobs a
## second bottle first, a little wide.
func _molotov_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var ember := Color(1.0, 0.42, 0.08)
	var hot := Color(1.0, 0.9, 0.55)
	var from := a.home + dir * 70.0
	_cam_focus(a.home.lerp(tpos, 0.4), 1.05 if big else 1.03, 0.3)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 44.0, 0.3)
	t.tween_property(a, "scale", Vector2.ONE * 1.16 * a.board_scale, 0.3)
	Sfx.play("ignite", 1.0, -4.0)
	_flame_burst(from, 90.0, hot, ember, 0.35)   # (the rag catches)
	await t.finished
	_clear_attack_line()
	if big:
		var wide := tpos + dir.orthogonal() * 46.0
		Sfx.play("whoosh", 0.9, -6.0)
		_molotov_fly(from, wide, 0.42, 0.85, func(): _splash(wide, dir, 0.6, null))
		a.kick(-dir, 8.0)
		await _wait(0.22)
	Sfx.play("whoosh", 0.8, -3.0)
	a.create_tween().tween_property(a, "position", a.home + dir * 16.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _molotov_fly(from, tpos, 0.5, 1.15 if big else 1.0, Callable())
	# Impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("glass_smash", 1.0, -2.0)
	Sfx.play("hit", 0.85 if direct else 1.0, -4.0)
	Sfx.play("boom", 0.9 if big else 1.15, 0.0 if big else -5.0)
	shake(22.0 if big else 12.0)
	_shockwave(tpos, 0.9 if big else 0.5)
	_post_pulse("aberration", 10.0 if big else 5.0, 0.4)
	_splash(tpos, dir, 1.3 if big else 1.0, d)
	_ring(tpos, ember, 1.5 if big else 1.2)
	if d:
		d.flash()
		d.kick(dir, 30.0 if big else 22.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (30.0 if big else 18.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)
	a.create_tween().tween_property(a, "rotation", a.home_rot, 0.2)


## Pirates attack: a ship's cannon rolls up in front of the attacker and swings round to aim, its fuse
## fizzes, and it fires: a muzzle flash and a cloud of smoke as it kicks back, the cannonball flying across
## trailing smoke, smashing into the target in wood splinters, sparks and smoke. A big hit: a bigger gun.
func _cannon_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var k := 1.6 if big else 1.35
	# It rolls up beside the attacker, on the side away from the target so its barrel leans across toward it
	var size := CardView.SIZE * a.board_scale
	var side := -1.0 if tpos.x >= a.home.x - 4.0 else 1.0
	var spot := a.home + Vector2(side * (size.x * 0.5 + 40.0 * k), signf(dir.y) * size.y * 0.18)
	var gun := Cannon.new()
	gun.position = spot
	gun.z_index = 72
	gun.flip = side > 0.0   # (on the right: it faces left)
	fx.add_child(gun)
	gun.aim_at(tpos)
	gun.scale = Vector2.ZERO
	_cam_focus(a.home.lerp(tpos, 0.4), 1.05 if big else 1.03, 0.3)
	Sfx.play("creak", 0.9, -4.0)
	var t := create_tween().set_parallel()
	t.tween_property(gun, "scale", Vector2.ONE * k, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 30.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_smoke_puff(spot + Vector2(0, 24.0 * k), 60.0 * k, Color(0.5, 0.48, 0.42))   # (dust as it rolls up)
	await t.finished
	_clear_attack_line()
	# The fuse fizzes at the back of the barrel
	var fuse := gun.breech()
	Sfx.play("ignite", 1.3, -6.0)
	for i in 4:
		get_tree().create_timer(i * 0.07).timeout.connect(func(): _sparks(fuse, Vector2.UP, Color(1.0, 0.8, 0.35), 5, 70.0))
	await _wait(0.32)
	# Fire
	var muzzle := gun.muzzle()
	Sfx.play("cannon", 0.85 if big else 1.0, 0.0)
	Sfx.play("boom", 1.2, -6.0)
	shake(14.0 if big else 9.0)
	_flame_burst(muzzle, 70.0 * k, Color(1.0, 0.95, 0.7), Color(1.0, 0.5, 0.15), 0.25)
	_smoke_puff(muzzle, 110.0 * k, Color(0.62, 0.62, 0.6))
	_ring(muzzle, Color(1.0, 0.85, 0.55), 0.7)
	gun.kick()
	var ball := Cannonball.new()
	ball.position = muzzle
	ball.z_index = 73
	ball.scale = Vector2.ONE * k * 0.9
	fx.add_child(ball)
	var trail := CPUParticles2D.new()   # (smoke behind it)
	trail.local_coords = false
	trail.amount = 30
	trail.lifetime = 0.6
	trail.texture = ArenaLife._soft_dot()
	trail.spread = 25.0
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 20.0
	trail.gravity = Vector2(0, -30)
	trail.scale_amount_min = 0.25
	trail.scale_amount_max = 0.5
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.75, 0.72, 0.55))
	g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	trail.color_ramp = g
	ball.add_child(trail)
	var lob := minf(70.0, muzzle.distance_to(tpos) * 0.12)
	var fly := create_tween()
	fly.tween_method(func(q: float):
		ball.position = muzzle.lerp(tpos, q) + Vector2(0, -lob * 4.0 * q * (1.0 - q))
		ball.rotation += 0.3, 0.0, 1.0, 0.3 if big else 0.26)
	await fly.finished
	ball.position = tpos
	trail.emitting = false
	ball.get_child(0).reparent(fx)   # (the smoke trail lingers as the ball goes)
	var left := trail
	get_tree().create_timer(0.7).timeout.connect(func(): if is_instance_valid(left): left.queue_free())
	ball.queue_free()
	# Impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("hit", 0.85 if direct else 1.0, -2.0)
	Sfx.play("boom", 0.8 if big else 1.0, 0.0 if big else -4.0)
	shake(24.0 if big else 14.0)
	_shockwave(tpos, 0.9 if big else 0.55)
	_post_pulse("aberration", 10.0 if big else 5.0, 0.4)
	_flame_burst(tpos, 80.0 * k, Color(1.0, 0.9, 0.6), Color(1.0, 0.45, 0.12), 0.3)
	_shards(tpos, dir, 16 if big else 10, [Color(0.55, 0.38, 0.22, 1.0), Color(0.42, 0.28, 0.16, 0.9), Color(0.25, 0.17, 0.1, 0.0)])   # (splinters)
	_sparks(tpos, dir, Color(1.0, 0.75, 0.35), 18 if big else 12, 70.0)
	_smoke_puff(tpos, 130.0 * k, Color(0.3, 0.3, 0.3))
	_ring(tpos, Color(0.35, 0.95, 0.85), 1.5 if big else 1.2)
	if d:
		d.flash()
		d.kick(dir, 30.0 if big else 22.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (30.0 if big else 18.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)
	a.create_tween().tween_property(a, "rotation", a.home_rot, 0.2)
	var gone := gun.create_tween()   # (the cannon rolls away into its smoke)
	gone.tween_interval(0.35)
	gone.tween_property(gun, "modulate:a", 0.0, 0.35)
	gone.tween_callback(gun.queue_free)


## Pirates summon: a pool of dark sea water opens in the slot, a wave bursts up out of it and the
## character rises through it, streaming water, ripples spreading as it settles.
func _wave_in(v: CardView, target: Vector2, heavy: bool) -> void:
	var sea := Color(0.2, 0.85, 0.8)
	var foam := Color(0.85, 1.0, 0.98)
	var k := 1.25 if heavy else 1.0
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	var size := CardView.SIZE * v.board_scale
	var pool := Sprite2D.new()   # (the water, seen at an angle: a flattened disc)
	pool.texture = ArenaLife._soft_dot()
	pool.position = target + Vector2(0, size.y * 0.25)
	pool.modulate = Color(0.04, 0.3, 0.34, 0.0)
	pool.z_index = v.z_index - 1
	cards_layer.add_child(pool)
	var pk := size.x / 64.0 * 2.2 * k
	var open := pool.create_tween().set_parallel()
	open.tween_property(pool, "scale", Vector2(pk, pk * 0.5), 0.3).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	open.tween_property(pool, "modulate:a", 0.85, 0.2)
	Sfx.play("splash", 0.9, -3.0)
	for i in 3:   # (ripples)
		get_tree().create_timer(i * 0.12).timeout.connect(func(): _ring(pool.position, sea, 1.1 + i * 0.25))
	await _wait(0.25)
	# The wave bursts up
	Sfx.play("splash", 1.15, -1.0)
	shake(5.0 if heavy else 3.0)
	_water_spray(pool.position, size.x * 0.9 * k, 70 if heavy else 50, sea, foam)
	# ...and the character rises out of it, wet and dark, brightening as it clears the water
	v.position = target + Vector2(0, size.y * 0.55)
	v.rotation = v.home_rot
	v.scale = Vector2.ONE * 0.8 * v.board_scale
	v.modulate = Color(0.25, 0.6, 0.65, 0.0)
	var rise := create_tween().set_parallel()
	rise.tween_property(v, "modulate:a", 1.0, 0.15)
	rise.tween_property(v, "position", target + Vector2(0, -22.0 * k), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_property(v, "scale", Vector2.ONE * 1.06 * v.board_scale, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_property(v, "modulate", Color.WHITE, 0.45).set_delay(0.15)
	await rise.finished
	_drips(v.position, size)
	var land := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(v, "position", target, 0.2)
	land.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.22)
	var close := pool.create_tween()
	close.tween_property(pool, "modulate:a", 0.0, 0.5)
	close.tween_callback(pool.queue_free)
	_ring(target, sea, 1.5 if heavy else 1.15)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## Pirates KO: a whirlpool opens under the card and it spins down into it, darkening, bubbles rising,
## until the water closes over it in a last splash.
func _sink_ko(v: CardView) -> void:
	var sea := Color(0.2, 0.85, 0.8)
	var at := v.position
	var size := CardView.SIZE * v.scale
	Sfx.play("ko", 0.9)
	Sfx.play("splash", 0.75, -3.0)
	shake(9)
	_post_pulse("aberration", 5.0, 0.35)
	_stamp(at, "K.O.", Color(0.35, 0.95, 0.85))
	var swirl := Node2D.new()   # (rings of water turning, drawn as broken arcs)
	swirl.position = at + Vector2(0, size.y * 0.2)
	swirl.z_index = v.z_index - 1
	swirl.scale = Vector2(1.0, 0.55)
	swirl.draw.connect(func():
		for i in 4:
			var r := size.x * (0.25 + 0.2 * i)
			for j in 3:
				var a0 := j * TAU / 3.0 + i * 0.7
				swirl.draw_arc(Vector2.ZERO, r, a0, a0 + 1.4, 18, Color(sea, 0.55 - 0.1 * i), 5.0 - i, true))
	cards_layer.add_child(swirl)
	var pit := Sprite2D.new()   # (the dark eye of it)
	pit.texture = ArenaLife._soft_dot()
	pit.position = swirl.position
	pit.modulate = Color(0.0, 0.08, 0.1, 0.85)
	pit.scale = Vector2(2.4, 1.2) * size.x / 64.0
	pit.z_index = v.z_index - 2
	cards_layer.add_child(pit)
	var turn := swirl.create_tween().set_parallel()
	turn.tween_property(swirl, "rotation", -TAU * 1.6, 1.3)
	turn.tween_property(swirl, "modulate:a", 0.0, 0.4).set_delay(0.95)
	_bubbles(at, size)
	var down := create_tween().set_parallel()
	down.tween_property(v, "rotation", v.rotation + 2.2, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(v, "scale", v.scale * 0.25, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(v, "position", swirl.position, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(v, "modulate", Color(0.1, 0.35, 0.4, 0.0), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await down.finished
	Sfx.play("splash", 1.2, -5.0)
	_water_spray(swirl.position, size.x * 0.5, 14, sea, Color(0.85, 1.0, 0.98))
	_ring(swirl.position, sea, 1.0)
	var shut := pit.create_tween()
	shut.tween_property(pit, "modulate:a", 0.0, 0.5)
	shut.tween_callback(pit.queue_free)
	get_tree().create_timer(0.5).timeout.connect(swirl.queue_free)
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.2)


## Sea spray bursting up from at: water drops thrown up and falling back, and white foam
func _water_spray(at: Vector2, width: float, amount: int, sea: Color, foam: Color) -> void:
	for white in [false, true]:
		var p := CPUParticles2D.new()
		p.position = at
		p.z_index = 74
		p.one_shot = true
		p.explosiveness = 0.85
		p.amount = amount if not white else amount / 2
		p.lifetime = 1.0
		p.texture = ArenaLife._soft_dot()
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(width * 0.5, 6)
		p.direction = Vector2.UP
		p.spread = 22.0
		p.initial_velocity_min = 300.0
		p.initial_velocity_max = 560.0
		p.gravity = Vector2(0, 950)
		p.scale_amount_min = 0.22 if not white else 0.35
		p.scale_amount_max = 0.55 if not white else 0.8
		var g := Gradient.new()
		g.set_color(0, Color(foam if white else sea, 0.95))
		g.set_color(1, Color(foam if white else sea, 0.0))
		p.color_ramp = g
		if white:
			p.material = _add_mat
		fx.add_child(p)
		p.emitting = true
		get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Water streaming off a card that's just come up out of the sea
func _drips(at: Vector2, size: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 74
	p.one_shot = true
	p.explosiveness = 0.3
	p.amount = 24
	p.lifetime = 0.7
	p.texture = ArenaLife._soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x * 0.45, size.y * 0.4)
	p.direction = Vector2.DOWN
	p.spread = 8.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var g := Gradient.new()
	g.set_color(0, Color(0.7, 1.0, 0.95, 0.9))
	g.set_color(1, Color(0.3, 0.8, 0.8, 0.0))
	p.color_ramp = g
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Bubbles rising out of the water where a card sinks
func _bubbles(at: Vector2, size: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at + Vector2(0, size.y * 0.15)
	p.z_index = 74
	p.amount = 26
	p.lifetime = 1.1
	p.texture = ArenaLife._soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x * 0.35, 10)
	p.direction = Vector2.UP
	p.spread = 15.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, -60)
	p.tangential_accel_min = -30.0
	p.tangential_accel_max = 30.0
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 1.0, 0.97, 0.0))
	g.add_point(0.2, Color(0.75, 1.0, 0.97, 0.75))
	g.set_color(1, Color(0.75, 1.0, 0.97, 0.0))
	p.color_ramp = g
	p.material = _add_mat
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.1).timeout.connect(func(): p.emitting = false)
	get_tree().create_timer(2.4).timeout.connect(p.queue_free)


## One Molotov lobbed from -> to (high in the middle: it swells as it comes up toward the view),
## hit() when it lands.
func _molotov_fly(from: Vector2, to: Vector2, secs: float, size: float, hit: Callable) -> void:
	var m := Molotov.new()
	m.position = from
	m.z_index = 72
	m.spin = randf_range(2.5, 4.0) * (1.0 if to.x >= from.x else -1.0)
	m.tumble_speed = randf_range(11.0, 14.0)
	fx.add_child(m)
	m.build(_add_mat, FX_FIRE)
	m.scale = Vector2.ONE * 0.8 * size
	# Its shadow on the board, under the path: small and faint while it's high, sharp as it comes down
	var shadow := Sprite2D.new()
	shadow.texture = ArenaLife._soft_dot()
	shadow.modulate = Color(0, 0, 0, 0.0)
	shadow.z_index = 71
	shadow.position = from
	fx.add_child(shadow)
	var light := Sprite2D.new()   # (the burning rag's light on the floor beneath it)
	light.texture = ArenaLife._soft_dot()
	light.material = _add_mat
	light.modulate = Color(1.0, 0.5, 0.15, 0.0)
	light.z_index = 71
	fx.add_child(light)
	var lob := maxf(120.0, from.distance_to(to) * 0.35)
	var fly := m.create_tween()
	fly.tween_method(func(k: float):
		var arc := 4.0 * k * (1.0 - k)
		m.position = from.lerp(to, k) + Vector2(0, -lob * arc)
		m.scale = Vector2.ONE * size * (1.35 + 0.55 * arc)
		shadow.position = from.lerp(to, k) + Vector2(0, 26.0 * size)
		shadow.scale = Vector2(1.5, 0.55) * size * (1.0 - 0.5 * arc)
		shadow.modulate.a = 0.55 * (1.0 - 0.6 * arc)
		light.position = shadow.position
		light.scale = Vector2(2.6, 0.95) * size * (1.0 - 0.35 * arc)
		light.modulate.a = 0.42 * (1.0 - 0.7 * arc), 0.0, 1.0, secs)
	await fly.finished
	shadow.queue_free()
	light.queue_free()
	if hit.is_valid():
		hit.call()
	m.smash()


## A Molotov breaking: a bloom of fire, glass glinting as it flies, and the burning fuel licking up
## over the card it hit (or the spot) in ragged tongues, the card still showing through, before it
## dies down to smoke.
func _splash(at: Vector2, dir: Vector2, k: float, d: CardView) -> void:
	var ember := Color(1.0, 0.42, 0.08)
	_flame_burst(at, 220.0 * k, Color(1.0, 0.78, 0.4), ember, 0.5)
	_shards(at, dir, int(10 * k), [Color(1.0, 0.92, 0.75, 0.9), Color(0.95, 0.6, 0.25, 0.6), Color(0.7, 0.35, 0.1, 0.0)])
	_burst(at, ember, int(22 * k), 420.0, 0.8, -120.0)   # (embers thrown up)
	_sparks(at, dir, Color(1.0, 0.7, 0.3), int(14 * k), 70.0)
	var foot := (d.home + Vector2(0, CardView.SIZE.y * 0.4 * d.scale.y)) if d else at + Vector2(0, 60)
	# The fuel spreads flat across the floor: a burning pool, and the scorch it leaves (seen at an angle)
	var pool := Sprite2D.new()
	pool.texture = ArenaLife._soft_dot()
	pool.material = _add_mat
	pool.modulate = Color(1.0, 0.45, 0.1, 0.0)
	pool.position = foot
	pool.scale = Vector2(1.2, 0.45) * k
	pool.z_index = 70
	fx.add_child(pool)
	var scorch := Sprite2D.new()
	scorch.texture = ArenaLife._soft_dot()
	scorch.modulate = Color(0.05, 0.03, 0.02, 0.0)
	scorch.position = foot
	scorch.scale = Vector2(3.4, 1.15) * k
	scorch.z_index = 69
	fx.add_child(scorch)
	var spread := create_tween().set_parallel()
	spread.tween_property(pool, "scale", Vector2(4.6, 1.6) * k, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	spread.tween_property(pool, "modulate:a", 0.8, 0.12)
	spread.tween_property(scorch, "modulate:a", 0.45, 0.3)
	spread.chain().tween_interval(0.5 * k)
	spread.chain().tween_property(pool, "modulate:a", 0.0, 0.7)
	spread.tween_property(scorch, "modulate:a", 0.0, 1.6).set_delay(0.4)
	spread.chain().tween_callback(func():
		pool.queue_free()
		scorch.queue_free())
	var row := _flame_row(foot, 170.0 * k, 200.0 * k, 4, cards_layer, d.z_index + 1 if d else 75, Color(1.0, 0.8, 0.45), ember, 0.5)
	var burn := create_tween()
	burn.tween_method(_row_life.bind(row), 0.0, 1.0, 0.12)
	burn.tween_interval(0.55 * k)
	burn.tween_method(_row_life.bind(row), 1.0, 0.0, 0.6)
	burn.tween_callback(_row_free.bind(row))
	get_tree().create_timer(0.5).timeout.connect(func(): _smoke_puff(at + Vector2(0, -50), 280.0 * k, Color(0.12, 0.1, 0.09)))


## A row of flames: n tongues of fire side by side across width, standing on foot (the middle of their
## base), taller in the middle and each its own height, so the top is ragged. Lit by _row_life.
func _flame_row(foot: Vector2, width: float, height: float, n: int, parent: Node, z: int, core: Color, outer: Color, gain := 0.7) -> Array:
	var row := []
	var w := width / n * 1.9
	for i in n:
		var middle := 1.0 - absf(i / maxf(n - 1.0, 1.0) - 0.5) * 0.5
		var h := height * randf_range(0.72, 1.0) * middle
		var x := foot.x - width / 2.0 + (i + 0.5) * width / n + randf_range(-6.0, 6.0)
		var f := _fx_rect(FX_FIRE, Vector2(x, foot.y - h / 2.0), Vector2(w, h),
			{"core": core, "outer": outer, "life": 0.0, "seed": randf() * 50.0, "gain": gain, "speed": randf_range(1.8, 2.6)}, parent, z)
		f.pivot_offset = Vector2(w / 2.0, h)   # (they grow up from their foot)
		row.append(f)
	return row


func _row_life(x: float, row: Array) -> void:
	for f in row:
		if is_instance_valid(f):
			(f.material as ShaderMaterial).set_shader_parameter("life", x)


func _row_free(row: Array) -> void:
	for f in row:
		if is_instance_valid(f):
			f.queue_free()


## A lit Molotov (Arsonists' attack): a round amber bottle with a burning rag in its neck, a glow round it,
## embers and smoke shed as it flies. The bottle tumbles end over end (tumble: it foreshortens as it turns
## toward and away from the view) and spins a little; its flame keeps burning upward.
## A ship's cannon seen side-on, standing on its wooden carriage and two wheels: an iron barrel with brass
## bands that tilts on its trunnion to aim (aim_at). flip: it faces left. kick(): it recoils and rolls
## back. muzzle() / breech(): where the shot leaves and the fuse is, on screen.
class Cannon extends Node2D:
	const PIVOT := Vector2(-2, -12)   # the trunnion the barrel turns on
	var flip := false
	var _root: Node2D
	var _barrel: Node2D

	func _ready() -> void:
		_root = Node2D.new()
		_root.scale.x = -1.0 if flip else 1.0
		add_child(_root)
		var carriage := Node2D.new()
		carriage.draw.connect(_draw_carriage.bind(carriage))
		_root.add_child(carriage)
		_barrel = Node2D.new()
		_barrel.position = PIVOT
		_barrel.draw.connect(_draw_barrel)
		_root.add_child(_barrel)
		var cheek := Node2D.new()   # (the bracket over the trunnion, in front of the barrel)
		cheek.draw.connect(func():
			cheek.draw_circle(PIVOT, 5.5, Color(0.85, 0.62, 0.25))
			cheek.draw_arc(PIVOT, 5.5, 0, TAU, 14, Color(0.04, 0.03, 0.03), 1.5, true))
		_root.add_child(cheek)

	## Tilts the barrel toward a point on screen (it can't point back over its own carriage)
	func aim_at(target: Vector2) -> void:
		var l := _root.to_local(target) - PIVOT
		_barrel.rotation = clampf(l.angle(), -1.4, 1.1)

	func muzzle() -> Vector2:
		return _barrel.to_global(Vector2(54, 0))

	func breech() -> Vector2:
		return _barrel.to_global(Vector2(-36, -8))

	func kick() -> void:
		var t := _root.create_tween()
		t.tween_property(_root, "position", Vector2(-20.0 if not flip else 20.0, 0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(_root, "position", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	func _draw_carriage(n: Node2D) -> void:
		var wood := Color(0.4, 0.25, 0.13)
		var wood_dark := Color(0.22, 0.13, 0.07)
		var brass := Color(0.85, 0.62, 0.25)
		var ink := Color(0.04, 0.03, 0.03)
		# A stepped wooden wedge, low at the back
		var body := PackedVector2Array([Vector2(-40, 2), Vector2(-14, 2), Vector2(-14, -6), Vector2(12, -6), Vector2(26, 12), Vector2(-44, 12)])
		n.draw_colored_polygon(body, wood)
		n.draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.0, true)
		n.draw_line(Vector2(-42, 7), Vector2(22, 7), wood_dark, 1.5)
		for wx in [-28.0, 14.0]:
			var c := Vector2(wx, 16)
			n.draw_circle(c, 11.0, wood_dark)
			n.draw_arc(c, 11.0, 0, TAU, 22, ink, 2.0, true)
			for k in 4:
				var ang := k * PI / 4.0
				n.draw_line(c + Vector2(cos(ang), sin(ang)) * 3.0, c + Vector2(cos(ang), sin(ang)) * 10.0, wood, 2.0)
			n.draw_circle(c, 3.2, brass)

	func _draw_barrel() -> void:
		var iron := Color(0.15, 0.16, 0.18)
		var iron_hi := Color(0.46, 0.49, 0.53)
		var brass := Color(0.85, 0.62, 0.25)
		var ink := Color(0.04, 0.03, 0.03)
		var body := PackedVector2Array([Vector2(-34, -11), Vector2(46, -7), Vector2(46, 7), Vector2(-34, 11)])
		_barrel.draw_colored_polygon(body, iron)
		_barrel.draw_line(Vector2(-30, -7), Vector2(44, -4), iron_hi, 2.5)   # (its shine)
		_barrel.draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.0, true)
		_barrel.draw_circle(Vector2(-37, 0), 8.0, iron)   # (the breech knob)
		_barrel.draw_arc(Vector2(-37, 0), 8.0, 0, TAU, 18, ink, 2.0, true)
		for bx in [-22.0, 2.0, 30.0]:   # brass bands
			var h := lerpf(11.0, 7.0, (bx + 34.0) / 80.0) + 1.0
			_barrel.draw_rect(Rect2(bx, -h, 5, h * 2.0), brass)
			_barrel.draw_rect(Rect2(bx, -h, 5, h * 2.0), ink, false, 1.2)
		_barrel.draw_rect(Rect2(46, -9, 8, 18), brass)   # (the muzzle ring)
		_barrel.draw_rect(Rect2(46, -9, 8, 18), ink, false, 1.5)
		_barrel.draw_circle(Vector2(54, 0), 4.5, ink)


## A cannonball: a black iron ball with a dull highlight.
class Cannonball extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(2, 3), 11.0, Color(0, 0, 0, 0.35))   # (shadow)
		draw_circle(Vector2.ZERO, 10.0, Color(0.1, 0.1, 0.11))
		draw_circle(Vector2(-3, -3), 3.5, Color(0.45, 0.47, 0.5, 0.8))
		draw_arc(Vector2.ZERO, 10.0, 0, TAU, 20, Color(0.02, 0.02, 0.02), 1.5, true)


class Molotov extends Node2D:
	var spin := 0.0
	var tumble := 0.0
	var tumble_speed := 0.0
	var _bottle: Node2D
	var _smoke: CPUParticles2D
	var _flame: ColorRect
	var _glow: Sprite2D
	var _embers: CPUParticles2D

	func build(add_mat: Material, fire: Shader) -> void:
		_glow = Sprite2D.new()
		_glow.texture = ArenaLife._soft_dot()
		_glow.scale = Vector2.ONE * 1.8
		_glow.modulate = Color(1.0, 0.45, 0.1, 0.45)
		_glow.material = add_mat
		add_child(_glow)
		_bottle = Node2D.new()
		_bottle.draw.connect(_draw_bottle)
		add_child(_bottle)
		_flame = ColorRect.new()
		_flame.size = Vector2(46, 46)
		_flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = fire
		m.set_shader_parameter("shape", 1)   # (a ball of flame round the rag)
		m.set_shader_parameter("core", Color(1.0, 0.92, 0.6))
		m.set_shader_parameter("outer", Color(1.0, 0.4, 0.06))
		m.set_shader_parameter("seed", randf() * 30.0)
		m.set_shader_parameter("speed", 2.6)
		m.set_shader_parameter("gain", 0.9)
		_flame.material = m
		add_child(_flame)
		_embers = CPUParticles2D.new()
		_embers.local_coords = false
		_embers.amount = 36
		_embers.lifetime = 0.5
		_embers.texture = ArenaLife._soft_dot()
		_embers.direction = Vector2.UP
		_embers.spread = 50.0
		_embers.initial_velocity_min = 20.0
		_embers.initial_velocity_max = 80.0
		_embers.gravity = Vector2(0, -80)
		_embers.scale_amount_min = 0.08
		_embers.scale_amount_max = 0.18
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
		g.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
		_embers.color_ramp = g
		_embers.material = add_mat
		add_child(_embers)
		_smoke = CPUParticles2D.new()   # (a trail of smoke behind it)
		_smoke.local_coords = false
		_smoke.amount = 26
		_smoke.lifetime = 0.7
		_smoke.texture = ArenaLife._soft_dot()
		_smoke.direction = Vector2.UP
		_smoke.spread = 30.0
		_smoke.initial_velocity_min = 6.0
		_smoke.initial_velocity_max = 24.0
		_smoke.gravity = Vector2(0, -40)
		_smoke.scale_amount_min = 0.35
		_smoke.scale_amount_max = 0.7
		var sg := Gradient.new()
		sg.set_color(0, Color(0.16, 0.12, 0.1, 0.45))
		sg.set_color(1, Color(0.1, 0.09, 0.09, 0.0))
		_smoke.color_ramp = sg
		_smoke.show_behind_parent = true
		add_child(_smoke)
		move_child(_smoke, 0)
		_place_flame()

	func _draw_bottle() -> void:
		var body := PackedVector2Array([Vector2(-12, 22), Vector2(12, 22), Vector2(12, -2), Vector2(5, -10),
			Vector2(5, -22), Vector2(-5, -22), Vector2(-5, -10), Vector2(-12, -2)])
		_bottle.draw_colored_polygon(body, Color(0.42, 0.18, 0.04, 0.96))   # (the glass, in shadow)
		# Round: strips across it, lit from the upper left (brightest a third of the way in, dark at the edges)
		for i in 12:
			var x0 := -12.0 + i * 2.0
			var u := (x0 + 13.0) / 24.0
			var lit := clampf(1.0 - absf(u - 0.33) * 2.1, 0.0, 1.0)
			var ax := absf(x0 + 1.0)
			var top := -10.0 if ax <= 5.0 else -2.0 - 8.0 * (12.0 - ax) / 7.0   # (along the shoulders)
			if ax <= 5.0:
				top = -22.0   # (the neck)
			_bottle.draw_rect(Rect2(x0, top, 2.0, 22.0 - top), Color(1.0, 0.62, 0.22, 0.6 * lit))
		_bottle.draw_rect(Rect2(-11.5, 8, 23, 13.5), Color(0.75, 0.3, 0.04, 0.45))   # (the fuel inside)
		_bottle.draw_line(Vector2(-11.5, 8), Vector2(11.5, 8), Color(1.0, 0.8, 0.4, 0.55), 1.5)   # (its surface)
		_bottle.draw_rect(Rect2(-10, -1, 20, 7), Color(0.78, 0.16, 0.06))   # (its label)
		_bottle.draw_rect(Rect2(-10, -1, 6, 7), Color(1.0, 0.5, 0.35, 0.35))
		var edge := body.duplicate()
		edge.append(body[0])
		_bottle.draw_polyline(edge, Color(0.2, 0.08, 0.02), 2.0, true)
		_bottle.draw_line(Vector2(-6.5, 19), Vector2(-6.5, 0), Color(1.0, 0.95, 0.8, 0.85), 2.0)   # (light on the glass)
		_bottle.draw_circle(Vector2(-7, -4), 2.2, Color(1.0, 1.0, 0.95, 0.8))
		# Tipped toward the view, its round base shows as an ellipse at the bottom
		var c := cos(tumble)
		if c > 0.0 and c < 0.97:
			var h := 12.0 * sqrt(1.0 - c * c) / maxf(_bottle.scale.y, 0.3)
			var cap := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				cap.append(Vector2(12.0 * cos(a), 22.0 + h * 0.5 * sin(a)))
			_bottle.draw_colored_polygon(cap, Color(0.55, 0.24, 0.05, 0.95))
			cap.append(cap[0])
			_bottle.draw_polyline(cap, Color(0.2, 0.08, 0.02), 1.5, true)
		_bottle.draw_colored_polygon(PackedVector2Array([Vector2(-5, -22), Vector2(5, -22), Vector2(7, -30), Vector2(-3, -33)]), Color(0.85, 0.78, 0.62))   # (the rag)

	## The flame sits on the rag wherever the spinning bottle has it.
	func _place_flame() -> void:
		var tip := Vector2(0, -30 * _bottle.scale.y).rotated(_bottle.rotation)
		_flame.position = tip - _flame.size / 2.0 + Vector2(0, -6)
		_embers.position = tip
		if _smoke:
			_smoke.position = tip

	func _process(delta: float) -> void:
		_bottle.rotation += spin * delta
		tumble += tumble_speed * delta
		var c := cos(tumble)   # (end over end: shorter as it turns toward or away from the view)
		_bottle.scale.y = signf(c) * maxf(absf(c), 0.3) if c != 0.0 else 0.3
		_bottle.queue_redraw()
		_place_flame()

	## It breaks: the bottle and its flame are gone at once; its embers die away behind it.
	func smash() -> void:
		_bottle.visible = false
		_flame.visible = false
		_glow.visible = false
		_embers.emitting = false
		_smoke.emitting = false
		get_tree().create_timer(0.8).timeout.connect(queue_free)


## Arsonists' summon: a wall of fire sweeps across the slot and roars up, and the character walks out
## through it, a dark shape at first and lit as it steps clear, while the wall dies down.
func _firewall_in(v: CardView, target: Vector2, heavy: bool) -> void:
	var ember := Color(1.0, 0.42, 0.08)
	var hot := Color(1.0, 0.88, 0.5)
	var k := 1.25 if heavy else 1.0
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	v.modulate.a = 0.0
	var foot := target + Vector2(0, CardView.SIZE.y * 0.42 * v.board_scale)
	var width := 330.0 * k
	var wall := _flame_row(foot, width, 290.0 * k, 7, cards_layer, v.z_index + 1, hot, ember, 0.75)
	Sfx.play("fire_roar", 1.0, -3.0)
	Sfx.play("whoosh", 0.7, -4.0)
	shake(6.0 if heavy else 4.0)
	# It sweeps in from the left: each flame shoots up from the ground in turn, embers kicked up at its foot
	_row_life(1.0, wall)
	for i in wall.size():
		var f: ColorRect = wall[i]
		f.scale = Vector2(1.0, 0.0)
		f.create_tween().tween_property(f, "scale:y", 1.0, 0.24).set_delay(i * 0.045).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var at := Vector2(f.position.x + f.size.x / 2.0, foot.y)
		get_tree().create_timer(i * 0.045).timeout.connect(func(): _burst(at, ember, 5, 240.0, 0.7, -140.0))
	await _wait(0.045 * wall.size() + 0.2)
	# The character walks out through it: a shape in the fire, lit as it steps clear
	v.position = target + Vector2(0, -34.0 * k)
	v.rotation = v.home_rot
	v.scale = Vector2.ONE * 0.86 * v.board_scale
	v.modulate = Color(0.08, 0.04, 0.02, 0.0)
	var walk := create_tween().set_parallel()
	walk.tween_property(v, "modulate:a", 1.0, 0.18)
	walk.tween_property(v, "position", target + Vector2(0, 10), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	walk.tween_property(v, "scale", Vector2.ONE * 1.05 * v.board_scale, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	walk.tween_property(v, "modulate", Color.WHITE, 0.4).set_delay(0.18)
	walk.tween_callback(func():   # (through it: the fire's behind now)
		for f in wall:
			f.z_index = v.z_index - 1).set_delay(0.3)
	await walk.finished
	var die := create_tween()
	die.tween_method(_row_life.bind(wall), 1.0, 0.0, 0.5)
	die.tween_callback(_row_free.bind(wall))
	var land := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(v, "position", target, 0.18)
	land.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.22)
	_burst(target, ember, 18 if heavy else 12, 300.0, 0.9, -160.0)
	_ring(target, ember, 1.5 if heavy else 1.15)
	await _impact(target, heavy)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## Arsonists KO: the card catches fire, chars, and burns away from the top down, cinders and ash
## drifting up off it, then a last curl of smoke.
func _ash_ko(v: CardView) -> void:
	var ember := Color(1.0, 0.42, 0.08)
	var hot := Color(1.0, 0.88, 0.5)
	Sfx.play("ko", 0.95)
	Sfx.play("fire_roar", 1.25, -5.0)
	shake(10)
	_post_pulse("aberration", 6.0, 0.35)
	_stamp(v.position, "K.O.", Color(1.0, 0.5, 0.15))
	var size := CardView.SIZE * v.scale
	var fire := _flame_row(v.position + Vector2(0, size.y * 0.45), size.x * 1.1, size.y * 1.15, 4, v.get_parent(), v.z_index + 1, hot, ember, 0.55)
	var roar := create_tween()
	roar.tween_method(_row_life.bind(fire), 0.0, 1.0, 0.15)
	roar.tween_interval(0.55)
	roar.tween_method(_row_life.bind(fire), 1.0, 0.0, 0.5)
	roar.tween_callback(_row_free.bind(fire))
	_cinders(v.position, size)
	v.reveal_color = ember
	var burn := create_tween().set_parallel()
	burn.tween_property(v, "modulate", Color(0.6, 0.42, 0.34), 0.35)   # (scorched)
	burn.tween_property(v, "reveal", 0.0, 0.95).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await burn.finished
	_smoke_puff(v.position + Vector2(0, -size.y * 0.3), size.x * 1.6, Color(0.14, 0.12, 0.12))
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.2)


## Militia KO: an explosion under the card throws it up, spinning and blackened, debris and smoke
## flying, and leaves a scorch mark on the ground, smoking.
func _blast_ko(v: CardView) -> void:
	var at := v.position
	var size := CardView.SIZE * v.scale
	Sfx.play("ko", 0.9)
	Sfx.play("boom", 0.75)
	shake(20)
	_shockwave(at, 0.8)
	_post_pulse("aberration", 10.0, 0.35)
	_stamp(at, "K.O.", Color(0.75, 1.0, 0.35))
	_flame_burst(at + Vector2(0, size.y * 0.15), size.x * 2.2, Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.08), 0.5)
	_shards(at, Vector2.UP, 18, [Color(0.45, 0.42, 0.36, 1.0), Color(0.3, 0.28, 0.24, 0.9), Color(0.2, 0.18, 0.16, 0.0)])   # (debris)
	_sparks(at, Vector2.UP, Color(1.0, 0.7, 0.3), 26, 150.0)
	_smoke_puff(at, size.x * 2.4, Color(0.16, 0.15, 0.13))
	# The scorch mark, left smoking
	var mark := Sprite2D.new()
	mark.texture = ArenaLife._soft_dot()
	mark.position = at + Vector2(0, size.y * 0.2)
	mark.scale = Vector2(2.6, 1.3) * size.x / 64.0
	mark.modulate = Color(0.0, 0.0, 0.0, 0.75)
	mark.z_index = 5
	cards_layer.add_child(mark)
	var fade := mark.create_tween()
	fade.tween_interval(0.9)
	fade.tween_property(mark, "modulate:a", 0.0, 1.0)
	fade.tween_callback(mark.queue_free)
	get_tree().create_timer(0.5).timeout.connect(func(): _smoke_puff(mark.position + Vector2(0, -30), size.x * 1.4, Color(0.2, 0.19, 0.17)))
	# The card thrown up, spinning, blackened, and gone
	var side := 1.0 if randf() < 0.5 else -1.0
	var t := create_tween().set_parallel()
	t.tween_property(v, "modulate", Color(0.3, 0.28, 0.24, 1.0), 0.15)
	t.tween_property(v, "position", at + Vector2(side * 70.0, -140.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "rotation", v.rotation + side * 2.6, 0.6)
	t.tween_property(v, "scale", v.scale * 0.6, 0.6)
	t.tween_property(v, "modulate:a", 0.0, 0.3).set_delay(0.3)
	await t.finished
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.2)


## Neutral summon: a streetlamp flickers on over the spot, the card drops into its light and lands in
## a puff of alley dust, and the lamp dims again.
func _spotlight_in(v: CardView, target: Vector2, heavy: bool) -> void:
	var warm := Color(1.0, 0.86, 0.55)
	var k := 1.25 if heavy else 1.0
	if heavy:
		_cam_focus(target, 1.07, 0.3)
	v.modulate.a = 0.0
	var size := CardView.SIZE * v.board_scale
	var top := target + Vector2(0, -size.y * 1.3 * k)
	var foot_y := target.y + size.y * 0.55
	var half_top := 24.0 * k
	var half_foot := size.x * 0.85 * k
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var cone := Polygon2D.new()
	cone.polygon = PackedVector2Array([top + Vector2(-half_top, 0), top + Vector2(half_top, 0),
		Vector2(target.x + half_foot, foot_y), Vector2(target.x - half_foot, foot_y)])
	cone.vertex_colors = PackedColorArray([Color(warm, 0.5), Color(warm, 0.5), Color(warm, 0.0), Color(warm, 0.0)])
	cone.material = add
	cone.z_index = v.z_index + 1
	cone.modulate.a = 0.0
	cards_layer.add_child(cone)
	var pool := Sprite2D.new()   # (the pool of light on the ground)
	pool.texture = ArenaLife._soft_dot()
	pool.position = Vector2(target.x, foot_y - size.y * 0.12)
	pool.scale = Vector2(half_foot * 2.0, half_foot * 0.7) / 64.0
	pool.modulate = Color(warm, 0.0)
	pool.material = add
	pool.z_index = 5
	cards_layer.add_child(pool)
	# It stutters on: a buzz, two flickers, then steady
	Sfx.play("neon_buzz", 1.0, -6.0)
	var on := create_tween()
	for a in [0.9, 0.1, 0.7, 0.0, 1.0]:
		on.tween_property(cone, "modulate:a", a, 0.05)
		on.parallel().tween_property(pool, "modulate:a", a * 0.55, 0.05)
		on.tween_interval(0.04)
	await on.finished
	# The card drops into the light from above
	v.position = target + Vector2(0, -size.y * 0.9)
	v.rotation = v.home_rot + randf_range(-0.12, 0.12)
	v.scale = Vector2.ONE * 1.12 * v.board_scale
	Sfx.play("whoosh", 1.2, -4.0)
	var drop := create_tween().set_parallel()
	drop.tween_property(v, "modulate:a", 1.0, 0.08)
	drop.tween_property(v, "position", target, 0.2 if heavy else 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(v, "rotation", v.home_rot, 0.2)
	drop.tween_property(v, "scale", Vector2.ONE * v.board_scale, 0.2)
	await drop.finished
	cone.z_index = v.z_index - 1
	Sfx.play("slam", 1.0 if heavy else 1.15)
	v.kick(Vector2(0, 1), 14.0)
	var dust := Color(0.42, 0.4, 0.37)
	_smoke_puff(Vector2(target.x - size.x * 0.45, foot_y - 20.0), size.x * 1.1 * k, dust)
	_smoke_puff(Vector2(target.x + size.x * 0.45, foot_y - 20.0), size.x * 1.1 * k, dust)
	_burst(Vector2(target.x, foot_y - 10.0), Color(0.62, 0.58, 0.5), 14 if heavy else 9, 260.0, 0.5, 600.0)   # (grit)
	_ring(target, warm, 1.4 if heavy else 1.1)
	await _impact(target, heavy)
	var off := create_tween().set_parallel()
	off.tween_property(cone, "modulate:a", 0.0, 0.45)
	off.tween_property(pool, "modulate:a", 0.0, 0.45)
	off.chain().tween_callback(cone.queue_free)
	off.chain().tween_callback(pool.queue_free)
	if heavy:
		_cam_reset(0.45)
		_dim(0.0, 0.35)


## Neutral attack: a street fight. The card coils back and charges in for a haymaker behind a blur of
## speed lines; on contact a comic-book word bursts out (POW! WHAM! CRACK!), action lines all round,
## and the target reels back.
func _brawl_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	Sfx.play("riser", 1.1 if big else 1.25, -6.0)
	_cam_focus(a.home.lerp(tpos, 0.5), 1.08 if big else 1.04, 0.3)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 70.0, 0.26)
	t.tween_property(a, "rotation", a.home_rot - 0.22, 0.26)
	t.tween_property(a, "scale", Vector2.ONE * 1.28 * a.board_scale, 0.26)
	await t.finished
	a.kick(dir.orthogonal(), 6.0)
	await _wait(0.06)
	_clear_attack_line()
	# The charge
	Sfx.play("whoosh", 1.15)
	_speed_lines(a.position, dir, 10 if big else 7)
	t = create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(a, "position", a.home.lerp(tpos, 0.82), 0.1)
	t.tween_property(a, "rotation", a.home_rot + 0.16, 0.1)
	t.tween_property(a, "scale", Vector2.ONE * 1.1 * a.board_scale, 0.1)
	await t.finished
	# Contact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("slam", 0.9 if big else 1.05)
	Sfx.play("hit", 0.85 if direct else 1.0)
	if big:
		Sfx.play("boom", 1.1, -3.0)
	shake(24.0 if big else 13.0)
	_shockwave(tpos, 0.9 if big else 0.5)
	_post_pulse("aberration", 12.0 if big else 5.0, 0.35)
	var word: String = (["KA-POW!", "WHAM!", "CRUNCH!"] if big else ["POW!", "BAM!", "WHACK!", "CRACK!", "THWACK!"]).pick_random()
	_comic_burst(tpos - dir * 20.0, word, big)
	_action_lines(tpos, 14 if big else 10)
	_burst(tpos, Color(1, 0.95, 0.75), 18 if big else 12, 480, 0.4)
	a.kick(-dir, 16.0)
	if d:
		d.flash()
		d.kick(dir, 36.0 if big else 26.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (46.0 if big else 26.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.parallel().tween_property(d, "rotation", d.home_rot + signf(dir.x + 0.01) * 0.18, 0.07)
		push.tween_property(d, "position", d.home, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		push.parallel().tween_property(d, "rotation", d.home_rot, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)
	a.create_tween().tween_property(a, "rotation", a.home_rot, 0.22).set_trans(Tween.TRANS_SINE)


## Neutral KO: knocked out cold. K.O.! bursts out, the card is sent spinning back toward its own side
## and drops, cartoon stars circle where it stood, and a puff of alley dust.
func _knockout_ko(v: CardView) -> void:
	var at := v.position
	var size := CardView.SIZE * v.scale
	Sfx.play("ko", 1.0)
	Sfx.play("slam", 0.8)
	shake(14)
	_post_pulse("aberration", 7.0, 0.35)
	_comic_burst(at + Vector2(0, -size.y * 0.2), "K.O.!", true)
	_dizzy_stars(at + Vector2(0, -size.y * 0.42), size.x * 0.45)
	var away := 1.0 if at.y > DIVIDER_Y else -1.0   # (back toward its owner's side)
	var side := 1.0 if randf() < 0.5 else -1.0
	var t := create_tween().set_parallel()
	t.tween_property(v, "position", at + Vector2(side * 60.0, away * 110.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "rotation", v.rotation + side * 3.4, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "scale", v.scale * 0.72, 0.5)
	t.tween_property(v, "modulate", Color(0.45, 0.43, 0.42, 1.0), 0.3)
	t.tween_property(v, "modulate:a", 0.0, 0.3).set_delay(0.45)
	await _wait(0.42)
	_smoke_puff(at + Vector2(side * 60.0, away * 110.0 + size.y * 0.2), size.x * 1.5, Color(0.42, 0.4, 0.37))
	await t.finished
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.25)


## A comic-book word in a jagged yellow starburst with a black outline: it pops in big, wobbles, and fades.
func _comic_burst(at: Vector2, word: String, big: bool) -> void:
	var b := Node2D.new()
	b.position = at
	b.rotation = randf_range(-0.22, 0.22)
	b.z_index = 82
	fx.add_child(b)
	var r := 92.0 if big else 72.0
	var pts := PackedVector2Array()
	for i in 24:   # (spikes of different lengths)
		var ang := TAU * i / 24.0
		pts.append(Vector2.from_angle(ang) * r * (1.0 if i % 2 == 0 else randf_range(0.55, 0.7)) * Vector2(1.45, 1.0))
	var star := Polygon2D.new()
	star.polygon = pts
	star.color = Color(1.0, 0.86, 0.15)
	b.add_child(star)
	var inner := Polygon2D.new()
	var small := PackedVector2Array()
	for p in pts:
		small.append(p * 0.72)
	inner.polygon = small
	inner.color = Color(1.0, 0.97, 0.75)
	b.add_child(inner)
	var edge := Line2D.new()
	edge.points = pts
	edge.closed = true
	edge.width = 6.0
	edge.default_color = Color(0.05, 0.04, 0.04)
	b.add_child(edge)
	var l := _label(48 if big else 38, Color(0.92, 0.12, 0.1), true)
	l.label_settings.outline_size = 10
	l.label_settings.outline_color = Color(0.05, 0.04, 0.04)
	l.text = word
	l.size = Vector2(320, 80)
	l.position = -l.size / 2.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	b.scale = Vector2.ONE * 0.2
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE * 1.12, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE, 0.12)
	t.parallel().tween_property(b, "rotation", b.rotation + randf_range(-0.08, 0.08), 0.12)
	t.tween_interval(0.35)
	t.tween_property(b, "modulate:a", 0.0, 0.25)
	t.parallel().tween_property(b, "scale", Vector2.ONE * 1.15, 0.25)
	t.tween_callback(b.queue_free)


## Comic action lines: short black-edged white strokes flying out from a hit.
func _action_lines(at: Vector2, n: int) -> void:
	for i in n:
		var ang := TAU * i / n + randf_range(-0.15, 0.15)
		var dirv := Vector2.from_angle(ang)
		var line := Line2D.new()
		line.width = randf_range(4.0, 7.0)
		line.default_color = Color(1, 1, 1, 0.95)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		var from := at + dirv * randf_range(60.0, 80.0)
		line.points = PackedVector2Array([from, from + dirv * 10.0])
		line.z_index = 81
		fx.add_child(line)
		var len := randf_range(40.0, 70.0)
		var t := line.create_tween().set_parallel()
		t.tween_method(func(k: float): line.points = PackedVector2Array([from + dirv * len * k, from + dirv * (10.0 + len * 1.6 * k)]), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(line, "modulate:a", 0.0, 0.2).set_delay(0.12)
		t.chain().tween_callback(line.queue_free)


## Speed lines streaking back from a charging card.
func _speed_lines(from: Vector2, dir: Vector2, n: int) -> void:
	var side_v := dir.orthogonal()
	for i in n:
		var line := Line2D.new()
		line.width = randf_range(2.0, 4.0)
		line.default_color = Color(1, 1, 1, 0.7)
		var off := side_v * randf_range(-70.0, 70.0)
		var a := from + off - dir * randf_range(20.0, 60.0)
		line.points = PackedVector2Array([a, a - dir * randf_range(90.0, 160.0)])
		line.z_index = 71
		fx.add_child(line)
		var t := line.create_tween().set_parallel()
		t.tween_property(line, "position", dir * 120.0, 0.18)
		t.tween_property(line, "modulate:a", 0.0, 0.18).set_delay(0.04)
		t.chain().tween_callback(line.queue_free)


## Little cartoon stars circling over a knocked-out card.
func _dizzy_stars(center: Vector2, radius: float) -> void:
	var n := 4
	var stars: Array = []
	for i in n:
		var l := _label(34, Color(1.0, 0.9, 0.3), true)
		l.text = "★"
		l.size = Vector2(40, 40)
		l.pivot_offset = l.size / 2.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.z_index = 83
		fx.add_child(l)
		stars.append(l)
	var t := create_tween()
	t.tween_method(func(k: float):
		for i in stars.size():
			var s: Label = stars[i]
			var ang := k * TAU * 1.6 + TAU * i / stars.size()
			s.position = center + Vector2(cos(ang) * radius, sin(ang) * radius * 0.35) - s.size / 2.0
			s.rotation = k * 6.0
			s.modulate.a = minf(1.0, k * 6.0) * (1.0 - smoothstep(0.7, 1.0, k)), 0.0, 1.0, 1.1)
	t.tween_callback(func():
		for s in stars:
			s.queue_free())


## Wildcard KO: the card turns away and bursts into a hand of playing cards that fan out, then
## scatter, spinning, with a spill of chips.
func _fold_ko(v: CardView) -> void:
	var gold := Color(1.0, 0.82, 0.35)
	var at := v.position
	Sfx.play("ko", 1.1)
	Sfx.play("shuffle", 1.3, -2.0)
	shake(12)
	_post_pulse("aberration", 6.0, 0.35)
	_stamp(at, "K.O.", gold)
	var turn := create_tween().set_parallel()
	turn.tween_property(v, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	turn.tween_property(v, "modulate:a", 0.0, 0.16).set_delay(0.06)
	for col in [Color(0.85, 0.1, 0.12), Color(0.1, 0.08, 0.1), gold]:   # (chips)
		_burst(at, col, 7, 360.0, 0.6, 600.0)
	var n := 7
	for i in n:
		var c := _playing_card(i)
		c.position = at - c.pivot_offset
		c.rotation = v.home_rot
		var fan := (i - (n - 1) / 2.0) * 0.28
		var out := at + Vector2.from_angle(-PI / 2 + fan * 1.6) * randf_range(170.0, 240.0) + Vector2(0, 60) - c.pivot_offset
		var t := c.create_tween()
		t.tween_property(c, "rotation", fan, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # (a hand, fanned)
		t.tween_interval(0.12)
		t.tween_property(c, "position", out, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)   # (then scattered)
		t.parallel().tween_property(c, "rotation", fan + randf_range(-4.0, 4.0), 0.6)
		t.parallel().tween_property(c, "modulate:a", 0.0, 0.3).set_delay(0.35)
		t.tween_callback(c.queue_free)
	_ring(at, gold, 1.3)
	await _wait(0.7)
	if v == _hovered:
		_hovered = null
	v.queue_free()


## A small playing card (Wildcard's KO): white with a gold edge, a suit in the middle.
func _playing_card(i: int) -> Control:
	var c := Panel.new()
	c.size = Vector2(56, 80)
	c.pivot_offset = Vector2(28, 70)   # (it fans from near its foot, like a hand)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.9)
	sb.border_color = Color(1.0, 0.82, 0.35)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	c.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = ["♠", "♥", "♣", "♦"][i % 4]
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color(0.85, 0.1, 0.12) if i % 2 == 1 else Color(0.1, 0.08, 0.1))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = c.size
	c.add_child(l)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 450
	fx.add_child(c)
	return c


## Underworld KO: the ground cracks open under the card in violet light and it's pulled down into the
## rift, darkening as it sinks; souls escape as the cracks close.
func _rift_ko(v: CardView) -> void:
	var violet := Color(0.72, 0.32, 1.0)
	var at := v.position
	var size := CardView.SIZE * v.scale
	Sfx.play("ko", 0.8)
	Sfx.play("slam", 0.55, -3.0)
	Sfx.play("riser", 0.5, -8.0)
	shake(12)
	_post_pulse("aberration", 8.0, 0.35)
	_stamp(at, "K.O.", violet.lightened(0.3))
	var rift := _fx_rect(FX_RIFT, at + Vector2(0, size.y * 0.3), Vector2(size.x * 2.0, size.y * 1.0), {"color": violet, "seed": randf() * 50.0, "gain": 0.85}, cards_layer, v.z_index - 1)
	var rm: ShaderMaterial = rift.material
	create_tween().tween_method(func(x: float): rm.set_shader_parameter("open", x), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_burst(at + Vector2(0, size.y * 0.3), violet, 14, 240.0, 0.6, -80.0)
	await _wait(0.15)
	# Pulled down: it lurches, then sinks into the light, shrinking and darkening
	var t := create_tween()
	t.tween_property(v, "position", at + Vector2(0, -12), 0.08)
	t.set_parallel()
	t.chain().tween_property(v, "position", at + Vector2(0, size.y * 0.32), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(v, "scale", Vector2(v.scale.x * 0.55, v.scale.y * 0.3), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(v, "modulate", Color(0.45, 0.25, 0.7, 0.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	_souls(at + Vector2(0, size.y * 0.2), violet, 14)
	_flame_burst(at + Vector2(0, size.y * 0.3), size.x * 1.2, Color(1.0, 0.82, 1.0), violet, 0.4)
	var close := create_tween()
	close.tween_method(func(x: float): rm.set_shader_parameter("heat", x), 1.0, 0.0, 0.7)
	close.tween_callback(rift.queue_free)
	if v == _hovered:
		_hovered = null
	v.queue_free()
	await _wait(0.2)


## Cinders and ash coming off a burning card (size: the card's), drifting up and swaying.
func _cinders(at: Vector2, size: Vector2) -> void:
	for ash in [false, true]:
		var p := CPUParticles2D.new()
		p.position = at
		p.amount = 40 if ash else 60
		p.lifetime = 1.6
		p.texture = ArenaLife._leaf() if ash else ArenaLife._soft_dot()
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = size / 2.0
		p.direction = Vector2.UP
		p.spread = 30.0
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 110.0
		p.gravity = Vector2(0, -50)
		p.tangential_accel_min = -40.0
		p.tangential_accel_max = 40.0
		p.angular_velocity_min = -180.0
		p.angular_velocity_max = 180.0
		p.scale_amount_min = 0.25 if ash else 0.08
		p.scale_amount_max = 0.45 if ash else 0.2
		var g := Gradient.new()
		if ash:   # (grey flakes, normal blend: they're darker than what's behind)
			g.set_color(0, Color(0.32, 0.28, 0.26, 0.9))
			g.set_color(1, Color(0.2, 0.18, 0.17, 0.0))
		else:
			g.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
			g.add_point(0.5, Color(1.0, 0.42, 0.08, 0.8))
			g.set_color(g.get_point_count() - 1, Color(0.5, 0.1, 0.02, 0.0))
			p.material = _add_mat
		p.color_ramp = g
		p.z_index = 450
		fx.add_child(p)
		p.emitting = true
		get_tree().create_timer(0.9).timeout.connect(func(): p.emitting = false)
		get_tree().create_timer(2.8).timeout.connect(p.queue_free)


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
	tok.z_index = 600
	cards_layer.add_child(tok)
	if ev.get("again", false):   # LOADED DICE: the lost one is tried again
		_float_text(at + Vector2(0, -230), "LOADED DICE!", GOLD, 34)
		_burst(at + Vector2(0, -150), GOLD, 16, 240, 0.5, 0.0)
		Sfx.play("promote", 1.4, -8.0)
	var rest := at + Vector2(0, -150)   # where it lands and shows the result
	tok.ground = rest.y + 44.0
	Sfx.play("coin_flip" if coin else "dice_roll")
	if coin:
		await _toss_coin(tok, at, rest, value == 1)
	else:
		await _roll_die(tok, at, rest, value)
	tok.edge = Color("6ef08a") if won else RED
	Sfx.play("coin_land" if coin else "dice_land", 1.0, -2.0)
	tok.land()
	_burst(tok.position, tok.edge, 22, 300, 0.6, 0.0)
	_ring(tok.position, tok.edge.lightened(0.3), 1.2)
	shake(5.0)
	var need := int(ev.get("need", 1))
	var text := ("HEADS!" if value == 1 else "TAILS") if coin else ("ROLLED %d" % value + ((" · SUCCESS" if won else " · FAILED") if need > 1 else ""))
	if ev.get("double", false):   # DOUBLE OR NOTHING: the stakes, and a bigger win
		text = "HEADS · DOUBLE!" if won else "TAILS · NOTHING"
		if won:
			_burst(tok.position, GOLD, 34, 420, 0.8, 0.0)
			_ring(tok.position, GOLD, 1.6)
			Sfx.play("legendary", 1.5, -10.0)
	_float_text(tok.position + Vector2(0, -110), text, tok.edge, 30)
	# A leader that Awakens on luck counts its wins: LUCK 3 / 5 over it
	if won:
		_luck_wins[side] = int(_luck_wins.get(side, 0)) + 1
		var lv = leaders.get(side)
		var goal := int(lv.card.get("awakenCondition", {}).get("luck", 0)) if lv is CardView and is_instance_valid(lv) else 0
		if goal > 0:
			var have := maxi(int(_luck_wins[side]), int(duel.sides.get(side, {}).get("luck_won", 0)))
			_float_text(lv.position + Vector2(0, -110 if side == "player" else 110), "READY TO AWAKEN" if have >= goal else "LUCK %d / %d" % [mini(have, goal), goal], GOLD, 26)
			_burst(lv.position, GOLD, 12, 200, 0.5, 0.0)
	await _wait(0.7)
	var out := create_tween()
	out.tween_property(tok, "modulate:a", 0.0, 0.25)
	out.tween_callback(tok.queue_free)


## A coin flipped off the card: it spins end over end up into the air, glinting, falls back and
## settles showing heads or tails with a little wobble.
func _toss_coin(tok: LuckToken, from: Vector2, rest: Vector2, heads: bool) -> void:
	var turns := 6 + randi() % 2   # whole half-turns, so it ends on the right face
	var flips := float(turns * 2 + (0 if heads else 1)) * PI
	var tilt := randf_range(-0.35, 0.35)
	var peak := rest + Vector2(randf_range(-30, 30), -230)
	var dur := 0.95
	var t := create_tween()
	t.tween_method(func(k: float):
		# up and back down (a parabola), turning fast then slowing as it comes down
		var up := 4.0 * k * (1.0 - k)
		tok.position = from.lerp(rest, k) + (peak - rest.lerp(from, 0.5)) * up * 0.9
		tok.scale = Vector2.ONE * lerpf(0.45, 1.0, minf(1.0, k * 2.5)) * (1.0 + up * 0.35)
		var spin := 1.0 - pow(1.0 - k, 2.2)
		tok.set_rot(Basis(Vector3.RIGHT, flips * spin) * Basis(Vector3.UP, tilt * (1.0 - k)))
		tok.height = up, 0.0, 1.0, dur)
	await t.finished
	# settles: rocks on its edge for a moment
	var w := create_tween()
	w.tween_method(func(k: float):
		var a := sin(k * TAU * 2.5) * 0.35 * (1.0 - k)
		tok.set_rot(Basis(Vector3.RIGHT, (0.0 if heads else PI) + a)), 0.0, 1.0, 0.35)
	await w.finished


## A die thrown from the card: it tumbles through the air, bounces twice and comes to rest showing the roll.
func _roll_die(tok: LuckToken, from: Vector2, rest: Vector2, value: int) -> void:
	var face_rot: Basis = {
		1: Basis.IDENTITY, 6: Basis(Vector3.RIGHT, PI), 2: Basis(Vector3.UP, -PI / 2), 5: Basis(Vector3.UP, PI / 2),
		3: Basis(Vector3.RIGHT, PI / 2), 4: Basis(Vector3.RIGHT, -PI / 2)}[clampi(value, 1, 6)]
	var final := Basis(Vector3.BACK, randf_range(-0.25, 0.25)) * Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.UP, -0.22) * face_rot   # (a little turned, so it reads as a cube)
	var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.4, 0.4)).normalized()
	var spins := randf_range(5.0, 7.0) * TAU
	var start := from + Vector2(randf_range(-40, 40), 30)
	var dur := 1.05
	var t := create_tween()
	t.tween_method(func(k: float):
		# an arc into the air, then two bounces getting smaller
		var hgt := 0.0
		if k < 0.55:
			var u := k / 0.55
			hgt = 4.0 * u * (1.0 - u) * 1.0
		elif k < 0.82:
			var u2 := (k - 0.55) / 0.27
			hgt = 4.0 * u2 * (1.0 - u2) * 0.3
		else:
			var u3 := (k - 0.82) / 0.18
			hgt = 4.0 * u3 * (1.0 - u3) * 0.08
		tok.position = start.lerp(rest, 1.0 - pow(1.0 - k, 1.6)) + Vector2(0, -200.0 * hgt)
		tok.scale = Vector2.ONE * lerpf(0.5, 1.0, minf(1.0, k * 2.0)) * (1.0 + hgt * 0.3)
		var left := pow(1.0 - k, 2.4)
		tok.set_rot(final * Basis(axis, spins * left))
		tok.height = hgt
		if k > 0.55 and not tok.get_meta("b1", false):
			tok.set_meta("b1", true)
			Sfx.play("dice_land", 1.2, -10.0)
			_burst(tok.position + Vector2(0, 40), Color(1, 1, 1, 0.6), 8, 160, 0.3, 300.0)
		elif k > 0.82 and not tok.get_meta("b2", false):
			tok.set_meta("b2", true)
			Sfx.play("dice_land", 1.35, -14.0), 0.0, 1.0, dur)
	await t.finished
	tok.set_rot(final)
	tok.height = 0.0


## A coin or a die in 3D for luck effects (shaders/luck3d.gdshader), with its shadow on the board
## (height: 0 on the ground, 1 at the top of its throw; ground: where the shadow lies).
class LuckToken extends Node2D:
	const SHADER := preload("res://shaders/luck3d.gdshader")
	const SIZE := 240.0
	var kind := "coin"
	var height := 0.0
	var ground := 0.0
	var edge := Color(0, 0, 0, 0)   # once it lands: green if the effect happens, red if not
	var _body: ColorRect
	var _shadow: Sprite2D
	var _mat := ShaderMaterial.new()
	var _flash := 0.0

	func _ready() -> void:
		_shadow = Sprite2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0))
		var tex := GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.gradient = g
		_shadow.texture = tex
		_shadow.top_level = true
		_shadow.z_index = 599
		add_child(_shadow)
		_body = ColorRect.new()
		_body.size = Vector2.ONE * SIZE
		_body.position = -_body.size / 2.0
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat.shader = SHADER
		_mat.set_shader_parameter("kind", 0 if kind == "coin" else 1)
		_body.material = _mat
		add_child(_body)

	func set_rot(b: Basis) -> void:
		_mat.set_shader_parameter("rot", b)

	## It lands: a white glint, then its rim glows the result colour.
	func land() -> void:
		_flash = 0.45
		create_tween().tween_property(self, "_flash", 0.0, 0.35)
		_mat.set_shader_parameter("glow", Color(edge, 0.0))
		create_tween().tween_method(func(a: float): _mat.set_shader_parameter("glow", Color(edge, a)), 0.0, 1.0, 0.3)

	func _process(_delta: float) -> void:
		_mat.set_shader_parameter("flash", _flash)
		if _shadow:
			var y := ground if ground != 0.0 else global_position.y + 44.0
			_shadow.global_position = Vector2(global_position.x + 10.0 + height * 30.0, y)
			_shadow.scale = Vector2(1.6, 0.55) * (1.0 - height * 0.45) * scale.x * (0.9 if kind == "coin" else 1.1)
			_shadow.modulate.a = (1.0 - height * 0.6) * modulate.a


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
	const VORTEX := preload("res://shaders/fx_vortex.gdshader")
	var glow := Color.PURPLE
	var radius := 0.0
	var spin := 3.0
	var _angle := 0.0
	var _rect: ColorRect
	var _mat := ShaderMaterial.new()

	func _ready() -> void:
		_rect = ColorRect.new()
		_rect.size = Vector2(240, 240)
		_rect.position = -_rect.size / 2.0
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat.shader = VORTEX
		_mat.set_shader_parameter("glow", glow)
		_mat.set_shader_parameter("seed", randf() * 20.0)
		_rect.material = _mat
		add_child(_rect)

	func _process(delta: float) -> void:
		_angle += spin * delta
		_mat.set_shader_parameter("angle", _angle)
		_rect.scale = Vector2.ONE * maxf(0.001, radius / 104.0)
		_rect.pivot_offset = _rect.size / 2.0
		_rect.visible = radius >= 1.0


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
		_flame_burst(hit, 46.0, Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.15), 0.12)
		_casing(a.home + dir * 30.0, dir)
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
	_flame_burst(tpos, 260.0 if big else 190.0, Color(1.0, 0.92, 0.65), Color(1.0, 0.42, 0.08), 0.45)
	_smoke_puff(tpos, 280.0 if big else 210.0, Color(0.32, 0.3, 0.28))
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
	_flame_burst(at + dir * 16.0, 84.0, Color(1.0, 0.96, 0.75), Color(1.0, 0.5, 0.1), 0.1)   # (the fireball)


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
	var halo := Line2D.new()   # (its glow)
	halo.points = l.points
	halo.width = 10.0
	halo.default_color = Color(col, 0.22)
	halo.material = _add_mat
	halo.z_index = 70
	fx.add_child(halo)
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", 0.0, 0.08)
	t.parallel().tween_property(halo, "modulate:a", 0.0, 0.1)
	t.tween_callback(func():
		l.queue_free()
		halo.queue_free())


## A laser beam from `from` to `to` that lasts `secs`, then narrows away.
func _beam(from: Vector2, to: Vector2, width: float, secs: float) -> void:
	var length := from.distance_to(to)
	var h := width * 5.0
	var b := ColorRect.new()
	b.size = Vector2(length + h * 0.2, h)
	b.position = from - Vector2(0, h / 2.0)
	b.pivot_offset = Vector2(0, h / 2.0)
	b.rotation = (to - from).angle()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.z_index = 70
	var m := ShaderMaterial.new()
	m.shader = FX_BEAM
	m.set_shader_parameter("glow", LASER_GLOW)
	m.set_shader_parameter("length_px", length)
	m.set_shader_parameter("seed", randf() * 20.0)
	b.material = m
	fx.add_child(b)
	var bloom := Sprite2D.new()   # (where it hits)
	bloom.texture = ArenaLife._soft_dot()
	bloom.position = to
	bloom.scale = Vector2.ONE * width / 9.0
	bloom.modulate = Color(LASER_GLOW.lightened(0.4), 0.9)
	bloom.material = _add_mat
	bloom.z_index = 71
	fx.add_child(bloom)
	var t := b.create_tween()
	t.tween_interval(secs)
	t.tween_method(func(x: float): m.set_shader_parameter("width", x), 1.0, 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(bloom, "modulate:a", 0.0, 0.12)
	t.tween_callback(func():
		b.queue_free()
		bloom.queue_free())


## The charge at the muzzle: a dark core in a glowing shell.
class LaserOrb extends Node2D:
	const FIRE := preload("res://shaders/fx_fire.gdshader")
	var glow := Color.PURPLE
	var core := Color.BLACK
	var _plasma: ColorRect
	var radius := 11.0:
		set(v):
			radius = v
			queue_redraw()
			if _plasma:
				_plasma.size = Vector2.ONE * radius * 5.0
				_plasma.position = -_plasma.size / 2.0

	func _ready() -> void:   # (a ball of plasma churning round the dark core)
		_plasma = ColorRect.new()
		_plasma.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = FIRE
		m.set_shader_parameter("shape", 1)
		m.set_shader_parameter("speed", 4.0)
		m.set_shader_parameter("core", Color(0.95, 0.9, 1.0))
		m.set_shader_parameter("outer", glow)
		m.set_shader_parameter("gain", 0.9)
		m.set_shader_parameter("seed", randf() * 20.0)
		_plasma.material = m
		add_child(_plasma)
		radius = radius

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


## Wildcard's attack: the card leans back and fans out a hand of cards from a normal deck, then throws
## them one by one with a flick: each tumbles through the air on an arc, trailing a ribbon of light, its
## spin easing as it lands, and thuds into the target with a springy wobble before dropping away. A big
## hit ends with a gold-edged court card or ace thrown hard, and the full impact.
func _card_strike(a: CardView, d: CardView, tpos: Vector2, dir: Vector2, big: bool, direct: bool) -> void:
	var side_v := dir.orthogonal()
	var hand_at := a.home + dir * 118.0
	var base_rot := dir.angle() + PI / 2
	# Wind-up: the attacker leans back as the hand fans out in front of it
	Sfx.play("shuffle", 1.2, -4.0)
	_cam_focus(a.home.lerp(tpos, 0.35), 1.05 if big else 1.03, 0.32)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(a, "position", a.home - dir * 30.0, 0.26)
	t.tween_property(a, "scale", Vector2.ONE * 1.18 * a.board_scale, 0.26)
	t.tween_property(a, "rotation", a.home_rot - 0.1, 0.26)
	var n := 5
	var fan: Array = []
	for i in n:
		var c := ThrownCard.new()
		c.deal()
		c.font = _font
		c.position = hand_at
		c.rotation = base_rot
		c.scale = Vector2.ONE * 0.2
		c.z_index = 72 + i
		fx.add_child(c)
		var spread := (i - (n - 1) / 2.0)
		var ft := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ft.tween_property(c, "scale", Vector2.ONE, 0.24).set_delay(i * 0.025)
		ft.tween_property(c, "rotation", base_rot + spread * 0.26, 0.24).set_delay(i * 0.025)
		ft.tween_property(c, "position", hand_at + side_v * spread * 9.0 - dir * absf(spread) * 3.0, 0.24).set_delay(i * 0.025)
		fan.append(c)
	await t.finished
	await _wait(0.05)
	_clear_attack_line()
	# The volley: thrown one by one from the fan
	for i in n:
		var c: ThrownCard = fan[n - 1 - i]   # (the top card first)
		var from := c.position
		var to := tpos + side_v * randf_range(-36.0, 36.0) + dir * randf_range(-22.0, 12.0)
		var bend := side_v * randf_range(42.0, 78.0) * (1.0 if i % 2 == 0 else -1.0)
		var turns := randf_range(2.5, 3.5) * (1.0 if randf() < 0.5 else -1.0)
		var r0 := c.rotation
		var land_rot := (to - from).angle() + PI / 2 + randf_range(-0.45, 0.45)
		var dur := randf_range(0.2, 0.24)
		c.flying = true
		var fly := c.create_tween()
		fly.tween_method(func(k: float):
			var e := 1.0 - pow(1.0 - k, 1.6)   # (fast off the hand, settling in)
			var m := from.lerp(to, e) + bend * 4.0 * e * (1.0 - e)
			c.trail.push_front(m)
			if c.trail.size() > 9:
				c.trail.pop_back()
			c.position = m
			var spin := 1.0 - pow(1.0 - k, 2.2)   # (the spin eases out as it lands)
			c.rotation = lerp_angle(r0, land_rot, k * k) + turns * TAU * spin * (1.0 - k * k)
			c.tumble = absf(cos(k * PI * 3.0))   # (turning over in the air)
			c.queue_redraw(), 0.0, 1.0, dur)
		fly.tween_callback(func():   # the thud: it bites in, wobbles, then drops away
			c.flying = false
			c.trail.clear()
			c.tumble = 1.0
			c.rotation = land_rot
			c.scale = Vector2.ONE * 1.18
			c.queue_redraw()
			var hit := c.create_tween().set_parallel()
			hit.tween_property(c, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			hit.tween_property(c, "rotation", land_rot, 0.3).from(land_rot + 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			hit.chain().tween_interval(0.12)
			hit.chain().tween_property(c, "position", to + Vector2(0, 30), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			hit.parallel().tween_property(c, "rotation", land_rot + randf_range(-0.6, 0.6), 0.34)
			hit.parallel().tween_property(c, "modulate:a", 0.0, 0.34)
			hit.chain().tween_callback(c.queue_free)
			_sparks(to, dir, Color(1, 0.95, 0.85), 12, 50.0)
			_burst(to, Color(1, 0.84, 0.4), 8, 260, 0.32, 0.0)
			_flame_burst(to, 96.0, Color(1.0, 0.97, 0.82), Color(1.0, 0.7, 0.18), 0.25)
			Sfx.play("hit", randf_range(1.35, 1.55), -9.0)
			shake(4.0)
			if d:
				d.kick(dir + side_v * randf_range(-0.4, 0.4), 9.0)
				d.flash())
		# the wrist flick
		Sfx.play("whoosh", randf_range(1.45, 1.75), -8.0)
		a.kick(-dir, 7.0)
		var flick := create_tween()
		flick.tween_property(a, "rotation", a.home_rot + 0.06 * (1.0 if i % 2 == 0 else -1.0), 0.05)
		flick.tween_property(a, "rotation", a.home_rot - 0.1, 0.07)
		await _wait(0.075)
	await _wait(0.22)
	# A big hit: a gold-edged court card or ace, thrown hard and straight
	if big:
		var fin := ThrownCard.new()
		fin.deal(true)
		fin.gold = true
		fin.font = _font
		fin.position = hand_at
		fin.rotation = base_rot
		fin.z_index = 78
		fin.scale = Vector2.ONE * 1.4
		fin.flying = true
		fx.add_child(fin)
		Sfx.play("whoosh", 1.05, -2.0)
		a.kick(-dir, 14.0)
		var fly2 := fin.create_tween()
		fly2.tween_method(func(k: float):
			var m := hand_at.lerp(tpos, k)
			fin.trail.push_front(m)
			if fin.trail.size() > 12:
				fin.trail.pop_back()
			fin.position = m
			fin.rotation = base_rot + TAU * 3.0 * (1.0 - pow(1.0 - k, 2.0))
			fin.queue_redraw(), 0.0, 1.0, 0.17).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		await fly2.finished
		fin.flying = false
		fin.trail.clear()
		fin.queue_redraw()
		var gone := fin.create_tween()
		gone.tween_property(fin, "scale", Vector2.ONE * 1.7, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		gone.tween_interval(0.1)
		gone.tween_property(fin, "modulate:a", 0.0, 0.28)
		gone.tween_callback(fin.queue_free)
	# Impact
	_strike_at = tpos
	_strike_time = _game_time
	Sfx.play("hit", 0.85 if direct else 1.0)
	Sfx.play("boom", 1.0 if big else 1.2, 0.0 if big else -5.0)
	shake(22.0 if big else 12.0)
	_shockwave(tpos, 0.9 if big else 0.5)
	_post_pulse("aberration", 12.0 if big else 5.0, 0.4)
	_sparks(tpos, dir, Color(1, 0.88, 0.5), 40 if big else 22)
	_burst(tpos, Color(1, 0.8, 0.35), 26, 520)
	_ring(tpos, Color(1, 0.86, 0.45), 1.5 if big else 1.2)
	_flame_burst(tpos, 290.0 if big else 210.0, Color(1.0, 0.97, 0.82), Color(1.0, 0.68, 0.15), 0.5)
	if d:
		d.flash()
		d.kick(dir, 30.0 if big else 22.0)
		var push := create_tween()
		push.tween_property(d, "position", d.home + dir * (30.0 if big else 18.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		push.tween_property(d, "position", d.home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if big:
		_impact_frame(0.06)
	a.create_tween().tween_property(a, "rotation", a.home_rot, 0.22).set_trans(Tween.TRANS_SINE)


## A thrown playing card (Wildcard's attack): any card of a normal deck, corner indices, a large
## centre pip (or the letter of a court card), gold edged; a gold card is the big hit's finisher.
## While flying it trails a tapered ribbon of light and tumbles (tumble: 0 edge-on, 1 face-on).
class ThrownCard extends Node2D:
	const SIZE := Vector2(36, 50)
	const SUITS := ["♠", "♥", "♣", "♦"]
	const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	var suit := 0
	var rank := "A"
	var gold := false
	var font: Font
	var flying := false
	var tumble := 1.0
	var trail: Array = []   # recent positions (in the parent's space)

	## A random card; court only: J, Q, K or A.
	func deal(court := false) -> void:
		suit = randi() % 4
		rank = ["A", "J", "Q", "K"].pick_random() if court else RANKS.pick_random()

	func _draw() -> void:
		# The ribbon: a tapered stroke through the recent positions
		if flying and trail.size() > 1:
			var pts: Array = trail.map(func(p): return (p - position).rotated(-rotation) / scale.x)
			for i in range(pts.size() - 1):
				var k := 1.0 - float(i) / pts.size()
				draw_line(pts[i], pts[i + 1], Color(1, 0.9, 0.62, 0.38 * k), 10.0 * k, true)
				draw_line(pts[i], pts[i + 1], Color(1, 1, 0.95, 0.5 * k), 3.0 * k, true)
		# The card, squeezed as it turns over
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(maxf(0.12, tumble), 1.0))
		var r := Rect2(-SIZE / 2, SIZE)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.bg_color = Color(1.0, 0.93, 0.66) if gold else Color(0.98, 0.96, 0.92)
		sb.border_color = Color(0.78, 0.55, 0.14)
		sb.set_border_width_all(2 if not gold else 3)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(1, 2)
		draw_style_box(sb, r)
		if tumble < 0.35 or font == null:   # (edge-on: no face to see)
			draw_set_transform(Vector2.ZERO)
			return
		var red := suit == 1 or suit == 3
		var ink := (Color(0.62, 0.08, 0.06) if red else Color(0.22, 0.12, 0.02)) if gold else (Color(0.82, 0.08, 0.1) if red else Color(0.08, 0.06, 0.06))
		# corner indices: top left, and bottom right turned round
		for flip in [false, true]:
			draw_set_transform(Vector2.ZERO, PI if flip else 0.0, Vector2(maxf(0.12, tumble), 1.0))
			draw_string(font, Vector2(-SIZE.x / 2 + 2, -SIZE.y / 2 + 11), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
			draw_string(font, Vector2(-SIZE.x / 2 + 2, -SIZE.y / 2 + 20), SUITS[suit], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(maxf(0.12, tumble), 1.0))
		# the centre: a court card's letter over its suit, else a large pip
		if rank in ["J", "Q", "K"]:
			draw_string(font, Vector2(-SIZE.x / 2, 4), rank, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, ink)
			draw_string(font, Vector2(-SIZE.x / 2, 17), SUITS[suit], HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 11, ink)
		else:
			draw_string(font, Vector2(-SIZE.x / 2, 9), SUITS[suit], HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 24 if rank == "A" else 18, ink)
		draw_set_transform(Vector2.ZERO)


## An attack that didn't get through a defender: its guard snaps up, the blow glances off.
func _ev_blocked(ev: Dictionary) -> void:
	var at := slot_pos(ev.side, ev.slot)
	var v: CardView = field.get(ev.side, {}).get(ev.slot)
	var back := Vector2(0, -1 if ev.side == "player" else 1)   # (towards whoever attacked)
	Sfx.play("set", 0.7)
	Sfx.play("slam", 1.5, -8.0)
	_guard_flash(at, BLUE)
	_sparks(at + back * 60.0, back, Color(0.7, 0.9, 1.0), 16, 70.0)
	if v:
		_pulse_glow(v, BLUE)
		v.kick(-back, 8.0)
	_float_text(at, "BLOCKED", BLUE, 40)
	await _wait(0.45)


## A guard holding: a shield's outline snaps up over the card and fades.
func _guard_flash(at: Vector2, col: Color) -> void:
	var s := Node2D.new()
	s.position = at
	s.z_index = 446
	s.material = _add_mat
	var pts := PackedVector2Array([Vector2(0, -92), Vector2(66, -64), Vector2(66, 14), Vector2(0, 92),
		Vector2(-66, 14), Vector2(-66, -64), Vector2(0, -92)])
	s.draw.connect(func():
		s.draw_colored_polygon(pts.slice(0, 6), Color(col, 0.16))
		s.draw_polyline(pts, col.lightened(0.4), 6.0, true))
	s.scale = Vector2.ONE * 0.7
	fx.add_child(s)
	var t := s.create_tween()
	t.tween_property(s, "scale", Vector2.ONE * 1.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.12)
	t.tween_property(s, "modulate:a", 0.0, 0.3)
	t.tween_callback(s.queue_free)


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
	if v.face_up and _clan_style(v.card, "ko") != "":
		match _clan_style(v.card, "ko"):
			"stardust": await _stardust(v, _clan_color(v.card))
			"ash": await _ash_ko(v)
			"sink": await _sink_ko(v)
			"blast": await _blast_ko(v)
			"fold": await _fold_ko(v)
			"rift": await _rift_ko(v)
			"knockout": await _knockout_ko(v)
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
		await _comet(_strike_at, root.position + root.size / 2, _strike_tint if _strike_tint.a > 0.0 else (RED if side == "player" else GOLD))
		_strike_at = Vector2.INF
	_strike_tint = Color(0, 0, 0, 0)
	Sfx.play("damage")
	Sfx.play("boom", 0.8 if lethal else 1.0, 0.0 if lethal or amount >= 1000 else -6.0)
	shake(clampf(amount / 60.0, 8.0, 28.0) * (1.4 if lethal else 1.0))
	_set_morale(side, ev.morale)
	if lethal:
		_finisher(_panels[side].root)
	elif side == "player" and int(ev.morale) <= DuelState.START_MORALE / 4:
		Sfx.play("heartbeat", 1.0, -2.0)
	# (just off the plate, so it never covers the Morale counting down: above yours, below the others')
	var up: bool = side in ["player", "ally"]
	_float_text(Vector2(root.position.x + root.size.x / 2, root.position.y - 50 if up else root.position.y + root.size.y + 50),
		"-%d" % amount, RED, 72)
	if side == "player":
		_screen_flash(RED, 0.22)
	await _wait(0.6)


## A keyword effect lands on a character (POISON, BURN, BLEED, SHOCK, FREEZE, STASIS).
func _ev_status(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	var kind := str(ev.kind)
	var style: Array = CardView.STATUS_STYLE.get(kind, [GOLD, "", kind.to_upper()])
	var col: Color = CardView.status_color(kind) if CardView.STATUS_STYLE.has(kind) else style[0]
	var from := _status_source()
	var fly := from != Vector2.INF and from.distance_to(v.position) > 60.0
	_status_arrive(v, ev, col, str(style[2]), from if fly else Vector2.INF)
	# (one effect on several characters: they land one after another, not one at a time)
	var more := not _queue.is_empty() and str(_queue[0].get("type", "")) == "status"
	await _wait(0.16 if more else (0.8 if fly else 0.5))


## Where the status about to land came from: the card whose effect call-out follows it (the rules name an
## effect once it has happened), or nowhere known (Vector2.INF).
func _status_source() -> Vector2:
	for i in mini(_queue.size(), 12):
		var nxt: Dictionary = _queue[i]
		var type := str(nxt.get("type", ""))
		if type == "effect":
			return _effect_origin(nxt)
		if not type in ["status", "stats", "position", "downed", "ko"]:
			return Vector2.INF
	return Vector2.INF


## The same for anything an effect does (a heal): the card whose call-out follows, or Vector2.INF.
func _source_ahead() -> Vector2:
	for i in mini(_queue.size(), 12):
		var nxt: Dictionary = _queue[i]
		var type := str(nxt.get("type", ""))
		if type == "effect":
			return _effect_origin(nxt)
		if not type in ["status", "stats", "position", "downed", "ko", "heal", "leader_heal", "damage"]:
			return Vector2.INF
	return Vector2.INF


## Soft lights streaming from one place to another (a heal on its way to the Morale it restores).
func _wisps(from: Vector2, to: Vector2, col: Color, n: int) -> void:
	for i in n:
		var w := Sprite2D.new()
		w.texture = ArenaLife._soft_dot()
		w.material = _add_mat
		w.modulate = Color(col.lightened(0.35), 1.0)
		w.scale = Vector2.ONE * randf_range(0.55, 0.95)
		w.position = from + Vector2(randf_range(-40, 40), randf_range(-50, 50))
		w.z_index = 450
		fx.add_child(w)
		var bend := Vector2(randf_range(-90, 90), randf_range(-90, 90))
		var a := w.position
		var t := w.create_tween()
		t.tween_method(func(k: float): w.position = a.lerp(to, k) + bend * 4.0 * k * (1.0 - k), 0.0, 1.0, randf_range(0.4, 0.55)).set_delay(i * 0.022).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(w.queue_free)


## Where the card behind an effect call-out is on the table.
func _effect_origin(ev: Dictionary) -> Vector2:
	var side := str(ev.get("side", ""))
	if int(ev.get("slot", -1)) >= 0:
		var v: CardView = field.get(side, {}).get(int(ev.slot))
		return v.position if v else Vector2.INF
	match str(ev.get("card", {}).get("cardType", "")):
		"leader":
			return pile_pos(side, "leader")
		"hustle", "ambush":
			return Vector2(1080, DIVIDER_Y)   # (where a Hustle is shown as it's played)
	return Vector2.INF


const STATUS_KEYS := ["poison", "burn", "bleed", "freeze_until", "stasis_until", "stun_until", "blind_until",
	"suppress_until", "silence_until"]

## What a status event says of the card's statuses (amounts, turns left) goes onto the view's card: the
## badges and the card panel read it there. (A copy: the view's card can be the rules' own.)
func _merge_status(v: CardView, c: Dictionary) -> void:
	if c.is_empty() or v.card.is_empty():
		return
	var mine := v.card.duplicate()
	for k in STATUS_KEYS:
		if c.has(k):
			mine[k] = c[k]
		else:
			mine.erase(k)
	v.card = mine


## A status's moment: it flies in from the card that caused it (when that's known), then lands its own
## way: flames catch up the card, ice closes in from its edges, lightning strikes it...
func _status_arrive(v: CardView, ev: Dictionary, col: Color, word: String, from: Vector2) -> void:
	var kind := str(ev.kind)
	if from != Vector2.INF:
		await _status_shot(from, v.position, kind, col)
		if not is_instance_valid(v):
			return
	_merge_status(v, ev.get("card", {}))
	if kind != "shock" and not v.statuses.has(kind):
		var st := v.statuses.duplicate()
		st.append(kind)
		v.statuses = st
	v.pop_badge(kind)
	v.flash()
	_pulse_glow(v, col)
	var at := v.position
	_float_text(at + Vector2(0, -110 if ev.side == "player" else 110), word, col, 34)
	match kind:
		"burn":   # it catches: flames shoot up the card, embers fly off it
			v.flare("burn", 2.6)
			Sfx.play("fire_roar", 1.5, -5.0)
			Sfx.play("ignite", 0.8, -2.0)
			_flame_burst(at + Vector2(0, 26), 300.0, Color(1.0, 0.95, 0.7), Color(1.0, 0.42, 0.08), 0.5)
			_burst(at + Vector2(0, 60), col, 36, 420, 0.9, -620.0)
			_sparks(at + Vector2(0, 80), Vector2.UP, Color(1.0, 0.7, 0.3), 16, 55.0)
		"poison":   # a splash that runs down it, and the fumes coming off
			v.flare("poison", 2.2)
			Sfx.play("splash", 0.8, -3.0)
			_burst(at + Vector2(0, -30), col, 30, 320, 0.8, 900.0)
			_smoke_puff(at + Vector2(0, 30), 250.0, Color(0.2, 0.5, 0.14, 0.55))
			_burst(at + Vector2(0, 60), col.lightened(0.3), 12, 110, 1.2, -170.0)
		"bleed":   # cut open
			v.flare("bleed", 2.0)
			Sfx.play("hit", 1.35, -3.0)
			_slash(at, col, v.scale.x)
			v.kick(Vector2(1, 0.4), 9.0)
			_burst(at, col, 24, 300, 0.7, 1000.0)
		"shock":
			Sfx.play("laser", 1.9, -4.0)
			Sfx.play("hit", 1.6, -6.0)
			if from == Vector2.INF:   # (out of the sky)
				_lightning(Vector2(at.x + randf_range(-90.0, 90.0), at.y - 620.0), at, col)
			for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_sparks(at, d, col, 6, 60.0)
			_burst(at, col, 40, 520, 0.45, 0.0)
			_screen_flash(col, 0.12)
			v.kick(Vector2(randf_range(-1.0, 1.0), -1), 10.0)
			shake(8)
		"freeze":   # the ice takes it from the edges in (the shader), with a crack and a breath of cold
			Sfx.play("glass_smash", 1.7, -9.0)
			_smoke_puff(at, 280.0, Color(0.75, 0.92, 1.0, 0.4))
			_ring_in(at, col, 1.7)
			_shards(at + Vector2(0, -40), Vector2.UP, 12, [Color(0.95, 1.0, 1.0), Color(0.65, 0.88, 1.0, 0.85), Color(0.5, 0.8, 1.0, 0.0)])
			_burst(at, col, 26, 200, 1.0, 140.0)
		"blind":   # a flash-bang: white, then the dark over its eyes
			v.flare("blind", 1.6)
			Sfx.play("boom", 1.7, -8.0)
			_flame_burst(at + Vector2(0, -30), 260.0, Color.WHITE, Color(0.75, 0.82, 1.0), 0.22)
			_ring(at + Vector2(0, -30), Color.WHITE, 1.7)
			_screen_flash(Color.WHITE, 0.14)
			_smoke_puff(at + Vector2(0, -30), 230.0, Color(0.05, 0.05, 0.1, 0.85))
		"stun":   # seeing stars
			Sfx.play("slam", 1.4, -4.0)
			v.kick(Vector2(-1.0 if randf() < 0.5 else 1.0, -0.6), 16.0)
			_burst(at + Vector2(0, -70), Color(1.0, 0.85, 0.35), 26, 400, 0.6, 500.0)
			_ring(at + Vector2(0, -60), col, 0.9)
			shake(5)
		"stasis":   # time closes in around it
			Sfx.play("riser", 0.7, -8.0)
			_ring_in(at, col, 1.9)
			_burst(at, col, 30, 160, 1.2, -60.0)
		"shield":
			v.flare("shield", 2.4)
			Sfx.play("promote", 1.5, -6.0)
			_ring(at, col, 1.3)
			_light_column(at, col)
		"suppress":   # pinned down under fire
			Sfx.play("hit", 1.9, -5.0)
			for i in 4:
				var to := at + Vector2(randf_range(-50.0, 50.0), randf_range(-70.0, 70.0))
				_tracer(to + Vector2(-560.0 if at.x > 1080.0 else 560.0, -180.0 + i * 40.0), to, col)
			_sparks(at, Vector2.UP, col, 12, 80.0)
			shake(4)
		"silence":   # the sound drawn out of it
			Sfx.play("down", 1.5, -6.0)
			_ring_in(at + Vector2(0, -40), col, 1.3)
			_burst(at, col, 18, 180, 0.7, -120.0)
		"charm":
			Sfx.play("promote", 1.8, -8.0)
			_ring(at, col, 1.2)
			_burst(at, col, 28, 260, 1.0, -260.0)
		"undead":
			Sfx.play("riser", 0.6, -6.0)
			_souls(at, col, 10)
			_ring(at, col, 1.2)
		_:
			Sfx.play("effect")
			_burst(at, col, 26, 240, 0.8, -200.0)


## A status on its way from the card that caused it: a fireball for BURN, a lobbed flask for POISON, a bolt
## for SHOCK, a shard of ice for FREEZE... (awaited: it ends as it arrives)
func _status_shot(from: Vector2, to: Vector2, kind: String, col: Color) -> void:
	_ring(from, col, 0.55)
	if kind == "shock":
		_lightning(from, to, col)
		await _wait(0.08)
		return
	if kind == "suppress":
		for i in 3:
			_tracer(from, to + Vector2(randf_range(-40.0, 40.0), randf_range(-60.0, 60.0)), col)
			await _wait(0.05)
		return
	# [how far it bows up off the straight line, seconds, head size, the trail's fall, the trail's spread]
	var style: Array = {"burn": [110.0, 0.3, 2.6, -260.0, 70.0], "poison": [210.0, 0.36, 2.2, 520.0, 40.0],
		"freeze": [0.0, 0.2, 1.8, 60.0, 16.0], "bleed": [30.0, 0.16, 1.6, 300.0, 20.0],
		"blind": [170.0, 0.34, 2.0, 0.0, 30.0]}.get(kind, [90.0, 0.28, 2.2, 0.0, 50.0])
	var head := Sprite2D.new()
	head.texture = _dot
	head.material = _add_mat
	head.self_modulate = col.lerp(Color.WHITE, 0.45)
	head.scale = Vector2.ONE * float(style[2])
	head.position = from
	head.z_index = 82
	fx.add_child(head)
	var trail := CPUParticles2D.new()
	trail.amount = 46
	trail.lifetime = 0.34
	trail.local_coords = false
	trail.texture = _dot
	trail.material = _add_mat
	trail.gravity = Vector2(0, float(style[3]))
	trail.spread = 180.0
	trail.initial_velocity_max = float(style[4])
	trail.scale_amount_min = 0.4
	trail.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, col.lerp(Color.WHITE, 0.25))
	g.set_color(1, Color(col, 0.0))
	trail.color_ramp = g
	head.add_child(trail)
	trail.scale = Vector2.ONE / head.scale
	Sfx.play("whoosh", 1.5, -6.0)
	var ctrl := from.lerp(to, 0.5) + Vector2(0, -float(style[0]))
	var t := create_tween()
	t.tween_method(func(k: float): head.position = from.lerp(ctrl, k).lerp(ctrl.lerp(to, k), k), 0.0, 1.0, float(style[1])) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	trail.emitting = false
	head.self_modulate.a = 0.0   # (the trail thins away behind it)
	get_tree().create_timer(0.5).timeout.connect(head.queue_free)


## A bolt of lightning from one point to another: a jagged line and a fork off it, there and gone.
func _lightning(from: Vector2, to: Vector2, col: Color) -> void:
	var across := (to - from).orthogonal().normalized()
	for fork in 2:
		var pts := PackedVector2Array()
		var steps := 9
		for i in steps + 1:
			var off := 0.0 if i == 0 or i == steps else randf_range(-30.0, 30.0) * (0.7 if fork == 0 else 1.5)
			pts.append(from.lerp(to, float(i) / steps) + across * off)
		var l := Line2D.new()
		l.points = pts
		l.width = 5.0 if fork == 0 else 2.5
		l.default_color = Color.WHITE if fork == 0 else col.lightened(0.4)
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.material = _add_mat
		l.z_index = 83
		fx.add_child(l)
		var halo := Line2D.new()   # (its glow)
		halo.points = pts
		halo.width = 18.0
		halo.default_color = Color(col, 0.3)
		halo.material = _add_mat
		halo.z_index = 82
		fx.add_child(halo)
		var t := l.create_tween()
		t.tween_interval(0.07)
		t.tween_property(l, "modulate:a", 0.0, 0.16)
		t.parallel().tween_property(halo, "modulate:a", 0.0, 0.2)
		t.tween_callback(func():
			l.queue_free()
			halo.queue_free())


## A cut across a card: a bright line drawn fast from corner to corner, left hanging a moment.
func _slash(at: Vector2, col: Color, s := 1.0) -> void:
	var a := at + Vector2(-58, -76) * s
	var b := at + Vector2(58, 76) * s
	var l := Line2D.new()
	l.width = 8.0
	var thin := Curve.new()   # (to a point at both ends)
	thin.add_point(Vector2(0.0, 0.0))
	thin.add_point(Vector2(0.5, 1.0))
	thin.add_point(Vector2(1.0, 0.0))
	l.width_curve = thin
	l.default_color = col.lerp(Color.WHITE, 0.6)
	l.material = _add_mat
	l.z_index = 83
	fx.add_child(l)
	var t := l.create_tween()
	t.tween_method(func(k: float): l.points = PackedVector2Array([a, a.lerp(b, k * 0.5), a.lerp(b, k)]), 0.02, 1.0, 0.09)
	t.tween_interval(0.12)
	t.tween_property(l, "modulate:a", 0.0, 0.25)
	t.tween_callback(l.queue_free)
	_sparks(at, b - a, col, 12, 30.0)


## A ring that closes in on a spot (the other way round from _ring).
func _ring_in(pos: Vector2, color: Color, size_from: float) -> void:
	var s := Sprite2D.new()
	s.texture = _ring_tex
	s.material = _add_mat
	s.modulate = Color(color, 0.0)
	s.position = pos
	s.scale = Vector2.ONE * size_from
	fx.add_child(s)
	var t := create_tween().set_parallel()
	t.tween_property(s, "scale", Vector2.ONE * 0.4, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(s, "modulate:a", 1.0, 0.3)
	t.chain().tween_property(s, "modulate:a", 0.0, 0.15)
	t.chain().tween_callback(s.queue_free)


## POISON / BURN tick at the start of the owner's turn; BLEED after a brawl.
func _ev_status_tick(ev: Dictionary) -> void:
	var v: CardView = field[ev.side].get(ev.slot)
	if v == null:
		return
	var kind := str(ev.kind)
	var col: Color = CardView.status_color(kind) if CardView.STATUS_STYLE.has(kind) else GOLD
	var text := "-%d ATK" % int(ev.amount)
	if kind == "burn":
		text = "BURN -%d" % int(ev.amount)
	elif kind == "bleed":
		text = "-%d ATK/DEF" % int(ev.amount)
	_merge_status(v, ev.get("card", {}))
	if kind != "bleed" and not ev.card.has(kind):
		v.statuses = v.statuses.filter(func(k): return k != kind)
	v.flare(kind, 2.4)   # (the last of it flares too, then dies away)
	v.pop_badge(kind)
	v.flash()
	_pulse_glow(v, col)
	var at := v.position
	match kind:
		"burn":   # the fire roars up, and what it costs flies to its owner's Morale (the damage that follows)
			Sfx.play("fire_roar", 1.6, -4.0)
			_flame_burst(at + Vector2(0, 20), 320.0, Color(1.0, 0.95, 0.7), Color(1.0, 0.42, 0.08), 0.5)
			_burst(at + Vector2(0, 50), col, 30, 420, 0.9, -620.0)
			_strike_at = at
			_strike_time = _game_time
			_strike_tint = Color(1.0, 0.55, 0.15)
		"poison":   # it sickens: a shudder, the fumes thicker
			Sfx.play("down", 1.3, -6.0)
			_smoke_puff(at + Vector2(0, 20), 230.0, Color(0.2, 0.5, 0.14, 0.5))
			_burst(at + Vector2(0, 40), col, 20, 150, 1.1, -190.0)
			v.kick(Vector2(0.3, 1), 5.0)
		"bleed":
			Sfx.play("down", 1.3, -6.0)
			_burst(at, col, 24, 260, 0.7, 1000.0)
		_:
			Sfx.play("down", 1.3, -6.0)
			_burst(at, col, 18, 200, 0.7, -150.0)
	_float_text(at + Vector2(0, -90 if ev.side == "player" else 90), text, col, 36)
	await _wait(0.4)


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
	var from: String = ev.side
	var side := str(ev.get("to", from))   # (a CHARMED card goes back to its owner's hand)
	var v: CardView = field[from].get(ev.slot)
	field[from].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, side, side == "player")
		v.position = slot_pos(from, ev.slot)
	v.show_badge = false
	v.downed = false
	v.glow = 0.0
	v.statuses = []   # (a card in the hand has no statuses: no WANTED poster on a card back)
	if v == _hovered:   # (it was just clicked as the target)
		_hovered = null
	v.set_card(ev.card)
	Sfx.play("whoosh", 1.2)
	_ring(v.position, BLUE, 1.2)
	_speed_lines(v.position, Vector2(0, 1 if side == "player" else -1), 8)   # (whisked off towards its hand)
	_burst(v.position, BLUE, 14, 240, 0.45, 0.0)
	_float_text(v.position + Vector2(0, -110 if side == "player" else 110), "BACK TO HAND", BLUE, 30)
	if side != "player" and v.face_up:   # (any other player's hand: FFA seats too, or it showed as a "?")
		v.flip(false)
	elif side == "player" and not v.face_up:
		v.flip(true)
	hand[side].append(v)
	_layout_hand(side)
	await _wait(0.4)


## A character goes back on top of its owner's deck: it turns face-down and slides onto the pile.
func _ev_topdeck(ev: Dictionary) -> void:
	var from: String = ev.side
	var side := str(ev.get("to", from))   # (a CHARMED card goes back on its owner's deck)
	var v: CardView = field[from].get(ev.slot)
	field[from].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, side, true)
		v.position = slot_pos(from, ev.slot)
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
		# Inside the panel's width, right-aligned, above or below it: whichever side stays on screen (in a
		# free-for-all the panels sit against different edges)
		badge.size = Vector2(minf(220.0, root.size.x), 26)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var g := root.get_global_rect()
		var below: bool = ev.side != "player"
		if below and g.end.y + 30.0 * root.get_global_transform().get_scale().y > 1080.0:
			below = false
		elif not below and g.position.y - 30.0 * root.get_global_transform().get_scale().y < 0.0:
			below = true
		badge.position = Vector2(root.size.x - badge.size.x, root.size.y + 2 if below else -26)
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
	v.position = pile_pos(str(ev.get("from_side", side)), "gutter")   # (raised from the opponent's Gutter: from theirs)
	v.z_index = 420
	Sfx.play("promote", 1.3, -6.0)
	_burst(v.position, GREEN, 20, 240, 0.6, -200.0)
	_float_text(v.position + Vector2(0, -110), "RECOVERED", GREEN, 28)
	hand[side].append(v)
	_layout_hand(side)
	await _wait(0.4)


## Cards leave a Gutter for good (exiled): they rise off the pile and burn away in violet flame.
func _ev_gutter_exile(ev: Dictionary) -> void:
	var side: String = ev.side
	var at := pile_pos(side, "gutter")
	var cards: Array = ev.get("cards", [])
	Sfx.play("ko", 0.7, -4.0)
	_float_text(at + Vector2(0, -120 if side == "player" else 120), "EXILED ×%d" % cards.size(), Color("c58bff"), 30)
	for i in mini(cards.size(), 4):
		var v := _new_view(cards[i], side, true)
		v.position = at
		v.z_index = 420 + i
		v.scale = Vector2.ONE * 0.8
		var t := v.create_tween().set_parallel()
		t.tween_property(v, "position", at + Vector2((i - 1.5) * 50.0, -150.0 if side == "player" else 150.0), 0.55).set_delay(i * 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(v, "modulate", Color(0.8, 0.4, 1.4, 0.0), 0.55).set_delay(0.2 + i * 0.08)
		t.chain().tween_callback(v.queue_free)
	_burst(at, Color("b06bff"), 34, 260, 0.9, -260.0)
	_ring(at, Color("b06bff"), 1.0)
	await _wait(0.7)


## A card effect restores Morale.
func _ev_heal(ev: Dictionary) -> void:
	var side: String = ev.side
	var root: Control = _panels[side].root
	var plate: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * (root.position + root.size / 2)
	var from := _source_ahead()
	if from != Vector2.INF:   # (it streams from the card that gave it to the Morale it restores)
		Sfx.play("whoosh", 1.5, -8.0)
		_ring(from, GREEN, 0.8)
		_wisps(from, plate, GREEN, 18)
		await _wait(0.5)
	_set_morale(side, ev.morale)
	Sfx.play("promote", 1.4, -4.0)
	_ring(plate, GREEN, 1.2)
	var up: bool = side in ["player", "ally"]   # (off the plate, like damage: the Morale stays readable)
	_float_text(Vector2(root.position.x + root.size.x / 2, root.position.y - 50 if up else root.position.y + root.size.y + 50),
		"+%d" % int(ev.amount), GREEN, 64)
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
	var calm := Game.photosafe()   # (Photosensitive mode: no flicker between the forms, no white-out)
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
	_converge(stage, col, 60, 0.85)
	create_tween().tween_property(v, "_flash", 0.25 if calm else 0.7, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in 8:
		v.kick(Vector2(randf_range(-1, 1), randf_range(-1, 1)), 3.0 + i * 1.7)
		if i % 3 == 0:
			_sparks(stage, Vector2.UP, bright, 6, 170.0)
		await _wait(0.09)
	# 2. The cocoon: light, the art glowing through it, morphing between the forms on a quickening heartbeat, swelling
	if calm:   # one slow swell; the new form shows when the light breaks
		v.create_tween().tween_property(v, "scale", Vector2.ONE * big * 1.06 * v.board_scale, 0.9).set_trans(Tween.TRANS_SINE)
		await _wait(0.9)
	else:
		var beats := [0.24, 0.2, 0.16, 0.13, 0.105, 0.085, 0.07, 0.058, 0.048, 0.04, 0.036]
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
	if not calm:
		_shockwave(stage, 1.0)
		_ring(stage, Color.WHITE, 2.8)
	_ring(stage, bright, 1.9)
	_burst(stage, bright, 25 if calm else 70, 760, 1.2, -120.0)
	Sfx.play("boom", 1.1, -2.0)
	Sfx.play("promote")
	Sfx.play("legendary", 1.2, -6.0)
	aura.create_tween().tween_property(aura, "modulate:a", 0.0, 0.5)
	# The new form spins in (two quick half-turns, settling), the light draining off it, foil sweeping across
	create_tween().tween_property(v, "_flash", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	v.move_to(stage, big, 0.0, 0.5, Tween.TRANS_BACK)
	if not calm:   # (two quick half-turns flash the card back past: not in Photosensitive mode)
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
	await _wait(0.35)
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
	tt.tween_method(show_tally, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tt.tween_callback(func():
		Sfx.play("click", 1.6, -6.0)
		tally.pivot_offset = tally.size / 2
		tally.scale = Vector2.ONE * 1.15
		tally.create_tween().tween_property(tally, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	await _wait(1.0)
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
			_activate(v, _side_color(side))
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


## CHARM: the character drifts across to the side that charmed it, pink hearts trailing (or, at the
## end of the turn, back home: "back").
## A tribute (absorb): the sacrificed character's strength streams into the one that took it.
func _ev_absorb(ev: Dictionary) -> void:
	var side: String = ev.side
	var v: CardView = field[side].get(int(ev.slot))
	if v == null:
		return
	var from := slot_pos(side, int(ev.get("from_slot", ev.slot)))
	var col := _clan_color(ev.card)
	v.set_meta("stat_quiet", _game_time + 2.0)   # (its numbers' change is shown here, not again by _stat_change)
	Sfx.play("promote", 0.8, -4.0)
	for i in 10:   # wisps flying from where it was into the card
		var w := Sprite2D.new()
		w.texture = ArenaLife._soft_dot()
		w.material = _add_mat
		w.modulate = Color(col.lightened(0.3), 0.9)
		w.scale = Vector2.ONE * randf_range(0.3, 0.55)
		w.position = from + Vector2(randf_range(-40, 40), randf_range(-60, 60))
		w.z_index = 450
		fx.add_child(w)
		var bend := Vector2(randf_range(-80, 80), randf_range(-80, 80))
		var a := w.position
		var t := w.create_tween()
		t.tween_method(func(k: float): w.position = a.lerp(v.position, k) + bend * 4.0 * k * (1.0 - k), 0.0, 1.0, randf_range(0.35, 0.5)).set_delay(i * 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(w.queue_free)
	await _wait(0.5)
	v.flash()
	_ring(v.position, col.lightened(0.3), 1.3)
	_burst(v.position, col, 20, 300, 0.5, 0.0)
	_float_text(v.position + Vector2(0, -120 if side == "player" else 120), "+%d ATK  +%d DEF" % [int(ev.atk), int(ev.def)], GOLD, 30)
	await _wait(0.3)


## PLUNDER from a hand or deck: the card turns face-up, crosses the board in a gold trail and goes
## into the plunderer's hand (face-down again if that's the opponent's).
func _ev_plunder(ev: Dictionary) -> void:
	var side: String = ev.side
	var from_side := str(ev.get("from_side", ""))
	var v: CardView
	if str(ev.get("from", "hand")) == "hand" and hand.has(from_side):
		v = _take_from_hand(from_side, ev.card.uid, ev.card)
		_layout_hand(from_side)
	else:
		v = _new_view(ev.card, from_side, false)
		v.position = pile_pos(from_side, "deck")
	v.set_card(ev.card)
	v.side = side
	v.z_index = 440
	if not v.face_up:
		v.flip(true)
	Sfx.play("whoosh", 1.1)
	_float_text(v.position + Vector2(0, -110 if from_side == "player" else 110), "PLUNDERED!", GOLD, 40)
	await v.move_to(v.position.lerp(Vector2(1080, DIVIDER_Y), 0.5), 1.25, 0.0, 0.3).finished
	if side != "player":
		v.flip(false)
	_burst(v.position, GOLD, 16, 220, 0.5)
	hand[side].append(v)
	_layout_hand(side)
	await _wait(0.35)


func _ev_charm(ev: Dictionary) -> void:
	var from: String = ev.side
	var to: String = str(ev.to_side)
	var v: CardView = field[from].get(ev.slot)
	field[from].erase(ev.slot)
	if v == null:
		v = _new_view(ev.card, to, true)
		v.position = slot_pos(from, ev.slot)
	v.set_card(ev.card)
	v.side = to
	var target := slot_pos(to, int(ev.to_slot))
	field[to][int(ev.to_slot)] = v
	v.home = target
	v.home_rot = PI / 2 if str(ev.card.get("position", "atk")) == "def" else 0.0
	v.z_index = 440
	var pink := Color(1.0, 0.45, 0.75) if not ev.get("plunder", false) else GOLD
	Sfx.play("whoosh", 0.8)
	_ring(v.position, pink, 1.1)
	if not ev.get("back", false):
		_float_text(v.position + Vector2(0, -110 if from == "player" else 110), "PLUNDERED!" if ev.get("plunder", false) else "CHARMED!", pink, 40)
		for i in 6:   # hearts trailing it across
			_burst(v.position.lerp(target, i / 5.0), pink, 4, 160, 0.5, i * 0.05)
	await v.move_to(target, v.home_scale, v.home_rot, 0.55, Tween.TRANS_SINE).finished
	v.z_index = 10
	_ring(target, pink, 0.8)


func _ev_discard(ev: Dictionary) -> void:
	var side: String = ev.side
	var v := _take_from_hand(side, ev.card.uid, ev.card)
	v.z_index = 440
	if not v.face_up:
		v.flip(true)
	await v.move_to(v.position + Vector2(0, -90 if side == "player" else 90), 1.3, 0.0, 0.2).finished
	_float_text(v.position + Vector2(0, -165 if side == "player" else 200), "DISCARDED", Color(0.93, 0.94, 1.0), 34)   # (clear of the card)
	await _wait(0.25)   # (long enough to read which card went)
	await _to_gutter(v, side)


func _ev_stats(ev: Dictionary) -> void:
	var shown := 0
	for side in ev.values:
		var vals: Dictionary = ev.values[side]
		for slot in vals:
			var v: CardView = field[side].get(slot)
			if v:
				var s: Array = vals[slot]
				var was: Array = v.stats()
				v.set_stats(s[0], s[1], s[2], s[3])
				if s.size() > 5:
					v.statuses = s[5]
				if _stat_change(v, was, shown):
					shown += 1


## A character's ATK or DEF moved (a card's effect, a status, an aura): the change pops up over its
## numbers, rising for a gain and sinking for a loss. Not for a card just placed, a new form (a promotion
## counts its own up) or a change already shown (a tribute's strength, _ev_absorb). Says whether it showed.
func _stat_change(v: CardView, was: Array, nth: int) -> bool:
	var key := "%s:%s" % [v.uid, str(v.card.get("id", ""))]
	var same: bool = str(v.get_meta("stat_key", "")) == key
	v.set_meta("stat_key", key)
	var quiet: bool = _game_time < float(v.get_meta("stat_quiet", 0.0))
	var now: Array = v.stats()
	if not same or quiet or was.size() < 2 or now.size() < 2 or not v.face_up or v.busy:
		return false
	var d_atk := int(now[0]) - int(was[0])
	var d_def := int(now[1]) - int(was[1])
	if d_atk == 0 and d_def == 0:
		return false
	var line := 0
	for pair in [[d_atk, "ATK"], [d_def, "DEF"]]:
		var d: int = pair[0]
		if d == 0:
			continue
		var col := Color.html(CardView._stat_color(1 if d > 0 else -1, 0, "ffffff"))
		_stat_pop(v.home + Vector2(0, 24.0 + line * 30.0), "%s%d %s" % ["+" if d > 0 else "-", absi(d), pair[1]], col, d > 0, nth * 0.05)
		line += 1
	var up := d_atk + d_def > 0
	_stat_arrows(v.home, Color.html(CardView._stat_color(1 if up else -1, 0, "ffffff")), up)
	if nth == 0:
		Sfx.play("effect", 1.5 if up else 0.75, -10.0)
	return true


func _stat_pop(at: Vector2, text: String, col: Color, up: bool, delay: float) -> void:
	var l := _label(26, col, true)
	l.text = text
	l.size = Vector2(300, 36)
	l.position = at - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	l.scale = Vector2.ONE * 1.5
	overlay.add_child(l)
	var t := l.create_tween()
	t.tween_interval(maxf(delay, 0.01))
	t.tween_property(l, "modulate:a", 1.0, 0.05)
	t.parallel().tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.5)
	t.tween_property(l, "position:y", l.position.y + (-34.0 if up else 34.0), 0.45)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.45)
	t.tween_callback(l.queue_free)


## Small arrows running up (a gain) or down (a loss) over a card: the direction says it without the colour.
func _stat_arrows(pos: Vector2, col: Color, up: bool) -> void:
	var dir := -1.0 if up else 1.0
	for i in 3:
		var ch := Node2D.new()
		ch.position = pos + Vector2((i - 1) * 34.0, -dir * 34.0)
		ch.z_index = 445
		ch.material = _add_mat
		ch.modulate.a = 0.0
		ch.draw.connect(func():
			ch.draw_polyline(PackedVector2Array([Vector2(-12, -dir * 7.0), Vector2(0, dir * 7.0), Vector2(12, -dir * 7.0)]), col, 5.0, true))
		fx.add_child(ch)
		var t := ch.create_tween()
		t.tween_interval(0.01 + i * 0.06)
		t.tween_property(ch, "modulate:a", 0.95, 0.06)
		t.tween_property(ch, "position:y", ch.position.y + dir * 72.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(ch, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_callback(ch.queue_free)


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
	if to.distance_to(v.position) > 10.0:
		_speed_lines(to, (to - v.position).normalized(), 6)
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
	_ring(v.home, BLUE if c.position == "def" else GOLD, 1.0)
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
	v.flash(0.5)   # (softer than a card's: the leader's face stays in view under it)
	v.kick(Vector2(randf_range(-1, 1), -1), 14.0)
	_burst(v.home, RED, 20, 320, 0.5)
	_ring(v.home, RED, 1.0)
	shake(6.0)
	await _wait(0.35)


func _ev_leader_heal(ev: Dictionary) -> void:
	var v: CardView = leaders.get(ev.side)
	if v == null:
		return
	v.badge_text = _influence_text(ev.influence)
	_float_text(v.home + Vector2(0, -40), "+%d" % ev.amount, Color(1.0, 0.85, 0.42), 56)
	Sfx.play("heal", 1.1)
	_ring(v.home, Color(1.0, 0.85, 0.42), 1.0)
	_burst(v.home, Color(1.0, 0.85, 0.42), 16, 220, 0.7, -260.0)
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
	var won: bool = ev.winner == "player" or (_coop and ev.winner != "boss" and ev.winner != "")   # (Turf Defense: you win with your ally)
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
	if _turf:
		await _turf.farewell(won)
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
		Game.match_result.veterans = _over.get("veterans", [])   # cards that reached a new veteran tier
		Game.match_result.turf = _over.get("turf")               # the turf map influence won
		Game.match_result.series = _over.get("series")           # a Casual or Ranked best of 3: the score so far
		if _over.has("result"):
			Game.match_result.result = _over.result
		if _coop:
			_coop_result_into(Game.match_result, _over)
		elif _ffa:
			_ffa_result_into(Game.match_result, _over)
	Game.go("post_match")


# ── View helpers ─────────────────────────────────────────────────────────────

## MARKED CARDS (DuelState.reveals): while you have one, your opponents' hand and face-down cards show
## you their faces (CardView.peek: only how they look; whether they're face-up, and every rule, stays).
## Online the server sends what they are (onlineMatch.js viewFor); a card it hasn't sent stays a back.
func _update_peek() -> void:
	if duel == null or _watching():
		return
	var sees: bool = duel.reveals("player")
	# Turf Defense: your teammate's hand and face-down cards always show you their faces
	for ally in duel.sides:
		if ally == "player" or not duel._teammates("player", ally):
			continue
		var t: Dictionary = duel.sides[ally]
		for v in hand.get(ally, []):
			_peek(v, true, t.hand)
		for slot in field.get(ally, {}):
			var v = field[ally][slot]
			var c = t.field[slot]
			if v != null and is_instance_valid(v) and c != null:
				_peek(v, c.get("face_down", false), [c])
	for foe in duel.foes_of("player"):
		var s: Dictionary = duel.sides[foe]
		for v in hand.get(foe, []):
			_peek(v, sees, s.hand)
		for slot in field.get(foe, {}):
			var v = field[foe][slot]
			var c = s.field[slot]
			if v != null and is_instance_valid(v) and c != null:
				_peek(v, sees and c.get("face_down", false), [c])


func _peek(v: CardView, on: bool, pool: Array) -> void:
	if not is_instance_valid(v):
		return
	if on and not v.card.has("name"):
		for c in pool:
			if c is Dictionary and int(c.get("uid", -1)) == v.uid and c.has("name"):
				v.set_card(c)
				break
	v.peek = on and v.card.has("name")


func _new_view(c: Dictionary, side: String, up: bool) -> CardView:
	var v := CardView.new()
	cards_layer.add_child(v)
	v.board_scale = _sc(side)
	v.vets = _vets.get(side, {})
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
	v.cost_now = -1   # (a lowered cost is only shown in the hand)
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
		if side == "player" and (v == _hovered or v == _selected):   # (only your own hand lifts: a card just sent to theirs stays there)
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


## Settings → Screen Shake & Flashes: 1 full, 0.5 reduced, 0 off (0 in Photosensitive mode).
func _fx_level() -> float:
	return Game.flash_level()


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


## A brawl-only boost or cut: "+700 ATK" rises over the card with a pulse and a ring (green up, red down).
func _brawl_boost(v: CardView, delta: int, what: String) -> void:
	var up := delta > 0
	var col := Color(0.45, 1.0, 0.55) if up else Color(1.0, 0.4, 0.4)
	Sfx.play("effect", 1.4 if up else 0.8, -6.0)
	_ring(v.home, col, 0.9)
	_float_text(v.home + Vector2(0, -40), "%s%d %s" % ["+" if up else "-", absi(delta), what], col, 40)
	var s := v.scale
	var t := create_tween()
	t.tween_property(v, "scale", s * 1.08, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "scale", s, 0.16)
	await _wait(0.45)


## After a batch of events, a character left mid-animation goes back to its place: e.g. an attacker
## whose attack was negated (no brawl to bring it back down).
func _settle_board() -> void:
	var raised := false
	for side in field:
		for slot in field[side]:
			var v: CardView = field[side][slot]
			if v == null or v.busy or v == _hovered:
				continue
			if v.z_index >= 400:   # (lifted for an attack)
				v.z_index = 10
				v.go_home(0.22)
				raised = true
	if raised and _mode != "target":
		_clear_attack_line()


## While the player aims an attack, the arrow follows the mouse and locks onto valid targets.
func _update_aim() -> void:
	if _mode != "target" or not field.player.has(_selected_slot):
		if _arrow.visible and not _playing:
			_arrow.hide_arrow()
		return
	var m := Game.pad.pointer(self)
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
	var vp := get_viewport()   # (global_canvas_transform: a phone's frame in the middle, widescreen.gd)
	return (vp.global_canvas_transform * vp.get_canvas_transform() * world) / vp.get_visible_rect().size


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

## A one-line label made smaller (down to min_size) until its text fits its width.
func _fit_label(l: Label, max_size: int, min_size: int) -> void:
	var ls: LabelSettings = l.label_settings
	var f: Font = ls.font if ls.font else l.get_theme_font("font")
	var size := max_size
	while size > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > l.size.x:
		size -= 1
	ls.font_size = size


func _label(font_size: int, color: Color, heading := false) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	if heading:
		ls.font = _font
	if font_size < 20 and Game.mobile():   # (small print a little bigger on a phone, as UI.label)
		font_size = mini(font_size + 3, 20)
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = clampi(font_size / 8, 3, 8)
	ls.outline_color = Color(0, 0, 0, 0.78)
	ls.shadow_size = 1
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(0, maxf(1.0, font_size / 16.0))
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A soft light in a colour behind lettering (float text, banners): it sits behind its parent.
func _text_glow(box: Vector2, text_width: float, font_size: int, color: Color) -> TextureRect:
	var g := TextureRect.new()
	g.texture = _dot
	g.material = _add_mat
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.show_behind_parent = true
	g.modulate = Color(color, 0.4 * _fx_level())
	g.size = Vector2(text_width * 1.5 + 110.0, font_size * 2.8)
	g.position = (box - g.size) / 2.0
	return g


## Pop-in text that drifts up and fades (world coordinates = screen coordinates here).
func _float_text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var l := _label(font_size, color, true)
	var f := UI.font_of("title")
	l.label_settings.font = f
	l.text = text
	l.size = Vector2(700, font_size * 1.4)
	l.position = pos - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.scale = Vector2.ONE * 1.7
	if font_size >= 28 and _fx_level() > 0.0:
		l.add_child(_text_glow(l.size, f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font_size, color))
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
	var f := UI.font_of("title")
	l.label_settings.font = f
	l.text = text
	l.size = Vector2(400, 70)
	l.position = pos - l.size / 2
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.rotation = -0.18
	l.scale = Vector2.ONE * 2.6
	# The stamp's frame: a cut plate in the same ink, dark under the letters
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x + 44.0
	var frame := Panel.new()
	var sb := UI.box(Color(0.02, 0.02, 0.05, 0.62), color, 2, 8)
	sb.border_width = 3.0
	sb.depth = 0.0
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.show_behind_parent = true
	frame.size = Vector2(w, 60)
	frame.position = Vector2((400.0 - w) / 2.0, 6)
	l.add_child(frame)
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
	var band := Banner.new()
	band.size = Vector2(940, 72)
	band.position = Vector2(1080 - 470, DIVIDER_Y - 36)
	band.accent = Color(color, 0.95)
	band.fill = Color(0.02, 0.025, 0.06, 0.8)
	band.fade_l = 340.0
	band.fade_r = 340.0
	band.open = 0.0
	var l := _label(46, Color.WHITE, true)
	l.label_settings.font = UI.font_of("title")
	l.label_settings.shadow_color = Color(color.darkened(0.2), 0.85)
	l.label_settings.shadow_offset = Vector2(3, 3)
	l.text = text
	l.size = band.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	band.add_child(l)
	overlay.add_child(band)
	var t := create_tween().set_parallel()
	t.tween_property(band, "open", 1.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 1.0, 0.14)
	if _fx_level() > 0.0:
		t.tween_property(band, "sheen", 1.2, 0.45).from(-0.2)
	else:
		t.tween_interval(0.45)
	t.chain().tween_property(band, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(band.queue_free)
	await _wait(0.45)


func _sweep_banner(text: String, color: Color) -> void:
	# A band of dark glass that opens from the middle of the table, the words in the title lettering over a
	# shadow of the side's colour; a gleam runs along it while it holds, then it shuts
	var band := Banner.new()
	band.size = Vector2(1920, 138)
	band.position = Vector2(1080 - 960, DIVIDER_Y - 69)
	band.pivot_offset = band.size / 2
	band.accent = color
	band.fade_l = 540.0
	band.fade_r = 540.0
	band.edge = 3.0
	band.open = 0.0
	var l := _label(92, Color.WHITE, true)
	var f := UI.font_of("title")
	l.label_settings.font = f
	l.label_settings.outline_size = 5
	l.label_settings.outline_color = Color(color.darkened(0.75), 0.9)
	l.label_settings.shadow_size = 2
	l.label_settings.shadow_color = Color(color.darkened(0.1), 0.95)
	l.label_settings.shadow_offset = Vector2(5, 5)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 92).x
	if tw > 1240.0:   # (a long name: smaller, so it stays on the band)
		l.label_settings.font_size = int(92.0 * 1240.0 / tw)
		tw = 1240.0
	l.text = text
	l.size = band.size
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.scale = Vector2.ONE * 1.2
	l.modulate.a = 0.0
	if _fx_level() > 0.0:
		l.add_child(_text_glow(l.size, tw * 0.8, 92, color))
	band.add_child(l)
	overlay.add_child(band)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(band, "open", 1.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 1.0, 0.16)
	t.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(l, "scale", Vector2.ONE * 1.035, 0.55)   # (a slow push in while it holds)
	if _fx_level() > 0.0:
		t.tween_property(band, "sheen", 1.15, 0.55).from(-0.15)
	t.chain().tween_property(band, "scale:y", 0.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(band, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(band.queue_free)
	await t.finished


func _splash_name(card_name: String, color: Color, y := DIVIDER_Y) -> void:
	var l := _label(84, Color.WHITE, true)
	var f := UI.font_of("title")
	l.label_settings.font = f
	l.text = card_name.to_upper()
	l.size = Vector2(1200, 110)
	l.position = Vector2(1080 - 600, y - 55)
	l.pivot_offset = l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.label_settings.outline_color = Color(color.darkened(0.7), 0.92)
	l.label_settings.outline_size = 6
	l.label_settings.shadow_size = 2
	l.label_settings.shadow_color = Color(color, 0.95)
	l.label_settings.shadow_offset = Vector2(5, 5)
	if _fx_level() > 0.0:
		l.add_child(_text_glow(l.size, minf(900.0, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 84).x * 0.8), 84, color))
	l.modulate.a = 0.0
	overlay.add_child(l)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(l, "modulate:a", 1.0, 0.15)
	t.tween_property(l, "position:x", l.position.x - 40, 0.9)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(l.queue_free)


## An ability going off: a leaning plate that slides in from the side that played it, with the card's picture,
## what kind of card it is, its name, and what the effect just did (its keywords in their colours).
func _callout(c: Dictionary, text: String, side: String) -> void:
	if _ui.has("callout") and is_instance_valid(_ui.callout):
		_ui.callout.queue_free()
	var mine := side == "player"
	var col := _side_color(side)
	var tex: Texture2D = CardDB.art(str(c.get("art_url", c.get("id", "")))) if not c.is_empty() else null
	var width := 720.0
	var lean := 30.0
	var art_w := 226.0 if tex else 0.0   # (no picture when the call-out is not about a card)
	var text_x := art_w - 22.0 if tex else 40.0
	var text_w := width - text_x - 110.0
	var lines := UI.font_of("strong").get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, text_w, 20).y
	var h := maxf(126.0, 72.0 + lines + 18.0)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(width, h)
	var band := Banner.new()
	band.size = box.size
	band.accent = col
	band.fill = Color(0.03, 0.035, 0.085, 0.95)
	band.skew = lean
	band.fade_r = 190.0
	band.cap = 9.0
	box.add_child(band)
	if tex:
		box.add_child(_art_slice(tex, Vector2(9.0, 2.0), Vector2(art_w, h - 4.0), lean * (h - 4.0) / h, 96.0))
	# (each line starts on the plate's lean)
	var at := func(y: float) -> Vector2: return Vector2(text_x + lean * (0.5 - y / h), y)
	var kind := _label(15, col.lightened(0.35), true)
	kind.label_settings.font = UI.font_of("label")
	kind.label_settings.outline_size = 2
	kind.text = "  ".join(_callout_kind(c).split(""))   # (spaced out, as a caption)
	kind.position = at.call(11.0)
	kind.visible = c.has("name")   # (nothing to name: the caption would only say "EFFECT" twice)
	box.add_child(kind)
	var n := _label(31, Color.WHITE, true)
	n.label_settings.font = UI.font_of("title")
	n.text = str(c.get("name", "Effect")).to_upper()
	n.position = at.call(27.0)
	n.size = Vector2(text_w, 38)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(n)
	var line := ColorRect.new()
	line.color = Color(col, 0.7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = at.call(66.0)
	line.size = Vector2(64, 2)
	box.add_child(line)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.scroll_active = false
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.meta_underlined = false
	t.add_theme_font_override("bold_font", UI.font_of("strong"))
	t.add_theme_font_size_override("normal_font_size", 20)
	t.add_theme_font_size_override("bold_font_size", 20)
	t.add_theme_color_override("default_color", UI.TEXT)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("outline_size", 3)
	t.text = Keywords.markup(text)
	t.position = at.call(72.0)
	t.size = Vector2(text_w + 6.0, lines + 12.0)
	box.add_child(t)
	overlay.add_child(box)
	_ui.callout = box
	var x := 1080.0 - width / 2.0
	var from := -90.0 if mine else 90.0   # (it comes in from its player's side)
	box.position = Vector2(x + from, DIVIDER_Y - h / 2.0 + (70.0 if mine else -70.0))
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(box, "position:x", x, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.14)
	if _fx_level() > 0.0:
		tw.tween_property(band, "sheen", 1.2, 0.5).from(-0.2).set_delay(0.1)
	else:
		tw.tween_interval(0.6)
	tw.chain().tween_interval(0.68)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.3)
	tw.tween_property(box, "position:x", x - from * 0.35, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(box.queue_free)


## What a call-out names its card as.
func _callout_kind(c: Dictionary) -> String:
	match str(c.get("cardType", "")):
		"leader":
			return "LEADER ABILITY"
		"gang_member":
			return "ABILITY"
		"ambush":
			return "AMBUSH"
		"hustle":
			var sub := str(c.get("subtype", ""))
			return "EQUIP" if sub == "equip" else ("CONTINUOUS" if sub == "continuous" else "HUSTLE")
	return "EFFECT"


## A card's picture (the part of the card under its name) in a leaning window that fades out to the right.
func _art_slice(tex: Texture2D, at: Vector2, window: Vector2, lean: float, fade: float) -> Polygon2D:
	var p := Polygon2D.new()
	p.texture = tex
	p.position = at
	var ts := tex.get_size()
	var full := window.x + lean
	var uw := ts.x * 0.84
	var uh := minf(ts.y * 0.44, uw * window.y / full)
	var origin := Vector2(ts.x * 0.08, ts.y * 0.12)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for corner in [[0.0, 0.0, 1.0], [window.x - fade, 0.0, 1.0], [window.x, 0.0, 0.0], [window.x, 1.0, 0.0], [window.x - fade, 1.0, 1.0], [0.0, 1.0, 1.0]]:
		var px: float = corner[0] + lean * (0.5 - corner[1])
		pts.append(Vector2(px, corner[1] * window.y))
		uvs.append(origin + Vector2((px + lean / 2.0) / full * uw, corner[1] * uh))
		cols.append(Color(1, 1, 1, corner[2]))
	p.polygon = pts
	p.uv = uvs
	p.vertex_colors = cols
	p.polygons = [PackedInt32Array([0, 1, 4, 5]), PackedInt32Array([1, 2, 3, 4])]
	return p


## A card's ability going off, on the card itself: it swells and glows in its side's colour, four brackets
## lock on to it, and a ring and a few sparks leave it.
func _activate(v: CardView, col: Color) -> void:
	_pulse_glow(v, col)
	_ring(v.position, col, 0.95)
	_burst(v.position, col.lightened(0.3), 14, 240, 0.7, -320.0)
	var b := FxBrackets.new()
	b.half = CARD * v.scale / 2.0
	b.position = v.position
	b.rotation = v.rotation
	b.color = col.lightened(0.45)
	b.material = _add_mat
	b.gap = 46.0
	b.modulate.a = 0.0
	fx.add_child(b)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(b, "gap", 7.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "modulate:a", 1.0, 0.1)
	t.chain().tween_interval(0.32)
	t.chain().tween_property(b, "gap", 30.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(b, "modulate:a", 0.0, 0.26)
	t.chain().tween_callback(b.queue_free)
	if not v.busy:
		var s := v.scale
		var swell := create_tween()
		swell.tween_property(v, "scale", s * 1.07, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swell.tween_property(v, "scale", s, 0.22)


## The word for what was just played ("HUSTLE", "EQUIPPED") on a small leaning band that opens under it, the
## card's name below the word.
func _action_tag(pos: Vector2, word: String, color: Color, title := "") -> void:
	var f := UI.font_of("title")
	title = title.to_upper()
	var w := maxf(f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x, _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x) + 200.0
	var band := Banner.new()
	band.size = Vector2(w, 64.0 if title == "" else 94.0)
	band.position = pos - band.size / 2
	band.accent = color
	band.fill = Color(0.02, 0.025, 0.06, 0.86)
	band.skew = 22.0
	band.fade_l = 74.0
	band.fade_r = 74.0
	band.open = 0.0
	band.modulate.a = 0.0
	var l := _label(44, Color.WHITE, true)
	l.label_settings.font = f
	l.label_settings.shadow_color = Color(color.darkened(0.15), 0.9)
	l.label_settings.shadow_offset = Vector2(3, 3)
	l.text = word
	l.size = Vector2(w, 58)
	l.position.y = 3
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(l)
	if title != "":
		var n := _label(24, color.lightened(0.5), true)
		n.text = title
		n.size = Vector2(w, 30)
		n.position.y = 55
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		band.add_child(n)
	overlay.add_child(band)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(band, "open", 1.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(band, "modulate:a", 1.0, 0.1)
	if _fx_level() > 0.0:
		t.tween_property(band, "sheen", 1.2, 0.45).from(-0.2)
	else:
		t.tween_interval(0.45)
	t.chain().tween_interval(0.3)
	t.chain().tween_property(band, "modulate:a", 0.0, 0.3)
	t.tween_property(band, "position:y", band.position.y - 22.0, 0.3)
	t.chain().tween_callback(band.queue_free)


# ── HUD ──────────────────────────────────────────────────────────────────────

func _build_detail() -> void:
	var p: Panel = $HUD/UI/Detail
	# A phone: the card's text bigger, under a smaller picture, and on a wide screen the panel (and
	# the player's plate under it) reach into the room at the side (scripts/widescreen.gd)
	var phone := Game.mobile()
	var side := minf(Game.wide.margin.x, 240.0)
	for panel in [p, $HUD/UI/PlayerPanel]:
		panel.position.x -= side
		panel.size.x += side
	var w := p.size.x - 40
	var art_h := 420.0 if phone else 482.0
	var art := TextureRect.new()
	art.size = Vector2(art_h * 340.0 / 482.0, art_h)
	art.position = Vector2((p.size.x - art.size.x) / 2, 18)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.material = UI.card_material(art.size)
	p.add_child(art)
	var y := art_h + 24
	var title := _label(34 if phone else 30, Color.WHITE, true)
	title.position = Vector2(20, y)
	title.size = Vector2(w, 40)
	p.add_child(title)
	var kind := _label(_kind_size(), Color(0.62, 0.66, 0.82))
	kind.position = Vector2(20, y + 40)
	kind.size = Vector2(w, 22)
	p.add_child(kind)
	var stats := RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.scroll_active = false
	stats.position = Vector2(20, y + 66)
	stats.size = Vector2(w, 34)
	stats.add_theme_font_override("normal_font", _font)
	stats.add_theme_font_size_override("normal_font_size", 28 if phone else 24)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stats)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.position = Vector2(20, y + 104)
	text.size = Vector2(w, p.size.y - y - 104 - 14)
	text.add_theme_font_size_override("normal_font_size", UI.text_size(21 if phone else 16, false))
	text.add_theme_font_size_override("italics_font_size", UI.text_size(20 if phone else 15, false))
	text.add_theme_font_size_override("bold_font_size", UI.text_size(21 if phone else 16, false))
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
	tip_text.custom_minimum_size = Vector2(minf(w, 420.0) if phone else 300.0, 0)
	tip_text.add_theme_font_size_override("normal_font_size", UI.text_size(19 if phone else 15, false))
	tip_text.add_theme_font_size_override("bold_font_size", UI.text_size(21 if phone else 17, false))
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


const DETAIL_ART_MIN := 300.0   # the card panel's picture never gets smaller than this (the zoom shows it whole)

## The card panel laid out for the text it has: a long one (or a bigger Text Size) takes its room from
## the picture, and only scrolls once the picture is as small as it goes.
func _fit_detail() -> void:
	var p: Panel = $HUD/UI/Detail
	var text: RichTextLabel = _ui.detail_text
	var full := 420.0 if Game.mobile() else 482.0
	var room := p.size.y - (full + 24.0) - 104.0 - 14.0   # (the text's height under a full-size picture)
	var art_h := clampf(full - maxf(float(text.get_content_height()) + 6.0 - room, 0.0), DETAIL_ART_MIN, full)
	var art: TextureRect = _ui.detail_art
	if is_equal_approx(art.size.y, art_h):
		return
	art.size = Vector2(art_h * 340.0 / 482.0, art_h)
	art.position = Vector2((p.size.x - art.size.x) / 2, 18)
	(art.material as ShaderMaterial).set_shader_parameter("quad_size", art.size)
	var y := art_h + 24.0
	_ui.detail_title.position.y = y
	_ui.detail_kind.position.y = y + 40
	_ui.detail_stats.position.y = y + 66
	text.position.y = y + 104
	text.size.y = p.size.y - y - 104 - 14


## The card panel's type line ("CHARACTER · NEBULA · AUTHORITY 3"): bigger on a phone.
func _kind_size() -> int:
	return 18 if Game.mobile() else 15


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

const STATUS_WORDS := {"guarded": "CAN'T BE ATTACKED", "poison": "POISON", "burn": "BURN", "bleed": "BLEED", "freeze": "FREEZE",
	"stasis": "STASIS", "stun": "STUN", "blind": "BLIND", "shield": "SHIELD", "suppress": "SUPPRESS", "downed": "DOWNED",
	"resting": "CAN'T ATTACK THIS TURN (just promoted or Awakened)", "bounty": "BOUNTY"}
## Statuses that aren't keywords (keywords use their own colour, and explain themselves when hovered)
const STATUS_COLORS := {"downed": "ff5a5a", "resting": "ffb35a", "guarded": "a0d8ff"}


## How long a status has left, after its name in the card panel: " (this turn)", " (2 turns)"
func _status_left(c: Dictionary, k: String) -> String:
	var left := CardView.status_turns(c, k)
	if left <= 0:
		return ""
	return " [color=#8a8aa0](%s)[/color]" % ("this turn" if left == 1 and not c.get(k) is Dictionary else "%d turn%s" % [left, "" if left == 1 else "s"])


## A status in the card panel, in its colour: "DOWNED" red, "STASIS" violet...
func _status_word(k, amt := "") -> String:
	var word: String = STATUS_WORDS.get(k, str(k).to_upper())
	if amt != "":   # (its number: "BURN 200")
		word += " " + amt
	var kw := Keywords.find(word)
	if kw != "" and STATUS_COLORS.get(k) == null:
		return "[url=%s][b][color=#%s]%s[/color][/b][/url]" % [kw, Keywords.color(kw).to_html(false), word]
	var col: String = Keywords.CB_STATUS[str(k).to_upper()].to_html(false) if Keywords.cb() and Keywords.CB_STATUS.has(str(k).to_upper()) \
		else STATUS_COLORS.get(k, "e6e6f0")
	if Keywords.STATUS_HELP.has(str(k).to_upper()):   # (DOWNED, CAN'T ATTACK YET: explained when hovered too)
		return "[url=%s][b][color=#%s]%s[/color][/b][/url]" % [str(k).to_upper(), col, Keywords._escape(word)]
	return "[b][color=#%s]%s[/color][/b]" % [col, Keywords._escape(word)]


func _show_detail(c: Dictionary, live_stats := [], live_status := []) -> void:
	# (nothing hovered: the last card played and what just happened, else the player's own card back)
	var mine := duel != null and duel.sides.has("player")
	var key := "%s:%s:%s:%d" % [c.get("uid", c.get("id", "")), live_stats, live_status, CardView.turn_now] if not c.is_empty() \
		else "idle:%s:%s:%d" % [_back_clan("player") if mine else "", _last_played.get("card", {}).get("uid", ""), _log_lines]
	if key == _detail_key:
		return
	_detail_key = key
	if c.is_empty() and not _last_played.is_empty():
		_show_idle()
		return
	if c.is_empty():
		_detail_spin = CardDB.back_style(_back_clan("player")) if mine else ""
		for style in CardDB.BACK_STYLES.values():
			_ui.detail_art.material.set_shader_parameter(style, 1.0 if style == _detail_spin else 0.0)
		UI.rarity_fx(_ui.detail_art.material, 1)
		_ui.detail_art.texture = _back_for("player") if mine else null
		_ui.detail_title.text = ""
		_ui.detail_kind.text = ""
		_ui.detail_stats.text = ""
		_ui.detail_text.text = "\n".join(["[color=#8a8aa0]%s[/color]" % UI.touch_words("Hover a card to see it here. Right-click it to zoom in.")] + _rival_leader_lines())
		_fit_detail()
		return
	var tex := CardDB.art_for(c)   # (a token shows the same one of its artworks as on the field)
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
	if Game.mobile():   # (bigger on a phone: a long name shrinks to fit)
		_fit_label(_ui.detail_title, 34, 22)
	var token: bool = c.get("token", false) or CardDB.get_card(str(c.get("id", ""))).get("token", false)
	var parts: Array = ["TOKEN" if token else TYPE_NAMES.get(c.get("cardType", ""), "CARD")]
	if c.get("subtype") is String and not token:
		parts.append(str(c.subtype).to_upper())
	if str(c.get("clanName", "")) != "":
		parts.append(str(c.clanName).to_upper())
	if not token:   # (a token isn't played from the hand: no cost)
		parts.append("AUTHORITY %d" % int(c.get("authority", 0)))
	_ui.detail_kind.text = "  ·  ".join(parts)
	_ui.detail_kind.label_settings.font_color = Color(0.62, 0.66, 0.82)   # (the idle panel colours it by side)
	_fit_label(_ui.detail_kind, _kind_size(), 10)
	if c.get("cardType") in ["gang_member", "leader"]:
		var base_atk := int(c.get("base_attack", c.get("attack", 0)))
		var base_def := int(c.get("base_defense", c.get("defense", 0)))
		var atk: int = live_stats[0] if live_stats.size() >= 2 else base_atk
		var def: int = live_stats[1] if live_stats.size() >= 2 else base_def
		_ui.detail_stats.text = "[color=#%s]ATK %d%s[/color]   [color=#%s]DEF %d%s[/color]" % [
			CardView._stat_color(atk, base_atk, "ffd86b"), atk, CardView._stat_mark(atk, base_atk),
			CardView._stat_color(def, base_def, "9ddcff"), def, CardView._stat_mark(def, base_def)]
	else:
		_ui.detail_stats.text = ""
	var body := Keywords.markup(str(c.get("effectText", "")))
	if not live_status.is_empty():
		var words: Array = live_status.map(func(k): return _status_word(k, CardView.status_amount(c, str(k))) + _status_left(c, str(k)))
		body = "[color=#8a8aa0]Status:[/color] %s\n\n%s" % ["[color=#8a8aa0]  ·  [/color]".join(words), body]
	if c.get("flavourText") is String:
		body += "\n\n[i][color=#8a8aa0]%s[/color][/i]" % c.flavourText
	if c.get("note") is String:   # (where the card is: shown above its text, not part of it)
		body = "[color=#8a8aa0]%s[/color]\n\n%s" % [Keywords._escape(c.note), body]
	_ui.detail_text.text = body
	_fit_detail()


## Nothing hovered, once a card has been played: that card ("LAST PLAYED · OPPONENT"), the last few
## things that happened, and when the rival leader Awakens (or that it already has).
func _show_idle() -> void:
	var c: Dictionary = _last_played.card
	var side: String = _last_played.side
	var tex := CardDB.art_for(c)
	_ui.detail_art.texture = tex if tex else _back_for(side)
	UI.rarity_fx(_ui.detail_art.material, int(c.get("rarity", 1)) if tex else 1, 0.37)
	_detail_spin = ""
	for style in CardDB.BACK_STYLES.values():
		_ui.detail_art.material.set_shader_parameter(style, 0.0)
	_ui.detail_title.text = str(c.get("name", "?"))
	if Game.mobile():
		_fit_label(_ui.detail_title, 34, 22)
	_ui.detail_kind.text = "LAST PLAYED  ·  %s" % _who(side).to_upper()
	_ui.detail_kind.label_settings.font_color = _side_color(side)
	if c.get("cardType") in ["gang_member", "leader"]:
		_ui.detail_stats.text = "[color=#ffd86b]ATK %d[/color]   [color=#9ddcff]DEF %d[/color]" % [int(c.get("attack", 0)), int(c.get("defense", 0))]
	else:
		_ui.detail_stats.text = ""
	var lines: Array = []
	for r in _recent:
		lines.append("[color=%s]%s[/color]" % [r[0], Keywords._escape(str(r[1]))])
	_ui.detail_text.text = "\n".join(lines + _rival_leader_lines())
	_fit_detail()


## When the rival leader Awakens (or that it already has): for the idle card panel.
func _rival_leader_lines() -> Array:
	var rival := "boss" if _coop else "" if _ffa else "opponent"
	if rival == "" or duel == null or not duel.sides.has(rival) or not duel.sides[rival].get("leader") is Dictionary:
		return []
	var ld: Dictionary = duel.sides[rival].leader
	var who := str(_names.get(rival, "Rival")) if _coop else "Rival"
	if not duel.leader_dormant(rival):
		return ["[color=#ff8a94]%s leader %s is on the field.[/color]" % [who, Keywords._escape(str(ld.get("name", "")))]]
	for line in str(ld.get("effectText", "")).split("\n"):
		if line.begins_with("AWAKEN"):
			return ["[color=#8a8aa0]%s leader %s: %s[/color]" % [who, Keywords._escape(str(ld.get("name", ""))),
				Keywords._escape(line.trim_prefix("AWAKEN:").strip_edges())]]
	return []


## stars: a turf map gang's rating (1..5), along the bottom of its picture.
## "NEBULA  ·  MASTERY 7": a player's mastery with their deck's clan, small, in its colour, on their plate
func _clan_line(p: Panel, prof) -> void:
	if not prof is Dictionary or not prof.get("clan") is String or prof.get("clan_level") == null:
		return
	var clan := CardDB.clan(str(prof.clan))
	var l := _label(12, clan.get("color", GOLD), true)
	l.text = "%s  ·  MASTERY %d" % [str(clan.get("name", prof.clan)).to_upper(), int(prof.clan_level)]
	l.position = Vector2(92, 66)
	p.add_child(l)


func _build_panel(side: String, p: Panel, display_name: String, avatar: String, subtitle: String, level := 0, stars := 0) -> void:
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
	if stars > 0:
		var rating := _label(12, GOLD, true)
		rating.text = "★".repeat(clampi(stars, 1, 5))
		rating.label_settings.outline_size = 5
		rating.label_settings.outline_color = Color(0, 0, 0, 0.95)
		rating.size = Vector2(64, 16)
		rating.position = Vector2(14, 62)
		rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(rating)
	var n := _label(26, Color.WHITE, true)
	n.text = display_name
	n.position = Vector2(92, 10)
	if display_name.length() > 12:   # (a long name, e.g. a turf gang's: smaller, so it fits)
		n.label_settings.font_size = 26 if display_name.length() <= 12 else 21 if display_name.length() <= 15 else 18
		n.position.y = 14
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
	var to_w := full * clampf(float(value) / _max_morale(side), 0.0, 1.0)
	if _turf and side == "boss" and value > 0 and value <= _max_morale(side) / 5.0:
		_turf.say("low")
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
		var auth: int = c.authority + (int(c.get("hidden_spend", 0)) if side != "player" and not duel.reveals("player") else 0)
		p.auth.text = "AUTHORITY   %d / %d" % [auth, maxi(c.authority_max, auth)]
		p.piles.text = "HAND %d    ·    DECK %d" % [c.hand, c.deck]
	queue_redraw()


func _build_phase_bar() -> void:
	var p: Panel = $HUD/UI/PhaseBar
	var cap := _label(13, Color(0.55, 0.57, 0.7))
	cap.text = "PHASE"
	cap.position = Vector2(16, 12)
	p.add_child(cap)
	# The turn's three phases as a track: a line down their marks, the one being played lit in its side's colour
	var track := Control.new()
	track.position = Vector2(0, 34)
	track.size = Vector2(p.size.x, PHASE_ROW * PHASE_NAMES.size())
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.draw.connect(_draw_phase_track.bind(track))
	p.add_child(track)
	_ui.phase_track = track
	_ui.phase_labels = {}
	var i := 0
	for key in PHASE_NAMES:
		var l := _label(26, Color(1, 1, 1, 0.5), true)
		l.text = PHASE_NAMES[key]
		l.position = Vector2(54, track.position.y + i * PHASE_ROW)
		l.size = Vector2(p.size.x - 62, PHASE_ROW)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		_ui.phase_labels[key] = l
		i += 1
	var next := Button.new()
	next.position = Vector2(14, p.size.y - 92)
	next.size = Vector2(p.size.x - 28, 76)
	next.add_theme_font_override("font", _font)
	next.add_theme_font_size_override("font_size", 28)
	next.pressed.connect(_on_next)
	p.add_child(next)
	var hint := _label(12, Color(0.55, 0.57, 0.7))
	hint.text = "SPACE"
	hint.visible = not Game.mobile()   # (no keyboard on a phone)
	hint.position = Vector2(p.size.x - 62, p.size.y - 112)
	p.add_child(hint)
	_ui.next = next
	_update_next_btn()


const PHASE_ROW := 52.0   # a phase's row on the track
var _phase_shown := ""     # the phase the track shows (what's on screen: the engine may be further on)
var _phase_side := ""      # ...and whose turn it is


## The phase on show, and whose turn it's in (side "": as it was).
func _set_phase_ui(phase: String, side := "") -> void:
	_phase_shown = phase
	if side != "":
		_phase_side = side
	for key in _ui.phase_labels:
		var l: Label = _ui.phase_labels[key]
		l.label_settings.font_color = Color.WHITE if key == phase else Color(1, 1, 1, 0.5)
	if _ui.has("phase_track"):
		_ui.phase_track.queue_redraw()
	_update_next_btn()


## The track beside the phase names: a diamond a phase, joined by a line. The phase being played has a
## band of its side's colour behind it and a bright mark; the ones done are filled, the ones to come hollow.
func _draw_phase_track(t: Control) -> void:
	var keys: Array = PHASE_NAMES.keys()
	var at := keys.find(_phase_shown)
	var col: Color = BLUE if _phase_side in ["", "player"] else _side_color(_phase_side)
	var x := 32.0
	var y := func(i: int) -> float: return PHASE_ROW * (i + 0.5)
	t.draw_line(Vector2(x, y.call(0)), Vector2(x, y.call(keys.size() - 1)), Color(1, 1, 1, 0.16), 2.0)
	if at > 0:
		t.draw_line(Vector2(x, y.call(0)), Vector2(x, y.call(at)), Color(col, 0.7), 2.0)
	for i in keys.size():
		var c := Vector2(x, y.call(i))
		if i == at:
			var band := Rect2(8, PHASE_ROW * i + 3, t.size.x - 16, PHASE_ROW - 6)
			t.draw_polygon(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]),
				PackedColorArray([Color(col, 0.42), Color(col, 0.0), Color(col, 0.0), Color(col, 0.42)]))
			t.draw_rect(Rect2(band.position, Vector2(4, band.size.y)), col.lightened(0.2))
			t.draw_circle(c, 15.0, Color(col, 0.22))
		var rad := 9.5 if i == at else 6.5
		var dia := PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)])
		if i == at:
			t.draw_colored_polygon(dia, col.lightened(0.55))
		elif i < at:
			t.draw_colored_polygon(dia, col.darkened(0.25))
		else:
			t.draw_colored_polygon(dia, Color(0.05, 0.06, 0.12))
			dia.append(dia[0])
			t.draw_polyline(dia, Color(1, 1, 1, 0.4), 1.5, true)


func _update_next_btn() -> void:
	if not _ui.has("next") or duel == null:
		return
	var b: Button = _ui.next
	if _watching():
		b.disabled = true   # a replay or a friend's match: only watching
		b.text = "WATCHING" if _spectating else "REPLAY"
		_style_next()
		return
	var mine := duel.active == "player" and not "player" in ai_sides
	b.disabled = not mine or duel.winner != "" or not duel.pending.is_empty() or _awaiting or not _tut_ok({"kind": "next"})
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
	_style_next()


## The button's look: a lit plate when the move is yours (gold to end the turn, blue to go on a phase), and
## a dark one that still reads when it isn't. Its words shrink to fit ("YOU'RE OUT · 3RD PLACE").
func _style_next() -> void:
	var b: Button = _ui.next
	var accent: Color = GOLD if b.text.begins_with("END TURN") else BLUE
	if not b.disabled and duel != null and duel.active != "player":
		accent = _side_color(str(duel.active))
	var look := "%s:%s:%s" % [accent.to_html(), b.disabled, b.text]
	if _ui.get("next_look", "") == look:
		return
	_ui.next_look = look
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, UI.button_box(accent, state, true))
	var off := UI.box(Color(0.05, 0.055, 0.1, 0.92), Color(1, 1, 1, 0.2), 2, 8)
	off.trim = false
	off.depth = 0.4
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.82, 0.84, 0.95, 0.62))
	var font_size := 28
	while font_size > 15 and _font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > b.size.x - 22:
		font_size -= 1
	b.add_theme_font_size_override("font_size", font_size)


## Under the phase panel, for as long as it lasts: whose move it is ("YOUR MOVE", or "<NAME> IS
## DECIDING…"), and online, the server's clock as a ring round the seconds left. It turns red in the last
## 15 seconds and beats in the last 10 of your own.
func _build_status() -> void:
	var box := Control.new()
	box.position = Vector2(1650, 652)
	box.size = Vector2(246, 240)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD/UI.add_child(box)
	var ring := Control.new()
	ring.position = Vector2(61, 0)
	ring.size = Vector2(124, 124)
	ring.pivot_offset = ring.size / 2
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(_draw_clock_ring.bind(ring))
	box.add_child(ring)
	var secs := _label(46, Color.WHITE, true)
	secs.size = ring.size
	secs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	secs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(secs)
	var plate := PanelContainer.new()   # (edged in the colour of whoever is deciding)
	var sb := _box(Color(0.02, 0.02, 0.06, 0.84), BLUE, 2, 10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	plate.add_theme_stylebox_override("panel", sb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size = Vector2(246, 0)
	plate.pivot_offset = Vector2(123, 22)
	box.add_child(plate)
	var who := _label(24, BLUE, true)
	who.custom_minimum_size = Vector2(226, 0)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate.add_child(who)
	_ui.status = box
	_ui.status_plate = plate
	_ui.status_ring = ring
	_ui.status_secs = secs
	_ui.status_who = who
	_ui.status_sec = -1
	_ui.status_color = BLUE


func _draw_clock_ring(ring: Control) -> void:
	var c := ring.size / 2
	var r := 52.0
	ring.draw_circle(c, r + 9.0, Color(0.02, 0.02, 0.06, 0.8))
	ring.draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.12), 8.0, true)
	var k := clampf(_clock_left / ONLINE_TURN_SECS, 0.0, 1.0)
	if k > 0.0:
		ring.draw_arc(c, r, -PI / 2, -PI / 2 + TAU * k, 72, _ui.status_color, 8.0, true)


## Who has to act now: whoever a prompt is waiting on, else whoever's turn it is.
func _acting_side() -> String:
	if not duel.pending.is_empty() and str(duel.pending.get("side", "")) != "":
		return str(duel.pending.side)
	return duel.active


func _update_status() -> void:
	if not _ui.has("status"):
		return
	var shown: bool = duel.winner == "" and _mode != "over" and _replay.is_empty()
	_ui.status.visible = shown
	if not shown:
		return
	var side := _acting_side()
	var mine: bool = side == "player" and not _spectating
	var away: bool = _online and _ui.get("away", false)
	var text: String
	var col: Color
	if mine:
		text = "YOUR CHOICE" if not duel.pending.is_empty() else "YOUR MOVE"
		col = BLUE
	else:
		var name := str(_names[side]).to_upper() if _names.has(side) else ("OPPONENT" if _online and not side in ai_sides else "CPU")
		text = ("%s IS AWAY…" if away else "%s IS DECIDING…") % name
		col = RED if away else _side_color(side) if side != "opponent" or _ffa else GOLD
	var who: Label = _ui.status_who
	var plate: PanelContainer = _ui.status_plate
	if who.text != text:   # (a new name pops in)
		who.text = text
		who.label_settings.font_color = col
		(plate.get_theme_stylebox("panel") as Plate).border_color = col
		plate.reset_size()
		plate.scale = Vector2.ONE * 1.12
		plate.create_tween().tween_property(plate, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The clock (online only; offline nobody is timed): the words sit under it, or alone in its place
	var ring: Control = _ui.status_ring
	ring.visible = _online and not _watching()
	plate.position.y = 134.0 if ring.visible else 60.0
	if not ring.visible:
		return
	var left := ceili(_clock_left)
	_ui.status_color = RED if _clock_left < 15.0 else col
	var secs: Label = _ui.status_secs
	secs.text = str(left)
	secs.label_settings.font_color = RED if _clock_left < 15.0 else Color.WHITE
	ring.queue_redraw()
	if left != int(_ui.status_sec):
		_ui.status_sec = left
		if mine and left <= 10 and left > 0:   # (your last ten seconds: it beats)
			ring.scale = Vector2.ONE * 1.12
			ring.create_tween().tween_property(ring, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			Sfx.play("click", 1.5 + (10 - left) * 0.03, -12.0)


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


## The arena's background sound (arenas.json "ambience": rain only where it rains; "" = none)
var _ambience := "city_rain"


## The duel's music and the street around it (Game.sound); the neon starts acting up.
func _play_music() -> void:
	Game.sound.music("duel", 2.0)
	Game.sound.ambience(_ambience)
	_neon_loop()


func _make_theme() -> Theme:
	# The menus' look (UI.theme: the plates, the buttons, the fonts), with the table's own sizes
	var th := Theme.new()
	th.default_font = UI.font_of("body")
	th.default_font_size = 18
	var panel := _box(UI.PLATE, UI.STEEL, 2, 10)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "Button", UI.button_box(BLUE, state))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", UI.TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.8, 0.93, 1.0))
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	th.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.5))
	th.set_constant("outline_size", "Button", 2)
	th.set_font("font", "Button", _font)
	th.set_font_size("font_size", "Button", 21)
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.9, 1.0))
	return th


func _box(bg: Color, border: Color, width: int, radius: int) -> Plate:
	var sb := UI.box(bg, border, width, radius)   # (the game's plate: scripts/ui/plate.gd)
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
	if ResourceLoader.exists("res://assets/arena_paint.png") and ResourceLoader.exists("res://assets/arena_1v1.jpg"):
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
		var can_activate := not duel.activations("player", slot).is_empty() or _set_ready(slot) or duel.can_flip("player", slot)
		if ready or can_activate:
			# Gold: can act. Teal pulse: an ability can be activated (gold to teal when both)
			field.player[slot].glow_color = GOLD if ready else TEAL
			field.player[slot].glow = 0.9
			if can_activate:
				field.player[slot].pulse_color = TEAL
			moves += 1
	_gutter_glow = not _gutter_ready().is_empty()
	if _gutter_glow:
		moves += 1
	queue_redraw()
	_nudge_next(moves == 0)


## Your Gutter's cards that can use a Gutter ability now: [[card, k], ...] (newest first).
func _gutter_ready() -> Array:
	var out: Array = []
	if duel == null or duel.active != "player" or not duel.sides.has("player"):
		return out
	var g: Array = duel.sides.player.gutter
	for i in range(g.size() - 1, -1, -1):
		var c = g[i]
		if not c is Dictionary or not c.has("uid"):
			continue
		for k in duel.gutter_activations("player", int(c.uid)):
			if _tut_ok({"kind": "gutter", "uid": int(c.uid), "fx": k}):
				out.append([c, k])
	return out


## "USE  (2 AUTHORITY)": the button for a Gutter card's k-th Gutter ability.
func _gutter_label(c: Dictionary, k: int, numbered: bool) -> String:
	var e: Dictionary = duel.fx_groups(c, "gutter")[k - 1][0]
	var n: int = maxi(1, int(e.get("cost_n", 1)))
	var cost: String = {"authority": "%d AUTHORITY" % n, "morale": "%d MORALE" % n, "discard": "DISCARD %d" % n,
		"sacrifice": "SACRIFICE AN ALLY", "exile_gutter": "EXILE %d OTHER%s" % [n, "" if n == 1 else "S"], "exile_self": "EXILE IT"}.get(str(e.get("cost", "")), "")
	return "USE%s%s" % [" %d" % k if numbered else "", "  (%s)" % cost if cost != "" else ""]


var _next_pulse: Tween = null
var _gutter_glow := false   # a card in your Gutter can use its Gutter ability (the pile glows teal)


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
	if str(p.get("key", "")) == "mulligan":
		_show_mulligan(p)
		return
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
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.96), PROMPT_EDGE, 2, 12))
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


## The opening hand: its cards laid out large to look over (hover one to read it), then keep them, or
## shuffle them back and draw again. KEEP is always on the left; the engine's suggestion is the lit one.
func _show_mulligan(p: Dictionary) -> void:
	_cancel_interaction()
	_mode = "choose"
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.97), PROMPT_EDGE, 2, 14))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var title := _label(40, GOLD, true)
	title.text = "YOUR OPENING HAND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var suggested := str(p.options[0].id) if not p.options.is_empty() else "keep"
	var sub := _label(19, Color(0.78, 0.8, 0.92))
	sub.text = "Keep it, or shuffle it back into your deck and draw again. You get this choice once."
	if suggested == "redraw":   # (the rule: no Gang Member of 2 Authority or less)
		sub.text = "No Gang Member here costs 2 Authority or less, so a redraw may serve you better. You get this choice once."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var cards: Array = hand.get("player", []).filter(func(v): return is_instance_valid(v)).map(func(v): return v.card)
	if cards.is_empty() and duel != null:   # (not dealt on screen yet: the hand itself)
		cards = duel.sides.get("player", {}).get("hand", [])
	var fan := HBoxContainer.new()
	fan.alignment = BoxContainer.ALIGNMENT_CENTER
	fan.add_theme_constant_override("separation", 14)
	col.add_child(fan)
	var size := CARD * (1.4 if cards.size() <= 5 else 1.15)
	var i := 0
	for c in cards:
		if not c is Dictionary:
			continue
		var b := TextureButton.new()
		b.texture_normal = CardDB.art_for(c)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = size
		b.pivot_offset = size / 2
		b.mouse_entered.connect(func():
			_show_detail(c)
			Sfx.play("click", 1.4, -12.0)
			b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.07, 0.1))
		b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
		b.pressed.connect(func(): _show_detail(c))
		fan.add_child(b)
		# (dealt out one after another)
		b.modulate.a = 0.0
		b.scale = Vector2.ONE * 0.86
		var deal := b.create_tween().set_parallel()
		deal.tween_property(b, "modulate:a", 1.0, 0.2).set_delay(0.08 + i * 0.07)
		deal.tween_property(b, "scale", Vector2.ONE, 0.28).set_delay(0.08 + i * 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	var hint := _label(15, Color(0.7, 0.72, 0.85))
	hint.text = "Hold a card to read it" if Game.mobile() else "Hover a card to read it"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var options: Array = p.options.duplicate()
	options.sort_custom(func(a, b): return str(a.id) == "keep" and str(b.id) != "keep")
	for o in options:
		var id := str(o.id)
		var b := Button.new()
		b.text = "KEEP THIS HAND" if id == "keep" else "SHUFFLE AND REDRAW" if id == "redraw" else str(o.label)
		b.custom_minimum_size = Vector2(340, 64)
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 28)
		UI.tint_button(b, GOLD if id == suggested else BLUE, id == suggested)
		UI.juice(b)
		b.pressed.connect(_pick.bind(id))
		row.add_child(b)
	overlay.add_child(box)
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1080 - sz.x / 2, clampf(DIVIDER_Y - sz.y / 2, 10, 1070 - sz.y))
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.15)
	_menu = box
	Sfx.play("draw", 1.2, -6.0)


## A search (or Gutter) pick: the cards laid out to choose from, like a pile's view. Hovering one
## shows it in the card panel; click to take it, or SKIP.
func _show_card_choice(p: Dictionary) -> void:
	_cancel_interaction()
	_mode = "choose"
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.97), PROMPT_EDGE, 2, 12))
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
	hint.text = "Hold a card to read it  ·  tap to take it" if Game.mobile() else "Hover a card to read it  ·  click to take it"
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
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.94), PROMPT_EDGE, 2, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var title := _label(18, Color.WHITE, true)
	title.text = "%s  ·  %s" % [p.prompt, UI.touch_words("click a glowing card")]
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
	_gutter_glow = false
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
		if _press and not _dragging and Game.pad.pointer(self).distance_to(_press_pos) > 14.0:
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
				Game.set_setting("window_mode", "fullscreen" if Game.settings.window_mode == "windowed" else "windowed")


## Controller support (scripts/pad.gd): the cards and spots on the board the D-pad can go to
## (canvas coordinates). Nothing while a menu is open, so the D-pad stays on its buttons.
func pad_targets() -> Array:
	var out: Array = []
	if _mode in ["menu", "over"]:
		return out
	for v in hand.player:
		if is_instance_valid(v) and not v.busy:
			out.append(v.get_global_transform() * Rect2(-CARD / 2, CARD))
	for side in field:
		for slot in field[side]:
			if is_instance_valid(field[side][slot]):
				out.append(field[side][slot].get_global_transform() * Rect2(-CARD / 2, CARD))
	for side in leaders:
		if is_instance_valid(leaders[side]):
			out.append(leaders[side].get_global_transform() * Rect2(-CARD / 2, CARD))
	for side in _sides:
		var size := CARD * _sc(side)
		for pile in (["gutter", "deck", "hideout"] if side == "player" else ["gutter", "deck"]):
			out.append(Rect2(pile_pos(side, pile) - size / 2, size))
		for slot in 10:   # empty spots a card can be deployed to or chosen
			if _valid.has("%s:%d" % [side, slot]) and not field.get(side, {}).has(slot):
				out.append(Rect2(slot_pos(side, slot) - size / 2, size))
	return out


## Opens the big view of the card under the mouse (face-up ones, and your own face-down ones).
func _zoom_hovered() -> bool:
	var v := _view_at(Game.pad.pointer(self))
	if v == null or v.card.is_empty() or not (v.face_up or v.peek or v.side == "player"):
		return false
	var base := CardDB.get_card(str(v.card.get("id", "")))
	var zc: Dictionary = (base if not base.is_empty() else v.card).duplicate()
	zc.live_status = _live_statuses(v)   # (the zoom explains its statuses too: DOWNED, STASIS, ...)
	zc.veteran = v.veteran   # (its owner's frame, not yours)
	if _vet_xp.has(v.side) and not v.card.get("token", false):
		zc.vet_xp = int(_vet_xp[v.side].get(str(v.card.get("id", "")), 0))   # (and its owner's card XP)
	zc.mine = v.side == "player" and _replay.is_empty() and not _spectating   # (yours: the zoom shows its card XP)
	if v.card.has("uid"):
		zc.uid = v.card.uid   # (a token zooms in on the same one of its artworks as on the field)
	UI.card_zoom($HUD/UI, zc)
	return true


## Whether a finger here (viewport coordinates) is on something of the board's own, a card, a pile or a
## slot: touch.gd then keeps the tap there instead of giving it to a button just beside it.
func touch_owns(at: Vector2) -> bool:
	var p := get_global_transform_with_canvas().affine_inverse() * at
	return _view_at(p) != null or not _pile_at(p).is_empty() or _sides.any(func(s): return _slot_at(s, p) != -1)


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
	var m := Game.pad.pointer(self)
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
		if not v.face_up and (v.side == "player" or v.peek) and not v.card.is_empty():
			_show_detail(v.card, v.stats(), _live_statuses(v))   # your own face-down card (or one MARKED shows you)
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
				shown.note = UI.touch_words("Top of the Gutter · click to see every card in it")
				if side == "player" and _gutter_glow:
					shown.note = UI.touch_words("A Gutter ability is ready · click your Gutter to use it")
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
						UI.touch_words("  ·  click to see them") if pile == "hideout" and side == "player" and n > 0 else ""]})


func _on_press() -> void:
	if _mode == "over":
		return
	var m := Game.pad.pointer(self)
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
		if is_instance_valid(v) and v.hit(Game.pad.pointer(self)):
			_open_hand_menu(v)


## "ACTIVATE  (2 AUTHORITY)": the menu entry for the card's k-th activated ability (Card Forge).
func _activate_label(slot: int, k: int, numbered: bool) -> String:
	var e: Dictionary = duel.activate_groups(duel.card_at("player", slot))[k - 1][0]
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
	var can_attack := duel.can_attack_with("player", slot) and _tut_attack_ok(slot)
	if can_attack:
		opts.append(["ATTACK", true, _begin_target.bind(slot)])
	if duel.can_change_position("player", slot) and _tut_ok({"kind": "position", "slot": slot}):
		var to_def: bool = duel.card_at("player", slot).position == "atk"
		opts.append(["CHANGE TO DEF" if to_def else "CHANGE TO ATK  (FLIP FACE-UP)" if duel.card_at("player", slot).face_down else "CHANGE TO ATK",
			true, _field_action.bind({"kind": "position", "slot": slot})])
	if duel.can_promote("player", slot) and _tut_ok({"kind": "promote", "slot": slot}):
		opts.append(["PROMOTE", true, _field_action.bind({"kind": "promote", "slot": slot})])
	if duel.can_use_ability("player", slot) and _tut_ok({"kind": "ability", "slot": slot}):
		opts.append(["BUFF A LIONS ALLY  (+400 / +400)", true, _field_action.bind({"kind": "ability", "slot": slot})])
	var abilities: Array = duel.activations("player", slot) if _tut_ok({"kind": "activate", "slot": slot}) else []
	for k in abilities:
		opts.append([_activate_label(slot, k, abilities.size() > 1), true, _field_action.bind({"kind": "activate", "slot": slot, "fx": k})])
	if duel.can_flip("player", slot) and _tut_ok({"kind": "flip", "slot": slot}):   # a Continuous Ambush set on an earlier turn: turn it face-up now
		opts.append(["FLIP %s FACE-UP" % str(c.get("name", "")).to_upper(), true, _field_action.bind({"kind": "flip", "slot": slot})])
	var reason := ""
	var set_card = duel.card_at("player", slot)
	if set_card != null and duel.set_hustle_slot("player", set_card) == slot and _tut_ok({"kind": "hustle", "uid": int(set_card.uid)}):
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
		if _tutorial and _tutorial.active:
			_tutorial.nudge()   # (not the move the coach is asking for)
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


# ── The tutorial's strict steps (scripts/duel/tutorial.gd): only the asked-for move is offered ──

## Outside the tutorial's lessons, everything is.
func _tut_ok(a: Dictionary) -> bool:
	return _tutorial == null or _tutorial.permits(a)


## A hand card the coach is asking for (in this way: "summon_atk", "summon_def" or "set").
func _tut_place_ok(uid: int, kind: String) -> bool:
	if _tutorial == null or not _tutorial.active:
		return true
	for slot in 10:
		var a := {"kind": "set", "uid": uid, "slot": slot} if kind == "set" \
			else {"kind": "summon", "uid": uid, "slot": slot, "position": "def" if kind == "summon_def" else "atk"}
		if _tutorial.permits(a):
			return true
	return false


## Any move at all with this hand card.
func _tut_card_ok(uid: int) -> bool:
	return _tut_place_ok(uid, "summon_atk") or _tut_place_ok(uid, "summon_def") or _tut_place_ok(uid, "set") \
		or _tut_ok({"kind": "hustle", "uid": uid})


## An attack from this lane the coach is asking for.
func _tut_attack_ok(slot: int) -> bool:
	if _tutorial == null or not _tutorial.active:
		return true
	return duel.attack_targets("player", "", slot).any(func(t): return _tutorial.permits({"kind": "attack", "from": slot, "target": t}))


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
	var targets: Array = duel.attack_targets("player", "", slot).filter(func(t): return _tut_ok({"kind": "attack", "from": slot, "target": t}))
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
	if not _tut_card_ok(v.uid):
		_tutorial.nudge()   # (the tutorial isn't asking for this card)
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
			if _tut_place_ok(v.uid, "summon_atk"):
				opts.append(["SUMMON  ·  ATK" + cost, ok, func(): _begin_place(v, "summon_atk")])
			if _tut_place_ok(v.uid, "summon_def"):
				opts.append(["SUMMON  ·  DEF" + cost, ok, func(): _begin_place(v, "summon_def")])
		"ambush":
			var ok := _playable(c)
			if ok == false and reason == "":
				reason = "No free back-row slot"
			if _tut_place_ok(v.uid, "set"):
				opts.append(["SET AMBUSH", ok, func(): _begin_place(v, "set")])
		"hustle":
			var ok := duel.can_hustle("player", c)
			if ok == false and reason == "":
				reason = "Requirements not met"
			if _tut_ok({"kind": "hustle", "uid": v.uid}):
				opts.append(["ACTIVATE", ok, func():
					_cancel_interaction()
					_act("player", {"kind": "hustle", "uid": v.uid})])
			# Or face-down in the back row, to activate when you choose (paid for then)
			if _tut_place_ok(v.uid, "set"):
				opts.append(["SET FACE DOWN", _settable(c), func(): _begin_place(v, "set")])
	opts.append(["CANCEL", true, _cancel_and_refresh])
	_menu = _make_menu(opts, reason, Vector2(v.home.x, HAND_LIFT_Y - CARD.y * HOVER_SCALE / 2 - 12))


func _make_menu(opts: Array, reason: String, anchor: Vector2) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.97), PROMPT_EDGE, 2, 10))
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
	if not _tut_card_ok(v.uid):
		_press = null
		_tutorial.nudge()   # (the tutorial isn't asking for this card)
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
	var m := Game.pad.pointer(self)
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
	var at := Game.pad.pointer(self)
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
	var opts: Array = []
	if _tut_place_ok(v.uid, "summon_atk"):
		opts.append(["SUMMON · ATK", true, func():
			_cancel_interaction()
			if not _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "atk", "tributes": tributes}):
				put_back.call()])
	if _tut_place_ok(v.uid, "summon_def"):
		opts.append(["SUMMON · DEF", true, func():
			_cancel_interaction()
			if not _act("player", {"kind": "summon", "uid": v.uid, "slot": slot, "position": "def", "tributes": tributes}):
				put_back.call()])
	opts.append(["CANCEL", true, put_back])
	_menu = _make_menu(opts, "Replaces %s: it goes to the Gutter" % over.name if over != null else "", slot_pos("player", slot) + Vector2(0, -CARD.y / 2 - 12))


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
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.085, 0.97), PROMPT_EDGE, 2, 12))
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
		var ready: Array = _gutter_ready() if pile == "gutter" and side == "player" else []
		if not ready.is_empty():   # (the cards that can act come first)
			var first: Array = []
			for r in ready:
				if not first.has(r[0]):
					first.append(r[0])
			cards = first + cards.filter(func(c): return not first.has(c))
			scroll.custom_minimum_size.y = minf(2.0, ceilf(cards.size() / 6.0)) * (183 + 44)
		for c in cards:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 4)
			var t := TextureRect.new()
			t.texture = CardDB.art(str(c.get("art_url", c.get("id", ""))))
			t.custom_minimum_size = CARD
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.mouse_filter = Control.MOUSE_FILTER_PASS
			t.tooltip_text = str(c.get("name", ""))
			var card: Dictionary = c
			t.mouse_entered.connect(func(): _show_detail(card))
			cell.add_child(t)
			var mine := ready.filter(func(r): return r[0] == card)
			for r in mine:   # this card's Gutter abilities, ready now
				var b := Button.new()
				b.text = _gutter_label(card, r[1], mine.size() > 1)
				b.custom_minimum_size = Vector2(CARD.x, 36)
				b.add_theme_font_size_override("font_size", 13)
				b.modulate = Color(0.75, 1.0, 0.95)
				var act := {"kind": "gutter", "uid": int(card.uid), "fx": r[1]}
				b.pressed.connect(func():
					Sfx.play("click")
					_field_action(act))
				cell.add_child(b)
			if not ready.is_empty() and mine.is_empty():
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(CARD.x, 36)
				cell.add_child(gap)
			grid.add_child(cell)
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
	_ui.prompt.text = UI.touch_words(text)
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
			if _coop:
				UI.dialog(overlay, "GIVE UP?", "You're out, and %s fights on alone. If they still win, so do you." % str(_names.get("ally", "your ally")), [
					["GIVE UP", func(): Net.send("coop:concede", {"matchId": _match_id}), RED], ["KEEP FIGHTING", func(): pass]])
				return
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
	_build_my_tag(players)


## Yours: a name tag over your board, like the others' (your Morale is on your panel).
func _build_my_tag(players: Dictionary) -> void:
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
	_plate_level(tag, sub, prof, "LV %d  ·  YOU")
	tag.add_child(sub)


## A free-for-all plate's level: the emblem, then the text (fmt takes the level).
func _plate_level(p: Control, sub: Label, prof: Dictionary, fmt: String) -> void:
	var level := int(prof.get("level", 0))
	if level <= 0:
		return
	var emblem := UI.texture_rect(UI.level_icon(level), Vector2(20, 20))
	emblem.position = Vector2(68, 28)
	p.add_child(emblem)
	sub.text = fmt % level
	sub.position.x = 92


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
	sub.text = "CPU"
	sub.position = Vector2(68, 30)
	if not prof.get("cpu", false):
		_plate_level(p, sub, prof, "LV %d")
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
	if _coop and side == "boss":   # (Turf Defense: right of the boss's board)
		right = _board_rect(side).end.x + 110.0
		y = _board_rect(side).get_center().y
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
		var targets: Array = duel.attack_targets("player", foe, slot)
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
	if _coop:
		_float_text(at, "%s DOWN" % ("YOU'RE" if side == "player" else "%s IS" % str(_names.get(side, "")).to_upper()), RED, 48)
		_log("%s %s down" % [_who(side), "are" if side == "player" else "is"], side)
	else:
		_float_text(at, "%s OUT · %s" % ["YOU'RE" if side == "player" else str(_names.get(side, "")).to_upper(), _place_text(int(ev.place))], RED, 48)
		_log("%s %s out (%s)" % [_who(side), "are" if side == "player" else "is", _place_text(int(ev.place))], side)
	queue_redraw()
	_update_next_btn()
	if _coop and side != "boss":
		_turf.say("player_out")
		if side == "player" and duel.winner == "":
			_coop_down_when_idle()
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



# ── Turf Defense (backend/socket/coopMatch.js) ───────────────────────────────
# You and your ally against a boss: the free-for-all's boards, with the boss's on top (bigger, its
# plate under it with the long Morale bar), yours bottom-left and your ally's bottom-right. Your
# ally isn't a target (the rules' teams); the boss's entrance, phases and lines are TurfShow's.

## Who's where: the boss's board centred on top, yours and your ally's below it.
func _setup_coop_sides(start: Dictionary) -> void:
	_ffa = true
	_coop = true
	_boss = start.get("boss", {}) if start.get("boss") is Dictionary else {}
	_turf = TurfShow.new(self, _boss)
	_foes = ["ally", "boss"]
	_sides = ["player", "ally", "boss"]
	hand = {}
	field = {}
	for side in _sides:
		hand[side] = []
		field[side] = {}
	var k := FFA_CARD_K
	var p := Vector2(FFA_STEP.x / (COLS[1] - COLS[0]), FFA_STEP.y / absf(ROWS.player[1] - ROWS.player[0]))
	var half_w := (RIGHT_X - LEFT_X) * p.x / 2.0 + CARD.x * k / 2.0
	var half_h := FFA_STEP.y / 2.0 + CARD.y * k / 2.0
	for pair in [["player", -1.0], ["ally", 1.0]]:
		var c := FFA_MID + Vector2((half_w + FFA_GAP.x / 2.0) * float(pair[1]), FFA_GAP.y / 2.0 + PLATE_H + 8.0 + half_h)
		_boards[pair[0]] = {"c": c, "s": k, "p": p, "rows": "player", "plate": c.y - half_h - 8.0 - PLATE_H}
	var kb := COOP_BOSS_K
	var bh := FFA_STEP.y * (kb / k) / 2.0 + CARD.y * kb / 2.0
	var cb := Vector2(FFA_MID.x, FFA_MID.y - FFA_GAP.y / 2.0 - PLATE_H - 8.0 - bh)
	_boards.boss = {"c": cb, "s": kb, "p": p * (kb / k), "rows": "opponent", "plate": cb.y + bh + 8.0}


## The plates: the boss's own (TurfShow.build_plate), your ally's like a free-for-all opponent's in
## your crew's colour, your name tag, and the boss's intel where a 1v1 opponent's plate goes.
func _build_coop_plates(players: Dictionary) -> void:
	for side in ["boss", "ally"]:
		var p := Panel.new()
		p.position = _plate_rect(side).position
		p.size = _plate_rect(side).size
		p.z_index = 2
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards_layer.add_child(p)
		if side == "boss":
			_panels.boss = _turf.build_plate(p)
		else:
			_build_plate("ally", p, players.get("ally", {}) if players.get("ally") is Dictionary else {}, TEAL)
	_build_my_tag(players)
	_turf.build_intel($HUD/UI/OppPanel)


## The boss's entrance before the first move (the match's opening events wait for it).
func _coop_intro(start: Dictionary) -> void:
	_playing = true
	await _turf.intro(start.get("players", {}) if start.get("players") is Dictionary else {})
	_playing = false
	_pump()


func _ev_boss_phase(ev: Dictionary) -> void:
	_log("%s: PHASE %d · %s" % [str(_names.get(ev.side, "The boss")), int(ev.get("phase", 1)) + 1, str(ev.get("label", ""))], ev.side)
	if _turf:
		await _turf.phase(ev)


## The boss ran out of cards: its Gutter goes back into its deck.
func _ev_recycle(ev: Dictionary) -> void:
	Sfx.play("shuffle", 0.8)
	_float_text(pile_pos(ev.side, "deck"), "GUTTER → DECK  ·  %d" % int(ev.get("count", 0)), _side_color(ev.side), 30)
	_log("%s shuffles %d cards from the Gutter back into the deck" % [_who(ev.side), int(ev.get("count", 0))], ev.side)
	await _wait(0.6)


## Once what's playing now has played (a big moment, like an Evolve, isn't covered by a panel).
func _when_idle() -> void:
	while is_inside_tree() and (_playing or not _queue.is_empty()):
		await get_tree().process_frame


func _coop_down_when_idle() -> void:
	await _when_idle()
	if is_inside_tree() and duel.winner == "":
		_show_coop_down_panel()


## You're down, and your ally fights on: watch (you still win if they do) or leave.
func _show_coop_down_panel() -> void:
	if _ui.has("out_panel") and is_instance_valid(_ui.out_panel):
		return
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.96), TEAL, 3, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var title := _label(48, RED, true)
	title.text = "YOU'RE DOWN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var t := _label(22, Color.WHITE)
	t.text = "%s fights on. If they beat %s, you win too." % [str(_names.get("ally", "Your ally")), str(_names.get("boss", "the boss"))]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	row.add_child(UI.button("KEEP WATCHING", func():
		if is_instance_valid(box):
			box.queue_free(), Vector2(260, 56), TEAL))
	row.add_child(UI.button("LEAVE", func():
		Net.send("coop:quit")
		UI.toast(overlay, "Your rewards come when the match ends.", GOLD)
		Game.go("turf_defense"), Vector2(200, 56), RED))
	overlay.add_child(box)
	box.z_index = 50
	var sz := box.get_combined_minimum_size()
	box.position = Vector2(1028 - sz.x / 2, 440 - sz.y / 2)
	_ui.out_panel = box


## Turf Defense results for the post-match screen: won or lost together, the boss, the rewards
## (and the prize card on a first clear).
func _coop_result_into(r: Dictionary, data: Dictionary) -> void:
	r.coop = true
	r.mode = "coop"
	r.result = "win" if data.get("won", false) else "loss"
	r.boss = data.get("boss", _boss) if data.get("boss") is Dictionary else _boss
	r.players = data.get("players", {})
	r.opponent_morale = int(duel.sides.get("boss", {}).get("morale", 0))
	if data.get("rewards") is Dictionary:
		r.rewards = data.rewards
	if data.get("achievements") is Array:
		r.achievements = data.achievements
	if data.get("mastery") is Dictionary:
		r.mastery = data.mastery


## A side's most Morale (a boss has its own; everyone else the usual 6000).
func _max_morale(side: String) -> float:
	var s = duel.sides.get(side) if duel != null else null
	return maxf(1.0, float(s.get("max_morale", DuelState.START_MORALE)) if s is Dictionary else float(DuelState.START_MORALE))
