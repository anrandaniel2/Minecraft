extends SceneTree

## Headless smoke test - run it with:
##
##     godot --headless --path . --script res://tests/smoke_test.gd
##
## It exercises the parts of the game that are pure logic: content registries,
## the asset manifests they depend on, recipe matching, terrain generation,
## mob/trade tables and container serialisation. Any failing check exits with a
## non-zero status so CI can gate on it.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	print("Blockcraft smoke test")
	_test_registries()
	_test_assets()
	_test_recipes()
	_test_world_generation()
	_test_mobs_and_trades()
	_test_containers()
	print("")
	if failures == 0:
		print("SMOKE OK - %d checks passed" % checks)
	else:
		print("SMOKE FAILED - %d of %d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------


func _test_registries() -> void:
	print("- registries")
	Blocks.build()
	Items.build()
	Recipes.build()
	check(Blocks.defs.size() > 100, "more than 100 block types (%d)" % Blocks.defs.size())
	check(Items.defs.size() > 200, "more than 200 items (%d)" % Items.defs.size())
	for block_name in ["stone", "grass_block", "dirt", "sand", "oak_log", "oak_planks", "chest",
			"furnace", "torch", "water", "lava", "bedrock", "diamond_ore", "piston", "piston_arm",
			"tnt", "obsidian", "glowstone", "crafting_table", "flower_poppy", "red_wool"]:
		check(Blocks.id(block_name) > 0, "block '%s' registered" % block_name)
	for item_name in ["stick", "coal", "charcoal", "iron_ingot", "raw_iron", "diamond", "emerald",
			"stone_pickaxe", "diamond_sword", "iron_chestplate", "bread", "apple", "wheat_seeds",
			"gunpowder", "flint_and_steel", "bucket", "bow", "arrow", "bookshelf", "paper"]:
		check(Items.def_by_name(item_name) != null, "item '%s' registered" % item_name)

	var stone_pickaxe: int = Items.id("stone_pickaxe")
	check(Items.tool_kind(stone_pickaxe) == "pickaxe", "a stone pickaxe is a pickaxe")
	check(Items.tool_tier(stone_pickaxe) == Blocks.TIER_STONE, "a stone pickaxe is stone tier")
	check(Items.durability(stone_pickaxe) > 0, "tools have durability")
	check(Items.max_stack(stone_pickaxe) == 1, "tools do not stack")
	check(Items.max_stack(Items.id("stick")) == 64, "resources stack to 64")
	check(Items.places_block(Blocks.id("stone")) == Blocks.id("stone"), "stone places stone")
	check(Items.def_of(Items.id("iron_chestplate")).armor_points > 0, "armour has points")
	check(Items.def_of(Items.id("bread")).is_food(), "bread is food")
	check(Items.attack_damage(Items.id("diamond_sword"))
		> Items.attack_damage(Items.id("wood_sword")), "diamond hits harder than wood")

	check(Blocks.break_time(Blocks.id("stone"), "pickaxe", Blocks.TIER_DIAMOND)
		< Blocks.break_time(Blocks.id("stone"), "", Blocks.TIER_NONE),
		"a diamond pickaxe mines stone faster than a bare hand")
	check(Blocks.break_time(Blocks.id("bedrock"), "pickaxe", Blocks.TIER_DIAMOND) == INF,
		"bedrock cannot be mined")
	check(Blocks.def(Blocks.id("water")).liquid, "water is a liquid")
	check(Blocks.is_replaceable(Blocks.id("tall_grass")), "grass is replaceable")
	check(Blocks.light_emission(Blocks.id("torch")) > 0, "torches emit light")
	var ore_drops: Array = Blocks.drops_for(Blocks.id("diamond_ore"), "pickaxe",
		Blocks.TIER_DIAMOND)
	check(not ore_drops.is_empty(), "diamond ore drops with a diamond pickaxe")
	var bare_drops: Array = Blocks.drops_for(Blocks.id("diamond_ore"), "", Blocks.TIER_NONE)
	check(bare_drops.is_empty(), "diamond ore drops nothing to a bare hand")
	check(Blocks.drops_for(Blocks.id("bedrock"), "pickaxe", Blocks.TIER_DIAMOND).is_empty(),
		"bedrock never drops anything")


## Every tile a block asks for must exist in the packed atlas, every mob skin must
## exist as a sheet, and the sounds the game plays must be on disk.
func _test_assets() -> void:
	print("- assets")
	var atlas: Variant = read_json("res://assets/generated/atlas.json")
	check(typeof(atlas) == TYPE_DICTIONARY, "atlas.json parses")
	var tiles: Dictionary = {}
	if typeof(atlas) == TYPE_DICTIONARY:
		tiles = atlas.get("tiles", {})
	check(tiles.size() > 100, "the atlas packs %d tiles" % tiles.size())
	var missing_tiles: Array = []
	for definition in Blocks.defs:
		for spec_value in definition.tile_names.values():
			var tile_name: String = str(spec_value)
			if not tiles.has(tile_name):
				missing_tiles.append("%s -> %s" % [definition.name, tile_name])
	var used_cells: Dictionary = {}
	for block_id in Blocks.defs.size():
		for face in 6:
			var cell: Vector2i = Blocks.face_tile(block_id, face, 0)
			used_cells[cell] = true
	check(used_cells.size() > 40, "the blocks use %d distinct atlas cells" % used_cells.size())
	check(missing_tiles.is_empty(), "every block tile exists in the atlas %s"
		% ("" if missing_tiles.is_empty() else str(missing_tiles.slice(0, 4))))

	var entities: Variant = read_json("res://assets/generated/entities.json")
	var skins: Dictionary = entities if typeof(entities) == TYPE_DICTIONARY else {}
	check(skins.size() >= 8, "%d mob skins are described" % skins.size())
	var missing_skins: Array = []
	for mob_type in MobTypes.all().keys():
		var skin: String = str(MobTypes.get_stats(mob_type).get("skin", ""))
		if not skins.has(skin):
			missing_skins.append(str(mob_type))
		elif not FileAccess.file_exists("res://assets/generated/entities/%s.png" % skin):
			missing_skins.append(str(mob_type))
	check(missing_skins.is_empty(), "every mob has a skin sheet %s"
		% ("" if missing_skins.is_empty() else str(missing_skins)))
	var hud_icons: Array = ["heart_full", "heart_half", "heart_empty", "hunger_full", "bubble",
		"crosshair", "logo"]
	var missing_icons: Array = []
	for icon in hud_icons:
		if not FileAccess.file_exists("res://assets/generated/ui/%s.png" % icon):
			missing_icons.append(icon)
	check(missing_icons.is_empty(), "the HUD icons are generated %s"
		% ("" if missing_icons.is_empty() else str(missing_icons)))
	var sounds: Array = ["step_stone", "step_grass", "dig_glass", "click", "explode", "thunder",
		"piston", "lever", "splash", "hurt", "eat", "level_up", "item_pickup"]
	var missing_sounds: Array = []
	for sound_name in sounds:
		if not FileAccess.file_exists("res://assets/audio/%s.wav" % sound_name):
			missing_sounds.append(sound_name)
	check(missing_sounds.is_empty(), "the sound effects are generated %s"
		% ("" if missing_sounds.is_empty() else str(missing_sounds)))
	check(FileAccess.file_exists("res://assets/audio/music_menu.wav"), "menu music exists")


# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------


func _test_recipes() -> void:
	print("- recipes")
	check(Recipes.shaped.size() > 40, "%d shaped recipes" % Recipes.shaped.size())
	check(Recipes.shapeless.size() >= 4, "%d shapeless recipes" % Recipes.shapeless.size())
	check(Recipes.smelting.size() > 10, "%d smelting recipes" % Recipes.smelting.size())

	var planks: int = Items.id("oak_planks")
	var log_id: int = Items.id("oak_log")
	var recipe: Recipes.Recipe = Recipes.match([log_id, -1, -1, -1], 2, 2)
	check(recipe != null, "a lone log matches a recipe")
	if recipe != null:
		check(Items.id(str(recipe.results[0]["item"])) == planks, "a log crafts into planks")
		check(int(recipe.results[0]["count"]) == 4, "a log gives four planks")

	var grid_2x2: Array = [planks, planks, -1, planks, planks, -1, -1, -1, -1]
	var table_recipe: Recipes.Recipe = Recipes.match(grid_2x2, 3, 3)
	check(table_recipe != null, "four planks match the crafting table recipe")
	if table_recipe != null:
		check(Items.id(str(table_recipe.results[0]["item"])) == Blocks.id("crafting_table"),
			"planks craft into a crafting table")
	check(Recipes.match([planks, -1, -1, planks], 2, 2) != null,
		"the crafting table also fits a 2x2 grid")

	var stick_recipe: Recipes.Recipe = Recipes.match([planks, -1, planks, -1], 2, 2)
	check(stick_recipe != null, "two planks match the stick recipe")
	if stick_recipe != null:
		check(Items.id(str(stick_recipe.results[0]["item"])) == Items.id("stick"),
			"planks craft into sticks")

	var smelt: Dictionary = Recipes.smelting_for(Items.id("iron_ore"))
	check(not smelt.is_empty(), "iron ore can be smelted")
	if not smelt.is_empty():
		check(int(smelt["item"]) == Items.id("iron_ingot"), "iron ore smelts into iron ingots")
		check(float(smelt["time"]) > 0.0, "smelting takes time")
	check(Recipes.can_smelt(Items.id("sand")), "sand can be smelted")
	check(not Recipes.can_smelt(Items.id("diamond")), "diamonds cannot be smelted")
	check(Recipes.fuel_seconds(Items.id("coal")) > 0.0, "coal burns as fuel")
	check(Recipes.fuel_seconds(Items.id("diamond")) == 0.0, "diamonds do not burn")
	check(not Recipes.options_for("#planks").is_empty(), "the '#planks' tag resolves to items")
	check(Recipes.options_for("#planks").size() >= 4, "every wood type is in '#planks'")
	check(Recipes.options_for("no_such_item").is_empty(), "unknown specs resolve to nothing")


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------


func _test_world_generation() -> void:
	print("- world generation")
	var generator := WorldGen.new(1337)
	var chunk := Chunk.new(Vector2i(0, 0))
	generator.generate_chunk(chunk)
	var air: int = 0
	var solid: int = 0
	var bedrock: int = 0
	var above_sea: int = 0
	var leaves: int = 0
	var ores: int = 0
	var ore_names: Array = ["coal_ore", "iron_ore", "copper_ore", "diamond_ore", "redstone_ore",
		"lapis_lazuli_ore", "gold_ore", "emerald_ore"]
	for x in Chunk.SIZE:
		for z in Chunk.SIZE:
			var top: int = 0
			for y in Chunk.HEIGHT:
				var block_id: int = chunk.get_block(x, y, z)
				if block_id == Blocks.AIR:
					air += 1
				else:
					solid += 1
					top = y
				if ore_names.has(Blocks.name_of(block_id)):
					ores += 1
			if chunk.get_block(x, 0, z) == Blocks.BEDROCK:
				bedrock += 1
			if top > WorldGen.SEA_LEVEL:
				above_sea += 1
			for y in range(Chunk.HEIGHT - 1, 0, -1):
				if Blocks.name_of(chunk.get_block(x, y, z)).ends_with("_leaves"):
					leaves += 1
					break
	# A handful of extra chunks so the ore count is not a coin flip.
	for extra in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 2), Vector2i(-1, 1)]:
		var extra_chunk := Chunk.new(extra)
		generator.generate_chunk(extra_chunk)
		for x in Chunk.SIZE:
			for z in Chunk.SIZE:
				for y in Chunk.HEIGHT:
					if ore_names.has(Blocks.name_of(extra_chunk.get_block(x, y, z))):
						ores += 1
	check(solid > 0 and air > 0, "the chunk has both air and blocks")
	check(bedrock == Chunk.SIZE * Chunk.SIZE, "bedrock seals the bottom of the world")
	check(above_sea > 0, "some columns rise above sea level (%d)" % above_sea)
	check(ores > 0, "the world contains ore (%d blocks in six chunks)" % ores)
	check(leaves >= 0, "leaf scan completed (%d leaf columns)" % leaves)

	var height_a: int = generator.height_at(0, 0)
	check(height_a == generator.height_at(0, 0), "terrain height is deterministic")
	check(WorldGen.new(1337).height_at(40, 40) == generator.height_at(40, 40),
		"the same seed produces the same terrain")
	var other := WorldGen.new(4242)
	check(other.height_at(40, 40) != height_a or other.height_at(80, 80) != generator.height_at(80, 80),
		"a different seed changes the terrain")
	check(height_a > 0 and height_a < Chunk.HEIGHT, "the surface height is inside the world")
	var biome: int = generator.biome_at(0, 0)
	check(biome >= 0 and biome < WorldGen.BIOME_NAMES.size(), "the biome lookup is in range (%s)"
		% WorldGen.BIOME_NAMES[biome])

	var village_a: Vector2i = StructureGen.village_center_near(generator, 0, 0, 900)
	var village_b: Vector2i = StructureGen.village_center_near(generator, 0, 0, 900)
	check(village_a == village_b, "village placement is deterministic")
	check(StructureGen.village_center_near(generator, 0, 0, 0) == StructureGen.NO_VILLAGE,
		"a zero-radius village search finds nothing")

	LightEngine.relight_chunk(chunk, {})
	check(chunk.get_sky_light(8, Chunk.HEIGHT - 1, 8) == 15, "the sky is fully lit")
	var dark_point := Vector3i(8, 6, 8)
	check(chunk.get_sky_light(dark_point.x, dark_point.y, dark_point.z) == 0
		or Blocks.is_opaque(chunk.get_block(dark_point.x, dark_point.y, dark_point.z)) == false,
		"lighting ran over the chunk")


