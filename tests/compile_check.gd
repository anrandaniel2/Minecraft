extends Node

## Loads every GDScript in the project, so a file that nothing else references
## still has to compile. Run it headless from the repository root:
##
##     godot --headless --path . res://tests/compile_check.tscn
##
## A scene is used instead of `--script` on purpose: `--script` returns before
## the autoloads are registered, and then every script that mentions
## `Settings`, `Registry` or `MpManager` would look broken.
##
## The exit code is non-zero when a script fails to load, which is how CI keeps
## dead code (a helper nothing calls, a constant that does not exist) from
## rotting silently.

const ROOTS: Array[String] = ["res://scripts", "res://tests"]


func _ready() -> void:
	var paths: Array[String] = []
	for root in ROOTS:
		_collect(root, paths)
	paths.sort()
	var broken: Array[String] = []
	for path in paths:
		var script: Variant = load(path)
		if script == null:
			broken.append("%s (could not be loaded)" % path)
		elif not (script as GDScript).is_valid():
			broken.append("%s (did not compile)" % path)
	print("Blockcraft: compiled %d scripts, %d broken" % [paths.size(), broken.size()])
	for problem in broken:
		print("::error::%s" % problem)
		printerr("BROKEN %s" % problem)
	get_tree().quit(1 if not broken.is_empty() else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	for name in dir.get_directories():
		_collect(dir_path.path_join(name), out)
