extends Area2D

const SPEED = 900.0

var direction := Vector2.RIGHT
var damage := 1
var pierce := 0              # kolik bugů navíc projde
var hit_list := []
var hot := false            # REDLINE střela


func _ready():
	rotation = direction.angle()
	if hot:
		$Rect.color = Color(3.5, 0.7, 0.3)
		scale = Vector2(1.5, 1.5)
	body_entered.connect(_on_hit)
	get_tree().create_timer(1.5, false).timeout.connect(queue_free)


func _physics_process(delta):
	position += direction * SPEED * delta


func _on_hit(body):
	if body in hit_list:
		return
	if body.has_method("take_damage"):
		hit_list.append(body)
		body.take_damage(damage)
		pierce -= 1
		if pierce < 0:
			queue_free()
	else:
		queue_free()             # zeď / plošina
