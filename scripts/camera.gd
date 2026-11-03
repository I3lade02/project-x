extends Camera2D

const MAX_OFFSET = 12.0     # max posun v pixelech
const DECAY = 1.8           # jak rychle třes utichá

var trauma := 0.0


func _ready():
	add_to_group("camera")


func shake(amount):
	trauma = min(trauma + amount, 1.0)


func _process(delta):
	trauma = max(trauma - DECAY * delta, 0.0)
	var s = trauma * trauma
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * MAX_OFFSET * s
