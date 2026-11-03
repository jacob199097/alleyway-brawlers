extends Node
## Plays the Neutral summon, attack and KO, for checking them by eye (not part of the test suite):
##   godot --path godot --write-movie out/f.png --fixed-fps 20 --quit-after 200 res://tests/neutral_fx.tscn

func _ready() -> void:
	var d: Node = load("res://scenes/duel.tscn").instantiate()
	add_child(d)
	await get_tree().create_timer(2.5).timeout
	for c in d.overlay.get_children():   # (the mulligan question: out of the way)
		if c is PanelContainer:
			c.visible = false
	var v = d.hand.player[0]
	d.hand.player.erase(v)
	v.busy = true
	var at: Vector2 = d.slot_pos("player", 2)
	v.home = at
	v.home_rot = 0.0
	v.z_index = 30
	await d._spotlight_in(v, at, false)
	v.busy = false
	var foe = d.hand.opponent[0]
	d.hand.opponent.erase(foe)
	var fat: Vector2 = d.slot_pos("opponent", 2)
	foe.home = fat
	foe.home_rot = 0.0
	foe.z_index = 30
	foe.flip(true)
	await foe.move_to(fat, 1.0, 0.0, 0.2).finished
	await get_tree().create_timer(0.4).timeout
	await d._brawl_strike(v, foe, fat, (fat - at).normalized(), true, false)
	v.go_home(0.28)
	await get_tree().create_timer(0.5).timeout
	await d._knockout_ko(foe)
