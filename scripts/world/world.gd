class_name World
extends Node3D

## The streaming voxel world.
##
## Responsibilities
## ----------------
## * Chunk streaming: generate, light, mesh and unload chunks around the player
##   inside a per-frame time budget, with generation and meshing on worker
##   threads so streaming never blocks a frame for long.
## * Block API for the rest of the game (`get_block`, `set_block`, `break_block`,
##   raycasts, light queries).
## * Player edits, containers and entities, which survive chunk unloads and are
##   what gets written to disk.
## * Wiring up the environment (day/night, weather), block ticking (fluids,
##   falling blocks, crops) and redstone.

signal chunk_ready(coord: Vector2i)
signal block_changed(pos: Vector3i, block_id: int, block_meta: int)
signal block_broken(pos: Vector3i, block_id: int, by_player: bool)
signal block_placed(pos: Vector3i, block_id: int)
signal world_ready()

const GEN_BUDGET_USEC: int = 6000        # per-frame main-thread work budget
const MAX_GEN_TASKS: int = 2             # concurrent chunk generators
const MAX_MESH_TASKS: int = 2            # concurrent chunk meshers
const COLLISION_DISTANCE: int = 3        # chunks that get physics shapes
const UNLOAD_MARGIN: int = 2
const SAVE_MAGIC: int = 0x424C4B43       # "BLCK"
const CONTAINER_TICK_DISTANCE: float = 64.0

var world_seed: int = 1337
var world_name: String = "World"
var slot: String = ""
var gamemode: String = "survival"
var played_seconds: float = 0.0

var generator: WorldGen
var chunks: Dictionary = {}              # Vector2i → Chunk
var _pending_gen: Dictionary = {}         # Vector2i → task id
var _pending_mesh: Dictionary = {}        # Vector2i → task id
var _mesh_queue: Array = []               # coords waiting for a mesh slot
var _gen_queue: Array = []                # coords waiting for a generator slot
var _dirty: Dictionary = {}               # Vector2i → true (needs a remesh)
var _streamed: bool = false               # set once the queues first drain
var _edits: Dictionary = {}               # Vector2i → {local index: [id, meta]}
var _containers: Dictionary = {}          # Vector3i → BlockContainer
var _signs: Dictionary = {}               # Vector3i → sign text
var _sign_labels: Dictionary = {}         # Vector3i → Label3D
var _sign_timer: float = 0.0
var _chunk_meshes: Dictionary = {}        # Vector2i → MeshInstance3D
var _collision_body: StaticBody3D
var _collision_shapes: Dictionary = {}    # Vector2i → CollisionShape3D
var _materials: Dictionary = {}           # material slot → ShaderMaterial
var _terrain_shader: Shader
var _container_tick: float = 0.0
var _hopper_phase: bool = false

var render_distance: int = 7
const SIGN_LABEL_DISTANCE: float = 48.0

var player: Node3D
var _last_player_chunk: Vector2i = Vector2i(9999, 9999)
var _spawn_position: Vector3 = Vector3(0.5, 80.0, 0.5)

# Subsystems (created in _ready)
var block_updates: BlockUpdates
var redstone: Redstone
var day_night: DayNightCycle
var weather: WeatherSystem
var mobs: MobManager
var particles: ParticleFx
var structures_ready: bool = false

# Streaming statistics for the debug overlay.
var stats: Dictionary = {
	"generated": 0, "meshed": 0, "loaded": 0, "queued": 0, "pending": 0,
	"vertices": 0, "triangles": 0, "unloaded": 0,
}


func _ready() -> void:
	add_to_group("world")
	_apply_settings()
	generator = WorldGen.new(world_seed)
	_build_materials()
	_build_collision_body()

	block_updates = BlockUpdates.new(self)
	redstone = Redstone.new(self)
	add_child(block_updates)
	# Subsystems get their world reference before entering the tree, so their
	# `_ready` and first `_process` can already talk to it safely.
	day_night = DayNightCycle.new()
	day_night.setup(self)
	add_child(day_night)
	weather = WeatherSystem.new()
	weather.setup(self)
	add_child(weather)
	mobs = MobManager.new(self)
	add_child(mobs)
	particles = ParticleFx.new()
	add_child(particles)

	_spawn_position = _compute_spawn()
	print("World '%s' seed %d, spawn %s" % [world_name, world_seed, str(_spawn_position)])
	# Generate the chunks under the spawn synchronously so the player lands on
	# solid ground on frame one, then stream the rest in over the next seconds.
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_generate_now(Vector2i(dx, dz))
	GameLog.step("world: spawn chunks generated, streaming starts")
	world_ready.emit()


func _apply_settings() -> void:
	render_distance = int(Settings.get_value("render_distance"))
	Settings.changed.connect(func(key: String, value: Variant) -> void:
		if key == "render_distance":
			render_distance = int(value)
			_last_player_chunk = Vector2i(9999, 9999)  # force a stream update
		elif key == "smooth_lighting":
			_update_shader_uniforms()
	)


func _compute_spawn() -> Vector3:
	var x := 8
	var z := 8
	var y: int = generator.height_at(x, z) + 2
	if y <= WorldGen.SEA_LEVEL:
		# Spawn on a beach instead of in the ocean when possible.
		for radius in range(8, 200, 8):
			for angle in 4:
				var probe_x: int = x + int(cos(TAU * angle / 4.0) * radius)
				var probe_z: int = z + int(sin(TAU * angle / 4.0) * radius)
				var probe_y: int = generator.height_at(probe_x, probe_z)
				if probe_y > WorldGen.SEA_LEVEL + 1:
					return Vector3(float(probe_x) + 0.5, float(probe_y) + 1.2, float(probe_z) + 0.5)
	return Vector3(float(x) + 0.5, float(y) + 1.0, float(z) + 0.5)


