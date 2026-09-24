## Godot-side Minecraft renderer.
##
## This renderer draws in Godot's main viewport using the complete Minecraft
## 26.3 resource pack staged from extracted/assets/minecraft. It resolves real
## blockstates, model-parent inheritance, element geometry, face UVs, and block
## textures; it does not draw a second GLFW/Blaze3D window.
##
## Java remains the owner of game state. A platform adapter can submit a block
## snapshot through apply_block_snapshot() without Java importing Godot APIs.
class_name MinecraftGodotRenderer
extends Node3D

const LOOK_SENSITIVITY := 0.004
const PITCH_LIMIT := deg_to_rad(85.0)
const MinecraftResourcePack := preload("res://scripts/MinecraftResourcePack.gd")

# This deterministic bootstrap scene is replaced as soon as a Java world/chunk
# adapter supplies an authoritative snapshot. Every ID is resolved from the
# complete extracted client resource pack, not a hand-authored Godot cube.
const BOOTSTRAP_PALETTE := [
	"minecraft:grass_block",
	"minecraft:dirt",
	"minecraft:stone",
	"minecraft:coarse_dirt",
	"minecraft:oak_planks",
	"minecraft:cobblestone",
	"minecraft:sand",
]

var _yaw := deg_to_rad(-35.0)
var _pitch := deg_to_rad(-22.0)
var _camera: Camera3D
var _world_root: Node3D
var _resource_pack: MinecraftResourcePack
var _snapshot_revision := 0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_world_root = Node3D.new()
	_world_root.name = "MinecraftWorld"
	add_child(_world_root)
	_resource_pack = MinecraftResourcePack.new()
	if _resource_pack.is_staged():
		apply_block_snapshot(_bootstrap_snapshot())
	else:
		push_warning(
			"Minecraft resource pack is not staged. Run " +
			"python3 tools/stage_minecraft_assets.py before launching Godot."
		)


func add_camera_drag(relative_pixels: Vector2) -> void:
	_yaw -= relative_pixels.x * LOOK_SENSITIVITY
	_pitch = clamp(_pitch - relative_pixels.y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


## Renderer adapter boundary.
##
## The Java/platform layer supplies entries in the form:
## { "block": "minecraft:stone", "x": 0, "y": 64, "z": 0 }
##
## A later full-client chunk adapter should call this only for changed chunks
## and replace this method with section-level mesh batching. Keeping this data
## contract free of Godot types lets the recovered client stay engine-agnostic.
func apply_block_snapshot(blocks: Array) -> void:
	if _world_root == null or _resource_pack == null:
		return
	for child in _world_root.get_children():
		child.queue_free()

	for entry_variant in blocks:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var block_id := str(entry.get("block", "minecraft:air"))
		if block_id == "minecraft:air":
			continue
		var mesh := _resource_pack.mesh_for_block(block_id)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = Vector3(
			float(entry.get("x", 0)),
			float(entry.get("y", 0)),
			float(entry.get("z", 0))
		)
		instance.rotation_degrees = _resource_pack.rotation_for_block(block_id)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_world_root.add_child(instance)
	_snapshot_revision += 1


func renderer_status() -> Dictionary:
	return {
		"resource_pack_staged": _resource_pack != null and _resource_pack.is_staged(),
		"snapshot_revision": _snapshot_revision,
		"block_instances": 0 if _world_root == null else _world_root.get_child_count(),
	}


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


func _bootstrap_snapshot() -> Array:
	var blocks: Array = []
	for x in range(-8, 9):
		for z in range(-8, 9):
			var palette_index := posmod(x * 31 + z * 17, BOOTSTRAP_PALETTE.size())
			blocks.append({
				"block": BOOTSTRAP_PALETTE[palette_index],
				"x": x,
				"y": -1,
				"z": z,
			})
			blocks.append({"block": "minecraft:grass_block", "x": x, "y": 0, "z": z})

	# Small model coverage sample: parent-model inheritance (oak leaves),
	# axis blockstates (oak log), translucency (glass), and rotated elements
	# (torch) all exercise actual Minecraft asset data.
	for y in range(1, 5):
		blocks.append({"block": "minecraft:oak_log", "x": -2, "y": y, "z": -2})
		blocks.append({"block": "minecraft:oak_log", "x": 3, "y": y, "z": 2})
	for x in range(-3, 0):
		for z in range(-3, 0):
			blocks.append({"block": "minecraft:oak_leaves", "x": x, "y": 5, "z": z})
	for x in range(2, 5):
		for z in range(1, 4):
			blocks.append({"block": "minecraft:oak_leaves", "x": x, "y": 5, "z": z})
	blocks.append({"block": "minecraft:glass", "x": 0, "y": 1, "z": -3})
	blocks.append({"block": "minecraft:torch", "x": 0, "y": 1, "z": -2})
	return blocks
