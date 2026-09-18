class_name Player
extends CharacterBody3D

## First/third person voxel player.
##
## Movement: walk, sprint, sneak (with edge protection), jump, swim, climb
## ladders, creative flight, auto-jump, view bobbing and step sounds.
## Survival: health, hunger, saturation, drowning, fall damage, experience,
## respawn, and a 36 slot inventory with a hotbar, armour slots and tool
## durability.
## Interaction: mining with per-block break times and crack overlay, placing,
## eating, buckets, flint & steel, bows, shears, hoes, seeds, containers and
## redstone components.

signal stats_changed()
signal died()
signal respawned()
signal item_dropped(item_id: int, count: int)
signal inventory_changed()
signal open_container_screen(container: BlockContainer, position: Vector3i)
signal open_crafting_screen(kind: String)
signal open_trade_screen(mob: Node)

const WALK_SPEED: float = 4.4
const SPRINT_SPEED: float = 6.1
const SNEAK_SPEED: float = 1.7
const CREATIVE_FLY_SPEED: float = 11.0
const JUMP_VELOCITY: float = 8.6
const SWIM_SPEED: float = 3.4
const CLIMB_SPEED: float = 3.2
const MOUSE_SENSITIVITY_BASE: float = 0.0022
const REACH: float = 5.0
const EYE_HEIGHT: float = 1.62
const MAX_HEALTH: float = 20.0
const MAX_HUNGER: float = 20.0
const MAX_BREATH: float = 10.0
const HOTBAR_SIZE: int = 9
const INVENTORY_SIZE: int = 36
const ARMOR_SLOTS: int = 4
const RESPAWN_DELAY: float = 3.0

# --- state ---
var world: World
var inventory: BlockContainer
var armor: BlockContainer                     # 4 slots: head, chest, legs, feet
var hotbar_index: int = 0
var health: float = MAX_HEALTH
var hunger: float = MAX_HUNGER
var saturation: float = 5.0
var exhaustion: float = 0.0
var breath: float = MAX_BREATH
var xp: int = 0
var level: int = 0
var is_dead: bool = false
var gamemode: String = "survival"
var flying: bool = false
var third_person: bool = false
var spawn_point: Vector3 = Vector3.ZERO

var _camera: Camera3D
var _arm_pivot: Node3D
var _held_mesh: MeshInstance3D
var _highlight: MeshInstance3D
var _crack: MeshInstance3D
var _shadow: MeshInstance3D
var _body_model: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0
var _fall_start_y: float = 0.0
var _step_timer: float = 0.0
var _sprinting: bool = false
var _sneaking: bool = false
var _auto_jump_cooldown: float = 0.0
var _attack_held: bool = false
var _use_held: bool = false
var _mining_position: Vector3i = Vector3i(9999, 9999, 9999)
var _mining_progress: float = 0.0
var _mining_total: float = 0.0
var _place_cooldown: float = 0.0
var _use_cooldown: float = 0.0
var _attack_cooldown: float = 0.0
var _hurt_time: float = 0.0
var _last_damage_source: String = ""
var _respawn_timer: float = 0.0
var _eat_timer: float = 0.0
var _bow_charge: float = 0.0
var _sprint_particle_timer: float = 0.0
var _underwater: bool = false
var _in_lava: bool = false
var _submerged_timer: float = 0.0
var _view_bob_time: float = 0.0
var _highlight_block: Vector3i = Vector3i(9999, 9999, 9999)
var _dropped_on_death: bool = false
var _tick_timer: float = 0.0
var _air_time: float = 0.0
var _play_time: float = 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	gamemode = str(Settings.get_value("gamemode"))
	inventory = BlockContainer.new(BlockContainer.KIND_CHEST)
	inventory._resize(INVENTORY_SIZE)
	inventory.title = "Inventory"
	armor = BlockContainer.new(BlockContainer.KIND_CHEST)
	armor._resize(ARMOR_SLOTS)
	armor.title = "Armour"
	_build_nodes()
	spawn_point = Vector3(0.0, 70.0, 0.0)
	health = MAX_HEALTH
	stats_changed.emit()


func setup(world_ref: World) -> void:
	world = world_ref


