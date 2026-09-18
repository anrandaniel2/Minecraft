class_name ItemDrop
extends RigidBody3D

## A dropped item stack: falls, bobs, and flies to the player when close.
##
## Uses a RigidBody so items stack naturally on the ground, but switches to
## scripted motion inside the magnet range so pickups feel snappy.

const MAGNET_RANGE: float = 2.6
const PICKUP_RANGE: float = 0.75
const MAGNET_SPEED: float = 9.0
const SIZE: float = 0.28
const LIFETIME: float = 300.0

var item_id: int = 0
var count: int = 1
var durability: int = 0
var picked_up_by: Array = []       # peer ids that already took their share
var _player: Node3D
var _life: float = 0.0
var _bob: float = 0.0
var _mesh: MeshInstance3D
var _pickup_delay: float = 0.6
var _world: World


func _ready() -> void:
	add_to_group("item_drop")
	collision_layer = 8
	collision_mask = 1
	gravity_scale = 1.2
	linear_damp = 1.5
	_build_visual()
	_player = get_tree().get_first_node_in_group("player")
	_world = get_tree().get_first_node_in_group("world") as World
	linear_velocity = Vector3(randf_range(-1.4, 1.4), 2.4, randf_range(-1.4, 1.4))
	angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))


func _build_visual() -> void:
	var texture: Texture2D = Registry.icon(item_id)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.7
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE, SIZE, SIZE)
	mesh.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE, SIZE, SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return
	_pickup_delay = maxf(0.0, _pickup_delay - delta)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	var target: Vector3 = _player.global_position + Vector3(0.0, 0.9, 0.0)
	var to_player: Vector3 = target - global_position
	var distance: float = to_player.length()
	if distance <= PICKUP_RANGE and _pickup_delay <= 0.0:
		_try_pickup()
		return
	if distance <= MAGNET_RANGE and _pickup_delay <= 0.0:
		var desired: Vector3 = to_player.normalized() * MAGNET_SPEED * clampf(distance, 0.4, 1.6)
		linear_velocity = linear_velocity.lerp(desired, 0.35)
		gravity_scale = 0.0
	else:
		gravity_scale = 1.2
	# Gentle spin so items in the world read as pickups.
	if _mesh != null:
		_bob += delta * 4.0
		_mesh.rotation.x += delta * 0.6
		_mesh.position.y = sin(_bob) * 0.02


func _try_pickup() -> void:
	if _player != null and _player.has_method("give_item"):
		var accepted: int = int(_player.give_item(item_id, count, durability))
		if accepted > 0:
			count -= accepted
			AudioManager.play_3d("item_pickup", global_position, self, -8.0,
				randf_range(0.95, 1.25))
			if count <= 0:
				queue_free()
				return
		_pickup_delay = 0.5


## Merges another drop of the same item into this one.
func try_merge(other: ItemDrop) -> bool:
	if other == null or other.item_id != item_id:
		return false
	var max_stack: int = Items.max_stack(item_id)
	if count >= max_stack:
		return false
	var space: int = max_stack - count
	var moved: int = mini(space, other.count)
	count += moved
	other.count -= moved
	if other.count <= 0:
		other.queue_free()
	return true
