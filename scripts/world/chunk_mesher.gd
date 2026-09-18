class_name ChunkMesher
extends RefCounted

## Turns a Chunk (plus its four horizontal neighbours) into render meshes.
##
## Design notes
## ------------
## * Greedy meshing. For each of the six face directions the chunk is sliced and
##   a mask of visible faces is built; faces that agree on block type, atlas
##   tile and all four corner light/AO values merge into one big quad. Terrain
##   therefore costs a few hundred triangles per chunk instead of tens of
##   thousands.
## * Neighbour chunk data is copied into a 1-voxel padded buffer first, so the
##   inner loops are pure integer maths on packed arrays - no dictionary
##   lookups and no chunk-boundary branches in the hot path.
## * Light is baked per vertex as two numbers (skylight, block light) in CUSTOM1
##   and combined with the current time of day in the shader, so the day/night
##   cycle never rebuilds a mesh.
## * Ambient occlusion per corner comes from the three neighbouring voxels and
##   is folded into the vertex colour, which is what gives voxel terrain its
##   soft contact shadows.
## * Materials are double sided (see terrain.gdshader): back faces are rejected
##   by depth for free, and it removes a whole class of winding bugs.
##
## Mesh data is returned as plain packed arrays so it can be produced on a
## worker thread and turned into ArrayMesh resources on the main thread.

const SIZE: int = Chunk.SIZE
const HEIGHT: int = Chunk.HEIGHT
const PAD_W: int = SIZE + 2
const PAD_H: int = HEIGHT + 2

const MAT_SOLID: int = 0     # opaque terrain
const MAT_CUTOUT: int = 1    # plants, leaves, glass (alpha tested)
const MAT_WATER: int = 2     # translucent, gentle wave animation

# Fixed per-face shading, the classic voxel look.
const FACE_TINT: PackedFloat32Array = [0.86, 0.86, 1.0, 0.60, 0.80, 0.80]

# Face order: +X, -X, +Y, -Y, +Z, -Z.
const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
# Per face: normal axis, and the two in-plane axes used for masking (u, v).
const FACE_AXES: Array[Vector3i] = [
	Vector3i(0, 2, 1), Vector3i(0, 2, 1),
	Vector3i(1, 0, 2), Vector3i(1, 0, 2),
	Vector3i(2, 0, 1), Vector3i(2, 0, 1),
]


class MeshBuilder:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var tile_origins := PackedVector2Array()   # CUSTOM0: atlas tile origin (in tiles)
	var light_uv := PackedVector2Array()       # CUSTOM1: (skylight, block light) 0..1
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return indices.is_empty()


class MeshResult:
	extends RefCounted
	var surfaces: Array = []              # [solid, cutout, water] MeshBuilder
	var collision_vertices := PackedVector3Array()
	var collision_indices := PackedInt32Array()
	var has_collision: bool = false
	var has_water: bool = false
	var triangle_count: int = 0


var _blocks := PackedByteArray()
var _meta := PackedByteArray()
var _light := PackedByteArray()
var _neighbors: Dictionary = {}
var _result: MeshResult
var _solid: MeshBuilder
var _cutout: MeshBuilder
var _water: MeshBuilder
var _atlas_cols: int = 16


static func build(chunk: Chunk, neighbors: Dictionary = {}) -> MeshResult:
	var mesher := ChunkMesher.new(neighbors)
	return mesher.build_chunk(chunk)


func _init(neighbor_chunks: Dictionary = {}) -> void:
	_blocks.resize(PAD_W * PAD_H * PAD_W)
	_meta.resize(PAD_W * PAD_H * PAD_W)
	_light.resize(PAD_W * PAD_H * PAD_W)
	_neighbors = neighbor_chunks
	_atlas_cols = Blocks.atlas_cols


static func pad_index(x: int, y: int, z: int) -> int:
	return ((y + 1) * PAD_W + (z + 1)) * PAD_W + (x + 1)


func block_at(x: int, y: int, z: int) -> int:
	if y < -1 or y > HEIGHT:
		return Blocks.AIR
	return _blocks[pad_index(x, y, z)]


func meta_at(x: int, y: int, z: int) -> int:
	if y < -1 or y > HEIGHT:
		return 0
	return _meta[pad_index(x, y, z)]


