class_name XpOrb
extends Area3D

## A floating experience orb: bobs, drifts toward the player, grants XP on touch.

const MAGNET_RANGE: float = 4.0
const SPEED: float = 7.0
const LIFETIME: float = 240.0

var amount: int = 1
var velocity: Vector3 = Vector3.ZERO
var _life: float = 0.0
var _bob: float = 0.0
var _player: Node3D


func _ready() -> void:
	add_to_group("xp_orb")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	velocity = Vector3(randf_range(-1.0, 1.0), 3.0, randf_range(-1.0, 1.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.95, 0.35)
	material.emission_enabled = true
	material.emission = Color(0.55, 1.0, 0.35)
	material.emission_energy_multiplier = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return
	_bob += delta * 3.0
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	var target: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	var to_player: Vector3 = target - global_position
	var distance: float = to_player.length()
	if distance < 0.7:
		if _player.has_method("give_xp"):
			_player.give_xp(amount)
		AudioManager.play_3d("xp_pickup", global_position, self, -10.0, randf_range(0.9, 1.3))
		queue_free()
		return
	if distance < MAGNET_RANGE:
		velocity = to_player.normalized() * SPEED
	else:
		velocity.y -= 9.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, delta * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 2.0)
	var world := get_tree().get_first_node_in_group("world") as World
	if world != null:
		var next := global_position + velocity * delta
		var voxel := Vector3i(floori(next.x), floori(next.y), floori(next.z))
		if world.is_solid(voxel):
			velocity.y = absf(velocity.y) * 0.5
			next.y = global_position.y
		global_position = next
	else:
		global_position += velocity * delta
	global_position.y += sin(_bob) * 0.002
