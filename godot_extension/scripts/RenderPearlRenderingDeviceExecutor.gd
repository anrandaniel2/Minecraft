## Godot-owned GPU resource uploader and GUI draw executor.
##
## Java never imports this class. The GDExtension owns the Java-to-native
## mailbox and exposes only validated metadata/retained byte ranges. This
## adapter uploads those resources and replays Java GuiRenderer draws into the
## same offscreen target. It does not rebuild menus, HUD, or text as Godot
## controls. GPU calls run on Godot's render thread.
class_name RenderPearlRenderingDeviceExecutor
extends Node

signal color_target_presented(texture: Texture2DRD, size: Vector2i)
signal java_gui_presented

const GuiDrawListScript = preload("res://scripts/RenderPearlGuiDrawList.gd")

const BUFFER_ID := 0
const BUFFER_SIZE := 1
const BUFFER_REVISION := 2
const BUFFER_USAGE := 3

const USAGE_VERTEX := 32
const USAGE_INDEX := 64
const USAGE_UNIFORM := 128

const TEXTURE_ID := 0
const TEXTURE_USAGE := 1
const TEXTURE_FORMAT := 2
const TEXTURE_WIDTH := 3
const TEXTURE_HEIGHT := 4
const TEXTURE_DEPTH_OR_LAYERS := 5
const TEXTURE_MIP_LEVELS := 6
const TEXTURE_REVISION := 7

const PASS_COLOR_TEXTURE_ID := 0
const PASS_DEPTH_TEXTURE_ID := 1
const PASS_REVISION := 2
const PASS_DRAW_COUNT := 3
const PASS_CLEAR_RED_BITS := 4
const PASS_CLEAR_GREEN_BITS := 5
const PASS_CLEAR_BLUE_BITS := 6
const PASS_CLEAR_ALPHA_BITS := 7
const PASS_DRAW_START := 8

# GDExtension transfer requests are capped in native code too. Keeping chunks
# bounded avoids one untrusted mailbox packet allocating an unbounded Variant.
const MAX_TRANSFER_CHUNK_BYTES := 4 * 1024 * 1024

# RenderPearl's extracted 26.3 enum ordinal for GpuFormat.RGBA8_UNORM.
const RENDERPEARL_RGBA8_UNORM := 6

var _rendering_device_available := false
var _submitted_buffer_sizes: Dictionary = {}
var _submitted_buffer_revisions: Dictionary = {}
var _submitted_buffer_usages: Dictionary = {}
var _submitted_texture_signatures: Dictionary = {}
var _submitted_texture_revisions: Dictionary = {}
var _gpu_buffers: Dictionary = {}
var _gpu_buffer_sizes: Dictionary = {}
var _gpu_buffer_usages: Dictionary = {}
var _gui_draws: RefCounted = GuiDrawListScript.new()
var java_gui_draw_count := 0
var _gpu_textures: Dictionary = {}
var _gpu_texture_signatures: Dictionary = {}
var _gpu_framebuffers: Dictionary = {}
var _submitted_pass_revision := 0
var _presented_texture: Texture2DRD
var _presented_rid := RID()


func _ready() -> void:
	# The getter is safe from the main thread and returns null in
	# headless/Compatibility runs. Methods on the returned device are not safe
	# there, so every allocation and upload is deferred to the render thread.
	_rendering_device_available = RenderingServer.get_rendering_device() != null


func synchronize(native_bridge: Object) -> bool:
	if not _rendering_device_available or native_bridge == null:
		return false
	var snapshot := _collect_snapshot(native_bridge)
	if snapshot.is_empty():
		return true
	RenderingServer.call_on_render_thread(_apply_snapshot.bind(snapshot))
	return true


func allocated_buffer_count() -> int:
	return _submitted_buffer_sizes.size()


func allocated_texture_count() -> int:
	return _submitted_texture_signatures.size()


func _exit_tree() -> void:
	if not _rendering_device_available:
		return
	# The node may be freed before the render thread runs this callable. Godot
	# releases the whole RenderingDevice on shutdown, so a missed callback only
	# leaks until process exit.
	RenderingServer.call_on_render_thread(_free_gpu_resources)


func _collect_snapshot(native_bridge: Object) -> Dictionary:
	var buffers: Array = _collect_buffers(native_bridge)
	var textures: Array = _collect_textures(native_bridge)
	var render_pass := _collect_pass(native_bridge)
	var frame_passes: Array = _collect_frame_passes(native_bridge)
	var draws: Array = _collect_draws(native_bridge)
	if buffers.is_empty() and textures.is_empty() and render_pass.is_empty() and draws.is_empty():
		return {}
	return {
		"buffers": buffers,
		"textures": textures,
		"pass": render_pass,
		"passes": frame_passes,
		"draws": draws,
	}


