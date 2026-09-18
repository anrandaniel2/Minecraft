class_name Mob
extends CharacterBody3D

## Every creature in the world: one class, driven by a stats table.
##
## Behaviour: wander, follow tempting items, flee when hurt, chase and attack
## the player (melee, ranged or explode), burn in daylight, swim, climb and die
## with drops + experience. AI is deliberately simple steering with obstacle
## jumping, which reads well in a blocky world and stays cheap with 40+ mobs.

signal died(mob: Mob)

const GRAVITY: float = 26.0
const SKIN_SIZE: float = 80.0     # every mob sheet is generated at 80x80 px

# Sounds that are already "ambient" voices, so hurting uses the matching hurt clip.
const IDLE_SOUNDS: PackedStringArray = [
	"zombie_idle", "skeleton_rattle", "creeper_hiss", "cow_moo", "pig_oink",
	"sheep_baa", "chicken_cluck", "cat_meow", "villager_hmm",
]
const WATER_BUOYANCY: float = 12.0

var mob_type: String = "pig"
var stats: Dictionary = {}
var health: float = 10.0
var max_health: float = 10.0
var world: World
var baby: bool = false
var persistent: bool = false
var tamed: bool = false
var profession: String = ""
var trade_count: int = 0

var _skin: Texture2D
var _material: StandardMaterial3D
var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _hurt_timer: float = 0.0
var _sound_timer: float = 0.0
var _attack_timer: float = 0.0
var _wander_timer: float = 0.0
var _wander_direction: Vector3 = Vector3.ZERO
var _jump_cooldown: float = 0.0
var _target: Node3D
var _fuse: float = -1.0                # creeper swell
var _fire_timer: float = 0.0            # daylight burning
var _breed_cooldown: float = 60.0
var _love_timer: float = 0.0
var _in_water: bool = false
var _age: float = 0.0
var _walker_phase: float = 0.0


func setup(type: String, world_ref: World) -> void:
	mob_type = type
	world = world_ref
	stats = MobTypes.get_stats(type)


func _ready() -> void:
	add_to_group("mob")
	add_to_group("damageable")
	if stats.is_empty():
		setup(mob_type, world)
	max_health = float(stats["health"])
	health = max_health
	var width: float = float(stats.get("width", 0.6))
	var height: float = float(stats.get("height", 1.8))
	if baby:
		width *= 0.65
		height *= 0.65
	_build_body(width, height)
	if bool(stats.get("village", false)):
		profession = Trades.profession_for(randi())
	_sound_timer = randf_range(1.0, float(stats.get("sound_interval", 8.0)))
	_wander_timer = randf_range(0.5, 3.0)
	# Slight random tint so a herd does not look cloned.
	var variation: float = randf_range(0.92, 1.08)
	_material.albedo_color = Color(variation, variation, variation)
	# Face a random direction at spawn.
	rotation.y = randf() * TAU
	if float(stats.get("speed", 2.0)) > 2.5:
		pass


func _build_body(width: float, height: float) -> void:
	_skin = Registry.entity_skin(str(stats.get("skin", "pig")))
	_material = StandardMaterial3D.new()
	_material.albedo_texture = _skin
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	var skin_name: String = str(stats.get("skin", "pig"))
	var tiles: Dictionary = Registry.entity_tiles.get(skin_name, {})
	var parts: Array = BoxModel.mob_parts(tiles, str(stats.get("model", "quadruped")),
		0.65 if baby else 1.0)
	var mesh := BoxModel.build(parts, Vector2(SKIN_SIZE, SKIN_SIZE))
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.name = "Model"
	add_child(_mesh_instance)

	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.2, width * 0.5)
	shape.height = maxf(0.6, height)
	_collision = CollisionShape3D.new()
	_collision.shape = shape
	_collision.position = Vector3(0.0, shape.height * 0.5, 0.0)
	add_child(_collision)

	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4


# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	_age += delta
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	_breed_cooldown = maxf(0.0, _breed_cooldown - delta)
	_love_timer = maxf(0.0, _love_timer - delta)
	_sound_timer -= delta
	_wander_timer -= delta
	_update_material()

	if _sound_timer <= 0.0:
		_sound_timer = randf_range(float(stats.get("sound_interval", 8.0)) * 0.7,
			float(stats.get("sound_interval", 8.0)) * 1.6)
		if _near_player(24.0):
			AudioManager.play_3d(str(stats.get("sound", "pig_oink")), global_position, self, -6.0,
				randf_range(0.92, 1.12))

	if not is_on_floor():
		velocity.y -= GRAVITY * delta * (0.35 if bool(stats.get("fall_slow", false)) else 1.0)
	else:
		velocity.y = -0.1

	_in_water = world.is_liquid(Vector3i(floori(global_position.x), floori(global_position.y),
		floori(global_position.z)))
	if _in_water:
		velocity.y = minf(velocity.y + WATER_BUOYANCY * delta, 2.0)
		velocity.y = maxf(velocity.y, -2.0)
		if velocity.y > -0.5 and randf() < 0.05:
			AudioManager.play_3d("swim", global_position, self, -10.0)

	if bool(stats.get("hostile", false)):
		_hostile_ai(delta)
	else:
		_passive_ai(delta)

	if bool(stats.get("burns_in_daylight", false)) and _tick_daylight_burn(delta):
		pass

	_apply_animation(delta)
	move_and_slide()
	_avoid_void()


func _passive_ai(delta: float) -> void:
	var player := _get_player()
	var tempted: bool = false
	if player != null and player.has_method("held_item_name"):
		var held: String = str(player.held_item_name())
		var tempt_item: String = str(stats.get("tempt", ""))
		if tempt_item != "" and held == tempt_item and _distance_to(player) < 12.0:
			tempted = true
			_face_towards(player.global_position, delta, 6.0)
			_move_horizontal(player.global_position - global_position, float(stats["speed"]) * 0.65)
	if tempted:
		_wander_timer = 0.0
		return
	if _hurt_timer > 0.6 and player != null and _distance_to(player) < 12.0:
		# Flee for a moment after being hit.
		_move_horizontal(global_position - player.global_position, float(stats["speed"]))
		return
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.0, 6.0)
		if randf() < 0.35:
			_wander_direction = Vector3.ZERO
		else:
			var angle: float = randf() * TAU
			_wander_direction = Vector3(cos(angle), 0.0, sin(angle))
	if _wander_direction != Vector3.ZERO:
		_face_towards(global_position + _wander_direction, delta, 4.0)
		_move_horizontal(_wander_direction, float(stats["speed"]) * 0.45)


