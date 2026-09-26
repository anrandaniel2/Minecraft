## Draws retained Java GuiRenderer passes into a Godot RenderingDevice framebuffer.
##
## This is not a Godot control rewrite. The vertex data, uniforms, scissor, and
## texture bindings come from the Java RenderPearl command stream. Only the
## three extracted GUI shader families are translated; unknown pipelines are
## skipped so world rendering can arrive without failing GUI frames.
extends RefCounted

const FAMILY_GUI_COLOR := 1
const FAMILY_GUI_TEXTURED := 2
const FAMILY_GUI_TEXT := 3

const KIND_DRAW := 1
const KIND_DRAW_INDEXED := 2

const BLEND_ALPHA := 0
const BLEND_PREMULTIPLIED := 1
const BLEND_OPAQUE := 2
const BLEND_ADDITIVE := 3
# RenderPearl BlendFunction.INVERT: one-minus-destination over one-minus-source.
const BLEND_INVERT := 4

# PrimitiveTopology ordinals from the extracted 26.3 enum.
const TOPOLOGY_TRIANGLE_FAN := 6
const TOPOLOGY_QUADS := 7

# RenderPearl GpuFormat ordinals used by GUI vertex elements.
const GPU_RGBA8_UNORM := 6
const GPU_R32_FLOAT := 44
const GPU_RG32_FLOAT := 45
const GPU_RGB32_FLOAT := 46
const GPU_RGBA32_FLOAT := 47

# Godot SamplerRepeatMode: repeat 0, mirrored 1, clamp-to-edge 2.
const REPEAT_CLAMP_TO_EDGE := 2

var _shaders: Dictionary = {}
var _pipelines: Dictionary = {}
var _samplers: Dictionary = {}
var _white_texture := RID()


func free_resources(rendering_device: RenderingDevice) -> void:
	if rendering_device == null:
		return
	for rid_variant in _pipelines.values():
		rendering_device.free_rid(rid_variant)
	for rid_variant in _shaders.values():
		rendering_device.free_rid(rid_variant)
	for rid_variant in _samplers.values():
		rendering_device.free_rid(rid_variant)
	if _white_texture.is_valid():
		rendering_device.free_rid(_white_texture)
	_pipelines.clear()
	_shaders.clear()
	_samplers.clear()
	_white_texture = RID()


func execute(
		rendering_device: RenderingDevice,
		buffer_rids: Dictionary,
		texture_rids: Dictionary,
		framebuffers: Dictionary,
		passes: Array,
		draws: Array
) -> Dictionary:
	var presented: Array = []
	var completed := 0
	for pass_variant in passes:
		var render_pass: Dictionary = pass_variant
		var color_id: int = render_pass.get("color_id", 0)
		var color_texture: RID = texture_rids.get(color_id, RID())
		if not color_texture.is_valid():
			continue
		var framebuffer := _framebuffer(rendering_device, framebuffers, color_id, color_texture)
		if not framebuffer.is_valid():
			continue
		var start: int = render_pass.get("draw_start", 0)
		var count: int = render_pass.get("draw_count", 0)
		var prepared: Array = []
		var temporary: Array[RID] = []
		for index in range(start, mini(start + count, draws.size())):
			var ready := _prepare_draw(
					rendering_device, draws[index], buffer_rids, texture_rids, framebuffer, temporary
			)
			if not ready.is_empty():
				prepared.append(ready)
		# Empty RenderPearl clear values mean load, not opaque black. A later GUI
		# pass must not wipe the world or blur target it composites onto.
		var clear_enabled: bool = render_pass.get("clear_enabled", true)
		var clear_colors := PackedColorArray()
		var clear_flags := 0
		if clear_enabled:
			clear_flags = RenderingDevice.DRAW_CLEAR_COLOR_0
			clear_colors = PackedColorArray([render_pass.get("clear", Color(0, 0, 0, 0))])
		var draw_list := rendering_device.draw_list_begin(
			framebuffer,
			clear_flags,
			clear_colors,
			1.0,
			0,
			Rect2(),
			0
		)
		if draw_list < 0:
			push_warning("RenderPearl GUI pass framebuffer %d could not begin" % color_id)
			_free_rids(rendering_device, temporary)
			continue
		for ready_variant in prepared:
			if _record_draw(rendering_device, draw_list, ready_variant):
				completed += 1
		rendering_device.draw_list_end()
		_free_rids(rendering_device, temporary)
		var size: Vector2i = render_pass.get("size", Vector2i.ZERO)
		if size.x > 1 and size.y > 1:
			presented.append({"rid": color_texture, "size": size})
	return {"draws": completed, "presented": presented}


