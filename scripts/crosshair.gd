extends Control

const COLOR_COLD = Color(0.5, 1.6, 1.8)
const COLOR_HOT = Color(2.5, 0.4, 0.2)


func _process(_delta):
	position = get_viewport().get_mouse_position()

	# ve hře vlastní zaměřovač, v pauze / výběru upgradu normální kurzor
	var paused = get_tree().paused
	for n in get_tree().get_nodes_in_group("ui_modal"):
		if n.visible:
			paused = true
	visible = not paused
	var want = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want

	var p = get_tree().current_scene.get("local_player") if get_tree().current_scene else null
	if p == null:
		for x in get_tree().get_nodes_in_group("player"):
			if x.get("player_index") == 0 or x.get("player_index") == null:
				p = x
	if p:
		modulate = COLOR_COLD.lerp(COLOR_HOT, p.heat / 100.0)


func _exit_tree():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
