class_name LightEngine
extends RefCounted

## Skylight + block light for a voxel world.
##
## Lighting is computed per *region*: a box of voxels (a whole chunk when a
## chunk loads, a small box around a block edit) plus a one-voxel border sampled
## from neighbouring chunks. Working on packed copies keeps the flood fill pure
## integer maths and lets the same code run on a worker thread during chunk
## generation and on the main thread for edits.
##
## Region work is:
##   1. copy blocks from the chunk (and border from neighbours)
##   2. seed skylight from every open column, seed block light from emitters
##   3. seed from the light that already exists just outside the region, so
##      light flows across borders instead of stopping at them
##   4. flood fill both channels (light - 1 per step, sky does not decay when it
##      falls straight down)
##   5. write the light back into the chunk

const MAX_LIGHT: int = 15


class Region:
	extends RefCounted
	var min_v: Vector3i = Vector3i.ZERO
	var max_v: Vector3i = Vector3i.ZERO
	var dims: Vector3i = Vector3i.ZERO     # including the 1-voxel border
	var blocks: PackedByteArray = PackedByteArray()
	var light: PackedByteArray = PackedByteArray()

	func _init() -> void:
		pass

	func setup(minimum: Vector3i, maximum: Vector3i) -> void:
		min_v = minimum
		max_v = maximum
		dims = maximum - minimum + Vector3i(3, 3, 3)
		var total: int = dims.x * dims.y * dims.z
		blocks.resize(total)
		light.resize(total)

	func index(x: int, y: int, z: int) -> int:
		return ((y - min_v.y + 1) * dims.z + (z - min_v.z + 1)) * dims.x + (x - min_v.x + 1)

	func in_region(x: int, y: int, z: int) -> bool:
		return x >= min_v.x and x <= max_v.x and z >= min_v.z and z <= max_v.z \
			and y >= min_v.y and y <= max_v.y

	## Includes the one-voxel border that is sampled from neighbouring chunks.
	func in_bounds(x: int, y: int, z: int) -> bool:
		return x >= min_v.x - 1 and x <= max_v.x + 1 \
			and z >= min_v.z - 1 and z <= max_v.z + 1 \
			and y >= min_v.y - 1 and y <= max_v.y + 1


## Relights a whole chunk (used after generation and when a neighbour loads).
static func relight_chunk(chunk: Chunk, neighbors: Dictionary = {}) -> void:
	var region := Region.new()
	region.setup(Vector3i(0, 0, 0), Vector3i(Chunk.SIZE - 1, Chunk.HEIGHT - 1, Chunk.SIZE - 1))
	_fill_region(region, chunk, neighbors)
	_compute(region)
	_write_back(region, chunk)


## Relights a box around an edit. Returns true when the light changed.
static func relight_box(chunk: Chunk, neighbors: Dictionary, center: Vector3i,
		radius: int = 6) -> void:
	var minimum := Vector3i(
		maxi(0, center.x - radius), 0,
		maxi(0, center.z - radius)
	)
	var maximum := Vector3i(
		mini(Chunk.SIZE - 1, center.x + radius), Chunk.HEIGHT - 1,
		mini(Chunk.SIZE - 1, center.z + radius)
	)
	var region := Region.new()
	region.setup(minimum, maximum)
	_fill_region(region, chunk, neighbors)
	_compute(region)
	_write_back(region, chunk)


# ---------------------------------------------------------------------------
# Region assembly
# ---------------------------------------------------------------------------


static func _fill_region(region: Region, chunk: Chunk, neighbors: Dictionary) -> void:
	var origin := Vector3i(chunk.coord.x * Chunk.SIZE, 0, chunk.coord.y * Chunk.SIZE)
	# Owning chunk
	for y in range(region.min_v.y, region.max_v.y + 1):
		for z in range(region.min_v.z, region.max_v.z + 1):
			for x in range(region.min_v.x, region.max_v.x + 1):
				var i: int = region.index(x, y, z)
				region.blocks[i] = chunk.blocks[Chunk.index(x, y, z)]
				region.light[i] = chunk.light[Chunk.index(x, y, z)]
	# Border from neighbours: only the voxels that fall outside this chunk.
	var east: Chunk = neighbors.get(Vector2i(1, 0))
	var west: Chunk = neighbors.get(Vector2i(-1, 0))
	var south: Chunk = neighbors.get(Vector2i(0, 1))
	var north: Chunk = neighbors.get(Vector2i(0, -1))
	for y in range(region.min_v.y, region.max_v.y + 1):
		for z in range(region.min_v.z, region.max_v.z + 1):
			for x in range(region.min_v.x, region.max_v.x + 1):
				var inside: bool = x >= 0 and x < Chunk.SIZE and z >= 0 and z < Chunk.SIZE
				if inside:
					continue
				var i: int = region.index(x, y, z)
				var local_x: int = posmod(x, Chunk.SIZE)
				var local_z: int = posmod(z, Chunk.SIZE)
				var source: Chunk = null
				if x >= Chunk.SIZE:
					source = east
				elif x < 0:
					source = west
				elif z >= Chunk.SIZE:
					source = south
				elif z < 0:
					source = north
				if source == null:
					region.blocks[i] = Blocks.BEDROCK if y < 0 else Blocks.AIR
					region.light[i] = 0
					continue
				var j: int = Chunk.index(local_x, y, local_z)
				region.blocks[i] = source.blocks[j]
				region.light[i] = source.light[j]
	# Vertical padding
	for z in range(region.min_v.z - 1, region.max_v.z + 2):
		for x in range(region.min_v.x - 1, region.max_v.x + 2):
			if region.in_region(x, -1, z):
				continue
			var i_below: int = region.index(x, -1, z)
			region.blocks[i_below] = Blocks.BEDROCK
			region.light[i_below] = 0
			var i_above: int = region.index(x, Chunk.HEIGHT, z)
			region.blocks[i_above] = Blocks.AIR
			region.light[i_above] = 0xF0


