extends "res://scripts/boss_base.gd"
## Boss MINER.EXE – kryptominer. Zamíří, vyrazí přes arénu a za sebou nechá hořící stopu.
## Když narazí do zdi, rozprskne koule a omráčí se – v tu chvíli dostává dvojnásobné poškození.
## 1) 1 nájezd, 2) 2 nájezdy za sebou, 3) 3 nájezdy a stopa hoří déle.

enum {CHASE, AIM, RAM, STUN}

const RAM_SPEED = 820.0
const RAM_TIME = 1.1
const AIM_TIME = 0.85
const CHAIN_AIM = 0.5
const STUN_TIME = 1.7
const LANE_W = 26.0           # polovina šířky varovného pruhu
const TRAIL_STEP = 46.0       # rozestup ohníčků ve stopě
const TRAIL_R = 30.0
const TRAIL_HEAT = 16.0       # teplo/s, když hráč stojí v ohni
const ORB_SPEED = 210.0
const FIRE_COLOR = Color(2.6, 1.6, 0.2)
const KEEP_DIST = 300.0       # mezi nájezdy si drží odstup (potřebuje rozjezd)
const MIN_LANE = 110.0        # kratší dráhu nájezd nezkouší

var state := CHASE
var timer := 2.5
var ram_dir := Vector2.RIGHT  # herní souřadnice
var rams_left := 0
var lane_len := 0.0
var trail := []               # [pozice, zbývající život, celkový život]
var last_drop := Vector2.ZERO
var strafe := 1.0
var cancels := 0              # kolikrát po sobě nájezd vzdal (zeď v cestě)

@onready var core = $Visual/Body/Core


func desired_velocity(delta) -> Vector2:
	match state:
		CHASE:
			if player == null:
				return Vector2.ZERO
			var w = to_game(player.global_position - global_position)
			var n = w.normalized()
			var radial = n * clampf((w.length() - KEEP_DIST) / 120.0, -1.0, 1.0)
			return to_screen((n.orthogonal() * strafe * 0.7 + radial).normalized()) * speed + wall_steer * speed
		RAM:
			return to_screen(ram_dir) * RAM_SPEED
	return Vector2.ZERO


func boss_behave(delta):
	timer -= delta
	match state:
		CHASE:
			core.modulate = Color.WHITE
			if timer <= 0:
				rams_left = phase
				_start_aim(AIM_TIME)
		AIM:
			if timer > 0.25:                   # míří až do posledního okamžiku
				ram_dir = to_game(player.global_position - global_position).normalized()
			lane_len = ray_length(global_position, ram_dir, RAM_SPEED * RAM_TIME)
			core.modulate = Color(4, 1, 0.3) if int(t * 14) % 2 == 0 else Color.WHITE
			if timer <= 0 and lane_len < MIN_LANE and cancels < 2:
				cancels += 1                   # málo místa na rozjezd -> přesunout se a zkusit znovu
				state = CHASE
				timer = 1.2
				strafe = -strafe
				core.modulate = Color.WHITE
			elif timer <= 0:
				cancels = 0                    # (napotřetí vyrazí i do zdi – a omráčí se)
				state = RAM
				timer = RAM_TIME
				contact_heat = 45.0
				last_drop = global_position
				velocity = to_screen(ram_dir) * RAM_SPEED
				Juice.play("ram", -2.0, 0.05)
		RAM:
			_drop_trail()
			if _hit_wall():
				_impact()
			elif timer <= 0:
				_next_ram(false)
		STUN:
			core.modulate = Color(2.5, 2.5, 0.6) if int(t * 6) % 2 == 0 else Color(0.6, 0.6, 0.6)
			if timer <= 0:
				state = CHASE
				timer = randf_range(1.6, 2.4)
				strafe = -strafe


func _start_aim(time: float):
	state = AIM
	timer = time
	ram_dir = to_game(player.global_position - global_position).normalized()
	Juice.play("charge", -6.0, 0.0)


