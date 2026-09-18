class_name FallingBlock
extends Node3D

## Sand/gravel that lost its support: falls, then becomes a block again.

var block_id: int = 0
var fall_speed: float = 0.0
var _world: World
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("falling_block")
	_world = get_tree().get_first_node_in_group("world") as World
	var material := StandardMaterial3D.new()
	material.albedo_texture = Registry.block_tile_icon(block_id)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.98, 0.98, 0.98)
	mesh.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	fall_speed = minf(fall_speed + 22.0 * delta, 24.0)
	position.y -= fall_speed * delta
	if _mesh != null:
		_mesh.rotation.x += delta * 1.2
	var voxel := Vector3i(floori(position.x), floori(position.y - 0.5), floori(position.z))
	if _world == null or not is_instance_valid(_world):
		queue_free()
		return
	var below: int = _world.get_block(voxel)
	if voxel.y <= 0 or (below != Blocks.AIR and not Blocks.is_liquid(below)):
		var land := voxel + Vector3i(0, 1, 0)
		if _world.get_block(land) == Blocks.AIR or Blocks.is_replaceable(_world.get_block(land)):
			_world.set_block(land, block_id)
			AudioManager.play_3d("place_block", Vector3(land) + Vector3(0.5, 0.5, 0.5),
				_world, -3.0, randf_range(0.85, 1.0))
		queue_free()
