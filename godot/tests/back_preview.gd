extends Control
## A clan's moving card back, big, at rest and hovered side by side, for checking it by eye (not part
## of the test suite):
##   godot --path godot --write-movie out/f.png --fixed-fps 20 --quit-after 200 res://tests/back_preview.tscn -- pirates

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var clan: String = args[0] if not args.is_empty() else "pirates"
	var size := Vector2(560, 840)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	for i in 2:   # (left at rest, right as if hovered)
		var art := UI.texture_rect(CardDB.back(clan), size)
		var mat := UI.card_material(size)
		var style := CardDB.back_style(clan)
		if style != "":
			mat.set_shader_parameter(style, 1.0)
		mat.set_shader_parameter("galaxy_glow", float(i))
		art.material = mat
		art.position = Vector2(300 + i * 760, 120)
		add_child(art)
