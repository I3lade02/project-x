extends CanvasLayer

var shown_heat := 0.0
var glitch := 0.0

func _process(delta):
	var target := 0.0
	var p = get_tree().get_first_node_in_group("player")
	if p:
		target = p.heat / 100.0
		# při crashi / smrti náhodně glitchne obrazovku
		if (p.crash_timer > 0 or p.dead) and randf() < 0.08:
			glitch = 0.9
		shown_heat = lerp(shown_heat, target, 1.0 - exp(-6.0 * delta))
		glitch = max(glitch - delta * 2.5, 0.0)
		RenderingServer.global_shader_parameter_set("heat", shown_heat)
		RenderingServer.global_shader_parameter_set("glitch", glitch)
		
func _exit_tree():
	RenderingServer.global_shader_parameter_set("heat", 0.0)
	RenderingServer.global_shader_parameter_set("glitch", 0.0)