func _build_nodes() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.9, 0.0)
	collision.name = "Body"
	add_child(collision)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	_camera.fov = float(Settings.get_value("fov"))
	_camera.near = 0.05
	_camera.far = 600.0
	add_child(_camera)

	_arm_pivot = Node3D.new()
	_arm_pivot.name = "ArmPivot"
	_camera.add_child(_arm_pivot)
	_held_mesh = MeshInstance3D.new()
	_held_mesh.name = "HeldItem"
	_held_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_mesh.position = Vector3(0.42, -0.38, -0.62)
	_held_mesh.rotation_degrees = Vector3(-16.0, -24.0, -6.0)
	_held_mesh.scale = Vector3.ONE * 0.34
	_arm_pivot.add_child(_held_mesh)

	# Block outline shown under the crosshair.
	_highlight = MeshInstance3D.new()
	_highlight.name = "BlockHighlight"
	var wire := ImmediateMesh.new()
	_highlight.mesh = wire
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.05, 0.05, 0.05, 0.75)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.no_depth_test = false
	_highlight.material_override = line_material
	add_child(_highlight)

	# Crack overlay for the block being mined.
	_crack = MeshInstance3D.new()
	_crack.name = "Crack"
	var crack_mesh := BoxMesh.new()
	crack_mesh.size = Vector3(1.02, 1.02, 1.02)
	var crack_material := StandardMaterial3D.new()
	crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_material.albedo_color = Color(1, 1, 1, 1)
	crack_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crack.material_override = crack_material
	_crack.mesh = crack_mesh
	_crack.visible = false
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)

	# Simple drop shadow, cheap stand-in for a real player model in first person.
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	quad.orientation = PlaneMesh.FACE_Y
	var shadow_material := StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_color = Color(0, 0, 0, 0.28)
	quad.material = shadow_material
	_shadow.mesh = quad
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	var ui_blocking: bool = get_tree().get_first_node_in_group("ui_blocking") != null
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ui_blocking:
		var motion := event as InputEventMouseMotion
		var sensitivity: float = float(Settings.get_value("sensitivity")) * 1.6
		var invert: float = -1.0 if bool(Settings.get_value("invert_y")) else 1.0
		_yaw -= motion.relative.x * sensitivity
		_pitch -= motion.relative.y * sensitivity * invert
		_pitch = clampf(_pitch, -PI * 0.495, PI * 0.495)
		return
	if event is InputEventMouseButton and not ui_blocking:
		var button := event as InputEventMouseButton
		if button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_play_time += delta
	_hurt_time = maxf(0.0, _hurt_time - delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	_use_cooldown = maxf(0.0, _use_cooldown - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_auto_jump_cooldown = maxf(0.0, _auto_jump_cooldown - delta)
	if is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return
	_update_camera(delta)
	_update_highlight()
	_update_held_item()
	_tick_survival(delta)
	_handle_hotbar_input()
	_handle_actions(delta)
	if world != null and world.day_night != null:
		_update_ambience()


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	_check_liquid()
	var input_direction: Vector2 = _input_vector()
	_sneaking = Input.is_action_pressed("sneak") and not flying
	var want_sprint: bool = Input.is_action_pressed("sprint") and not _sneaking \
		and input_direction.length() > 0.1
	_sprinting = want_sprint and (gamemode == "creative" or hunger > 6.0)

	if flying:
		_fly_physics(delta, input_direction)
	elif _underwater or _in_lava:
		_swim_physics(delta, input_direction)
	else:
		_walk_physics(delta, input_direction)

	move_and_slide()
	_track_fall()
	_play_step_sounds(delta)
	if _auto_jump_cooldown <= 0.0 and bool(Settings.get_value("auto_jump")) and is_on_floor() \
			and input_direction.length() > 0.1 and _blocked_ahead(input_direction):
		velocity.y = JUMP_VELOCITY * 0.85
		_auto_jump_cooldown = 0.35


func _input_vector() -> Vector2:
	var vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if vector.length() > 1.0:
		vector = vector.normalized()
	return vector


func _walk_physics(delta: float, input_direction: Vector2) -> void:
	velocity.y -= 26.0 * delta
	var basis_forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var basis_right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var direction: Vector3 = (basis_right * input_direction.x + basis_forward * input_direction.y)
	var speed: float = WALK_SPEED
	if _sprinting:
		speed = SPRINT_SPEED
	elif _sneaking:
		speed = SNEAK_SPEED
	if not is_on_floor():
		speed *= 0.82
	# Sneak edge protection: stop at the edge of a block unless jumping.
	if _sneaking and is_on_floor() and direction.length() > 0.01:
		var probe: Vector3 = global_position + direction.normalized() * 0.45 + Vector3(0, 0.1, 0)
		var foot := Vector3i(floori(probe.x), floori(probe.y) - 1, floori(probe.z))
		if not world.is_solid(foot) and not world.is_solid(foot + Vector3i(0, 1, 0)):
			direction *= 0.0
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_step_sound(1.0, "step_grass")
	# Ladders climb
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.5),
		floori(global_position.z))
	var ladder_id: int = world.get_block(feet)
	if ladder_id != Blocks.AIR and Blocks.def(ladder_id).climbable:
		velocity.y = CLIMB_SPEED if input_direction.y < 0.0 or Input.is_action_pressed("jump") \
			else (-CLIMB_SPEED if input_direction.y > 0.0 else 0.0)


func _swim_physics(delta: float, input_direction: Vector2) -> void:
	var basis_forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var basis_right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var direction: Vector3 = (basis_right * input_direction.x + basis_forward * input_direction.y)
	velocity.x = direction.x * SWIM_SPEED
	velocity.z = direction.z * SWIM_SPEED
	var buoyancy: float = 6.0 if _underwater else 14.0
	if _in_lava:
		buoyancy = 3.0
		velocity.y = maxf(velocity.y - 14.0 * delta, -1.6)
	velocity.y += buoyancy * delta
	velocity.y = clampf(velocity.y, -6.0, 5.0)
	if Input.is_action_pressed("jump"):
		velocity.y = SWIM_SPEED
	if Input.is_action_pressed("sneak"):
		velocity.y = -SWIM_SPEED
	if _underwater and _sprinting:
		velocity.x *= 1.2
		velocity.z *= 1.2
	if _swimming_motion(direction) and randf() < delta * 2.0:
		AudioManager.play_3d("swim", global_position, self, -8.0)


func _swimming_motion(direction: Vector3) -> bool:
	return direction.length() > 0.1


