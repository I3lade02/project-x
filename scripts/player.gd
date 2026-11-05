extends CharacterBody2D

signal heat_changed(value)
signal crashed
signal rebooted
signal died

const BULLET_SCENE = preload("res://scenes/bullet.tscn")
const Pickup = preload("res://scripts/pickup.gd")

const SPEED = 300.0
const JUMP = -650.0
const GRAVITY = 1400.0
const FIRE_DELAY = 0.3
# úrovně overclocku: čím déle držíš, tím vyšší (rychlost, prodleva palby, teplo/s)
const OC_LEVELS = [
	{"speed": 1.4, "fire": 0.15, "heat": 15.0},
	{"speed": 1.65, "fire": 0.12, "heat": 25.0},
	{"speed": 1.9, "fire": 0.09, "heat": 40.0},
]
const OC_LEVEL_TIME = 1.2     # po kolika s držení se zvýší úroveň
const COOL = 25.0             # chlazení/s
const SHOT_HEAT = 4.0         # teplo za výstřel
const HIT_INVULN = 0.6        # nesmrtelnost po zásahu
const KNOCKBACK = 450.0
const PLATFORM_LAYER = 5      # vrstva proskočitelných plošin
const DROP_TIME = 0.25        # jak dlouho padá skrz plošinu
const SPREAD = 0.15           # úhel mezi střelami ve vějíři (rad)
const BLAST_RADIUS = 180.0
const BLAST_DAMAGE = 5
const WARN_HEAT = 85.0        # od kdy pípá varování

# vent
const VENT_MIN_HEAT = 40.0    # od kolika % jde ventovat
const VENT_BASE_RADIUS = 110.0
const VENT_RADIUS_PER_HEAT = 1.6
const VENT_KNOCK = 650.0

# skok
const COYOTE_TIME = 0.1       # jak dlouho po sjetí z hrany jde ještě skočit
const JUMP_BUFFER = 0.12      # skok zmáčknutý těsně před dopadem
const JUMP_CUT = 0.5          # puštění skoku = nižší skok

# dash
const DASH_SPEED = 950.0
const DASH_TIME = 0.14
const DASH_COOLDOWN = 0.55
const DASH_HEAT = 10.0
const DASH_DAMAGE = 2         # jen při overclocku
const DASH_HIT_RADIUS = 34.0
const GHOST_INTERVAL = 0.025

const GUN_POS = Vector2(0, -2)

# bonusy
const DOUBLE_JUMP_TIME = 12.0
const NITRO_TIME = 5.0
const COOLANT_AMOUNT = 50.0

# --- staty (mění je upgrady) ---
var speed_mult := 1.0
var cool_mult := 1.0
var cool_delay := 0.8         # za kolik s po zahřátí začne chladnout
var shot_heat_mult := 1.0
var fire_rate_mult := 1.0     # násobí prodlevu mezi výstřely
var damage := 1
var pierce := 0
var multishot := 0
var extra_jumps := 0
var contact_heat_mult := 1.0
var crash_time := 2.5         # délka "rebootu"
var thermal_blast := false
var heat_power := false
var vent_cd_time := 3.0       # cooldown ventu
var redline_start := 80.0     # od kolika % je REDLINE
var upgrades := {}            # id : počet

# --- corrupty ---
var heat_up_mult := 1.0       # jak moc hřeje overclock
var jam_chance := 0.0         # šance, že se výstřel zasekne
var enemy_hp_bonus := 0       # čte aréna
var enemy_speed_mult := 1.0   # čte aréna
var extra_enemies := 0        # čte aréna
var drop_mult := 1.0          # čte aréna
var corrupts := {}            # id : počet

# --- stav ---
var heat := 0.0
var cool_timer := 0.0
var overclock := false
var crash_timer := 0.0
var fire_cd := 0.0
var facing := 1
var max_jumps := 1
var air_jumps_left := 0
var coyote := 0.0
var jump_buffer := 0.0
var invuln := 0.0
var knock := 0.0
var dead := false
var double_jump_timer := 0.0
var nitro_timer := 0.0
var drop_timer := 0.0
var warned := false
var aim_dir := Vector2.RIGHT
var squash := Vector2.ONE
var dash_timer := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var dash_overclocked := false
var dash_hits := []
var ghost_timer := 0.0
var oc_level := 0             # 0 = bez overclocku, 1–3
var oc_hold := 0.0
var vent_cd := 0.0

@onready var visual = $Visual
@onready var body = $Visual/Body
@onready var gun = $Gun
@onready var muzzle = $Gun/Muzzle
@onready var smoke = $Smoke
@onready var blast_ring = $BlastRing


