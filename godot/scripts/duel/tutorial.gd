extends Node
## The guided first duel. It sets up a staged match on the real duel screen, shows a coach
## panel step by step, highlights what to click, only lets the player make the move being
## taught, and plays the opponent's turns from a script. After the last lesson the match
## carries on as a normal game against the CPU.
##
## Cards are picked from whatever is in data/cards.json (cheap level-1 characters), so the
## tutorial keeps working when the card set changes. Their effects are switched off here so
## only the core rules are on show.

const INFO := "info"    # read, then press NEXT
const DO := "do"        # make the highlighted move
const WAIT := "wait"    # watch the opponent's turn

var screen: Node        # duel.gd
var d: DuelState
var steps: Array = []
var index := 0
var active := true      # false once the lessons are over (free play)

var cards := {}         # role -> card dict (in the state) : p1 p2 p3 o1 o2
var _opp_plan := {}     # turn -> {uid, slot, position}
var _opp_done := {}
var _panel: PanelContainer
var _step_label: Label
var _body: RichTextLabel
var _next: Button
var _marker: Control
var _shown := -1


# ── Setup ────────────────────────────────────────────────────────────────────

## Build the staged match. Returns the DuelState for the duel screen to run.
func make_duel(duel_screen: Node) -> DuelState:
	screen = duel_screen
	var pool := _characters()
	var p1 := _pick(pool, 1, "attack", true, [])
	var p2 := _pick(pool, 2, "attack", true, [p1])
	var p3 := _pick(pool, 3, "attack", true, [p1, p2])
	var o1 := _pick(pool, 1, "attack", false, [p1, p2, p3])
	var o2 := _pick(pool, 2, "defense", false, [p1, p2, p3, o1])
	var fill := pool.filter(func(id): return int(CardDB.get_card(id).authority) >= 4)
	if fill.is_empty():
		fill = pool
	var f := func(i: int) -> String: return fill[i % fill.size()]
	# Draws come off the back of the deck: the opening hand is the last five cards
	var pdeck: Array = []
	var odeck: Array = []
	for i in 30:
		pdeck.append(f.call(i))
		odeck.append(f.call(i + 3))
	pdeck.append_array([f.call(7), f.call(6), f.call(1), f.call(0), p3, p2, p1])
	odeck.append_array([f.call(8), f.call(5), f.call(4), f.call(2), o2, o1])
	var leader := ""
	for id in CardDB.all():
		if CardDB.get_card(id).get("cardType") == "leader":
			leader = id
			break
	d = DuelState.new({"player": pdeck, "opponent": odeck}, {}, {"player": leader, "opponent": leader}, "player", -1)
	_strip_effects()
	# Find the staged cards (hand order is fixed: opening draws alternate, player first)
	var ph: Array = []
	for i in 5:
		ph.append(d.sides.player.deck[d.sides.player.deck.size() - 1 - i])
	var oh: Array = []
	for i in 2:
		oh.append(d.sides.opponent.deck[d.sides.opponent.deck.size() - 1 - i])
	cards = {"p1": ph[0], "p2": ph[1], "p3": ph[2], "o1": oh[0], "o2": oh[1]}
	_fix_numbers()
	_opp_plan = {
		2: {"uid": cards.o1.uid, "slot": 2, "position": "atk"},
		4: {"uid": cards.o2.uid, "slot": 2, "position": "def"},
	}
	_build_steps()
	_build_ui()
	return d


## Level-1 characters, cheapest first.
func _characters() -> Array:
	var out: Array = []
	for id in CardDB.all():
		var c: Dictionary = CardDB.get_card(id)
		if c.get("cardType") == "gang_member" and int(c.get("level", 1)) == 1:
			out.append(id)
	return out


## The card at this Authority (or the nearest cheaper/dearer one) with the highest/lowest stat.
func _pick(pool: Array, cost: int, stat: String, highest: bool, avoid: Array) -> String:
	for spread in 6:
		var best := ""
		for id in pool:
			if id in avoid:
				continue
			var c: Dictionary = CardDB.get_card(id)
			if absi(int(c.authority) - cost) != spread:
				continue
			if best == "" or (int(c[stat]) > int(CardDB.get_card(best)[stat])) == highest \
					and int(c[stat]) != int(CardDB.get_card(best)[stat]):
				best = id
		if best != "":
			return best
	return pool[0]


