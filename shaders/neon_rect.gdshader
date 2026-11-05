shader_type canvas_item;

// tmavá výplň + svítící okraj (pro plošiny apod.)
uniform vec4 fill_color : source_color = vec4(0.04, 0.05, 0.10, 1.0);
uniform vec4 edge_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float edge_px = 2.0;
uniform float glow_strength = 2.5;

void fragment() {
	vec2 px = fwidth(UV);
	vec2 d = min(UV, 1.0 - UV) / px;          // vzdálenost od okraje v pixelech
	float e = min(d.x, d.y);
	float edge = 1.0 - smoothstep(edge_px - 0.5, edge_px + 0.5, e);
	float inner = exp(-e / 6.0) * 0.35;
	vec3 col = fill_color.rgb + edge_color.rgb * (edge * glow_strength + inner);
	COLOR = vec4(col, fill_color.a);
}
