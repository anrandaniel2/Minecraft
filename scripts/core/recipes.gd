class_name Recipes
extends RefCounted

## Crafting and smelting data + matching.
##
## Shaped recipes are authored as a small grid of characters with a key map, so
## the same recipe works on a 2x2 (inventory) or 3x3 (table) grid as long as it
## fits. Matching is position-independent inside the grid (the pattern is
## slid around until it lines up), and mirrored horizontally as a fallback -
## exactly how players expect Minecraft recipes to behave.

class Recipe:
	extends RefCounted
	var kind: String = "shaped"        # shaped | shapeless
	var rows: PackedStringArray = []   # shaped patterns
	var key: Dictionary = {}           # char -> item name
	var ingredients: Array = []        # shapeless: item names
	var results: Array = []            # [{item, count}]
	var result_item: String = ""       # smelting
	var result_count: int = 1
	var smelt_time: float = 10.0
	var xp: float = 0.5
	var width: int = 0
	var height: int = 0


static var shaped: Array = []
static var shapeless: Array = []
static var smelting: Dictionary = {}   # item name -> Recipe
static var fuels: Dictionary = {}      # item name -> seconds
static var _built: bool = false


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------


static var _tag_cache: Dictionary = {}


## Item tags: a recipe key may reference a tag ("#planks") to accept any item
## in the group, the way Minecraft recipes accept any wood type.
## Material names ("iron") expand to the item plus its ingot/gem spelling.
## Public wrapper around `_ids_for`: the ingredient options for a spec such as
## "#planks", "oak_planks" or "@wool". Used by the crafting UI.
static func options_for(spec: String) -> Array:
	return _ids_for(spec)


static func tags() -> Dictionary:
	return {
		"planks": ["oak_planks", "birch_planks", "spruce_planks", "jungle_planks"],
		"logs": ["oak_log", "birch_log", "spruce_log", "jungle_log"],
		"wool": ["white_wool", "orange_wool", "magenta_wool", "light_blue_wool", "yellow_wool",
			"lime_wool", "pink_wool", "gray_wool", "light_gray_wool", "cyan_wool", "purple_wool",
			"blue_wool", "brown_wool", "green_wool", "red_wool", "black_wool"],
		"stone_like": ["stone", "cobblestone", "granite", "diorite", "andesite"],
	}


static func _ids_for(spec: String) -> Array:
	var cached = _tag_cache.get(spec)
	if cached != null:
		return cached
	var out: Array = []
	if spec.begins_with("#"):
		for item_name in tags().get(spec.substr(1), []):
			var item_id: int = Items.id(str(item_name))
			if item_id >= 0:
				out.append(item_id)
	else:
		for candidate in _material_options(spec):
			var item_id: int = Items.id(candidate)
			if item_id >= 0 and not out.has(item_id):
				out.append(item_id)
	_tag_cache[spec] = out
	return out


## Tool/armour materials are authored as "iron"; the actual item is
## "iron_ingot" / "diamond" / "gold_ingot" depending on the material.
static func _material_options(spec: String) -> Array:
	match spec:
		"iron":
			return ["iron_ingot"]
		"gold":
			return ["gold_ingot"]
		"copper":
			return ["copper_ingot"]
		"wood":
			return ["oak_planks", "birch_planks", "spruce_planks", "jungle_planks"]
	return [spec]


