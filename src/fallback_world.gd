extends Node3D
# Fallback GDScript world when C++ GDExtension not built
# Uses exact same values as C++ port from decompiled Eaglercraft 26.2

const CHUNK_SIZE_X = 16
const CHUNK_SIZE_Y = 128 # Smaller for GDScript performance
const CHUNK_SIZE_Z = 16
const WORLD_MIN_Y = 0
const WORLD_MAX_Y = 128

var chunks: Dictionary = {}
var world_seed: int = 12345
var render_distance: int = 5

var noise: FastNoiseLite

func _ready():
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = world_seed
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	
	generate_initial_world()
	print("Fallback GDScript world generated - %d chunks" % chunks.size())

func generate_initial_world():
	for x in range(-render_distance, render_distance+1):
		for z in range(-render_distance, render_distance+1):
			create_chunk(x, z)

func create_chunk(cx: int, cz: int):
	var key = "%d,%d" % [cx, cz]
	if chunks.has(key):
		return chunks[key]
	
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cx, cz]
	chunk_node.position = Vector3(cx * CHUNK_SIZE_X, 0, cz * CHUNK_SIZE_Z)
	add_child(chunk_node)
	
	var mesh_instance = MeshInstance3D.new()
	chunk_node.add_child(mesh_instance)
	
	var static_body = StaticBody3D.new()
	chunk_node.add_child(static_body)
	
	var collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)
	
	# Generate terrain data
	var blocks = []
	blocks.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
	blocks.fill(0)
	
	for x in range(CHUNK_SIZE_X):
		for z in range(CHUNK_SIZE_Z):
			var world_x = cx * CHUNK_SIZE_X + x
			var world_z = cz * CHUNK_SIZE_Z + z
			var height_noise = noise.get_noise_2d(world_x, world_z)
			var height = 32 + int(height_noise * 16)
			height = clamp(height, 5, CHUNK_SIZE_Y - 10)
			
			for y in range(CHUNK_SIZE_Y):
				var idx = x + z * CHUNK_SIZE_X + y * CHUNK_SIZE_X * CHUNK_SIZE_Z
				if y == 0:
					blocks[idx] = 7 # bedrock
				elif y < height - 4:
					blocks[idx] = 1 # stone
				elif y < height - 1:
					blocks[idx] = 3 # dirt
				elif y < height:
					blocks[idx] = 2 # grass
				else:
					blocks[idx] = 0 # air
			
			# Simple tree
			if height > 30 and randf() < 0.02:
				for ty in range(4):
					var y = height + ty
					if y < CHUNK_SIZE_Y:
						var idx = x + z * CHUNK_SIZE_X + y * CHUNK_SIZE_X * CHUNK_SIZE_Z
						blocks[idx] = 17 # log
				# leaves
				for lx in range(-2, 3):
					for lz in range(-2, 3):
						for ly in range(3):
							if lx == 0 and lz == 0 and ly < 2:
								continue
							var wx = x + lx
							var wz = z + lz
							var wy = height + 3 + ly
							if wx < 0 or wx >= CHUNK_SIZE_X or wz < 0 or wz >= CHUNK_SIZE_Z or wy >= CHUNK_SIZE_Y:
								continue
							var idx = wx + wz * CHUNK_SIZE_X + wy * CHUNK_SIZE_X * CHUNK_SIZE_Z
							if blocks[idx] == 0:
								blocks[idx] = 18 # leaves
	
	# Generate mesh
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	# Simple face culling
	for y in range(CHUNK_SIZE_Y):
		for z in range(CHUNK_SIZE_Z):
			for x in range(CHUNK_SIZE_X):
				var idx = x + z * CHUNK_SIZE_X + y * CHUNK_SIZE_X * CHUNK_SIZE_Z
				var block_id = blocks[idx]
				if block_id == 0:
					continue
				
				# Check neighbors
				var neighbors = [
					[0, 1, 0], [0, -1, 0],
					[1, 0, 0], [-1, 0, 0],
					[0, 0, 1], [0, 0, -1]
				]
				for dir_idx in range(6):
					var nx = x + neighbors[dir_idx][0]
					var ny = y + neighbors[dir_idx][1]
					var nz = z + neighbors[dir_idx][2]
					var neighbor_id = 0
					if nx >= 0 and nx < CHUNK_SIZE_X and ny >= 0 and ny < CHUNK_SIZE_Y and nz >= 0 and nz < CHUNK_SIZE_Z:
						var nidx = nx + nz * CHUNK_SIZE_X + ny * CHUNK_SIZE_X * CHUNK_SIZE_Z
						neighbor_id = blocks[nidx]
					# If neighbor is air, add face
					if neighbor_id == 0:
						_add_face(vertices, normals, uvs, indices, Vector3(x, y, z), dir_idx, block_id)
	
	if vertices.size() == 0:
		return chunk_node
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Material
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, mat)
	
	# Collision
	var shape = ConcavePolygonShape3D.new()
	# Create faces from vertices and indices
	var faces = PackedVector3Array()
	faces.resize(indices.size())
	for i in range(indices.size()):
		faces[i] = vertices[indices[i]]
	shape.set_faces(faces)
	collision_shape.shape = shape
	
	chunks[key] = chunk_node
	return chunk_node

