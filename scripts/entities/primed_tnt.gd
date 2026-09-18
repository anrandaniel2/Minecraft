class_name PrimedTnt
extends Node3D

## Lit TNT: hisses for a few seconds, blinks, then explodes.

const FUSE_TIME: float = 3.2
const POWER: float = 4.2

var velocity: Vector3 = Vector3.ZERO
var fuse: float = FUSE_TIME
var _world: World
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("primed_tnt")
	_world = get_tree().get_first_node_in_group("world") as World
	_material = Arrow._make_material(Color(1, 1, 1))
	_material.albedo_texture = Registry.block_tile_icon(Blocks.id("tnt"))
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.9, 0.9)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.98, 0.98, 0.98)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = _material
	add_child(_mesh)
	AudioManager.play_3d("fuse", global_position, self, -1.0)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if _world == null or not is_instance_valid(_world):
		queue_free()
		return
	velocity.y -= 24.0 * delta
	var next: Vector3 = global_position + velocity * delta
	var voxel := Vector3i(floori(next.x), floori(next.y), floori(next.z))
	if _world.is_solid(voxel):
		velocity = Vector3(velocity.x * 0.6, 0.0, velocity.z * 0.6)
	else:
		global_position = next
		velocity.x = move_toward(velocity.x, 0.0, delta * 3.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 3.0)
	# Blink faster as the fuse burns down.
	var blink: float = 0.5 + 0.5 * sin(fuse * 22.0)
	_material.albedo_color = Color(1.0, 1.0 - blink * 0.4, 1.0 - blink * 0.4)
	if fuse <= 0.0:
		_world.explode(global_position + Vector3(0.0, 0.5, 0.0), POWER,
			bool(Settings.get_value("mob_griefing")) or true)
		queue_free()
