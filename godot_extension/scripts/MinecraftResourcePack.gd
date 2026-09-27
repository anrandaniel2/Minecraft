## Minecraft 26.3 resource-pack model loader for the Godot viewport backend.
##
## The source data is the complete ``extracted/assets/minecraft`` namespace,
## staged below ``res://minecraft_assets/minecraft`` before an export.  This
## loader deliberately consumes Minecraft blockstate and model JSON rather than
## using hand-authored colored cubes. It is renderer-only: Java game logic can
## supply block IDs/chunk snapshots through the platform adapter without ever
## depending on Godot classes.
class_name MinecraftResourcePack
extends RefCounted

const ASSET_ROOT := "res://minecraft_assets/minecraft"
const MODEL_ROOT := ASSET_ROOT + "/models"
const BLOCKSTATE_ROOT := ASSET_ROOT + "/blockstates"
const TEXTURE_ROOT := ASSET_ROOT + "/textures"

var _json_cache: Dictionary = {}
var _model_definition_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _texture_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _transparent_texture_ids: Dictionary = {}


func is_staged() -> bool:
	return FileAccess.file_exists(BLOCKSTATE_ROOT + "/stone.json") \
		and FileAccess.file_exists(MODEL_ROOT + "/block/cube_all.json")


## Returns a Mesh for a Minecraft block ID (for example minecraft:grass_block).
## The mesh uses the client pack's blockstate -> model -> parent -> texture
## chain, including model elements and element rotations.
func mesh_for_block(block_id: String) -> Mesh:
	var selection := _select_block_model(block_id)
	if selection.is_empty():
		return null

	var cache_key := "%s|x=%s|y=%s" % [
		selection["model"], selection.get("x", 0), selection.get("y", 0)
	]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]

	var mesh := _build_model_mesh(selection["model"])
	if mesh != null:
		_mesh_cache[cache_key] = mesh
	return mesh


## The variant rotation is stored separately because the same base model can be
## selected at different rotations by a blockstate. Call this on the
## MeshInstance3D that receives mesh_for_block().
func rotation_for_block(block_id: String) -> Vector3:
	var selection := _select_block_model(block_id)
	return Vector3(float(selection.get("x", 0)), float(selection.get("y", 0)), 0.0)


func _select_block_model(block_id: String) -> Dictionary:
	var local_id := _normalise_identifier(block_id)
	var state: Dictionary = _read_json(BLOCKSTATE_ROOT.path_join(local_id + ".json"))
	if state.is_empty():
		# A missing blockstate is allowed for model-only resources used by a
		# caller. This keeps the adapter useful for data supplied by the client.
		if FileAccess.file_exists(MODEL_ROOT.path_join(local_id + ".json")):
			return {"model": local_id}
		return {}

	var choice: Variant = null
	var variants: Dictionary = state.get("variants", {})
	if not variants.is_empty():
		if variants.has(""):
			choice = variants[""]
		else:
			var keys: Array = variants.keys()
			keys.sort()
			choice = variants[keys[0]]
	elif state.has("multipart"):
		# Multipart blocks can contain several meshes. The first unconditional
		# apply entry is a safe base representation; the chunk adapter can later
		# emit every part once it provides state properties.
		for part in state["multipart"]:
			if part is Dictionary and (not part.has("when") or part["when"].is_empty()):
				choice = part.get("apply")
				break
		if choice == null and not state["multipart"].is_empty():
			choice = state["multipart"][0].get("apply")

	if choice is Array:
		if choice.is_empty():
			return {}
		choice = choice[0]
	if not (choice is Dictionary) or not choice.has("model"):
		return {}

	return {
		"model": _normalise_identifier(str(choice["model"])),
		"x": int(choice.get("x", 0)),
		"y": int(choice.get("y", 0)),
	}


