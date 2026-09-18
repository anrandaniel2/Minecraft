class_name Items
extends RefCounted

## Item registry. Block items mirror the block registry (same id, so a stack id
## resolves either way); pure items start at ITEM_ID_BASE.

const ITEM_ID_BASE: int = 256

static var defs: Array[ItemDef] = []
static var ids: Dictionary = {}
static var _built: bool = false
static var _next_item_id: int = ITEM_ID_BASE

# Tool tier material profiles: id suffix -> [tier, speed, durability, attack, fuel]
const TOOL_MATERIALS: Dictionary = {
	"wood": [Blocks.TIER_WOOD, 2.0, 60, 2.0, 0.0],
	"stone": [Blocks.TIER_STONE, 4.0, 132, 3.0, 0.0],
	"iron": [Blocks.TIER_IRON, 6.0, 251, 4.0, 0.0],
	"gold": [Blocks.TIER_IRON, 12.0, 33, 2.0, 0.0],
	"diamond": [Blocks.TIER_DIAMOND, 8.0, 1562, 5.0, 0.0],
}

const TOOL_KINDS: PackedStringArray = ["pickaxe", "axe", "shovel", "sword", "hoe"]

# Armour: material -> [slot points array (head, chest, legs, feet), durability, toughness]
const ARMOR_MATERIALS: Dictionary = {
	"leather": [[1, 3, 2, 1], 80, 0.0],
	"iron": [[2, 6, 5, 2], 240, 0.0],
	"gold": [[2, 5, 3, 1], 112, 0.0],
	"diamond": [[3, 8, 6, 3], 528, 2.0],
}
const ARMOR_SLOTS: PackedStringArray = ["helmet", "chestplate", "leggings", "boots"]

# Food: name -> [hunger, saturation, heal, always_edible]
const FOODS: Dictionary = {
	"apple": [4, 2.4, 0.0, false],
	"golden_apple": [4, 9.6, 4.0, true],
	"bread": [5, 6.0, 0.0, false],
	"carrot": [3, 3.6, 0.0, false],
	"potato": [1, 0.6, 0.0, false],
	"baked_potato": [5, 6.0, 0.0, false],
	"cookie": [2, 0.4, 0.0, false],
	"melon_slice": [2, 1.2, 0.0, false],
	"pumpkin_pie": [8, 4.8, 0.0, false],
	"mushroom_stew": [6, 7.2, 0.0, false],
	"rotten_flesh": [4, 0.8, 0.0, true],
	"porkchop": [3, 1.8, 0.0, false],
	"cooked_porkchop": [8, 12.8, 0.0, false],
	"beef": [3, 1.8, 0.0, false],
	"steak": [8, 12.8, 0.0, false],
	"chicken": [2, 1.2, 0.0, false],
	"cooked_chicken": [6, 7.2, 0.0, false],
	"mutton": [2, 1.2, 0.0, false],
	"cooked_mutton": [6, 9.6, 0.0, false],
}

# Pure items: name -> [icon, extra properties]
const EXTRA_ITEMS: Dictionary = {
	"stick": {"fuel": 5.0},
	"coal": {"fuel": 80.0},
	"charcoal": {"fuel": 80.0},
	"raw_iron": {},
	"raw_gold": {},
	"raw_copper": {},
	"iron_ingot": {},
	"gold_ingot": {},
	"copper_ingot": {},
	"diamond": {},
	"emerald": {},
	"lapis_lazuli": {},
	"redstone": {},
	"glowstone_dust": {},
	"gunpowder": {},
	"string": {},
	"feather": {},
	"leather": {},
	"bone": {},
	"bone_meal": {},
	"flint": {},
	"clay_ball": {},
	"brick": {},
	"paper": {},
	"book": {},
	"wheat": {},
	"wheat_seeds": {},
	"sugar": {},
	"sugar_cane": {},
	"egg": {},
	"slimeball": {},
	"snowball": {},
	"arrow": {},
	"bucket": {"stack": 16},
	"water_bucket": {"stack": 1},
	"lava_bucket": {"stack": 1, "fuel": 1000.0},
	"flint_and_steel": {"stack": 1, "durability": 64},
	"bow": {"stack": 1, "durability": 384},
	"shears": {"stack": 1, "durability": 238},
	"torch": {},
}

