extends Area2D

const COOL_PER_SEC = 40.0
const LIFT = 2600.0
const MAX_UP = -350.0

func _physics_process(delta):
	for b in get_overlapping_bodies():
		if b.is_in_group("player") and not b.dead:
			b.heat = max(b.heat - COOL_PER_SEC * delta, 0.0)
			b.heat_changed.emit(b.heat)
			b.velocity.y = max(b.velocity.y - LIFT * delta, MAX_UP)
