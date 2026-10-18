// Density / risk overlay from the simulation's density grid image:
//   R = density * 50 (5.1 p/m² = 1.0), G = level * 85 (0 comfortable .. 3 dangerous)
shader_type canvas_item;

uniform int mode = 0;        // 0 density, 1 risk
uniform float strength = 1.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	if (mode == 0) {
		float d = t.r * 5.1;
		vec3 c = d < 1.0 ? mix(vec3(0.99, 0.91, 0.45), vec3(0.98, 0.69, 0.20), d)
			: d < 2.5 ? mix(vec3(0.98, 0.69, 0.20), vec3(0.91, 0.30, 0.17), (d - 1.0) / 1.5)
			: mix(vec3(0.91, 0.30, 0.17), vec3(0.55, 0.05, 0.20), clamp((d - 2.5) / 2.0, 0.0, 1.0));
		float a = smoothstep(0.15, 1.2, d) * 0.62;
		COLOR = vec4(c, a * strength);
	} else {
		float l = t.g * 3.0;
		vec3 c = l < 1.5 ? vec3(0.98, 0.80, 0.25) : l < 2.5 ? vec3(0.97, 0.47, 0.10) : vec3(0.86, 0.10, 0.18);
		float a = smoothstep(0.4, 1.0, l) * (l < 1.5 ? 0.30 : l < 2.5 ? 0.50 : 0.70);
		COLOR = vec4(c, a * strength);
	}
}