func _ready():
	add_to_group("player")


func _physics_process(delta):
	if dead:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	invuln -= delta
	double_jump_timer = max(double_jump_timer - delta, 0.0)
	nitro_timer = max(nitro_timer - delta, 0.0)
	drop_timer -= delta
	dash_cd -= delta
	vent_cd -= delta
	set_collision_mask_value(PLATFORM_LAYER, drop_timer <= 0)
	update_aim()

	# --- CRASH stav (modrá obrazovka smrti :) ---
	if crash_timer > 0:
		crash_timer -= delta
		velocity.x = move_toward(velocity.x, 0, SPEED * delta * 4)
		move_and_slide()
		body.color = Color(0.2, 0.3, 1.0) if int(crash_timer * 6) % 2 == 0 else Color(0.1, 0.1, 0.4)
		if crash_timer <= 0:
			heat = 50.0
			heat_changed.emit(heat)
			rebooted.emit()
		return

	# --- DASH ---
	if dash_timer > 0:
		dash_step(delta)
		update_visual(delta)
		return
	if Input.is_action_just_pressed("dash") and dash_cd <= 0:
		start_dash()
		if dash_timer > 0:
			return

	# --- vent ---
	if Input.is_action_just_pressed("vent"):
		try_vent()

	# --- overclock (úrovně) ---
	overclock = Input.is_action_pressed("overclock")
	if overclock:
		oc_hold += delta
		var lvl = min(1 + int(oc_hold / OC_LEVEL_TIME), OC_LEVELS.size())
		if lvl > oc_level and oc_level > 0:
			Juice.play("oc_up", -6.0, 0.0)
			Juice.shake(0.08)
		oc_level = lvl
	else:
		oc_hold = 0.0
		oc_level = 0

	# --- pohyb ---
	var speed = SPEED * speed_mult * (OC_LEVELS[oc_level - 1]["speed"] if oc_level > 0 else 1.0)
	var dir = Input.get_axis("move_left", "move_right")
	velocity.x = dir * speed + knock
	knock = move_toward(knock, 0, 1800 * delta)

	# --- skok (coyote time + jump buffer) ---
	max_jumps = 1 + extra_jumps + (1 if double_jump_timer > 0 else 0)
	if is_on_floor():
		coyote = COYOTE_TIME
		air_jumps_left = max_jumps - 1
	else:
		coyote -= delta

	var fresh_press := false
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() and Input.is_action_pressed("move_down"):
			drop_timer = DROP_TIME            # dolů + skok = propadnout plošinou
		else:
			jump_buffer = JUMP_BUFFER
			fresh_press = true
	jump_buffer -= delta

	if jump_buffer > 0 and coyote > 0:
		do_jump()
		coyote = 0.0
	elif fresh_press and air_jumps_left > 0:
		do_jump()
		air_jumps_left -= 1
		Juice.burst(global_position + Vector2(0, 20), Color(0.5, 1.5, 2.0), 6)

	if Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y *= JUMP_CUT                # krátké zmáčknutí = nízký skok

	# --- pohyb + dopad ---
	var was_on_floor = is_on_floor()
	var fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor and fall_speed > 300:
		squash = Vector2(1.3, 0.75)
		Juice.play("land", -10.0)
		Juice.burst(global_position + Vector2(0, 20), Color(0.6, 1.2, 1.8), 6)

	# --- střelba ---
	fire_cd -= delta
	if Input.is_action_pressed("shoot") and fire_cd <= 0:
		shoot()

	# --- teplota ---
	if overclock:
		add_heat(OC_LEVELS[oc_level - 1]["heat"] * heat_up_mult * delta)
	elif cool_timer > 0:
		cool_timer -= delta
	else:
		heat = max(heat - COOL * cool_mult * delta, 0.0)
		heat_changed.emit(heat)

	update_visual(delta)


func do_jump():
	velocity.y = JUMP
	jump_buffer = 0.0
	squash = Vector2(0.75, 1.3)
	Juice.play("jump", -6.0)


# --- míření myší ---
func update_aim():
	var to_mouse = get_global_mouse_position() - gun.global_position
	if to_mouse.length() > 4.0:
		aim_dir = to_mouse.normalized()
	facing = 1 if aim_dir.x >= 0 else -1
	gun.rotation = aim_dir.angle()
	gun.scale.y = facing


