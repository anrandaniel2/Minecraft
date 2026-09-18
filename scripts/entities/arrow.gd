class_name Arrow
extends Node3D

## An arrow in flight: points along its velocity, damages what it hits, and
## sticks into blocks (where it can be picked back up).

const GRAVITY: float = 22.0
const MAX_LIFETIME: float = 30.0

var velocity: Vector3 = Vector3.ZERO
var damage: float = 4.0
var owner_is_player: bool = true
var stuck: bool = false
var _life: float = 0.0
var _world: World
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("projectile")
	_world = get_tree().get_first_node_in_group("world") as World
	var body := BoxMesh.new()
	body.size = Vector3(0.06, 0.06, 0.7)
	var instance := MeshInstance3D.new()
	instance.mesh = body
	instance.material_override = _make_material(Color(0.75, 0.62, 0.4))
	add_child(instance)
	var tip := BoxMesh.new()
	tip.size = Vector3(0.09, 0.09, 0.16)
	var tip_instance := MeshInstance3D.new()
	tip_instance.mesh = tip
	tip_instance.material_override = _make_material(Color(0.85, 0.86, 0.9))
	tip_instance.position = Vector3(0.0, 0.0, -0.3)
	add_child(tip_instance)
	_mesh = instance


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return material


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME:
		queue_free()
		return
	if stuck:
		return
	velocity.y -= GRAVITY * delta
	var start: Vector3 = global_position
	var next: Vector3 = start + velocity * delta
	if _world != null and is_instance_valid(_world):
		# Sample the path so fast arrows cannot tunnel through blocks.
		var samples: int = maxi(1, int(ceil((next - start).length() / 0.25)))
		for index in samples:
			var point: Vector3 = start.lerp(next, float(index + 1) / float(samples))
			var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
			if _world.is_solid(voxel):
				_land(point, voxel)
				return
			var hit: Node3D = _check_entity(point)
			if hit != null:
				if hit.has_method("take_damage"):
					hit.take_damage(damage, "arrow")
				if Settings.get_value("particles"):
					_world.spawn_particles(point, "critical", 6)
				AudioManager.play_3d("arrow_hit", point, self, -4.0)
				queue_free()
				return
	global_position = next
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity.normalized(), Vector3.UP)
		rotate_object_local(Vector3.RIGHT, 0.0)


func _check_entity(point: Vector3) -> Node3D:
	var group: String = "mob" if owner_is_player else "player"
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D and node != self:
			var offset: Vector3 = (node as Node3D).global_position + Vector3(0.0, 0.9, 0.0) - point
			if offset.length() < 0.75:
				return node
	return null


func _land(point: Vector3, voxel: Vector3i) -> void:
	stuck = true
	velocity = Vector3.ZERO
	global_position = point
	AudioManager.play_3d("arrow_hit", point, self, -6.0)
	# Arrows despawn after a while even when stuck.
	var timer := get_tree().create_timer(40.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)
