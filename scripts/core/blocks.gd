class_name Blocks
extends RefCounted

## Block registry: every placeable block, its atlas tiles, physics and drops.
##
## Block ids are dense ints assigned in registration order (air is 0), which
## keeps chunk storage at one byte per voxel. Hot per-block properties are
## mirrored into flat arrays (`opaque`, `solid`, ...) indexed by id so the
## mesher and physics queries never touch a Dictionary.
##
## Faces are indexed the same way everywhere in the codebase:
##   0 = +X (east)   1 = -X (west)   2 = +Y (up)
##   3 = -Y (down)   4 = +Z (south)  5 = -Z (north)
##
## A block's `meta` byte (stored per voxel in the chunk) encodes orientation in
## its low 3 bits and block-specific flags/states in the high bits.

# --- shape constants -------------------------------------------------------
const SHAPE_CUBE: int = 0       # full block, greedy meshed
const SHAPE_CROSS: int = 1      # two crossed quads (plants)
const SHAPE_LIQUID: int = 2     # water/lava, lowered surface
const SHAPE_TORCH: int = 3      # small crossed post with a light
const SHAPE_SLAB: int = 4       # bottom half block
const SHAPE_LAYER: int = 5      # snow layer / pressure plate (thin box)
const SHAPE_LADDER: int = 6     # flat quad against a wall, climbable
const SHAPE_FARMLAND: int = 7   # cube with a lowered top surface

# --- tool tiers ------------------------------------------------------------
const TIER_NONE: int = 0
const TIER_WOOD: int = 1
const TIER_STONE: int = 2
const TIER_IRON: int = 3
const TIER_DIAMOND: int = 4

# --- sound groups ----------------------------------------------------------
const SOUND_STONE: int = 0
const SOUND_WOOD: int = 1
const SOUND_GRASS: int = 2
const SOUND_SAND: int = 3
const SOUND_GLASS: int = 4
const SOUND_WOOL: int = 5
const SOUND_GRAVEL: int = 6
const SOUND_PLANT: int = 7

static var defs: Array[BlockDef] = []
static var ids: Dictionary = {}                 # name → id
static var item_drops: Array = []               # id → Array[{item, count, chance}]
static var tiles: Array = []                    # id → Array[Vector2i] (6 faces)
static var front_tiles: Array = []              # id → Vector2i (facing tile) or (-1,-1)
static var tile_size: int = 16
static var atlas_cell: int = 24
static var atlas_cols: int = 16
static var atlas_size: int = 384
static var _built: bool = false

# Flat lookup tables (indexed by block id) for hot paths.
static var opaque: PackedByteArray = PackedByteArray()
static var solid: PackedByteArray = PackedByteArray()
static var liquid: PackedByteArray = PackedByteArray()
static var emission: PackedByteArray = PackedByteArray()
static var shape_of: PackedByteArray = PackedByteArray()
static var hardness_of: PackedFloat32Array = PackedFloat32Array()
static var tier_of: PackedByteArray = PackedByteArray()
static var tool_of: Array[String] = []
static var sound_of: PackedByteArray = PackedByteArray()
static var cutout: PackedByteArray = PackedByteArray()
static var replaceable: PackedByteArray = PackedByteArray()
static var gravity: PackedByteArray = PackedByteArray()
static var burning: PackedByteArray = PackedByteArray()

# Frequently used ids, resolved once.
static var AIR: int = 0
static var WATER: int = 0
static var LAVA: int = 0
static var GRASS: int = 0
static var DIRT: int = 0
static var STONE: int = 0
static var SAND: int = 0
static var FURNACE: int = 0
static var FURNACE_LIT: int = 0
static var CHEST: int = 0
static var CRAFTING_TABLE: int = 0
static var TORCH: int = 0
static var GLASS: int = 0
static var BEDROCK: int = 0
static var FARMLAND: int = 0
static var WHEAT: int = 0
static var ICE: int = 0
static var SNOWY_GRASS_BLOCK: int = 0
static var SANDSTONE: int = 0
static var COARSE_DIRT: int = 0
static var CLAY: int = 0
static var GRAVEL: int = 0
static var COBBLESTONE: int = 0
static var OAK_LOG: int = 0
static var OAK_LEAVES: int = 0
static var CACTUS: int = 0
static var SUGAR_CANE: int = 0
static var GLOWSTONE: int = 0
static var TNT: int = 0
static var OBSIDIAN: int = 0
static var SNOW_LAYER: int = 0
static var GRANITE: int = 0
static var DIORITE: int = 0
static var ANDESITE: int = 0


static func id(block_name: String) -> int:
	return ids.get(block_name, 0)


