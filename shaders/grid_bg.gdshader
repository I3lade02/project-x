shader_type canvas_item;

// animovaná neonová mřížka, při vysoké teplotě zčervená
global uniform float heat;
uniform vec4 base_color : source_color = vec4(0.015, 0.015, 0.05, 1.0);
uniform vec4 grid_color : source_color = vec4(0.30, 0.12, 0.75, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.15, 0.05, 1.0);
uniform float cell = 48.0;
uniform float scroll_speed = 12.0;

void fragment() {
	vec2 vs = 1.0 / SCREEN_PIXEL_SIZE;                    // velikost obrazovky v pixelech
	vec2 p = SCREEN_UV * vec2(vs.x / vs.y * 760.0, 760.0); // buňky stejně velké na každém poměru stran
	p.y += TIME * scroll_speed;
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.0, 1.5, min(g.x, g.y));
	float horizon = pow(SCREEN_UV.y, 3.0);
	vec3 gc = mix(grid_color.rgb, hot_color.rgb, clamp(heat, 0.0, 1.0));
	vec3 col = base_color.rgb + gc * line * (0.18 + 0.55 * horizon) + gc * horizon * 0.12;
	col += hot_color.rgb * smoothstep(0.7, 1.0, heat) * (0.5 + 0.5 * sin(TIME * 8.0)) * 0.06;
	COLOR = vec4(col, 1.0);
}
