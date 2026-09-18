shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D cloud_texture : filter_linear, repeat_enable;
uniform vec2 scroll = vec2(0.0, 0.0);
uniform vec3 tint = vec3(1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec4 tex = texture(cloud_texture, UV * 6.0 + scroll);
	if (tex.a < 0.05) {
		discard;
	}
	ALBEDO = tex.rgb * tint;
	ALPHA = tex.a * alpha;
}