func _free_rids(rendering_device: RenderingDevice, rids: Array[RID]) -> void:
	for rid in rids:
		if rid.is_valid():
			rendering_device.free_rid(rid)


func _prepare_draw(
		rendering_device: RenderingDevice,
		draw: Dictionary,
		buffer_rids: Dictionary,
		texture_rids: Dictionary,
		framebuffer: RID,
		temporary: Array[RID]
) -> Dictionary:
	var family: int = draw.get("family", 0)
	if family < FAMILY_GUI_COLOR or family > FAMILY_GUI_TEXT:
		return {}
	var stride: int = draw.get("vertex_stride", 0)
	var vertex_buffer: RID = buffer_rids.get(draw.get("vertex_buffer_id", 0), RID())
	if stride <= 0 or not vertex_buffer.is_valid():
		return {}
	var pipeline := _pipeline(rendering_device, framebuffer, family, draw)
	if not pipeline.is_valid():
		return {}
	var scissor := Rect2(
			draw.get("scissor_x", 0),
			draw.get("scissor_y", 0),
			draw.get("scissor_width", 0),
			draw.get("scissor_height", 0)
	)
	if scissor.size.x <= 0.0 or scissor.size.y <= 0.0:
		return {}
	var topology := int(draw.get("topology", 4))
	var indexed: bool = int(draw.get("kind", 0)) == KIND_DRAW_INDEXED
	# Vulkan draws QUADS as triangle lists. Indexed GUI buffers are already the
	# sequential 0,1,2,2,3,0 expansion. Non-indexed quads and fans are not.
	var expand_quads := topology == TOPOLOGY_QUADS and not indexed
	var expand_fan := topology == TOPOLOGY_TRIANGLE_FAN and not indexed
	var vertex_shift := int(draw.get("base_vertex", 0)) if indexed else int(draw.get("first", 0))
	var byte_offset := int(draw.get("vertex_offset", 0)) + vertex_shift * stride
	if byte_offset < 0:
		return {}
	var vertex_format: int = _vertex_format(rendering_device, family, stride, draw.get("attributes", []))
	if vertex_format <= 0:
		return {}
	var vertex_count := int(draw.get("count", 0))
	if indexed:
		var remaining := int(draw.get("vertex_length", 0)) - vertex_shift * stride
		vertex_count = int(remaining / stride) if remaining > 0 else vertex_count
		# The slice length is the whole staging buffer. Indexed GUI draws only
		# need the vertices their index count addresses; a huge array create
		# fails and the text quad is never presented.
		var index_count := int(draw.get("count", 0))
		if topology == TOPOLOGY_QUADS and index_count >= 6:
			vertex_count = mini(vertex_count, int(index_count / 6) * 4)
		elif index_count > 0 and index_count < vertex_count:
			vertex_count = index_count
	if vertex_count <= 0:
		return {}
	var buffers: Array[RID] = [vertex_buffer]
	var array := rendering_device.vertex_array_create(
			vertex_count,
			vertex_format,
			buffers,
			PackedInt64Array([byte_offset])
	)
	if not array.is_valid():
		return {}
	temporary.append(array)
	var index_array := RID()
	if expand_quads or expand_fan:
		var expanded := _expanded_index_array(rendering_device, vertex_count, expand_fan)
		index_array = expanded.get("array", RID())
		if not index_array.is_valid():
			return {}
		temporary.append(expanded["buffer"])
		temporary.append(index_array)
		indexed = true
	elif indexed:
		index_array = _index_array(rendering_device, draw, buffer_rids)
		if not index_array.is_valid():
			# GuiRenderer's non-sorted draws use the shared sequential quad
			# buffer. If that buffer was not in the executed frame, rebuild the
			# same 0,1,2,2,3,0 expansion so the text quad can still be presented.
			var fallback_expanded := _expanded_index_array(rendering_device, vertex_count, expand_fan)
			index_array = fallback_expanded.get("array", RID())
			if not index_array.is_valid():
				return {}
			temporary.append(fallback_expanded["buffer"])
			temporary.append(index_array)
		else:
			temporary.append(index_array)
	var shader: RID = _shaders.get(_shader_key(family, draw), RID())
	var uniform_sets := _uniform_sets(rendering_device, shader, family, draw, texture_rids, temporary)
	if uniform_sets.is_empty():
		return {}
	return {
		"pipeline": pipeline,
		"scissor": scissor,
		"indexed": indexed,
		"vertex_array": array,
		"index_array": index_array,
		"uniform_sets": uniform_sets,
		"instances": maxi(int(draw.get("instance_count", 1)), 1),
	}