func _collect_buffers(native_bridge: Object) -> Array:
	var uploads: Array = []
	var count: int = native_bridge.call(&"get_render_buffer_count")
	for index in range(count):
		var resource_id: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_ID)
		var size_bytes: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_SIZE)
		var revision: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_REVISION)
		var usage: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_USAGE)
		if resource_id <= 0 or size_bytes <= 0 or revision <= 0:
			continue
		if _submitted_buffer_sizes.get(resource_id, -1) == size_bytes \
				and _submitted_buffer_revisions.get(resource_id, -1) == revision \
				and _submitted_buffer_usages.get(resource_id, -1) == usage:
			continue
		var bytes := _read_buffer_bytes(native_bridge, resource_id, size_bytes)
		if bytes.size() != size_bytes:
			push_warning("RenderPearl buffer %d byte transfer was incomplete" % resource_id)
			continue
		_submitted_buffer_sizes[resource_id] = size_bytes
		_submitted_buffer_revisions[resource_id] = revision
		_submitted_buffer_usages[resource_id] = usage
		uploads.append({
			"id": resource_id,
			"size": size_bytes,
			"usage": usage,
			"bytes": bytes,
		})
	return uploads


func _collect_textures(native_bridge: Object) -> Array:
	var uploads: Array = []
	var count: int = native_bridge.call(&"get_render_texture_count")
	for index in range(count):
		var resource_id: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_ID)
		var format: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_FORMAT)
		var width: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_WIDTH)
		var height: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_HEIGHT)
		var depth_or_layers: int = native_bridge.call(
			&"get_render_texture_attribute", index, TEXTURE_DEPTH_OR_LAYERS
		)
		var mip_levels: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_MIP_LEVELS)
		var revision: int = native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_REVISION)
		if resource_id <= 0 or width <= 0 or height <= 0 or depth_or_layers <= 0 or mip_levels <= 0 or revision <= 0:
			continue
		var signature := [Vector4i(format, width, height, depth_or_layers), mip_levels]
		if format != RENDERPEARL_RGBA8_UNORM:
			if _submitted_texture_signatures.get(resource_id) != signature:
				push_warning("RenderPearl texture format %d is not mapped to Godot yet" % format)
				_submitted_texture_signatures[resource_id] = signature
			continue
		if _submitted_texture_signatures.get(resource_id) == signature \
				and _submitted_texture_revisions.get(resource_id, -1) == revision:
			continue
		var layers := _read_texture_layers(native_bridge, resource_id, depth_or_layers, mip_levels)
		if layers.is_empty():
			push_warning("RenderPearl texture %d byte transfer was incomplete" % resource_id)
			continue
		_submitted_texture_signatures[resource_id] = signature
		_submitted_texture_revisions[resource_id] = revision
		uploads.append({
			"id": resource_id,
			"format": format,
			"width": width,
			"height": height,
			"layers": depth_or_layers,
			"mip_levels": mip_levels,
			"signature": signature,
			"layer_bytes": layers,
		})
	return uploads


