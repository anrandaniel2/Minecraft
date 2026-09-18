class_name RemotePlayer
extends Node3D

## A networked player: box-model avatar with a name tag, smoothly interpolated
## from the last few state packets.

const INTERP_SPEED: float = 12.0

var peer_id: int = 0
var display_name: String = "Player"
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var held_item_id: int = -1
var health: float = 20.0
var sneaking: bool = false
var _label: Label3D
var _model: MeshInstance3D
var _hand: MeshInstance3D
var _materials: Dictionary = {}
var _walk_phase: float = 0.0


func setup(id: int, name_text: String) -> void:
	peer_id = id
	display_name = name_text
	if _label != null:
		_label.text = name_text


func _ready() -> void:
	add_to_group("remote_player")
	collision_layer = 0
	collision_mask = 0
	_build_model()
	_build_label()
	global_position = target_position


func _build_model() -> void:
	var skin: Texture2D = Registry.player_skin()
	var tiles: Dictionary = Registry.entity_tiles.get("player", {})
	var parts: Array = BoxModel.mob_parts(tiles, "humanoid", 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = skin
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	_materials["body"] = material
	_model = MeshInstance3D.new()
	_model.mesh = BoxModel.build(parts, Vector2(80.0, 80.0))
	_model.material_override = material
	_model.name = "Body"
	add_child(_model)

	# Held item proxy, parented to the body so it swings along.
	_hand = MeshInstance3D.new()
	_hand.name = "Held"
	var hand_material := StandardMaterial3D.new()
	hand_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hand_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_hand.material_override = hand_material
	_hand.position = Vector3(0.36, 1.05, -0.34)
	_hand.rotation_degrees = Vector3(-14.0, -20.0, 0.0)
	_hand.scale = Vector3.ONE * 0.3
	add_child(_hand)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "NameTag"
	_label.text = display_name
	_label.position = Vector3(0.0, 2.25, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.006
	_label.modulate = Color(1, 1, 1, 0.92)
	add_child(_label)


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, clampf(delta * INTERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * INTERP_SPEED, 0.0, 1.0))
	if _model != null:
		var speed: float = global_position.distance_to(target_position)
		_walk_phase += delta * (2.0 + speed * 6.0)
		_model.position.y = absf(sin(_walk_phase)) * 0.05 if speed > 0.02 else 0.0
		_model.rotation.x = lerp_angle(_model.rotation.x, -target_pitch * 0.4, clampf(delta * 8.0, 0.0, 1.0))
	if _label != null:
		_label.text = display_name


func apply_state(state: Dictionary) -> void:
	target_position = Vector3(
		float(state.get("x", target_position.x)),
		float(state.get("y", target_position.y)),
		float(state.get("z", target_position.z)))
	target_yaw = float(state.get("yaw", target_yaw))
	target_pitch = float(state.get("pitch", target_pitch))
	sneaking = bool(state.get("sneak", false))
	health = float(state.get("health", health))
	var held: int = int(state.get("held", held_item_id))
	if held != held_item_id:
		held_item_id = held
		_update_hand()


func _update_hand() -> void:
	if _hand == null:
		return
	var material := _hand.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_texture = Registry.icon(held_item_id) if held_item_id >= 0 else null
	_hand.visible = held_item_id >= 0


func set_health(value: float) -> void:
	health = value


func distance_to_camera(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	return camera.global_position.distance_to(global_position)