static func name_of(block_id: int) -> String:
	if block_id < 0 or block_id >= defs.size():
		return "air"
	return defs[block_id].name


static func def(block_id: int) -> BlockDef:
	if block_id < 0 or block_id >= defs.size():
		return defs[0]
	return defs[block_id]


static func is_air(block_id: int) -> bool:
	return block_id == AIR


static func is_opaque(block_id: int) -> bool:
	return block_id < opaque.size() and opaque[block_id] == 1


static func is_solid(block_id: int) -> bool:
	return block_id < solid.size() and solid[block_id] == 1


static func is_liquid(block_id: int) -> bool:
	return block_id < liquid.size() and liquid[block_id] == 1


static func is_cutout(block_id: int) -> bool:
	return block_id < cutout.size() and cutout[block_id] == 1


static func is_replaceable(block_id: int) -> bool:
	return block_id < replaceable.size() and replaceable[block_id] == 1


static func shape(block_id: int) -> int:
	if block_id < 0 or block_id >= shape_of.size():
		return SHAPE_CUBE
	return shape_of[block_id]


static func light_emission(block_id: int) -> int:
	if block_id < 0 or block_id >= emission.size():
		return 0
	return emission[block_id]


## True when this block hides the neighbouring face (used by the mesher).
static func hides_face(block_id: int, neighbour: int) -> bool:
	if not is_opaque(block_id):
		return false
	if block_id == neighbour and is_liquid(block_id):
		return false
	return true


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

static func _register(
	block_name: String,
	tile_spec: Dictionary,
	opts: Dictionary = {}
) -> int:
	var block_id: int = defs.size()
	var definition := BlockDef.new()
	definition.id = block_id
	definition.name = block_name
	definition.tile_names = _tile_spec_only(tile_spec)
	definition.item_icon = str(opts.get("item_icon", ""))
	definition.display_name = str(opts.get("title", _prettify(block_name)))
	definition.solid = bool(opts.get("solid", true))
	definition.opaque = bool(opts.get("opaque", true))
	definition.liquid = bool(opts.get("liquid", false))
	definition.emission = int(opts.get("light", 0))
	definition.hardness = float(opts.get("hardness", 1.0))
	definition.tool = str(opts.get("tool", ""))
	definition.tier = int(opts.get("tier", TIER_NONE))
	definition.shape = int(opts.get("shape", SHAPE_CUBE))
	definition.sound = int(opts.get("sound", SOUND_STONE))
	definition.drops = opts.get("drops", [])
	definition.gravity = bool(opts.get("gravity", false))
	definition.burning = bool(opts.get("burning", false))
	definition.replaceable = bool(opts.get("replaceable", false))
	definition.cutout = bool(opts.get("cutout", false))
	definition.stack = int(opts.get("stack", 64))
	definition.plantable = bool(opts.get("plantable", false))
	definition.fuel = float(opts.get("fuel", 0.0))
	definition.crafting = str(opts.get("crafting", ""))
	definition.collides = bool(opts.get("collides", definition.solid))
	definition.harvest = str(opts.get("harvest", ""))
	definition.seed_item = str(opts.get("seed", ""))
	definition.container = str(opts.get("container", ""))
	definition.crafting = str(opts.get("crafting", ""))
	definition.xp = int(opts.get("xp_amount", opts.get("xp", 0)))
	definition.climbable = bool(opts.get("climbable", false))
	definition.tile_names = _tile_spec_only(tile_spec)
	defs.append(definition)
	ids[block_name] = block_id

	# Flat lookup tables.
	opaque.resize(block_id + 1)
	solid.resize(block_id + 1)
	liquid.resize(block_id + 1)
	emission.resize(block_id + 1)
	shape_of.resize(block_id + 1)
	hardness_of.resize(block_id + 1)
	tier_of.resize(block_id + 1)
	sound_of.resize(block_id + 1)
	cutout.resize(block_id + 1)
	replaceable.resize(block_id + 1)
	gravity.resize(block_id + 1)
	burning.resize(block_id + 1)
	opaque[block_id] = 1 if definition.opaque else 0
	solid[block_id] = 1 if definition.solid else 0
	liquid[block_id] = 1 if definition.liquid else 0
	emission[block_id] = definition.emission
	shape_of[block_id] = definition.shape
	hardness_of[block_id] = definition.hardness
	tier_of[block_id] = definition.tier
	sound_of[block_id] = definition.sound
	cutout[block_id] = 1 if definition.cutout else 0
	replaceable[block_id] = 1 if definition.replaceable else 0
	gravity[block_id] = 1 if definition.gravity else 0
	burning[block_id] = 1 if definition.burning else 0
	item_drops.append(definition.drops.duplicate())
	tool_of.append(definition.tool)
	# Tile arrays are filled in _resolve_tiles() once the atlas manifest is known.
	tiles.append([])
	front_tiles.append(Vector2i(-1, -1))
	return block_id


