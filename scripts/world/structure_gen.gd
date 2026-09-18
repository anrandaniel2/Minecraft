class_name StructureGen
extends RefCounted

## Deterministic world structures: villages, dungeons, mineshafts, desert wells,
## ruined huts and mountain boulders.
##
## Structures are placed on hashed grids: a structure's origin is derived from
## the world seed and its grid cell, so every chunk computes the same set of
## structures and simply clips the writes to its own bounds. Nothing is stored
## and nothing has to be generated in order.

const SIZE: int = Chunk.SIZE
const VILLAGE_CELL: int = 160
const NO_VILLAGE: Vector2i = Vector2i(-1000000, -1000000)


static func generate(gen: WorldGen, chunk: Chunk, heights: PackedInt32Array,
		biomes: PackedInt32Array) -> void:
	var origin_x: int = chunk.coord.x * SIZE
	var origin_z: int = chunk.coord.y * SIZE
	var bounds := Rect2i(origin_x, origin_z, SIZE, SIZE)

	_structure_grid(gen, chunk, bounds, heights, VILLAGE_CELL, 1, _try_village)
	_structure_grid(gen, chunk, bounds, heights, 128, 2, _try_dungeon)
	_structure_grid(gen, chunk, bounds, heights, 192, 3, _try_mineshaft)
	_structure_grid(gen, chunk, bounds, heights, 224, 4, _try_desert_well)
	_structure_grid(gen, chunk, bounds, heights, 176, 5, _try_hut)
	_structure_grid(gen, chunk, bounds, heights, 96, 6, _try_boulder)


## Closest village centre to (x, z) within `radius`, or NO_VILLAGE.
##
## Villages are pure functions of the seed, so NPC spawning can look one up
## without keeping any state around (and it agrees with what was built).
static func village_center_near(gen: WorldGen, x: int, z: int, radius: int) -> Vector2i:
	if radius <= 0:
		return NO_VILLAGE
	var cell: int = VILLAGE_CELL
	var min_cell_x: int = int(floor(float(x - radius) / float(cell)))
	var max_cell_x: int = int(floor(float(x + radius) / float(cell)))
	var min_cell_z: int = int(floor(float(z - radius) / float(cell)))
	var max_cell_z: int = int(floor(float(z + radius) / float(cell)))
	var best: Vector2i = NO_VILLAGE
	var best_distance: float = INF
	for cell_x in range(min_cell_x, max_cell_x + 1):
		for cell_z in range(min_cell_z, max_cell_z + 1):
			var hash_value: int = gen._hash3(cell_x * 7919 + 1, 131, cell_z * 104729 + 1)
			if hash_value % 100 >= 65:
				continue
			var jitter_x: int = (hash_value / 100) % (cell / 2)
			var jitter_z: int = (hash_value / 10000) % (cell / 2)
			var origin := Vector2i(cell_x * cell + jitter_x, cell_z * cell + jitter_z)
			var biome: int = gen.biome_at(origin.x, origin.y)
			if not biome in [WorldGen.BIOME_PLAINS, WorldGen.BIOME_SAVANNA,
					WorldGen.BIOME_DESERT, WorldGen.BIOME_FOREST]:
				continue
			if gen.height_at(origin.x, origin.y) <= WorldGen.SEA_LEVEL:
				continue
			var distance: float = Vector2(float(origin.x - x), float(origin.y - z)).length()
			if distance > float(radius) or distance >= best_distance:
				continue
			# Same flatness test the builder uses.
			var lowest: int = gen.height_at(origin.x, origin.y)
			var highest: int = lowest
			for dx in range(-18, 19, 6):
				for dz in range(-18, 19, 6):
					var height: int = gen.height_at(origin.x + dx, origin.y + dz)
					lowest = mini(lowest, height)
					highest = maxi(highest, height)
			if highest - lowest > 7:
				continue
			best_distance = distance
			best = origin
	return best


# ---------------------------------------------------------------------------
# Placement scaffold
# ---------------------------------------------------------------------------


