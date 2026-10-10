extends Node
## In-game updates without a new download. Must stay the FIRST autoload: it loads a downloaded
## patch (a .pck of the game's code and scenes, see docs/CARD_PIPELINE.md) before any other
## script is loaded, so the rest of the game runs from the patch.
##
## A patch only applies to the full build it was made for (its "base" version and up), since
## project settings, the autoload list and class_name scripts come from the full build.
## Keep this script free of dependencies: nothing else is loaded yet when it runs.

const DIR := "user://patch"
const INFO := DIR + "/patch.json"
const BOOTING := DIR + "/booting"   # exists while a patched start-up hasn't reached the menus

var applied := ""   # the patch version running now, or ""
var builtin := ""   # this full build's version


func _init() -> void:
	builtin = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var info := read_info()
	if info.is_empty():
		return
	var version := str(info.get("version", ""))
	var path := "%s/%s" % [DIR, info.get("file", "")]
	if compare(builtin, version) >= 0:
		clear()   # a full build at least as new as the patch was installed
		return
	if compare(builtin, str(info.get("base", ""))) < 0 or not FileAccess.file_exists(path):
		return
	if FileAccess.file_exists(BOOTING):
		# The last start with this patch never reached the menus: don't try it again
		push_warning("Patch %s failed to start last time; running the built-in version." % version)
		info.failed = true
		_write_info(info)
		DirAccess.remove_absolute(BOOTING)
		return
	if info.get("failed", false):
		return
	FileAccess.open(BOOTING, FileAccess.WRITE).store_string(version)
	if ProjectSettings.load_resource_pack(path, true):
		applied = version
		ProjectSettings.set_setting("application/config/version", version)
		print("Patcher: running update %s on build %s" % [version, builtin])
	else:
		DirAccess.remove_absolute(BOOTING)


## The boot screen calls this once the game has started properly.
func boot_ok() -> void:
	if FileAccess.file_exists(BOOTING):
		DirAccess.remove_absolute(BOOTING)


## Whether a patch with this version already failed here (don't download it again).
func failed(version: String) -> bool:
	var info := read_info()
	return info.get("failed", false) and str(info.get("version", "")) == version


static func read_info() -> Dictionary:
	if not FileAccess.file_exists(INFO):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	return v if v is Dictionary else {}


## Install a downloaded patch (already checked) to load on the next start.
static func install(version: String, base: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := "game-%s.pck" % version
	var f := FileAccess.open("%s/%s" % [DIR, file], FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	var old := read_info()
	_write_info({"version": version, "base": base, "file": file})
	if str(old.get("file", "")) not in ["", file]:
		DirAccess.remove_absolute("%s/%s" % [DIR, old.file])
	return true


static func clear() -> void:
	var info := read_info()
	if info.has("file"):
		DirAccess.remove_absolute("%s/%s" % [DIR, info.file])
	DirAccess.remove_absolute(INFO)
	DirAccess.remove_absolute(BOOTING)


## Start the game again (to load a freshly installed patch).
func restart() -> void:
	var args := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


static func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func _write_info(info: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	FileAccess.open(INFO, FileAccess.WRITE).store_string(JSON.stringify(info))