## Keeps only the face keys of a tile spec so block data stays separate.
static func _tile_spec_only(spec: Dictionary) -> Dictionary:
	var out := {}
	for key in ["all", "side", "top", "bottom", "front"]:
		if spec.has(key):
			out[key] = spec[key]
	return out


static func _prettify(raw: String) -> String:
	var parts: PackedStringArray = raw.split("_")
	var out: PackedStringArray = []
	for part in parts:
		if part.length() == 0:
			continue
		out.append(part.substr(0, 1).to_upper() + part.substr(1))
	return " ".join(out)


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

static func build() -> void:
	if _built:
		return
	_built = true
	defs.clear()
	ids.clear()
	item_drops.clear()
	tiles.clear()
	front_tiles.clear()
	tool_of.clear()
	opaque = PackedByteArray()
	solid = PackedByteArray()
	liquid = PackedByteArray()
	emission = PackedByteArray()
	shape_of = PackedByteArray()
	hardness_of = PackedFloat32Array()
	tier_of = PackedByteArray()
	sound_of = PackedByteArray()
	cutout = PackedByteArray()
	replaceable = PackedByteArray()
	gravity = PackedByteArray()
	burning = PackedByteArray()

	_register_terrain()
	_register_ores()
	_register_wood()
	_register_plants()
	_register_building()
	_register_devices()
	_register_wool()
	_register_furniture()
	_load_atlas_manifest()
	_resolve_tiles()
	_cache_hot_ids()


static func _register_terrain() -> void:
	_register("air", {}, {
		"title": "Air", "solid": false, "opaque": false, "hardness": 0.0,
		"replaceable": true, "shape": SHAPE_CUBE, "collides": false,
	})
	_register("stone", {"all": "stone"}, {"hardness": 1.5, "tool": "pickaxe", "tier": TIER_WOOD,
		"drops": [{"item": "cobblestone", "count": 1}]})
	_register("granite", {"all": "stone"}, {"title": "Granite", "hardness": 1.5, "tool": "pickaxe",
		"tier": TIER_WOOD, "drops": [{"item": "granite", "count": 1}]})
	_register("diorite", {"all": "stone"}, {"hardness": 1.5, "tool": "pickaxe", "tier": TIER_WOOD,
		"drops": [{"item": "diorite", "count": 1}]})
	_register("andesite", {"all": "stone"}, {"hardness": 1.5, "tool": "pickaxe", "tier": TIER_WOOD,
		"drops": [{"item": "andesite", "count": 1}]})
	_register("cobblestone", {"all": "cobblestone"}, {"hardness": 2.0, "tool": "pickaxe",
		"tier": TIER_WOOD, "drops": [{"item": "cobblestone", "count": 1}]})
	_register("mossy_cobblestone", {"all": "mossy_cobblestone"}, {"hardness": 2.0, "tool": "pickaxe",
		"tier": TIER_WOOD})
	_register("dirt", {"all": "dirt"}, {"hardness": 0.5, "tool": "shovel", "sound": SOUND_GRASS})
	_register("coarse_dirt", {"all": "coarse_dirt"}, {"hardness": 0.5, "tool": "shovel", "sound": SOUND_GRASS})
	_register("grass_block", {"top": "grass_top", "bottom": "dirt", "side": "grass_side"},
		{"title": "Grass Block", "hardness": 0.6, "tool": "shovel", "sound": SOUND_GRASS,
		 "drops": [{"item": "dirt", "count": 1}], "plantable": true})
	_register("snowy_grass_block", {"top": "snow", "bottom": "dirt", "side": "grass_side_snowy"},
		{"title": "Snowy Grass Block", "hardness": 0.6, "tool": "shovel", "sound": SOUND_GRASS,
		 "drops": [{"item": "dirt", "count": 1}]})
	_register("sand", {"all": "sand"}, {"hardness": 0.5, "tool": "shovel", "sound": SOUND_SAND,
		"gravity": true})
	_register("red_sand", {"all": "red_sand"}, {"hardness": 0.5, "tool": "shovel",
		"sound": SOUND_SAND, "gravity": true})
	_register("sandstone", {"top": "sandstone_top", "bottom": "sandstone_bottom",
		"side": "sandstone_side"}, {"hardness": 0.8, "tool": "pickaxe", "tier": TIER_WOOD})
	_register("gravel", {"all": "gravel"}, {"hardness": 0.6, "tool": "shovel", "sound": SOUND_GRAVEL,
		"gravity": true, "drops": [{"item": "gravel", "count": 1},
		{"item": "flint", "count": 1, "chance": 0.15}]})
	_register("clay", {"all": "clay"}, {"hardness": 0.6, "tool": "shovel", "sound": SOUND_GRAVEL,
		"drops": [{"item": "clay_ball", "count": 4}]})
	_register("snow_block", {"all": "snow"}, {"title": "Snow Block", "hardness": 0.2,
		"tool": "shovel", "sound": SOUND_SAND, "drops": [{"item": "snowball", "count": 4}]})
	_register("snow_layer", {"all": "snow"}, {"title": "Snow", "hardness": 0.1, "tool": "shovel",
		"sound": SOUND_SAND, "shape": SHAPE_LAYER, "opaque": false, "solid": false,
		"drops": [{"item": "snowball", "count": 1}]})
	_register("ice", {"all": "ice"}, {"hardness": 0.5, "tool": "pickaxe", "opaque": false,
		"sound": SOUND_GLASS, "drops": [], "cutout": true})
	_register("packed_ice", {"all": "packed_ice"}, {"hardness": 0.5, "tool": "pickaxe"})
	_register("water", {"all": "water"}, {"solid": false, "opaque": false, "liquid": true,
		"shape": SHAPE_LIQUID, "hardness": 100.0, "sound": SOUND_GRASS, "replaceable": true,
		"drops": [], "cutout": true})
	_register("lava", {"all": "lava"}, {"solid": false, "opaque": false, "liquid": true,
		"shape": SHAPE_LIQUID, "light": 15, "hardness": 100.0, "replaceable": true, "drops": [],
		"cutout": true, "sound": SOUND_STONE})
	_register("bedrock", {"all": "bedrock"}, {"hardness": -1.0, "tool": "pickaxe", "tier": TIER_DIAMOND,
		"drops": []})
	_register("obsidian", {"all": "obsidian"}, {"hardness": 12.0, "tool": "pickaxe", "tier": TIER_DIAMOND})
	_register("soul_sand", {"all": "soul_sand"}, {"hardness": 0.5, "tool": "shovel", "sound": SOUND_SAND})


