shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 tint_color : source_color = vec4(1.0);

void fragment() {
    vec4 albedo = texture(albedo_texture, UV) * tint_color;
    if (albedo.a < 0.1) discard;
    ALBEDO = albedo.rgb;
    ALPHA = albedo.a;
}