## Visits every grid cell whose structure bounding box could touch this chunk.
static func _structure_grid(gen: WorldGen, chunk: Chunk, bounds: Rect2i,
		heights: PackedInt32Array, cell: int, salt: int, placer: Callable) -> void:
	var reach: int = int(cell * 0.5)
	var min_cell_x: int = int(floor(float(bounds.position.x - reach) / float(cell)))
	var max_cell_x: int = int(floor(float(bounds.end.x + reach) / float(cell)))
	var min_cell_z: int = int(floor(float(bounds.position.y - reach) / float(cell)))
	var max_cell_z: int = int(floor(float(bounds.end.y + reach) / float(cell)))
	for cell_x in range(min_cell_x, max_cell_x + 1):
		for cell_z in range(min_cell_z, max_cell_z + 1):
			var hash_value: int = gen._hash3(cell_x * 7919 + salt, salt * 131, cell_z * 104729 + salt)
			if hash_value % 100 >= 65:
				continue  # ~65% of cells hold a structure
			var jitter_x: int = (hash_value / 100) % (cell / 2)
			var jitter_z: int = (hash_value / 10000) % (cell / 2)
			var origin := Vector2i(cell_x * cell + jitter_x, cell_z * cell + jitter_z)
			placer.call(gen, chunk, origin, heights, hash_value)


# ---------------------------------------------------------------------------
# Villages
# ---------------------------------------------------------------------------


static func _try_village(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	var biome: int = gen.biome_at(origin.x, origin.y)
	if not biome in [WorldGen.BIOME_PLAINS, WorldGen.BIOME_SAVANNA, WorldGen.BIOME_DESERT,
			WorldGen.BIOME_FOREST]:
		return
	var center_y: int = gen.height_at(origin.x, origin.y)
	if center_y <= WorldGen.SEA_LEVEL:
		return
	if not _intersects(chunk, origin.x, origin.y, 42):
		return
	# Check the whole footprint is reasonably flat before building.
	var lowest: int = center_y
	var highest: int = center_y
	for dx in range(-18, 19, 6):
		for dz in range(-18, 19, 6):
			var h: int = gen.height_at(origin.x + dx, origin.y + dz)
			lowest = mini(lowest, h)
			highest = maxi(highest, h)
	if highest - lowest > 7:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash_value
	var desert: bool = biome == WorldGen.BIOME_DESERT
	var planks: int = Blocks.id("sandstone" if desert else "oak_planks")
	var log_block: int = Blocks.id("sandstone" if desert else "oak_log")
	var floor_block: int = Blocks.id("sandstone" if desert else "cobblestone")

	_plaza(gen, chunk, origin, center_y, rng, floor_block)
	# A ring of buildings around the plaza.
	var buildings: int = 5 + int(hash_value % 3)
	for index in buildings:
		var angle: float = TAU * float(index) / float(buildings) + rng.randf_range(-0.25, 0.25)
		var distance: float = rng.randf_range(13.0, 19.0)
		var bx: int = origin.x + int(round(cos(angle) * distance))
		var bz: int = origin.y + int(round(sin(angle) * distance))
		var width: int = rng.randi_range(5, 8)
		var depth: int = rng.randi_range(5, 8)
		_building(gen, chunk, Vector2i(bx, bz), width, depth, rng, planks, log_block,
			floor_block, desert)


static func _plaza(gen: WorldGen, chunk: Chunk, origin: Vector2i, ground: int,
		rng: RandomNumberGenerator, floor_block: int) -> void:
	# Well in the middle, gravel paths radiating out.
	for x in range(-3, 4):
		for z in range(-3, 4):
			if absi(x) == 3 or absi(z) == 3:
				_put(chunk, origin.x + x, ground, origin.y + z, Blocks.id("cobblestone"))
			elif absi(x) <= 1 and absi(z) <= 1:
				_put(chunk, origin.x + x, ground, origin.y + z, Blocks.WATER)
			_clear_column(chunk, origin.x + x, ground + 1, origin.y + z)
	for index in 4:
		var dir := Vector2i(1, 0) if index == 0 else (Vector2i(-1, 0) if index == 1 else
			(Vector2i(0, 1) if index == 2 else Vector2i(0, -1)))
		for step in range(4, 20):
			var path_x: int = origin.x + dir.x * step
			var path_z: int = origin.y + dir.y * step
			var path_y: int = gen.height_at(path_x, path_z)
			if path_y <= WorldGen.SEA_LEVEL:
				break
			_put(chunk, path_x, path_y, path_z, floor_block)
			_clear_column(chunk, path_x, path_y + 1, path_z)
	# lamps
	for corner: Vector2i in [
			Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4)]:
		var lamp_x: int = origin.x + corner.x
		var lamp_z: int = origin.y + corner.y
		var lamp_y: int = gen.height_at(lamp_x, lamp_z)
		_put(chunk, lamp_x, lamp_y, lamp_z, Blocks.id("cobblestone"))
		_put(chunk, lamp_x, lamp_y + 1, lamp_z, Blocks.id("cobblestone"))
		_put(chunk, lamp_x, lamp_y + 2, lamp_z, Blocks.id("torch"), 2)