static func build() -> void:
	if _built:
		return
	_built = true
	_tag_cache.clear()
	shaped.clear()
	shapeless.clear()
	smelting.clear()

	# --- wood processing ---
	for wood in ["oak", "birch", "spruce", "jungle"]:
		_add_shapeless(["%s_log" % wood], [{"item": "%s_planks" % wood, "count": 4}])
	_shaped(["#", "#"], {"#": "#planks"}, [{"item": "stick", "count": 4}])
	_shaped(["##", "##"], {"#": "#planks"}, [{"item": "crafting_table", "count": 1}])
	_shaped(["###", "# #", "###"], {"#": "#planks"}, [{"item": "chest", "count": 1}])
	_shaped(["WW", "WW", "WW"], {"W": "#planks"}, [{"item": "oak_door", "count": 1}])
	_shaped(["###", "PPP"], {"#": "#wool", "P": "#planks"}, [{"item": "bed", "count": 1}])
	_shaped(["X X", "XSX", "X X"], {"X": "iron_ingot", "S": "stick"}, [{"item": "rail", "count": 16}])
	_shaped(["##"], {"#": "#planks"}, [{"item": "slab_oak", "count": 2}])
	_shaped(["# #", "###", "# #"], {"#": "stick"}, [{"item": "ladder", "count": 3}])
	_shaped(["###", "#X#", "###"], {"#": "#planks", "X": "diamond"}, [{"item": "jukebox", "count": 1}])
	_shaped(["###", "#X#", "###"], {"#": "#planks", "X": "redstone"}, [{"item": "note_block", "count": 1}])
	_shaped(["###", "###", "###"], {"#": "#planks"}, [{"item": "bookshelf", "count": 1}])

	# --- basic blocks ---
	_shaped(["###", "# #", "###"], {"#": "cobblestone"}, [{"item": "furnace", "count": 1}])
	_shaped(["##", "##"], {"#": "stone"}, [{"item": "stone_bricks", "count": 4}])
	_shaped(["##", "##"], {"#": "brick"}, [{"item": "bricks", "count": 1}])
	_shaped(["##", "##"], {"#": "sand"}, [{"item": "sandstone", "count": 1}])
	_shaped(["##", "##"], {"#": "red_sand"}, [{"item": "sandstone", "count": 1}])
	_shaped(["##"], {"#": "stone"}, [{"item": "slab_stone", "count": 2}])
	_shaped(["##"], {"#": "cobblestone"}, [{"item": "slab_cobblestone", "count": 2}])
	_shaped(["##"], {"#": "sandstone"}, [{"item": "slab_sandstone", "count": 2}])
	_shaped(["##"], {"#": "bricks"}, [{"item": "slab_bricks", "count": 2}])
	_shaped(["###", "#X#", "###"], {"#": "#planks", "X": "book"}, [{"item": "bookshelf", "count": 1}])
	_shaped(["###", "XXX", "###"], {"#": "gunpowder", "X": "sand"}, [{"item": "tnt", "count": 1}])
	_shaped([" # ", "#X#", " # "], {"#": "cobblestone", "X": "iron_ingot"}, [{"item": "piston", "count": 1}])
	_shaped([" # ", "#X#", " # "], {"#": "cobblestone", "X": "slimeball"}, [{"item": "sticky_piston", "count": 1}])
	_shaped(["###", "#X#", "###"], {"#": "cobblestone", "X": "bow"}, [{"item": "dispenser", "count": 1}])
	_shaped(["##", "##"], {"#": "redstone"}, [{"item": "redstone_block", "count": 1}])
	_shaped(["#", "X"], {"#": "coal", "X": "stick"}, [{"item": "torch", "count": 4}])
	_shaped(["#", "X"], {"#": "charcoal", "X": "stick"}, [{"item": "torch", "count": 4}])
	_shaped(["#", "X"], {"#": "redstone", "X": "stick"}, [{"item": "redstone_torch", "count": 1}])
	_shaped(["##"], {"#": "stone"}, [{"item": "pressure_plate_stone", "count": 1}])
	_shaped(["#", "X"], {"#": "stick", "X": "cobblestone"}, [{"item": "lever", "count": 1}])
	_shaped(["XXX", " # "], {"#": "stick", "X": "string"}, [{"item": "bow", "count": 1}])
	_shaped(["X", "#", "#"], {"#": "stick", "X": "flint"}, [{"item": "arrow", "count": 4}])
	_shaped(["X ", " #"], {"#": "iron_ingot", "X": "flint"}, [{"item": "flint_and_steel", "count": 1}])
	_shaped([" X", "X "], {"X": "iron_ingot"}, [{"item": "shears", "count": 1}])
	_shaped(["# #", " # "], {"#": "iron_ingot"}, [{"item": "bucket", "count": 1}])
	_shaped(["#X#", "#X#", " # "], {"#": "glass", "X": "glowstone_dust"}, [{"item": "glowstone", "count": 1}])
	_shaped(["###"], {"#": "sugar_cane"}, [{"item": "paper", "count": 3}])
	_shaped(["#X"], {"#": "paper", "X": "leather"}, [{"item": "book", "count": 1}])
	_shaped(["#"], {"#": "sugar_cane"}, [{"item": "sugar", "count": 1}])
	_shaped(["##", "##"], {"#": "melon_slice"}, [{"item": "melon", "count": 1}])
	_shaped(["###", "#X#", "###"], {"#": "wheat", "X": "sugar"}, [{"item": "cookie", "count": 8}])
	_shaped(["###", "XXX", "###"], {"#": "wheat", "X": "pumpkin"}, [{"item": "pumpkin_pie", "count": 1}])
	_shaped(["###"], {"#": "wheat"}, [{"item": "bread", "count": 1}])
	_shaped(["###", "#X#", "###"], {"#": "gold_ingot", "X": "apple"}, [{"item": "golden_apple", "count": 1}])
	_shaped(["#", "#"], {"#": "bone"}, [{"item": "bone_meal", "count": 3}])
	_shaped(["##", "##"], {"#": "clay_ball"}, [{"item": "clay", "count": 1}])
	_shaped(["#", "#"], {"#": "clay_ball"}, [{"item": "brick", "count": 1}])
	_shaped(["##", "##"], {"#": "string"}, [{"item": "white_wool", "count": 1}])
	_shaped(["##", "##"], {"#": "snowball"}, [{"item": "snow_block", "count": 1}])
	_shaped(["##", "##"], {"#": "ice"}, [{"item": "packed_ice", "count": 1}])

	# --- tools ---
	for material in Items.TOOL_MATERIALS:
		var mat_name: String = material
		_shaped(["###", " X ", " X "], {"#": mat_name, "X": "stick"}, [{"item": "%s_pickaxe" % mat_name, "count": 1}])
		_shaped(["## ", "#X ", " X "], {"#": mat_name, "X": "stick"}, [{"item": "%s_axe" % mat_name, "count": 1}])
		_shaped(["#", "X", "X"], {"#": mat_name, "X": "stick"}, [{"item": "%s_shovel" % mat_name, "count": 1}])
		_shaped(["#", "#", "X"], {"#": mat_name, "X": "stick"}, [{"item": "%s_sword" % mat_name, "count": 1}])
		_shaped(["##", " X", " X"], {"#": mat_name, "X": "stick"}, [{"item": "%s_hoe" % mat_name, "count": 1}])
	# --- armour ---
	for material in Items.ARMOR_MATERIALS:
		var mat_name: String = material
		_shaped(["###", "# #"], {"#": mat_name}, [{"item": "%s_helmet" % mat_name, "count": 1}])
		_shaped(["# #", "###", "###"], {"#": mat_name}, [{"item": "%s_chestplate" % mat_name, "count": 1}])
		_shaped(["###", "# #", "# #"], {"#": mat_name}, [{"item": "%s_leggings" % mat_name, "count": 1}])
		_shaped(["# #", "# #"], {"#": mat_name}, [{"item": "%s_boots" % mat_name, "count": 1}])

	# --- smelting ---
	_smelt("cobblestone", "stone", 10.0, 0.1)
	_smelt("sand", "glass", 10.0, 0.1)
	_smelt("red_sand", "glass", 10.0, 0.1)
	for log_name in ["oak_log", "birch_log", "spruce_log", "jungle_log"]:
		_smelt(log_name, "charcoal", 10.0, 0.15)
	_smelt("raw_iron", "iron_ingot", 10.0, 0.7)
	_smelt("raw_gold", "gold_ingot", 10.0, 1.0)
	_smelt("raw_copper", "copper_ingot", 10.0, 0.7)
	_smelt("iron_ore", "iron_ingot", 10.0, 0.7)
	_smelt("gold_ore", "gold_ingot", 10.0, 1.0)
	_smelt("copper_ore", "copper_ingot", 10.0, 0.7)
	_smelt("clay", "bricks", 10.0, 0.3)
	_smelt("clay_ball", "brick", 10.0, 0.3)
	_smelt("porkchop", "cooked_porkchop", 10.0, 0.35)
	_smelt("beef", "steak", 10.0, 0.35)
	_smelt("chicken", "cooked_chicken", 10.0, 0.35)
	_smelt("mutton", "cooked_mutton", 10.0, 0.35)
	_smelt("potato", "baked_potato", 10.0, 0.35)

	# --- fuel values (seconds of smelting per item) ---
	fuels = {
		"coal": 80.0, "charcoal": 80.0, "stick": 5.0, "lava_bucket": 1000.0,
		"crafting_table": 15.0, "bookshelf": 15.0, "oak_door": 15.0, "ladder": 15.0,
		"chest": 15.0, "jukebox": 15.0, "note_block": 15.0,
	}
	for wood in ["oak", "birch", "spruce", "jungle"]:
		fuels["%s_planks" % wood] = 15.0
		fuels["%s_log" % wood] = 15.0
		fuels["%s_sapling" % wood] = 5.0
		fuels["%s_leaves" % wood] = 1.0
	for wool_name in tags()["wool"]:
		fuels[wool_name] = 5.0


