extends "res://scripts/enemy_iso.gd"
## Turret – stojí na místě, nabíjí a střílí žhavé koule na hráče.

const CHARGE_TIME = 0.6
const ORB_SPEED = 240.0
const FIRE_INTERVAL = 2.2

var burst := 1               # kolik koulí najednou (nastaví aréna)
var fire_cd := 1.5
var charging := 0.0

@onready var gun = $Visual/Gun
@onready var core = $Visual/Body/Core


func setup():
	fire_cd = randf_range(1.2, 2.2)
	visual.scale = Vector2(0.1, 0.1)
	create_tween().tween_property(visual, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func desired_velocity(_delta) -> Vector2:
	return Vector2.ZERO


func behave(delta):
	if player == null or player.dead:
		return
	var to = player.global_position - global_position
	gun.rotation = to.angle()
	if charging > 0:
		charging -= delta
		core.modulate = Color(1, 1, 1).lerp(Color(4, 1.2, 0.3), 1.0 - charging / CHARGE_TIME)
		if charging <= 0:
			fire(to)
		return
	fire_cd -= delta
	if fire_cd <= 0:
		charging = CHARGE_TIME
		Juice.play("charge", -10.0)


func fire(to: Vector2):
	core.modulate = Color.WHITE
	fire_cd = FIRE_INTERVAL
	Juice.play("orb", -6.0)
	var w = Vector2(to.x, to.y * 2.0).normalized()
	for i in burst:
		var a = (i - (burst - 1) / 2.0) * 0.25
		shoot_orb(w.rotated(a) * ISO * ORB_SPEED)
