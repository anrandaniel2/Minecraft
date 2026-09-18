shader_type spatial;
render_mode blend_add, cull_front, unshaded, depth_draw_never, shadows_disabled;

// A cheap star field: hashed cells on the dome, shown only at night.
uniform float night_factor : hint_range(0.0, 1.0) = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 dir = normalize(VERTEX);
	vec3 cell = floor(dir * 90.0);
	float star = hash(cell);
	float brightness = smoothstep(0.9965, 0.9995, star) * night_factor;
	if (brightness <= 0.001) {
		discard;
	}
	float twinkle = 0.75 + 0.25 * hash(cell + vec3(7.0));
	ALBEDO = vec3(brightness * twinkle * 1.6);
	ALPHA = brightness * twinkle;
}
