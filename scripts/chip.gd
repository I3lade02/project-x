extends Area2D
## Čip (měna). Vyskočí z nepřítele a přitáhne se k hráči, když je blízko
## (nebo vždy po vyčištění vlny – "vacuum").

const BASE_RADIUS = 90.0      # dosah magnetu v "herních" souřadnicích
const MAGNET_SPEED = 520.0

var value := 1
var vel := Vector2.ZERO
var vacuum := false
var t := 0.0
var player

@onready var visual = $Visual


func _ready():
	add_to_group("chips")
	player = get_tree().get_first_node_in_group("player")
	vel = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)).normalized() * randf_range(60.0, 150.0)
	t = randf() * TAU
	body_entered.connect(_on_body_entered)


func _physics_process(delta):
	t += delta
	vel = vel.move_toward(Vector2.ZERO, 300.0 * delta)
	position += vel * delta
	visual.position.y = -10.0 + sin(t * 5.0) * 3.0
	visual.rotation = sin(t * 3.0) * 0.3
	if player and not player.dead:
		var d = player.global_position - global_position
		var r = BASE_RADIUS * player.chip_magnet
		if vacuum or Vector2(d.x, d.y * 2.0).length() < r:
			var sp = MAGNET_SPEED * (1.6 if vacuum else 1.0)
			position += d.normalized() * minf(sp * delta, d.length())


func _on_body_entered(b):
	if b.has_method("add_chips"):
		b.add_chips(value)
		Juice.play("chip", -12.0, 0.15)
		queue_free()
