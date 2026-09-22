## First Godot viewport renderer milestone.
##
## This is deliberately a Godot-native voxel scene, not a claim that the
## desktop Blaze3D renderer has already been ported. It establishes the viewport,
## fullscreen presentation, lighting, block geometry, and look-camera contract
## which the recovered full client renderer will target.
class_name MinecraftGodotRenderer
extends Node3D

const LOOK_SENSITIVITY := 0.004
const PITCH_LIMIT := deg_to_rad(85.0)

var _yaw := deg_to_rad(-35.0)
var _pitch := deg_to_rad(-22.0)
var _camera: Camera3D

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_demo_voxels()

func add_camera_drag(relative_pixels: Vector2) -> void:
	_yaw -= relative_pixels.x * LOOK_SENSITIVITY
	_pitch = clamp(_pitch - relative_pixels.y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("6eb9ed")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5edff")
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(8.0, 7.5, 11.0)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.current = true
	add_child(_camera)

func _build_demo_voxels() -> void:
	# Small deterministic terrain used while the Minecraft/Blaze3D draw-command
	# adapter is being ported. Blocks render wholly inside Godot's main viewport.
	for x in range(-8, 9):
		for z in range(-8, 9):
			var height := 0 if abs(x) + abs(z) < 10 else -1
			_add_block(Vector3(x, height - 1, z), Color("806044"))
			_add_block(Vector3(x, height, z), Color("64a944"))
	for y in range(0, 4):
		_add_block(Vector3(-2, y + 1, -2), Color("8b6a45"))
		_add_block(Vector3(3, y + 1, 2), Color("8b6a45"))
	_add_block(Vector3(-2, 5, -2), Color("4d8d3c"))
	_add_block(Vector3(3, 5, 2), Color("4d8d3c"))

func _add_block(block_position: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	cube.material = material
	mesh_instance.mesh = cube
	mesh_instance.position = block_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)