func _hostile_ai(delta: float) -> void:
	var player := _get_player()
	var target_position := Vector3.ZERO
	_target = null
	if player != null:
		var distance: float = _distance_to(player)
		if distance < float(stats.get("follow_range", 16.0)):
			# Skip players that are already dead (they cannot be attacked).
			var player_dead: bool = false
			var dead_value: Variant = player.get("is_dead")
			if typeof(dead_value) == TYPE_BOOL:
				player_dead = dead_value
			if not player_dead:
				_target = player
				target_position = player.global_position
	if _target == null:
		# Idle wander while looking for prey.
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(3.0, 7.0)
			var angle: float = randf() * TAU
			_wander_direction = Vector3(cos(angle), 0.0, sin(angle)) if randf() < 0.5 else Vector3.ZERO
		if _wander_direction != Vector3.ZERO:
			_face_towards(global_position + _wander_direction, delta, 3.0)
			_move_horizontal(_wander_direction, float(stats["speed"]) * 0.35)
		_fuse = -1.0
		return
	_face_towards(target_position, delta, 9.0)
	var to_target: Vector3 = target_position - global_position
	var horizontal_distance: float = Vector2(to_target.x, to_target.z).length()
	var reach: float = float(stats.get("reach", 1.4))
	# Spiders and other climbers scale walls when blocked.
	if bool(stats.get("climbs", false)) and is_on_wall():
		velocity.y = 2.4
	# Creepers swell up and detonate.
	if bool(stats.get("explodes", false)):
		if horizontal_distance < reach + 1.2:
			if _fuse < 0.0:
				_fuse = 0.0
				AudioManager.play_3d("creeper_hiss", global_position, self, -2.0)
			_fuse += delta
			if _fuse >= 1.6:
				_explode()
				return
			velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
			return
		else:
			_fuse = maxf(-1.0, _fuse - delta)
	if bool(stats.get("ranged", false)):
		# Skeletons keep their distance and shoot.
		if horizontal_distance < 5.0:
			_move_horizontal(global_position - target_position, float(stats["speed"]) * 0.6)
		elif horizontal_distance > 12.0:
			_move_horizontal(to_target, float(stats["speed"]))
		else:
			velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
		if _attack_timer <= 0.0 and _can_see(player):
			_attack_timer = randf_range(1.4, 2.4)
			_shoot_arrow(target_position)
		return
	# Melee
	_move_horizontal(to_target, float(stats["speed"]))
	if horizontal_distance <= reach and _attack_timer <= 0.0:
		_attack_timer = 1.0
		if player.has_method("take_damage"):
			player.take_damage(float(stats.get("attack", 3.0)), mob_type)
		var knock_direction: Vector3 = to_target.normalized()
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity += Vector3(knock_direction.x, 0.35,
				knock_direction.z) * 5.0


func _move_horizontal(direction: Vector3, speed: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		velocity.x = move_toward(velocity.x, 0.0, 0.6)
		velocity.z = move_toward(velocity.z, 0.0, 0.6)
		return
	flat = flat.normalized()
	var target_velocity: Vector3 = flat * speed * (0.65 if _in_water else 1.0)
	velocity.x = move_toward(velocity.x, target_velocity.x, 0.35)
	velocity.z = move_toward(velocity.z, target_velocity.z, 0.35)
	# Jump over one-block obstacles and out of water.
	if is_on_floor() and _jump_cooldown <= 0.0:
		var ahead := Vector3i(
			floori(global_position.x + flat.x * 0.7),
			floori(global_position.y),
			floori(global_position.z + flat.z * 0.7))
		var ahead_up: Vector3i = ahead + Vector3i(0, 1, 0)
		if world.is_solid(ahead) and not world.is_solid(ahead_up):
			velocity.y = 7.4
			_jump_cooldown = 0.5
	if _in_water and velocity.y > 0.0:
		velocity.y = 3.0


func _face_towards(position: Vector3, delta: float, speed: float) -> void:
	var to_target: Vector3 = position - global_position
	if Vector2(to_target.x, to_target.z).length_squared() < 0.001:
		return
	var target_yaw: float = atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * speed, 0.0, 1.0))


func _apply_animation(delta: float) -> void:
	if _mesh_instance == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	_walker_phase += delta * horizontal_speed * 3.2
	var bob: float = absf(sin(_walker_phase)) * 0.045 * minf(horizontal_speed, 3.0) * 0.4
	_mesh_instance.position.y = bob
	_mesh_instance.rotation.z = sin(_walker_phase) * 0.045 * minf(horizontal_speed, 3.0) * 0.2


func _can_see(target: Node3D) -> bool:
	var origin: Vector3 = global_position + Vector3(0.0, 1.4, 0.0)
	var to_target: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0) - origin
	var result: Dictionary = world.raycast(origin, to_target.normalized(), to_target.length())
	if not bool(result.get("hit", false)):
		return true
	return float(result.get("distance", 99.0)) >= to_target.length() - 0.4


