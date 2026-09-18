extends Node

## World persistence (autoload name: SaveManager).
##
## A world lives in `user://saves/<slot>/`:
##   world.json      metadata + player state + world state (seed, time, weather)
##   chunks.bin      compressed block edits (terrain is regenerated from the seed)
##   containers.json chest/furnace/dispenser contents
##   entities.json   mobs that were alive when the world was saved
##
## Slot names are directory names, so they are sanitised; display names live in
## world.json which lets players rename a world without moving files.

const SAVE_DIR: String = "user://saves"
const WORLD_FILE: String = "world.json"
const CHUNK_FILE: String = "chunks.bin"
const CONTAINER_FILE: String = "containers.json"
const ENTITY_FILE: String = "entities.json"
const FORMAT_VERSION: int = 2

signal world_saved(slot: String)
signal world_loaded(slot: String)

## Set by the world-select menu and consumed by the game scene.
var pending_world: Dictionary = {}
var pending_is_new: bool = false
var current_slot: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Migrate the legacy single-slot autosave name so old builds keep working.
	if DirAccess.dir_exists_absolute("user://world_data") and not DirAccess.dir_exists_absolute(slot_dir("default")):
		pass


func slot_dir(slot: String) -> String:
	return "%s/%s" % [SAVE_DIR, slot]


func sanitize(name: String) -> String:
	var out := name.strip_edges().to_lower()
	out = out.replace(" ", "_")
	var clean := ""
	for index in out.length():
		var ch := out[index]
		if ch.is_valid_identifier() or ch >= "0" and ch <= "9" or ch == "_" or ch == "-":
			clean += ch
	if clean == "":
		clean = "world_%d" % (Time.get_unix_time_from_system() as int)
	return clean.substr(0, 32)


func unique_slot(base: String) -> String:
	var slot: String = sanitize(base)
	var candidate: String = slot
	var index: int = 2
	while DirAccess.dir_exists_absolute(slot_dir(candidate)):
		candidate = "%s_%d" % [slot, index]
		index += 1
	return candidate


# ---------------------------------------------------------------------------
# Listing / creating
# ---------------------------------------------------------------------------


func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			var meta := read_meta(name)
			if not meta.is_empty():
				meta["slot"] = name
				meta["size_bytes"] = _dir_size(slot_dir(name))
				out.append(meta)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


func read_meta(slot: String) -> Dictionary:
	var path := "%s/%s" % [slot_dir(slot), WORLD_FILE]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func create_world(name: String, seed_value: int, gamemode: String, extra: Dictionary = {}) -> Dictionary:
	var slot: String = unique_slot(name)
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	var world := {
		"format": FORMAT_VERSION,
		"slot": slot,
		"name": name.strip_edges() if name.strip_edges() != "" else "New World",
		"seed": seed_value,
		"gamemode": gamemode,
		"difficulty": int(Settings.get_value("difficulty")),
		"created": Time.get_unix_time_from_system(),
		"last_played": Time.get_unix_time_from_system(),
		"played_seconds": 0.0,
		"day_time": 0.3,
		"weather": "clear",
		"player": {},
	}
	for key in extra:
		world[key] = extra[key]
	_write_json("%s/%s" % [slot_dir(slot), WORLD_FILE], world)
	return world


## Creates a random but human-readable seed.
static func random_seed() -> int:
	return int(randi()) % 100000000


func delete_world(slot: String) -> void:
	_delete_dir_recursive(slot_dir(slot))


func duplicate_world(slot: String) -> String:
	var source: Dictionary = read_meta(slot)
	if source.is_empty():
		return ""
	var new_slot: String = unique_slot(str(source.get("name", slot)) + "_copy")
	_copy_dir(slot_dir(slot), slot_dir(new_slot))
	var meta := read_meta(new_slot)
	meta["name"] = "%s (copy)" % str(meta.get("name", "World"))
	meta["created"] = Time.get_unix_time_from_system()
	_write_json("%s/%s" % [slot_dir(new_slot), WORLD_FILE], meta)
	return new_slot


func rename_world(slot: String, new_name: String) -> void:
	var meta := read_meta(slot)
	if meta.is_empty():
		return
	meta["name"] = new_name.strip_edges()
	_write_json("%s/%s" % [slot_dir(slot), WORLD_FILE], meta)


# ---------------------------------------------------------------------------
# Saving / loading
# ---------------------------------------------------------------------------


func save_world(slot: String, state: Dictionary, chunks: PackedByteArray,
		containers: Array, entities: Array) -> bool:
	if slot == "":
		return false
	var dir_path := slot_dir(slot)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var meta := read_meta(slot)
	if meta.is_empty():
		meta = {"format": FORMAT_VERSION, "name": slot, "seed": 0, "gamemode": "survival"}
	for key in state:
		meta[key] = state[key]
	meta["last_played"] = Time.get_unix_time_from_system()
	meta["format"] = FORMAT_VERSION
	var ok := _write_json("%s/%s" % [dir_path, WORLD_FILE], meta)
	ok = _write_bytes("%s/%s" % [dir_path, CHUNK_FILE], chunks) and ok
	ok = _write_json("%s/%s" % [dir_path, CONTAINER_FILE], {"containers": containers}) and ok
	ok = _write_json("%s/%s" % [dir_path, ENTITY_FILE], {"entities": entities}) and ok
	if ok:
		world_saved.emit(slot)
	return ok


func load_chunks(slot: String) -> PackedByteArray:
	var path := "%s/%s" % [slot_dir(slot), CHUNK_FILE]
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())


func load_containers(slot: String) -> Array:
	var path := "%s/%s" % [slot_dir(slot), CONTAINER_FILE]
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("containers", [])


func load_entities(slot: String) -> Array:
	var path := "%s/%s" % [slot_dir(slot), ENTITY_FILE]
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("entities", [])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(data))
	return true


func _write_bytes(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return false
	file.store_buffer(data)
	return true


func _dir_size(path: String) -> int:
	var total: int = 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var file := FileAccess.open("%s/%s" % [path, name], FileAccess.READ)
			if file != null:
				total += file.get_length()
		name = dir.get_next()
	dir.list_dir_end()
	return total


func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var source := FileAccess.open("%s/%s" % [from, name], FileAccess.READ)
			if source != null:
				var target := FileAccess.open("%s/%s" % [to, name], FileAccess.WRITE)
				if target != null:
					target.store_buffer(source.get_buffer(source.get_length()))
		name = dir.get_next()
	dir.list_dir_end()


func _delete_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_delete_dir_recursive("%s/%s" % [path, name])
		else:
			DirAccess.remove_absolute("%s/%s" % [path, name])
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


static func format_play_time(seconds: float) -> String:
	var total := int(seconds)
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes


static func format_date(unix_time: float) -> String:
	var dict := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d %02d:%02d" % [dict["year"], dict["month"], dict["day"],
		dict["hour"], dict["minute"]]
