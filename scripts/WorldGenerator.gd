extends RefCounted
class_name WorldGenerator
# Port of src/world/WorldGenerator.cpp + src/utils/PerlinNoise.cpp
# Original: net.minecraft.world.WorldGenerator (Java) -> WASM -> C++ -> GDScript

var seed: int = 1337
var perlin: FastNoiseLite

func _init():
	perlin = FastNoiseLite.new()
	perlin.seed = seed
	perlin.noise_type = FastNoiseLite.TYPE_PERLIN
	perlin.frequency = 0.02

func get_height(x: int, z: int) -> int:
	# Same as original Perlin noise terrain
	var h = perlin.get_noise_2d(x, z) * 20 + 64
	# Add second octave like original
	perlin.frequency = 0.05
	h += perlin.get_noise_2d(x, z) * 5
	perlin.frequency = 0.02
	return int(h)

func get_biome(x: int, z: int) -> String:
	# Biomes from original 26.2: Plains, Desert, Snow, Cherry Blossom
	var temp = perlin.get_noise_2d(x * 0.01, z * 0.01)
	if temp > 0.5:
		return "Desert"
	elif temp < -0.5:
		return "Snow"
	elif temp > 0.3:
		return "Cherry"
	else:
		return "Plains"

func generate_chunk(cx: int, cz: int) -> Dictionary:
	# Returns block data for chunk - replicates WorldGenerator::generateChunk
	var blocks = {}
	for x in range(16):
		for z in range(16):
			var world_x = cx * 16 + x
			var world_z = cz * 16 + z
			var height = get_height(world_x, world_z)
			var biome = get_biome(world_x, world_z)
			for y in range(height):
				var block_type = "stone"
				if y == height - 1:
					if biome == "Desert":
						block_type = "sand"
					elif biome == "Snow":
						block_type = "snow"
					elif biome == "Cherry":
						block_type = "grass_cherry"
					else:
						block_type = "grass"
				elif y >= height - 4:
					block_type = "dirt"
				blocks[Vector3i(x, y, z)] = block_type
	return blocks