func _strip_effects() -> void:
	for side in d.sides:
		var s: Dictionary = d.sides[side]
		for c in s.deck:
			c.effectKey = ""
			c.erase("ability")
			c.effectText = "Card effects are switched off in the tutorial."
		if s.leader != null:
			s.leader.effectKey = ""
			s.leader.awakenCondition = {}
			s.leader.effectText = "Dormant leader. While it's Dormant it can be attacked: hits remove its Influence, and at 0 it's defeated and its owner loses 1000 Morale."


## Make sure each lesson plays out as described, whatever the card stats are.
func _fix_numbers() -> void:
	var p1: Dictionary = cards.p1
	var p2: Dictionary = cards.p2
	var p3: Dictionary = cards.p3
	var o1: Dictionary = cards.o1
	var o2: Dictionary = cards.o2
	if p2.base_attack <= o1.base_attack:
		_set_stats(p2, o1.base_attack + 400, p2.base_defense)
	if p1.base_attack <= o1.base_defense:
		_set_stats(p1, o1.base_defense + 200, p1.base_defense)
	if p2.base_attack <= o2.base_defense:
		_set_stats(p2, o2.base_defense + 400, p2.base_defense)
	# One hit from the first character defeats the leader
	d.sides.opponent.leader.influence = p1.base_attack
	# Leave the opponent a little Morale after the scripted lessons, to finish in free play
	var dealt: int = (p2.base_attack - o1.base_attack) + DuelState.LEADER_DEFEAT_PENALTY + p3.base_attack
	d.sides.opponent.morale = dealt + 700


static func _set_stats(c: Dictionary, atk: int, def: int) -> void:
	c.base_attack = atk
	c.attack = atk
	c.base_defense = def
	c.defense = def


# ── Lessons ──────────────────────────────────────────────────────────────────

func _n(role: String) -> String:
	return "[color=#f4d35e]%s[/color]" % str(cards[role].name)


