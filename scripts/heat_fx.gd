extends CanvasLayer
## Posílá teplotu (nejteplejšího živého hráče) a glitch do shaderů.

var shown_heat := 0.0
var glitch := 0.0


func _process(delta):
	var target := 0.0
	for p in get_tree().get_nodes_in_group("player"):
		if p.dead:
			continue
		target = maxf(target, p.heat / 100.0)
		# při crashi náhodně glitchne obrazovku
		if p.crash_timer > 0 and randf() < 0.08:
			glitch = 0.9
	shown_heat = lerp(shown_heat, target, 1.0 - exp(-6.0 * delta))
	glitch = max(glitch - delta * 2.5, 0.0)
	RenderingServer.global_shader_parameter_set("heat", shown_heat)
	RenderingServer.global_shader_parameter_set("glitch", glitch)


func _exit_tree():
	RenderingServer.global_shader_parameter_set("heat", 0.0)
	RenderingServer.global_shader_parameter_set("glitch", 0.0)