func _record_draw(rendering_device: RenderingDevice, draw_list: int, ready: Dictionary) -> bool:
	rendering_device.draw_list_bind_render_pipeline(draw_list, ready["pipeline"])
	rendering_device.draw_list_enable_scissor(draw_list, ready["scissor"])
	var sets: Array = ready["uniform_sets"]
	for set_index in range(sets.size()):
		rendering_device.draw_list_bind_uniform_set(draw_list, sets[set_index], set_index)
	rendering_device.draw_list_bind_vertex_array(draw_list, ready["vertex_array"])
	if ready["indexed"]:
		rendering_device.draw_list_bind_index_array(draw_list, ready["index_array"])
	rendering_device.draw_list_draw(draw_list, ready["indexed"], ready["instances"], 0)
	return true


func _uniform_sets(
		rendering_device: RenderingDevice,
		shader: RID,
		family: int,
		draw: Dictionary,
		texture_rids: Dictionary,
		temporary: Array[RID]
) -> Array:
	if not shader.is_valid():
		return []
	var dynamic_bytes := _align16(draw.get("dynamic_bytes", PackedByteArray()))
	if dynamic_bytes.is_empty():
		dynamic_bytes = _identity_dynamic()
	var projection_bytes := _align16(draw.get("projection_bytes", PackedByteArray()))
	if projection_bytes.size() < 64:
		var size: Vector2i = draw.get("target_size", Vector2i(1, 1))
		projection_bytes = _ortho(float(maxi(size.x, 1)), float(maxi(size.y, 1)))
	var dynamic_buffer := rendering_device.uniform_buffer_create(dynamic_bytes.size(), dynamic_bytes)
	var projection_buffer := rendering_device.uniform_buffer_create(projection_bytes.size(), projection_bytes)
	if not dynamic_buffer.is_valid() or not projection_buffer.is_valid():
		return []
	temporary.append(dynamic_buffer)
	temporary.append(projection_buffer)
	var dynamic_set := _uniform_buffer_set(rendering_device, shader, 0, dynamic_buffer)
	var projection_set := _uniform_buffer_set(rendering_device, shader, 1, projection_buffer)
	if not dynamic_set.is_valid() or not projection_set.is_valid():
		return []
	temporary.append(dynamic_set)
	temporary.append(projection_set)
	var sets: Array = [dynamic_set, projection_set]
	if family == FAMILY_GUI_COLOR:
		return sets
	var texture: RID = texture_rids.get(draw.get("sampler0_texture_id", 0), RID())
	if not texture.is_valid():
		texture = _white(rendering_device)
	var base_mip: int = draw.get("sampler0_base_mip", 0)
	if base_mip > 0:
		var sliced := rendering_device.texture_create_shared_from_slice(
				RDTextureView.new(), texture, 0, base_mip, 1, 0
		)
		if sliced.is_valid():
			temporary.append(sliced)
			texture = sliced
	var sampler := _sampler(rendering_device, draw)
	if not sampler.is_valid() or not texture.is_valid():
		return []
	var sampler_uniform := RDUniform.new()
	sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	sampler_uniform.binding = 0
	# Godot's combined sampler uniform expects the sampler RID, then the texture.
	sampler_uniform.add_id(sampler)
	sampler_uniform.add_id(texture)
	var sampler_uniforms: Array[RDUniform] = [sampler_uniform]
	var sampler_set := rendering_device.uniform_set_create(sampler_uniforms, shader, 2)
	if not sampler_set.is_valid():
		return []
	temporary.append(sampler_set)
	sets.append(sampler_set)
	return sets