func _read_buffer_bytes(native_bridge: Object, resource_id: int, size_bytes: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	var offset := 0
	while offset < size_bytes:
		var request_size := mini(MAX_TRANSFER_CHUNK_BYTES, size_bytes - offset)
		var chunk = native_bridge.call(&"get_render_buffer_bytes", resource_id, offset, request_size)
		if typeof(chunk) != TYPE_PACKED_BYTE_ARRAY or chunk.size() != request_size:
			return PackedByteArray()
		bytes.append_array(chunk)
		offset += request_size
	return bytes


func _read_texture_layers(
		native_bridge: Object,
		resource_id: int,
		layer_count: int,
		mip_levels: int
) -> Array:
	var layers: Array = []
	for layer in range(layer_count):
		var layer_bytes := PackedByteArray()
		for mip_level in range(mip_levels):
			var mip_size: int = native_bridge.call(
				&"get_render_texture_mip_layer_size", resource_id, mip_level, layer
			)
			if mip_size <= 0:
				return []
			var offset := 0
			while offset < mip_size:
				var request_size := mini(MAX_TRANSFER_CHUNK_BYTES, mip_size - offset)
				var chunk = native_bridge.call(
					&"get_render_texture_mip_layer_bytes",
					resource_id,
					mip_level,
					layer,
					offset,
					request_size
				)
				if typeof(chunk) != TYPE_PACKED_BYTE_ARRAY or chunk.size() != request_size:
					return []
				layer_bytes.append_array(chunk)
				offset += request_size
		layers.append(layer_bytes)
	return layers


func _collect_frame_passes(native_bridge: Object) -> Array:
	if not native_bridge.has_method(&"get_render_frame_pass_count"):
		return []
	var passes: Array = []
	var count: int = native_bridge.call(&"get_render_frame_pass_count")
	for index in range(count):
		var color_id: int = native_bridge.call(
				&"get_render_frame_pass_attribute", index, PASS_COLOR_TEXTURE_ID
		)
		if color_id <= 0:
			continue
		var size := _texture_size(native_bridge, color_id)
		var clear_alpha := _bits_to_float(
			native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_CLEAR_ALPHA_BITS)
		)
		passes.append({
			"color_id": color_id,
			"depth_id": native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_DEPTH_TEXTURE_ID),
			"draw_count": native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_DRAW_COUNT),
			"draw_start": native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_DRAW_START),
			"size": size,
			"clear_enabled": clear_alpha >= 0.0,
			"clear": Color(
				_bits_to_float(native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_CLEAR_RED_BITS)),
				_bits_to_float(native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_CLEAR_GREEN_BITS)),
				_bits_to_float(native_bridge.call(&"get_render_frame_pass_attribute", index, PASS_CLEAR_BLUE_BITS)),
				clampf(clear_alpha, 0.0, 1.0)
			),
		})
	return passes


func _collect_draws(native_bridge: Object) -> Array:
	if not native_bridge.has_method(&"get_render_draw_count"):
		return []
	var draws: Array = []
	var count: int = native_bridge.call(&"get_render_draw_count")
	for index in range(count):
		var pipeline_id: int = native_bridge.call(&"get_render_draw_attribute", index, 1)
		var family: int = native_bridge.call(&"get_render_draw_attribute", index, 2)
		var draw := {
			"family": family,
			"blend": native_bridge.call(&"get_render_draw_attribute", index, 3),
			"topology": native_bridge.call(&"get_render_draw_attribute", index, 4),
			"kind": native_bridge.call(&"get_render_draw_attribute", index, 5),
			"count": native_bridge.call(&"get_render_draw_attribute", index, 6),
			"instance_count": native_bridge.call(&"get_render_draw_attribute", index, 7),
			"first": native_bridge.call(&"get_render_draw_attribute", index, 8),
			"base_vertex": native_bridge.call(&"get_render_draw_attribute", index, 9),
			"vertex_buffer_id": native_bridge.call(&"get_render_draw_attribute", index, 11),
			"vertex_stride": native_bridge.call(&"get_render_draw_attribute", index, 12),
			"vertex_offset": native_bridge.call(&"get_render_draw_attribute", index, 13),
			"vertex_length": native_bridge.call(&"get_render_draw_attribute", index, 14),
			"index_buffer_id": native_bridge.call(&"get_render_draw_attribute", index, 15),
			"index_type": native_bridge.call(&"get_render_draw_attribute", index, 16),
			"index_offset": native_bridge.call(&"get_render_draw_attribute", index, 17),
			"scissor_x": native_bridge.call(&"get_render_draw_attribute", index, 19),
			"scissor_y": native_bridge.call(&"get_render_draw_attribute", index, 20),
			"scissor_width": native_bridge.call(&"get_render_draw_attribute", index, 21),
			"scissor_height": native_bridge.call(&"get_render_draw_attribute", index, 22),
			"sampler0_texture_id": native_bridge.call(&"get_render_draw_attribute", index, 29),
			"sampler0_base_mip": native_bridge.call(&"get_render_draw_attribute", index, 30),
			"sampler0_min_filter": native_bridge.call(&"get_render_draw_attribute", index, 31),
			"sampler0_mag_filter": native_bridge.call(&"get_render_draw_attribute", index, 32),
			"sampler0_address_u": native_bridge.call(&"get_render_draw_attribute", index, 33),
			"sampler0_address_v": native_bridge.call(&"get_render_draw_attribute", index, 34),
			"grayscale": _pipeline_flag(native_bridge, pipeline_id, 1),
			"attributes": _collect_pipeline_attributes(native_bridge, pipeline_id),
			"dynamic_bytes": _read_bound_uniform(native_bridge, index, 23, 24, 25),
			"projection_bytes": _read_bound_uniform(native_bridge, index, 26, 27, 28),
			"target_size": _texture_size(
					native_bridge, native_bridge.call(&"get_render_draw_attribute", index, 0)
			),
		}
		draws.append(draw)
	return draws