func _build_model_mesh(model_id: String) -> ArrayMesh:
	var model := _load_model_definition(model_id)
	var elements: Array = model.get("elements", [])
	if elements.is_empty():
		return null

	# A model can use a different texture for each face. Each texture becomes a
	# mesh surface, while all block instances reuse the resulting ArrayMesh.
	var surfaces: Dictionary = {}
	for element_variant in elements:
		if not (element_variant is Dictionary):
			continue
		var element: Dictionary = element_variant
		var from_values: Array = element.get("from", [])
		var to_values: Array = element.get("to", [])
		if from_values.size() != 3 or to_values.size() != 3:
			continue
		var block_from := _model_vector(from_values)
		var block_to := _model_vector(to_values)
		var faces: Dictionary = element.get("faces", {})
		for direction_variant in faces:
			var direction := str(direction_variant)
			var face_variant: Variant = faces[direction_variant]
			if not (face_variant is Dictionary):
				continue
			var face: Dictionary = face_variant
			var texture_id := _resolve_texture_reference(str(face.get("texture", "")), model.get("textures", {}))
			if texture_id.is_empty():
				texture_id = "__missing__"
			if not surfaces.has(texture_id):
				surfaces[texture_id] = _new_surface_data()
			var surface: Array = surfaces[texture_id]
			var vertices := _face_vertices(direction, block_from, block_to)
			if vertices.is_empty():
				continue
			vertices = _rotate_element_vertices(vertices, element)
			var normal := _face_normal(direction)
			if element.has("rotation"):
				normal = _rotate_element_normal(normal, element["rotation"])
			_append_face(surface, vertices, normal, _face_uv(face))
			surfaces[texture_id] = surface

	if surfaces.is_empty():
		return null

	var mesh := ArrayMesh.new()
	var texture_ids: Array = surfaces.keys()
	texture_ids.sort()
	for texture_variant in texture_ids:
		var texture_id := str(texture_variant)
		var surface: Array = surfaces[texture_id]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface[0]
		arrays[Mesh.ARRAY_NORMAL] = surface[1]
		arrays[Mesh.ARRAY_TEX_UV] = surface[2]
		arrays[Mesh.ARRAY_INDEX] = surface[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for_texture(texture_id))
	return mesh


func _load_model_definition(model_id: String) -> Dictionary:
	var normalised_id := _normalise_identifier(model_id)
	if _model_definition_cache.has(normalised_id):
		return _model_definition_cache[normalised_id]

	# Store a placeholder before following parents so malformed parent cycles
	# cannot recurse forever on a third-party resource pack.
	_model_definition_cache[normalised_id] = {}
	var source: Dictionary = _read_json(MODEL_ROOT.path_join(normalised_id + ".json"))
	if source.is_empty():
		return {}

	var inherited: Dictionary = {}
	if source.has("parent"):
		inherited = _load_model_definition(str(source["parent"]))

	var textures: Dictionary = {}
	if inherited.has("textures"):
		textures = inherited["textures"].duplicate()
	for texture_name in source.get("textures", {}):
		textures[texture_name] = source["textures"][texture_name]

	var elements: Array = inherited.get("elements", [])
	if source.has("elements"):
		elements = source["elements"]

	var resolved := {
		"textures": textures,
		"elements": elements,
	}
	_model_definition_cache[normalised_id] = resolved
	return resolved


func _read_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("Minecraft resource JSON is invalid: %s" % path)
		return {}
	_json_cache[path] = parsed
	return parsed


func _resolve_texture_reference(reference: String, textures: Dictionary) -> String:
	var resolved := reference
	var visited: Dictionary = {}
	while resolved.begins_with("#"):
		var texture_key := resolved.trim_prefix("#")
		if visited.has(texture_key) or not textures.has(texture_key):
			return ""
		visited[texture_key] = true
		var texture_value: Variant = textures[texture_key]
		# 26.3 also permits a texture declaration object. Its sprite is the
		# normal resource identifier; force_translucent maps to Godot alpha
		# blending for assets such as glass.
		if texture_value is Dictionary:
			if not texture_value.has("sprite"):
				return ""
			resolved = str(texture_value["sprite"])
			var texture_id := _normalise_identifier(resolved)
			if bool(texture_value.get("force_translucent", false)):
				_transparent_texture_ids[texture_id] = true
			return texture_id
		if not (texture_value is String):
			return ""
		resolved = texture_value
	return _normalise_identifier(resolved)


func _material_for_texture(texture_id: String) -> StandardMaterial3D:
	if _material_cache.has(texture_id):
		return _material_cache[texture_id]

	var material := StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _transparent_texture_ids.has(texture_id):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.albedo_color = Color.WHITE
	if texture_id == "__missing__":
		material.albedo_color = Color(1.0, 0.0, 1.0)
	else:
		var texture := _texture_for_identifier(texture_id)
		if texture != null:
			material.albedo_texture = texture
		else:
			material.albedo_color = Color(0.9, 0.0, 0.9)
	_material_cache[texture_id] = material
	return material


func _texture_for_identifier(texture_id: String) -> Texture2D:
	if _texture_cache.has(texture_id):
		return _texture_cache[texture_id]
	var resource_path := TEXTURE_ROOT.path_join(texture_id + ".png")
	if not ResourceLoader.exists(resource_path):
		return null
	var texture := load(resource_path) as Texture2D
	if texture != null:
		_texture_cache[texture_id] = texture
	return texture


