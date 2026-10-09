extends Node
## Plays the big-summon showcase and the damage comet on demand, for checking them by eye:
##   godot --path godot --write-movie out/f.png --fixed-fps 20 --quit-after 120 res://tests/fx_stage.tscn

func _ready() -> void:
	var d: Node = load("res://scenes/duel.tscn").instantiate()
	add_child(d)
	await get_tree().create_timer(2.5).timeout
	var v = d.hand.player[0]
	d.hand.player.erase(v)
	v.busy = true
	v.z_index = 420
	d._dim(0.6, 0.2)
	await d._showcase(v, {"name": "Sovereign"}, d.BLUE)
	await v.move_to(d.slot_pos("player", 2), 1.0, 0.0, 0.2).finished
	await d._impact(d.slot_pos("player", 2), true)
	d._dim(0.0, 0.3)
	var root: Control = d._panels.opponent.root
	await d._comet(d.slot_pos("opponent", 2), root.position + root.size / 2, d.GOLD)
	d._set_morale("opponent", 4800)