func sky_at(x: int, y: int, z: int) -> int:
	if y < -1:
		return 0
	if y > HEIGHT:
		return 15
	return (_light[pad_index(x, y, z)] >> 4) & 0xF


func block_light_at(x: int, y: int, z: int) -> int:
	if y < -1 or y > HEIGHT:
		return 0
	return _light[pad_index(x, y, z)] & 0xF


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


func build_chunk(chunk: Chunk) -> MeshResult:
	_result = MeshResult.new()
	_solid = MeshBuilder.new()
	_cutout = MeshBuilder.new()
	_water = MeshBuilder.new()
	_fill_padded(chunk)
	_emit_greedy_faces()
	_emit_special_shapes(chunk)
	_emit_liquids(chunk)
	_result.surfaces = [_solid, _cutout, _water]
	_result.has_collision = not _result.collision_indices.is_empty()
	_result.has_water = not _water.is_empty()
	_result.triangle_count = (_solid.indices.size() + _cutout.indices.size() + _water.indices.size()) / 3
	return _result


# ---------------------------------------------------------------------------
# Padded copy of the chunk + its neighbours
# ---------------------------------------------------------------------------


func _fill_padded(chunk: Chunk) -> void:
	for y in HEIGHT:
		for z in SIZE:
			var src_row: int = (y * SIZE + z) * SIZE
			var dst_row: int = pad_index(0, y, z)
			for x in SIZE:
				_blocks[dst_row + x] = chunk.blocks[src_row + x]
				_meta[dst_row + x] = chunk.meta[src_row + x]
				_light[dst_row + x] = chunk.light[src_row + x]
	# Copy only the facing slice from each neighbour.
	var east: Chunk = _neighbors.get(Vector2i(1, 0))
	if east != null:
		for y in HEIGHT:
			for z in SIZE:
				var i: int = Chunk.index(0, y, z)
				var d: int = pad_index(SIZE, y, z)
				_blocks[d] = east.blocks[i]
				_meta[d] = east.meta[i]
				_light[d] = east.light[i]
	var west: Chunk = _neighbors.get(Vector2i(-1, 0))
	if west != null:
		for y in HEIGHT:
			for z in SIZE:
				var i: int = Chunk.index(SIZE - 1, y, z)
				var d: int = pad_index(-1, y, z)
				_blocks[d] = west.blocks[i]
				_meta[d] = west.meta[i]
				_light[d] = west.light[i]
	var south: Chunk = _neighbors.get(Vector2i(0, 1))
	if south != null:
		for y in HEIGHT:
			for x in SIZE:
				var i: int = Chunk.index(x, y, 0)
				var d: int = pad_index(x, y, SIZE)
				_blocks[d] = south.blocks[i]
				_meta[d] = south.meta[i]
				_light[d] = south.light[i]
	var north: Chunk = _neighbors.get(Vector2i(0, -1))
	if north != null:
		for y in HEIGHT:
			for x in SIZE:
				var i: int = Chunk.index(x, y, SIZE - 1)
				var d: int = pad_index(x, y, -1)
				_blocks[d] = north.blocks[i]
				_meta[d] = north.meta[i]
				_light[d] = north.light[i]
	# Vertical padding: solid below (hides bottom faces), open sky above.
	for z in range(-1, SIZE + 1):
		for x in range(-1, SIZE + 1):
			_blocks[pad_index(x, -1, z)] = Blocks.BEDROCK
			_blocks[pad_index(x, HEIGHT, z)] = Blocks.AIR
			_light[pad_index(x, HEIGHT, z)] = 0xF0


# ---------------------------------------------------------------------------
# Greedy meshing
# ---------------------------------------------------------------------------


