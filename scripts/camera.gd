extends Camera2D
## Kamera s třesem. Když má cíl (target), plynule ho sleduje.

const MAX_OFFSET = 12.0     # max posun v pixelech
const DECAY = 1.8           # jak rychle třes utichá
const FOLLOW = 5.0          # jak rychle dohání cíl
const LOOK_UP = Vector2(0, -20)

var trauma := 0.0
var target: Node2D = null


func _ready():
	add_to_group("camera")


func shake(amount):
	trauma = min(trauma + amount, 1.0)


# okamžitě skočí na cíl (bez dojezdu)
func snap():
	if is_instance_valid(target):
		global_position = target.global_position + LOOK_UP


func _process(delta):
	if is_instance_valid(target):
		global_position = global_position.lerp(target.global_position + LOOK_UP, 1.0 - exp(-FOLLOW * delta))
	trauma = max(trauma - DECAY * delta, 0.0)
	var s = trauma * trauma
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * MAX_OFFSET * s