func get_spawn_position() -> Vector3:
	return _spawn_position


# ---------------------------------------------------------------------------
# Materials & collision
# ---------------------------------------------------------------------------


func _build_materials() -> void:
	_terrain_shader = load("res://shaders/terrain.gdshader")
	if _terrain_shader == null:
		push_error("terrain shader missing")
		return
	for slot in ["solid", "cutout", "water"]:
		var material := ShaderMaterial.new()
		material.shader = _terrain_shader if slot != "water" \
			else load("res://shaders/water.gdshader")
		material.set_shader_parameter("atlas", Registry.atlas_texture)
		material.set_shader_parameter("atlas_size", Vector2(float(Blocks.atlas_size),
			float(Blocks.atlas_size)))
		material.set_shader_parameter("tile_pixels", float(Blocks.tile_size))
		material.set_shader_parameter("cell_pixels", float(Blocks.atlas_cell))
		material.set_shader_parameter("atlas_cols", float(Blocks.atlas_cols))
		material.set_shader_parameter("alpha_test", slot != "solid")
		material.set_shader_parameter("is_water", slot == "water")
		material.set_shader_parameter("day_factor", 1.0)
		_materials[slot] = material
	_update_shader_uniforms()


func _update_shader_uniforms() -> void:
	var fog_color := Color(0.62, 0.74, 0.9)
	for slot in _materials:
		var material: ShaderMaterial = _materials[slot]
		material.set_shader_parameter("fog_color", fog_color)
		material.set_shader_parameter("fog_distance", float(render_distance * Chunk.SIZE))
		material.set_shader_parameter("smooth_lighting",
			bool(Settings.get_value("smooth_lighting")))


## Called by the day/night cycle.
func set_day_factor(factor: float) -> void:
	for slot in _materials:
		(_materials[slot] as ShaderMaterial).set_shader_parameter("day_factor", factor)
	_update_shader_uniforms()


func _build_collision_body() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "WorldCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	add_child(_collision_body)


# ---------------------------------------------------------------------------
# Streaming
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	played_seconds += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	var player_chunk: Vector2i = world_to_chunk(player.global_position)
	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_refresh_streaming(player_chunk)
		_update_collision_window(player_chunk)
		_update_shader_uniforms()
	# Safety net: never let the player stand in a chunk that does not exist yet.
	if not chunks.has(player_chunk):
		_generate_now(player_chunk)
	_pump_streaming()
	_tick_containers(delta)
	_tick_sign_labels(delta)


## Furnaces near the player keep smelting while the world is loaded.
func _tick_containers(delta: float) -> void:
	_container_tick += delta
	if _container_tick < 0.25:
		return
	var step: float = _container_tick
	_container_tick = 0.0
	var origin: Vector3 = player.global_position
	for position in _containers.keys():
		var container: BlockContainer = _containers[position]
		if container == null:
			continue
		var center: Vector3 = Vector3(position) + Vector3(0.5, 0.5, 0.5)
		if center.distance_to(origin) > CONTAINER_TICK_DISTANCE:
			continue
		if container.kind == BlockContainer.KIND_HOPPER:
			# Hoppers move one item every other container tick, which works out
			# at roughly two items a second: busy enough to see, and cheap enough
			# that a long line of them keeps the frame budget.
			_hopper_phase = not _hopper_phase
			if _hopper_phase and _tick_hopper(position, container):
				container_changed.emit(position)
			continue
		if container.kind != BlockContainer.KIND_FURNACE:
			continue
		var was_lit: bool = container.lit
		var smelted: bool = container.tick_furnace(step)
		if smelted:
			container_changed.emit(position)
			var produced: Variant = container.get_slot(2)
			if produced != null:
				item_smelted.emit(position, int(produced["id"]))
			if container.get_slot(2) != null and Settings.get_value("particles"):
				spawn_particles(center + Vector3(0.0, 0.6, 0.0), "smoke", 2)
		if was_lit != container.lit:
			container_changed.emit(position)
			if container.lit:
				AudioManager.play_3d("furnace", center, self, -6.0)


func world_to_chunk(position: Vector3) -> Vector2i:
	return Vector2i(int(floor(position.x)) >> 4, int(floor(position.z)) >> 4)


