class_name MobManager
extends Node3D

## Spawns, caps and despawns mobs around the player, and persists them.
##
## Spawning follows Minecraft-ish rules: passive animals appear on lit grass in
## herds during the day, hostile mobs appear where it is dark (caves, or the
## surface at night). Both are capped, spawned outside the player's immediate
## view, and despawned when they wander too far away.

const PASSIVE_CAP: int = 18
const HOSTILE_CAP: int = 22
const SPAWN_INTERVAL: float = 2.5
const MIN_SPAWN_DISTANCE: float = 22.0
const MAX_SPAWN_DISTANCE: float = 52.0
const DESPAWN_DISTANCE: float = 96.0
const PEACEFUL_CAP: int = 0

var world: World
var mobs: Array[Mob] = []
var enabled: bool = true

var _spawn_timer: float = 3.0
var _spawn_attempts: int = 0
var _mobs_spawned: int = 0
var _mobs_despawned: int = 0


func _init(world_ref: World = null) -> void:
	world = world_ref
	name = "MobManager"


func _ready() -> void:
	add_to_group("mob_manager")
	# Also works when the manager is added by hand without a world argument.
	if world == null:
		world = get_parent() as World
	if world == null:
		world = get_tree().get_first_node_in_group("world") as World


func _process(delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	# Prune in place: `filter()` returns an untyped Array, which cannot be
	# assigned back to a typed `Array[Mob]` (and would fail every frame).
	for index in range(mobs.size() - 1, -1, -1):
		if not is_instance_valid(mobs[index]):
			mobs.remove_at(index)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_try_spawn_cycle()
	_despawn_far_mobs()


func _try_spawn_cycle() -> void:
	var player: Node3D = world.player
	if player == null or not is_instance_valid(player):
		return
	var difficulty: int = int(Settings.get_value("difficulty"))
	var passive_count: int = 0
	var hostile_count: int = 0
	for mob in mobs:
		if bool(mob.stats.get("hostile", false)):
			hostile_count += 1
		else:
			passive_count += 1
	if passive_count < PASSIVE_CAP:
		# Villages first: villagers only ever appear around a plaza.
		if not _try_spawn_villagers(player):
			_try_spawn_group(false, player)
	if difficulty > 0 and hostile_count < HOSTILE_CAP:
		_try_spawn_group(true, player)


## Returns true when a village was found and populated.
func _try_spawn_villagers(player: Node3D) -> bool:
	var origin: Vector2i = Vector2i(floori(player.global_position.x),
		floori(player.global_position.z))
	var center: Vector2i = StructureGen.village_center_near(world.generator, origin.x, origin.y, 72)
	if center.x == StructureGen.NO_VILLAGE.x:
		return false
	var existing: int = 0
	for mob in mobs:
		if is_instance_valid(mob) and bool(mob.stats.get("village", false)):
			if mob.global_position.distance_to(Vector3(float(center.x), mob.global_position.y,
					float(center.y))) < 40.0:
				existing += 1
	if existing >= 8:
		return true
	for index in 2:
		var offset := Vector2i(randi_range(-10, 10), randi_range(-10, 10))
		var position := Vector3(float(center.x + offset.x) + 0.5, 0.0,
			float(center.y + offset.y) + 0.5)
		position.y = float(world.surface_height(floori(position.x), floori(position.z)))
		if world.is_liquid(Vector3i(floori(position.x), floori(position.y) - 1, floori(position.z))):
			continue
		var villager: Mob = spawn("villager", position, true)
		if villager.global_position.distance_to(player.global_position) > DESPAWN_DISTANCE:
			villager.queue_free()
	return true


func _try_spawn_group(hostile: bool, player: Node3D) -> void:
	_spawn_attempts += 1
	var origin: Vector3 = player.global_position
	var angle: float = randf() * TAU
	var distance: float = randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
	var spawn_x: int = floori(origin.x + cos(angle) * distance)
	var spawn_z: int = floori(origin.z + sin(angle) * distance)
	var coord := Vector2i(spawn_x >> 4, spawn_z >> 4)
	if not world.chunks.has(coord):
		return
	var biome: int = world.biome_at(spawn_x, spawn_z)
	# Choose a candidate position: surface, or underground for hostiles.
	var spawn_y: int = world.surface_height(spawn_x, spawn_z)
	var underground: bool = false
	if hostile and randf() < 0.55:
		# Try a cave spot below the surface.
		var probe_y: int = randi_range(8, maxi(9, spawn_y - 6))
		for _step in 12:
			if world.get_block(Vector3i(spawn_x, probe_y, spawn_z)) == Blocks.AIR \
					and world.get_block(Vector3i(spawn_x, probe_y + 1, spawn_z)) == Blocks.AIR \
					and world.is_solid(Vector3i(spawn_x, probe_y - 1, spawn_z)):
				underground = true
				spawn_y = probe_y
				break
			probe_y -= 3
			if probe_y < 6:
				break
	var type: String = _pick_type(hostile, biome, spawn_x, spawn_y, spawn_z, underground)
	if type == "":
		return
	var group_size: int = int(MobTypes.get_stats(type).get("spawn_group", 1))
	group_size = clampi(group_size, 1, 4)
	for index in group_size:
		var offset := Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		var position := Vector3(float(spawn_x) + 0.5, float(spawn_y), float(spawn_z) + 0.5) + offset
		var ground: int = world.surface_height(floori(position.x), floori(position.z))
		position.y = float(ground if not underground else spawn_y)
		if world.get_block(Vector3i(floori(position.x), floori(position.y), floori(position.z))) != Blocks.AIR:
			continue
		if world.is_liquid(Vector3i(floori(position.x), floori(position.y) - 1, floori(position.z))):
			continue
		spawn(type, position)


func _pick_type(hostile: bool, biome: int, x: int, y: int, z: int,
		underground: bool) -> String:
	var light: float = world.get_light(Vector3i(x, y, z))
	var candidates: Array = []
	var pool: PackedStringArray = MobTypes.hostile_types() if hostile \
		else MobTypes.wild_passive_types()
	for mob_type in pool:
		var stats: Dictionary = MobTypes.get_stats(mob_type)
		var biomes: Array = stats.get("biomes", [])
		if not biomes.is_empty() and not biomes.has(biome):
			continue
		var min_light: float = float(stats.get("min_light", 0.0))
		var max_light: float = float(stats.get("max_light", 1.0))
		if light < min_light or light > max_light:
			continue
		# Passive mobs always need a solid, plantable floor.
		if not hostile and underground:
			continue
		candidates.append(mob_type)
	if candidates.is_empty():
		return ""
	return str(candidates[randi() % candidates.size()])


func spawn(mob_type: String, position: Vector3, persistent: bool = false) -> Mob:
	if not MobTypes.exists(mob_type):
		mob_type = "pig"
	var mob := Mob.new()
	mob.setup(mob_type, world)
	mob.persistent = persistent
	mob.position = position
	world.add_child(mob)
	mobs.append(mob)
	_mobs_spawned += 1
	# Keep the cap honest even when spawning is driven from elsewhere.
	if mobs.size() > PASSIVE_CAP + HOSTILE_CAP + 12:
		_despawn_far_mobs()
	return mob


func _despawn_far_mobs() -> void:
	var player: Node3D = world.player
	if player == null or not is_instance_valid(player):
		return
	var origin: Vector3 = player.global_position
	var survivors: Array[Mob] = []
	for mob in mobs:
		if not is_instance_valid(mob):
			continue
		if mob.persistent or mob.tamed:
			survivors.append(mob)
			continue
		var distance: float = mob.global_position.distance_to(origin)
		var hostile: bool = bool(mob.stats.get("hostile", false))
		var despawn: bool = distance > DESPAWN_DISTANCE
		# Hostile mobs vanish when the world turns bright (like monsters do).
		if hostile and distance > 40.0 and world.day_night != null \
				and world.day_night.is_day() and world.get_sky_light(
					Vector3i(floori(mob.global_position.x), floori(mob.global_position.y),
						floori(mob.global_position.z))) > 12:
			despawn = true
		if despawn:
			mob.queue_free()
			_mobs_despawned += 1
			continue
		survivors.append(mob)
	mobs = survivors


# ---------------------------------------------------------------------------
# Queries used by the player, UI and debug overlay
# ---------------------------------------------------------------------------


func nearby(position: Vector3, radius: float) -> Array:
	var out: Array = []
	for mob in mobs:
		if is_instance_valid(mob) and mob.global_position.distance_to(position) <= radius:
			out.append(mob)
	return out


func count() -> int:
	var total: int = 0
	for mob in mobs:
		if is_instance_valid(mob):
			total += 1
	return total


func hostile_count() -> int:
	var total: int = 0
	for mob in mobs:
		if is_instance_valid(mob) and bool(mob.stats.get("hostile", false)):
			total += 1
	return total


func stats_summary() -> Dictionary:
	return {
		"total": count(), "hostile": hostile_count(),
		"spawned": _mobs_spawned, "despawned": _mobs_despawned, "attempts": _spawn_attempts,
	}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func serialize() -> Array:
	var out: Array = []
	var player: Node3D = world.player
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
	for mob in mobs:
		if not is_instance_valid(mob):
			continue
		# Only mobs near the player are saved; the rest can respawn naturally.
		if origin != Vector3.ZERO and mob.global_position.distance_to(origin) > 72.0:
			continue
		out.append(mob.serialize())
	return out


func deserialize(data: Array) -> void:
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mob: Mob = Mob.from_save(entry, world)
		world.add_child(mob)
		mobs.append(mob)