static func _building(gen: WorldGen, chunk: Chunk, center: Vector2i, width: int, depth: int,
		rng: RandomNumberGenerator, planks: int, log_block: int, floor_block: int,
		desert: bool) -> void:
	var base_y: int = gen.height_at(center.x, center.y)
	if base_y <= WorldGen.SEA_LEVEL:
		return
	var height: int = rng.randi_range(3, 5)
	var half_w: int = width / 2
	var half_d: int = depth / 2
	# Floor + walls
	for x in range(-half_w, half_w + 1):
		for z in range(-half_d, half_d + 1):
			_clear_column(chunk, center.x + x, base_y + 1, center.y + z)
			_put(chunk, center.x + x, base_y, center.y + z, floor_block)
	for level in range(1, height + 1):
		for x in range(-half_w, half_w + 1):
			for z in range(-half_d, half_d + 1):
				var is_wall: bool = absi(x) == half_w or absi(z) == half_d
				if not is_wall:
					continue
				# corners are logs
				if absi(x) == half_w and absi(z) == half_d:
					_put(chunk, center.x + x, base_y + level, center.y + z, log_block)
					continue
				_put(chunk, center.x + x, base_y + level, center.y + z, planks)
	# Door on a random wall
	var door_side: int = rng.randi_range(0, 3)
	var door_x: int = center.x
	var door_z: int = center.y
	match door_side:
		0:
			door_z = center.y - half_d
		1:
			door_z = center.y + half_d
		2:
			door_x = center.x - half_w
		_:
			door_x = center.x + half_w
	_clear_column(chunk, door_x, base_y + 1, door_z)
	_clear_column(chunk, door_x, base_y + 2, door_z)
	# Windows
	for x in range(-half_w + 1, half_w):
		if x % 2 == 0:
			_put(chunk, center.x + x, base_y + 2, center.y - half_d, Blocks.GLASS)
			_put(chunk, center.x + x, base_y + 2, center.y + half_d, Blocks.GLASS)
	for z in range(-half_d + 1, half_d):
		if z % 2 == 0:
			_put(chunk, center.x - half_w, base_y + 2, center.y + z, Blocks.GLASS)
			_put(chunk, center.x + half_w, base_y + 2, center.y + z, Blocks.GLASS)
	# Roof: flat slab of planks, desert gets a stepped sandstone dome
	for x in range(-half_w - 1, half_w + 2):
		for z in range(-half_d - 1, half_d + 2):
			var edge: bool = absi(x) > half_w - 1 or absi(z) > half_d - 1
			_put(chunk, center.x + x, base_y + height + 1, center.y + z, planks)
			if edge and rng.randf() < 0.6:
				_put(chunk, center.x + x, base_y + height + 2, center.y + z, planks)
	if not desert:
		_put(chunk, center.x, base_y + height + 1, center.y, Blocks.id("glowstone"))
	# Interior: torch, chest, crafting table, bed-less bedroom
	_put(chunk, center.x + 1, base_y + 2, center.y + 1, Blocks.TORCH, 2)
	if rng.randf() < 0.7:
		_put(chunk, center.x - 1, base_y + 1, center.y - 1, Blocks.CHEST, 4)
	if rng.randf() < 0.6:
		_put(chunk, center.x + 1, base_y + 1, center.y - 1, Blocks.CRAFTING_TABLE)
	if rng.randf() < 0.5:
		_put(chunk, center.x - 1, base_y + 2, center.y + 1, Blocks.FURNACE, 4)
	if not desert and rng.randf() < 0.4:
		for step in range(1, 3):
			_put(chunk, center.x - half_w - step, base_y + step, center.y - half_d, planks)


# ---------------------------------------------------------------------------
# Dungeons
# ---------------------------------------------------------------------------


