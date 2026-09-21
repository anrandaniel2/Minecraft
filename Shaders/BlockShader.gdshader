shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

// Minecraft block shader - pixel art with nearest filtering, AO, and lightmap
// Translation of net.minecraft.client.renderer.block.ModelBlockRenderer lighting

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D lightmap_texture : filter_linear;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_pos;
varying float vertex_ao;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vertex_ao = COLOR.r; // AO baked into vertex color from ChunkMesher
}

void fragment() {
    vec4 albedo = texture(albedo_texture, UV) * tint_color;
    
    // Alpha scissor for transparent blocks like leaves, glass
    if (albedo.a < 0.5) {
        discard;
    }
    
    // Apply AO - from ModelBlockRenderer.calculateAO
    float ao = mix(1.0, vertex_ao, ao_strength);
    
    // Simple sky light + block light - would sample lightmap
    // For mobile, we use vertex color for light
    vec3 light = vec3(1.0) * ao * brightness;
    
    // Fog - from net.minecraft.client.renderer.FogRenderer
    float fog_distance = length(world_pos - CAMERA_POSITION_WORLD);
    float fog_factor = clamp((fog_distance - 100.0) / 200.0, 0.0, 1.0);
    vec3 fog_color = vec3(0.6, 0.8, 1.0); // sky color, would be from biome
    
    ALBEDO = albedo.rgb * light;
    ALPHA = albedo.a;
    
    // Apply fog
    ALBEDO = mix(ALBEDO, fog_color, fog_factor * 0.3);
}

void light() {
    // Disable Godot lights, use baked lighting for performance on mobile
    DIFFUSE_LIGHT = vec3(0.0);
    SPECULAR_LIGHT = vec3(0.0);
}
