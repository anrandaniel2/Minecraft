class_name Chunk
extends RefCounted

## One 16 x 128 x 16 column of voxels.
##
## Storage is flat byte arrays so a chunk is cheap to allocate, cheap to hand to
## a worker thread, and trivial to serialise:
##   blocks  one byte per voxel (block id, see Blocks)
##   meta    orientation + state bits (see Blocks.header docs)
##   light   high nibble = skylight, low nibble = block light
##
## `generate()` runs on a worker thread and only touches its own arrays, so it
## never races with the main thread; the done flag is the handshake.

const SIZE: int = 16
const HEIGHT: int = 128
const VOLUME: int = SIZE * SIZE * HEIGHT

var coord: Vector2i = Vector2i.ZERO
var blocks: PackedByteArray = PackedByteArray()
var meta: PackedByteArray = PackedByteArray()
var light: PackedByteArray = PackedByteArray()

var dirty: bool = true            # mesh needs rebuilding
var lighting_done: bool = false
var generated: bool = false
var has_collision: bool = false
var has_water: bool = false

# Player edits applied on top of generated terrain (kept for saving).
var edits: Dictionary = {}        # local index -> block id


func _init(chunk_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = chunk_coord
	blocks.resize(VOLUME)
	meta.resize(VOLUME)
	light.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x


static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < HEIGHT and z >= 0 and z < SIZE


func get_block(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return Blocks.AIR
	return blocks[index(x, y, z)]


func get_meta(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return meta[index(x, y, z)]


func set_block(x: int, y: int, z: int, block_id: int, block_meta: int = 0) -> void:
	if not in_bounds(x, y, z):
		return
	var i: int = index(x, y, z)
	blocks[i] = block_id
	meta[i] = block_meta
	if block_id != Blocks.AIR:
		if Blocks.is_liquid(block_id):
			has_water = true


func set_light(x: int, y: int, z: int, sky: int, block_light: int) -> void:
	if not in_bounds(x, y, z):
		return
	light[index(x, y, z)] = ((sky & 0xF) << 4) | (block_light & 0xF)


func get_sky_light(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 15
	return (light[index(x, y, z)] >> 4) & 0xF


func get_block_light(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return light[index(x, y, z)] & 0xF


## Highest non-air block in a column (-1 when the column is empty).
func column_height(x: int, z: int) -> int:
	for y in range(HEIGHT - 1, -1, -1):
		if blocks[index(x, y, z)] != Blocks.AIR:
			return y
	return -1


## Fast path used by the terrain generator: writes a run of blocks in one column.
func set_column(x: int, z: int, from_y: int, to_y: int, block_id: int,
		block_meta: int = 0) -> void:
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return
	var start: int = maxi(0, from_y)
	var end: int = mini(HEIGHT - 1, to_y)
	for y in range(start, end + 1):
		var i: int = index(x, y, z)
		blocks[i] = block_id
		meta[i] = block_meta
	if block_id != Blocks.AIR and Blocks.is_liquid(block_id):
		has_water = true


func count_non_air() -> int:
	var total: int = 0
	for i in blocks.size():
		if blocks[i] != Blocks.AIR:
			total += 1
	return total


## A cheap content hash, used by tests to prove terrain is deterministic.
func content_hash() -> int:
	return hash(blocks) ^ hash(meta)