func _refresh_streaming(center: Vector2i) -> void:
	var wanted: Array = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var coord := center + Vector2i(dx, dz)
			if chunks.has(coord) or _pending_gen.has(coord) or _gen_queue.has(coord):
				continue
			wanted.append(coord)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, center) < _chebyshev(b, center)
	)
	_gen_queue.append_array(wanted)
	stats["queued"] = _gen_queue.size()
	# Unload chunks that drifted out of range.
	var limit: int = render_distance + UNLOAD_MARGIN
	var to_unload: Array = []
	for coord in chunks:
		if _chebyshev(coord, center) > limit:
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Runs the streaming pipeline inside a frame budget.
func _pump_streaming() -> void:
	var deadline: int = Time.get_ticks_usec() + GEN_BUDGET_USEC

	# 1. Start generator tasks for queued chunks (nearest first, already sorted).
	while not _gen_queue.is_empty() and _pending_gen.size() < MAX_GEN_TASKS:
		var coord: Vector2i = _gen_queue.pop_front()
		if chunks.has(coord) or _pending_gen.has(coord):
			continue
		_start_gen_task(coord)

	# 2. Collect finished chunks.
	for coord in _pending_gen.keys():
		var task_id: int = _pending_gen[coord]
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		_pending_gen.erase(coord)
		var chunk: Chunk = _gen_results.get(coord)
		_gen_results.erase(coord)
		if chunk != null:
			_adopt_chunk(coord, chunk)
		if Time.get_ticks_usec() > deadline:
			break

	# 3. Queue meshing for dirty chunks (requires neighbours for correct borders).
	while not _mesh_queue.is_empty() and _pending_mesh.size() < MAX_MESH_TASKS:
		var coord: Vector2i = _mesh_queue.pop_front()
		if not chunks.has(coord) or _pending_mesh.has(coord):
			continue
		_start_mesh_task(coord)

	# 4. Apply finished meshes.
	for coord in _pending_mesh.keys():
		var task_id: int = _pending_mesh[coord]
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		_pending_mesh.erase(coord)
		var result: ChunkMesher.MeshResult = _mesh_results.get(coord)
		_mesh_results.erase(coord)
		if result != null and chunks.has(coord):
			_apply_mesh(coord, result)
		if Time.get_ticks_usec() > deadline:
			break

	# 5. Re-mesh chunks that changed (edits, lighting).
	if not _dirty.is_empty() and _mesh_queue.is_empty():
		var dirty_coord: Vector2i = _dirty.keys()[0]
		_dirty.erase(dirty_coord)
		if chunks.has(dirty_coord):
			_mesh_queue.append(dirty_coord)

	stats["loaded"] = chunks.size()
	stats["queued"] = _gen_queue.size()
	stats["pending"] = _pending_gen.size() + _pending_mesh.size()
	if not _streamed and _gen_queue.is_empty() and _mesh_queue.is_empty() \
			and _pending_gen.is_empty() and _pending_mesh.is_empty():
		# The moment the streaming queue drains: if a phone dies while playing,
		# this line tells us whether it happened during the initial load.
		_streamed = true
		GameLog.step("world: streaming caught up (%d chunks)" % chunks.size())


func _adopt_chunk(coord: Vector2i, chunk: Chunk) -> void:
	_apply_saved_edits(coord, chunk)
	chunks[coord] = chunk
	stats["generated"] = int(stats["generated"]) + 1
	# Lighting needs the neighbours, so it runs once they exist (and is redone
	# whenever a neighbour arrives, which is how light crosses chunk borders).
	LightEngine.relight_chunk(chunk, _neighbours_of(coord))
	for offset: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour_coord: Vector2i = coord + offset
		if chunks.has(neighbour_coord):
			_dirty[neighbour_coord] = true
			var neighbour: Chunk = chunks[neighbour_coord]
			if not neighbour.lighting_done:
				LightEngine.relight_chunk(neighbour, _neighbours_of(neighbour_coord))
	_dirty[coord] = true
	chunk_ready.emit(coord)


func _neighbours_of(coord: Vector2i) -> Dictionary:
	var out := {}
	for offset: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour = chunks.get(coord + offset)
		if neighbour != null:
			out[offset] = neighbour
	return out


func _start_gen_task(coord: Vector2i) -> void:
	var chunk := Chunk.new(coord)
	var task_id: int = WorkerThreadPool.add_task(
		func() -> void:
			generator.generate_chunk(chunk)
			_gen_results[coord] = chunk,
		true, "chunk_gen"
	)
	_pending_gen[coord] = task_id


func _start_mesh_task(coord: Vector2i) -> void:
	var chunk: Chunk = chunks[coord]
	var neighbours: Dictionary = _neighbours_of(coord)
	var task_id: int = WorkerThreadPool.add_task(
		func() -> void:
			_mesh_results[coord] = ChunkMesher.build(chunk, neighbours),
		true, "chunk_mesh"
	)
	_pending_mesh[coord] = task_id


var _gen_results: Dictionary = {}
var _mesh_results: Dictionary = {}


## Generates and meshes a chunk immediately on the main thread (spawn area and
## the safety net under the player). Returns the chunk.
func _generate_now(coord: Vector2i) -> Chunk:
	if chunks.has(coord):
		return chunks[coord]
	var chunk := Chunk.new(coord)
	generator.generate_chunk(chunk)
	_adopt_chunk(coord, chunk)
	LightEngine.relight_chunk(chunk, _neighbours_of(coord))
	_apply_mesh(coord, ChunkMesher.build(chunk, _neighbours_of(coord)))
	return chunk


func _apply_mesh(coord: Vector2i, result: ChunkMesher.MeshResult) -> void:
	var chunk: Chunk = chunks.get(coord)
	if chunk == null:
		return
	var instance: MeshInstance3D = _chunk_meshes.get(coord)
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = "Chunk_%d_%d" % [coord.x, coord.y]
		instance.position = Vector3(float(coord.x * Chunk.SIZE), 0.0, float(coord.y * Chunk.SIZE))
		add_child(instance)
		_chunk_meshes[coord] = instance
	var mesh := _build_array_mesh(result)
	instance.mesh = mesh
	instance.visible = false  # marked visible once every neighbour is loaded
	var distance: int = _chebyshev(coord, _last_player_chunk)
	if distance > COLLISION_DISTANCE:
		_remove_collision(coord)
	else:
		_build_collision(coord, result, distance)
	stats["meshed"] = int(stats["meshed"]) + 1
	stats["triangles"] = int(stats["triangles"]) + result.triangle_count


