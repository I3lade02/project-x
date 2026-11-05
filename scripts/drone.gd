extends "res://scripts/enemy_iso.gd"
## Dron – rychlý, kličkuje a létá přes bloky (koliduje jen se zdmi arény).

const HOVER = 36.0          # výška letu
var weave := 0.0


func setup():
	weave = randf() * TAU


func desired_velocity(_delta) -> Vector2:
	var dir = chase_dir()
	var side = Vector2(-dir.y, dir.x) * sin(t * 3.0 + weave) * 0.7   # kličkování
	var desired = (dir + side).normalized() * ISO * speed
	desired += separation() * speed * separation_force
	return desired


func behave(_delta):
	visual.position.y = -HOVER + sin(t * 5.0 + weave) * 4.0