func _fly_physics(delta: float, input_direction: Vector2) -> void:
	var pitch_basis: Basis = Basis(Vector3.RIGHT, _pitch)
	var yaw_basis: Basis = Basis(Vector3.UP, _yaw)
	var look_direction: Vector3 = (pitch_basis * yaw_basis).z
	var basis_forward: Vector3 = look_direction
	var basis_right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var direction: Vector3 = basis_right * input_direction.x + basis_forward * input_direction.y
	var vertical: float = 0.0
	if Input.is_action_pressed("jump"):
		vertical += 1.0
	if Input.is_action_pressed("sneak"):
		vertical -= 1.0
	if vertical != 0.0:
		direction += Vector3(0, vertical, 0)
	var speed: float = CREATIVE_FLY_SPEED
	if _sprinting:
		speed *= 1.9
	if Input.is_action_pressed("sprint") and Input.is_action_pressed("jump"):
		speed *= 2.0
	velocity = direction.normalized() * speed if direction.length() > 0.01 else Vector3.ZERO


func _blocked_ahead(input_direction: Vector2) -> bool:
	var basis_forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var basis_right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var direction: Vector3 = (basis_right * input_direction.x + basis_forward * input_direction.y).normalized()
	var ahead: Vector3 = global_position + direction * 0.55 + Vector3(0, 0.2, 0)
	var voxel := Vector3i(floori(ahead.x), floori(ahead.y), floori(ahead.z))
	return world.is_solid(voxel) or world.is_solid(voxel + Vector3i(0, 1, 0))


func _track_fall() -> void:
	if is_on_floor():
		if _fall_start_y - global_position.y > 4.0 and _air_time > 0.2:
			var fall: float = _fall_start_y - global_position.y
			var damage: float = floorf(fall - 3.0)
			if damage > 0.0:
				take_damage(damage, "fall")
				AudioManager.play_3d("break_block", global_position, self, -3.0, 0.7)
		_fall_start_y = global_position.y
		_air_time = 0.0
	else:
		_air_time += get_physics_process_delta_time()
		_fall_start_y = maxf(_fall_start_y, global_position.y)


func _check_liquid() -> void:
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.4),
		floori(global_position.z))
	var head := Vector3i(floori(global_position.x), floori(global_position.y + EYE_HEIGHT),
		floori(global_position.z))
	_underwater = world.is_liquid(head)
	_in_lava = world.get_block(feet) == Blocks.LAVA or world.get_block(head) == Blocks.LAVA
	if _in_lava:
		take_damage(4.0 * get_physics_process_delta_time() * 2.0, "lava")


func _play_step_sounds(delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.6:
		return
	_step_timer -= delta * horizontal_speed
	if _step_timer > 0.0:
		return
	_step_timer = 2.1
	var below := Vector3i(floori(global_position.x), floori(global_position.y) - 1,
		floori(global_position.z))
	var block_id: int = world.get_block(below)
	if block_id == Blocks.AIR:
		return
	var sound_name: String = str(Registry.STEP_SOUNDS.get(Blocks.sound_of[block_id], "step_stone"))
	AudioManager.play_3d(sound_name, global_position, self, -10.0, randf_range(0.85, 1.15))
	if _sprinting and Settings.get_value("particles"):
		_sprint_particle_timer -= delta
		if _sprint_particle_timer <= 0.0:
			_sprint_particle_timer = 0.35
			if world != null:
				world.spawn_particles(global_position, "smoke", 2)


func _play_step_sound(volume: float, sound_name: String) -> void:
	AudioManager.play_3d(sound_name, global_position, self, -6.0 * (1.0 - volume) - 6.0)


# ---------------------------------------------------------------------------
# Camera & view
# ---------------------------------------------------------------------------


func _update_camera(delta: float) -> void:
	rotation.y = _yaw
	_camera.rotation.x = _pitch
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_view_bob_time += delta * speed
	var bob_enabled: bool = bool(Settings.get_value("view_bobbing"))
	var bob: float = sin(_view_bob_time * 1.6) * 0.045 * minf(speed / SPRINT_SPEED, 1.2) if bob_enabled else 0.0
	_bob_amount = lerpf(_bob_amount, bob, clampf(delta * 8.0, 0.0, 1.0))
	var hurt_shake: float = sin(_hurt_time * 40.0) * _hurt_time * 0.06
	var eye: float = EYE_HEIGHT
	if _sneaking:
		eye -= 0.18
	var position_y: float = eye + _bob_amount
	_camera.position.x = cos(_view_bob_time * 0.8) * 0.03 * minf(speed / SPRINT_SPEED, 1.0) \
		if bob_enabled else 0.0
	_camera.position.y = position_y
	_camera.position.z = hurt_shake * 0.3
	_camera.rotation.z = hurt_shake
	# Sprinting widens the FOV a little.
	var target_fov: float = float(Settings.get_value("fov")) * (1.06 if _sprinting else 1.0)
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * 6.0, 0.0, 1.0))
	_shadow.visible = not third_person
	if _shadow.visible:
		_shadow.global_position = Vector3(global_position.x,
			floorf(global_position.y) + 0.02, global_position.z)


func _update_highlight() -> void:
	var result: Dictionary = raycast_target() if world != null else {"hit": false}
	var mesh: ImmediateMesh = _highlight.mesh
	mesh.clear_surfaces()
	if not bool(result.get("hit", false)):
		_highlight_block = Vector3i(9999, 9999, 9999)
		return
	var position: Vector3i = result["position"]
	_highlight_block = position
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var min_corner := Vector3(0.002, 0.002, 0.002)
	var max_corner := Vector3(0.998, 0.998, 0.998)
	var corners: Array[Vector3] = [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
	]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7]]
	for edge in edges:
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()
	_highlight.position = Vector3(position) + Vector3(0.0, 0.0, 0.0)


