extends Node2D
## Kreslí svítící okraje sektoru a "útesy" pod předními hranami (pocit hloubky 2.5D).

const DIRS = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DEPTH = 30.0

var lines := PackedVector2Array()
var cliffs := []
var color := Color(2, 0.5, 1.8)


# walk = pochozí dlaždice, open = dlaždice, kde okraj nekreslit (navazující chodba / sektor)
func setup(walk: Dictionary, open: Dictionary, edge_color: Color, origin: Vector2):
	lines = PackedVector2Array()
	cliffs = []
	color = edge_color
	for c in walk:
		var t = _p(origin, c.x, c.y)
		var r = _p(origin, c.x + 1, c.y)
		var b = _p(origin, c.x + 1, c.y + 1)
		var l = _p(origin, c.x, c.y + 1)
		var segs = [[t, r], [r, b], [b, l], [l, t]]
		for k in 4:
			var n = c + DIRS[k]
			if walk.has(n) or open.has(n):
				continue
			lines.append(segs[k][0])
			lines.append(segs[k][1])
			if k == 1 or k == 2:      # přední hrany -> útes dolů
				var a = segs[k][0]
				var e = segs[k][1]
				cliffs.append(PackedVector2Array([a, e, e + Vector2(0, DEPTH), a + Vector2(0, DEPTH)]))
	queue_redraw()


func _p(o: Vector2, x: float, y: float) -> Vector2:
	return o + Vector2((x - y) * 32.0, (x + y) * 16.0)


func _draw():
	var top = Color(color.r * 0.22, color.g * 0.22, color.b * 0.22, 1.0)
	var bottom = Color(0, 0, 0, 0)
	for p in cliffs:
		draw_polygon(p, PackedColorArray([top, top, bottom, bottom]))
	if lines.size() > 0:
		draw_multiline(lines, color, 2.0)