# --- dash ---
func start_dash():
	var d = Input.get_axis("move_left", "move_right")
	dash_dir = Vector2(d if d != 0 else facing, 0).normalized()
	dash_timer = DASH_TIME
	dash_cd = DASH_COOLDOWN
	dash_overclocked = Input.is_action_pressed("overclock")
	dash_hits = []
	ghost_timer = 0.0
	invuln = max(invuln, DASH_TIME + 0.05)
	knock = 0.0
	squash = Vector2(1.4, 0.7)
	Juice.play("dash", -4.0)
	Juice.shake(0.1)
	add_heat(DASH_HEAT)                       # může způsobit crash -> zruší dash


func dash_step(delta):
	dash_timer -= delta
	velocity = dash_dir * DASH_SPEED
	move_and_slide()
	# overclock dash zraní bugy, kterými proletíš
	if dash_overclocked:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e in dash_hits and e.global_position.distance_to(global_position) < DASH_HIT_RADIUS:
				dash_hits.append(e)
				e.take_damage(DASH_DAMAGE)
	ghost_timer -= delta
	if ghost_timer <= 0:
		ghost_timer = GHOST_INTERVAL
		spawn_ghost()
	if dash_timer <= 0:
		velocity.x *= 0.4


# "duch" za postavou při dashi
func spawn_ghost():
	var g = ColorRect.new()
	g.size = Vector2(28, 40)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.color = Color(2.5, 0.5, 1.8, 0.6) if dash_overclocked else Color(0.4, 1.5, 2.0, 0.5)
	g.global_position = global_position - Vector2(14, 20)
	get_tree().current_scene.add_child(g)
	var tw = g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.2)
	tw.tween_callback(g.queue_free)


func shoot():
	fire_cd = (OC_LEVELS[oc_level - 1]["fire"] if oc_level > 0 else FIRE_DELAY) * fire_rate_mult
	add_heat(SHOT_HEAT * shot_heat_mult)
	if randf() < jam_chance:
		Juice.play("jam", -4.0)
		return                                # packet loss – výstřel se zasekl
	Juice.play("shoot", -8.0)
	gun.position = GUN_POS - aim_dir * 5.0   # cuknutí zbraně
	var count = 1 + multishot
	var redline = in_redline()
	var dmg = damage + (1 if heat_power and heat >= 50.0 else 0) + (1 if redline else 0)
	for i in count:
		var angle = (i - (count - 1) / 2.0) * SPREAD
		var b = BULLET_SCENE.instantiate()
		b.global_position = muzzle.global_position
		b.direction = aim_dir.rotated(angle)
		b.damage = dmg
		b.pierce = pierce
		b.hot = redline
		get_tree().current_scene.add_child(b)


func add_heat(amount):
	if amount > 0 and nitro_timer > 0:
		return                                # dusík = žádné zahřívání
	heat = clamp(heat + amount, 0.0, 100.0)
	cool_timer = cool_delay
	heat_changed.emit(heat)
	if heat >= 100.0 and crash_timer <= 0:
		crash()


# volá nepřítel při dotyku
func hit(amount, from_x):
	if dead or invuln > 0:
		return
	if crash_timer > 0:
		die()
		return
	invuln = HIT_INVULN
	var side = sign(global_position.x - from_x)
	if side == 0:
		side = 1
	knock = KNOCKBACK * side
	velocity.y = -250
	Juice.play("hurt")
	Juice.shake(0.4)
	Juice.hitstop(0.08)
	add_heat(amount * contact_heat_mult)


# volá pickup při sebrání
func apply_powerup(type):
	if dead:
		return
	match type:
		Pickup.Type.DOUBLE_JUMP:
			double_jump_timer = DOUBLE_JUMP_TIME
			air_jumps_left += 1               # hned můžeš skočit i ve vzduchu
		Pickup.Type.COOLANT:
			heat = max(heat - COOLANT_AMOUNT, 0.0)
			heat_changed.emit(heat)
		Pickup.Type.NITRO:
			nitro_timer = NITRO_TIME


# volá aréna po výběru karty
func apply_upgrade(id):
	upgrades[id] = upgrades.get(id, 0) + 1
	match id:
		"cooler": cool_mult += 0.3
		"paste": cool_delay = max(cool_delay - 0.2, 0.2)
		"efficient": shot_heat_mult *= 0.75
		"firerate": fire_rate_mult *= 0.8
		"pierce": pierce += 1
		"multishot": multishot += 1
		"damage": damage += 1
		"speed": speed_mult += 0.1
		"jump": extra_jumps += 1
		"armor": contact_heat_mult *= 0.7
		"reboot": crash_time = max(crash_time - 0.7, 1.0)
		"blast": thermal_blast = true
		"heatpower": heat_power = true
		"ventcd": vent_cd_time = max(vent_cd_time - 1.0, 1.0)
		"redline": redline_start = 70.0