# Item -> block it places (block items are auto-registered; these are the extras)
const ITEM_PLACES_BLOCK: Dictionary = {
	"water_bucket": "water",
	"lava_bucket": "lava",
	"sugar_cane": "sugar_cane",
	"wheat_seeds": "wheat",
	"carrot": "carrots",
	"potato": "potatoes",
}


static func build() -> void:
	if _built:
		return
	_built = true
	defs.clear()
	ids.clear()
	_next_item_id = ITEM_ID_BASE
	# 1) Block items keep the block's id (0..255).
	for block_id in Blocks.defs.size():
		var block_def: BlockDef = Blocks.defs[block_id]
		if block_def.name == "air":
			continue
		var item := ItemDef.new()
		item.id = block_id
		item.name = block_def.name
		item.display_name = block_def.display_name
		item.block = block_id
		item.icon = _block_icon_tile(block_def)
		item.stack = block_def.stack
		item.fuel = block_def.fuel
		_pad_to(block_id)
		defs[block_id] = item
		ids[block_def.name] = block_id
	# 2) Pure items.
	for item_name in EXTRA_ITEMS:
		var props: Dictionary = EXTRA_ITEMS[item_name]
		# A few names (torch, wheat, sugar cane) are both blocks and items. The
		# block item keeps the id and the atlas icon, and only the extra
		# properties are merged in, so the name never resolves to a stray twin.
		var existing: ItemDef = def_by_name(item_name)
		var item: ItemDef = null
		if existing != null and existing.is_block():
			item = existing
		else:
			item = ItemDef.new()
			item.name = item_name
			item.display_name = Blocks._prettify(item_name)
			item.icon = item_name
			item.stack = int(props.get("stack", 64))
			_register(item)
		item.fuel = float(props.get("fuel", item.fuel))
		item.durability = int(props.get("durability", item.durability))
		if props.has("stack"):
			item.stack = int(props["stack"])
	# 3) Foods.
	for food_name in FOODS:
		var food := _ensure(food_name)
		var stats: Array = FOODS[food_name]
		food.hunger = int(stats[0])
		food.saturation = float(stats[1])
		food.heal_amount = float(stats[2])
		food.always_edible = bool(stats[3])
		if food.display_name == "":
			food.display_name = Blocks._prettify(food_name)
		if food.icon == "":
			food.icon = food_name
	# 4) Tools.
	for material in TOOL_MATERIALS:
		var profile: Array = TOOL_MATERIALS[material]
		for kind in TOOL_KINDS:
			var item_name := "%s_%s" % [material, kind]
			var tool := _ensure(item_name)
			tool.icon = item_name
			tool.display_name = "%s %s" % [Blocks._prettify(material), Blocks._prettify(kind)]
			tool.tool_kind = kind
			tool.tool_tier = int(profile[0])
			tool.tool_speed = float(profile[1])
			tool.durability = int(profile[2])
			tool.attack = float(profile[3])
			tool.stack = 1
			if kind == "sword":
				tool.attack += 2.0
			if kind == "shears":
				tool.tool_kind = "shears"
	# 5) Armour.
	for material in ARMOR_MATERIALS:
		var armor_stats: Array = ARMOR_MATERIALS[material]
		for slot in ARMOR_SLOTS.size():
			var item_name := "%s_%s" % [material, ARMOR_SLOTS[slot]]
			var armor := _ensure(item_name)
			armor.icon = item_name
			armor.display_name = "%s %s" % [Blocks._prettify(material), Blocks._prettify(ARMOR_SLOTS[slot])]
			armor.armor_slot = slot
			armor.armor_points = int(armor_stats[0][slot])
			armor.armor_toughness = float(armor_stats[2])
			armor.durability = int(armor_stats[1])
			armor.stack = 1
	# 6) Shears fire a fake tool profile.
	var shears := _ensure("shears")
	shears.tool_kind = "shears"
	shears.tool_tier = Blocks.TIER_IRON
	shears.tool_speed = 5.0
	shears.stack = 1


