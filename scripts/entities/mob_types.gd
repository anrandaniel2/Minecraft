class_name MobTypes
extends RefCounted

## Every mob's stats, model, drops and spawn rules in one table.
##
## Fields:
##   health, speed (m/s), hostile, flying, model (BoxModel kind), skin (sheet name),
##   width/height (collision box), attack (damage per hit), reach (attack range),
##   xp, drops [[item, min, max, chance]], sound, sound_interval, biomes (empty = any),
##   min_light/max_light for spawning, spawn_group (how many spawn together),
##   burns_in_daylight, can_swim, jump_power.

static func all() -> Dictionary:
	return {
	"pig": {
		"health": 10.0, "speed": 2.0, "hostile": false, "model": "quadruped",
		"skin": "pig", "width": 0.9, "height": 0.9, "xp": 1,
		"drops": [["porkchop", 1, 3, 1.0]], "sound": "pig_oink", "sound_interval": 8.0,
		"biomes": [WorldGen.BIOME_PLAINS, WorldGen.BIOME_FOREST, WorldGen.BIOME_SAVANNA,
			WorldGen.BIOME_TAIGA, WorldGen.BIOME_JUNGLE],
		"min_light": 0.35, "max_light": 1.0, "spawn_group": 3, "tempt": "carrot",
	},
	"villager": {
		"health": 20.0, "speed": 1.6, "hostile": false, "model": "humanoid",
		"skin": "villager", "width": 0.7, "height": 1.9, "xp": 0,
		"drops": [], "sound": "villager_hmm", "sound_interval": 12.0,
		"biomes": [], "min_light": 0.0, "max_light": 1.0, "spawn_group": 3,
		"village": true,
	},
	"cow": {
		"health": 10.0, "speed": 1.9, "hostile": false, "model": "quadruped",
		"skin": "cow", "width": 0.95, "height": 1.3, "xp": 1,
		"drops": [["beef", 1, 3, 1.0], ["leather", 0, 2, 1.0]], "sound": "cow_moo",
		"sound_interval": 10.0,
		"biomes": [WorldGen.BIOME_PLAINS, WorldGen.BIOME_FOREST, WorldGen.BIOME_SAVANNA,
			WorldGen.BIOME_TAIGA],
		"min_light": 0.35, "max_light": 1.0, "spawn_group": 3, "tempt": "wheat",
	},
	"sheep": {
		"health": 8.0, "speed": 2.0, "hostile": false, "model": "quadruped",
		"skin": "sheep", "width": 0.9, "height": 1.25, "xp": 1,
		"drops": [["mutton", 1, 2, 1.0]], "sound": "sheep_baa", "sound_interval": 9.0,
		"biomes": [WorldGen.BIOME_PLAINS, WorldGen.BIOME_FOREST, WorldGen.BIOME_MOUNTAINS,
			WorldGen.BIOME_TAIGA, WorldGen.BIOME_SNOWY],
		"min_light": 0.35, "max_light": 1.0, "spawn_group": 4, "tempt": "wheat",
		"shearable": "white_wool",
	},
	"chicken": {
		"health": 4.0, "speed": 2.1, "hostile": false, "model": "chicken",
		"skin": "chicken", "width": 0.5, "height": 0.7, "xp": 1,
		"drops": [["chicken", 1, 1, 1.0], ["feather", 0, 2, 1.0]], "sound": "chicken_cluck",
		"sound_interval": 7.0, "fall_slow": true,
		"biomes": [WorldGen.BIOME_PLAINS, WorldGen.BIOME_FOREST, WorldGen.BIOME_JUNGLE,
			WorldGen.BIOME_SWAMP],
		"min_light": 0.35, "max_light": 1.0, "spawn_group": 4, "tempt": "wheat_seeds",
	},
	"cat": {
		"health": 8.0, "speed": 2.6, "hostile": false, "model": "quadruped",
		"skin": "cat", "width": 0.6, "height": 0.7, "xp": 1,
		"drops": [], "sound": "cat_meow", "sound_interval": 12.0,
		"biomes": [WorldGen.BIOME_PLAINS, WorldGen.BIOME_FOREST, WorldGen.BIOME_SWAMP],
		"min_light": 0.2, "max_light": 1.0, "spawn_group": 1, "tempt": "chicken",
		"scares_creepers": true,
	},
	"zombie": {
		"health": 20.0, "speed": 2.3, "hostile": true, "model": "humanoid",
		"skin": "zombie", "width": 0.6, "height": 1.9, "attack": 3.0, "reach": 1.4,
		"xp": 5, "drops": [["rotten_flesh", 0, 2, 1.0]], "sound": "zombie_idle",
		"sound_interval": 6.0, "burns_in_daylight": true, "follow_range": 20.0,
		"biomes": [], "min_light": 0.0, "max_light": 0.32, "spawn_group": 3,
		"reinforcements": true,
	},
	"skeleton": {
		"health": 20.0, "speed": 2.2, "hostile": true, "model": "humanoid",
		"skin": "skeleton", "width": 0.6, "height": 1.9, "attack": 0.0, "reach": 14.0,
		"xp": 5, "drops": [["bone", 0, 2, 1.0], ["arrow", 0, 2, 1.0]], "sound": "skeleton_rattle",
		"sound_interval": 7.0, "burns_in_daylight": true, "ranged": true, "follow_range": 22.0,
		"biomes": [], "min_light": 0.0, "max_light": 0.32, "spawn_group": 2,
	},
	"creeper": {
		"health": 20.0, "speed": 2.1, "hostile": true, "model": "creeper",
		"skin": "creeper", "width": 0.6, "height": 1.7, "attack": 0.0, "reach": 2.0,
		"xp": 5, "drops": [["gunpowder", 0, 2, 1.0]], "sound": "creeper_hiss",
		"sound_interval": 9.0, "explodes": true, "explosion_power": 3.0, "follow_range": 18.0,
		"biomes": [], "min_light": 0.0, "max_light": 0.3, "spawn_group": 1,
	},
	"spider": {
		"health": 16.0, "speed": 2.8, "hostile": true, "model": "spider",
		"skin": "cat", "width": 1.0, "height": 0.8, "attack": 2.0, "reach": 1.3,
		"xp": 5, "drops": [["string", 0, 2, 1.0]], "sound": "zombie_hurt",
		"sound_interval": 8.0, "climbs": true, "follow_range": 18.0,
		"biomes": [], "min_light": 0.0, "max_light": 0.35, "spawn_group": 2,
	},
	}


static func get_stats(mob_type: String) -> Dictionary:
	var table: Dictionary = all()
	return table.get(mob_type, table["pig"])


static func exists(mob_type: String) -> bool:
	return all().has(mob_type)


## Passive mobs that spawn in the wild (villagers are placed by villages only).
static func wild_passive_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for mob_type in passive_types():
		if not bool(get_stats(mob_type).get("village", false)):
			out.append(mob_type)
	return out


## Villagers, which the mob manager only spawns inside villages.
static func village_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for mob_type in passive_types():
		if bool(get_stats(mob_type).get("village", false)):
			out.append(mob_type)
	return out


static func passive_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for mob_type in all():
		if not bool(all()[mob_type]["hostile"]):
			out.append(mob_type)
	return out


static func hostile_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for mob_type in all():
		if bool(all()[mob_type]["hostile"]):
			out.append(mob_type)
	return out


static func display_name(mob_type: String) -> String:
	return Blocks._prettify(mob_type)
