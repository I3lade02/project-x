extends CharacterBody2D
## Hráč v izo pohledu (bez skoku). Pozice = bod na zemi, grafika (Visual) je nad ní.

signal heat_changed(value)
signal crashed
signal rebooted
signal died

const BULLET_SCENE = preload("res://scenes/bullet_iso.tscn")
const Pickup = preload("res://scripts/pickup.gd")

const ISO = Vector2(1.0, 0.5)   # na obrazovce je osa Y poloviční
const SPEED = 280.0
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
const KNOCKBACK = 420.0
const SPREAD = 0.15           # úhel mezi střelami ve vějíři (rad)
const BLAST_RADIUS = 180.0
const BLAST_DAMAGE = 5
const WARN_HEAT = 85.0        # od kdy pípá varování
const AIM_HEIGHT = 22.0       # výška zbraně nad zemí

# vent
const VENT_MIN_HEAT = 40.0    # od kolika % jde ventovat
const VENT_BASE_RADIUS = 110.0
const VENT_RADIUS_PER_HEAT = 1.6
const VENT_KNOCK = 650.0

# dash (nabíjí se po jednom)
const DASH_SPEED = 900.0
const DASH_TIME = 0.14
const DASH_RECHARGE = 0.6     # za jak dlouho se nabije 1 dash
const DASH_GAP = 0.1          # min. mezera mezi dvěma dashi
const DASH_HEAT = 10.0
const DASH_DAMAGE = 2         # jen při overclocku
const DASH_HIT_RADIUS = 40.0
const GHOST_INTERVAL = 0.025
const GHOST_SHAPE = [Vector2(-19, -40), Vector2(0, -50), Vector2(19, -40), Vector2(19, 0), Vector2(0, 10), Vector2(-19, 0)]

const GUN_POS = Vector2(0, -22)

# bonusy
const DOUBLE_DASH_TIME = 12.0
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
var extra_dashes := 0
var contact_heat_mult := 1.0
var crash_time := 2.5         # délka "rebootu"
var thermal_blast := false
var heat_power := false
var vent_cd_time := 3.0       # cooldown ventu
var redline_start := 80.0     # od kolika % je REDLINE
var upgrades := {}            # id : počet

# --- čipy a obchod ---
var chips := 0                # měna z nepřátel
var shield := 0               # pohltí zásah (max 3)
var fuse := 0                 # pojistka: místo crashe se vyventuješ
var chip_magnet := 1.0        # násobí dosah přitahování čipů
var dash_recharge_mult := 1.0
var start_nitro := 0          # příští vlna začne s dusíkem
var corrupt_removals := 0     # kolikrát už byl corrupt odstraněn (zdražuje)
var clean_bought := 0         # kolikrát koupen čistý upgrade (zdražuje)

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
var invuln := 0.0
var knock := Vector2.ZERO
var dead := false
var double_dash_timer := 0.0
var nitro_timer := 0.0
var warned := false
var aim_dir := Vector2.RIGHT
var squash := Vector2.ONE
var dash_timer := 0.0
var dash_gap := 0.0
var dash_charges := 1
var dash_recharge := 0.0
var dash_dir := Vector2.RIGHT
var dash_overclocked := false
var dash_hits := []
var ghost_timer := 0.0
var oc_level := 0             # 0 = bez overclocku, 1–3
var oc_hold := 0.0
var vent_cd := 0.0
var in_fan_t := 0.0           # > 0 = stojí ve ventilátoru (nastavuje fan_iso.gd)

@onready var visual = $Visual
@onready var body = $Visual/Body
@onready var gun = $Gun
@onready var muzzle = $Gun/Muzzle
@onready var smoke = $Smoke
@onready var blast_ring = $BlastRing
@onready var frost = $Frost
@onready var shield_ring = $ShieldRing


func _ready():
	add_to_group("player")


# vzdálenost v "herních" souřadnicích (osa Y se na obrazovce zmenšuje)
static func iso_dist(a: Vector2, b: Vector2) -> float:
	var d = a - b
	return Vector2(d.x, d.y * 2.0).length()


func max_dashes() -> int:
	return 1 + extra_dashes + (1 if double_dash_timer > 0 else 0)


func world_node():
	var w = get_tree().get_first_node_in_group("world")
	return w if w else get_tree().current_scene


