class_name Trades
extends RefCounted

## Villager professions and their offers.
##
## An offer is {"give": item_name, "give_count": n, "get": item_name,
## "get_count": n}. Every profession also has a "buy" offer that takes emeralds,
## so players can turn a farm into gear without a trip to a distant cave.

const PROFESSIONS: Dictionary = {
	"farmer": {
		"title": "Farmer",
		"offers": [
			{"give": "wheat", "give_count": 18, "get": "emerald", "get_count": 1},
			{"give": "carrot", "give_count": 16, "get": "emerald", "get_count": 1},
			{"give": "potato", "give_count": 16, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 1, "get": "bread", "get_count": 6},
			{"give": "emerald", "give_count": 3, "get": "wheat_seeds", "get_count": 12},
		],
	},
	"librarian": {
		"title": "Librarian",
		"offers": [
			{"give": "paper", "give_count": 22, "get": "emerald", "get_count": 1},
			{"give": "book", "give_count": 2, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 4, "get": "book", "get_count": 3},
			{"give": "emerald", "give_count": 8, "get": "lapis_lazuli", "get_count": 4},
			{"give": "emerald", "give_count": 12, "get": "bookshelf", "get_count": 1},
		],
	},
	"blacksmith": {
		"title": "Blacksmith",
		"offers": [
			{"give": "coal", "give_count": 15, "get": "emerald", "get_count": 1},
			{"give": "iron_ingot", "give_count": 4, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 3, "get": "iron_ingot", "get_count": 2},
			{"give": "emerald", "give_count": 10, "get": "diamond", "get_count": 1},
			{"give": "emerald", "give_count": 6, "get": "iron_pickaxe", "get_count": 1},
		],
	},
	"butcher": {
		"title": "Butcher",
		"offers": [
			{"give": "beef", "give_count": 10, "get": "emerald", "get_count": 1},
			{"give": "mutton", "give_count": 12, "get": "emerald", "get_count": 1},
			{"give": "leather", "give_count": 8, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 2, "get": "cooked_porkchop", "get_count": 3},
			{"give": "emerald", "give_count": 4, "get": "leather_leggings", "get_count": 1},
		],
	},
	"cleric": {
		"title": "Cleric",
		"offers": [
			{"give": "rotten_flesh", "give_count": 20, "get": "emerald", "get_count": 1},
			{"give": "gold_ingot", "give_count": 3, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 3, "get": "redstone", "get_count": 4},
			{"give": "emerald", "give_count": 5, "get": "glowstone_dust", "get_count": 2},
			{"give": "emerald", "give_count": 12, "get": "golden_apple", "get_count": 1},
		],
	},
	"cartographer": {
		"title": "Cartographer",
		"offers": [
			{"give": "paper", "give_count": 24, "get": "emerald", "get_count": 1},
			{"give": "emerald", "give_count": 7, "get": "paper", "get_count": 16},
			{"give": "emerald", "give_count": 14, "get": "bow", "get_count": 1},
			{"give": "emerald", "give_count": 6, "get": "arrow", "get_count": 16},
			{"give": "emerald", "give_count": 9, "get": "flint_and_steel", "get_count": 1},
		],
	},
}

const PROFESSION_NAMES: PackedStringArray = ["farmer", "librarian", "blacksmith", "butcher",
	"cleric", "cartographer"]


static func profession_for(seed_value: int) -> String:
	return PROFESSION_NAMES[absi(seed_value) % PROFESSION_NAMES.size()]


static func title(profession: String) -> String:
	var entry: Dictionary = PROFESSIONS.get(profession, {})
	return str(entry.get("title", profession.capitalize()))


static func offers(profession: String) -> Array:
	var entry: Dictionary = PROFESSIONS.get(profession, {})
	return entry.get("offers", [])


## Checks whether a trade can be made and how many times in a row.
static func affordable(offer: Dictionary, inventory: BlockContainer) -> int:
	var give_id: int = Items.id(str(offer.get("give", "")))
	if give_id < 0:
		return 0
	var needed: int = maxi(1, int(offer.get("give_count", 1)))
	return inventory.count_of(give_id) / needed


static func apply_offer(offer: Dictionary, inventory: BlockContainer) -> bool:
	var give_id: int = Items.id(str(offer.get("give", "")))
	var get_id: int = Items.id(str(offer.get("get", "")))
	if give_id < 0 or get_id < 0:
		return false
	var give_count: int = maxi(1, int(offer.get("give_count", 1)))
	var get_count: int = maxi(1, int(offer.get("get_count", 1)))
	if inventory.count_of(give_id) < give_count:
		return false
	if not inventory.has_room_for(get_id, get_count) and inventory.count_of(get_id) == 0:
		return false
	inventory.remove(give_id, give_count)
	inventory.add(get_id, get_count)
	return true


static func describe(offer: Dictionary) -> String:
	var give_id: int = Items.id(str(offer.get("give", "")))
	var get_id: int = Items.id(str(offer.get("get", "")))
	return "%d x %s  →  %d x %s" % [int(offer.get("give_count", 1)), Items.display_name(give_id),
		int(offer.get("get_count", 1)), Items.display_name(get_id)]