static func _register_ores() -> void:
	var ores := {
		"coal_ore": ["coal", 1],
		"iron_ore": ["raw_iron", 1],
		"copper_ore": ["raw_copper", 2],
		"gold_ore": ["raw_gold", 1],
		"diamond_ore": ["diamond", 1],
		"emerald_ore": ["emerald", 1],
		"redstone_ore": ["redstone", 4],
		"lapis_ore": ["lapis_lazuli", 5],
	}
	var tiers := {
		"coal_ore": TIER_WOOD, "iron_ore": TIER_STONE, "copper_ore": TIER_STONE,
		"gold_ore": TIER_IRON, "diamond_ore": TIER_IRON, "emerald_ore": TIER_IRON,
		"redstone_ore": TIER_IRON, "lapis_ore": TIER_STONE,
	}
	for ore_name in ores:
		var drop: Array = ores[ore_name]
		var xp: int = 1
		if ore_name in ["diamond_ore", "emerald_ore"]:
			xp = 4
		elif ore_name in ["gold_ore", "redstone_ore", "lapis_ore"]:
			xp = 3
		_register(ore_name, {"all": ore_name}, {
			"hardness": 3.0, "tool": "pickaxe", "tier": tiers[ore_name],
			"drops": [{"item": str(drop[0]), "count": int(drop[1])}], "xp": xp,
			"xp_amount": xp,
		})
	# Deepslate-style lit ore used while redstone components glow.
	_register("lit_redstone_ore", {"all": "redstone_ore"}, {
		"title": "Redstone Ore", "hardness": 3.0, "tool": "pickaxe", "tier": TIER_IRON,
		"light": 9, "drops": [{"item": "redstone", "count": 4}],
	})


static func _register_wood() -> void:
	for wood in ["oak", "birch", "spruce", "jungle"]:
		_register("%s_log" % wood, {"top": "%s_log_top" % wood, "bottom": "%s_log_top" % wood,
			"side": "%s_log_side" % wood}, {
			"hardness": 2.0, "tool": "axe", "sound": SOUND_WOOD, "burning": true,
			"fuel": 15.0,
		})
		_register("%s_planks" % wood, {"all": "%s_planks" % wood}, {
			"hardness": 2.0, "tool": "axe", "sound": SOUND_WOOD, "burning": true, "fuel": 15.0,
		})
		_register("%s_leaves" % wood, {"all": "%s_leaves" % wood}, {
			"hardness": 0.2, "sound": SOUND_GRASS, "opaque": false, "cutout": true, "burning": true,
			"drops": [{"item": "%s_sapling" % wood, "count": 1, "chance": 0.08},
				{"item": "stick", "count": 1, "chance": 0.12}],
		})
		_register("%s_sapling" % wood, {"all": "%s_sapling" % wood}, {
			"hardness": 0.0, "sound": SOUND_GRASS, "shape": SHAPE_CROSS, "opaque": false,
			"solid": false, "cutout": true, "burning": true, "plantable": true,
		})
	_register("bookshelf", {"top": "oak_planks", "bottom": "oak_planks", "side": "bookshelf"},
		{"hardness": 1.5, "tool": "axe", "sound": SOUND_WOOD, "burning": true, "fuel": 15.0,
		 "drops": [{"item": "book", "count": 3}]})


