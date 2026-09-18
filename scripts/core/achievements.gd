class_name Achievements
extends RefCounted

## Goals that give the sandbox a direction, in the spirit of the classic
## advancement list. Every entry says what fires it:
##
##   {"kind": "block", "names": [...]}  a block broken or placed
##   {"kind": "item",  "names": [...]}  an item crafted, smelted or picked up
##   {"kind": "event", "event": "..."}  a named gameplay moment
##
## The list is data, so the HUD, the `/achievements` command and the smoke test
## all read the same source. Progress is saved per world.

const LIST: Array = [
	{"id": "getting_wood", "title": "Getting Wood", "desc": "Break a tree trunk",
		"kind": "block", "names": ["oak_log", "birch_log", "spruce_log", "jungle_log"]},
	{"id": "benchmarking", "title": "Benchmarking", "desc": "Craft a crafting table",
		"kind": "item", "names": ["crafting_table"]},
	{"id": "time_to_mine", "title": "Time to Mine!", "desc": "Mine some stone",
		"kind": "block", "names": ["stone", "cobblestone"]},
	{"id": "hot_topic", "title": "Hot Topic", "desc": "Craft a furnace",
		"kind": "item", "names": ["furnace"]},
	{"id": "stone_age", "title": "Stone Age", "desc": "Craft a stone pickaxe",
		"kind": "item", "names": ["stone_pickaxe"]},
	{"id": "acquire_hardware", "title": "Acquire Hardware", "desc": "Smelt an iron ingot",
		"kind": "item", "names": ["iron_ingot"]},
	{"id": "bake_bread", "title": "Bake Bread", "desc": "Craft a loaf of bread",
		"kind": "item", "names": ["bread"]},
	{"id": "diamonds", "title": "DIAMONDS!", "desc": "Find a diamond ore",
		"kind": "block", "names": ["diamond_ore"]},
	{"id": "what_a_deal", "title": "What a Deal!", "desc": "Trade with a villager",
		"kind": "event", "event": "trade"},
	{"id": "monster_hunter", "title": "Monster Hunter", "desc": "Defeat a hostile mob",
		"kind": "event", "event": "hostile_kill"},
	{"id": "sweet_dreams", "title": "Sweet Dreams", "desc": "Sleep in a bed",
		"kind": "event", "event": "sleep"},
	{"id": "signature", "title": "Signature", "desc": "Write on a sign",
		"kind": "event", "event": "sign"},
	{"id": "automation", "title": "Automation", "desc": "Place a hopper",
		"kind": "event", "event": "hopper"},
	{"id": "village_tour", "title": "Village Tour", "desc": "Reach a village",
		"kind": "event", "event": "village"},
	{"id": "we_need_to_go_deeper", "title": "We Need to Go Deeper",
		"desc": "Reach y = 16 or lower", "kind": "event", "event": "depth"},
	{"id": "sky_high", "title": "Sky High", "desc": "Climb to y = 120",
		"kind": "event", "event": "height"},
]

static var _unlocked: Array[String] = []


static func all() -> Array:
	return LIST


static func total() -> int:
	return LIST.size()


static func find(achievement_id: String) -> Dictionary:
	for entry in LIST:
		if str(entry["id"]) == achievement_id:
			return entry
	return {}


## Unlocks an achievement. Returns true only the first time, so callers can use
## the result to decide whether to show a toast.
static func unlock(achievement_id: String) -> bool:
	if achievement_id == "" or find(achievement_id).is_empty():
		return false
	if _unlocked.has(achievement_id):
		return false
	_unlocked.append(achievement_id)
	return true


static func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


static func unlocked_count() -> int:
	return _unlocked.size()


## Every achievement whose "kind" matches and whose name list contains `name`.
static func unlock_matching(kind: String, name: String) -> Array:
	var fresh: Array = []
	for entry in LIST:
		if str(entry.get("kind", "")) != kind:
			continue
		var names: Array = entry.get("names", [])
		if not names.has(name):
			continue
		if unlock(str(entry["id"])):
			fresh.append(str(entry["id"]))
	return fresh


static func unlock_for_block(block_id: int) -> Array:
	if block_id < 0:
		return []
	return unlock_matching("block", Blocks.name_of(block_id))


static func unlock_for_item(item_id: int) -> Array:
	if item_id < 0:
		return []
	return unlock_matching("item", Items.name_of(item_id))


static func unlock_for_event(event: String) -> Array:
	var fresh: Array = []
	for entry in LIST:
		if str(entry.get("kind", "")) != "event":
			continue
		if str(entry.get("event", "")) != event:
			continue
		if unlock(str(entry["id"])):
			fresh.append(str(entry["id"]))
	return fresh


static func title_of(achievement_id: String) -> String:
	return str(find(achievement_id).get("title", achievement_id))


## Unlocked ids in list order, which is also the order saved to disk.
static func serialize() -> Array:
	var out: Array = []
	for entry in LIST:
		if _unlocked.has(str(entry["id"])):
			out.append(str(entry["id"]))
	return out


static func deserialize(data: Array) -> void:
	reset()
	for value in data:
		unlock(str(value))


static func reset() -> void:
	_unlocked.clear()