func _physics_process(delta):
	if dead:
		return

	invuln -= delta
	double_dash_timer = max(double_dash_timer - delta, 0.0)
	nitro_timer = max(nitro_timer - delta, 0.0)
	vent_cd -= delta
	dash_gap -= delta
	in_fan_t -= delta
	# nabíjení dashů
	if dash_charges < max_dashes():
		dash_recharge -= delta
		if dash_recharge <= 0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE * dash_recharge_mult
	else:
		dash_charges = max_dashes()
		dash_recharge = DASH_RECHARGE * dash_recharge_mult
	update_aim()

	# --- CRASH stav (modrá obrazovka smrti :) ---
	if crash_timer > 0:
		crash_timer -= delta
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0 * delta)
		move_and_slide()
		body.modulate = Color(0.25, 0.35, 1.2) if int(crash_timer * 6) % 2 == 0 else Color(0.1, 0.12, 0.45)
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
	if Input.is_action_just_pressed("dash") and dash_charges > 0 and dash_gap <= 0:
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

	# --- pohyb (8 směrů) ---
	var speed = SPEED * speed_mult * (OC_LEVELS[oc_level - 1]["speed"] if oc_level > 0 else 1.0)
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * ISO * speed + knock
	knock = knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	move_and_slide()

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


# --- míření myší ---
func update_aim():
	var origin = global_position + Vector2(0, -AIM_HEIGHT)
	var to_mouse = get_global_mouse_position() - origin
	if to_mouse.length() > 4.0:
		aim_dir = to_mouse.normalized()
	facing = 1 if aim_dir.x >= 0 else -1
	gun.rotation = aim_dir.angle()
	gun.scale.y = facing


# --- dash ---
func start_dash():
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length() > 0.1:
		dash_dir = (input * ISO).normalized()
	else:
		dash_dir = aim_dir
	dash_timer = DASH_TIME
	dash_gap = DASH_TIME + DASH_GAP
	dash_charges -= 1
	dash_overclocked = Input.is_action_pressed("overclock")
	dash_hits = []
	ghost_timer = 0.0
	invuln = max(invuln, DASH_TIME + 0.05)
	knock = Vector2.ZERO
	squash = Vector2(1.35, 0.75)
	Juice.play("dash", -4.0)
	Juice.shake(0.1)
	add_heat(DASH_HEAT)                       # může způsobit crash -> zruší dash


func dash_step(delta):
	dash_timer -= delta
	velocity = dash_dir * DASH_SPEED * Vector2(1.0, 0.75)
	move_and_slide()
	# overclock dash zraní bugy, kterými proletíš
	if dash_overclocked:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e in dash_hits and iso_dist(e.global_position, global_position) < DASH_HIT_RADIUS:
				dash_hits.append(e)
				e.take_damage(DASH_DAMAGE)
	ghost_timer -= delta
	if ghost_timer <= 0:
		ghost_timer = GHOST_INTERVAL
		spawn_ghost()
	if dash_timer <= 0:
		velocity *= 0.3


# "duch" za postavou při dashi
func spawn_ghost():
	var g = Polygon2D.new()
	g.polygon = PackedVector2Array(GHOST_SHAPE)
	g.color = Color(2.5, 0.5, 1.8, 0.55) if dash_overclocked else Color(0.4, 1.5, 2.0, 0.45)
	g.global_position = global_position
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
	var world = world_node()
	for i in count:
		var angle = (i - (count - 1) / 2.0) * SPREAD
		var b = BULLET_SCENE.instantiate()
		b.direction = aim_dir.rotated(angle)
		# střela startuje na zemi pod hlavní, grafika je o AIM_HEIGHT výš
		b.global_position = global_position + b.direction * 18.0
		b.damage = dmg
		b.pierce = pierce
		b.hot = redline
		world.add_child(b)


func add_heat(amount):
	if amount > 0 and nitro_timer > 0:
		return                                # dusík = žádné zahřívání
	heat = clamp(heat + amount, 0.0, 100.0)
	cool_timer = cool_delay
	heat_changed.emit(heat)
	if heat >= 100.0 and crash_timer <= 0:
		if fuse > 0:                          # pojistka: místo crashe nouzový vent
			fuse -= 1
			vent()
			return
		crash()


# volá nepřítel při dotyku
func hit(amount, from_pos: Vector2):
	if dead or invuln > 0:
		return
	if shield > 0:                            # štít pohltí zásah
		shield -= 1
		invuln = HIT_INVULN
		Juice.play("shield", -2.0)
		Juice.shake(0.2)
		show_ring(60.0, Color(0.6, 1.6, 2.2, 0.6))
		return
	if crash_timer > 0:
		die()
		return
	invuln = HIT_INVULN
	var d = global_position - from_pos
	var dir = Vector2(d.x, d.y * 2.0).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	knock = dir * ISO * KNOCKBACK
	Juice.play("hurt")
	Juice.shake(0.4)
	Juice.hitstop(0.08)
	add_heat(amount * contact_heat_mult)