func _uniform_buffer_set(rendering_device: RenderingDevice, shader: RID, set_index: int, buffer: RID) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer)
	var uniforms: Array[RDUniform] = [uniform]
	return rendering_device.uniform_set_create(uniforms, shader, set_index)


func _align16(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.is_empty():
		return bytes
	var padded := bytes.duplicate()
	var remainder := padded.size() % 16
	if remainder != 0:
		padded.resize(padded.size() + 16 - remainder)
	return padded


func _index_array(rendering_device: RenderingDevice, draw: Dictionary, buffer_rids: Dictionary) -> RID:
	var index_buffer: RID = buffer_rids.get(draw.get("index_buffer_id", 0), RID())
	if not index_buffer.is_valid():
		return RID()
	var index_type: int = draw.get("index_type", 0)
	var stride := 4 if index_type == RenderingDevice.INDEX_BUFFER_FORMAT_UINT32 else 2
	var first := int(draw.get("first", 0))
	var byte_offset := int(draw.get("index_offset", 0))
	if byte_offset % stride != 0:
		return RID()
	return rendering_device.index_array_create(index_buffer, int(byte_offset / float(stride)) + first, int(draw.get("count", 0)))


func _pipeline(
		rendering_device: RenderingDevice,
		framebuffer: RID,
		family: int,
		draw: Dictionary
) -> RID:
	var framebuffer_format := rendering_device.framebuffer_get_format(framebuffer)
	var key := "%d:%d:%d:%d:%d:%s" % [
		family,
		int(draw.get("blend", BLEND_ALPHA)),
		int(draw.get("topology", 4)),
		framebuffer_format,
		1 if bool(draw.get("grayscale", false)) else 0,
		_attribute_key(draw.get("attributes", [])),
	]
	var cached: RID = _pipelines.get(key, RID())
	if cached.is_valid() and rendering_device.render_pipeline_is_valid(cached):
		return cached
	var shader := _shader(rendering_device, family, bool(draw.get("grayscale", false)))
	var vertex_format := _vertex_format(
			rendering_device, family, int(draw.get("vertex_stride", 0)), draw.get("attributes", [])
	)
	if not shader.is_valid() or vertex_format <= 0:
		return RID()
	var primitive := _primitive(int(draw.get("topology", 4)))
	if primitive < 0:
		return RID()
	var created := rendering_device.render_pipeline_create(
			shader,
			framebuffer_format,
			vertex_format,
			primitive,
			_raster_state(),
			RDPipelineMultisampleState.new(),
			RDPipelineDepthStencilState.new(),
			_blend_state(int(draw.get("blend", BLEND_ALPHA))),
			0,
			0,
			[]
	)
	if created.is_valid():
		_pipelines[key] = created
	return created


func _shader(rendering_device: RenderingDevice, family: int, grayscale: bool) -> RID:
	var key := _shader_key(family, {"grayscale": grayscale})
	var cached: RID = _shaders.get(key, RID())
	if cached.is_valid():
		return cached
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_vertex = _vertex_shader(family)
	source.source_fragment = _fragment_shader(family, grayscale)
	var spirv := rendering_device.shader_compile_spirv_from_source(source, true)
	if spirv == null or spirv.bytecode_vertex.is_empty() or spirv.bytecode_fragment.is_empty():
		var vertex_error := "" if spirv == null else spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX)
		var fragment_error := "" if spirv == null else spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT)
		push_warning("RenderPearl GUI shader family %d failed to compile: %s %s" % [family, vertex_error, fragment_error])
		return RID()
	var shader := rendering_device.shader_create_from_spirv(spirv, "renderpearl_gui_%d" % key)
	if shader.is_valid():
		_shaders[key] = shader
	return shader


func _shader_key(family: int, draw: Dictionary) -> int:
	return family + (8 if bool(draw.get("grayscale", false)) else 0)


