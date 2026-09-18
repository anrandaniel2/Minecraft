class_name WorldGen
extends RefCounted

## Deterministic terrain generation.
##
## Everything is a pure function of (world_seed, x, y, z), which is what makes
## infinite streaming possible: chunks can be generated in any order, on any
## thread, and always agree at their borders. Player edits are stored separately
## by the World node and re-applied on top.
##
## Generation pipeline per chunk:
##   1. terrain columns (continentalness / erosion / hills / mountains / rivers)
##   2. biome assignment per column (temperature x humidity x height)
##   3. surface materials (grass, sand, snow, red sand, podzol...)
##   4. water fill up to sea level
##   5. caves: two interpolated 3D tunnel noises plus cheese caverns
##   6. ore veins, placed as hashed blobs by depth band
##   7. structures (villages, dungeons, mineshafts, wells, huts)
##   8. decorations: trees, grass, flowers, cacti, sugar cane, pumpkins, mushrooms

const SIZE: int = Chunk.SIZE
const HEIGHT: int = Chunk.HEIGHT
const SEA_LEVEL: int = 62
const BEDROCK_LEVEL: int = 3
const BASE_HEIGHT: int = 66

# --- biome ids ---
const BIOME_OCEAN: int = 0
const BIOME_BEACH: int = 1
const BIOME_PLAINS: int = 2
const BIOME_FOREST: int = 3
const BIOME_TAIGA: int = 4
const BIOME_DESERT: int = 5
const BIOME_SAVANNA: int = 6
const BIOME_JUNGLE: int = 7
const BIOME_MOUNTAINS: int = 8
const BIOME_SNOWY: int = 9
const BIOME_SWAMP: int = 10
const BIOME_IDS: int = 11

const BIOME_NAMES: PackedStringArray = [
	"Ocean", "Beach", "Plains", "Forest", "Taiga", "Desert", "Savanna",
	"Jungle", "Mountains", "Snowy Tundra", "Swamp",
]

# Cave sampling lattice: caves are evaluated every CAVE_STEP blocks and
# trilinearly interpolated, which is ~35x cheaper than per-voxel noise.
const CAVE_STEP: int = 4
const GRID_W: int = SIZE / CAVE_STEP + 1
const GRID_H: int = HEIGHT / CAVE_STEP + 1

var seed_value: int = 0
var _n_continent: FastNoiseLite
var _n_erosion: FastNoiseLite
var _n_hills: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_mountain_mask: FastNoiseLite
var _n_river: FastNoiseLite
var _n_temperature: FastNoiseLite
var _n_humidity: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_tunnel_a: FastNoiseLite
var _n_tunnel_b: FastNoiseLite
var _n_cheese: FastNoiseLite
var _n_dirt_depth: FastNoiseLite
var _n_cave_scale: FastNoiseLite

# per-chunk scratch buffers (generation runs on one thread per chunk)
var _height_cache: Dictionary = {}
var _biome_cache: Dictionary = {}


func _init(world_seed: int = 1337) -> void:
	seed_value = world_seed
	_build_noise()


func _build_noise() -> void:
	_n_continent = _noise(0, 0.0012, 3, 0.55, 2.0)
	_n_erosion = _noise(1, 0.0045, 2, 0.5, 2.0)
	_n_hills = _noise(2, 0.021, 4, 0.5, 2.0)
	_n_ridge = _noise(3, 0.0075, 4, 0.5, 2.1, FastNoiseLite.FRACTAL_RIDGED)
	_n_mountain_mask = _noise(4, 0.0016, 2, 0.5, 2.0)
	_n_river = _noise(5, 0.0022, 2, 0.5, 2.0, FastNoiseLite.FRACTAL_RIDGED)
	_n_temperature = _noise(6, 0.0009, 2, 0.5, 2.0)
	_n_humidity = _noise(7, 0.0011, 2, 0.5, 2.0)
	_n_detail = _noise(8, 0.09, 2, 0.5, 2.0)
	_n_tunnel_a = _noise(9, 0.017, 2, 0.5, 2.0)
	_n_tunnel_b = _noise(10, 0.017, 2, 0.5, 2.0)
	_n_cheese = _noise(11, 0.012, 3, 0.5, 2.0)
	_n_dirt_depth = _noise(12, 0.05, 2, 0.5, 2.0)
	_n_cave_scale = _noise(13, 0.003, 2, 0.5, 2.0)


