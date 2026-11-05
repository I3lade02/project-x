extends Camera2D
## Kamera s třesem. Sleduje cíl (target) nebo skupinu hráčů (targets).
## Ve co-opu drží oba hráče v záběru a podle potřeby se oddálí.

const MAX_OFFSET = 12.0     # max posun při třesu v pixelech
const DECAY = 1.8           # jak rychle třes utichá
const FOLLOW = 5.0          # jak rychle dohání cíl
const LOOK_UP = Vector2(0, -20)
const LOOK_AHEAD = 0.18     # kamera se trochu posune směrem k myši (jen 1 hráč)
const MAX_LOOK = 140.0
const MIN_ZOOM = 0.6        # max oddálení v co-opu
const FRAME_MARGIN = Vector2(380, 300)

var trauma := 0.0
var target: Node2D = null
var targets := []


func _ready():
	add_to_group("camera")


func shake(amount):
	trauma = min(trauma + amount, 1.0)


func _tracked() -> Array:
	var list = []
	for t in targets:
		if is_instance_valid(t) and not t.dead:
			list.append(t)
	if list.is_empty():
		for t in targets:
			if is_instance_valid(t):
				list.append(t)
	if list.is_empty() and is_instance_valid(target):
		list.append(target)
	return list


func _focus(list: Array) -> Vector2:
	var sum = Vector2.ZERO
	for t in list:
		sum += t.global_position
	return sum / list.size() + LOOK_UP


# okamžitě skočí na cíl (bez dojezdu)
func snap():
	var list = _tracked()
	if not list.is_empty():
		global_position = _focus(list)


func _process(delta):
	var list = _tracked()
	if not list.is_empty():
		var goal = _focus(list)
		var want_zoom = 1.0
		if list.size() == 1:
			var m = get_viewport().get_mouse_position() - get_viewport_rect().size / 2.0
			goal += (m * LOOK_AHEAD).limit_length(MAX_LOOK)
		else:
			# oddálit, aby se všichni vešli do záběru
			var lo = list[0].global_position
			var hi = lo
			for t in list:
				lo = lo.min(t.global_position)
				hi = hi.max(t.global_position)
			var span = hi - lo
			var view = get_viewport_rect().size - FRAME_MARGIN
			var need = maxf(span.x / view.x, span.y / view.y)
			want_zoom = clampf(1.0 / maxf(need, 0.001), MIN_ZOOM, 1.0)
		global_position = global_position.lerp(goal, 1.0 - exp(-FOLLOW * delta))
		zoom = zoom.lerp(Vector2.ONE * want_zoom, 1.0 - exp(-3.0 * delta))
	trauma = max(trauma - DECAY * delta, 0.0)
	var s = trauma * trauma
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * MAX_OFFSET * s