func _emit_greedy_faces() -> void:
	var dims := [SIZE, HEIGHT, SIZE]
	for face in 6:
		var axes: Vector3i = FACE_AXES[face]
		var axis: int = axes.x
		var u_axis: int = axes.y
		var v_axis: int = axes.z
		var normal: Vector3i = FACE_NORMALS[face]
		var plane_offset: int = 1 if normal.x + normal.y + normal.z > 0 else 0
		var u_count: int = dims[u_axis]
		var v_count: int = dims[v_axis]
		for slice in dims[axis]:
			var mask := PackedInt32Array()
			var mask_keys := PackedInt32Array()
			var mask_light := PackedInt32Array()
			mask.resize(u_count * v_count)
			mask_keys.resize(u_count * v_count)
			mask_light.resize(u_count * v_count)
			var any: bool = false
			for v in v_count:
				var pos := Vector3i.ZERO
				pos[axis] = slice
				pos[v_axis] = v
				for u in u_count:
					pos[u_axis] = u
					var block_id: int = block_at(pos.x, pos.y, pos.z)
					if block_id == Blocks.AIR:
						continue
					if Blocks.shape(block_id) != Blocks.SHAPE_CUBE \
							and Blocks.shape(block_id) != Blocks.SHAPE_FARMLAND:
						continue
					var neighbour: int = block_at(pos.x + normal.x, pos.y + normal.y, pos.z + normal.z)
					if _hides(block_id, neighbour):
						continue
					var index: int = v * u_count + u
					var light_key: int = _corner_light_key(pos, face)
					mask[index] = block_id + 1
					mask_keys[index] = _tile_key(block_id, face, meta_at(pos.x, pos.y, pos.z))
					mask_light[index] = light_key
					any = true
			if not any:
				continue
			_greedy_emit(mask, mask_keys, mask_light, u_count, v_count, face, axes, slice,
				plane_offset)


func _tile_key(block_id: int, face: int, block_meta: int) -> int:
	var cell: Vector2i = Blocks.face_tile(block_id, face, block_meta)
	if cell.x < 0:
		return -1
	return cell.y * _atlas_cols + cell.x


## Packs (sky, block light, AO) for all four corners into one int so only
## identically shaded faces merge. 10 bits per corner.
func _corner_light_key(pos: Vector3i, face: int) -> int:
	var key: int = 0
	var axes: Vector3i = FACE_AXES[face]
	for corner_index in 4:
		var du: int = -1 if corner_index in [0, 3] else 1
		var dv: int = -1 if corner_index < 2 else 1
		var packed: int = _sample_corner(pos, face, axes, du, dv)
		key = (key << 10) | packed
	return key


func _sample_corner(pos: Vector3i, face: int, axes: Vector3i, du: int, dv: int) -> int:
	var normal: Vector3i = FACE_NORMALS[face]
	var nx: int = pos.x + normal.x
	var ny: int = pos.y + normal.y
	var nz: int = pos.z + normal.z
	var u_axis: int = axes.y
	var v_axis: int = axes.z
	var side_a := Vector3i(nx, ny, nz)
	side_a[u_axis] += du
	var side_b := Vector3i(nx, ny, nz)
	side_b[v_axis] += dv
	var corner := Vector3i(nx, ny, nz)
	corner[u_axis] += du
	corner[v_axis] += dv
	var solid_a: bool = Blocks.is_opaque(block_at(side_a.x, side_a.y, side_a.z))
	var solid_b: bool = Blocks.is_opaque(block_at(side_b.x, side_b.y, side_b.z))
	var solid_c: bool = Blocks.is_opaque(block_at(corner.x, corner.y, corner.z))
	var occlusion: int = 3
	if solid_a:
		occlusion -= 1
	if solid_b:
		occlusion -= 1
	if not (solid_a and solid_b) and solid_c:
		occlusion -= 1
	occlusion = clampi(occlusion, 0, 3)
	var sky: int = sky_at(nx, ny, nz)
	var block_light: int = block_light_at(nx, ny, nz)
	return (sky & 0xF) | ((block_light & 0xF) << 4) | ((occlusion & 0x3) << 8)


func _greedy_emit(mask: PackedInt32Array, mask_keys: PackedInt32Array,
		mask_light: PackedInt32Array, u_count: int, v_count: int, face: int,
		axes: Vector3i, slice: int, plane_offset: int) -> void:
	var u: int = 0
	while u < u_count:
		var v: int = 0
		while v < v_count:
			var index: int = v * u_count + u
			var block_entry: int = mask[index]
			if block_entry == 0:
				v += 1
				continue
			var tile_key: int = mask_keys[index]
			var light_key: int = mask_light[index]
			var height: int = 1
			while v + height < v_count:
				var next: int = (v + height) * u_count + u
				if mask[next] != block_entry or mask_keys[next] != tile_key \
						or mask_light[next] != light_key:
					break
				height += 1
			var width: int = 1
			while u + width < u_count:
				var ok: bool = true
				for check in height:
					var next: int = (v + check) * u_count + u + width
					if mask[next] != block_entry or mask_keys[next] != tile_key \
							or mask_light[next] != light_key:
						ok = false
						break
				if not ok:
					break
				width += 1
			_emit_quad(block_entry - 1, face, axes, slice, plane_offset, u, v, width, height,
				light_key)
			for clear_v in range(v, v + height):
				for clear_u in range(u, u + width):
					mask[clear_v * u_count + clear_u] = 0
			v += height
		u += 1


