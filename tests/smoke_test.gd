extends SceneTree

## Headless smoke test.
##
##     godot --headless --path . --script res://tests/smoke_test.gd
##
## It builds the content registries, generates a few chunks, crafts a handful of
## recipes and checks the mob/trade tables. Anything that throws or fails an
## assertion exits with a non-zero status, which is what CI looks at.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	print("Blockcraft smoke test")
	_test_registries()
	_test_recipes()
	_test_world_generation()
	_test_mobs_and_trades()
	_test_save_format()
	print("")
	if failures == 0:
		print("SMOKE OK - %d checks passed" % checks)
	else:
		print("SMOKE FAILED - %d of %d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _test_registries() -> void:
	print("- registries")
	Blocks.build()
	Items.build()
	Recipes.build()
	check(Blocks.defs.size() > 100, "more than 100 block types (%d)" % Blocks.defs.size())
	check(Items.defs.size() > 200, "more than 200 items (%d)" % Items.defs.size())
	for block_name in ["stone", "grass_block", "dirt", "oak_log", "chest", "furnace", "torch",
			"water", "lava", "bedrock", "diamond_ore", "piston", "piston_arm", "tnt"]:
		check(Blocks.id(block_name) > 0, "block '%s' registered" % block_name)
	for item_name in ["stick", "coal", "iron_ingot", "diamond", "emerald", "stone_pickaxe",
			"diamond_sword", "iron_chestplate", "bread", "apple"]:
		check(Items.id(item_name) > 0, "item '%s' registered" % item_name)
	var stone_pickaxe: int = Items.id("stone_pickaxe")
	check(Items.tool_kind(stone_pickaxe) == "pickaxe", "stone pickaxe is a pickaxe")
	check(Items.tool_tier(stone_pickaxe) == Blocks.TIER_STONE, "stone pickaxe has tier 2")
	check(Items.durability(stone_pickaxe) > 0, "stone pickaxe has durability")
	check(Items.places_block(Blocks.id("stone")) == Blocks.id("stone"), "stone item places stone")
	check(Blocks.break_time(Blocks.id("stone"), "diamond_pickaxe", Blocks.TIER_DIAMOND)
		< Blocks.break_time(Blocks.id("stone"), "", Blocks.TIER_NONE),
		"a diamond pickaxe mines stone faster than a bare hand")
	check(Blocks.def(Blocks.id("bedrock")).hardness < 0.0, "bedrock is unbreakable")
	var drops: Array = Blocks.drops_for(Blocks.id("diamond_ore"), "stone_pickaxe",
		Blocks.TIER_STONE)
	check(not drops.is_empty(), "diamond ore drops something with a stone pickaxe")
	var bare: Array = Blocks.drops_for(Blocks.id("diamond_ore"), "", Blocks.TIER_NONE)
	check(bare.is_empty(), "diamond ore drops nothing to a bare hand")


func _test_recipes() -> void:
	print("- recipes")
	check(Recipes.shaped.size() > 40, "at least 40 shaped recipes (%d)" % Recipes.shaped.size())
	check(Recipes.smelting.size() > 10, "at least 10 smelting recipes (%d)"
		% Recipes.smelting.size())
	var planks: int = Items.id("oak_planks")
	var log_id: int = Items.id("oak_log")
	var grid: Array = [log_id, -1, -1, -1]
	var recipe: Recipes.Recipe = Recipes.match(grid, 2, 2)
	check(recipe != null, "a lone log matches a shapeless recipe")
	if recipe != null:
		check(Items.id(str(recipe.results[0]["item"])) == planks, "log crafts into planks")
	var table_grid: Array = [planks, planks, -1, planks, planks, -1, -1, -1, -1]
	var table_recipe: Recipes.Recipe = Recipes.match(table_grid, 3, 3)
	check(table_recipe != null, "four planks match the crafting table recipe")
	if table_recipe != null:
		check(Items.id(str(table_recipe.results[0]["item"])) == Blocks.id("crafting_table"),
			"planks craft into a crafting table")
	var smelt: Dictionary = Recipes.smelting_for(Blocks.id("iron_ore"))
	check(not smelt.is_empty(), "iron ore can be smelted")
	if not smelt.is_empty():
		check(int(smelt["item"]) == Items.id("iron_ingot"), "iron ore smelts into iron ingots")
	check(Recipes.fuel_seconds(Items.id("coal")) > 0.0, "coal burns as fuel")
	check(not Recipes.options_for("#planks").is_empty(), "the '#planks' tag resolves to items")


func _test_world_generation() -> void:
	print("- world generation")
	var generator := WorldGen.new(1337)
	var chunk := Chunk.new(Vector2i(0, 0))
	generator.generate_chunk(chunk)
	var air: int = 0
	var solid: int = 0
	var bedrock: int = 0
	var surface: int = 0
	for x in Chunk.SIZE:
		for z in Chunk.SIZE:
			var height: int = 0
			for y in Chunk.HEIGHT:
				var block_id: int = chunk.get_block(x, y, z)
				if block_id == Blocks.AIR:
					air += 1
				else:
					solid += 1
					height = y
			if chunk.get_block(x, 0, z) == Blocks.BEDROCK:
				bedrock += 1
			if height > WorldGen.SEA_LEVEL:
				surface += 1
	check(solid > 0 and air > 0, "the generated chunk has both air and blocks")
	check(bedrock == Chunk.SIZE * Chunk.SIZE, "bedrock seals the bottom of the world")
	check(surface > 0, "some columns rise above sea level (%d)" % surface)
	var height_a: int = generator.height_at(0, 0)
	var height_b: int = generator.height_at(0, 0)
	check(height_a == height_b, "terrain height is deterministic")
	var second := WorldGen.new(1337)
	check(second.height_at(40, 40) == generator.height_at(40, 40),
		"the same seed produces the same terrain")
	var other := WorldGen.new(4242)
	check(other.height_at(40, 40) != height_a or other.height_at(80, 80) != generator.height_at(80, 80),
		"a different seed changes the terrain")
	var biome: int = generator.biome_at(0, 0)
	check(biome >= 0 and biome < WorldGen.BIOME_NAMES.size(), "biome lookup is in range")
	var village: Vector2i = StructureGen.village_center_near(generator, 0, 0, 900)
	check(village == StructureGen.village_center_near(generator, 0, 0, 900),
		"village placement is deterministic")
	check(StructureGen.village_center_near(generator, 0, 0, 0) == StructureGen.NO_VILLAGE,
		"a zero-radius village search returns nothing")


func _test_mobs_and_trades() -> void:
	print("- mobs and trades")
	for mob_type in ["pig", "cow", "sheep", "chicken", "cat", "zombie", "skeleton", "creeper",
			"spider", "villager"]:
		var stats: Dictionary = MobTypes.get_stats(mob_type)
		check(not stats.is_empty() and float(stats["health"]) > 0.0,
			"mob '%s' has stats" % mob_type)
		check(str(stats.get("model", "")) != "", "mob '%s' has a model kind" % mob_type)
	check(MobTypes.hostile_types().size() >= 4, "at least four hostile mob types")
	check(not MobTypes.wild_passive_types().has("villager"),
		"villagers do not spawn in the wild")
	check(MobTypes.village_types().has("villager"), "villagers spawn in villages")
	for mob_type in MobTypes.all().keys():
		var skin: String = str(MobTypes.get_stats(mob_type).get("skin", ""))
		check(skin != "", "mob '%s' has a skin sheet" % mob_type)
		for drop in MobTypes.get_stats(mob_type).get("drops", []):
			check(Items.id(str(drop[0])) >= 0, "mob '%s' drops a real item (%s)"
				% [mob_type, str(drop[0])])
	var professions: Array = Trades.PROFESSION_NAMES
	check(professions.size() >= 4, "at least four villager professions")
	for profession in professions:
		var offers: Array = Trades.offers(str(profession))
		check(not offers.is_empty(), "profession '%s' has trades" % profession)
		for offer in offers:
			check(Items.id(str(offer["give"])) >= 0 and Items.id(str(offer["get"])) >= 0,
				"'%s' trade uses real items (%s)" % [profession, Trades.describe(offer)])


func _test_save_format() -> void:
	print("- saves")
	var container := BlockContainer.new(BlockContainer.KIND_FURNACE)
	container.set_slot(0, BlockContainer.make_stack(Items.id("iron_ore"), 3))
	container.set_slot(1, BlockContainer.make_stack(Items.id("coal"), 1))
	var encoded: Array = container.serialize()
	check(encoded.size() == 3, "a furnace serialises to three slots")
	var restored := BlockContainer.new(BlockContainer.KIND_FURNACE)
	restored.deserialize(encoded)
	check(restored.get_slot(0) != null and int(restored.get_slot(0)["count"]) == 3,
		"furnace contents survive a save round trip")
	var before: float = restored.get_slot(0)["count"]
	var smelted: bool = false
	for _step in 40:
		if restored.tick_furnace(1.0):
			smelted = true
			break
	check(smelted, "the restored furnace actually smelts")
	check(restored.get_slot(2) != null, "smelting produced output")
	check(before > 0.0, "sanity: the input stack was there")
	var chest := BlockContainer.new(BlockContainer.KIND_CHEST)
	check(chest.size() == 27, "chests have 27 slots")
	var dispenser := BlockContainer.new(BlockContainer.KIND_DISPENSER)
	check(dispenser.size() == 9, "dispensers have 9 slots")