func _shoot_arrow(target_position: Vector3) -> void:
	var origin: Vector3 = global_position + Vector3(0.0, 1.5, 0.0)
	var to_target: Vector3 = (target_position + Vector3(0.0, 1.0, 0.0)) - origin
	var distance: float = to_target.length()
	var speed: float = 26.0
	var gravity: float = 26.0
	var travel_time: float = distance / speed
	var aim: Vector3 = to_target + Vector3(0.0, 0.5 * gravity * travel_time * travel_time, 0.0)
	var arrow := Arrow.new()
	arrow.position = origin
	arrow.velocity = aim.normalized() * speed
	arrow.owner_is_player = false
	arrow.damage = 3.0
	world.add_child(arrow)
	AudioManager.play_3d("bow_shoot", global_position, self, -4.0)


func _explode() -> void:
	var power: float = float(stats.get("explosion_power", 3.0))
	var damage_terrain: bool = bool(Settings.get_value("mob_griefing"))
	world.explode(global_position + Vector3(0.0, 0.6, 0.0), power, damage_terrain)
	world.spawn_particles(global_position, "explosion", 40)
	health = 0.0
	_die(true)


func _tick_daylight_burn(delta: float) -> bool:
	if world.day_night == null or not world.day_night.is_day():
		_fire_timer = 0.0
		return false
	var voxel := Vector3i(floori(global_position.x), floori(global_position.y + 1.0),
		floori(global_position.z))
	if world.get_sky_light(voxel) < 14:
		_fire_timer = 0.0
		return false
	_fire_timer += delta
	if _fire_timer > 1.0:
		_fire_timer = 0.0
		if Settings.get_value("particles"):
			world.spawn_particles(global_position + Vector3(0.0, 1.0, 0.0), "smoke", 4)
		take_damage(1.0, "sunlight", false)
	return true


func _avoid_void() -> void:
	if global_position.y < -6.0:
		queue_free()


# ---------------------------------------------------------------------------
# Damage, death, interaction
# ---------------------------------------------------------------------------


func take_damage(amount: float, source: String = "", knockback: bool = true) -> void:
	if health <= 0.0:
		return
	health -= amount
	_hurt_timer = 0.6
	if knockback:
		var from_player := _get_player()
		if from_player != null and _distance_to(from_player) < 6.0:
			var away: Vector3 = (global_position - from_player.global_position).normalized()
			velocity += Vector3(away.x, 0.4, away.z) * 5.5
	var sound: String = str(stats.get("sound", ""))
	if sound != "":
		var chosen: String = sound if IDLE_SOUNDS.has(sound) else "%s_hurt" % sound.split("_")[0]
		AudioManager.play_3d(chosen, global_position, self, -3.0, randf_range(0.9, 1.1))
	if Settings.get_value("particles"):
		world.spawn_particles(global_position + Vector3(0.0, 1.0, 0.0), "critical", 5)
	if health <= 0.0:
		_die()


func _die(exploded: bool = false) -> void:
	if not exploded:
		var xp: int = int(stats.get("xp", 1))
		if xp > 0:
			world.spawn_xp(global_position + Vector3(0.0, 0.5, 0.0), xp)
	for drop in stats.get("drops", []):
		var item_name: String = str(drop[0])
		var min_count: int = int(drop[1])
		var max_count: int = int(drop[2])
		var chance: float = float(drop[3])
		if randf() > chance:
			continue
		var count: int = randi_range(min_count, max_count)
		if count > 0:
			var item_id: int = Items.id(item_name)
			if item_id >= 0:
				world.spawn_item_drop(global_position + Vector3(0.0, 0.6, 0.0), item_id, count)
	if Settings.get_value("particles"):
		world.spawn_particles(global_position + Vector3(0.0, 0.8, 0.0), "smoke", 10)
	died.emit(self)
	queue_free()