## Emits one quad. Corner order is (0,0) (1,0) (1,1) (0,1) in plane space and
## UVs run 0..width / 0..height so merged quads tile the texture seamlessly.
func _emit_quad(block_id: int, face: int, axes: Vector3i, slice: int, plane_offset: int,
		u: int, v: int, width: int, height: int, light_key: int) -> void:
	var cell: Vector2i = Blocks.face_tile(block_id, face, 0)
	if cell.x < 0:
		return
	var builder: MeshBuilder = _solid
	if Blocks.is_cutout(block_id):
		builder = _cutout
	var axis: int = axes.x
	var u_axis: int = axes.y
	var v_axis: int = axes.z
	var top_surface: float = 0.9375 if Blocks.shape(block_id) == Blocks.SHAPE_FARMLAND else 1.0
	var base_index: int = builder.vertices.size()
	var normal: Vector3i = FACE_NORMALS[face]
	var tint: float = FACE_TINT[face]
	var tile_origin := Vector2(float(cell.x), float(cell.y))
	var corner_uv := [Vector2(0.0, float(height)), Vector2(float(width), float(height)),
		Vector2(float(width), 0.0), Vector2(0.0, 0.0)]
	var collision_corners: Array[Vector3] = []
	for corner_index in 4:
		var cu: float = 0.0 if corner_index in [0, 3] else float(width)
		var cv: float = 0.0 if corner_index < 2 else float(height)
		var coord := Vector3i.ZERO
		coord[axis] = slice + plane_offset
		coord[u_axis] = u + int(cu)
		coord[v_axis] = v + int(cv)
		var point := Vector3(float(coord.x), float(coord.y), float(coord.z))
		if face == 2:
			point.y += top_surface - 1.0
		collision_corners.append(point)
		var packed: int = (light_key >> ((3 - corner_index) * 10)) & 0x3FF
		var sky: int = packed & 0xF
		var block_light: int = (packed >> 4) & 0xF
		var occlusion: int = (packed >> 8) & 0x3
		var ao: float = 0.60 + 0.40 * (float(occlusion) / 3.0)
		builder.vertices.append(point)
		builder.normals.append(Vector3(float(normal.x), float(normal.y), float(normal.z)))
		builder.colors.append(Color(tint * ao, tint * ao, tint * ao, 1.0))
		builder.uvs.append(corner_uv[corner_index])
		builder.tile_origins.append(tile_origin)
		builder.light_uv.append(Vector2(float(sky) / 15.0, float(block_light) / 15.0))
	builder.indices.append_array([base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3])
	if Blocks.solid[block_id] == 1:
		_emit_collision(collision_corners)


func _emit_collision(positions: Array) -> void:
	var base_index: int = _result.collision_vertices.size()
	for point in positions:
		_result.collision_vertices.append(point)
	_result.collision_indices.append_array([base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3])


## True when `neighbour` hides the face of `block_id` that touches it.
func _hides(block_id: int, neighbour: int) -> bool:
	if neighbour == Blocks.AIR or not Blocks.is_opaque(neighbour):
		return false
	if Blocks.is_liquid(neighbour):
		return false
	if neighbour == block_id and Blocks.is_cutout(block_id):
		return true
	return true


# ---------------------------------------------------------------------------
# Special shapes
# ---------------------------------------------------------------------------


