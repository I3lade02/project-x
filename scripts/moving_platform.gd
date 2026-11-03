extends AnimatableBody2D

@export var move_offset := Vector2(250, 0)
@export var period := 6.0

var start_pos := Vector2.ZERO
var t := 0.0

func _ready():
	start_pos = position
	
func _physics_process(delta):
	t += delta
	position = start_pos + move_offset * sin(t * TAU / period)