static func _register_plants() -> void:
	var cross := {"shape": SHAPE_CROSS, "opaque": false, "solid": false, "cutout": true,
		"sound": SOUND_PLANT, "hardness": 0.0, "replaceable": true}
	_register("tall_grass", {"all": "tall_grass"}, _merge(cross, {
		"drops": [{"item": "wheat_seeds", "count": 1, "chance": 0.25}], "burning": true,
		"plantable": true}))
	_register("fern", {"all": "fern"}, _merge(cross, {
		"drops": [{"item": "wheat_seeds", "count": 1, "chance": 0.25}], "burning": true,
		"plantable": true}))
	_register("dead_bush", {"all": "dead_bush"}, _merge(cross, {
		"drops": [{"item": "stick", "count": 1, "chance": 0.6}], "burning": true,
		"plantable": true}))
	_register("web", {"all": "web"}, _merge(cross, {
		"drops": [{"item": "string", "count": 1}], "hardness": 4.0, "tool": "sword"}))
	for flower in ["flower_dandelion", "flower_poppy", "flower_tulip_red",
			"flower_tulip_orange", "flower_tulip_white", "flower_blue_orchid", "flower_allium"]:
		_register(flower, {"all": flower}, _merge(cross, {"plantable": true}))
	_register("mushroom_red", {"all": "mushroom_red"}, _merge(cross, {"plantable": true}))
	_register("mushroom_brown", {"all": "mushroom_brown"}, _merge(cross, {"plantable": true}))
	_register("sugar_cane", {"all": "sugar_cane"}, _merge(cross, {
		"drops": [{"item": "sugar_cane", "count": 1}], "plantable": true}))
	_register("cactus", {"top": "cactus_top", "bottom": "cactus_bottom", "side": "cactus_side"},
		{"hardness": 0.4, "sound": SOUND_PLANT, "plantable": true})
	_register("wheat", {"all": "wheat_0"}, _merge(cross, {"item_icon": "wheat",
		"title": "Wheat Crop", "plantable": true, "drops": [],
		"harvest": "wheat", "seed": "wheat_seeds"}))
	_register("carrots", {"all": "carrots"}, _merge(cross, {
		"plantable": true, "drops": [], "harvest": "carrot", "seed": "carrot"}))
	_register("potatoes", {"all": "potatoes"}, _merge(cross, {
		"plantable": true, "drops": [], "harvest": "potato", "seed": "potato"}))
	_register("pumpkin", {"top": "pumpkin_top", "bottom": "pumpkin_top", "side": "pumpkin_side"},
		{"hardness": 1.0, "tool": "axe", "sound": SOUND_WOOD})
	_register("jack_o_lantern", {"top": "pumpkin_top", "bottom": "pumpkin_top",
		"side": "pumpkin_side", "front": "jack_front"},
		{"title": "Jack o'Lantern", "hardness": 1.0, "tool": "axe", "sound": SOUND_WOOD,
		 "light": 15, "facing": true})
	_register("melon", {"top": "melon_top", "bottom": "melon_top", "side": "melon_side"},
		{"hardness": 1.0, "tool": "axe", "sound": SOUND_WOOD,
		 "drops": [{"item": "melon_slice", "count": 5}]})
	_register("farmland", {"top": "farmland", "bottom": "dirt", "side": "dirt"},
		{"hardness": 0.6, "tool": "shovel", "sound": SOUND_GRASS, "shape": SHAPE_FARMLAND,
		 "drops": [{"item": "dirt", "count": 1}], "opaque": true})