func _vertex_format(rendering_device: RenderingDevice, family: int, stride: int, attributes: Array) -> int:
	var descriptions: Array[RDVertexAttribute] = []
	for attribute_variant in attributes:
		var attribute: Dictionary = attribute_variant
		var location: int = attribute.get("location", 255)
		if location == 255 or location < 0:
			continue
		var data_format := _data_format(int(attribute.get("format", -1)))
		if data_format < 0:
			continue
		var description := RDVertexAttribute.new()
		description.location = location
		description.offset = int(attribute.get("offset", 0))
		description.format = data_format
		description.stride = stride
		description.binding = 0
		descriptions.append(description)
	if descriptions.is_empty():
		descriptions = _fallback_attributes(family, stride)
	if descriptions.is_empty():
		return 0
	return rendering_device.vertex_format_create(descriptions)


func _fallback_attributes(family: int, stride: int) -> Array[RDVertexAttribute]:
	var attributes: Array[RDVertexAttribute] = []
	if stride < 12:
		return attributes
	var position := RDVertexAttribute.new()
	position.location = 0
	position.offset = 0
	position.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	position.stride = stride
	position.binding = 0
	attributes.append(position)
	if family == FAMILY_GUI_TEXTURED and stride >= 12 + 8 + 4:
		var uv := RDVertexAttribute.new()
		uv.location = 1
		uv.offset = 12
		uv.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		uv.stride = stride
		uv.binding = 0
		attributes.append(uv)
		var color := RDVertexAttribute.new()
		color.location = 2
		color.offset = 20
		color.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		color.stride = stride
		color.binding = 0
		attributes.append(color)
	elif stride >= 12 + 4:
		var color := RDVertexAttribute.new()
		color.location = 1
		color.offset = 12
		color.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		color.stride = stride
		color.binding = 0
		attributes.append(color)
		if family == FAMILY_GUI_TEXT and stride >= 16 + 8:
			var uv := RDVertexAttribute.new()
			uv.location = 2
			uv.offset = 16
			uv.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
			uv.stride = stride
			uv.binding = 0
			attributes.append(uv)
	return attributes


func _framebuffer(
		rendering_device: RenderingDevice,
		framebuffers: Dictionary,
		color_id: int,
		color_texture: RID
) -> RID:
	var existing: RID = framebuffers.get(color_id, RID())
	if existing.is_valid():
		return existing
	var attachments: Array[RID] = [color_texture]
	var created := rendering_device.framebuffer_create(attachments)
	if created.is_valid():
		framebuffers[color_id] = created
	return created


func _sampler(rendering_device: RenderingDevice, draw: Dictionary) -> RID:
	var min_filter: int = draw.get("sampler0_min_filter", 0)
	var mag_filter: int = draw.get("sampler0_mag_filter", 0)
	var address_u := _address(int(draw.get("sampler0_address_u", 0)))
	var address_v := _address(int(draw.get("sampler0_address_v", 0)))
	var key := "%d:%d:%d:%d" % [min_filter, mag_filter, address_u, address_v]
	var cached: RID = _samplers.get(key, RID())
	if cached.is_valid():
		return cached
	var state := RDSamplerState.new()
	state.min_filter = min_filter
	state.mag_filter = mag_filter
	state.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.repeat_u = address_u
	state.repeat_v = address_v
	state.repeat_w = address_u
	var created := rendering_device.sampler_create(state)
	if created.is_valid():
		_samplers[key] = created
	return created


func _white(rendering_device: RenderingDevice) -> RID:
	if _white_texture.is_valid():
		return _white_texture
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = 1
	format.height = 1
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var pixels := PackedByteArray([255, 255, 255, 255])
	var data: Array[PackedByteArray] = [pixels]
	_white_texture = rendering_device.texture_create(format, RDTextureView.new(), data)
	return _white_texture


func _address(mode: int) -> int:
	# RenderPearl clamp-to-edge is 1. Godot's clamp-to-edge is 2, not mirrored repeat.
	return REPEAT_CLAMP_TO_EDGE if mode == 1 else 0