func _new_surface_data() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]


func _append_face(surface: Array, vertices: Array, normal: Vector3, uv: Rect2) -> void:
	var positions: PackedVector3Array = surface[0]
	var normals: PackedVector3Array = surface[1]
	var uvs: PackedVector2Array = surface[2]
	var indices: PackedInt32Array = surface[3]
	var first_index := positions.size()
	# Minecraft UV coordinates are expressed in texture pixels (normally 16px).
	var face_uvs := [
		Vector2(uv.position.x, uv.end.y) / 16.0,
		Vector2(uv.end.x, uv.end.y) / 16.0,
		Vector2(uv.end.x, uv.position.y) / 16.0,
		Vector2(uv.position.x, uv.position.y) / 16.0,
	]
	for index in range(4):
		positions.append(vertices[index])
		normals.append(normal)
		uvs.append(face_uvs[index])
	indices.append_array(PackedInt32Array([
		first_index, first_index + 1, first_index + 2,
		first_index, first_index + 2, first_index + 3,
	]))
	surface[0] = positions
	surface[1] = normals
	surface[2] = uvs
	surface[3] = indices


func _face_vertices(direction: String, from: Vector3, to: Vector3) -> Array:
	match direction:
		"down":
			return [Vector3(from.x, from.y, to.z), Vector3(to.x, from.y, to.z), Vector3(to.x, from.y, from.z), Vector3(from.x, from.y, from.z)]
		"up":
			return [Vector3(from.x, to.y, from.z), Vector3(to.x, to.y, from.z), Vector3(to.x, to.y, to.z), Vector3(from.x, to.y, to.z)]
		"north":
			return [Vector3(to.x, from.y, from.z), Vector3(from.x, from.y, from.z), Vector3(from.x, to.y, from.z), Vector3(to.x, to.y, from.z)]
		"south":
			return [Vector3(from.x, from.y, to.z), Vector3(to.x, from.y, to.z), Vector3(to.x, to.y, to.z), Vector3(from.x, to.y, to.z)]
		"west":
			return [Vector3(from.x, from.y, from.z), Vector3(from.x, from.y, to.z), Vector3(from.x, to.y, to.z), Vector3(from.x, to.y, from.z)]
		"east":
			return [Vector3(to.x, from.y, to.z), Vector3(to.x, from.y, from.z), Vector3(to.x, to.y, from.z), Vector3(to.x, to.y, to.z)]
	return []


func _face_normal(direction: String) -> Vector3:
	match direction:
		"down": return Vector3.DOWN
		"up": return Vector3.UP
		"north": return Vector3.BACK
		"south": return Vector3.FORWARD
		"west": return Vector3.LEFT
		"east": return Vector3.RIGHT
	return Vector3.UP


func _face_uv(face: Dictionary) -> Rect2:
	var values: Array = face.get("uv", [0.0, 0.0, 16.0, 16.0])
	if values.size() != 4:
		return Rect2(0.0, 0.0, 16.0, 16.0)
	return Rect2(float(values[0]), float(values[1]), float(values[2]) - float(values[0]), float(values[3]) - float(values[1]))


func _rotate_element_vertices(vertices: Array, element: Dictionary) -> Array:
	if not element.has("rotation") or not (element["rotation"] is Dictionary):
		return vertices
	var rotation: Dictionary = element["rotation"]
	var axis := _rotation_axis(str(rotation.get("axis", "y")))
	var angle := deg_to_rad(float(rotation.get("angle", 0.0)))
	var origin_values: Array = rotation.get("origin", [8.0, 8.0, 8.0])
	var origin := _model_vector(origin_values)
	var transformed: Array = []
	for vertex in vertices:
		transformed.append(origin + (vertex - origin).rotated(axis, angle))
	return transformed


func _rotate_element_normal(normal: Vector3, rotation_variant: Variant) -> Vector3:
	if not (rotation_variant is Dictionary):
		return normal
	var rotation: Dictionary = rotation_variant
	return normal.rotated(_rotation_axis(str(rotation.get("axis", "y"))), deg_to_rad(float(rotation.get("angle", 0.0)))).normalized()


func _rotation_axis(axis: String) -> Vector3:
	match axis:
		"x": return Vector3.RIGHT
		"z": return Vector3.FORWARD
	return Vector3.UP


func _model_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]) / 16.0 - 0.5, float(values[1]) / 16.0 - 0.5, float(values[2]) / 16.0 - 0.5)


func _normalise_identifier(identifier: String) -> String:
	var result := identifier
	if result.begins_with("minecraft:"):
		result = result.trim_prefix("minecraft:")
	return result
