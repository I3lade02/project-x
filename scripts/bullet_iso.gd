extends Area2D
## Střela v izo pohledu: pozice = bod na zemi, grafika je posunutá nahoru (Visual).

const SPEED = 820.0

var direction := Vector2.RIGHT
var damage := 1
var pierce := 0              # kolik bugů navíc projde
var hit_list := []
var hot := false             # REDLINE střela

@onready var visual = $Visual
@onready var rect = $Visual/Rect


func _ready():
	rect.rotation = direction.angle()
	if hot:
		rect.color = Color(3.5, 0.7, 0.3)
		visual.scale = Vector2(1.5, 1.5)
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
		queue_free()             # blok / zeď
