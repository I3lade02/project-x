extends Area2D
## Žhavá koule nepřátel (turret, boss). Zastaví ji blok, dash ji proletí.

var velocity := Vector2.RIGHT * 240.0
var heat := 12.0
var life := 5.0
var t := 0.0

@onready var visual = $Visual


func _ready():
	body_entered.connect(_on_body_entered)


func _physics_process(delta):
	t += delta
	life -= delta
	position += velocity * delta
	visual.scale = Vector2.ONE * (1.0 + sin(t * 18.0) * 0.12)
	if life <= 0:
		queue_free()


func _on_body_entered(b):
	if b.has_method("hit"):
		b.hit(heat, global_position)
	Juice.burst(global_position + Vector2(0, -20), Color(3, 0.8, 0.2), 6)
	queue_free()