func _pipeline_flag(native_bridge: Object, pipeline_id: int, bit: int) -> bool:
	if pipeline_id <= 0 or not native_bridge.has_method(&"get_render_pipeline_attribute"):
		return false
	# Attribute 5 is the native shader-identifier flag word. Bit 0 is grayscale.
	var flags: int = native_bridge.call(&"get_render_pipeline_attribute", pipeline_id, 5)
	return (flags & bit) != 0


func _collect_pipeline_attributes(native_bridge: Object, pipeline_id: int) -> Array:
	if pipeline_id <= 0 or not native_bridge.has_method(&"get_render_pipeline_attribute"):
		return []
	var count: int = native_bridge.call(&"get_render_pipeline_attribute", pipeline_id, 4)
	var attributes: Array = []
	for index in range(count):
		attributes.append({
			"location": native_bridge.call(&"get_render_pipeline_vertex_attribute", pipeline_id, index, 0),
			"offset": native_bridge.call(&"get_render_pipeline_vertex_attribute", pipeline_id, index, 1),
			"format": native_bridge.call(&"get_render_pipeline_vertex_attribute", pipeline_id, index, 2),
		})
	return attributes


func _read_bound_uniform(
		native_bridge: Object,
		draw_index: int,
		id_attribute: int,
		offset_attribute: int,
		length_attribute: int
) -> PackedByteArray:
	var buffer_id: int = native_bridge.call(&"get_render_draw_attribute", draw_index, id_attribute)
	var length: int = native_bridge.call(&"get_render_draw_attribute", draw_index, length_attribute)
	if buffer_id <= 0 or length <= 0:
		return PackedByteArray()
	var offset: int = native_bridge.call(&"get_render_draw_attribute", draw_index, offset_attribute)
	# GUI dynamic/projection blocks are at most a few std140 matrices.
	var request := mini(length, 256)
	var bytes = native_bridge.call(&"get_render_buffer_bytes", buffer_id, offset, request)
	if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray()
	return bytes


func _collect_pass(native_bridge: Object) -> Dictionary:
	var revision: int = native_bridge.call(&"get_render_pass_attribute", PASS_REVISION)
	var color_id: int = native_bridge.call(&"get_render_pass_attribute", PASS_COLOR_TEXTURE_ID)
	if revision <= 0 or color_id <= 0 or revision == _submitted_pass_revision:
		return {}
	var size := _texture_size(native_bridge, color_id)
	if size == Vector2i.ZERO:
		return {}
	_submitted_pass_revision = revision
	var clear_alpha := _bits_to_float(native_bridge.call(&"get_render_pass_attribute", PASS_CLEAR_ALPHA_BITS))
	return {
		"revision": revision,
		"color_id": color_id,
		"depth_id": native_bridge.call(&"get_render_pass_attribute", PASS_DEPTH_TEXTURE_ID),
		"draw_count": native_bridge.call(&"get_render_pass_attribute", PASS_DRAW_COUNT),
		"size": size,
		"clear_enabled": clear_alpha >= 0.0,
		"clear": Color(
			_bits_to_float(native_bridge.call(&"get_render_pass_attribute", PASS_CLEAR_RED_BITS)),
			_bits_to_float(native_bridge.call(&"get_render_pass_attribute", PASS_CLEAR_GREEN_BITS)),
			_bits_to_float(native_bridge.call(&"get_render_pass_attribute", PASS_CLEAR_BLUE_BITS)),
			clampf(clear_alpha, 0.0, 1.0)
		),
	}


func _texture_size(native_bridge: Object, texture_id: int) -> Vector2i:
	var count: int = native_bridge.call(&"get_render_texture_count")
	for index in range(count):
		if native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_ID) != texture_id:
			continue
		return Vector2i(
			native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_WIDTH),
			native_bridge.call(&"get_render_texture_attribute", index, TEXTURE_HEIGHT)
		)
	return Vector2i.ZERO


