@tool
extends StaticBody2D
## Izometrický blok (kryt). Velikost v dlaždicích, výška v pixelech.
## Grafiku jde později nahradit spritem – stačí vypnout "draw_placeholder".

const HW = 32.0   # polovina šířky dlaždice
const HH = 16.0   # polovina výšky dlaždice

@export var size := Vector2(1, 1):
	set(v):
		size = v
		_rebuild()
@export var height := 40.0:
	set(v):
		height = v
		_rebuild()
@export var draw_placeholder := true:
	set(v):
		draw_placeholder = v
		_rebuild()
@export var top_color := Color(0.09, 0.13, 0.24)
@export var left_color := Color(0.05, 0.08, 0.15)
@export var right_color := Color(0.07, 0.11, 0.2)
@export var edge_color := Color(0.25, 0.9, 1.25)


func _ready():
	_rebuild()


func iso(a: float, b: float) -> Vector2:
	return Vector2((a - b) * HW, (a + b) * HH)


func _rebuild():
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("gen"):
			remove_child(c)
			c.queue_free()
	var w = size.x / 2.0
	var d = size.y / 2.0
	var t = iso(-w, -d)
	var r = iso(w, -d)
	var b = iso(w, d)
	var l = iso(-w, d)
	var up = Vector2(0, -height)

	# kolize = půdorys bloku na zemi
	var col = CollisionPolygon2D.new()
	col.polygon = PackedVector2Array([t, r, b, l])
	_add(col)

	if not draw_placeholder:
		return
	_poly([r + up, b + up, b, r], right_color)
	_poly([l + up, b + up, b, l], left_color)
	_poly([t + up, r + up, b + up, l + up], top_color)
	_line([t + up, r + up, b + up, l + up, t + up])
	_line([l + up, l, b, r, r + up])
	_line([b + up, b])


func _poly(pts, color):
	var p = Polygon2D.new()
	p.polygon = PackedVector2Array(pts)
	p.color = color
	_add(p)


func _line(pts):
	var ln = Line2D.new()
	ln.points = PackedVector2Array(pts)
	ln.width = 1.5
	ln.default_color = edge_color
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	_add(ln)


func _add(n):
	n.set_meta("gen", true)
	add_child(n)
