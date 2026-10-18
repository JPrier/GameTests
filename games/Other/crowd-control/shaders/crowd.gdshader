// Crowd rendering: one instance per person (MultiMesh). The Rust simulation writes data, not colours:
//   COLOR           = (destination/8, profile/8, state/4, stress)
//   INSTANCE_CUSTOM = (dx/scale, dy/scale, heading, hash)  dx,dy = movement during the last tick
// so overlay modes only change uniforms, and motion is interpolated between 20 Hz ticks.
shader_type canvas_item;

uniform float alpha = 1.0;        // fraction of the current tick elapsed (render interpolation)
uniform int mode = 0;             // 0 destination, 1 stress, 2 profile
uniform float detail = 1.0;       // 0 = simple dots (far zoom) .. 1 = shoulders + head
uniform vec4 dest_colors[4];
uniform vec4 profile_colors[8];
uniform float draw_scale = 1.5;   // visual size relative to the physical body

varying vec3 v_col;
varying float v_heading;
varying float v_state;
varying float v_hash;

vec3 stress_ramp(float s) {
	vec3 calm = vec3(0.18, 0.62, 0.30);
	vec3 tense = vec3(0.96, 0.62, 0.0);
	vec3 angry = vec3(0.88, 0.19, 0.19);
	return s < 0.5 ? mix(calm, tense, s * 2.0) : mix(tense, angry, (s - 0.5) * 2.0);
}

void vertex() {
	float dest = floor(COLOR.r * 8.0 + 0.5);
	float prof = floor(COLOR.g * 8.0 + 0.5);
	v_state = floor(COLOR.b * 4.0 + 0.5);
	float stress = COLOR.a;
	v_heading = INSTANCE_CUSTOM.z;
	v_hash = INSTANCE_CUSTOM.w;
	vec3 c;
	if (mode == 1) {
		c = stress_ramp(clamp(stress, 0.0, 1.0));
	} else if (mode == 2) {
		c = profile_colors[int(prof) % 8].rgb;
	} else {
		c = dest_colors[int(dest) % 4].rgb;
	}
	v_col = c * (0.88 + 0.24 * v_hash);
	COLOR = vec4(1.0);
	VERTEX = VERTEX * draw_scale - INSTANCE_CUSTOM.xy * (1.0 - alpha);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float ca = cos(-v_heading);
	float sa = sin(-v_heading);
	vec2 q = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);   // q.x = forward, q.y = across
	float aa = fwidth(length(p)) * 1.2;
	// far zoom: a plain dot
	float dot_d = length(p) - 0.30;
	// near zoom: shoulders (ellipse wider across the walking direction) and a head
	float sh = length(vec2(q.x / 0.22, q.y / 0.36)) - 1.0;
	float sh_d = sh * 0.22;
	float head_d = length(q - vec2(0.03, 0.0)) - 0.135;
	float body = mix(dot_d, min(sh_d, head_d), detail);
	float a = 1.0 - smoothstep(-aa, aa, body);
	if (a <= 0.0) {
		discard;
	}
	vec3 col = v_col;
	// head: darker, varied hair tones
	float head_in = (1.0 - smoothstep(-aa, aa, head_d)) * detail;
	vec3 hair = mix(vec3(0.16, 0.11, 0.08), vec3(0.42, 0.30, 0.18), v_hash);
	col = mix(col, hair, head_in * 0.85);
	// outline for contrast on light paving
	float edge = smoothstep(-aa * 3.0, -aa, body);
	col = mix(col, col * 0.45, edge * 0.8);
	// people held at a gate look a little muted
	if (v_state > 0.5 && v_state < 1.5) {
		col = mix(col, vec3(dot(col, vec3(0.33))), 0.25);
	}
	COLOR = vec4(col, a);
}