func _build_array_mesh(result: ChunkMesher.MeshResult) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var custom_flags: int = (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for slot in 3:
		var builder: ChunkMesher.MeshBuilder = result.surfaces[slot]
		if builder == null or builder.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = builder.vertices
		arrays[Mesh.ARRAY_NORMAL] = builder.normals
		arrays[Mesh.ARRAY_COLOR] = builder.colors
		arrays[Mesh.ARRAY_TEX_UV] = builder.uvs
		arrays[Mesh.ARRAY_CUSTOM0] = builder.tile_origins
		arrays[Mesh.ARRAY_CUSTOM1] = builder.light_uv
		arrays[Mesh.ARRAY_INDEX] = builder.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[_slot_name(slot)])
	return mesh


static func _slot_name(slot: int) -> String:
	match slot:
		ChunkMesher.MAT_CUTOUT:
			return "cutout"
		ChunkMesher.MAT_WATER:
			return "water"
	return "solid"


func _build_collision(coord: Vector2i, result: ChunkMesher.MeshResult, distance: int) -> void:
	_remove_collision(coord)
	if not result.has_collision:
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = result.collision_vertices
	arrays[Mesh.ARRAY_INDEX] = result.collision_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	var collision := CollisionShape3D.new()
	collision.name = "ChunkCol_%d_%d" % [coord.x, coord.y]
	collision.shape = shape
	collision.position = Vector3(float(coord.x * Chunk.SIZE), 0.0, float(coord.y * Chunk.SIZE))
	_collision_body.add_child(collision)
	_collision_shapes[coord] = collision


func _remove_collision(coord: Vector2i) -> void:
	var collision: CollisionShape3D = _collision_shapes.get(coord)
	if collision != null and is_instance_valid(collision):
		collision.queue_free()
	_collision_shapes.erase(coord)


func _update_collision_window(center: Vector2i) -> void:
	# Give near chunks physics, and drop it from the ones that drifted away.
	for coord in chunks:
		var distance: int = _chebyshev(coord, center)
		if distance <= COLLISION_DISTANCE and not _collision_shapes.has(coord):
			var chunk: Chunk = chunks[coord]
			if chunk != null:
				_dirty[coord] = true
		elif distance > COLLISION_DISTANCE and _collision_shapes.has(coord):
			_remove_collision(coord)
	# Visibility: a chunk may only render once all four neighbours are loaded so
	# that border faces are culled correctly.
	for coord in _chunk_meshes:
		var instance: MeshInstance3D = _chunk_meshes[coord]
		instance.visible = _all_neighbours_loaded(coord)


func _all_neighbours_loaded(coord: Vector2i) -> bool:
	for offset: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not chunks.has(coord + offset):
			return false
	return true


func _unload_chunk(coord: Vector2i) -> void:
	var instance: MeshInstance3D = _chunk_meshes.get(coord)
	if instance != null and is_instance_valid(instance):
		instance.queue_free()
	_chunk_meshes.erase(coord)
	_remove_collision(coord)
	var chunk: Chunk = chunks.get(coord)
	if chunk != null:
		_capture_edits(coord, chunk)
	chunks.erase(coord)
	_dirty.erase(coord)
	stats["unloaded"] = int(stats["unloaded"]) + 1


func _exit_tree() -> void:
	for task_id in _pending_gen.values():
		if not WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
	for task_id in _pending_mesh.values():
		if not WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)


# ---------------------------------------------------------------------------
# Block API
# ---------------------------------------------------------------------------


func get_block(pos: Vector3i) -> int:
	var chunk: Chunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if chunk == null:
		return Blocks.AIR
	if pos.y < 0 or pos.y >= Chunk.HEIGHT:
		return Blocks.AIR
	return chunk.get_block(pos.x & 15, pos.y, pos.z & 15)


func get_block_meta(pos: Vector3i) -> int:
	var chunk: Chunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if chunk == null or pos.y < 0 or pos.y >= Chunk.HEIGHT:
		return 0
	return chunk.get_block_meta(pos.x & 15, pos.y, pos.z & 15)


func is_loaded(pos: Vector3i) -> bool:
	return chunks.has(Vector2i(pos.x >> 4, pos.z >> 4))


func is_solid(pos: Vector3i) -> bool:
	return Blocks.is_solid(get_block(pos))


func is_opaque(pos: Vector3i) -> bool:
	return Blocks.is_opaque(get_block(pos))


func is_liquid(pos: Vector3i) -> bool:
	return Blocks.is_liquid(get_block(pos))


func get_sky_light(pos: Vector3i) -> int:
	var chunk: Chunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if chunk == null or pos.y < 0 or pos.y >= Chunk.HEIGHT:
		return 15
	return chunk.get_sky_light(pos.x & 15, pos.y, pos.z & 15)


func get_block_light(pos: Vector3i) -> int:
	var chunk: Chunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if chunk == null or pos.y < 0 or pos.y >= Chunk.HEIGHT:
		return 0
	return chunk.get_block_light(pos.x & 15, pos.y, pos.z & 15)


## Combined 0..1 brightness used by mob spawning and the HUD light meter.
func get_light(pos: Vector3i) -> float:
	return maxf(float(get_sky_light(pos)) / 15.0 * day_night.daylight_factor(),
		float(get_block_light(pos)) / 15.0)


