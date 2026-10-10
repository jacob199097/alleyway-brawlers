extends Node
## Saves the avatars UI.avatar makes from card backs and card art, to check the crops by eye.
##   godot --headless --path godot res://tests/avatar_crops.tscn -- <out_dir> [card id]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	var keys: Array = ["profile_001", "clan:nebula", "clan:militia"]
	for c in CardDB.clans():
		keys.append("clan:" + str(c.id))
	keys.append("card:" + (args[1] if args.size() > 1 else str(CardDB.all()[0])))
	for k in keys:
		var t := UI.avatar(k)
		var img: Image = null
		if t is AtlasTexture:   # imported art is compressed: cut the region out by hand
			img = t.atlas.get_image()
			img.decompress()
			img = img.get_region(Rect2i(t.region))
		elif t:
			img = t.get_image()
		if img:
			img.save_png("%s/avatar_%s.png" % [out, str(k).replace(":", "_")])
			print("saved ", k, " ", img.get_size())
	get_tree().quit()