func _update_held_item() -> void:
	var item_id: int = held_item()
	var texture: Texture2D = Registry.icon(item_id) if item_id >= 0 else null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if texture != null else BaseMaterial3D.CULL_BACK
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh.material = material
	_held_mesh.mesh = mesh
	_arm_pivot.visible = not third_person and item_id >= 0
	# Swing animation on use/attack.
	var swing: float = clampf(_attack_cooldown / 0.25, 0.0, 1.0)
	_held_mesh.rotation_degrees = Vector3(-16.0 - swing * 45.0, -24.0, -6.0)
	_held_mesh.position = Vector3(0.42, -0.38 - swing * 0.12, -0.62 + swing * 0.1)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------


func _handle_hotbar_input() -> void:
	for index in 9:
		if Input.is_action_just_pressed("hotbar_%d" % (index + 1)):
			hotbar_index = index
			stats_changed.emit()
			AudioManager.play_ui()


func _handle_actions(delta: float) -> void:
	if world == null:
		return
	var ui_blocking: bool = get_tree().get_first_node_in_group("ui_blocking") != null
	if ui_blocking:
		_attack_held = false
		_use_held = false
		_crack.visible = false
		return
	_attack_held = Input.is_action_pressed("attack")
	_use_held = Input.is_action_pressed("use")
	if Input.is_action_just_pressed("drop_item"):
		drop_held_item()
	if Input.is_action_just_pressed("pick_block"):
		_pick_block()
	if Input.is_action_just_pressed("toggle_fly") and gamemode == "creative":
		flying = not flying
		velocity = Vector3.ZERO
		AudioManager.play_ui()
	if Input.is_action_just_pressed("toggle_perspective"):
		third_person = not third_person
		_camera.position.z = 4.0 if third_person else 0.0

	if _attack_held:
		_mine(delta)
	else:
		_mining_progress = 0.0
		_crack.visible = false
		_mining_position = Vector3i(9999, 9999, 9999)
	if _use_held:
		_use(delta)
	else:
		_eat_timer = 0.0
		_bow_charge = 0.0


## Distance/position of the block or entity the player is looking at.
func look_yaw() -> float:
	return _yaw


func look_pitch() -> float:
	return _pitch


## Touch controls feed look deltas directly instead of mouse motion events.
func add_look_delta(delta: Vector2) -> void:
	_yaw -= delta.x * 0.006
	_pitch -= delta.y * 0.006
	_pitch = clampf(_pitch, -PI * 0.495, PI * 0.495)


func is_underwater() -> bool:
	return _underwater


func raycast_target() -> Dictionary:
	if world == null:
		return {"hit": false}
	var origin: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_transform.basis.z
	# Entities first, so attacking mobs feels responsive.
	var closest_mob: Node3D = null
	var closest_distance: float = REACH
	for mob in get_tree().get_nodes_in_group("mob"):
		if not (mob is Node3D):
			continue
		var to_mob: Vector3 = (mob as Node3D).global_position + Vector3(0, 0.8, 0) - origin
		var distance: float = to_mob.length()
		if distance > REACH:
			continue
		var angle: float = rad_to_deg(acos(clampf(direction.normalized().dot(to_mob.normalized()),
			-1.0, 1.0)))
		var radius_degrees: float = rad_to_deg(atan2(0.75, maxf(distance, 0.1)))
		if angle <= radius_degrees and distance < closest_distance:
			closest_distance = distance
			closest_mob = mob as Node3D
	var block_hit: Dictionary = world.raycast(origin, direction, REACH)
	if closest_mob != null and (not bool(block_hit.get("hit", false))
			or float(block_hit.get("distance", 99.0)) > closest_distance):
		return {"hit": true, "mob": closest_mob, "distance": closest_distance}
	return block_hit


func _mine(delta: float) -> void:
	var target: Dictionary = raycast_target()
	if not bool(target.get("hit", false)):
		_mining_progress = 0.0
		_crack.visible = false
		return
	if target.has("mob"):
		_attack_mob(target["mob"])
		return
	var position: Vector3i = target["position"]
	var block_id: int = int(target["block"])
	if gamemode == "creative":
		world.break_block(position, held_item(), true)
		_mining_progress = 0.0
		AudioManager.play_3d("break_block", Vector3(position) + Vector3(0.5, 0.5, 0.5), self, -3.0)
		_attack_cooldown = 0.25
		return
	if position != _mining_position:
		_mining_position = position
		_mining_progress = 0.0
		_mining_total = Blocks.break_time(block_id, Items.name_of(held_item()),
			Items.tool_tier(held_item()), Items.tool_speed(held_item()))
	var definition := Blocks.def(block_id)
	if definition.hardness < 0.0:
		return
	_mining_progress += delta
	_attack_cooldown = 0.25
	# Mining progress feedback: crack overlay + dig sound.
	var stage: int = clampi(int(_mining_progress / maxf(0.001, _mining_total) * 10.0), 0, 9)
	if not Registry.break_stages.is_empty():
		var material := _crack.material_override as StandardMaterial3D
		if material != null:
			material.albedo_texture = Registry.break_stages[stage]
	_crack.position = Vector3(position) + Vector3(0.5, 0.5, 0.5)
	_crack.visible = true
	if fmod(_mining_progress, 0.24) < delta:
		AudioManager.play_3d(Registry.dig_sound(block_id), Vector3(position) + Vector3(0.5, 0.5, 0.5),
			self, -12.0, randf_range(0.85, 1.15))
	if Settings.get_value("particles") and fmod(_mining_progress, 0.4) < delta:
		world.spawn_particles(Vector3(position) + Vector3(0.5, 0.5, 0.5), "block_break", 4)
	if _mining_progress >= _mining_total:
		_mining_progress = 0.0
		_crack.visible = false
		var broken: bool = world.break_block(position, held_item(), true)
		if broken:
			AudioManager.play_3d(Registry.dig_sound(block_id), Vector3(position) + Vector3(0.5, 0.5, 0.5),
				self, -3.0, randf_range(0.9, 1.1))
			_damage_tool()


