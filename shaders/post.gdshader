shader_type canvas_item;

// post-process: heat haze, chromatic aberration, scanlines, vinět, glitch
global uniform float heat;
global uniform float glitch;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float rand(float x) { return fract(sin(x * 91.7) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	float h = smoothstep(0.6, 1.0, heat);

	// tetelení vzduchu
	uv.x += sin(uv.y * 60.0 + TIME * 6.0) * 0.0025 * h;
	uv.y += cos(uv.x * 50.0 + TIME * 5.0) * 0.0015 * h;

	// glitch – posunuté horizontální pruhy
	float slice = step(0.6, rand(floor(uv.y * 28.0) + floor(TIME * 24.0)));
	uv.x += (slice - 0.5) * 0.04 * glitch;

	// chromatická aberace
	vec2 dir = uv - 0.5;
	float ca = 0.0012 + 0.004 * h + 0.012 * glitch;
	float r = texture(screen_tex, uv + dir * ca).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir * ca).b;
	vec3 col = vec3(r, g, b);

	// scanlines
	col *= 0.95 + 0.05 * sin(SCREEN_UV.y * 720.0 * 3.14159);

	// vinět (při přehřátí pulzuje červeně)
	float v = smoothstep(0.85, 0.25, length(SCREEN_UV - 0.5));
	vec3 vig = vec3(0.6, 0.0, 0.0) * h * (0.6 + 0.4 * sin(TIME * 10.0));
	col = mix(vig, col, mix(1.0, v, 0.45 + 0.4 * h));

	COLOR = vec4(col, 1.0);
}