func _emit_special_shapes(chunk: Chunk) -> void:
	for y in HEIGHT:
		for z in SIZE:
			for x in SIZE:
				var i: int = Chunk.index(x, y, z)
				var block_id: int = chunk.blocks[i]
				if block_id == Blocks.AIR:
					continue
				match Blocks.shape(block_id):
					Blocks.SHAPE_CROSS:
						_emit_cross(x, y, z, block_id)
					Blocks.SHAPE_TORCH:
						_emit_torch(x, y, z, block_id)
					Blocks.SHAPE_LAYER:
						_emit_box(x, y, z, block_id, chunk.meta[i], 0.0, 0.125)
					Blocks.SHAPE_SLAB:
						_emit_box(x, y, z, block_id, chunk.meta[i], 0.0, 0.5)
					Blocks.SHAPE_LADDER:
						_emit_ladder(x, y, z, block_id, chunk.meta[i])
					_:
						pass


func _emit_cross(x: int, y: int, z: int, block_id: int) -> void:
	var cell: Vector2i = Blocks.face_tile(block_id, 0, 0)
	if cell.x < 0:
		return
	var light := Vector2(float(sky_at(x, y, z)) / 15.0, float(block_light_at(x, y, z)) / 15.0)
	var tile_origin := Vector2(float(cell.x), float(cell.y))
	var jitter: float = float((x * 7 + z * 13) % 5) * 0.02
	var builder: MeshBuilder = _cutout
	for orientation in 2:
		var base_index: int = builder.vertices.size()
		var corners: Array[Vector3] = []
		if orientation == 0:
			corners = [
				Vector3(x + 0.06 + jitter, y, z + 0.06 + jitter),
				Vector3(x + 0.94 - jitter, y, z + 0.94 - jitter),
				Vector3(x + 0.94 - jitter, y + 1.0, z + 0.94 - jitter),
				Vector3(x + 0.06 + jitter, y + 1.0, z + 0.06 + jitter),
			]
		else:
			corners = [
				Vector3(x + 0.94 - jitter, y, z + 0.06 + jitter),
				Vector3(x + 0.06 + jitter, y, z + 0.94 - jitter),
				Vector3(x + 0.06 + jitter, y + 1.0, z + 0.94 - jitter),
				Vector3(x + 0.94 - jitter, y + 1.0, z + 0.06 + jitter),
			]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for index in 4:
			builder.vertices.append(corners[index])
			builder.normals.append(Vector3(0, 1, 0))
			builder.colors.append(Color(1, 1, 1, 1))
			builder.uvs.append(uvs[index])
			builder.tile_origins.append(tile_origin)
			builder.light_uv.append(light)
		builder.indices.append_array([base_index, base_index + 1, base_index + 2,
			base_index, base_index + 2, base_index + 3])


func _emit_torch(x: int, y: int, z: int, block_id: int) -> void:
	var cell: Vector2i = Blocks.face_tile(block_id, 0, 0)
	if cell.x < 0:
		return
	var light := Vector2(float(sky_at(x, y, z)) / 15.0, 1.0)
	var tile_origin := Vector2(float(cell.x), float(cell.y))
	var builder: MeshBuilder = _cutout
	var half: float = 0.075
	var bottom: float = 0.55
	var top: float = 1.0
	var cx: float = float(x) + 0.5
	var cz: float = float(z) + 0.5
	for orientation in 2:
		var base_index: int = builder.vertices.size()
		var dx: float = half if orientation == 0 else 0.0
		var dz: float = 0.0 if orientation == 0 else half
		var corners: Array[Vector3] = [
			Vector3(cx - dx, float(y) + bottom, cz - dz),
			Vector3(cx + dx, float(y) + bottom, cz + dz),
			Vector3(cx + dx, float(y) + top, cz + dz),
			Vector3(cx - dx, float(y) + top, cz - dz),
		]
		var uvs := [Vector2(0.35, 1.0), Vector2(0.65, 1.0), Vector2(0.65, 0.0), Vector2(0.35, 0.0)]
		for index in 4:
			builder.vertices.append(corners[index])
			builder.normals.append(Vector3(0, 1, 0))
			builder.colors.append(Color(1.3, 1.28, 1.15, 1.0))
			builder.uvs.append(uvs[index])
			builder.tile_origins.append(tile_origin)
			builder.light_uv.append(light)
		builder.indices.append_array([base_index, base_index + 1, base_index + 2,
			base_index, base_index + 2, base_index + 3])