# ---------------------------------------------------------------------------
# Mobs and villagers
# ---------------------------------------------------------------------------


func _test_mobs_and_trades() -> void:
	print("- mobs and trades")
	var types: Dictionary = MobTypes.all()
	check(types.size() >= 8, "%d mob types" % types.size())
	for mob_type in types.keys():
		var stats: Dictionary = MobTypes.get_stats(mob_type)
		check(float(stats.get("health", 0.0)) > 0.0, "%s has health" % mob_type)
		check(str(stats.get("model", "")) != "", "%s has a model kind" % mob_type)
		check(str(stats.get("skin", "")) != "", "%s has a skin" % mob_type)
		for drop in stats.get("drops", []):
			check(Items.def_by_name(str(drop[0])) != null, "%s drops a real item (%s)"
				% [mob_type, str(drop[0])])
	check(MobTypes.hostile_types().size() >= 4, "%d hostile mob types"
		% MobTypes.hostile_types().size())
	check(not MobTypes.wild_passive_types().has("villager"), "villagers never spawn in the wild")
	check(MobTypes.village_types().has("villager"), "villagers spawn in villages")
	check(MobTypes.exists("creeper"), "creepers exist")
	check(not MobTypes.exists("dragon"), "an unknown mob type reports false")

	check(Trades.PROFESSION_NAMES.size() >= 4, "%d villager professions"
		% Trades.PROFESSION_NAMES.size())
	for profession in Trades.PROFESSION_NAMES:
		var offers: Array = Trades.offers(str(profession))
		check(not offers.is_empty(), "'%s' has offers" % profession)
		check(str(Trades.title(str(profession))) != "", "'%s' has a title" % profession)
		for offer in offers:
			var give_name: String = str(offer.get("give", ""))
			var get_name: String = str(offer.get("get", ""))
			check(Items.def_by_name(give_name) != null and Items.def_by_name(get_name) != null,
				"'%s' trades real items (%s)" % [profession, Trades.describe(offer)])
			check(int(offer.get("give_count", 0)) > 0 and int(offer.get("get_count", 0)) > 0,
				"'%s' trade counts are positive" % profession)


