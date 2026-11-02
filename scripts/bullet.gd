extends Area2D

const SPEED = 900.0
var direction := Vector2.RIGHT
var damage := 1

func _ready():
	body_entered.connect(_on_hit)
	get_tree().create_timer(1.5).timeout.connect(queue_free)
	
func _physics_process(delta):
	position += direction * SPEED * delta
	
func _on_hit(body):
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
