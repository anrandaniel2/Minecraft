class_name WeatherSystem
extends Node3D

## Weather: clear, rain and thunderstorms.
##
## Weather follows the player (particles are repositioned each frame), drives a
## looping rain ambience, dims the sky while it rains, and occasionally strikes
## lightning that flashes the sun and rumbles a few seconds later.

signal weather_changed(state: String)

const STATE_CLEAR: String = "clear"
const STATE_RAIN: String = "rain"
const STATE_THUNDER: String = "thunder"
const RAIN_RADIUS: float = 22.0
const RAIN_HEIGHT: float = 14.0

var current: String = STATE_CLEAR
var time_left: float = 120.0
var world: World

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _lightning_timer: float = 0.0
var _flash: float = 0.0
var _rumble_pending: float = 0.0


func setup(world_ref: World) -> void:
	world = world_ref


func _ready() -> void:
	name = "Weather"
	add_to_group("weather")
	_build_particles()
	time_left = randf_range(90.0, 300.0)


func is_raining() -> bool:
	return current != STATE_CLEAR


func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		_roll_weather()
	var player: Node3D = _player()
	if player != null:
		var position: Vector3 = player.global_position
		if _rain != null:
			_rain.global_position = position + Vector3(0.0, RAIN_HEIGHT, 0.0)
		if _snow != null:
			_snow.global_position = position + Vector3(0.0, RAIN_HEIGHT, 0.0)
		_update_biome_precipitation(player.global_position)

	# Lightning
	if current == STATE_THUNDER and player != null:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_strike(player.global_position)
	if _rumble_pending > 0.0:
		_rumble_pending -= delta
		if _rumble_pending <= 0.0:
			AudioManager.play("thunder", -4.0, randf_range(0.85, 1.05))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		if world != null and world.day_night != null:
			world.day_night.sun.light_energy += _flash * 2.4


func _player() -> Node3D:
	if world == null:
		return null
	return world.player


func _roll_weather() -> void:
	var roll: float = randf()
	var next: String = STATE_CLEAR
	if roll < 0.42:
		next = STATE_CLEAR
	elif roll < 0.85:
		next = STATE_RAIN
	else:
		next = STATE_THUNDER
	set_weather(next)


func set_weather(state: String) -> void:
	current = state
	match state:
		STATE_RAIN:
			time_left = randf_range(60.0, 200.0)
		STATE_THUNDER:
			time_left = randf_range(45.0, 120.0)
			_lightning_timer = randf_range(4.0, 12.0)
		_:
			time_left = randf_range(180.0, 600.0)
	_apply_particles()
	weather_changed.emit(current)


func _update_biome_precipitation(player_position: Vector3) -> void:
	if world == null or not is_raining():
		return
	# Snow instead of rain in cold biomes.
	var biome: int = world.biome_at(floori(player_position.x), floori(player_position.z))
	var cold: bool = biome in [WorldGen.BIOME_TAIGA, WorldGen.BIOME_SNOWY, WorldGen.BIOME_MOUNTAINS]
	if _rain != null:
		_rain.emitting = not cold and is_raining()
	if _snow != null:
		_snow.emitting = cold and is_raining()


func _apply_particles() -> void:
	var raining: bool = is_raining()
	if _rain != null:
		_rain.emitting = raining
	if _snow != null:
		_snow.emitting = false
	AudioManager.set_ambience("rain_loop" if raining else "",
		-14.0 if current == STATE_RAIN else -8.0)


func _strike(origin: Vector3) -> void:
	_lightning_timer = randf_range(6.0, 20.0)
	_flash = 1.0
	_rumble_pending = randf_range(0.8, 2.5)
	var offset := Vector3(randf_range(-40.0, 40.0), 0.0, randf_range(-40.0, 40.0))
	var strike_position: Vector3 = origin + offset
	if world != null:
		# Lightning can set fire to the block it lands on.
		var ground_y: int = world.surface_height(floori(strike_position.x), floori(strike_position.z))
		var target := Vector3i(floori(strike_position.x), ground_y, floori(strike_position.z))
		world.spawn_particles(Vector3(target) + Vector3(0.5, 0.5, 0.5), "smoke", 24)


func _build_particles() -> void:
	_rain = _make_precipitation(
		"RainParticles", 900, Color(0.62, 0.72, 0.98, 0.5), Vector2(0.02, 0.4), Vector3(0, -26, 0), 1.0)
	_snow = _make_precipitation(
		"SnowParticles", 600, Color(1.0, 1.0, 1.0, 0.85), Vector2(0.05, 0.05), Vector3(0, -3.0, 0), 3.0)


func _make_precipitation(particle_name: String, amount: int, color: Color, size: Vector2,
		gravity: Vector3, drift: float) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(RAIN_RADIUS, 0.5, RAIN_RADIUS)
	process.direction = Vector3(drift * 0.15, -1.0, 0.0)
	process.spread = 4.0
	process.gravity = gravity
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.name = particle_name
	particles.amount = amount
	particles.lifetime = 1.4
	particles.emitting = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(
		Vector3(-RAIN_RADIUS, -RAIN_HEIGHT - 4.0, -RAIN_RADIUS),
		Vector3(RAIN_RADIUS * 2.0, RAIN_HEIGHT + 8.0, RAIN_RADIUS * 2.0))
	particles.local_coords = false
	add_child(particles)
	return particles