# volá pickup při sebrání
func apply_powerup(type):
	if dead:
		return
	match type:
		Pickup.Type.DOUBLE_JUMP:              # v izo verzi = double dash
			double_dash_timer = DOUBLE_DASH_TIME
			dash_charges += 1
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
		"jump":                               # v izo verzi = +1 dash
			extra_dashes += 1
			dash_charges += 1
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
		if iso_dist(e.global_position, global_position) < BLAST_RADIUS:
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
	vent()


func vent():
	var h = heat
	var radius = VENT_BASE_RADIUS + h * VENT_RADIUS_PER_HEAT
	var dmg = 1 + int(h / 25.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if iso_dist(e.global_position, global_position) < radius:
			e.take_damage(dmg)
			if e.has_method("knockback"):
				var d = e.global_position - global_position
				var dir = Vector2(d.x, d.y * 2.0).normalized()
				e.knockback(dir * ISO * VENT_KNOCK)
	heat = 0.0
	cool_timer = 0.0
	warned = false
	heat_changed.emit(heat)
	vent_cd = vent_cd_time
	squash = Vector2(1.3, 0.8)
	show_ring(radius, Color(0.6, 2.2, 2.6, 0.6))
	Juice.play("vent")
	Juice.shake(0.5)
	Juice.hitstop(0.06)
	Juice.burst(global_position + Vector2(0, -20), Color(1.5, 2.0, 2.2), 24)


# rozpínající se elipsa na zemi (vent / termální výbuch)
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
	body.modulate = Color(0.3, 0.3, 0.3)
	smoke.emitting = true
	died.emit()


func update_visual(delta):
	var t = heat / 100.0
	if nitro_timer > 0:
		body.modulate = Color(0.7, 0.9, 1.0)                    # zmrzlý od dusíku
	else:
		body.modulate = Color.WHITE.lerp(Color(1, 0.15, 0.1), t)   # červená podle teploty
	if in_fan_t > 0:
		body.modulate = body.modulate.lerp(Color(0.6, 1.3, 1.6), 0.5)  # chladne ve ventilátoru
	frost.emitting = in_fan_t > 0
	shield_ring.visible = shield > 0
	shield_ring.modulate.a = 0.5 + 0.3 * sin(Time.get_ticks_msec() / 150.0)
	smoke.emitting = heat > 60.0                               # kouř od 60 %

	# squash & stretch
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
	visual.scale = squash
	gun.position = gun.position.lerp(GUN_POS, 1.0 - exp(-20.0 * delta))

	if heat > WARN_HEAT:                                       # třes těsně před crashem
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


# ============================================================
#  Čipy a obchod
# ============================================================

func add_chips(n: int):
	chips += n


# efekt položky z terminálu, vrací text pro hráče
func apply_shop_item(id: String, arg = null) -> String:
	match id:
		"shield":
			shield = mini(shield + 1, 3)
			return "Štít: %d/3" % shield
		"fuse":
			fuse += 1
			return "Pojistka připravena"
		"fins":
			cool_mult += 0.15
			return "Chlazení +15 %"
		"capacitor":
			dash_recharge_mult *= 0.85
			return "Dash se nabíjí rychleji"
		"magnet":
			chip_magnet *= 1.5
			return "Magnet zesílen"
		"nitro":
			start_nitro += 1
			return "Příští vlna začne s dusíkem"
		"remove_corrupt":
			remove_corrupt(arg)
			corrupt_removals += 1
			return "Corrupt odstraněn"
	return ""


# opak apply_corrupt()
func remove_corrupt(id):
	if id == null or not corrupts.has(id):
		return
	corrupts[id] -= 1
	if corrupts[id] <= 0:
		corrupts.erase(id)
	match id:
		"fan": cool_mult += 0.15
		"sensor": heat_up_mult -= 0.25
		"fragment": shot_heat_mult /= 1.2
		"io": fire_rate_mult /= 1.1
		"heavy": speed_mult += 0.08
		"firewall": enemy_hp_bonus = maxi(enemy_hp_bonus - 1, 0)
		"fastbugs": enemy_speed_mult -= 0.1
		"leak": extra_enemies = maxi(extra_enemies - 2, 0)
		"sensitive": contact_heat_mult /= 1.25
		"boot": crash_time -= 0.5
		"packet": jam_chance = maxf(jam_chance - 0.15, 0.0)
		"dry": drop_mult /= 0.7
		"clog": vent_cd_time -= 1.5