func set_block(pos: Vector3i, block_id: int, block_meta: int = 0,
		update_light: bool = true) -> bool:
	if pos.y < 0 or pos.y >= Chunk.HEIGHT:
		return false
	var coord := Vector2i(pos.x >> 4, pos.z >> 4)
	var chunk: Chunk = chunks.get(coord)
	if chunk == null:
		# Remember the edit so it is applied when the chunk streams in.
		_record_edit(coord, pos.x & 15, pos.y, pos.z & 15, block_id, block_meta)
		return true
	var old_id: int = chunk.get_block(pos.x & 15, pos.y, pos.z & 15)
	var old_meta: int = chunk.get_block_meta(pos.x & 15, pos.y, pos.z & 15)
	if old_id == block_id and old_meta == block_meta:
		return true
	chunk.set_block(pos.x & 15, pos.y, pos.z & 15, block_id, block_meta)
	chunk.has_water = _chunk_has_water(chunk)
	_record_edit(coord, pos.x & 15, pos.y, pos.z & 15, block_id, block_meta)
	if update_light and (Blocks.light_emission(old_id) > 0 or Blocks.light_emission(block_id) > 0
			or Blocks.is_opaque(old_id) != Blocks.is_opaque(block_id)):
		_relight_around(coord, Vector3i(pos.x & 15, pos.y, pos.z & 15))
	_mark_dirty_with_neighbours(coord, pos)
	block_updates.on_block_changed(pos, old_id, block_id)
	redstone.on_block_changed(pos, old_id, block_id)
	block_changed.emit(pos, block_id, block_meta)
	return true


static func _chunk_has_water(chunk: Chunk) -> bool:
	for i in chunk.blocks.size():
		if Blocks.is_liquid(chunk.blocks[i]):
			return true
	return false


func _mark_dirty_with_neighbours(coord: Vector2i, pos: Vector3i) -> void:
	_dirty[coord] = true
	var local_x: int = pos.x & 15
	var local_z: int = pos.z & 15
	if local_x == 0:
		_dirty[coord + Vector2i(-1, 0)] = true
	elif local_x == 15:
		_dirty[coord + Vector2i(1, 0)] = true
	if local_z == 0:
		_dirty[coord + Vector2i(0, -1)] = true
	elif local_z == 15:
		_dirty[coord + Vector2i(0, 1)] = true


func _relight_around(coord: Vector2i, local_pos: Vector3i) -> void:
	var chunk: Chunk = chunks.get(coord)
	if chunk == null:
		return
	LightEngine.relight_box(chunk, _neighbours_of(coord), local_pos, 7)
	# Light can spill over a border, so neighbours need a refresh too.
	var local_x: int = local_pos.x
	var local_z: int = local_pos.z
	if local_x <= 7 or local_x >= 8 or local_z <= 7 or local_z >= 8:
		for offset: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbour_coord: Vector2i = coord + offset
			var neighbour: Chunk = chunks.get(neighbour_coord)
			if neighbour != null:
				LightEngine.relight_chunk(neighbour, _neighbours_of(neighbour_coord))
				_dirty[neighbour_coord] = true


