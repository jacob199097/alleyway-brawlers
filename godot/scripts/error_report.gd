extends Logger
## Collects the game's errors for the server (backend/routes/telemetry.js), so bugs show up
## without players having to describe them. Game installs it at start-up and sends what it has
## every so often. It also notices when the last session didn't close properly (a crash or a
## forced quit) and sends the end of that session's log.
##
## Godot can call _log_error from any thread, so the queue is behind a mutex.

const RUNNING := "user://running"     # exists while the game is open
const MAX_PER_SESSION := 50           # distinct errors sent per session (repeats are counted)

var muted := false   # set while sending, so a failed send can't report itself

var _mutex := Mutex.new()
var _queue: Array = []   # [{kind, message, location, detail, count}]
var _seen := {}          # message + location -> its entry (repeats only raise the count)


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if muted or error_type == ERROR_TYPE_WARNING:
		return
	var location := "%s:%d" % [file, line]
	var detail := ""
	if not script_backtraces.is_empty():
		var bt: ScriptBacktrace = script_backtraces[0]
		if bt.get_frame_count() > 0:
			location = "%s:%d in %s()" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
			detail = bt.format()
	var kind: String = {ERROR_TYPE_SCRIPT: "script", ERROR_TYPE_SHADER: "shader"}.get(error_type, "error")
	_add(kind, rationale if rationale != "" else code, location, detail)


func _log_message(_message: String, _error: bool) -> void:
	pass


## Call once at start-up: reports an unclean end of the last session, then marks this one open.
func start_session() -> void:
	if FileAccess.file_exists(RUNNING):
		_add("crash", "The game didn't close properly last time", "", _last_log_tail(40))
	var f := FileAccess.open(RUNNING, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())


## Call when the game closes normally.
func end_session() -> void:
	if FileAccess.file_exists(RUNNING):
		DirAccess.remove_absolute(RUNNING)


## Everything waiting to be sent (and forget it).
func take() -> Array:
	_mutex.lock()
	var out := _queue.duplicate(true)
	for e in _queue:
		e.count = 0   # repeats from now on are counted afresh
	_queue.clear()
	_mutex.unlock()
	return out


## Put back a batch that couldn't be sent.
func give_back(batch: Array) -> void:
	_mutex.lock()
	_queue = batch + _queue
	_mutex.unlock()


func _add(kind: String, message: String, location: String, detail: String) -> void:
	var key := message + "|" + location
	_mutex.lock()
	if _seen.has(key):
		_seen[key].count += 1
		if not _queue.has(_seen[key]):
			_queue.append(_seen[key])   # already sent once: send the new count too
	elif _seen.size() < MAX_PER_SESSION:
		var e := {"kind": kind, "message": message.left(500), "location": location.left(200), "detail": detail.left(4000), "count": 1}
		_seen[key] = e
		_queue.append(e)
	_mutex.unlock()


## The last lines of the previous session's log (Godot keeps old logs as godot<date>.log).
static func _last_log_tail(lines: int) -> String:
	var dir := "user://logs"
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("godot") and f.ends_with(".log") and f != "godot.log":
			files.append(f)
	if files.is_empty():
		return ""
	files.sort()
	var text := FileAccess.get_file_as_string("%s/%s" % [dir, files[-1]])
	var all := text.strip_edges().split("\n")
	return "\n".join(all.slice(maxi(0, all.size() - lines)))