func _hit_wall() -> bool:
	if timer > RAM_TIME - 0.08:          # první snímky po startu nepočítat
		return false
	for i in get_slide_collision_count():
		if not get_slide_collision(i).get_collider() is CharacterBody2D:
			return true
	return false


func _impact():
	Juice.play("blast", -2.0)
	Juice.shake(0.6)
	Juice.burst(global_position + Vector2(0, -20), FIRE_COLOR, 24)
	var n = [0, 8, 10, 12][phase]
	var off = randf() * TAU
	for i in n:
		shoot_orb(to_screen(Vector2.RIGHT.rotated(off + i * TAU / n)) * ORB_SPEED, 12.0)
	velocity = -to_screen(ram_dir) * 150.0
	_next_ram(true)


func _next_ram(stun_after: bool):
	contact_heat = 35.0
	rams_left -= 1
	if rams_left > 0 and player != null and not player.dead:
		_start_aim(CHAIN_AIM)
	elif stun_after:
		state = STUN
		timer = STUN_TIME
	else:
		state = CHASE
		timer = randf_range(1.8, 2.6)


func _drop_trail():
	if iso_dist(global_position, last_drop) < TRAIL_STEP:
		return
	last_drop = global_position
	var life = [0.0, 4.0, 5.0, 7.0][phase]
	trail.append([global_position, life, life])
	if trail.size() > 28:
		trail.pop_front()


# omráčený miner dostává dvojnásobné poškození
func take_damage(amount):
	super(amount * 2 if state == STUN else amount)


func update_fx(delta):
	for f in trail:
		f[1] -= delta
	trail = trail.filter(func(f): return f[1] > 0)
	for p in alive_targets():
		if p.dash_timer > 0:
			continue
		for f in trail:
			if iso_dist(p.global_position, f[0]) < TRAIL_R:
				p.add_heat(TRAIL_HEAT * delta)
				break


func draw_ground(c: Node2D):
	for f in trail:
		var k = clampf(f[1] / f[2], 0.0, 1.0)
		var flick = 0.8 + 0.2 * sin(now() * 20.0 + f[0].x)
		draw_disc(c, f[0], TRAIL_R * (0.6 + 0.4 * k), Color(FIRE_COLOR, 0.28 * k * flick + 0.05))
		draw_disc(c, f[0], TRAIL_R * 0.45 * k, Color(3.2, 2.2, 0.6, 0.5 * k * flick))
	if state == AIM:
		var dir = to_screen(ram_dir)
		var side = to_screen(ram_dir.orthogonal()) * LANE_W
		var a = global_position
		var b = global_position + dir * lane_len
		var on = 0.35 if int(now() * 10.0) % 2 == 0 else 0.18
		c.draw_colored_polygon(PackedVector2Array([a + side, b + side, b - side, a - side]), Color(3, 0.5, 0.2, on))
		c.draw_line(b + side * 1.4, b - side * 1.4, Color(3.5, 0.8, 0.3, 0.9), 4.0)


# stopa se posílá jako sbalená pole (ať se snímek vejde do jednoho paketu)
func net_state() -> Array:
	var pos = PackedVector2Array()
	var life = PackedByteArray()
	for f in trail:
		pos.append(f[0])
		life.append(roundi(clampf(f[1] / f[2], 0.0, 1.0) * 255.0))
	return [state, ram_dir, lane_len, pos, life]


func apply_net_state(s: Array):
	if s.size() >= 5:
		state = s[0]
		ram_dir = s[1]
		lane_len = s[2]
		trail = []
		for i in s[3].size():
			trail.append([s[3][i], s[4][i] / 255.0, 1.0])
		if state == STUN:
			core.modulate = Color(2.5, 2.5, 0.6) if int(now() * 6) % 2 == 0 else Color(0.6, 0.6, 0.6)
		elif state == AIM:
			core.modulate = Color(4, 1, 0.3) if int(now() * 14) % 2 == 0 else Color.WHITE
		else:
			core.modulate = Color.WHITE