## Breaks a block, spawning its drops. Returns true when something was broken.
func break_block(pos: Vector3i, tool_item: int = -1, by_player: bool = false,
		drop_items: bool = true) -> bool:
	var block_id: int = get_block(pos)
	if block_id == Blocks.AIR:
		return false
	if Blocks.def(block_id).hardness < 0.0 and not by_player:
		return false
	var block_meta: int = get_block_meta(pos)
	var tool_kind: String = Items.tool_kind(tool_item)
	var tool_tier: int = Items.tool_tier(tool_item)
	# Containers spill their contents.
	var container: BlockContainer = _containers.get(pos)
	if container != null:
		for stack in container.serialize():
			if int(stack.get("count", 0)) > 0:
				spawn_item_drop(Vector3(pos) + Vector3(0.5, 0.5, 0.5), int(stack["id"]),
					int(stack["count"]), stack.get("durability", 0))
		_containers.erase(pos)
		container_changed.emit(pos)
	# Crops drop their harvest plus seeds.
	if Blocks.def(block_id).harvest != "" and block_meta >= 7 and drop_items:
		var harvest: String = Blocks.def(block_id).harvest
		spawn_item_drop(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Items.id(harvest), 1)
		if block_id == Blocks.id("wheat"):
			spawn_item_drop(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Items.id("wheat_seeds"),
				randi_range(1, 3))
	if drop_items and Blocks.def(block_id).harvest == "":
		for drop in Blocks.drops_for(block_id, tool_kind, tool_tier):
			var item_id: int = Items.id(str(drop["item"]))
			if item_id < 0:
				item_id = Blocks.id(str(drop["item"]))
			if item_id >= 0:
				spawn_item_drop(Vector3(pos) + Vector3(0.5, 0.5, 0.5), item_id, int(drop["count"]))
	var xp: int = Blocks.def(block_id).xp
	if xp > 0 and drop_items:
		spawn_xp(Vector3(pos) + Vector3(0.5, 0.5, 0.5), xp)
	set_block(pos, Blocks.AIR)
	block_broken.emit(pos, block_id, by_player)
	# Neighbouring plants fall away.
	for offset: Vector3i in [
			Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
		var neighbour: Vector3i = pos + offset
		var neighbour_id: int = get_block(neighbour)
		if Blocks.shape(neighbour_id) == Blocks.SHAPE_CROSS and offset.y != 0:
			break_block(neighbour, -1, by_player, drop_items)
	return true


## Places a block if the space allows. `facing` is the player's yaw for
## orientable blocks.
func place_block(pos: Vector3i, block_id: int, facing: int = 0) -> bool:
	if block_id == Blocks.AIR:
		return false
	var existing: int = get_block(pos)
	if not (existing == Blocks.AIR or Blocks.is_replaceable(existing)):
		return false
	var block_meta: int = 0
	if Blocks.has_facing(block_id):
		block_meta = facing & 0x7
	var definition: BlockDef = Blocks.def(block_id)
	# Support checks: plants need soil, torches need a floor or wall.
	if definition.shape == Blocks.SHAPE_CROSS or definition.shape == Blocks.SHAPE_TORCH:
		var below: int = get_block(pos + Vector3i(0, -1, 0))
		if definition.shape == Blocks.SHAPE_TORCH:
			var supported: bool = Blocks.is_opaque(below)
			if not supported:
				for offset: Vector3i in [
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
						Vector3i(0, 0, -1)]:
					if Blocks.is_opaque(get_block(pos + offset)):
						supported = true
						break
			if not supported:
				return false
		elif not Blocks.is_plantable(below) and below != Blocks.FARMLAND:
			if definition.name != "sugar_cane":
				return false
			if get_block(pos + Vector3i(0, -1, 0)) != Blocks.id("sugar_cane"):
				var near_water: bool = false
				for offset: Vector3i in [
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
						Vector3i(0, 0, -1), Vector3i(1, -1, 0), Vector3i(-1, -1, 0),
						Vector3i(0, -1, 1), Vector3i(0, -1, -1)]:
					if is_liquid(pos + offset):
						near_water = true
						break
				if not near_water:
					return false
	set_block(pos, block_id, block_meta)
	block_placed.emit(pos, block_id)
	return true


## Distance to the first block hit by a ray, plus the hit normal/position.
func raycast(origin: Vector3, direction: Vector3, max_distance: float = 6.0,
		include_liquids: bool = false) -> Dictionary:
	var dir := direction.normalized()
	var step: float = 0.05
	var travel: float = 0.0
	var last_voxel := Vector3i(999999, 999999, 999999)
	var normal := Vector3i.ZERO
	var previous := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	while travel <= max_distance:
		var point: Vector3 = origin + dir * travel
		var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if voxel != last_voxel:
			last_voxel = voxel
			var block_id: int = get_block(voxel)
			var hit: bool = block_id != Blocks.AIR and (include_liquids or not Blocks.is_liquid(block_id))
			# A block only counts as a target when it actually has a shape.
			if hit and Blocks.shape(block_id) == Blocks.SHAPE_CROSS:
				hit = false
			if hit:
				normal = previous - voxel
				if normal.length_squared() > 1:
					normal = _dominant_axis(previous - voxel)
				return {
					"hit": true, "position": voxel, "block": block_id,
					"normal": normal, "point": point,
					"distance": travel, "meta": get_block_meta(voxel),
				}
			previous = voxel
		travel += step
	return {"hit": false}


static func _dominant_axis(delta: Vector3i) -> Vector3i:
	if absi(delta.x) >= absi(delta.y) and absi(delta.x) >= absi(delta.z):
		return Vector3i(signi(delta.x), 0, 0)
	if absi(delta.y) >= absi(delta.z):
		return Vector3i(0, signi(delta.y), 0)
	return Vector3i(0, 0, signi(delta.z))


## Surface height for spawning mobs and structures.
func surface_height(x: int, z: int) -> int:
	var chunk: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if chunk == null:
		return generator.height_at(x, z) + 1
	for y in range(Chunk.HEIGHT - 1, 0, -1):
		var block_id: int = chunk.get_block(x & 15, y, z & 15)
		if block_id != Blocks.AIR and not Blocks.is_liquid(block_id):
			return y + 1
	return generator.height_at(x, z) + 1


func biome_at(x: int, z: int) -> int:
	return generator.biome_at(x, z)


func biome_name(x: int, z: int) -> String:
	return WorldGen.BIOME_NAMES[biome_at(x, z)]


# ---------------------------------------------------------------------------
# Entities & items
# ---------------------------------------------------------------------------


func spawn_item_drop(position: Vector3, item_id: int, count: int = 1,
		durability: int = 0) -> void:
	if item_id < 0 or count <= 0:
		return
	var drop := ItemDrop.new()
	drop.item_id = item_id
	drop.count = count
	drop.durability = durability
	drop.position = position
	add_child(drop)


func spawn_xp(position: Vector3, amount: int) -> void:
	var drop := XpOrb.new()
	drop.amount = amount
	drop.position = position
	add_child(drop)


## Spawns an explosion: destroys blocks in radius, damages entities, drops items.
func explode(center: Vector3, radius: float, damage_terrain: bool = true) -> void:
	if damage_terrain:
		var block_radius: int = int(ceil(radius))
		var center_voxel := Vector3i(floori(center.x), floori(center.y), floori(center.z))
		for dx in range(-block_radius, block_radius + 1):
			for dy in range(-block_radius, block_radius + 1):
				for dz in range(-block_radius, block_radius + 1):
					var distance: float = Vector3(dx, dy, dz).length()
					if distance > radius * (0.75 + randf() * 0.35):
						continue
					var pos: Vector3i = center_voxel + Vector3i(dx, dy, dz)
					var block_id: int = get_block(pos)
					if block_id == Blocks.AIR or block_id == Blocks.BEDROCK:
						continue
					var hardness: float = Blocks.def(block_id).hardness
					if hardness < 0.0 or hardness > 8.0:
						continue
					if Blocks.is_liquid(block_id):
						continue
					break_block(pos, -1, false, randf() < 0.3)
	# Damage entities and the player in range.
	for entity in get_tree().get_nodes_in_group("damageable"):
		if entity is Node3D:
			var offset: Vector3 = (entity as Node3D).global_position - center
			var distance: float = offset.length()
			if distance < radius * 2.0 and entity.has_method("take_damage"):
				var falloff: float = clampf(1.0 - distance / (radius * 2.0), 0.0, 1.0)
				entity.take_damage(int(round(24.0 * falloff)), "explosion")
	AudioManager.play_3d("explode", center, self, 2.0, randf_range(0.9, 1.1), 48.0)


## One-shot particle burst; routed through ParticleFx so FX code stays in one place.
func spawn_particles(position: Vector3, kind: String = "smoke", count: int = 0,
		tint: Color = Color.WHITE) -> void:
	if particles == null or not is_instance_valid(particles):
		return
	particles.spawn(kind, position, count, tint)


## Convenience wrapper used by block updates and gameplay code.
func spawn_break_particles(position: Vector3, count: int = 8) -> void:
	spawn_particles(position, "block_break", count)


func spawn_mob(mob_type: String, position: Vector3, persistent: bool = false) -> Mob:
	if mobs == null:
		return null
	return mobs.spawn(mob_type, position, persistent)


# ---------------------------------------------------------------------------
# Containers
# ---------------------------------------------------------------------------


signal container_changed(pos: Vector3i)
signal item_smelted(pos: Vector3i, item_id: int)
signal sign_changed(pos: Vector3i, text: String)


## One hopper tick: push an item into the container it points at, or otherwise
## pull one out of the container sitting on top of it.
func _tick_hopper(position: Vector3i, container: BlockContainer) -> bool:
	var direction: Vector3i = Blocks.facing_offset(get_block_meta(position))
	var target: BlockContainer = get_container(position + direction)
	if target != null and BlockContainer.transfer_one(container, target):
		return true
	if not container.is_empty():
		# Still holding something: wait for the target to drain instead of
		# hoarding a second load on top of what it cannot pass on.
		return false
	var source: BlockContainer = get_container(position + Vector3i(0, 1, 0))
	if source != null and BlockContainer.transfer_one(source, container):
		return true
	return false


# ---------------------------------------------------------------------------
# Signs
# ---------------------------------------------------------------------------


## Stores the text written on a sign, or clears it when the text is empty.
func set_sign_text(pos: Vector3i, text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		_signs.erase(pos)
	else:
		_signs[pos] = trimmed
	_refresh_sign_label(pos)
	sign_changed.emit(pos, trimmed)


func sign_text(pos: Vector3i) -> String:
	return str(_signs.get(pos, ""))


func sign_count() -> int:
	return _signs.size()


## Drops sign text when the block is no longer a sign, so a broken sign never
## leaves a floating label behind.
func _forget_sign(pos: Vector3i) -> void:
	if not _signs.has(pos) and not _sign_labels.has(pos):
		return
	_signs.erase(pos)
	var label: Label3D = _sign_labels.get(pos)
	if label != null and is_instance_valid(label):
		label.queue_free()
	_sign_labels.erase(pos)


## Keeps billboarded text alive for the signs around the player. Creating and
## destroying labels on a slow timer is cheaper than tracking chunk streaming.
func _tick_sign_labels(delta: float) -> void:
	if _signs.is_empty() and _sign_labels.is_empty():
		return
	_sign_timer += delta
	if _sign_timer < 0.4:
		return
	_sign_timer = 0.0
	var origin: Vector3 = player.global_position if player != null else _spawn_position
	for position in _signs.keys():
		var text: String = str(_signs[position])
		if player != null and Vector3(position).distance_to(origin) > SIGN_LABEL_DISTANCE:
			var away: Label3D = _sign_labels.get(position)
			if away != null and is_instance_valid(away):
				away.visible = false
			continue
		_create_sign_label(position, text)


func _create_sign_label(pos: Vector3i, text: String) -> void:
	var label: Label3D = _sign_labels.get(pos)
	if label == null or not is_instance_valid(label):
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.pixel_size = 0.0055
		label.font_size = 48
		label.outline_size = 12
		label.modulate = Color(1, 1, 1)
		label.no_depth_test = false
		label.name = "SignLabel"
		add_child(label)
		_sign_labels[pos] = label
	label.text = text
	label.visible = true
	label.global_position = Vector3(pos) + Vector3(0.5, 1.15, 0.5)


## Called by the sign editor when a label should appear or change right away.
func _refresh_sign_label(pos: Vector3i) -> void:
	var text: String = sign_text(pos)
	if text == "":
		_forget_sign(pos)
		return
	_create_sign_label(pos, text)


func get_container(pos: Vector3i) -> BlockContainer:
	var existing: BlockContainer = _containers.get(pos)
	if existing != null:
		return existing
	var block_id: int = get_block(pos)
	var kind: String = Blocks.container_kind(block_id)
	if kind == "":
		return null
	var container := BlockContainer.new(kind)
	container.position = pos
	containers_created += 1
	_containers[pos] = container
	return container


var containers_created: int = 0


func remove_container(pos: Vector3i) -> void:
	_containers.erase(pos)
	container_changed.emit(pos)


func container_positions() -> Array:
	return _containers.keys()


func has_container(pos: Vector3i) -> bool:
	return _containers.has(pos)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func _record_edit(coord: Vector2i, local_x: int, y: int, local_z: int, block_id: int,
		block_meta: int) -> void:
	var chunk_edits: Dictionary = _edits.get(coord, {})
	chunk_edits[Chunk.index(local_x, y, local_z)] = [block_id, block_meta]
	_edits[coord] = chunk_edits


func _apply_saved_edits(coord: Vector2i, chunk: Chunk) -> void:
	var chunk_edits: Dictionary = _edits.get(coord, {})
	for index in chunk_edits:
		var entry: Array = chunk_edits[index]
		chunk.blocks[index] = int(entry[0])
		chunk.meta[index] = int(entry[1])


func _capture_edits(coord: Vector2i, chunk: Chunk) -> void:
	var chunk_edits: Dictionary = _edits.get(coord, {})
	for index in chunk_edits:
		if index < chunk.blocks.size():
			chunk.blocks[index] = int(chunk_edits[index][0])
			chunk.meta[index] = int(chunk_edits[index][1])


## Binary blob of every player edit; terrain itself is regenerated from the seed.
func serialize_edits() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, SAVE_MAGIC)
	out.append_array(var_to_bytes(_edits.size()))
	for coord in _edits:
		out.append_array(var_to_bytes(coord.x))
		out.append_array(var_to_bytes(coord.y))
		var chunk_edits: Dictionary = _edits[coord]
		out.append_array(var_to_bytes(chunk_edits.size()))
		for index in chunk_edits:
			out.append_array(var_to_bytes(index))
			var entry: Array = chunk_edits[index]
			out.append_array(var_to_bytes(int(entry[0])))
			out.append_array(var_to_bytes(int(entry[1])))
	return out


func apply_serialized_edits(data: PackedByteArray) -> void:
	if data.size() < 8:
		return
	if data.decode_u32(0) != SAVE_MAGIC:
		push_warning("save blob has an unexpected header")
		return
	var cursor := {"offset": 4}
	var chunk_count: int = int(read_var(data, cursor))
	for _chunk_index in chunk_count:
		var cx: int = int(read_var(data, cursor))
		var cz: int = int(read_var(data, cursor))
		var count: int = int(read_var(data, cursor))
		var chunk_edits := {}
		for _entry in count:
			var index: int = int(read_var(data, cursor))
			var block_id: int = int(read_var(data, cursor))
			var block_meta: int = int(read_var(data, cursor))
			chunk_edits[index] = [block_id, block_meta]
		_edits[Vector2i(cx, cz)] = chunk_edits
	# Chunks already in memory need the edits re-applied.
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_apply_saved_edits(coord, chunk)
		_dirty[coord] = true
		LightEngine.relight_chunk(chunk, _neighbours_of(coord))


static func var_to_bytes(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, value)
	return out


static func read_var(data: PackedByteArray, cursor: Dictionary) -> int:
	var offset: int = int(cursor["offset"])
	if offset + 4 > data.size():
		return 0
	cursor["offset"] = offset + 4
	return data.decode_s32(offset)


func serialize_containers() -> Array:
	var out: Array = []
	for pos in _containers:
		var container: BlockContainer = _containers[pos]
		out.append({
			"x": pos.x, "y": pos.y, "z": pos.z, "kind": container.kind,
			"slots": container.serialize(),
		})
	return out


func apply_containers(data: Array) -> void:
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos := Vector3i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("z", 0)))
		var container := BlockContainer.new(str(entry.get("kind", "chest")))
		container.position = pos
		container.deserialize(entry.get("slots", []))
		_containers[pos] = container


