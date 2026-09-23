## Godot-owned GPU resource uploader for decoded RenderPearl resource handles.
##
## Java never imports this class. The GDExtension owns the Java-to-native
## mailbox and exposes only validated metadata/retained byte ranges; this
## adapter allocates and uploads matching RenderingDevice resources. GPU calls
## run on Godot's render thread. Pipeline, pass, bindings, and draw-list
## execution remain separate backend slices.
class_name RenderPearlRenderingDeviceExecutor
extends Node

const BUFFER_ID := 0
const BUFFER_SIZE := 1
const BUFFER_REVISION := 2

const TEXTURE_ID := 0
const TEXTURE_USAGE := 1
const TEXTURE_FORMAT := 2
const TEXTURE_WIDTH := 3
const TEXTURE_HEIGHT := 4
const TEXTURE_DEPTH_OR_LAYERS := 5
const TEXTURE_MIP_LEVELS := 6
const TEXTURE_REVISION := 7

# GDExtension transfer requests are capped in native code too. Keeping chunks
# bounded avoids one untrusted mailbox packet allocating an unbounded Variant.
const MAX_TRANSFER_CHUNK_BYTES := 4 * 1024 * 1024

# RenderPearl's extracted 26.3 enum ordinal for GpuFormat.RGBA8_UNORM.
const RENDERPEARL_RGBA8_UNORM := 6

var _rendering_device_available := false
var _submitted_buffer_sizes: Dictionary = {}
var _submitted_buffer_revisions: Dictionary = {}
var _submitted_texture_signatures: Dictionary = {}
var _submitted_texture_revisions: Dictionary = {}
var _gpu_buffers: Dictionary = {}
var _gpu_buffer_sizes: Dictionary = {}
var _gpu_textures: Dictionary = {}
var _gpu_texture_signatures: Dictionary = {}


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
	if buffers.is_empty() and textures.is_empty():
		return {}
	return {"buffers": buffers, "textures": textures}


func _collect_buffers(native_bridge: Object) -> Array:
	var uploads: Array = []
	var count: int = native_bridge.call(&"get_render_buffer_count")
	for index in range(count):
		var resource_id: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_ID)
		var size_bytes: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_SIZE)
		var revision: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_REVISION)
		if resource_id <= 0 or size_bytes <= 0 or revision <= 0:
			continue
		if _submitted_buffer_sizes.get(resource_id, -1) == size_bytes \
				and _submitted_buffer_revisions.get(resource_id, -1) == revision:
			continue
		var bytes := _read_buffer_bytes(native_bridge, resource_id, size_bytes)
		if bytes.size() != size_bytes:
			push_warning("RenderPearl buffer %d byte transfer was incomplete" % resource_id)
			continue
		_submitted_buffer_sizes[resource_id] = size_bytes
		_submitted_buffer_revisions[resource_id] = revision
		uploads.append({"id": resource_id, "size": size_bytes, "bytes": bytes})
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


func _apply_snapshot(snapshot: Dictionary) -> void:
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return
	for buffer_variant in snapshot.get("buffers", []):
		_apply_buffer(rendering_device, buffer_variant)
	for texture_variant in snapshot.get("textures", []):
		_apply_texture(rendering_device, texture_variant)


func _apply_buffer(rendering_device: RenderingDevice, buffer_upload: Dictionary) -> void:
	var resource_id: int = buffer_upload["id"]
	var size_bytes: int = buffer_upload["size"]
	var bytes: PackedByteArray = buffer_upload["bytes"]
	var existing: RID = _gpu_buffers.get(resource_id, RID())
	if existing.is_valid() and _gpu_buffer_sizes.get(resource_id, -1) == size_bytes:
		var update_result := rendering_device.buffer_update(existing, 0, size_bytes, bytes)
		if update_result != OK:
			push_warning("RenderPearl buffer %d upload failed: %d" % [resource_id, update_result])
		return
	if existing.is_valid():
		rendering_device.free_rid(existing)
	# Usage-specific buffer types belong with pipeline/binding realization.
	# Storage buffers can retain the exact bytes until that slice exists.
	var created := rendering_device.storage_buffer_create(size_bytes, bytes)
	if not created.is_valid():
		push_warning("RenderPearl buffer %d allocation failed" % resource_id)
		_gpu_buffers.erase(resource_id)
		_gpu_buffer_sizes.erase(resource_id)
		return
	_gpu_buffers[resource_id] = created
	_gpu_buffer_sizes[resource_id] = size_bytes


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


func _free_gpu_resources() -> void:
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return
	for rid_variant in _gpu_buffers.values():
		rendering_device.free_rid(rid_variant)
	for rid_variant in _gpu_textures.values():
		rendering_device.free_rid(rid_variant)
	_gpu_buffers.clear()
	_gpu_buffer_sizes.clear()
	_gpu_textures.clear()
	_gpu_texture_signatures.clear()


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
