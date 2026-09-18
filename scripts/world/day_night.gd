class_name DayNightCycle
extends Node

## Sky, sun, moon, stars, clouds and the day/night factor.
##
## time_of_day runs 0..1 (0 = midnight, 0.25 = sunrise, 0.5 = noon,
## 0.75 = sunset). The class owns the WorldEnvironment, the sun/moon light and a
## cloud layer, and reports a `day_factor` the terrain shader uses to blend
## skylight between night and day - so the time of day never rebuilds a mesh.

signal time_changed(time_of_day: float)

const DAY_LENGTH_SECONDS: float = 1200.0   # 20 real minutes per Minecraft day
const CLOUD_HEIGHT: float = 150.0

# Sky / light palettes
const DAY_SKY_TOP: Color = Color(0.24, 0.51, 0.94)
const DAY_SKY_HORIZON: Color = Color(0.66, 0.82, 0.98)
const NIGHT_SKY_TOP: Color = Color(0.04, 0.05, 0.18)
const NIGHT_SKY_HORIZON: Color = Color(0.16, 0.18, 0.38)
const SUNSET_HORIZON: Color = Color(0.98, 0.47, 0.22)
const SUNSET_TOP: Color = Color(0.36, 0.28, 0.52)
const SUN_COLOR_DAY: Color = Color(1.0, 0.97, 0.9)
const SUN_COLOR_LOW: Color = Color(1.0, 0.60, 0.32)
const MOON_COLOR: Color = Color(0.62, 0.70, 1.0)
const FOG_DAY: Color = Color(0.68, 0.80, 0.96)
const FOG_NIGHT: Color = Color(0.10, 0.12, 0.28)
const AMBIENT_DAY: Color = Color(0.80, 0.85, 0.94)
const AMBIENT_NIGHT: Color = Color(0.24, 0.28, 0.44)

@export var time_of_day: float = 0.32
@export var frozen: bool = false

var world: World
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var clouds: MeshInstance3D
var stars: MeshInstance3D
var _cloud_material: ShaderMaterial
var _day_factor: float = 1.0
var _queue_timer: float = 0.0


func _ready() -> void:
	name = "DayNightCycle"
	_build_environment()
	_build_clouds()
	_build_stars()
	_apply(0.0)


func setup(world_ref: World) -> void:
	world = world_ref


func _process(delta: float) -> void:
	if not frozen:
		var length: float = DAY_LENGTH_SECONDS / maxf(0.05, day_speed()) 
		time_of_day = fposmod(time_of_day + delta / length, 1.0)
	_apply(delta)
	_queue_timer += delta
	if _queue_timer > 1.0:
		_queue_timer = 0.0
		time_changed.emit(time_of_day)


## Difficulty/settings hook: creative worlds run a little faster by default.
## Jumps the clock, used by the `/time` command and by multiplayer sync.
func set_time(value: float) -> void:
	time_of_day = fposmod(value, 1.0)


func day_speed() -> float:
	return 1.0


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.25
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.85
	environment.ambient_light_energy = 1.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = FOG_DAY
	environment.fog_density = 0.0
	environment.fog_sky_affect = 0.4
	environment.fog_aerial_perspective = 0.3
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.ssao_enabled = false

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	# Phones get a tighter shadow box with two splits: much cheaper, and the
	# distance fog hides the shorter range anyway.
	var mobile: bool = OS.has_feature("mobile") or OS.has_feature("android") \
		or OS.has_feature("ios")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if mobile \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 48.0 if mobile else 90.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 1.2
	add_child(sun)


func _build_clouds() -> void:
	_cloud_material = ShaderMaterial.new()
	var shader := load("res://shaders/clouds.gdshader")
	if shader == null:
		return
	_cloud_material.shader = shader
	_cloud_material.set_shader_parameter("cloud_texture", Registry.ui("cloud"))
	_cloud_material.set_shader_parameter("scroll", Vector2(0.0, 0.0))
	_cloud_material.set_shader_parameter("tint", Color(1, 1, 1))
	_cloud_material.set_shader_parameter("alpha", 0.85)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400.0, 1400.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	plane.material = _cloud_material
	clouds = MeshInstance3D.new()
	clouds.name = "Clouds"
	clouds.mesh = plane
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.position = Vector3(0.0, CLOUD_HEIGHT, 0.0)
	add_child(clouds)