func serialize_entities() -> Array:
	if mobs == null:
		return []
	return mobs.serialize()


func apply_entities(data: Array) -> void:
	if mobs != null:
		mobs.deserialize(data)


## Everything the save file needs about the world state.
func serialize_signs() -> Array:
	var out: Array = []
	for pos in _signs:
		out.append({"x": pos.x, "y": pos.y, "z": pos.z, "text": _signs[pos]})
	return out


func apply_signs(data: Array) -> void:
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos := Vector3i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("z", 0)))
		var text: String = str(entry.get("text", ""))
		if text != "":
			_signs[pos] = text


func save_state() -> Dictionary:
	return {
		"day_time": day_night.time_of_day,
		"weather": weather.state,
		"weather_timer": weather.time_left,
		"played_seconds": played_seconds,
		"spawn": {"x": _spawn_position.x, "y": _spawn_position.y, "z": _spawn_position.z},
		"signs": serialize_signs(),
	}


func apply_state(state: Dictionary) -> void:
	day_night.time_of_day = float(state.get("day_time", 0.3))
	weather.set_weather(str(state.get("weather", "clear")))
	weather.time_left = float(state.get("weather_timer", 120.0))
	played_seconds = float(state.get("played_seconds", 0.0))
	apply_signs(state.get("signs", []))
	var spawn = state.get("spawn")
	if typeof(spawn) == TYPE_DICTIONARY:
		_spawn_position = Vector3(float(spawn.get("x", 0.5)), float(spawn.get("y", 80.0)),
			float(spawn.get("z", 0.5)))


# ---------------------------------------------------------------------------
# Statistics for the debug overlay
# ---------------------------------------------------------------------------


func loaded_chunk_count() -> int:
	return chunks.size()


func loaded_block_count() -> int:
	return chunks.size() * Chunk.VOLUME


func collision_shape_count() -> int:
	return _collision_shapes.size()


func edit_count() -> int:
	var total: int = 0
	for coord in _edits:
		total += (_edits[coord] as Dictionary).size()
	return total
