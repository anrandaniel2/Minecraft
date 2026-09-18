class_name BoxModel
extends RefCounted

## Builds Minecraft-style box models: a list of cuboids, each with its own
## texture rectangles per face, merged into one ArrayMesh with vertex colours.
##
## A part looks like:
##   {size: Vector3, offset: Vector3, tint: Color,
##    front: Rect2, back: Rect2, side: Rect2, top: Rect2, bottom: Rect2}
## Rect2 values are pixel rects in the mob's skin sheet (see Registry.entity_tile).
## Missing rects fall back to `side` and then to the first available rect.

const FACE_KEYS: PackedStringArray = ["side", "side", "top", "bottom", "front", "back"]

# Face order +X, -X, +Y, -Y, +Z, -Z with unit cube corner offsets.
const FACE_CORNERS: Array = [
	[Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
]


## `parts` is an Array of Dictionaries, `skin_size` the sheet resolution.
static func build(parts: Array, skin_size: Vector2) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for part in parts:
		_add_box(vertices, normals, colors, uvs, indices, part, skin_size)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_box(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array,
		part: Dictionary, skin_size: Vector2) -> void:
	var size: Vector3 = part.get("size", Vector3.ONE)
	var offset: Vector3 = part.get("offset", Vector3.ZERO)
	var tint: Color = part.get("tint", Color.WHITE)
	var inflate: float = float(part.get("inflate", 0.0))
	var scale: Vector3 = part.get("scale", Vector3.ONE)
	var fallback: Rect2 = part.get("side", Rect2(0, 0, 16, 16))
	for face in 6:
		var key: String = FACE_KEYS[face]
		var rect: Rect2 = part.get(key, fallback)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			rect = fallback
		var base_index: int = vertices.size()
		var normal := Vector3.ZERO
		match face:
			0:
				normal = Vector3(1, 0, 0)
			1:
				normal = Vector3(-1, 0, 0)
			2:
				normal = Vector3(0, 1, 0)
			3:
				normal = Vector3(0, -1, 0)
			4:
				normal = Vector3(0, 0, 1)
			_:
				normal = Vector3(0, 0, -1)
		var uv_corners: Array = [
			Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y),
			Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.position.y),
		]
		for corner_index in 4:
			var corner: Vector3 = FACE_CORNERS[face][corner_index]
			var local := Vector3(
				(corner.x - 0.5) * size.x * scale.x,
				(corner.y - 0.5) * size.y * scale.y,
				(corner.z - 0.5) * size.z * scale.z
			)
			local += offset
			local += normal * inflate
			vertices.append(local)
			normals.append(normal)
			colors.append(tint)
			uvs.append(uv_corners[corner_index] / skin_size)
		indices.append_array([base_index, base_index + 1, base_index + 2,
			base_index, base_index + 2, base_index + 3])