func _attack_mob(mob: Node3D) -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.4
	var item_id: int = held_item()
	var damage: float = Items.attack_damage(item_id)
	if mob.has_method("take_damage"):
		mob.take_damage(damage, "player")
	AudioManager.play_3d("hurt", mob.global_position, self, -6.0, 0.8)
	if Settings.get_value("particles"):
		world.spawn_particles(mob.global_position + Vector3(0.0, 1.0, 0.0), "critical", 4)
	if Items.durability(item_id) > 0:
		_damage_tool(1)


func _use(delta: float) -> void:
	var target: Dictionary = raycast_target()
	var item_id: int = held_item()
	var item := Items.def_of(item_id)
	# Entities come first: feeding, shearing, taming and villager trading.
	if bool(target.get("hit", false)) and target.has("mob") and _use_cooldown <= 0.0:
		var mob: Node = target["mob"]
		if mob.has_method("interact"):
			_use_cooldown = 0.3
			if mob.interact(self, item_id):
				_consume_held(1)
				inventory_changed.emit()
				return
	if item == null:
		return
	if item.is_food() and (hunger < MAX_HUNGER or item.always_edible):
		_eat(delta)
		return
	if item.name == "bow":
		_charge_bow(delta)
		return
	if item.name == "bucket":
		_use_bucket(target)
		return
	if item.name == "water_bucket" or item.name == "lava_bucket":
		_place_liquid(target, item.name)
		return
	if not bool(target.get("hit", false)) or target.has("mob"):
		return
	var position: Vector3i = target["position"]
	var block_id: int = int(target["block"])
	var container_kind: String = Blocks.container_kind(block_id)
	if container_kind != "" and _use_cooldown <= 0.0:
		_use_cooldown = 0.3
		_open_container(position)
		return
	var crafting: String = Blocks.crafting_kind(block_id)
	if crafting != "" and _use_cooldown <= 0.0:
		_use_cooldown = 0.3
		open_crafting_screen.emit("table")
		return
	if Blocks.name_of(block_id) == "lever" and _use_cooldown <= 0.0:
		_use_cooldown = 0.25
		if world.redstone != null:
			world.redstone.toggle_lever(position)
		return
	if Blocks.name_of(block_id) == "tnt" and _use_cooldown <= 0.0:
		if item.name == "flint_and_steel":
			_ignite_tnt(position)
		return
	# Flint and steel: light furnaces, TNT or a fire block when the world has one.
	if item.name == "flint_and_steel":
		if _use_cooldown <= 0.0:
			_use_cooldown = 0.4
			if block_id == Blocks.FURNACE:
				world.set_block(position, Blocks.FURNACE_LIT, world.get_block_meta(position))
				_damage_tool(1)
				AudioManager.play_3d("fuse", Vector3(position) + Vector3(0.5, 0.5, 0.5), self, -4.0)
				return
			var fire_id: int = Blocks.id("fire")
			var above: Vector3i = position + Vector3i(0, 1, 0)
			if fire_id > 0 and world.get_block(above) == Blocks.AIR \
					and world.get_block(position) != Blocks.AIR:
				world.set_block(above, fire_id)
				_damage_tool(1)
				return
			_try_ignite_neighbours(position)
		return
	# Hoes turn dirt/grass into farmland.
	if item.tool_kind == "hoe" and _use_cooldown <= 0.0:
		if block_id == Blocks.GRASS or block_id == Blocks.DIRT:
			if world.get_block(position + Vector3i(0, 1, 0)) == Blocks.AIR:
				_use_cooldown = 0.3
				world.set_block(position, Blocks.FARMLAND)
				AudioManager.play_3d("step_grass", Vector3(position) + Vector3(0.5, 1.0, 0.5),
					self, -6.0)
				_damage_tool(1)
				return
	if item.name in ["wheat_seeds", "carrot", "potato"] and _use_cooldown <= 0.0:
		var above: Vector3i = position + Vector3i(0, 1, 0)
		if block_id == Blocks.FARMLAND and world.get_block(above) == Blocks.AIR:
			var crop: String = {"wheat_seeds": "wheat", "carrot": "carrots",
				"potato": "potatoes"}[item.name]
			_use_cooldown = 0.25
			world.set_block(above, Blocks.id(crop), 0)
			if Blocks.id(crop) != Blocks.AIR:
				_consume_held(1)
			return
	if item.name == "bone_meal" and _use_cooldown <= 0.0:
		var definition := Blocks.def(block_id)
		if definition.harvest != "":
			var meta: int = world.get_block_meta(position)
			if meta < 7:
				_use_cooldown = 0.3
				world.set_block(position, block_id, mini(7, meta + randi_range(1, 3)))
				_consume_held(1)
				if Settings.get_value("particles"):
					world.spawn_particles(Vector3(position) + Vector3(0.5, 0.8, 0.5), "heart", 3)
		return
	# Place a block.
	if Items.is_placeable(item_id) and _place_cooldown <= 0.0:
		_place_block(position, target.get("normal", Vector3i.UP), Items.places_block(item_id))