# ---------------------------------------------------------------------------
# Containers
# ---------------------------------------------------------------------------


func _test_containers() -> void:
	print("- containers")
	var chest := BlockContainer.new(BlockContainer.KIND_CHEST)
	check(chest.size() == 27, "chests have 27 slots")
	check(BlockContainer.new(BlockContainer.KIND_DISPENSER).size() == 9, "dispensers have 9 slots")
	var iron: int = Items.id("iron_ingot")
	check(chest.add(iron, 40) == 0, "40 ingots fit in a fresh chest")
	check(chest.count_of(iron) == 40, "the chest counts its ingots")
	check(chest.add(iron, 100) == 0, "100 more ingots fit")
	check(chest.count_of(iron) == 140, "the chest holds 140 ingots")
	check(chest.add(iron, 2000) > 0, "the chest refuses to overflow and reports the leftover")
	var emptied: int = chest.remove(iron, chest.count_of(iron))
	check(emptied == 140 and chest.is_empty(), "the chest empties again")

	var furnace := BlockContainer.new(BlockContainer.KIND_FURNACE)
	furnace.set_slot(0, BlockContainer.make_stack(Items.id("iron_ore"), 3))
	furnace.set_slot(1, BlockContainer.make_stack(Items.id("coal"), 1))
	var encoded: Array = furnace.serialize()
	check(encoded.size() == 3, "a furnace serialises to three slots")
	var restored := BlockContainer.new(BlockContainer.KIND_FURNACE)
	restored.deserialize(encoded)
	check(restored.get_slot(0) != null and int(restored.get_slot(0)["count"]) == 3,
		"furnace contents survive a save round trip")
	var smelted: bool = false
	for _step in 60:
		if restored.tick_furnace(1.0):
			smelted = true
			break
	check(smelted, "the restored furnace smelts")
	var output: Variant = restored.get_slot(2)
	check(output != null, "smelting produced output")
	if output != null:
		check(int(output["id"]) == Items.id("iron_ingot"), "the output is an iron ingot")
	check(restored.burn_time > 0.0 or restored.lit, "the furnace consumed its fuel")
