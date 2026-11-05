extends Area2D
## Ventilátor v izo pohledu.
## Hráči uvnitř: rychle chladne, rychleji se mu nabíjí dash i vent.
## Bugy uvnitř: vzduch je odfukuje ven (kromě turretu a bosse).

const ISO = Vector2(1.0, 0.5)
const COOL_PER_SEC = 55.0       # chlazení hráče
const RECHARGE_BOOST = 1.0      # dash/vent se nabíjí o tolik rychleji (1.0 = 2× rychleji)
const PUSH_FORCE = 380.0        # odfouknutí bugů
const PUSH_INTERVAL = 0.4

var push_cd := 0.0
var player_inside := false

@onready var column = $Column
@onready var particles = $Particles


func _physics_process(delta):
	push_cd -= delta
	var push_now = push_cd <= 0
	if push_now:
		push_cd = PUSH_INTERVAL
	var has_player := false

	for b in get_overlapping_bodies():
		if b.is_in_group("player") and not b.dead:
			has_player = true
			b.heat = max(b.heat - COOL_PER_SEC * delta, 0.0)
			b.heat_changed.emit(b.heat)
			b.dash_recharge -= delta * RECHARGE_BOOST
			b.vent_cd -= delta * RECHARGE_BOOST
			b.in_fan_t = 0.15
		elif push_now and b.is_in_group("enemies") and b.knock_resist < 1.0:
			var d = b.global_position - global_position
			var dir = Vector2(d.x, d.y * 2.0).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			b.knockback(dir * ISO * PUSH_FORCE)

	# vstup hráče = zvuk + silnější proud vzduchu
	if has_player and not player_inside:
		Juice.play("cool", -4.0)
	player_inside = has_player
	var target_a = 0.28 if has_player else 0.1
	column.color.a = lerp(column.color.a, target_a, 1.0 - exp(-8.0 * delta))
	particles.speed_scale = 2.0 if has_player else 1.0