static func _add_shapeless(ingredients: Array, results: Array) -> void:
	if results.is_empty():
		return
	var recipe := Recipe.new()
	recipe.kind = "shapeless"
	recipe.ingredients = ingredients
	recipe.results = results
	recipe.result_item = str(results[0]["item"])
	recipe.result_count = int(results[0].get("count", 1))
	shapeless.append(recipe)


static func _shaped(rows: Array, key_map: Dictionary, results: Array) -> void:
	if results.is_empty():
		return
	var recipe := Recipe.new()
	recipe.kind = "shaped"
	recipe.rows = PackedStringArray(rows)
	recipe.key = key_map
	recipe.results = results
	recipe.result_item = str(results[0]["item"])
	recipe.result_count = int(results[0].get("count", 1))
	recipe.height = rows.size()
	var width: int = 0
	for row in rows:
		width = maxi(width, str(row).length())
	recipe.width = width
	shaped.append(recipe)


static func _smelt(input_item: String, output_item: String, time: float, xp: float) -> void:
	if Items.id(input_item) < 0:
		return
	if Items.id(output_item) < 0:
		# Fall back to the input item when the output does not exist (smooth stone).
		output_item = input_item
	var recipe := Recipe.new()
	recipe.kind = "smelting"
	recipe.result_item = output_item
	recipe.result_count = 1
	recipe.smelt_time = time
	recipe.xp = xp
	smelting[input_item] = recipe


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------