static func _pad_to(index: int) -> void:
	while defs.size() <= index:
		defs.append(null)


static func _register(item: ItemDef) -> int:
	item.id = _next_item_id
	_next_item_id += 1
	_pad_to(item.id)
	defs[item.id] = item
	ids[item.name] = item.id
	return item.id


static func _ensure(item_name: String) -> ItemDef:
	var existing: int = ids.get(item_name, -1)
	if existing >= 0 and defs[existing] != null:
		return defs[existing]
	var item := ItemDef.new()
	item.name = item_name
	item.display_name = Blocks._prettify(item_name)
	_register(item)
	return item


static func _block_icon_tile(block_def: BlockDef) -> String:
	if block_def.item_icon != "":
		return block_def.item_icon
	var spec := block_def.tile_names
	if spec.has("all"):
		return str(spec["all"])
	if spec.has("side"):
		return str(spec["side"])
	if spec.has("top"):
		return str(spec["top"])
	return ""


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------


static func id(item_name: String) -> int:
	return ids.get(item_name, -1)


static func def_of(item_id: int) -> ItemDef:
	if item_id < 0 or item_id >= defs.size():
		return null
	return defs[item_id]


static func def_by_name(item_name: String) -> ItemDef:
	var item_id: int = id(item_name)
	if item_id < 0:
		return null
	return defs[item_id]


static func name_of(item_id: int) -> String:
	var item := def_of(item_id)
	return item.name if item != null else ""


static func display_name(item_id: int) -> String:
	var item := def_of(item_id)
	return item.display_name if item != null else ""


static func places_block(item_id: int) -> int:
	var item := def_of(item_id)
	if item == null:
		return -1
	return item.block


static func is_placeable(item_id: int) -> bool:
	return places_block(item_id) >= 0


static func max_stack(item_id: int) -> int:
	var item := def_of(item_id)
	if item == null:
		return 64
	return item.max_stack()


static func tool_kind(item_id: int) -> String:
	var item := def_of(item_id)
	return item.tool_kind if item != null else ""


static func tool_tier(item_id: int) -> int:
	var item := def_of(item_id)
	return item.tool_tier if item != null else Blocks.TIER_NONE


static func tool_speed(item_id: int) -> float:
	var item := def_of(item_id)
	if item == null or item.tool_kind == "":
		return 1.0
	return item.tool_speed


static func attack_damage(item_id: int) -> float:
	var item := def_of(item_id)
	return item.attack if item != null else 1.0


static func durability(item_id: int) -> int:
	var item := def_of(item_id)
	return item.durability if item != null else 0


## Every item that can appear in a creative inventory, in a stable order.
static func creative_list() -> Array:
	var out: Array = []
	for item in defs:
		if item == null:
			continue
		if item.name == "air":
			continue
		out.append(item.id)
	# Order: by category-ish groups so the creative grid reads sensibly.
	var order := ["tools", "armor", "food", "blocks", "misc"]
	var buckets := {"tools": [], "armor": [], "food": [], "blocks": [], "misc": []}
	for item_id in out:
		var item: ItemDef = defs[item_id]
		if item.is_tool() or item.is_armor():
			buckets["tools" if item.is_tool() else "armor"].append(item_id)
		elif item.is_food():
			buckets["food"].append(item_id)
		elif item.is_block():
			buckets["blocks"].append(item_id)
		else:
			buckets["misc"].append(item_id)
	var result: Array = []
	for group in order:
		result.append_array(buckets[group])
	return result


## Seconds of furnace burn time this item provides (0 when it is not a fuel).
static func smelt_fuel(item_id: int) -> float:
	var item := def_of(item_id)
	if item == null:
		return 0.0
	if item.fuel > 0.0:
		return item.fuel
	return Recipes.fuel_seconds(item_id)
