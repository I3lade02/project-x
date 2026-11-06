extends Area2D
## JÁDRO – vzácná měna pro skill tree. Padá z bosse a vzácně z nepřátel.
## Sebrané jádro patří celému týmu, uloží se na konci runu.

const MAGNET_RADIUS = 80.0
const MAGNET_SPEED = 420.0

var vel := Vector2.ZERO
var vacuum := false
var t := 0.0

@onready var visual = $Visual


func _ready():
	add_to_group("cores")
	vel = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)).normalized() * randf_range(40.0, 110.0)
	body_entered.connect(_on_body_entered)


func _physics_process(delta):
	t += delta
	vel = vel.move_toward(Vector2.ZERO, 250.0 * delta)
	position += vel * delta
	visual.position.y = -16.0 + sin(t * 3.0) * 4.0
	visual.rotation = sin(t * 2.0) * 0.25
	var p = _nearest_player()
	if p:
		var d = p.global_position - global_position
		if vacuum or Vector2(d.x, d.y * 2.0).length() < MAGNET_RADIUS:
			position += d.normalized() * minf(MAGNET_SPEED * (2.5 if vacuum else 1.0) * delta, d.length())


func _nearest_player():
	var best = null
	var best_d = INF
	for p in get_tree().get_nodes_in_group("player"):
		if p.dead:
			continue
		var d = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _on_body_entered(b):
	if b.is_in_group("player"):
		var arena = get_tree().current_scene
		if arena.has_method("collect_core"):
			arena.collect_core()
		queue_free()