static func _register_building() -> void:
	_register("stone_bricks", {"all": "stone_bricks"}, {"hardness": 1.5, "tool": "pickaxe",
		"tier": TIER_WOOD})
	_register("mossy_stone_bricks", {"all": "mossy_stone_bricks"}, {"hardness": 1.5,
		"tool": "pickaxe", "tier": TIER_WOOD})
	_register("bricks", {"all": "bricks"}, {"hardness": 2.0, "tool": "pickaxe", "tier": TIER_WOOD})
	_register("glass", {"all": "glass"}, {"hardness": 0.3, "sound": SOUND_GLASS, "opaque": false,
		"cutout": true, "drops": []})
	_register("glowstone", {"all": "glowstone"}, {"hardness": 0.3, "sound": SOUND_GLASS, "light": 15,
		"drops": [{"item": "glowstone_dust", "count": 3}]})
	_register("quartz_block", {"all": "snow"}, {"title": "Quartz Block", "hardness": 0.8,
		"tool": "pickaxe", "tier": TIER_WOOD})
	_register("slab_stone", {"all": "stone"}, {"title": "Stone Slab", "hardness": 2.0,
		"tool": "pickaxe", "tier": TIER_WOOD, "shape": SHAPE_SLAB, "opaque": false,
		"drops": [{"item": "slab_stone", "count": 1}]})
	_register("slab_oak", {"all": "oak_planks"}, {"title": "Oak Slab", "hardness": 2.0,
		"tool": "axe", "sound": SOUND_WOOD, "shape": SHAPE_SLAB, "opaque": false, "burning": true,
		"drops": [{"item": "slab_oak", "count": 1}]})
	_register("slab_cobblestone", {"all": "cobblestone"}, {"title": "Cobblestone Slab",
		"hardness": 2.0, "tool": "pickaxe", "tier": TIER_WOOD, "shape": SHAPE_SLAB,
		"opaque": false, "drops": [{"item": "slab_cobblestone", "count": 1}]})
	_register("slab_sandstone", {"top": "sandstone_top", "bottom": "sandstone_top",
		"side": "sandstone_side"}, {"title": "Sandstone Slab", "hardness": 0.8,
		"tool": "pickaxe", "tier": TIER_WOOD, "shape": SHAPE_SLAB, "opaque": false,
		"drops": [{"item": "slab_sandstone", "count": 1}]})
	_register("slab_bricks", {"all": "bricks"}, {"title": "Brick Slab", "hardness": 2.0,
		"tool": "pickaxe", "tier": TIER_WOOD, "shape": SHAPE_SLAB, "opaque": false,
		"drops": [{"item": "slab_bricks", "count": 1}]})


static func _register_devices() -> void:
	_register("crafting_table", {"top": "crafting_top", "bottom": "oak_planks",
		"side": "crafting_side"}, {"hardness": 2.5, "tool": "axe", "sound": SOUND_WOOD,
		"burning": true, "fuel": 15.0, "crafting": "3x3"})
	_register("furnace", {"top": "furnace_top", "bottom": "furnace_top", "side": "furnace_side",
		"front": "furnace_front"}, {"hardness": 3.5, "tool": "pickaxe", "tier": TIER_WOOD,
		"facing": true, "container": "furnace"})
	_register("furnace_lit", {"top": "furnace_top", "bottom": "furnace_top",
		"side": "furnace_side", "front": "furnace_front_lit"},
		{"title": "Furnace", "hardness": 3.5, "tool": "pickaxe", "tier": TIER_WOOD, "light": 13,
		 "facing": true, "container": "furnace", "drops": [{"item": "furnace", "count": 1}]})
	_register("chest", {"top": "chest_top", "bottom": "chest_top", "side": "chest_side",
		"front": "chest_front"}, {"hardness": 2.5, "tool": "axe", "sound": SOUND_WOOD,
		"burning": true, "facing": true, "container": "chest", "opaque": false, "cutout": true})
	_register("torch", {"all": "torch"}, {"hardness": 0.0, "light": 14, "shape": SHAPE_TORCH,
		"opaque": false, "solid": false, "cutout": true, "sound": SOUND_WOOD,
		"drops": [{"item": "torch", "count": 1}]})
	_register("redstone_torch", {"all": "redstone_torch"}, {"hardness": 0.0, "light": 7,
		"shape": SHAPE_TORCH, "opaque": false, "solid": false, "cutout": true, "sound": SOUND_WOOD})
	_register("redstone_wire", {"all": "redstone_dust"}, {"title": "Redstone Dust",
		"hardness": 0.0, "shape": SHAPE_LAYER, "opaque": false, "solid": false, "cutout": true,
		"drops": [{"item": "redstone", "count": 1}]})
	_register("redstone_block", {"all": "redstone_block"}, {"hardness": 3.0, "tool": "pickaxe",
		"tier": TIER_WOOD})
	_register("lever", {"all": "lever"}, {"hardness": 0.5, "shape": SHAPE_LAYER, "opaque": false,
		"solid": false, "cutout": true, "sound": SOUND_WOOD})
	_register("pressure_plate_stone", {"all": "pressure_plate"},
		{"title": "Stone Pressure Plate", "hardness": 0.5, "tool": "pickaxe", "shape": SHAPE_LAYER,
		 "opaque": false, "solid": false, "cutout": true})
	_register("note_block", {"all": "note_block"}, {"hardness": 0.8, "tool": "axe",
		"sound": SOUND_WOOD, "burning": true})
	_register("jukebox", {"all": "jukebox"}, {"hardness": 1.5, "tool": "axe", "sound": SOUND_WOOD})
	_register("tnt", {"top": "tnt_top", "bottom": "tnt_bottom", "side": "tnt_side"},
		{"title": "TNT", "hardness": 0.0, "sound": SOUND_GRASS})
	_register("piston", {"top": "piston_top", "bottom": "piston_side", "side": "piston_side"},
		{"hardness": 1.5, "facing": true})
	_register("sticky_piston", {"top": "sticky_piston_top", "bottom": "piston_side",
		"side": "piston_side"}, {"hardness": 1.5, "facing": true})
	# Extended piston head: placed by the piston logic, never held by the player.
	_register("piston_arm", {"all": "piston_arm"}, {"hardness": 1.5, "facing": true,
		"drops": []})
	_register("dispenser", {"top": "furnace_top", "bottom": "furnace_top",
		"side": "furnace_side", "front": "dispenser_front"},
		{"hardness": 3.5, "tool": "pickaxe", "tier": TIER_WOOD, "facing": true,
		 "container": "dispenser"})
	_register("ladder", {"all": "ladder"}, {"hardness": 0.4, "shape": SHAPE_LADDER, "opaque": false,
		"solid": false, "cutout": true, "sound": SOUND_WOOD, "climbable": true, "facing": true,
		"burning": true, "fuel": 15.0})
	_register("oak_door", {"all": "oak_planks"}, {"title": "Oak Door", "hardness": 3.0,
		"tool": "axe", "sound": SOUND_WOOD, "burning": true, "facing": true})
	_register("glass_pane", {"all": "glass"}, {"title": "Glass Pane", "hardness": 0.3,
		"sound": SOUND_GLASS, "shape": SHAPE_LAYER, "opaque": false, "solid": false,
		"cutout": true, "drops": []})


