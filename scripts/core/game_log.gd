extends Node

## Autoload `GameLog`: a tiny append-only journal.
##
## A phone keeps no console, so when a build dies on a device there is normally
## nothing to look at. Every line written here also goes to `user://log.txt` and
## is flushed immediately, which means the trail survives a hard crash or an
## ANR kill. The main menu can show that file and copy it, so a report can be
## "here are the last lines" instead of "it crashed".
##
## Usage: `GameLog.step("world")` for milestones, `GameLog.write("...")` for
## anything else. Both print to stdout as well, so `adb logcat` sees them too.

const PATH: String = "user://log.txt"
const MAX_BYTES: int = 128 * 1024
const MAX_LINES: int = 400

var _lines: PackedStringArray = PackedStringArray()
var _file: FileAccess


func _ready() -> void:
	_open()
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	write("session start - Godot %s, %s, renderer %s, worker threads %d" % [
		Engine.get_version_info()["string"], OS.get_name(), renderer, worker_thread_count()])


## Opens the journal and carries the previous session over, so the lines right
## before a crash are still there after the restart.
func _open() -> void:
	var previous: PackedStringArray = PackedStringArray()
	if FileAccess.file_exists(PATH):
		var handle := FileAccess.open(PATH, FileAccess.READ)
		if handle != null:
			var text: String = handle.get_as_text()
			handle.close()
			# A journal bigger than the cap is not worth replaying; start over.
			if text.length() <= MAX_BYTES:
				previous = text.split("\n", false)
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("GameLog could not open %s" % PATH)
		return
	if previous.size() > MAX_LINES:
		previous = previous.slice(previous.size() - MAX_LINES)
	_lines = previous
	for line in _lines:
		_file.store_line(line)
	_file.flush()


## Appends one line. Frame number included: the last line before a crash
## usually names the step that was running.
func write(message: String) -> void:
	if _lines.size() >= MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_lines.append(line_for(message))
	print("Blockcraft: ", message)
	if _file != null:
		_file.store_line(_lines[-1])
		_file.flush()


## Stamps a message the way both the journal and the console show it.
static func line_for(message: String) -> String:
	return "[%s f%d] %s" % [Time.get_time_string_from_system(), Engine.get_process_frames(), message]


func step(name: String) -> void:
	write("step: %s" % name)


func clear() -> void:
	_lines.clear()
	if _file != null:
		_file.close()
		_file = FileAccess.open(PATH, FileAccess.WRITE)
		if _file != null:
			_file.flush()


## The last `count` lines, oldest first, ready to show or copy.
func tail(count: int = 200) -> String:
	var from: int = maxi(0, _lines.size() - count)
	return "\n".join(_lines.slice(from)) if _lines.size() > 0 else ""


func line_count() -> int:
	return _lines.size()


## How many worker threads the pool really has.
##
## A WorkerThreadPool with no threads runs every task on the calling thread, so
## counting the distinct threads that ran a small group task tells the truth
## about `threading/worker_pool/max_threads`: -1 is auto (one worker per core)
## and anything >= 0 is literal, which is why 0 silently serialises the whole
## game onto the main thread.
static func worker_thread_count() -> int:
	var caller: int = OS.get_thread_caller_id()
	var seen: Dictionary = {}
	var guard := Mutex.new()
	var task: int = WorkerThreadPool.add_group_task(func(_index: int) -> void:
		guard.lock()
		seen[OS.get_thread_caller_id()] = true
		guard.unlock()
	, 16, -1, false)
	WorkerThreadPool.wait_for_group_task_completion(task)
	seen.erase(caller)
	return seen.size()