## Player right-click interaction: feeding, shearing, taming, trading.
func interact(player: Node, item_id: int) -> bool:
	var item_name: String = Items.name_of(item_id)
	if bool(stats.get("village", false)) and item_name == "":
		# Empty hand: open the trade screen on the player that right-clicked.
		if player != null and player.has_signal("open_trade_screen"):
			player.open_trade_screen.emit(self)
		return false
	if item_name == "":
		return false
	if item_name == str(stats.get("tempt", "")) and _breed_cooldown <= 0.0 and not baby:
		_love_timer = 8.0
		_breed_cooldown = 30.0
		if Settings.get_value("particles"):
			world.spawn_particles(global_position + Vector3(0.0, 1.2, 0.0), "heart", 3)
		_try_breed()
		return true
	if item_name == "shears" and stats.has("shearable") and _breed_cooldown <= 0.0:
		var wool: String = str(stats["shearable"])
		var wool_id: int = Items.id(wool)
		if wool_id >= 0:
			world.spawn_item_drop(global_position + Vector3(0.0, 1.0, 0.0), wool_id,
				randi_range(1, 3))
			_breed_cooldown = 20.0
			AudioManager.play_3d("sheep_baa", global_position, self, -3.0)
			return true
	if mob_type == "cat" and item_name in ["chicken", "cod"]:
		tamed = true
		if Settings.get_value("particles"):
			world.spawn_particles(global_position + Vector3(0.0, 1.0, 0.0), "heart", 3)
		return true
	return false


func _try_breed() -> void:
	for other in get_tree().get_nodes_in_group("mob"):
		if other == self or not (other is Mob):
			continue
		var mate: Mob = other
		if mate.mob_type != mob_type or mate.baby or mate._love_timer <= 0.0:
			continue
		if global_position.distance_to(mate.global_position) > 6.0:
			continue
		_love_timer = 0.0
		mate._love_timer = 0.0
		var child := Mob.new()
		child.setup(mob_type, world)
		child.baby = true
		child.position = (global_position + mate.global_position) * 0.5 + Vector3(0, 0.5, 0)
		world.add_child(child)
		if Settings.get_value("particles"):
			world.spawn_particles(child.global_position + Vector3(0.0, 1.0, 0.0), "heart", 4)
		return


func grow_up() -> void:
	if not baby:
		return
	baby = false
	if _mesh_instance != null:
		_mesh_instance.queue_free()
	if _collision != null:
		_collision.queue_free()
	_build_body(float(stats.get("width", 0.6)), float(stats.get("height", 1.8)))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _get_player() -> Node3D:
	if world == null:
		return null
	var player: Node3D = world.player
	if player == null or not is_instance_valid(player):
		return null
	return player


func _distance_to(node: Node3D) -> float:
	return global_position.distance_to(node.global_position)


func _near_player(distance: float) -> bool:
	var player := _get_player()
	if player == null:
		return false
	return _distance_to(player) < distance


func _update_material() -> void:
	if _material == null:
		return
	if _hurt_timer > 0.0:
		_material.emission_enabled = true
		_material.emission = Color(0.75, 0.15, 0.15)
	else:
		_material.emission_enabled = false
	if _fuse > 0.0:
		# Creepers flash white while swelling.
		var flash: float = 0.5 + 0.5 * sin(_fuse * 26.0)
		_material.albedo_color = Color(1.0, 1.0, 1.0).lerp(Color(0.7, 0.9, 1.0), flash)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func serialize() -> Dictionary:
	return {
		"type": mob_type,
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"health": health, "baby": baby, "tamed": tamed, "profession": profession,
		"trade_count": trade_count,
	}


static func from_save(entry: Dictionary, world_ref: World) -> Mob:
	var mob := Mob.new()
	mob.setup(str(entry.get("type", "pig")), world_ref)
	mob.baby = bool(entry.get("baby", false))
	mob.tamed = bool(entry.get("tamed", false))
	mob.position = Vector3(float(entry.get("x", 0)), float(entry.get("y", 64)),
		float(entry.get("z", 0)))
	mob.health = float(entry.get("health", 10.0))
	mob.profession = str(entry.get("profession", ""))
	mob.trade_count = int(entry.get("trade_count", 0))
	return mob