## Furniture added after the originals on purpose: saved chunks store raw block
## ids, so every new block has to be appended to the end of the registry.
static func _register_furniture() -> void:
	_register("bed", {"top": "bed_top", "bottom": "oak_planks", "side": "bed_side"},
		{"hardness": 0.2, "sound": SOUND_WOOD, "shape": SHAPE_SLAB, "opaque": false,
		 "burning": true, "drops": [{"item": "bed", "count": 1}]})


static func _register_wool() -> void:
	var colors := [
		"white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
		"light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black",
	]
	for color in colors:
		_register("%s_wool" % color, {"all": "wool_%s" % color}, {
			"title": "%s Wool" % _prettify(color), "hardness": 0.8, "sound": SOUND_WOOL,
			"burning": true, "fuel": 1.0,
		})


static func _merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for key in extra:
		out[key] = extra[key]
	return out


# ---------------------------------------------------------------------------
# Atlas resolution
# ---------------------------------------------------------------------------

static func _load_atlas_manifest() -> void:
	var file := FileAccess.open("res://assets/generated/atlas.json", FileAccess.READ)
	if file == null:
		push_warning("atlas.json missing - run tools/gen_assets.py")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("atlas.json is malformed")
		return
	tile_size = int(parsed.get("tile_pixels", 16))
	atlas_cell = int(parsed.get("cell", 24))
	atlas_cols = int(parsed.get("cols", 16))
	atlas_size = int(parsed.get("size", 384))
	_atlas_lookup = {}
	for key in parsed.get("tiles", {}):
		var cell: Array = parsed["tiles"][key]
		_atlas_lookup[key] = Vector2i(int(cell[0]), int(cell[1]))


static var _atlas_lookup: Dictionary = {}


static func tile_cell(tile_name: String) -> Vector2i:
	return _atlas_lookup.get(tile_name, Vector2i(-1, -1))


## Expands each block's tile spec into six resolved atlas cells (plus an
## optional facing-dependent front tile).
static func _resolve_tiles() -> void:
	for block_id in defs.size():
		var definition: BlockDef = defs[block_id]
		var spec := definition.tile_names
		if spec.is_empty():
			tiles[block_id] = [] as Array[Vector2i]
			continue
		var side_name: String = str(spec.get("side", spec.get("all", "")))
		var top_name: String = str(spec.get("top", spec.get("all", side_name)))
		var bottom_name: String = str(spec.get("bottom", spec.get("all", side_name)))
		var faces: Array[Vector2i] = []
		faces.resize(6)
		faces[0] = tile_cell(side_name)
		faces[1] = tile_cell(side_name)
		faces[2] = tile_cell(top_name)
		faces[3] = tile_cell(bottom_name)
		faces[4] = tile_cell(side_name)
		faces[5] = tile_cell(side_name)
		tiles[block_id] = faces
		if spec.has("front"):
			front_tiles[block_id] = tile_cell(str(spec["front"]))