func _expanded_index_array(rendering_device: RenderingDevice, vertex_count: int, fan: bool) -> Dictionary:
	if vertex_count < 3 or (not fan and vertex_count % 4 != 0):
		return {}
	var indices := PackedInt32Array()
	if fan:
		indices.resize((vertex_count - 2) * 3)
		var cursor := 0
		for index in range(1, vertex_count - 1):
			indices[cursor] = 0
			indices[cursor + 1] = index
			indices[cursor + 2] = index + 1
			cursor += 3
	else:
		# Same winding as RenderSystem.sharedSequentialQuad: 0,1,2, 2,3,0.
		var quads := vertex_count / 4
		indices.resize(quads * 6)
		var cursor := 0
		for quad in range(quads):
			var base := quad * 4
			indices[cursor] = base
			indices[cursor + 1] = base + 1
			indices[cursor + 2] = base + 2
			indices[cursor + 3] = base + 2
			indices[cursor + 4] = base + 3
			indices[cursor + 5] = base
			cursor += 6
	var index_bytes := indices.to_byte_array()
	var buffer := rendering_device.index_buffer_create(
		indices.size(), RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, index_bytes, false, 0
	)
	if not buffer.is_valid():
		return {}
	var array := rendering_device.index_array_create(buffer, 0, indices.size())
	if not array.is_valid():
		rendering_device.free_rid(buffer)
		return {}
	return {"buffer": buffer, "array": array}


func _primitive(topology: int) -> int:
	match topology:
		0, 1:
			return RenderingDevice.RENDER_PRIMITIVE_LINES
		2:
			# Godot 4.7 names this LINESTRIPS, not LINE_STRIPS.
			return RenderingDevice.RENDER_PRIMITIVE_LINESTRIPS
		3:
			return RenderingDevice.RENDER_PRIMITIVE_POINTS
		4, TOPOLOGY_QUADS, TOPOLOGY_TRIANGLE_FAN:
			# VulkanConst.toVk maps QUADS to VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST.
			# Fans are expanded to that same list because 4.7 has no fan primitive.
			return RenderingDevice.RENDER_PRIMITIVE_TRIANGLES
		5:
			return RenderingDevice.RENDER_PRIMITIVE_TRIANGLE_STRIPS
		_:
			return -1


func _blend_state(blend: int) -> RDPipelineColorBlendState:
	var attachment := RDPipelineColorBlendStateAttachment.new()
	attachment.write_r = true
	attachment.write_g = true
	attachment.write_b = true
	attachment.write_a = true
	attachment.enable_blend = blend != BLEND_OPAQUE
	if blend == BLEND_PREMULTIPLIED:
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	elif blend == BLEND_ADDITIVE:
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_SRC_ALPHA
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	elif blend == BLEND_INVERT:
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_DST_COLOR
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_COLOR
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	else:
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_SRC_ALPHA
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	var state := RDPipelineColorBlendState.new()
	var attachments: Array[RDPipelineColorBlendStateAttachment] = [attachment]
	state.attachments = attachments
	return state


func _raster_state() -> RDPipelineRasterizationState:
	var state := RDPipelineRasterizationState.new()
	state.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
	return state


func _data_format(gpu_format: int) -> int:
	match gpu_format:
		GPU_RGBA8_UNORM:
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		GPU_R32_FLOAT:
			return RenderingDevice.DATA_FORMAT_R32_SFLOAT
		GPU_RG32_FLOAT:
			return RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		GPU_RGB32_FLOAT:
			return RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
		GPU_RGBA32_FLOAT:
			return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		_:
			return -1


func _attribute_key(attributes: Array) -> String:
	var parts: PackedStringArray = []
	for attribute_variant in attributes:
		var attribute: Dictionary = attribute_variant
		parts.append("%d:%d:%d" % [attribute.get("location", 255), attribute.get("offset", 0), attribute.get("format", -1)])
	return "|".join(parts)


func _identity_dynamic() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(160)
	_write_identity(bytes, 0)
	_write_identity(bytes, 64)
	bytes.encode_float(128, 1.0)
	bytes.encode_float(132, 1.0)
	bytes.encode_float(136, 1.0)
	bytes.encode_float(140, 1.0)
	return bytes