## Bottom-anchored partial cubes: slabs (0..0.5) and snow/plates (0..0.125).
func _emit_box(x: int, y: int, z: int, block_id: int, block_meta: int, bottom: float,
		top: float) -> void:
	var y0: float = float(y) + bottom
	var y1: float = float(y) + top
	var x0: float = float(x)
	var x1: float = float(x) + 1.0
	var z0: float = float(z)
	var z1: float = float(z) + 1.0
	for face in 6:
		var normal: Vector3i = FACE_NORMALS[face]
		var neighbour: int = block_at(x + normal.x, y + normal.y, z + normal.z)
		match face:
			2:
				if Blocks.is_opaque(neighbour) and Blocks.shape(neighbour) == Blocks.SHAPE_CUBE:
					continue
			3:
				if Blocks.is_opaque(neighbour) and Blocks.shape(neighbour) == Blocks.SHAPE_CUBE:
					continue
			_:
				if Blocks.is_opaque(neighbour):
					continue
		var cell: Vector2i = Blocks.face_tile(block_id, face, block_meta)
		if cell.x < 0:
			continue
		var sky: float = float(sky_at(x + normal.x, y + normal.y, z + normal.z)) / 15.0
		var block_light: float = float(block_light_at(x + normal.x, y + normal.y,
			z + normal.z)) / 15.0
		var builder: MeshBuilder = _cutout if Blocks.is_cutout(block_id) else _solid
		var base_index: int = builder.vertices.size()
		var corners: Array[Vector3] = []
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		match face:
			0:
				corners = [Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0),
					Vector3(x1, y1, z1)]
			1:
				corners = [Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1),
					Vector3(x0, y1, z0)]
			2:
				corners = [Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1),
					Vector3(x0, y1, z1)]
				uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			3:
				corners = [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0),
					Vector3(x0, y0, z0)]
				uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			4:
				corners = [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1),
					Vector3(x0, y1, z1)]
			_:
				corners = [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0),
					Vector3(x1, y1, z0)]
		var collides: bool = Blocks.solid[block_id] == 1
		var tint: float = FACE_TINT[face]
		for index in 4:
			builder.vertices.append(corners[index])
			builder.normals.append(Vector3(normal.x, normal.y, normal.z))
			builder.colors.append(Color(tint, tint, tint, 1.0))
			builder.uvs.append(uvs[index])
			builder.tile_origins.append(Vector2(float(cell.x), float(cell.y)))
			builder.light_uv.append(Vector2(sky, block_light))
		builder.indices.append_array([base_index, base_index + 1, base_index + 2,
			base_index, base_index + 2, base_index + 3])
		if collides:
			_emit_collision(corners)


func _emit_ladder(x: int, y: int, z: int, block_id: int, block_meta: int) -> void:
	var cell: Vector2i = Blocks.face_tile(block_id, 0, 0)
	if cell.x < 0:
		return
	var builder: MeshBuilder = _cutout
	var base_index: int = builder.vertices.size()
	var offset: float = 0.06
	var x0: float = float(x)
	var x1: float = float(x) + 1.0
	var z0: float = float(z)
	var z1: float = float(z) + 1.0
	var y0: float = float(y)
	var y1: float = float(y) + 1.0
	var corners: Array[Vector3] = []
	var normal := Vector3i.ZERO
	match block_meta & 0x7:
		0:
			corners = [Vector3(x1 - offset, y0, z0), Vector3(x1 - offset, y0, z1),
				Vector3(x1 - offset, y1, z1), Vector3(x1 - offset, y1, z0)]
			normal = Vector3i(-1, 0, 0)
		1:
			corners = [Vector3(x0 + offset, y0, z1), Vector3(x0 + offset, y0, z0),
				Vector3(x0 + offset, y1, z0), Vector3(x0 + offset, y1, z1)]
			normal = Vector3i(1, 0, 0)
		2:
			corners = [Vector3(x1, y0, z1 - offset), Vector3(x0, y0, z1 - offset),
				Vector3(x0, y1, z1 - offset), Vector3(x1, y1, z1 - offset)]
			normal = Vector3i(0, 0, -1)
		_:
			corners = [Vector3(x0, y0, z0 + offset), Vector3(x1, y0, z0 + offset),
				Vector3(x1, y1, z0 + offset), Vector3(x0, y1, z0 + offset)]
			normal = Vector3i(0, 0, 1)
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var sky: float = float(sky_at(x, y, z)) / 15.0
	var block_light: float = float(block_light_at(x, y, z)) / 15.0
	for index in 4:
		builder.vertices.append(corners[index])
		builder.normals.append(Vector3(normal.x, normal.y, normal.z))
		builder.colors.append(Color(0.95, 0.95, 0.95, 1.0))
		builder.uvs.append(uvs[index])
		builder.tile_origins.append(Vector2(float(cell.x), float(cell.y)))
		builder.light_uv.append(Vector2(sky, block_light))
	builder.indices.append_array([base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3])