# volá aréna spolu s upgradem
func apply_corrupt(id):
	if id == "":
		return
	corrupts[id] = corrupts.get(id, 0) + 1
	match id:
		"fan": cool_mult = max(cool_mult - 0.15, 0.3)
		"sensor": heat_up_mult += 0.25
		"fragment": shot_heat_mult *= 1.2
		"io": fire_rate_mult *= 1.1
		"heavy": speed_mult = max(speed_mult - 0.08, 0.5)
		"firewall": enemy_hp_bonus += 1
		"fastbugs": enemy_speed_mult += 0.1
		"leak": extra_enemies += 2
		"sensitive": contact_heat_mult *= 1.25
		"boot": crash_time += 0.5
		"packet": jam_chance += 0.15
		"dry": drop_mult *= 0.7
		"clog": vent_cd_time += 1.5


# násobič skóre podle teploty (x1 až x4)
func multiplier():
	return 1 + int(heat / 25.0)


func crash():
	crash_timer = crash_time
	dash_timer = 0.0
	oc_level = 0
	oc_hold = 0.0
	smoke.emitting = true
	Juice.play("crash")
	Juice.shake(0.8)
	Juice.hitstop(0.15)
	crashed.emit()
	if thermal_blast:
		do_thermal_blast()


func do_thermal_blast():
	Juice.play("blast")
	Juice.shake(1.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(global_position) < BLAST_RADIUS:
			e.take_damage(BLAST_DAMAGE)
	show_ring(BLAST_RADIUS, Color(3, 1.5, 0.3, 0.6))


# REDLINE = 80–100 % teploty (bonus poškození)
func in_redline():
	return heat >= redline_start and crash_timer <= 0


# vent – vypustí všechno teplo jako výbuch páry
func try_vent():
	if vent_cd > 0 or heat < VENT_MIN_HEAT:
		Juice.play("jam", -6.0)               # nejde (cooldown / málo tepla)
		return
	var h = heat
	var radius = VENT_BASE_RADIUS + h * VENT_RADIUS_PER_HEAT
	var dmg = 1 + int(h / 25.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		var d = e.global_position - global_position
		if d.length() < radius:
			e.take_damage(dmg)
			if e.has_method("knockback"):
				e.knockback(d.normalized() * VENT_KNOCK + Vector2(0, -250))
	heat = 0.0
	cool_timer = 0.0
	warned = false
	heat_changed.emit(heat)
	vent_cd = vent_cd_time
	velocity.y = min(velocity.y, -200.0)
	squash = Vector2(1.3, 0.8)
	show_ring(radius, Color(0.6, 2.2, 2.6, 0.6))
	Juice.play("vent")
	Juice.shake(0.5)
	Juice.hitstop(0.06)
	Juice.burst(global_position, Color(1.5, 2.0, 2.2), 24)


# rozpínající se kruh (vent / termální výbuch)
func show_ring(radius, color):
	blast_ring.color = color
	blast_ring.visible = true
	blast_ring.scale = Vector2(0.2, 0.2)
	blast_ring.modulate.a = 1.0
	var target = Vector2.ONE * (radius / BLAST_RADIUS)
	var tw = create_tween()
	tw.tween_property(blast_ring, "scale", target, 0.25)
	tw.parallel().tween_property(blast_ring, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): blast_ring.visible = false)


func die():
	dead = true
	body.color = Color(0.3, 0.3, 0.3)
	smoke.emitting = true
	died.emit()


func update_visual(delta):
	var t = heat / 100.0
	if nitro_timer > 0:
		body.color = Color(0.7, 0.9, 1.0)                    # zmrzlý od dusíku
	else:
		body.color = Color.WHITE.lerp(Color(1, 0.15, 0.1), t)   # červená podle teploty
	smoke.emitting = heat > 60.0                            # kouř od 60 %

	# squash & stretch + otočení podle míření
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
	visual.scale = Vector2(facing * squash.x, squash.y)
	gun.position = gun.position.lerp(GUN_POS, 1.0 - exp(-20.0 * delta))

	if heat > WARN_HEAT:                                    # třes těsně před crashem
		visual.position = Vector2(randf_range(-2, 2), randf_range(-2, 2))
	else:
		visual.position = Vector2.ZERO
	# varovné pípnutí (jednou, znovu až po vychladnutí pod 75)
	if heat > WARN_HEAT and not warned:
		warned = true
		Juice.play("warn", -4.0, 0.0)
	elif heat < WARN_HEAT - 10.0:
		warned = false
	# blikání při nesmrtelnosti
	visual.modulate.a = 0.4 if invuln > 0 and int(invuln * 20) % 2 == 0 else 1.0