func _ortho(width: float, height: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(64)
	var sx := 2.0 / width if width > 0.0 else 1.0
	var sy := -2.0 / height if height > 0.0 else 1.0
	bytes.encode_float(0, sx)
	bytes.encode_float(20, sy)
	bytes.encode_float(40, -1.0)
	bytes.encode_float(48, -1.0)
	bytes.encode_float(52, 1.0)
	bytes.encode_float(60, 1.0)
	return bytes


func _write_identity(bytes: PackedByteArray, offset: int) -> void:
	bytes.encode_float(offset, 1.0)
	bytes.encode_float(offset + 20, 1.0)
	bytes.encode_float(offset + 40, 1.0)
	bytes.encode_float(offset + 60, 1.0)


func _vertex_shader(family: int) -> String:
	var inputs := "layout(location = 0) in vec3 a_position;\nlayout(location = 1) in vec4 a_color;\n"
	var varyings := "layout(location = 0) out vec4 v_color;\n"
	var assignments := "v_color = a_color;\n"
	if family == FAMILY_GUI_TEXTURED:
		inputs = "layout(location = 0) in vec3 a_position;\nlayout(location = 1) in vec2 a_uv;\nlayout(location = 2) in vec4 a_color;\n"
		varyings = "layout(location = 0) out vec4 v_color;\nlayout(location = 1) out vec2 v_uv;\n"
		# core/position_tex_color copies UV0. TextureMat remains in the std140
		# block so ColorModulator keeps its extracted offset, but it is unused.
		assignments = "v_color = a_color;\nv_uv = a_uv;\n"
	elif family == FAMILY_GUI_TEXT:
		inputs = "layout(location = 0) in vec3 a_position;\nlayout(location = 1) in vec4 a_color;\nlayout(location = 2) in vec2 a_uv;\n"
		varyings = "layout(location = 0) out vec4 v_color;\nlayout(location = 1) out vec2 v_uv;\n"
		assignments = "v_color = a_color;\nv_uv = a_uv;\n"
	return """#version 450
%s
layout(std140, set = 0, binding = 0) uniform DynamicTransforms {
	mat4 ModelViewMat;
	mat4 TextureMat;
	vec4 ColorModulator;
	vec4 ModelOffset;
};
layout(std140, set = 1, binding = 0) uniform Projection {
	mat4 ProjMat;
};
%s
void main() {
	gl_Position = ProjMat * ModelViewMat * vec4(a_position, 1.0);
	%s
}
""" % [inputs, varyings, assignments]


func _fragment_shader(family: int, grayscale: bool) -> String:
	var inputs := "layout(location = 0) in vec4 v_color;\n"
	var sample := ""
	var color := "vec4 color = v_color * ColorModulator;"
	var discard_test := "if (color.a == 0.0) { discard; }"
	if family == FAMILY_GUI_TEXTURED:
		inputs = "layout(location = 0) in vec4 v_color;\nlayout(location = 1) in vec2 v_uv;\n"
		sample = "layout(set = 2, binding = 0) uniform sampler2D Sampler0;\n"
		color = "vec4 color = texture(Sampler0, v_uv) * v_color * ColorModulator;"
	elif family == FAMILY_GUI_TEXT:
		inputs = "layout(location = 0) in vec4 v_color;\nlayout(location = 1) in vec2 v_uv;\n"
		sample = "layout(set = 2, binding = 0) uniform sampler2D Sampler0;\n"
		# core/text.fsh uses .rrrr only when IS_GRAYSCALE is defined.
		if grayscale:
			color = "vec4 color = texture(Sampler0, v_uv).rrrr * v_color * ColorModulator;"
		else:
			color = "vec4 color = texture(Sampler0, v_uv) * v_color * ColorModulator;"
		discard_test = "if (color.a < 0.1) { discard; }"
	return """#version 450
%s
layout(std140, set = 0, binding = 0) uniform DynamicTransforms {
	mat4 ModelViewMat;
	mat4 TextureMat;
	vec4 ColorModulator;
	vec4 ModelOffset;
};
%s
layout(location = 0) out vec4 frag_color;
void main() {
	%s
	%s
	frag_color = color;
}
""" % [inputs, sample, color, discard_test]