func _bits_to_float(bits: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, bits & 0xFFFFFFFF)
	return bytes.decode_float(0)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return
	for buffer_variant in snapshot.get("buffers", []):
		_apply_buffer(rendering_device, buffer_variant, snapshot)
	for texture_variant in snapshot.get("textures", []):
		_apply_texture(rendering_device, texture_variant)
	var passes: Array = snapshot.get("passes", [])
	var draws: Array = snapshot.get("draws", [])
	if not passes.is_empty():
		var result: Dictionary = _gui_draws.execute(
				rendering_device, _gpu_buffers, _gpu_textures, _gpu_framebuffers, passes, draws
		)
		var completed: int = result.get("draws", 0)
		if completed > 0:
			java_gui_draw_count = completed
			call_deferred("_emit_java_gui_presented")
		# Blur pyramids are smaller than the main GUI target. Present the last
		# largest target so an intermediate pass cannot cover the Java UI.
		var best: Dictionary = {}
		var best_area := 0
		for presented_variant in result.get("presented", []):
			var presented: Dictionary = presented_variant
			var size: Vector2i = presented["size"]
			var area := size.x * size.y
			if area >= best_area:
				best = presented
				best_area = area
		if not best.is_empty():
			_present_color_target(best["rid"], best["size"])
		return
	var render_pass: Dictionary = snapshot.get("pass", {})
	if not render_pass.is_empty():
		_clear_color_target(rendering_device, render_pass)


func _apply_buffer(rendering_device: RenderingDevice, buffer_upload: Dictionary, snapshot: Dictionary) -> void:
	var resource_id: int = buffer_upload["id"]
	var size_bytes: int = buffer_upload["size"]
	var usage: int = buffer_upload.get("usage", 0)
	var bytes: PackedByteArray = buffer_upload["bytes"]
	var existing: RID = _gpu_buffers.get(resource_id, RID())
	if existing.is_valid() and _gpu_buffer_sizes.get(resource_id, -1) == size_bytes \
			and _gpu_buffer_usages.get(resource_id, -1) == usage:
		var update_result := rendering_device.buffer_update(existing, 0, size_bytes, bytes)
		if update_result != OK:
			push_warning("RenderPearl buffer %d upload failed: %d" % [resource_id, update_result])
		return
	if existing.is_valid():
		rendering_device.free_rid(existing)
	var created := _create_buffer(rendering_device, usage, size_bytes, bytes, resource_id, snapshot)
	if not created.is_valid():
		push_warning("RenderPearl buffer %d allocation failed" % resource_id)
		_gpu_buffers.erase(resource_id)
		_gpu_buffer_sizes.erase(resource_id)
		_gpu_buffer_usages.erase(resource_id)
		return
	_gpu_buffers[resource_id] = created
	_gpu_buffer_sizes[resource_id] = size_bytes
	_gpu_buffer_usages[resource_id] = usage


func _apply_texture(rendering_device: RenderingDevice, texture_upload: Dictionary) -> void:
	var resource_id: int = texture_upload["id"]
	var signature: Array = texture_upload["signature"]
	var layer_bytes: Array = texture_upload["layer_bytes"]
	var existing: RID = _gpu_textures.get(resource_id, RID())
	if existing.is_valid() and _gpu_texture_signatures.get(resource_id) == signature:
		for layer in range(layer_bytes.size()):
			var update_result := rendering_device.texture_update(existing, layer, layer_bytes[layer])
			if update_result != OK:
				push_warning("RenderPearl texture %d layer %d upload failed: %d" % [
					resource_id, layer, update_result
				])
				return
		return
	if existing.is_valid():
		_release_framebuffer(rendering_device, resource_id)
		rendering_device.free_rid(existing)
	var texture_format := _make_texture_format(
		texture_upload["format"],
		texture_upload["width"],
		texture_upload["height"],
		texture_upload["layers"],
		texture_upload["mip_levels"]
	)
	if texture_format == null:
		return
	var initial_data: Array[PackedByteArray] = []
	initial_data.assign(layer_bytes)
	var created := rendering_device.texture_create(texture_format, RDTextureView.new(), initial_data)
	if not created.is_valid():
		push_warning("RenderPearl texture %d allocation failed" % resource_id)
		_gpu_textures.erase(resource_id)
		_gpu_texture_signatures.erase(resource_id)
		return
	_gpu_textures[resource_id] = created
	_gpu_texture_signatures[resource_id] = signature


func _release_framebuffer(rendering_device: RenderingDevice, texture_id: int) -> void:
	var framebuffer: RID = _gpu_framebuffers.get(texture_id, RID())
	if framebuffer.is_valid():
		rendering_device.free_rid(framebuffer)
	_gpu_framebuffers.erase(texture_id)
	if _presented_rid == _gpu_textures.get(texture_id, RID()):
		_presented_rid = RID()


