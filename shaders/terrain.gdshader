shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

// Terrain shader.
//
// Vertices carry:
//   UV      - continuous texture coordinates (a merged quad can span many
//             blocks, so they run 0..width / 0..height)
//   COLOR   - ambient occlusion * fixed per-face shading
//   CUSTOM0 - atlas tile origin in tile units
//   CUSTOM1 - (skylight, block light) as 0..1

uniform sampler2D atlas : filter_nearest_mipmap, repeat_enable;
uniform vec2 atlas_size = vec2(384.0, 384.0);
uniform float tile_pixels = 16.0;
uniform float cell_pixels = 24.0;
uniform float atlas_cols = 16.0;
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform bool alpha_test = false;
uniform bool is_water = false;
uniform bool smooth_lighting = true;
uniform vec3 fog_color = vec3(0.68, 0.8, 0.96);
uniform float fog_distance = 120.0;
uniform float fog_start = 0.55;
uniform float time_offset = 0.0;
uniform float ambient_min = 0.055;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Repeat the tile inside the merged quad, then offset into the atlas cell.
	vec2 within = fract(UV + vec2(0.0001));
	vec2 tile_origin = CUSTOM0;
	vec2 cell_uv = (tile_origin * cell_pixels + vec2(1.0) + within * tile_pixels) / atlas_size;
	vec4 tex = texture(atlas, cell_uv);
	if (alpha_test && tex.a < 0.4) {
		discard;
	}

	float sky = CUSTOM1.x;
	float block_light = CUSTOM1.y;
	float light = max(sky * day_factor, block_light);
	// A small ambient floor keeps caves and night readable without torches.
	light = clamp(light, ambient_min, 1.0);
	light = pow(light, 0.85);

	vec3 tint = COLOR.rgb;
	if (smooth_lighting) {
		tint = mix(vec3(dot(COLOR.rgb, vec3(0.333))) * 1.05, COLOR.rgb, 0.35);
	}
	ALBEDO = tex.rgb * tint * light;
	ALPHA = is_water ? 0.78 * tex.a : tex.a;
	ROUGHNESS = is_water ? 0.05 : 0.92;
	METALLIC = 0.0;
	if (is_water) {
		// Gentle animated normals so water catches the sun.
		float wave = sin(time_offset * 1.4 + world_pos.x * 0.35 + world_pos.z * 0.28) * 0.06;
		NORMAL_MAP = vec3(0.5 + wave, 0.5 - wave, 1.0);
		NORMAL_MAP_DEPTH = 0.35;
		SPECULAR = 0.6;
	}
	// Emissive blocks (torches, glowstone) glow through the light pass.
	if (!is_water && block_light > 0.65 && sky < 0.35) {
		EMISSION = tex.rgb * 0.25 * block_light;
	}
}

void light() {
	// Custom fog so distant chunks fade into the sky colour cleanly.
	vec3 view = world_pos - CAMERA_POSITION_WORLD;
	float distance = length(view);
	float start = fog_distance * fog_start;
	float fog = clamp((distance - start) / max(1.0, fog_distance - start), 0.0, 1.0);
	fog = fog * fog;
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * LIGHT_COLOR * 0.85;
	SPECULAR_LIGHT += SPECULAR_AMOUNT * LIGHT_COLOR * ATTENUATION;
	ALBEDO = mix(ALBEDO, fog_color, fog);
}
