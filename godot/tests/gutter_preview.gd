extends Node
## Shows a Gutter ability ready (the Gutter glows teal, its viewer has a USE button) and a PLUNDER
## from the opponent's hand, for checking them by eye (not part of the test suite):
##   godot --path godot --write-movie out/f.png --fixed-fps 10 --quit-after 120 res://tests/gutter_preview.tscn

func _ready() -> void:
	var d: Node = load("res://scenes/duel.tscn").instantiate()
	add_child(d)
	await get_tree().create_timer(2.5).timeout
	var st: DuelState = d.duel
	for c in d.overlay.get_children():   # (the mulligan question: out of the way)
		if c is PanelContainer:
			c.visible = false
	if st.pending is Dictionary and st.pending.get("side") == "player":
		d._act("player", {"kind": "choose", "option": "keep"})
	await get_tree().create_timer(4.0).timeout
	st.active = "player"
	st.phase = "deployment"
	st.sides.player.authority = 5
	var ghost: Dictionary = st.make_card({"id": str(st.sides.player.deck[0].id), "name": "Gutter Ghost",
		"effects": [{"when": "gutter", "do": "damage", "amount": 300, "cost": "exile_self"}]})
	st.sides.player.gutter.append(ghost)
	d.counts = st._counts()
	d._player_ready()
	await get_tree().create_timer(0.5).timeout
	d.counts = st._counts()   # (the board's own events from before the Ghost came in)
	d.queue_redraw()
	await get_tree().create_timer(1.0).timeout
	d._show_pile("player", "gutter")
	await get_tree().create_timer(2.0).timeout
	d._cancel_and_refresh()
	var taken: Dictionary = st.sides.opponent.hand[0]
	await d._ev_plunder({"type": "plunder", "side": "player", "from_side": "opponent", "from": "hand", "card": taken})