func _build_steps() -> void:
	var p1: Dictionary = cards.p1
	var p2: Dictionary = cards.p2
	var p3: Dictionary = cards.p3
	var o1: Dictionary = cards.o1
	steps = [
		{"type": INFO, "mark": func(): return _panel_rect("player"),
			"text": "Welcome to the alley! Each player has [b]Morale[/b] (normally 6000). Knock your rival's Morale down to [b]0[/b] and you win.\n\nThis rival is already roughed up. This quick lesson walks you through a real duel."},
		{"type": DO, "allow": func(a): return a.kind == "choose" and a.option == "keep",
			"done": func(): return d.pending.is_empty() and d.phase == "deployment",
			"text": "You start with 5 cards. Once per game, at the start, you can [b]shuffle your hand back and draw 5 new ones[/b] (a mulligan).\n\nThis hand is good: press [b]KEEP THIS HAND[/b]."},
		{"type": INFO, "mark": func(): return screen._panels.player.auth.get_global_rect().grow(8),
			"text": "This is your [b]Authority[/b]. Every card costs Authority: the number in the card's top corner.\n\nYou have [b]1[/b] now. It goes up by 1 every turn (up to 15) and refills, so bigger cards come later."},
		{"type": DO, "mark": func(): return _hand_rect(p1),
			"allow": func(a): return a.kind == "summon" and int(a.uid) == p1.uid and a.get("position", "atk") == "atk",
			"done": func(): return _on_field("player", p1),
			"text": "%s costs 1. [b]Click it[/b], choose [b]SUMMON[/b], then click a glowing lane to put it on the field." % _n("p1")},
		{"type": INFO, "mark": func(): return _field_rect("player", p1),
			"text": "Your first character! The numbers under it are its [b]ATK / DEF[/b].\n\nCharacters fight in your front row. Summoned face-up like this, it's in [b]ATK position[/b], ready to attack."},
		{"type": DO, "mark": func(): return screen._ui.next.get_global_rect().grow(6),
			"allow": func(a): return a.kind == "next",
			"done": func(): return d.active == "opponent",
			"text": "Nobody can attack on turn 1. Press [b]END TURN[/b] (or [b]Space[/b]) to finish your turn."},
		{"type": WAIT, "done": func(): return d.active == "player" and d.turn == 3 and d.phase == "deployment",
			"text": "Your rival's turn. Watch what they do…"},
		{"type": INFO, "mark": func(): return _field_rect("opponent", o1),
			"text": "They summoned %s ([b]%d ATK[/b]).\n\nIt's your turn again: you drew a card, and your Authority went up to [b]2[/b]." % [_n("o1"), o1.base_attack]},
		{"type": DO, "mark": func(): return _hand_rect(p2),
			"allow": func(a): return a.kind == "summon" and int(a.uid) == p2.uid and a.get("position", "atk") == "atk",
			"done": func(): return _on_field("player", p2),
			"text": "Summon %s (cost 2) the same way: click it, [b]SUMMON[/b], pick a lane." % _n("p2")},
		{"type": DO, "mark": func(): return screen._ui.next.get_global_rect().grow(6),
			"allow": func(a): return a.kind == "next",
			"done": func(): return d.phase == "brawl",
			"text": "Time to fight. Press the phase button (or [b]Space[/b]) to go to the [b]BRAWL[/b] phase."},
		{"type": DO, "mark": func(): return _field_rect("player", p2) if not _attacking() else _field_rect("opponent", o1),
			"allow": func(a): return a.kind == "attack" and int(a.from) == _slot("player", p2) and int(a.target) == _slot("opponent", o1),
			"done": func(): return o1.downed,
			"text": "Attack! [b]Click %s[/b], then [b]click %s[/b].\n\nATK against ATK: the higher number wins. The loser is [b]Downed[/b], and its owner loses Morale equal to the difference ([b]%d[/b])." % [_n("p2"), _n("o1"), p2.base_attack - o1.base_attack]},
		{"type": INFO, "mark": func(): return _field_rect("opponent", o1),
			"text": "[b]Downed![/b] It's turned sideways: it can't attack, and it no longer protects its owner.\n\nHit it again and it's [b]knocked out[/b]. Leave it, and it gets back up (in DEF) after a full round."},
		{"type": DO, "mark": func(): return _field_rect("player", p1) if not _attacking() else _field_rect("opponent", o1),
			"allow": func(a): return a.kind == "attack" and int(a.from) == _slot("player", p1) and int(a.target) == _slot("opponent", o1),
			"done": func(): return not _on_field("opponent", o1),
			"text": "Finish it off: attack %s with %s. Against a Downed card you need more ATK than its [b]DEF[/b] ([b]%d[/b])." % [_n("o1"), _n("p1"), o1.base_defense]},
		{"type": INFO, "mark": func(): return Rect2(screen.pile_pos("opponent", "gutter") - screen.CARD / 2, screen.CARD).grow(10),
			"text": "[b]K.O.![/b] Knocked-out cards go to the [b]Gutter[/b], the discard pile.\n\nNote: beating a Downed or DEF card doesn't cost its owner Morale. Only winning an ATK-vs-ATK fight, or a Direct Attack, does."},
		{"type": DO, "mark": func(): return screen._ui.next.get_global_rect().grow(6),
			"allow": func(a): return a.kind == "next",
			"done": func(): return d.active == "opponent",
			"text": "Each character attacks once per turn. Press the phase button until your turn ends."},
		{"type": WAIT, "done": func(): return d.active == "player" and d.turn == 5 and d.phase == "deployment",
			"text": "Your rival's turn…"},
		{"type": INFO, "mark": func(): return _field_rect("opponent", cards.o2),
			"text": "They played a card [b]face-down in DEF position[/b]. You can't see it until it's attacked.\n\nTo beat a DEF card, your ATK must be higher than its DEF. Win and it's Downed; fall short and the attack is [b]Blocked[/b]."},
		{"type": DO, "mark": func(): return _hand_rect(p3),
			"allow": func(a): return a.kind == "summon" and int(a.uid) == p3.uid and a.get("position", "atk") == "atk",
			"done": func(): return _on_field("player", p3),
			"text": "You have [b]3 Authority[/b] now. Summon %s first." % _n("p3")},
		{"type": DO, "mark": func(): return screen._ui.next.get_global_rect().grow(6),
			"allow": func(a): return a.kind == "next",
			"done": func(): return d.phase == "brawl",
			"text": "On to the [b]BRAWL[/b] phase."},
		{"type": DO, "mark": func(): return _field_rect("player", p2) if not _attacking() else _field_rect("opponent", cards.o2),
			"allow": func(a): return a.kind == "attack" and int(a.from) == _slot("player", p2) and int(a.target) == _slot("opponent", cards.o2),
			"done": func(): return cards.o2.downed or not _on_field("opponent", cards.o2),
			"text": "Attack the face-down card with %s ([b]%d ATK[/b])." % [_n("p2"), p2.base_attack]},
		{"type": DO, "mark": func(): return _field_rect("player", p1) if not _attacking() else _leader_rect(),
			"allow": func(a): return a.kind == "attack" and int(a.from) == _slot("player", p1) and int(a.target) == DuelState.LEADER,
			"done": func(): return d.sides.opponent.leader_state == "defeated",
			"text": "See their [b]Leader[/b]? While it's Dormant you can attack it at any time. Hits remove its [b]Influence[/b]; at 0 it's defeated and its owner [b]loses 1000 Morale[/b].\n\nAttack it with %s: click %s, then click their leader." % [_n("p1"), _n("p1")]},
		{"type": DO, "mark": func(): return _field_rect("player", p3) if not _attacking() else _direct_rect(),
			"allow": func(a): return a.kind == "attack" and int(a.from) == _slot("player", p3) and int(a.target) == DuelState.DIRECT,
			"done": func(): return d.phase == "brawl" and not screen._playing and _p3_attacked(),
			"text": "Their only character is Downed, so nothing protects their Morale. [b]Direct Attack![/b]\n\nClick %s, then the [b]DIRECT ATTACK[/b] button at the top." % _n("p3")},
		{"type": INFO, "last": true,
			"text": "That's the basics! You'll also meet:\n• [b]Ambush[/b] cards: set face-down in your back row, they spring when you're attacked.\n• [b]Hustles[/b]: one-shot effects.\n• [b]Promotion[/b]: characters level up into stronger forms from your Hideout.\n\nNow finish them off!"},
	]