# ---------------------------------------------------------------------------
# Flood fill
# ---------------------------------------------------------------------------


static func _compute(region: Region) -> void:
	var sky_queue := PackedInt32Array()
	var block_queue := PackedInt32Array()
	var dims: Vector3i = region.dims
	var total: int = dims.x * dims.y * dims.z
	# Clear interior light (keep border values as incoming seeds).
	for y in range(region.min_v.y, region.max_v.y + 1):
		for z in range(region.min_v.z, region.max_v.z + 1):
			for x in range(region.min_v.x, region.max_v.x + 1):
				region.light[region.index(x, y, z)] = 0

	# 1. Skylight seeds: straight down from the top of each column.
	for z in range(region.min_v.z - 1, region.max_v.z + 2):
		for x in range(region.min_v.x - 1, region.max_v.x + 2):
			var level: int = 15
			var y: int = Chunk.HEIGHT
			# The row above the world is always full daylight.
			var above_index: int = region.index(x, Chunk.HEIGHT, z)
			region.light[above_index] = (region.light[above_index] & 0x0F) | 0xF0
			sky_queue.append(above_index)
			while y >= region.min_v.y:
				var i: int = region.index(x, y, z)
				var block_id: int = region.blocks[i]
				if Blocks.is_opaque(block_id):
					break
				if Blocks.is_cutout(block_id) or Blocks.is_liquid(block_id):
					level -= 1
					if level <= 0:
						break
				region.light[i] = (region.light[i] & 0x0F) | (level << 4)
				sky_queue.append(i)
				y -= 1

	# 2. Block light seeds from emitters, plus existing border light.
	for y in range(region.min_v.y - 1, region.max_v.y + 2):
		for z in range(region.min_v.z - 1, region.max_v.z + 2):
			for x in range(region.min_v.x - 1, region.max_v.x + 2):
				var i: int = region.index(x, y, z)
				var inside: bool = region.in_region(x, y, z)
				var emission: int = Blocks.light_emission(region.blocks[i])
				if emission > 0:
					region.light[i] = (region.light[i] & 0xF0) | emission
					block_queue.append(i)
				elif not inside:
					var border_block: int = region.light[i] & 0x0F
					if border_block > 1:
						block_queue.append(i)
					var border_sky: int = (region.light[i] >> 4) & 0xF
					if border_sky > 1:
						sky_queue.append(i)

	_flood(region, sky_queue, true)
	_flood(region, block_queue, false)


## Iterative breadth-first flood fill. `sky` selects the channel to propagate.
static func _flood(region: Region, queue: PackedInt32Array, sky: bool) -> void:
	var dims: Vector3i = region.dims
	var dim_xy: int = dims.x * dims.z
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var packed: int = region.light[i]
		var level: int = ((packed >> 4) & 0xF) if sky else (packed & 0xF)
		if level <= 1:
			continue
		# Decode the index back into coordinates.
		var x: int = i % dims.x - 1 + region.min_v.x
		var rest: int = i / dims.x
		var z: int = rest % dims.z - 1 + region.min_v.z
		var y: int = rest / dims.z - 1 + region.min_v.y
		# Six neighbours; -Y keeps full strength when the light came from above.
		var next_level: int = level - 1
		var below_level: int = level if (sky and level == MAX_LIGHT) else level - 1
		for direction in 6:
			var nx: int = x
			var ny: int = y
			var nz: int = z
			var candidate: int = next_level
			match direction:
				0:
					nx += 1
				1:
					nx -= 1
				2:
					ny += 1
				3:
					ny -= 1
					candidate = below_level
				4:
					nz += 1
				_:
					nz -= 1
			if not region.in_bounds(nx, ny, nz):
				continue
			var j: int = region.index(nx, ny, nz)
			var target_block: int = region.blocks[j]
			if Blocks.is_opaque(target_block):
				continue
			var attenuation: int = 0
			if Blocks.is_cutout(target_block) or Blocks.is_liquid(target_block):
				attenuation = 1
			var value: int = candidate - attenuation
			if value <= 0:
				continue
			var target_packed: int = region.light[j]
			var current: int = ((target_packed >> 4) & 0xF) if sky else (target_packed & 0xF)
			if current >= value:
				continue
			region.light[j] = ((value << 4) | (target_packed & 0x0F)) if sky \
				else ((target_packed & 0xF0) | value)
			queue.append(j)


# ---------------------------------------------------------------------------
# Write back
# ---------------------------------------------------------------------------


static func _write_back(region: Region, chunk: Chunk) -> void:
	for y in range(region.min_v.y, region.max_v.y + 1):
		for z in range(region.min_v.z, region.max_v.z + 1):
			for x in range(region.min_v.x, region.max_v.x + 1):
				chunk.light[Chunk.index(x, y, z)] = region.light[region.index(x, y, z)]
	chunk.lighting_done = true