## Standard mob anatomy built from a skin sheet, shared by almost every mob.
## `quadruped` makes four legs, otherwise two legs + two arms (humanoid).
static func mob_parts(skin_tiles: Dictionary, kind: String = "humanoid",
		child_scale: float = 1.0) -> Array:
	var head_front: Rect2 = _tile(skin_tiles, "head_front")
	var head_side: Rect2 = _tile(skin_tiles, "head_side")
	var head_back: Rect2 = _tile(skin_tiles, "head_back")
	var head_top: Rect2 = _tile(skin_tiles, "head_top")
	var body_front: Rect2 = _tile(skin_tiles, "body_front")
	var body_side: Rect2 = _tile(skin_tiles, "body_side")
	var body_back: Rect2 = _tile(skin_tiles, "body_back")
	var body_top: Rect2 = _tile(skin_tiles, "body_top")
	var limb: Rect2 = _tile(skin_tiles, "limb_side")
	var limb_top: Rect2 = _tile(skin_tiles, "limb_top")
	var extra_a: Rect2 = _tile(skin_tiles, "extra_a")
	var extra_b: Rect2 = _tile(skin_tiles, "extra_b")
	var parts: Array = []
	match kind:
		"chicken":
			parts.append({"size": Vector3(0.25, 0.3, 0.25), "offset": Vector3(0, 0.52, -0.16),
				"front": head_front, "side": head_side, "top": head_top, "back": head_back,
				"bottom": head_side})
			parts.append({"size": Vector3(0.4, 0.34, 0.5), "offset": Vector3(0, 0.32, 0.05),
				"front": body_front, "side": body_side, "top": body_top, "back": body_back,
				"bottom": body_side})
			parts.append({"size": Vector3(0.5, 0.1, 0.35), "offset": Vector3(0.03, 0.3, 0.08),
				"side": mid_tile(extra_a, limb), "front": mid_tile(extra_a, limb),
				"top": limb_top, "back": mid_tile(extra_a, limb), "bottom": limb})
			parts.append({"size": Vector3(0.08, 0.24, 0.08), "offset": Vector3(0.1, 0.12, 0.02),
				"side": extra_b, "front": extra_b, "top": extra_b, "back": extra_b,
				"bottom": extra_b})
			parts.append({"size": Vector3(0.08, 0.24, 0.08), "offset": Vector3(-0.1, 0.12, 0.02),
				"side": extra_b, "front": extra_b, "top": extra_b, "back": extra_b,
				"bottom": extra_b})
		"quadruped":
			parts.append({"size": Vector3(0.5, 0.5, 0.5), "offset": Vector3(0, 0.62, 0.42),
				"front": head_front, "side": head_side, "top": head_top, "back": head_back,
				"bottom": head_side})
			parts.append({"size": Vector3(0.55, 0.5, 0.85), "offset": Vector3(0, 0.55, -0.01),
				"front": body_front, "side": body_side, "top": body_top, "back": body_back,
				"bottom": body_side})
			for corner in [Vector3(0.17, 0.0, 0.28), Vector3(-0.17, 0.0, 0.28),
					Vector3(0.17, 0.0, -0.3), Vector3(-0.17, 0.0, -0.3)]:
				parts.append({"size": Vector3(0.2, 0.5, 0.2),
					"offset": Vector3(corner.x, 0.24, corner.z),
					"front": limb, "side": limb, "top": limb_top, "back": limb, "bottom": limb})
		"creeper":
			parts.append({"size": Vector3(0.5, 0.5, 0.5), "offset": Vector3(0, 0.72, 0),
				"front": head_front, "side": head_side, "top": head_top, "back": head_back,
				"bottom": head_side})
			parts.append({"size": Vector3(0.5, 0.75, 0.28), "offset": Vector3(0, 0.36, 0),
				"front": body_front, "side": body_side, "top": body_top, "back": body_back,
				"bottom": body_side})
			for corner in [Vector3(0.16, 0, 0.16), Vector3(-0.16, 0, 0.16),
					Vector3(0.16, 0, -0.14), Vector3(-0.16, 0, -0.14)]:
				parts.append({"size": Vector3(0.22, 0.42, 0.22),
					"offset": Vector3(corner.x, 0.21, corner.z),
					"front": limb, "side": limb, "top": limb_top, "back": limb, "bottom": limb})
		"spider":
			parts.append({"size": Vector3(0.4, 0.35, 0.4), "offset": Vector3(0, 0.5, 0.45),
				"front": head_front, "side": head_side, "top": head_top, "back": head_back,
				"bottom": head_side})
			parts.append({"size": Vector3(0.55, 0.4, 0.6), "offset": Vector3(0, 0.45, 0.0),
				"front": body_front, "side": body_side, "top": body_top, "back": body_back,
				"bottom": body_side})
			parts.append({"size": Vector3(0.6, 0.45, 0.35), "offset": Vector3(0, 0.45, -0.42),
				"front": extra_a, "side": extra_a, "top": body_top, "back": extra_a,
				"bottom": extra_a})
			for side in [-1.0, 1.0]:
				for index in 3:
					parts.append({"size": Vector3(0.55, 0.08, 0.08),
						"offset": Vector3(side * 0.32, 0.42, 0.3 - index * 0.3),
						"front": limb, "side": limb, "top": limb, "back": limb, "bottom": limb})
		_:
			# humanoid: head, body, arms, legs
			parts.append({"size": Vector3(0.5, 0.5, 0.5), "offset": Vector3(0, 1.45, 0),
				"front": head_front, "side": head_side, "top": head_top, "back": head_back,
				"bottom": head_side})
			parts.append({"size": Vector3(0.5, 0.75, 0.28), "offset": Vector3(0, 0.83, 0),
				"front": body_front, "side": body_side, "top": body_top, "back": body_back,
				"bottom": body_side})
			parts.append({"size": Vector3(0.22, 0.75, 0.22), "offset": Vector3(0.36, 0.83, 0),
				"front": limb, "side": limb, "top": limb_top, "back": limb, "bottom": limb})
			parts.append({"size": Vector3(0.22, 0.75, 0.22), "offset": Vector3(-0.36, 0.83, 0),
				"front": limb, "side": limb, "top": limb_top, "back": limb, "bottom": limb})
			parts.append({"size": Vector3(0.24, 0.72, 0.24), "offset": Vector3(0.12, 0.1, 0),
				"front": extra_c_or(limb), "side": extra_c_or(limb), "top": limb_top,
				"back": extra_c_or(limb), "bottom": extra_c_or(limb)})
			parts.append({"size": Vector3(0.24, 0.72, 0.24), "offset": Vector3(-0.12, 0.1, 0),
				"front": extra_c_or(limb), "side": extra_c_or(limb), "top": limb_top,
				"back": extra_c_or(limb), "bottom": extra_c_or(limb)})
	if child_scale != 1.0:
		for part in parts:
			part["offset"] = (part["offset"] as Vector3) * child_scale
			part["size"] = (part["size"] as Vector3) * child_scale
	return parts


static func _tile(tiles: Dictionary, key: String) -> Rect2:
	return tiles.get(key, Rect2(0, 0, 16, 16))


static func mid_tile(a: Rect2, fallback: Rect2) -> Rect2:
	return a if a.size.x > 0.0 else fallback


static func extra_c_or(fallback: Rect2) -> Rect2:
	return fallback