## Water and lava surfaces. Level (meta 0..7, 7 = full) lowers the surface.
func _emit_liquids(chunk: Chunk) -> void:
	var builder: MeshBuilder = _water
	for y in HEIGHT:
		for z in SIZE:
			for x in SIZE:
				var block_id: int = chunk.get_block(x, y, z)
				if not Blocks.is_liquid(block_id):
					continue
				var above: int = block_at(x, y + 1, z)
				var covered: bool = Blocks.is_opaque(above)
				var cell: Vector2i = Blocks.face_tile(block_id, 2, 0)
				if cell.x < 0:
					continue
				var tile_origin := Vector2(float(cell.x), float(cell.y))
				var sky: float = float(sky_at(x, y + 1, z)) / 15.0
				var block_light: float = float(block_light_at(x, y + 1, z)) / 15.0
				var light := Vector2(sky, block_light)
				var full: bool = above == block_id
				var height: float = 1.0 if full else 0.875
				if not covered and not full:
					var base_index: int = builder.vertices.size()
					var y_top: float = float(y) + height
					var corners: Array[Vector3] = [
						Vector3(float(x), y_top, float(z)),
						Vector3(float(x) + 1.0, y_top, float(z)),
						Vector3(float(x) + 1.0, y_top, float(z) + 1.0),
						Vector3(float(x), y_top, float(z) + 1.0),
					]
					var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
					for index in 4:
						builder.vertices.append(corners[index])
						builder.normals.append(Vector3(0, 1, 0))
						builder.colors.append(Color(0.88, 0.93, 1.0, 1.0))
						builder.uvs.append(uvs[index])
						builder.tile_origins.append(tile_origin)
						builder.light_uv.append(light)
					builder.indices.append_array([base_index, base_index + 1, base_index + 2,
						base_index, base_index + 2, base_index + 3])
				# side faces against air/gaps
				if full:
					continue
				for face in [0, 1, 4, 5]:
					var normal: Vector3i = FACE_NORMALS[face]
					var neighbour: int = block_at(x + normal.x, y + normal.y, z + normal.z)
					if neighbour == block_id:
						continue
					if Blocks.is_opaque(neighbour):
						continue
					var side_cell: Vector2i = Blocks.face_tile(block_id, face, 0)
					var base_index: int = builder.vertices.size()
					var y0: float = float(y)
					var y1: float = float(y) + height
					var x0: float = float(x)
					var x1: float = float(x) + 1.0
					var z0: float = float(z)
					var z1: float = float(z) + 1.0
					var corners: Array[Vector3] = []
					match face:
						0:
							corners = [Vector3(x1, y0, z0), Vector3(x1, y0, z1),
								Vector3(x1, y1, z1), Vector3(x1, y1, z0)]
						1:
							corners = [Vector3(x0, y0, z1), Vector3(x0, y0, z0),
								Vector3(x0, y1, z0), Vector3(x0, y1, z1)]
						4:
							corners = [Vector3(x0, y0, z1), Vector3(x1, y0, z1),
								Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
						_:
							corners = [Vector3(x1, y0, z0), Vector3(x0, y0, z0),
								Vector3(x0, y1, z0), Vector3(x1, y1, z0)]
					var uvs := [Vector2(0, height), Vector2(1, height), Vector2(1, 0),
						Vector2(0, 0)]
					for index in 4:
						builder.vertices.append(corners[index])
						builder.normals.append(Vector3(normal.x, normal.y, normal.z))
						builder.colors.append(Color(0.82, 0.88, 0.99, 1.0))
						builder.uvs.append(uvs[index])
						builder.tile_origins.append(Vector2(float(side_cell.x), float(side_cell.y)))
						builder.light_uv.append(light)
					builder.indices.append_array([base_index, base_index + 1, base_index + 2,
						base_index, base_index + 2, base_index + 3])