func _build_stars() -> void:
	var shader := load("res://shaders/stars.gdshader")
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("night_factor", 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = 480.0
	sphere.height = 960.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = material
	stars = MeshInstance3D.new()
	stars.name = "Stars"
	stars.mesh = sphere
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.visible = false
	add_child(stars)


func daylight_factor() -> float:
	return _day_factor


func is_night() -> bool:
	return _sun_height() < -0.02


func is_day() -> bool:
	return _sun_height() > 0.02


func _sun_height() -> float:
	return sin((time_of_day - 0.25) * TAU)


## 0 = midnight, 0.5 = noon. Convenient for the HUD clock.
func clock_string() -> String:
	var hours: float = time_of_day * 24.0
	var hh: int = int(hours)
	var mm: int = int((hours - float(hh)) * 60.0)
	return "%02d:%02d" % [hh, mm]


func _apply(delta: float) -> void:
	var height: float = _sun_height()
	var daylight: float = smoothstep(-0.10, 0.22, height)
	_day_factor = clampf(daylight, 0.0, 1.0)
	var glow: float = clampf(1.0 - absf(height) / 0.24, 0.0, 1.0)

	# Sun/moon light
	var pitch: float = -(time_of_day - 0.25) * 360.0
	sun.rotation_degrees = Vector3(pitch, -35.0, 0.0)
	if height >= -0.05:
		sun.light_color = SUN_COLOR_LOW.lerp(SUN_COLOR_DAY, clampf(height / 0.35, 0.0, 1.0))
		sun.light_energy = lerpf(0.18, 1.25, daylight)
		sun.shadow_enabled = true
	else:
		sun.light_color = MOON_COLOR
		sun.light_energy = 0.22
		sun.shadow_enabled = true

	# Sky colours
	var top: Color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, daylight).lerp(SUNSET_TOP, glow * 0.45)
	var horizon: Color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, daylight).lerp(
		SUNSET_HORIZON, glow * 0.8)
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_bottom_color = top.darkened(0.35)
	sky_material.ground_horizon_color = horizon.darkened(0.25)
	sky_material.sun_angle_max = 12.0

	# Ambient + fog
	environment.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, daylight)
	environment.ambient_light_energy = lerpf(0.55, 1.25, daylight)
	var fog: Color = FOG_NIGHT.lerp(FOG_DAY, daylight).lerp(SUNSET_HORIZON, glow * 0.3)
	environment.fog_light_color = fog
	environment.fog_density = 0.0016 + (1.0 - daylight) * 0.0012

	if stars != null:
		var night: float = clampf(1.0 - daylight * 2.2, 0.0, 1.0)
		stars.visible = night > 0.02
		(stars.mesh.material as ShaderMaterial).set_shader_parameter("night_factor", night)
		stars.rotation.y = time_of_day * TAU

	if world != null and is_instance_valid(world):
		world.set_day_factor(_day_factor)

	if clouds != null and _cloud_material != null:
		_cloud_material.set_shader_parameter("scroll", Vector2(
			float(Time.get_ticks_msec()) * 0.0000085,
			float(Time.get_ticks_msec()) * 0.0000031))
		var tint: Color = Color(1, 1, 1).lerp(Color(0.24, 0.28, 0.48), 1.0 - daylight)
		_cloud_material.set_shader_parameter("tint", tint)
		_cloud_material.set_shader_parameter("alpha", 0.45 + daylight * 0.4)
		var player := world.player if world != null else null
		if player != null and is_instance_valid(player):
			clouds.position = Vector3(snappedf(player.global_position.x, 8.0), CLOUD_HEIGHT,
				snappedf(player.global_position.z, 8.0))
			stars.position = Vector3(player.global_position.x, player.global_position.y + 40.0,
				player.global_position.z)