func _clear_color_target(rendering_device: RenderingDevice, render_pass: Dictionary) -> void:
	var color_id: int = render_pass["color_id"]
	var color_texture: RID = _gpu_textures.get(color_id, RID())
	if not color_texture.is_valid():
		return
	var framebuffer: RID = _gpu_framebuffers.get(color_id, RID())
	if not framebuffer.is_valid():
		var attachments: Array[RID] = [color_texture]
		framebuffer = rendering_device.framebuffer_create(attachments)
		if not framebuffer.is_valid():
			push_warning("RenderPearl color target %d framebuffer allocation failed" % color_id)
			return
		_gpu_framebuffers[color_id] = framebuffer
	var clear_enabled: bool = render_pass.get("clear_enabled", true)
	var draw_list := rendering_device.draw_list_begin(
		framebuffer,
		RenderingDevice.DRAW_CLEAR_COLOR_0 if clear_enabled else 0,
		PackedColorArray([render_pass["clear"]]) if clear_enabled else PackedColorArray(),
		1.0,
		0,
		Rect2()
	)
	if draw_list < 0:
		push_warning("RenderPearl color target %d clear failed" % color_id)
		return
	rendering_device.draw_list_end()
	_present_color_target(color_texture, render_pass["size"])


func _present_color_target(color_texture: RID, size: Vector2i) -> void:
	# The protocol smoke frame is a 1×1 transport check. Do not cover the
	# resource-pack fallback viewport with that placeholder target.
	if size.x <= 1 or size.y <= 1:
		return
	if _presented_rid == color_texture and _presented_texture != null:
		return
	_presented_rid = color_texture
	call_deferred("_emit_color_target", color_texture, size)


func _emit_java_gui_presented() -> void:
	java_gui_presented.emit()


func _emit_color_target(color_texture: RID, size: Vector2i) -> void:
	if _presented_texture == null:
		_presented_texture = Texture2DRD.new()
	_presented_texture.texture_rd_rid = color_texture
	color_target_presented.emit(_presented_texture, size)


func _free_gpu_resources() -> void:
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return
	for rid_variant in _gpu_buffers.values():
		rendering_device.free_rid(rid_variant)
	for rid_variant in _gpu_framebuffers.values():
		rendering_device.free_rid(rid_variant)
	for rid_variant in _gpu_textures.values():
		rendering_device.free_rid(rid_variant)
	_gpu_buffers.clear()
	_gpu_buffer_sizes.clear()
	_gpu_buffer_usages.clear()
	_gpu_textures.clear()
	_gpu_texture_signatures.clear()
	_gpu_framebuffers.clear()


func _create_buffer(
		rendering_device: RenderingDevice,
		usage: int,
		size_bytes: int,
		bytes: PackedByteArray,
		resource_id: int,
		snapshot: Dictionary
) -> RID:
	if usage & USAGE_INDEX != 0 and usage & USAGE_VERTEX == 0:
		var index_type := _index_type_for(snapshot, resource_id)
		var stride := 4 if index_type == RenderingDevice.INDEX_BUFFER_FORMAT_UINT32 else 2
		if size_bytes % stride != 0:
			push_warning("RenderPearl index buffer %d size is not aligned" % resource_id)
			return RID()
		return rendering_device.index_buffer_create(size_bytes // stride, index_type, bytes, false, 0)
	if usage & USAGE_VERTEX != 0:
		return rendering_device.vertex_buffer_create(size_bytes, bytes)
	if usage & USAGE_UNIFORM != 0:
		return rendering_device.uniform_buffer_create(size_bytes, bytes)
	return rendering_device.storage_buffer_create(size_bytes, bytes)


func _index_type_for(snapshot: Dictionary, buffer_id: int) -> int:
	for draw_variant in snapshot.get("draws", []):
		var draw: Dictionary = draw_variant
		if int(draw.get("index_buffer_id", 0)) == buffer_id:
			return int(draw.get("index_type", 0))
	return RenderingDevice.INDEX_BUFFER_FORMAT_UINT16


func _make_texture_format(
		format: int,
		width: int,
		height: int,
		depth_or_layers: int,
		mip_levels: int
) -> RDTextureFormat:
	if format != RENDERPEARL_RGBA8_UNORM:
		return null
	var texture_format := RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	if depth_or_layers > 1:
		texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	texture_format.width = width
	texture_format.height = height
	texture_format.depth = 1
	texture_format.array_layers = depth_or_layers
	texture_format.mipmaps = mip_levels
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	return texture_format
