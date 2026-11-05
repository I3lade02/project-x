extends Control
## Šipky na okraji obrazovky: ukazují nepřátele mimo záběr (červeně, boss růžově),
## terminál (zlatě) a cestu do dalšího sektoru (bíle).

const MARGIN = 26.0
const ENEMY_COLOR = Color(2.0, 0.35, 0.3, 0.85)
const BOSS_COLOR = Color(2.2, 0.4, 1.8, 1.0)
const TERMINAL_COLOR = Color(1.9, 1.5, 0.45, 1.0)
const EXIT_COLOR = Color(1.7, 1.7, 2.0, 1.0)


func _process(_delta):
	queue_redraw()


func _draw():
	var vt = get_viewport().get_canvas_transform()
	var rect = get_viewport_rect().grow(-MARGIN)
	for e in get_tree().get_nodes_in_group("enemies"):
		var boss = e.scene_file_path.ends_with("boss.tscn")
		_arrow(rect, vt * (e.global_position + Vector2(0, -16)), BOSS_COLOR if boss else ENEMY_COLOR, 16.0 if boss else 9.0)
	for t in get_tree().get_nodes_in_group("terminal"):
		_arrow(rect, vt * (t.global_position + Vector2(0, -30)), TERMINAL_COLOR, 13.0)
	var scene = get_tree().current_scene
	if scene:
		var ex = scene.get("exit_target")
		if ex != null:
			_arrow(rect, vt * ex, EXIT_COLOR, 15.0)


func _arrow(rect: Rect2, p: Vector2, col: Color, size: float):
	if rect.has_point(p):
		return
	var center = rect.get_center()
	var dir = (p - center).normalized()
	var tx = (rect.size.x / 2.0) / maxf(absf(dir.x), 0.0001)
	var ty = (rect.size.y / 2.0) / maxf(absf(dir.y), 0.0001)
	var pos = center + dir * minf(tx, ty)
	var side = dir.orthogonal() * size * 0.65
	draw_colored_polygon(PackedVector2Array([pos + dir * size, pos - dir * size * 0.4 + side, pos - dir * size * 0.4 - side]), col)
