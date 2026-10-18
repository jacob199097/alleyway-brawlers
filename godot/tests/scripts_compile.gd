extends Node
## Every script under res://scripts compiles (run as a scene, so the autoloads exist).
## Run:  godot --headless --path godot res://tests/scripts_compile.tscn

var _bad := 0


func _ready() -> void:
	_walk("res://scripts")
	print("Scripts compile: %d failed" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)


func _walk(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var s = load(dir + "/" + f)
			if s == null or not (s as GDScript).can_instantiate():
				_bad += 1
				push_error("does not compile: %s/%s" % [dir, f])