func _p3_attacked() -> bool:
	var c = cards.p3
	return c.has_attacked or not _on_field("player", c)


# ── Board lookups (screen rectangles for the highlight) ─────────────────────

func _slot(side: String, c: Dictionary) -> int:
	for slot in DuelState.FRONT:
		if d.sides[side].field[slot] == c:
			return slot
	return -99


func _on_field(side: String, c: Dictionary) -> bool:
	return _slot(side, c) != -99


func _attacking() -> bool:
	return screen._mode == "target"


func _view_rect(v: Node2D) -> Rect2:
	if v == null or not is_instance_valid(v):
		return Rect2()
	var sz: Vector2 = screen.CARD * v.scale.x
	if absf(sin(v.rotation)) > 0.7:
		sz = Vector2(sz.y, sz.x)
	return Rect2(v.global_position - sz / 2, sz).grow(8)


func _hand_rect(c: Dictionary) -> Rect2:
	for v in screen.hand.player:
		if v.uid == c.uid:
			return _view_rect(v)
	return Rect2()


func _field_rect(side: String, c: Dictionary) -> Rect2:
	var slot := _slot(side, c)
	return _view_rect(screen.field[side].get(slot)) if slot != -99 else Rect2()


func _leader_rect() -> Rect2:
	return _view_rect(screen.leaders.get("opponent"))


func _direct_rect() -> Rect2:
	var b = screen._direct_btn
	return b.get_global_rect().grow(6) if b and is_instance_valid(b) else Rect2()


func _panel_rect(side: String) -> Rect2:
	return screen._panels[side].root.get_global_rect().grow(6)


# ── Gating and the opponent's script ─────────────────────────────────────────

## May the player make this move right now?
func allow(a: Dictionary) -> bool:
	if not active:
		return true
	var st: Dictionary = steps[index]
	if st.type == DO and st.allow.call(a):
		return true
	nudge()
	return false


func nudge() -> void:
	Sfx.play("click", 0.7, -4.0)
	var t := _panel.create_tween()
	for x in [14.0, -10.0, 6.0, 0.0]:
		t.tween_property(_panel, "position:x", 24.0 + x, 0.05)
	_body.modulate = Color(1.6, 1.4, 0.8)
	_body.create_tween().tween_property(_body, "modulate", Color.WHITE, 0.4)