## Lights any TNT touching the given block (used by flint and steel).
func _try_ignite_neighbours(position: Vector3i) -> void:
	for offset in [Vector3i.ZERO, Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if world.get_block(position + offset) == Blocks.id("tnt"):
			_ignite_tnt(position + offset)
			return
	if _use_cooldown > 0.0:
		_use_cooldown = 0.0
		AudioManager.play_ui()


func _ignite_tnt(position: Vector3i) -> void:
	_use_cooldown = 0.4
	world.set_block(position, Blocks.AIR)
	var tnt := PrimedTnt.new()
	tnt.position = Vector3(position) + Vector3(0.5, 0.2, 0.5)
	world.add_child(tnt)
	_damage_tool(1)


func _place_block(hit_position: Vector3i, normal: Vector3i, block_id: int) -> void:
	var target: Vector3i = hit_position + normal
	if world.get_block(target) == Blocks.AIR or Blocks.is_replaceable(world.get_block(target)):
		pass
	else:
		target = hit_position
	# Do not place inside the player.
	var player_voxel := Vector3i(floori(global_position.x), floori(global_position.y),
		floori(global_position.z))
	if target == player_voxel or target == Vector3i(player_voxel.x, player_voxel.y + 1, player_voxel.z):
		return
	var facing: int = _facing_from_normal(normal, true)
	if not world.place_block(target, block_id, facing):
		return
	_place_cooldown = 0.18
	AudioManager.play_3d("place_block", Vector3(target) + Vector3(0.5, 0.5, 0.5), self, -8.0,
		randf_range(0.9, 1.05))
	_consume_held(1)


## Torches/ladders attach to the clicked face; pistons/furnaces face the player.
static func _facing_from_normal(normal: Vector3i, from_block: bool) -> int:
	if normal == Vector3i(1, 0, 0):
		return 0
	if normal == Vector3i(-1, 0, 0):
		return 1
	if normal == Vector3i(0, 0, 1):
		return 2
	if normal == Vector3i(0, 0, -1):
		return 3
	if normal == Vector3i(0, 1, 0):
		return 4
	return 5


func _open_container(position: Vector3i) -> void:
	var container: BlockContainer = world.get_container(position)
	if container == null:
		return
	open_container_screen.emit(container, position)
	AudioManager.play_3d("click", Vector3(position) + Vector3(0.5, 0.5, 0.5), self, -8.0)


func _eat(delta: float) -> void:
	var item_id: int = held_item()
	var item := Items.def_of(item_id)
	if item == null or item.hunger <= 0:
		return
	_eat_timer += delta
	if fmod(_eat_timer, 0.25) < delta:
		AudioManager.play_3d("eat", global_position, self, -10.0, randf_range(0.9, 1.2))
	if _eat_timer >= item.eat_time:
		_eat_timer = 0.0
		hunger = minf(MAX_HUNGER, hunger + float(item.hunger))
		saturation = minf(MAX_HUNGER, saturation + item.saturation)
		if item.heal_amount > 0.0:
			health = minf(MAX_HEALTH, health + item.heal_amount)
		_consume_held(1)
		stats_changed.emit()
		AudioManager.play_3d("level_up", global_position, self, -12.0)


func _charge_bow(delta: float) -> void:
	_bow_charge = minf(1.0, _bow_charge + delta * 1.2)
	if _bow_charge >= 1.0:
		var arrows: int = inventory.count_of(Items.id("arrow"))
		if arrows <= 0:
			return
		_consume_item(Items.id("arrow"), 1)
		var arrow := Arrow.new()
		arrow.position = _camera.global_position - _camera.global_transform.basis.z * 0.6
		var speed: float = 34.0 + _bow_charge * 14.0
		arrow.velocity = -_camera.global_transform.basis.z * speed
		arrow.damage = 4.0 + _bow_charge * 4.0
		arrow.owner_is_player = true
		world.add_child(arrow)
		AudioManager.play_3d("bow_shoot", global_position, self, -4.0)
		_bow_charge = 0.0
		_damage_tool(1)


func _use_bucket(target: Dictionary) -> void:
	if not bool(target.get("hit", false)) or target.has("mob"):
		return
	var position: Vector3i = target["position"]
	var block_id: int = int(target["block"])
	if Blocks.is_liquid(block_id):
		var item_name: String = "water_bucket" if block_id == Blocks.WATER else "lava_bucket"
		world.set_block(position, Blocks.AIR)
		_consume_held(1)
		give_item(Items.id(item_name), 1)
		AudioManager.play_3d("splash", Vector3(position) + Vector3(0.5, 0.5, 0.5), self, -4.0)
		return
	# Fill from a nearby source block.
	for offset in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1)]:
		var probe: Vector3i = position + offset
		var probe_id: int = world.get_block(probe)
		if Blocks.is_liquid(probe_id):
			var item_name: String = "water_bucket" if probe_id == Blocks.WATER else "lava_bucket"
			world.set_block(probe, Blocks.AIR)
			_consume_held(1)
			give_item(Items.id(item_name), 1)
			AudioManager.play_3d("splash", global_position, self, -4.0)
			return


