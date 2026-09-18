shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx, shadows_disabled;

// Water surface: same atlas lookup as terrain.gdshader, plus animated normals.
uniform sampler2D atlas : filter_nearest, repeat_enable;
uniform vec2 atlas_size = vec2(384.0, 384.0);
uniform float tile_pixels = 16.0;
uniform float cell_pixels = 24.0;
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform bool smooth_lighting = true;
uniform vec3 fog_color = vec3(0.68, 0.8, 0.96);
uniform float fog_distance = 120.0;
uniform float fog_start = 0.55;
uniform float time_offset = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.72;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 within = fract(UV + vec2(0.0001) + vec2(time_offset * 0.02, time_offset * 0.013));
	vec2 cell_uv = (CUSTOM0 * cell_pixels + vec2(1.0) + within * tile_pixels) / atlas_size;
	vec4 tex = texture(atlas, cell_uv);
	float light = clamp(max(CUSTOM1.x * day_factor, CUSTOM1.y), 0.06, 1.0);
	vec3 tint = mix(vec3(1.0), COLOR.rgb, 0.4);
	ALBEDO = tex.rgb * tint * light;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	float wave_x = sin(world_pos.x * 0.7 + time_offset * 1.7) * 0.5 + 0.5;
	float wave_z = cos(world_pos.z * 0.9 + time_offset * 1.3) * 0.5 + 0.5;
	NORMAL_MAP = vec3(wave_x, wave_z, 1.0);
	NORMAL_MAP_DEPTH = 0.3;
}

void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * LIGHT_COLOR * 0.8;
	SPECULAR_LIGHT += SPECULAR_AMOUNT * LIGHT_COLOR * ATTENUATION;
	vec3 view = world_pos - CAMERA_POSITION_WORLD;
	float start = fog_distance * fog_start;
	float fog = clamp((length(view) - start) / max(1.0, fog_distance - start), 0.0, 1.0);
	ALBEDO = mix(ALBEDO, fog_color, fog * fog);
}