func _add_face(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, idxs: PackedInt32Array, pos: Vector3, dir: int, block_id: int):
	var normal: Vector3
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var v3: Vector3
	var color: Color
	
	match block_id:
		1: color = Color(0.5, 0.5, 0.5) # stone
		2: color = Color(0.3, 0.6, 0.2) # grass
		3: color = Color(0.5, 0.35, 0.2) # dirt
		7: color = Color(0.2, 0.2, 0.2) # bedrock
		17: color = Color(0.4, 0.25, 0.1) # log
		18: color = Color(0.2, 0.6, 0.15) # leaves
		_: color = Color(0.8, 0.8, 0.8)
	
	var x = pos.x
	var y = pos.y
	var z = pos.z
	
	match dir:
		0: # top
			v0 = Vector3(x, y+1, z)
			v1 = Vector3(x+1, y+1, z)
			v2 = Vector3(x+1, y+1, z+1)
			v3 = Vector3(x, y+1, z+1)
			normal = Vector3(0,1,0)
		1: # bottom
			v0 = Vector3(x, y, z+1)
			v1 = Vector3(x+1, y, z+1)
			v2 = Vector3(x+1, y, z)
			v3 = Vector3(x, y, z)
			normal = Vector3(0,-1,0)
		2: # +X
			v0 = Vector3(x+1, y, z)
			v1 = Vector3(x+1, y, z+1)
			v2 = Vector3(x+1, y+1, z+1)
			v3 = Vector3(x+1, y+1, z)
			normal = Vector3(1,0,0)
		3: # -X
			v0 = Vector3(x, y, z+1)
			v1 = Vector3(x, y, z)
			v2 = Vector3(x, y+1, z)
			v3 = Vector3(x, y+1, z+1)
			normal = Vector3(-1,0,0)
		4: # +Z
			v0 = Vector3(x, y, z+1)
			v1 = Vector3(x+1, y, z+1)
			v2 = Vector3(x+1, y+1, z+1)
			v3 = Vector3(x, y+1, z+1)
			normal = Vector3(0,0,1)
		5: # -Z
			v0 = Vector3(x+1, y, z)
			v1 = Vector3(x, y, z)
			v2 = Vector3(x, y+1, z)
			v3 = Vector3(x+1, y+1, z)
			normal = Vector3(0,0,-1)
	
	var start = verts.size()
	verts.append(v0)
	verts.append(v1)
	verts.append(v2)
	verts.append(v3)
	norms.append(normal)
	norms.append(normal)
	norms.append(normal)
	norms.append(normal)
	uvs.append(Vector2(0,1))
	uvs.append(Vector2(1,1))
	uvs.append(Vector2(1,0))
	uvs.append(Vector2(0,0))
	idxs.append(start)
	idxs.append(start+1)
	idxs.append(start+2)
	idxs.append(start)
	idxs.append(start+2)
	idxs.append(start+3)