static func _try_dungeon(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	if not _intersects(chunk, origin.x, origin.y, 24):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_value
	var room_y: int = rng.randi_range(16, 44)
	if room_y >= gen.height_at(origin.x, origin.y) - 8:
		return
	var width: int = rng.randi_range(6, 10)
	var depth: int = rng.randi_range(6, 10)
	var wall: int = Blocks.id("mossy_cobblestone" if hash_value % 3 == 0 else "cobblestone")
	var height: int = 4
	# Room shell
	for x in range(-width, width + 1):
		for z in range(-depth, depth + 1):
			for y in range(-1, height + 1):
				var is_shell: bool = absi(x) == width or absi(z) == depth or y == -1 or y == height
				var pos_x: int = origin.x + x
				var pos_z: int = origin.y + z
				var pos_y: int = room_y + y
				if is_shell:
					_put(chunk, pos_x, pos_y, pos_z, wall)
				else:
					_put(chunk, pos_x, pos_y, pos_z, Blocks.AIR)
	# Chests and torches
	var chests: int = rng.randi_range(1, 3)
	for index in chests:
		var cx: int = origin.x + rng.randi_range(-width + 1, width - 1)
		var cz: int = origin.y + rng.randi_range(-depth + 1, depth - 1)
		_put(chunk, cx, room_y, cz, Blocks.CHEST, rng.randi_range(0, 3))
	if rng.randf() < 0.6:
		_put(chunk, origin.x + 2, room_y, origin.y + 2, Blocks.id("web"))
	_put(chunk, origin.x, room_y + height - 1, origin.y, Blocks.TORCH, 2)
	_put(chunk, origin.x + width - 1, room_y + height - 1, origin.y - depth + 1, Blocks.TORCH, 2)
	# Entrance shaft up to the surface on some dungeons
	if rng.randf() < 0.4:
		var surface: int = gen.height_at(origin.x, origin.y)
		for y in range(room_y + height, surface):
			_put(chunk, origin.x, y, origin.y, Blocks.AIR)


# ---------------------------------------------------------------------------
# Mineshafts
# ---------------------------------------------------------------------------


static func _try_mineshaft(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_value
	var base_y: int = rng.randi_range(14, 40)
	var along_x: bool = hash_value % 2 == 0
	var length: int = rng.randi_range(40, 96)
	var start: Vector2i = origin
	var direction: int = 1 if hash_value % 4 < 2 else -1
	if along_x:
		start.x = origin.x - length / 2
	else:
		start.y = origin.y - length / 2
	if not _intersects(chunk, origin.x, origin.y, length / 2 + 8):
		return
	# Main corridor
	for step in length:
		var cx: int = start.x + (step * direction if along_x else 0)
		var cz: int = start.y + (0 if along_x else step * direction)
		_corridor_slice(chunk, cx, cz, base_y, along_x, rng)
		# A worn cart track along the corridor floor.
		if step % 5 != 4:
			_put(chunk, cx, base_y + 1, cz, Blocks.RAIL)
		if step % 8 == 0:
			# support beams
			_put(chunk, cx, base_y, cz, Blocks.id("oak_log"))
			_put(chunk, cx, base_y + 3, cz, Blocks.id("oak_log"))
			if step % 16 == 0:
				_put(chunk, cx, base_y + 3, cz - 1, Blocks.TORCH, 2)
			if rng.randf() < 0.12:
				_put(chunk, cx + (1 if along_x else 0), base_y + 1,
					cz + (1 if not along_x else 0), Blocks.CHEST, rng.randi_range(0, 3))
	# A couple of side branches
	for branch in 3:
		var branch_step: int = rng.randi_range(4, length - 4)
		var bx: int = start.x + (branch_step * direction if along_x else 0)
		var bz: int = start.y + (0 if along_x else branch_step * direction)
		var branch_dir: int = 1 if rng.randf() < 0.5 else -1
		var branch_length: int = rng.randi_range(8, 22)
		for step in branch_length:
			var sx: int = bx + (0 if along_x else step * branch_dir)
			var sz: int = bz + (step * branch_dir if along_x else 0)
			_corridor_slice(chunk, sx, sz, base_y, not along_x, rng)


static func _corridor_slice(chunk: Chunk, x: int, z: int, y: int, along_x: bool,
		rng: RandomNumberGenerator) -> void:
	for dy in range(0, 4):
		for side in range(-1, 2):
			var px: int = x + (0 if along_x else side)
			var pz: int = z + (side if along_x else 0)
			if dy == 0:
				_put(chunk, px, y + dy, pz, Blocks.id("oak_planks"))
			else:
				_put(chunk, px, y + dy, pz, Blocks.AIR)
	# occasional cave-in rubble
	if rng.randf() < 0.08:
		_put(chunk, x, y + 3, z, Blocks.id("gravel"))


# ---------------------------------------------------------------------------
# Desert wells, huts, boulders
# ---------------------------------------------------------------------------


static func _try_desert_well(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	if gen.biome_at(origin.x, origin.y) != WorldGen.BIOME_DESERT:
		return
	if not _intersects(chunk, origin.x, origin.y, 8):
		return
	var ground: int = gen.height_at(origin.x, origin.y)
	var sandstone: int = Blocks.id("sandstone")
	for x in range(-2, 3):
		for z in range(-2, 3):
			var is_ring: bool = absi(x) == 2 or absi(z) == 2
			_clear_column(chunk, origin.x + x, ground + 1, origin.y + z)
			if is_ring:
				for level in range(-2, 2):
					_put(chunk, origin.x + x, ground + level, origin.y + z, sandstone)
			else:
				_put(chunk, origin.x + x, ground - 2, origin.y + z, Blocks.WATER)
				_put(chunk, origin.x + x, ground - 1, origin.y + z, Blocks.AIR)


static func _try_hut(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	var biome: int = gen.biome_at(origin.x, origin.y)
	if not biome in [WorldGen.BIOME_SWAMP, WorldGen.BIOME_TAIGA, WorldGen.BIOME_FOREST]:
		return
	if not _intersects(chunk, origin.x, origin.y, 12):
		return
	var ground: int = gen.height_at(origin.x, origin.y)
	if ground <= WorldGen.SEA_LEVEL:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_value
	var planks: int = Blocks.id("spruce_planks" if biome == WorldGen.BIOME_TAIGA else "oak_planks")
	var logs: int = Blocks.id("spruce_log" if biome == WorldGen.BIOME_TAIGA else "oak_log")
	var half: int = 3
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			_clear_column(chunk, origin.x + x, ground + 1, origin.y + z)
			_put(chunk, origin.x + x, ground, origin.y + z, planks)
			var is_wall: bool = absi(x) == half or absi(z) == half
			if not is_wall:
				continue
			# Ruined: skip some wall blocks so huts look abandoned.
			if rng.randf() < 0.22:
				continue
			for y in range(1, 4):
				_put(chunk, origin.x + x, ground + y, origin.y + z,
					logs if (absi(x) == half and absi(z) == half) else planks)
	for x in range(-half - 1, half + 2):
		for z in range(-half - 1, half + 2):
			if rng.randf() < 0.85:
				_put(chunk, origin.x + x, ground + 4, origin.y + z, planks)
	_clear_column(chunk, origin.x, ground + 1, origin.y - half)
	if rng.randf() < 0.7:
		_put(chunk, origin.x + 1, ground + 1, origin.y + 1, Blocks.CHEST, 0)
	if rng.randf() < 0.5:
		_put(chunk, origin.x - 1, ground + 2, origin.y - 1, Blocks.id("web"))


static func _try_boulder(gen: WorldGen, chunk: Chunk, origin: Vector2i,
		heights: PackedInt32Array, hash_value: int) -> void:
	var biome: int = gen.biome_at(origin.x, origin.y)
	if not biome in [WorldGen.BIOME_MOUNTAINS, WorldGen.BIOME_TAIGA, WorldGen.BIOME_SNOWY]:
		return
	if not _intersects(chunk, origin.x, origin.y, 6):
		return
	var ground: int = gen.height_at(origin.x, origin.y)
	var stone: int = Blocks.id("stone")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_value
	var radius: int = rng.randi_range(2, 4)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			for dy in range(0, radius + 1):
				if dx * dx + dy * dy + dz * dz > radius * radius + 1:
					continue
				_put(chunk, origin.x + dx, ground + dy, origin.y + dz, stone)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


static func _intersects(chunk: Chunk, x: int, z: int, reach: int) -> bool:
	var origin_x: int = chunk.coord.x * SIZE
	var origin_z: int = chunk.coord.y * SIZE
	return x + reach >= origin_x and x - reach < origin_x + SIZE \
		and z + reach >= origin_z and z - reach < origin_z + SIZE


static func _put(chunk: Chunk, world_x: int, y: int, world_z: int, block_id: int,
		block_meta: int = 0) -> void:
	var local_x: int = world_x - chunk.coord.x * SIZE
	var local_z: int = world_z - chunk.coord.y * SIZE
	if local_x < 0 or local_x >= SIZE or local_z < 0 or local_z >= SIZE:
		return
	if y < 0 or y >= Chunk.HEIGHT:
		return
	chunk.set_block(local_x, y, local_z, block_id, block_meta)


static func _clear_column(chunk: Chunk, world_x: int, from_y: int, world_z: int,
		to_y: int = -1) -> void:
	var local_x: int = world_x - chunk.coord.x * SIZE
	var local_z: int = world_z - chunk.coord.y * SIZE
	if local_x < 0 or local_x >= SIZE or local_z < 0 or local_z >= SIZE:
		return
	var top: int = to_y if to_y >= 0 else from_y + 4
	for y in range(maxi(0, from_y), mini(Chunk.HEIGHT, top + 1)):
		chunk.set_block(local_x, y, local_z, Blocks.AIR)
