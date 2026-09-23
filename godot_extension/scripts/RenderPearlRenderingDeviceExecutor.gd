## Godot-owned GPU resource allocator for decoded RenderPearl resource handles.
##
## Java never imports this class. The GDExtension owns the Java-to-native
## mailbox and exposes only validated metadata; this adapter allocates matching
## RenderingDevice resources in Godot's rendering context. Upload/update and
## draw-list execution are added as their command sinks become available.
class_name RenderPearlRenderingDeviceExecutor
extends Node

const BUFFER_ID := 0
const BUFFER_SIZE := 1

const TEXTURE_ID := 0
const TEXTURE_USAGE := 1
const TEXTURE_FORMAT := 2
const TEXTURE_WIDTH := 3
const TEXTURE_HEIGHT := 4
const TEXTURE_DEPTH_OR_LAYERS := 5
const TEXTURE_MIP_LEVELS := 6

# RenderPearl's extracted 26.3 enum ordinal for GpuFormat.RGBA8_UNORM.
const RENDERPEARL_RGBA8_UNORM := 6

var _rd: RenderingDevice
var _buffers: Dictionary = {}
var _buffer_sizes: Dictionary = {}
var _textures: Dictionary = {}
var _texture_signatures: Dictionary = {}


func _ready() -> void:
	# RenderingDevice is intentionally absent in headless/Compatibility runs.
	# The native command sink remains active there, while Forward+/Mobile builds
	# allocate real Godot GPU resources through this node.
	_rd = RenderingServer.get_rendering_device()


func synchronize(native_bridge: Object) -> bool:
	if _rd == null or native_bridge == null:
		return false
	_sync_buffers(native_bridge)
	_sync_textures(native_bridge)
	return true


func allocated_buffer_count() -> int:
	return _buffers.size()


func allocated_texture_count() -> int:
	return _textures.size()


func _exit_tree() -> void:
	if _rd == null:
		return
	for rid_variant in _buffers.values():
		_rd.free_rid(rid_variant)
	for rid_variant in _textures.values():
		_rd.free_rid(rid_variant)
	_buffers.clear()
	_textures.clear()


func _sync_buffers(native_bridge: Object) -> void:
	var count: int = native_bridge.call(&"get_render_buffer_count")
	for index in range(count):
		var resource_id: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_ID)
		var size_bytes: int = native_bridge.call(&"get_render_buffer_attribute", index, BUFFER_SIZE)
		if resource_id <= 0 or size_bytes <= 0:
			continue
		if _buffer_sizes.get(resource_id, -1) == size_bytes:
			continue
		if _buffers.has(resource_id):
			_rd.free_rid(_buffers[resource_id])
		# Initial contents and subsequent updates are retained by the native sink;
		# the next upload bridge slice copies them into this GPU allocation.
		_buffers[resource_id] = _rd.storage_buffer_create(size_bytes)
		_buffer_sizes[resource_id] = size_bytes


func _sync_textures(native_bridge: Object) -> void:
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
		if resource_id <= 0 or width <= 0 or height <= 0 or depth_or_layers <= 0 or mip_levels <= 0:
			continue
		var signature := Vector4i(format, width, height, depth_or_layers)
		if _texture_signatures.get(resource_id) == [signature, mip_levels]:
			continue
		if _textures.has(resource_id):
			_rd.free_rid(_textures[resource_id])
		var texture_format := _make_texture_format(format, width, height, depth_or_layers, mip_levels)
		if texture_format == null:
			push_warning("RenderPearl texture format %d is not mapped to Godot yet" % format)
			continue
		_textures[resource_id] = _rd.texture_create(texture_format, RDTextureView.new())
		_texture_signatures[resource_id] = [signature, mip_levels]


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