func _place_liquid(target: Dictionary, item_name: String) -> void:
	if _place_cooldown > 0.0:
		return
	var position: Vector3i = Vector3i(floori(global_position.x), floori(global_position.y),
		floori(global_position.z))
	if bool(target.get("hit", false)) and not target.has("mob"):
		var hit: Vector3i = target["position"]
		var normal: Vector3i = target.get("normal", Vector3i.UP)
		var candidate: Vector3i = hit + normal
		if world.get_block(candidate) == Blocks.AIR or Blocks.is_replaceable(world.get_block(candidate)):
			position = candidate
	if world.get_block(position) != Blocks.AIR and not Blocks.is_replaceable(world.get_block(position)):
		return
	var block_id: int = Blocks.WATER if item_name == "water_bucket" else Blocks.LAVA
	world.set_block(position, block_id, 7)
	_place_cooldown = 0.3
	_consume_held(1)
	give_item(Items.id("bucket"), 1)
	AudioManager.play_3d("splash", Vector3(position) + Vector3(0.5, 0.5, 0.5), self, -4.0)


# ---------------------------------------------------------------------------
# Inventory helpers
# ---------------------------------------------------------------------------


func held_item() -> int:
	var stack: Variant = inventory.get_slot(hotbar_index)
	if stack == null:
		return -1
	return int(stack["id"])


func held_item_name() -> String:
	var item_id: int = held_item()
	return Items.name_of(item_id) if item_id >= 0 else ""


func held_stack() -> Variant:
	return inventory.get_slot(hotbar_index)


func give_item(item_id: int, count: int, durability: int = 0) -> int:
	if item_id < 0:
		return 0
	var leftover: int = inventory.add(item_id, count, durability)
	var accepted: int = count - leftover
	if accepted > 0:
		inventory_changed.emit()
		stats_changed.emit()
	return accepted


func give_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed_for_level() and level < 100:
		xp -= xp_needed_for_level()
		level += 1
		AudioManager.play("level_up", -4.0)
	stats_changed.emit()


func xp_needed_for_level() -> int:
	return 7 + level * 3


func total_armor_points() -> int:
	var total: int = 0
	for index in ARMOR_SLOTS:
		var stack: Variant = armor.get_slot(index)
		if stack == null:
			continue
		var item := Items.def_of(int(stack["id"]))
		if item != null:
			total += item.armor_points
	# Durability damage reduces protection slightly.
	return total


func drop_held_item() -> void:
	var stack: Variant = inventory.get_slot(hotbar_index)
	if stack == null:
		return
	var item_id: int = int(stack["id"])
	var count: int = int(stack["count"])
	var durability: int = int(stack.get("durability", 0))
	inventory.set_slot(hotbar_index, null)
	inventory_changed.emit()
	_spawn_drop(item_id, count, durability)


func _spawn_drop(item_id: int, count: int, durability: int) -> void:
	if world == null:
		return
	var direction: Vector3 = -_camera.global_transform.basis.z
	var position: Vector3 = _camera.global_position + direction * 0.6
	var drop := ItemDrop.new()
	drop.item_id = item_id
	drop.count = count
	drop.durability = durability
	drop.position = position
	drop.linear_velocity = direction * 6.0 + Vector3(0, 2.0, 0)
	world.add_child(drop)
	item_dropped.emit(item_id, count)


func _pick_block() -> void:
	var target: Dictionary = raycast_target()
	if not bool(target.get("hit", false)) or target.has("mob"):
		return
	var block_id: int = int(target["block"])
	give_item(block_id, 1)


func _consume_held(amount: int = 1) -> void:
	var stack: Variant = inventory.get_slot(hotbar_index)
	if stack == null:
		return
	stack["count"] = int(stack["count"]) - amount
	inventory.set_slot(hotbar_index, stack)
	inventory_changed.emit()
	stats_changed.emit()


func _consume_item(item_id: int, amount: int) -> void:
	inventory.remove(item_id, amount)
	inventory_changed.emit()


## Tool durability: tools wear out and break with a sound.
func _damage_tool(amount: int = 1) -> void:
	var stack: Variant = inventory.get_slot(hotbar_index)
	if stack == null:
		return
	var item := Items.def_of(int(stack["id"]))
	if item == null or item.durability <= 0:
		return
	var durability: int = int(stack.get("durability", item.durability)) - amount
	if durability <= 0:
		inventory.set_slot(hotbar_index, null)
		AudioManager.play_3d("break_block", global_position, self, -2.0, 1.4)
		inventory_changed.emit()
		return
	stack["durability"] = durability
	inventory.set_slot(hotbar_index, stack)


# ---------------------------------------------------------------------------
# Survival
# ---------------------------------------------------------------------------


func _tick_survival(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < 0.5:
		return
	var step: float = _tick_timer
	_tick_timer = 0.0
	if gamemode == "creative":
		health = MAX_HEALTH
		hunger = MAX_HUNGER
		breath = MAX_BREATH
		return
	# Hunger drains with activity.
	var drain: float = 0.008 * step
	if _sprinting:
		drain *= 3.0
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		drain *= 1.5
	exhaustion += drain
	while exhaustion >= 4.0:
		exhaustion -= 4.0
		if saturation > 0.0:
			saturation = maxf(0.0, saturation - 1.0)
		else:
			hunger = maxf(0.0, hunger - 1.0)
			stats_changed.emit()
	# Regeneration / starvation.
	if hunger >= 18.0 and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + step * 0.6)
		exhaustion += step * 0.6
		stats_changed.emit()
	elif hunger <= 0.0:
		take_damage(step * 0.5, "starving")
	# Breath while submerged.
	if _underwater:
		_submerged_timer += step
		breath = maxf(0.0, MAX_BREATH - _submerged_timer)
		if breath <= 0.0:
			take_damage(step * 2.0, "drowning")
		stats_changed.emit()
	else:
		_submerged_timer = 0.0
		if breath < MAX_BREATH:
			breath = minf(MAX_BREATH, breath + step * 3.0)
			stats_changed.emit()