## Finds the recipe for a crafting grid. `grid` is a w x h array of item ids
## (-1 for empty), row-major.
static func match(grid: Array, width: int, height: int) -> Recipe:
	var used: Array = []
	for item_id in grid:
		if item_id >= 0:
			used.append(item_id)
	if used.is_empty():
		return null
	# Shapeless first: cheaper to check and unambiguous for small grids.
	for recipe in shapeless:
		if _matches_shapeless(recipe, grid):
			return recipe
	for recipe in shaped:
		var recipe_width: int = recipe.width
		var recipe_height: int = recipe.height
		if recipe_width > width or recipe_height > height:
			continue
		for offset_y in range(height - recipe_height + 1):
			for offset_x in range(width - recipe_width + 1):
				if _matches_shaped(recipe, grid, width, height, offset_x, offset_y, false):
					return recipe
				if _matches_shaped(recipe, grid, width, height, offset_x, offset_y, true):
					return recipe
	return null


static func _matches_shapeless(recipe: Recipe, grid: Array) -> bool:
	var needed: Array = []
	var alternatives: Array = []
	for spec in recipe.ingredients:
		var options: Array = _ids_for(str(spec))
		if options.is_empty():
			return false
		needed.append(spec)
		alternatives.append(options)
	var pool: Array = []
	for item_id in grid:
		if item_id >= 0:
			pool.append(item_id)
	if pool.size() != needed.size():
		return false
	for options in alternatives:
		var found_index: int = -1
		for index in pool.size():
			if options.has(pool[index]):
				found_index = index
				break
		if found_index < 0:
			return false
		pool.remove_at(found_index)
	return pool.is_empty()


static func _matches_shaped(
	recipe: Recipe, grid: Array, width: int, height: int,
	offset_x: int, offset_y: int, mirrored: bool
) -> bool:
	# Every cell of the grid must be explained: inside the pattern → the mapped
	# item, outside the pattern → empty.
	for y in range(height):
		for x in range(width):
			var grid_item: int = grid[y * width + x]
			var pattern_x: int = x - offset_x
			if mirrored:
				pattern_x = recipe.width - 1 - pattern_x
			var pattern_y: int = y - offset_y
			var expected: String = ""
			if pattern_x >= 0 and pattern_x < recipe.width and pattern_y >= 0 and pattern_y < recipe.height:
				var row: String = recipe.rows[pattern_y]
				if pattern_x < row.length():
					var letter: String = row[pattern_x]
					if letter != " ":
						expected = str(recipe.key.get(letter, ""))
			if expected == "":
				if grid_item >= 0:
					return false
			else:
				if not _ids_for(expected).has(grid_item):
					return false
	return true


## Smelting recipe for an item id ({} when the item cannot be smelted).
static func smelting_for(item_id: int) -> Dictionary:
	var item_name: String = Items.name_of(item_id)
	if item_name == "":
		return {}
	var recipe: Recipe = smelting.get(item_name)
	if recipe == null:
		return {}
	var output_id: int = Items.id(recipe.result_item)
	if output_id < 0:
		output_id = item_id
	return {
		"item": output_id,
		"count": recipe.result_count,
		"time": recipe.smelt_time,
		"xp": recipe.xp,
	}


static func can_smelt(item_id: int) -> bool:
	return not smelting_for(item_id).is_empty()


static func fuel_seconds(item_id: int) -> float:
	var item_name: String = Items.name_of(item_id)
	if item_name == "":
		return 0.0
	return float(fuels.get(item_name, 0.0))


## Human-readable ingredient list, used by the recipe book UI.
static func describe(recipe: Recipe) -> String:
	var lines: PackedStringArray = []
	if recipe.kind == "shaped":
		for row in recipe.rows:
			lines.append(row)
	else:
		for item_name in recipe.ingredients:
			lines.append("%s x1" % Blocks._prettify(str(item_name)))
	return "\n".join(lines)