static func _cache_hot_ids() -> void:
	AIR = id("air")
	WATER = id("water")
	LAVA = id("lava")
	GRASS = id("grass_block")
	DIRT = id("dirt")
	STONE = id("stone")
	SAND = id("sand")
	FURNACE = id("furnace")
	FURNACE_LIT = id("furnace_lit")
	CHEST = id("chest")
	CRAFTING_TABLE = id("crafting_table")
	TORCH = id("torch")
	GLASS = id("glass")
	BEDROCK = id("bedrock")
	FARMLAND = id("farmland")
	WHEAT = id("wheat")
	ICE = id("ice")
	SNOWY_GRASS_BLOCK = id("snowy_grass_block")
	SANDSTONE = id("sandstone")
	COARSE_DIRT = id("coarse_dirt")
	CLAY = id("clay")
	GRAVEL = id("gravel")
	COBBLESTONE = id("cobblestone")
	OAK_LOG = id("oak_log")
	OAK_LEAVES = id("oak_leaves")
	CACTUS = id("cactus")
	SUGAR_CANE = id("sugar_cane")
	GLOWSTONE = id("glowstone")
	TNT = id("tnt")
	OBSIDIAN = id("obsidian")
	SNOW_LAYER = id("snow_layer")
	GRANITE = id("granite")
	DIORITE = id("diorite")
	ANDESITE = id("andesite")


# ---------------------------------------------------------------------------
# Queries used by gameplay code
# ---------------------------------------------------------------------------


## Atlas cell for a face, honouring facing-dependent blocks (furnace fronts).
static func face_tile(block_id: int, face: int, meta: int = 0) -> Vector2i:
	var front: Vector2i = front_tiles[block_id]
	if front.x >= 0 and (meta & 0x7) == face:
		return front
	var faces: Array = tiles[block_id]
	if face < faces.size():
		return faces[face]
	return Vector2i(-1, -1)


## Drops when this block is broken with the given tool item id and tier.
static func drops_for(block_id: int, tool_item: String, tool_tier: int) -> Array:
	var definition: BlockDef = def(block_id)
	if definition.harvest != "":
		# Crop: the plant itself never drops, the harvest does.
		return [{"item": definition.harvest, "count": 1}]
	if definition.drops.is_empty():
		return []
	if definition.tier > TIER_NONE:
		# Ores and stone need the right tool at the right tier to yield anything.
		if tool_item != definition.tool or tool_tier < definition.tier:
			return []
	var out: Array = []
	for drop in definition.drops:
		var chance: float = float(drop.get("chance", 1.0))
		if chance < 1.0 and randf() > chance:
			continue
		out.append({"item": str(drop["item"]), "count": int(drop.get("count", 1))})
	return out


## Seconds needed to break this block with the given tool (infinity if unbreakable).
static func break_time(block_id: int, tool_item: String, tool_tier: int, haste: float = 1.0) -> float:
	var definition: BlockDef = def(block_id)
	if definition.hardness < 0.0:
		return INF
	var base: float = maxf(0.05, definition.hardness)
	var speed: float = 1.0
	if tool_item == definition.tool and tool_item != "":
		speed = 1.0 + float(tool_tier) * 1.7
	elif tool_item != "":
		speed = 1.15
	var seconds: float = base / speed * 1.5 / maxf(0.1, haste)
	return maxf(0.05, seconds)


static func is_plantable(block_id: int) -> bool:
	return def(block_id).plantable


static func has_facing(block_id: int) -> bool:
	return def(block_id).container != "" or def(block_id).climbable or def(block_id).name in _FACING_BLOCKS


static func crafting_kind(block_id: int) -> String:
	return def(block_id).crafting


static func container_kind(block_id: int) -> String:
	return def(block_id).container


## Blocks that remember which way they were placed.
const _FACING_BLOCKS: PackedStringArray = [
	"jack_o_lantern", "piston", "sticky_piston", "piston_arm", "furnace", "furnace_lit", "chest",
	"dispenser", "ladder", "oak_door",
]


static func fuel_value(block_id: int) -> float:
	return def(block_id).fuel


static func tier_name(tier: int) -> String:
	match tier:
		TIER_WOOD:
			return "wooden"
		TIER_STONE:
			return "stone"
		TIER_IRON:
			return "iron"
		TIER_DIAMOND:
			return "diamond"
	return "hand"