## The opponent's move, or {} to let the normal CPU decide (after the lessons).
func opponent_move() -> Dictionary:
	if not active:
		return {}
	if not d.pending.is_empty():
		if d.pending.kind == "choose":
			var ids: Array = d.pending.options.map(func(o): return o.id)
			return {"kind": "choose", "option": "keep" if "keep" in ids else ids[0]}
		return {"kind": "discard", "uid": d.sides.opponent.hand[0].uid}
	if d.phase == "deployment" and _opp_plan.has(d.turn) and not _opp_done.has(d.turn):
		_opp_done[d.turn] = true
		var p: Dictionary = _opp_plan[d.turn]
		return {"kind": "summon", "uid": p.uid, "slot": p.slot, "position": p.position}
	return {"kind": "next"}


# ── Coach panel ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_marker = Control.new()
	_marker.size = Vector2(1920, 1080)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	screen.overlay.add_child(_marker)
	_panel = UI.panel(UI.GOLD, Color(0.03, 0.03, 0.09, 0.97))
	_panel.position = Vector2(24, 24)
	_panel.custom_minimum_size = Vector2(380, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UI.label("TUTORIAL", 26, UI.GOLD, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_step_label = UI.label("", 16, UI.MUTED)
	head.add_child(_step_label)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(350, 0)
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_font_size_override("bold_font_size", 20)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)
	_next = UI.button("NEXT  ▶", _advance, Vector2(350, 52), UI.GOLD)
	col.add_child(_next)
	var skip := UI.button("Skip tutorial", _ask_skip, Vector2(350, 38))
	skip.add_theme_font_size_override("font_size", 16)
	col.add_child(skip)
	screen.overlay.add_child(_panel)


func _ask_skip() -> void:
	UI.dialog(screen.overlay, "SKIP THE TUTORIAL?", "You can replay it any time from Fight → Tutorial.",
		[["SKIP", _skip, UI.RED], ["KEEP LEARNING", func(): pass]])


func _skip() -> void:
	Game.set_setting("tutorial_done", true)
	Game.go("main_menu")


func _advance() -> void:
	if index >= steps.size():
		return
	if steps[index].get("last", false):
		_finish()
		return
	index += 1


func _finish() -> void:
	active = false
	Game.set_setting("tutorial_done", true)
	var t := _panel.create_tween()
	t.tween_property(_panel, "modulate:a", 0.0, 0.3)
	t.tween_callback(_panel.queue_free)
	_marker.queue_free()
	# Hand the turn back to the duel screen (the CPU takes over the opponent from here)
	screen._player_ready()


## Called every frame by the duel screen.
func update() -> void:
	if not active:
		return
	var st: Dictionary = steps[index]
	var idle: bool = not screen._playing and screen._queue.is_empty()
	if st.type != INFO and idle and st.done.call():
		index += 1
		Sfx.play("phase", 1.3, -6.0)
		st = steps[index]
	if _shown != index:
		_shown = index
		_body.text = st.text
		_step_label.text = "%d / %d" % [index + 1, steps.size()]
		_next.visible = st.type == INFO
		_next.text = "FINISH THEM OFF  ▶" if st.get("last", false) else "NEXT  ▶"
		_panel.reset_size()
		_panel.modulate.a = 0.0
		_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)
	_marker.queue_redraw()


func _draw_marker() -> void:
	if not active or index >= steps.size():
		return
	var st: Dictionary = steps[index]
	if not st.has("mark") or screen._playing:
		return
	var r: Rect2 = st.mark.call()
	if r.size == Vector2.ZERO:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	_marker.draw_rect(r.grow(4.0 + pulse * 6.0), Color(UI.GOLD, 0.25 + 0.35 * pulse), false, 3.0)
	_marker.draw_rect(r, Color(UI.GOLD, 0.9), false, 4.0)
	# A bouncing pointer above the target
	var tip := Vector2(r.get_center().x, r.position.y - 10.0 - pulse * 12.0)
	if tip.y < 40.0:
		tip = Vector2(r.get_center().x, r.end.y + 10.0 + pulse * 12.0)
		_marker.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-18, 26), tip + Vector2(18, 26)]), UI.GOLD)
	else:
		_marker.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-18, -26), tip + Vector2(18, -26)]), UI.GOLD)