func take_damage(amount: float, source: String = "") -> void:
	if is_dead or gamemode == "creative":
		return
	var armor_points: int = total_armor_points()
	var reduction: float = clampf(float(armor_points) * 0.04, 0.0, 0.8)
	var final_amount: float = amount * (1.0 - reduction)
	health -= final_amount
	_hurt_time = minf(0.6, 0.25 + final_amount * 0.03)
	_last_damage_source = source
	if amount >= 1.0:
		AudioManager.play("hurt", -4.0, randf_range(0.9, 1.1))
		# Armour takes durability damage.
		for index in ARMOR_SLOTS:
			var stack: Variant = armor.get_slot(index)
			if stack == null:
				continue
			var item := Items.def_of(int(stack["id"]))
			if item == null or item.durability <= 0:
				continue
			var durability: int = int(stack.get("durability", item.durability)) - 1
			if durability <= 0:
				armor.set_slot(index, null)
			else:
				stack["durability"] = durability
				armor.set_slot(index, stack)
	stats_changed.emit()
	if health <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	_respawn_timer = RESPAWN_DELAY
	velocity = Vector3.ZERO
	AudioManager.play("death", 0.0)
	if Settings.get_value("particles") and world != null:
		world.spawn_particles(global_position + Vector3(0.0, 1.0, 0.0), "smoke", 12)
	if not bool(Settings.get_value("keep_inventory")):
		_drop_all_items()
	died.emit()


func _drop_all_items() -> void:
	for index in inventory.size():
		var stack: Variant = inventory.get_slot(index)
		if stack != null:
			_spawn_drop(int(stack["id"]), int(stack["count"]), int(stack.get("durability", 0)))
			inventory.set_slot(index, null)
	for index in ARMOR_SLOTS:
		var stack: Variant = armor.get_slot(index)
		if stack != null:
			_spawn_drop(int(stack["id"]), 1, int(stack.get("durability", 0)))
			armor.set_slot(index, null)
	inventory_changed.emit()


func respawn() -> void:
	is_dead = false
	health = MAX_HEALTH
	hunger = MAX_HUNGER
	saturation = 5.0
	exhaustion = 0.0
	breath = MAX_BREATH
	flying = false
	if world != null:
		var spawn: Vector3 = world.get_spawn_position()
		global_position = spawn
		velocity = Vector3.ZERO
	respawned.emit()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Ambience
# ---------------------------------------------------------------------------


func _update_ambience() -> void:
	var night: bool = world.day_night.is_night()
	var underground: bool = false
	var head := Vector3i(floori(global_position.x), floori(global_position.y + 2.0),
		floori(global_position.z))
	if world.get_sky_light(head) < 7:
		underground = true
	var track: String = "music_day"
	if underground:
		track = "music_cave"
	elif night:
		track = "music_night"
	if AudioManager.current_music() != track:
		AudioManager.play_music(track, 3.0)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func serialize() -> Dictionary:
	var items: Array = []
	for index in inventory.size():
		var stack: Variant = inventory.get_slot(index)
		if stack == null:
			items.append({})
		else:
			items.append({
				"item": Items.name_of(int(stack["id"])),
				"count": int(stack["count"]),
				"durability": int(stack.get("durability", 0)),
			})
	var armor_items: Array = []
	for index in ARMOR_SLOTS:
		var stack: Variant = armor.get_slot(index)
		if stack == null:
			armor_items.append({})
		else:
			armor_items.append({
				"item": Items.name_of(int(stack["id"])),
				"count": 1,
				"durability": int(stack.get("durability", 0)),
			})
	return {
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"yaw": _yaw, "pitch": _pitch, "health": health, "hunger": hunger,
		"saturation": saturation, "xp": xp, "level": level, "gamemode": gamemode,
		"hotbar": hotbar_index, "flying": flying, "inventory": items, "armor": armor_items,
		"play_time": _play_time,
	}


func apply_state(state: Dictionary) -> void:
	global_position = Vector3(float(state.get("x", 0.0)), float(state.get("y", 80.0)),
		float(state.get("z", 0.0)))
	_yaw = float(state.get("yaw", 0.0))
	_pitch = float(state.get("pitch", 0.0))
	health = float(state.get("health", MAX_HEALTH))
	hunger = float(state.get("hunger", MAX_HUNGER))
	saturation = float(state.get("saturation", 5.0))
	xp = int(state.get("xp", 0))
	level = int(state.get("level", 0))
	hotbar_index = clampi(int(state.get("hotbar", 0)), 0, HOTBAR_SIZE - 1)
	flying = bool(state.get("flying", false)) and gamemode == "creative"
	_play_time = float(state.get("play_time", 0.0))
	_restore_items(state.get("inventory", []), inventory)
	_restore_items(state.get("armor", []), armor)
	inventory_changed.emit()
	stats_changed.emit()


func _restore_items(data: Array, target: BlockContainer) -> void:
	for index in mini(data.size(), target.size()):
		var entry = data[index]
		if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
			continue
		var item_id: int = Items.id(str(entry.get("item", "")))
		if item_id < 0:
			continue
		target.set_slot(index, BlockContainer.make_stack(item_id, int(entry.get("count", 1)),
			int(entry.get("durability", 0))))