func _noise(index: int, frequency: float, octaves: int, gain: float, lacunarity: float,
		fractal: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value * 31 + index * 7919
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = lacunarity
	return noise


# ---------------------------------------------------------------------------
# Height / biome queries
# ---------------------------------------------------------------------------


## Terrain surface height (topmost solid block's y) at a world column.
func height_at(world_x: int, world_z: int) -> int:
	var key: int = (world_x << 20) ^ (world_z & 0xFFFFF)
	var cached = _height_cache.get(key)
	if cached != null:
		return cached
	var h: int = _compute_height(world_x, world_z)
	if _height_cache.size() > 4096:
		_height_cache.clear()
	_height_cache[key] = h
	return h


func _compute_height(world_x: int, world_z: int) -> int:
	var x := float(world_x)
	var z := float(world_z)
	var continent: float = _n_continent.get_noise_2d(x, z)          # -1..1
	var erosion: float = _n_erosion.get_noise_2d(x, z)
	var hills: float = _n_hills.get_noise_2d(x, z)
	var mountain: float = clampf((_n_mountain_mask.get_noise_2d(x, z) + 0.15) * 1.6, 0.0, 1.0)
	var ridge: float = _n_ridge.get_noise_2d(x, z)
	var detail: float = _n_detail.get_noise_2d(x, z)

	# Ocean basins vs land: continentalness drives the base elevation.
	var base: float = float(BASE_HEIGHT) + continent * 26.0
	# Erosion carves valleys, positive values flatten the terrain.
	var flat: float = clampf(1.0 - erosion * 0.8, 0.25, 1.4)
	var rolling: float = hills * 9.0 * flat
	# Mountains rise where the mask is high, sharpened by the ridged noise.
	var mountain_height: float = pow(mountain, 1.7) * 62.0 * clampf(erosion + 0.7, 0.2, 1.5)
	var ridged: float = pow(clampf(ridge * 0.5 + 0.5, 0.0, 1.0), 1.6) * mountain
	var height: float = base + rolling + mountain_height + ridged * 22.0 + detail * 1.6

	# Rivers: narrow bands where the ridged river noise sits near its crest.
	var river: float = absf(_n_river.get_noise_2d(x, z))
	if river < 0.045 and height > float(SEA_LEVEL) - 4.0:
		var depth: float = 1.0 - river / 0.045
		height = lerpf(height, float(SEA_LEVEL) - 3.0, clampf(depth * 1.35, 0.0, 1.0))

	return clampi(int(round(height)), BEDROCK_LEVEL + 1, HEIGHT - 12)


func biome_at(world_x: int, world_z: int) -> int:
	var key: int = (world_x << 20) ^ (world_z & 0xFFFFF)
	var cached = _biome_cache.get(key)
	if cached != null:
		return cached
	var height: int = height_at(world_x, world_z)
	var temperature: float = _n_temperature.get_noise_2d(float(world_x), float(world_z))
	var humidity: float = _n_humidity.get_noise_2d(float(world_x), float(world_z))
	var biome: int = classify_biome(height, temperature, humidity)
	if _biome_cache.size() > 8192:
		_biome_cache.clear()
	_biome_cache[key] = biome
	return biome


static func classify_biome(height: int, temperature: float, humidity: float) -> int:
	if height <= SEA_LEVEL - 4:
		return BIOME_OCEAN
	if height <= SEA_LEVEL + 1:
		if temperature < -0.35:
			return BIOME_SNOWY
		return BIOME_BEACH
	if height > SEA_LEVEL + 42:
		return BIOME_MOUNTAINS
	# Cold-adapted biomes first, then a temperature/humidity matrix.
	if temperature < -0.35:
		return BIOME_TAIGA if humidity > -0.1 else BIOME_SNOWY
	if temperature < -0.05 and humidity > 0.35:
		return BIOME_SWAMP
	if temperature > 0.35:
		if humidity < -0.25:
			return BIOME_DESERT
		if humidity < 0.15:
			return BIOME_SAVANNA
		return BIOME_JUNGLE
	if humidity > 0.28:
		return BIOME_FOREST
	return BIOME_PLAINS


## Surface (top solid) y for a chunk-local column, clamped to chunk height.
func local_height(chunk_x: int, chunk_z: int, x: int, z: int) -> int:
	return height_at(chunk_x * SIZE + x, chunk_z * SIZE + z)


# ---------------------------------------------------------------------------
# Chunk generation
# ---------------------------------------------------------------------------


func generate_chunk(chunk: Chunk) -> void:
	var origin_x: int = chunk.coord.x * SIZE
	var origin_z: int = chunk.coord.y * SIZE
	var heights := PackedInt32Array()
	var biomes := PackedInt32Array()
	heights.resize(SIZE * SIZE)
	biomes.resize(SIZE * SIZE)

	# 1 + 2: columns and biomes
	for z in SIZE:
		for x in SIZE:
			var world_x: int = origin_x + x
			var world_z: int = origin_z + z
			var height: int = height_at(world_x, world_z)
			var temperature: float = _n_temperature.get_noise_2d(float(world_x), float(world_z))
			var humidity: float = _n_humidity.get_noise_2d(float(world_x), float(world_z))
			var biome: int = classify_biome(height, temperature, humidity)
			heights[z * SIZE + x] = height
			biomes[z * SIZE + x] = biome

	# 3 + 4: materials and water
	for z in SIZE:
		for x in SIZE:
			var height: int = heights[z * SIZE + x]
			var biome: int = biomes[z * SIZE + x]
			_fill_column(chunk, x, z, height, biome)
			if height < SEA_LEVEL:
				var water_top: int = SEA_LEVEL
				for y in range(height + 1, water_top + 1):
					if chunk.get_block(x, y, z) == Blocks.AIR:
						chunk.set_block(x, y, z, Blocks.WATER, 7)
			chunk.set_block(x, 0, z, Blocks.BEDROCK, 0)
			if height > 1 and _hash3(origin_x + x, 1, origin_z + z) % 3 != 0:
				chunk.set_block(x, 1, z, Blocks.BEDROCK, 0)
			if height > 2 and _hash3(origin_x + x, 2, origin_z + z) % 5 != 0:
				chunk.set_block(x, 2, z, Blocks.BEDROCK, 0)

	# 5: caves
	_carve_caves(chunk, heights)
	# 6: ores
	_place_ores(chunk, heights)
	# 7: structures
	StructureGen.generate(self, chunk, heights, biomes)
	# 8: decorations
	_decorate(chunk, heights, biomes)
	chunk.generated = true
	chunk.dirty = true


func _fill_column(chunk: Chunk, x: int, z: int, height: int, biome: int) -> void:
	var soil_depth: int = 3 + int(_n_dirt_depth.get_noise_2d(float(x), float(z)) * 1.5)
	var sub_block: int = Blocks.STONE
	var top_block: int = Blocks.GRASS
	var soil: int = Blocks.DIRT
	match biome:
		BIOME_OCEAN:
			top_block = Blocks.SAND
			soil = Blocks.SAND
		BIOME_BEACH:
			top_block = Blocks.SAND
			soil = Blocks.SAND
		BIOME_DESERT:
			top_block = Blocks.SAND
			soil = Blocks.SAND
			sub_block = Blocks.SANDSTONE
			soil_depth = 5
		BIOME_SAVANNA:
			top_block = Blocks.GRASS
			soil = Blocks.COARSE_DIRT
		BIOME_SNOWY, BIOME_TAIGA:
			top_block = Blocks.SNOWY_GRASS_BLOCK
			soil = Blocks.DIRT
		BIOME_MOUNTAINS:
			top_block = Blocks.STONE if height > SEA_LEVEL + 34 else Blocks.GRASS
			soil = Blocks.STONE if height > SEA_LEVEL + 34 else Blocks.DIRT
		BIOME_SWAMP:
			top_block = Blocks.GRASS
			soil = Blocks.DIRT
	var clay: int = Blocks.CLAY
	# stone core
	for y in range(BEDROCK_LEVEL, height - soil_depth + 1):
		if y > BEDROCK_LEVEL - 1:
			var block: int = sub_block
			# scattered granite/diorite/andesite patches keep stone interesting
			var patch: int = _hash3(x * 7 + y, y * 13, z * 3 + y) % 100
			if patch < 4:
				block = Blocks.GRANITE
			elif patch < 8:
				block = Blocks.DIORITE
			elif patch < 12:
				block = Blocks.ANDESITE
			chunk.set_block(x, y, z, block)
	# soil band
	for y in range(maxi(BEDROCK_LEVEL, height - soil_depth + 1), height):
		chunk.set_block(x, y, z, soil)
	# surface block
	if height >= BEDROCK_LEVEL:
		chunk.set_block(x, height, z, top_block)
		if biome == BIOME_SWAMP and height <= SEA_LEVEL + 1 and _hash3(x, height, z) % 3 == 0:
			chunk.set_block(x, height, z, clay)


# ---------------------------------------------------------------------------
# Caves
# ---------------------------------------------------------------------------


func _carve_caves(chunk: Chunk, heights: PackedInt32Array) -> void:
	var origin_x: int = chunk.coord.x * SIZE
	var origin_z: int = chunk.coord.y * SIZE
	var tunnel_a := PackedFloat32Array()
	var tunnel_b := PackedFloat32Array()
	var cheese := PackedFloat32Array()
	var total: int = GRID_W * GRID_H * GRID_W
	tunnel_a.resize(total)
	tunnel_b.resize(total)
	cheese.resize(total)

	# Sample the 3D noises on a coarse lattice.
	for gz in GRID_W:
		for gy in GRID_H:
			for gx in GRID_W:
				var wx := float(origin_x + gx * CAVE_STEP)
				var wy := float(gy * CAVE_STEP)
				var wz := float(origin_z + gz * CAVE_STEP)
				var index: int = (gy * GRID_W + gz) * GRID_W + gx
				tunnel_a[index] = _n_tunnel_a.get_noise_3d(wx, wy * 1.8, wz)
				tunnel_b[index] = _n_tunnel_b.get_noise_3d(wx, wy * 1.8, wz)
				cheese[index] = _n_cheese.get_noise_3d(wx, wy * 1.4, wz)

	var lava_level: int = 11
	for z in SIZE:
		for x in SIZE:
			var height: int = heights[z * SIZE + x]
			var surface_guard: int = height - 3
			var max_y: int = mini(HEIGHT - 1, height + 1)
			for y in range(BEDROCK_LEVEL + 1, max_y):
				# Trilinear interpolation of the lattice samples at the voxel.
				var fx: float = float(x) / float(CAVE_STEP)
				var fy: float = float(y) / float(CAVE_STEP)
				var fz: float = float(z) / float(CAVE_STEP)
				var gx0: int = mini(int(fx), GRID_W - 2)
				var gy0: int = mini(int(fy), GRID_H - 2)
				var gz0: int = mini(int(fz), GRID_W - 2)
				var tx: float = fx - float(gx0)
				var ty: float = fy - float(gy0)
				var tz: float = fz - float(gz0)
				var base_a: int = (gy0 * GRID_W + gz0) * GRID_W + gx0
				var base_b: int = base_a + GRID_W
				var base_c: int = base_a + GRID_W * GRID_W
				var base_d: int = base_c + GRID_W
				var a_val: float = _lerp3(tunnel_a, base_a, base_b, base_c, base_d, tx, ty, tz)
				var b_val: float = _lerp3(tunnel_b, base_a, base_b, base_c, base_d, tx, ty, tz)
				var c_val: float = _lerp3(cheese, base_a, base_b, base_c, base_d, tx, ty, tz)

				# Two intersecting tunnel fields carve winding caves when both
				# are near zero; the cheese field opens large caverns deeper down.
				var is_cave: bool = false
				if absf(a_val) < 0.075 and absf(b_val) < 0.075:
					is_cave = true
				elif c_val > 0.62 and y < 52:
					is_cave = true
				if not is_cave:
					continue
				if y > surface_guard:
					continue  # keep a roof so the surface stays walkable
				var current: int = chunk.get_block(x, y, z)
				if current == Blocks.BEDROCK or Blocks.is_liquid(current):
					continue
				if y <= lava_level:
					chunk.set_block(x, y, z, Blocks.LAVA, 7)
				else:
					chunk.set_block(x, y, z, Blocks.AIR)
				# Let a little light in where caves reach the surface.
				if y == surface_guard and _hash3(x + y, y, z * 3) % 7 == 0:
					chunk.set_block(x, y + 1, z, Blocks.AIR)


static func _lerp3(values: PackedFloat32Array, base_a: int, base_b: int, base_c: int,
		base_d: int, tx: float, ty: float, tz: float) -> float:
	# x axis
	var a0: float = values[base_a] + (values[base_a + 1] - values[base_a]) * tx
	var a1: float = values[base_b] + (values[base_b + 1] - values[base_b]) * tx
	var b0: float = values[base_c] + (values[base_c + 1] - values[base_c]) * tx
	var b1: float = values[base_d] + (values[base_d + 1] - values[base_d]) * tx
	# z axis
	var c0: float = a0 + (a1 - a0) * tz
	var c1: float = b0 + (b1 - b0) * tz
	# y axis
	return c0 + (c1 - c0) * ty


# ---------------------------------------------------------------------------
# Ores
# ---------------------------------------------------------------------------


const ORE_BANDS: Array = [
	# [block name, min y, max y, veins per chunk, vein size]
	["coal_ore", 6, 110, 9, 12],
	["iron_ore", 5, 72, 7, 8],
	["copper_ore", 20, 84, 6, 9],
	["gold_ore", 4, 34, 3, 6],
	["redstone_ore", 3, 22, 4, 7],
	["lapis_ore", 3, 34, 2, 6],
	["diamond_ore", 3, 16, 1, 5],
	["emerald_ore", 5, 40, 1, 2],
]


func _place_ores(chunk: Chunk, heights: PackedInt32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value) * 6364136223846793005 + chunk.coord.x * 187167 + chunk.coord.y * 96429
	for band in ORE_BANDS:
		var block_id: int = Blocks.id(str(band[0]))
		var min_y: int = int(band[1])
		var max_y: int = int(band[2])
		var veins: int = int(band[3])
		var vein_size: int = int(band[4])
		for _vein in veins:
			var x: int = rng.randi_range(0, SIZE - 1)
			var z: int = rng.randi_range(0, SIZE - 1)
			var surface: int = heights[z * SIZE + x]
			var top: int = mini(max_y, surface - 2)
			if top <= min_y:
				continue
			var y: int = rng.randi_range(min_y, top)
			_scatter_vein(chunk, x, y, z, block_id, vein_size, rng)


func _scatter_vein(chunk: Chunk, x: int, y: int, z: int, block_id: int, size: int,
		rng: RandomNumberGenerator) -> void:
	var placed: int = 0
	var cx: int = x
	var cy: int = y
	var cz: int = z
	while placed < size:
		if Chunk.in_bounds(cx, cy, cz):
			var existing: int = chunk.blocks[Chunk.index(cx, cy, cz)]
			if Blocks.is_opaque(existing) and existing != Blocks.BEDROCK:
				chunk.set_block(cx, cy, cz, block_id)
		placed += 1
		match rng.randi_range(0, 5):
			0:
				cx += 1
			1:
				cx -= 1
			2:
				cy += 1
			3:
				cy -= 1
			4:
				cz += 1
			_:
				cz -= 1


# ---------------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------------


const TREE_DENSITY: Dictionary = {
	BIOME_FOREST: 0.13,
	BIOME_PLAINS: 0.012,
	BIOME_TAIGA: 0.10,
	BIOME_JUNGLE: 0.20,
	BIOME_SNOWY: 0.02,
	BIOME_SWAMP: 0.05,
	BIOME_SAVANNA: 0.02,
	BIOME_MOUNTAINS: 0.015,
	BIOME_DESERT: 0.0,
	BIOME_OCEAN: 0.0,
	BIOME_BEACH: 0.0,
}

const TREE_TYPES: Dictionary = {
	BIOME_FOREST: ["oak", "oak", "oak", "birch"],
	BIOME_PLAINS: ["oak"],
	BIOME_TAIGA: ["spruce", "spruce", "birch"],
	BIOME_JUNGLE: ["jungle", "jungle", "oak"],
	BIOME_SNOWY: ["spruce"],
	BIOME_SWAMP: ["oak"],
	BIOME_SAVANNA: ["oak"],
	BIOME_MOUNTAINS: ["spruce"],
}


func _decorate(chunk: Chunk, heights: PackedInt32Array, biomes: PackedInt32Array) -> void:
	var origin_x: int = chunk.coord.x * SIZE
	var origin_z: int = chunk.coord.y * SIZE
	# Trees are considered for a margin around the chunk so canopies from
	# neighbouring trees still land here.
	for z in range(-3, SIZE + 3):
		for x in range(-3, SIZE + 3):
			var world_x: int = origin_x + x
			var world_z: int = origin_z + z
			var biome: int = biome_at(world_x, world_z)
			var density: float = float(TREE_DENSITY.get(biome, 0.0))
			if density <= 0.0:
				continue
			if float(_hash2(world_x, world_z) % 10000) / 10000.0 >= density:
				continue
			var ground: int = height_at(world_x, world_z)
			if ground <= SEA_LEVEL:
				continue
			var types: Array = TREE_TYPES.get(biome, ["oak"])
			var tree: String = str(types[_hash2(world_x * 3, world_z * 7) % types.size()])
			_place_tree(chunk, world_x, world_z, ground + 1, tree, x, z)
	if origin_x == 0 and origin_z == 0:
		pass
	# ground cover: grass, flowers, cacti, sugar cane, mushrooms, pumpkins
	for z in SIZE:
		for x in SIZE:
			var height: int = heights[z * SIZE + x]
			var biome: int = biomes[z * SIZE + x]
			var world_x: int = origin_x + x
			var world_z: int = origin_z + z
			if height < SEA_LEVEL:
				continue
			var above: int = chunk.get_block(x, height + 1, z)
			if above != Blocks.AIR or chunk.get_block(x, height, z) == Blocks.AIR:
				continue
			var roll: int = _hash3(world_x, height, world_z) % 1000
			match biome:
				BIOME_PLAINS, BIOME_FOREST, BIOME_SAVANNA:
					if roll < 240:
						chunk.set_block(x, height + 1, z, Blocks.id("tall_grass"))
					elif roll < 265:
						chunk.set_block(x, height + 1, z,
							Blocks.id("flower_dandelion" if roll % 2 == 0 else "flower_poppy"))
					elif roll < 272 and biome == BIOME_FOREST:
						chunk.set_block(x, height + 1, z, Blocks.id("mushroom_brown"))
				BIOME_JUNGLE:
					if roll < 380:
						chunk.set_block(x, height + 1, z, Blocks.id("tall_grass"))
					elif roll < 400:
						chunk.set_block(x, height + 1, z, Blocks.id("flower_blue_orchid"))
					elif roll < 408:
						chunk.set_block(x, height + 1, z, Blocks.id("melon"))
				BIOME_TAIGA, BIOME_SNOWY:
					if roll < 120:
						chunk.set_block(x, height + 1, z, Blocks.id("fern"))
					elif roll < 128:
						chunk.set_block(x, height + 1, z, Blocks.id("mushroom_red"))
				BIOME_DESERT:
					if roll < 6:
						chunk.set_block(x, height + 1, z, Blocks.id("cactus"))
						chunk.set_block(x, height + 2, z, Blocks.id("cactus"))
					elif roll < 12:
						chunk.set_block(x, height + 1, z, Blocks.id("dead_bush"))
				BIOME_SWAMP:
					if roll < 200:
						chunk.set_block(x, height + 1, z, Blocks.id("tall_grass"))
					elif roll < 218:
						chunk.set_block(x, height + 1, z, Blocks.id("mushroom_brown"))
					elif roll < 224:
						chunk.set_block(x, height + 1, z, Blocks.id("sugar_cane"))
			# snow layer on cold biomes
			if (biome == BIOME_SNOWY or biome == BIOME_TAIGA) and height > SEA_LEVEL \
					and roll % 5 != 0:
				if chunk.get_block(x, height + 1, z) == Blocks.AIR:
					if height + 1 > SEA_LEVEL:
						chunk.set_block(x, height + 1, z, Blocks.id("snow_layer"))
			if biome == BIOME_MOUNTAINS and height > SEA_LEVEL + 30:
				if chunk.get_block(x, height + 1, z) == Blocks.AIR and _hash3(world_x, height + 9, world_z) % 3 == 0:
					chunk.set_block(x, height + 1, z, Blocks.id("snow_layer"))


func _place_tree(chunk: Chunk, world_x: int, world_z: int, base_y: int, tree: String,
		local_x: int, local_z: int) -> void:
	var trunk_height: int = 4 + _hash2(world_x, world_z) % 3
	var log_block: int = Blocks.id("%s_log" % tree)
	var leaf_block: int = Blocks.id("%s_leaves" % tree)
	var canopy_radius: int = 2 if tree != "jungle" else 2
	var canopy_top: int = base_y + trunk_height
	for y in range(base_y, base_y + trunk_height):
		_write(chunk, local_x, y, local_z, log_block)
	# canopy: two wide layers, then a narrowing cap
	for layer in range(0, canopy_top - base_y + 2):
		var y: int = base_y + trunk_height - 2 + layer
		var radius: int = canopy_radius - maxi(0, layer - 2)
		if tree == "jungle" and layer > 3:
			radius = 1
		if tree == "spruce":
			radius = 1 if layer < 2 else (2 if layer < 4 else maxi(0, 4 - layer))
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and layer < 2:
					continue
				var distance: int = absi(dx) + absi(dz)
				if distance > radius + 1:
					continue
				if distance == radius and (radius > 1 and _hash3(world_x + dx, y, world_z + dz) % 3 == 0):
					continue
				_write_leaf(chunk, local_x + dx, y, local_z + dz, leaf_block)


func _write(chunk: Chunk, x: int, y: int, z: int, block_id: int) -> void:
	if Chunk.in_bounds(x, y, z):
		var existing: int = chunk.blocks[Chunk.index(x, y, z)]
		if existing == Blocks.AIR or Blocks.is_replaceable(existing):
			chunk.set_block(x, y, z, block_id)


func _write_leaf(chunk: Chunk, x: int, y: int, z: int, block_id: int) -> void:
	if Chunk.in_bounds(x, y, z):
		var existing: int = chunk.blocks[Chunk.index(x, y, z)]
		if existing == Blocks.AIR:
			chunk.set_block(x, y, z, block_id)


# ---------------------------------------------------------------------------
# Deterministic hashes (cheap value noise, no FloatNoiseLite needed)
# ---------------------------------------------------------------------------


func _hash2(x: int, z: int) -> int:
	var h: int = seed_value + x * 374761393 + z * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func _hash3(x: int, y: int, z: int) -> int:
	var h: int = seed_value + x * 374761393 + y * 1103515245 + z * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
