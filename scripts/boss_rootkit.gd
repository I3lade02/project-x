extends "res://scripts/boss_base.gd"
## Boss ROOTKIT.DLL – mizí a objevuje se jinde. Kde zmizí, nechá minu; po objevení pálí vějíř koulí.
## Skrytý nejde zasáhnout – místo, kde se objeví, napoví blikající značka.
## 1) mina na místě zmizení, 2) + 2 miny kolem hráče, 3) 4 miny, kratší cyklus a přivolává drony.

enum {SHOW, HIDE}

const MINE_TIME = 1.5
const MINE_R = 72.0
const MINE_HEAT = 24.0
const ORB_SPEED = 250.0
const KEEP_DIST = 260.0       # odstup, který drží od hráče
const GLITCH = Color(0.5, 2.6, 1.0)

var state := SHOW
var timer := 3.0
var shot_cd := 0.8
var shots_left := 2
var mines := []               # [pozice, zbývající čas]
var appear_at := Vector2.ZERO
var fade := 1.0               # 1 = vidět, 0 = skrytý
var cycle := 0
var strafe := 1.0

@onready var core = $Visual/Body/Core
@onready var shards = $Visual/Shards


func boss_setup():
	strafe = 1.0 if randf() < 0.5 else -1.0


func desired_velocity(_delta) -> Vector2:
	if state == HIDE or player == null:
		return Vector2.ZERO
	var w = to_game(player.global_position - global_position)
	var dist = w.length()
	if dist < 1.0:
		return Vector2.ZERO
	var n = w / dist
	var radial = n * clampf((dist - KEEP_DIST) / 100.0, -1.0, 1.0)
	var dir = (n.orthogonal() * strafe * 0.8 + radial).normalized()
	return to_screen(dir) * speed + wall_steer * speed


func boss_behave(delta):
	timer -= delta
	match state:
		SHOW:
			shot_cd -= delta
			if shot_cd <= 0 and shots_left > 0:
				shots_left -= 1
				shot_cd = 0.7
				_fan()
			if timer <= 0:
				_vanish()
		HIDE:
			if timer <= 0:
				_appear()


func _fan():
	var w = to_game(player.global_position - global_position).normalized()
	var n = [0, 3, 5, 7][phase]
	for i in n:
		shoot_orb(to_screen(w.rotated((i - (n - 1) / 2.0) * 0.2)) * ORB_SPEED, 12.0)
	Juice.play("orb", -5.0)


func _vanish():
	state = HIDE
	timer = [0.0, 1.4, 1.2, 1.0][phase]
	collision_layer = 0                       # střely jím proletí
	contact_heat = 0.0
	mines.append([global_position, MINE_TIME])
	var around = [0, 0, 2, 4][phase]
	var off = randf() * TAU
	for i in around:
		var p = player.global_position + to_screen(Vector2.RIGHT.rotated(off + i * TAU / around) * 95.0)
		if arena and arena.current["layout"]["walk"].has(arena.screen_to_cell(p)):
			mines.append([p, MINE_TIME + 0.15 * i])
	appear_at = free_spot_near(player.global_position, 180.0, 360.0)
	Juice.play("teleport", -2.0, 0.05)
	Juice.burst(global_position + Vector2(0, -40), GLITCH, 16)


func _appear():
	global_position = appear_at
	velocity = Vector2.ZERO
	state = SHOW
	timer = [0.0, 3.4, 3.0, 2.5][phase]
	shots_left = [0, 2, 2, 3][phase]
	shot_cd = 0.45
	collision_layer = 4
	contact_heat = 30.0
	strafe = -strafe
	cycle += 1
	Juice.play("teleport", -2.0, 0.05)
	Juice.burst(global_position + Vector2(0, -40), GLITCH, 16)
	if phase >= 3 and cycle % 2 == 0:
		for i in 2:
			summon.emit("drone", global_position + to_screen(Vector2.RIGHT.rotated(randf() * TAU) * 60.0))


# skrytý rootkit nejde zasáhnout (ani výbuchem)
func take_damage(amount):
	if state == HIDE:
		return
	super(amount)


func update_fx(delta):
	fade = move_toward(fade, 0.0 if state == HIDE else 1.0, delta * 5.0)
	_apply_look()
	for m in mines:
		m[1] -= delta
		if m[1] <= 0:
			_explode(m[0])
	mines = mines.filter(func(m): return m[1] > 0)


func _explode(pos: Vector2):
	Juice.play("blast", -6.0)
	Juice.burst(pos + Vector2(0, -10), GLITCH, 22)
	for p in alive_targets():
		if iso_dist(p.global_position, pos) < MINE_R:
			p.hit(MINE_HEAT, pos)


func _apply_look():
	visual.modulate.a = 0.1 + 0.9 * fade
	visual.position.x = randf_range(-6, 6) * (1.0 - fade) if fade < 1.0 else 0.0
	shards.rotation = now() * 1.6
	core.modulate = Color(1, 1, 1) * (1.0 + 0.5 * sin(now() * 7.0))


func draw_ground(c: Node2D):
	for m in mines:
		var k = 1.0 - clampf(m[1] / MINE_TIME, 0.0, 1.0)
		var on = int(now() * (6.0 + 10.0 * k)) % 2 == 0
		draw_ring(c, m[0], MINE_R, 2.5, Color(GLITCH, 0.7 if on else 0.35))
		draw_disc(c, m[0], MINE_R * k, Color(GLITCH, 0.22))
		draw_disc(c, m[0], 7.0, Color(3, 0.6, 0.6, 1.0 if on else 0.4))
	if state == HIDE:
		var r = 18.0 + 22.0 * fposmod(now() * 2.0, 1.0)
		draw_ring(c, appear_at, r, 2.0, Color(GLITCH, 0.8))
		draw_ring(c, appear_at, 40.0, 1.5, Color(GLITCH, 0.3))


func net_state() -> Array:
	return [state, fade, appear_at, mines]


func apply_net_state(s: Array):
	if s.size() >= 4:
		state = s[0]
		fade = s[1]
		appear_at = s[2]
		mines = s[3]
		_apply_look()
