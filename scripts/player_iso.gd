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
const AUTO_AIM_RANGE = 650.0  # P2 míří automaticky na nejbližšího nepřítele v tomto dosahu
const LEASH = 900.0           # v co-opu se hráči nemůžou vzdálit víc (kamera)
const P2_COLOR = Color(1.0, 0.78, 0.45)

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

# --- kdo hraje ---
@export var player_index := 0  # 0 = hráč 1 (klávesnice + myš), 1 = hráč 2 (šipky, auto-míření)
var prefix := ""               # předpona akcí ("" nebo "p2_")
var auto_aim := false
var base_color := Color.WHITE
var remote_input := false      # (host) hráč 2 po síti – vstupy chodí v net_input
var net_input := {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "shoot": false, "overclock": false}
var _net_presses := {}         # akce -> počet stisků, které ještě nebyly zpracované
var puppet := false            # (klient) jen zobrazuje stav z hostitele
var _net_pos := Vector2.ZERO
var _net_max_dashes := 1

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
	if player_index == 1:
		if not Net.is_online():          # co-op na jedné klávesnici
			prefix = "p2_"
			auto_aim = true
		base_color = P2_COLOR
		$Gun/Barrel.color = Color(1.0, 0.55, 0.2)
	$Tag.text = "P%d" % (player_index + 1)
	$Tag.visible = GameSettings.two_players()
	$Tag.modulate = Color(0.5, 1.6, 2.0) if player_index == 0 else Color(2.0, 1.3, 0.5)


# název akce pro tohoto hráče
func act(action: String) -> String:
	return prefix + action


# otevřené menu (pauza, obchod, karty) -> lokální hráč nereaguje
func _ui_blocked() -> bool:
	for n in get_tree().get_nodes_in_group("ui_modal"):
		if n.visible:
			return true
	return false


func move_input() -> Vector2:
	if remote_input:
		return net_input["move"]
	if _ui_blocked():
		return Vector2.ZERO
	return Input.get_vector(act("move_left"), act("move_right"), act("move_up"), act("move_down"))


func inp_held(action: String) -> bool:
	if remote_input:
		return net_input.get(action, false)
	if _ui_blocked():
		return false
	return Input.is_action_pressed(act(action))


func inp_just(action: String) -> bool:
	if remote_input:
		if _net_presses.get(action, 0) > 0:
			_net_presses[action] -= 1
			return true
		return false
	if _ui_blocked():
		return false
	return Input.is_action_just_pressed(act(action))


# (host) vstupy hráče 2 ze sítě; stisky chodí jako počítadla, aby se neztratily
var _last_counts := {}
func set_net_input(move: Vector2, aim: Vector2, shoot: bool, oc: bool, counts: Dictionary):
	net_input["move"] = move.limit_length(1.0)
	if aim.length() > 0.1:
		net_input["aim"] = aim.normalized()
	net_input["shoot"] = shoot
	net_input["overclock"] = oc
	for a in counts:
		var diff = counts[a] - _last_counts.get(a, 0)
		if diff > 0:
			_net_presses[a] = _net_presses.get(a, 0) + diff
		_last_counts[a] = counts[a]


# druhý živý hráč (co-op), jinak null
func partner():
	for p in get_tree().get_nodes_in_group("player"):
		if p != self and not p.dead:
			return p
	return null


# vzdálenost v "herních" souřadnicích (osa Y se na obrazovce zmenšuje)
static func iso_dist(a: Vector2, b: Vector2) -> float:
	var d = a - b
	return Vector2(d.x, d.y * 2.0).length()


func max_dashes() -> int:
	if puppet:
		return _net_max_dashes
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
	if inp_just("dash") and dash_charges > 0 and dash_gap <= 0:
		start_dash()
		if dash_timer > 0:
			return

	# --- vent ---
	if inp_just("vent"):
		try_vent()

	# --- overclock (úrovně) ---
	overclock = inp_held("overclock")
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
	var input = move_input()
	velocity = input * ISO * speed + knock
	knock = knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	# co-op: hráči se nemůžou rozběhnout moc daleko od sebe
	var other = partner() if not Net.is_online() else null
	if other:
		var d = global_position - other.global_position
		if d.length() > LEASH and velocity.dot(d) > 0:
			var n = d.normalized()
			velocity -= n * velocity.dot(n)
	move_and_slide()

	# --- střelba ---
	fire_cd -= delta
	if inp_held("shoot") and fire_cd <= 0:
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
	if remote_input:
		aim_dir = net_input["aim"]
	elif auto_aim:
		# hráč 2: nejbližší nepřítel, jinak směr pohybu
		var best = null
		var best_d = AUTO_AIM_RANGE
		for e in get_tree().get_nodes_in_group("enemies"):
			var dd = iso_dist(e.global_position, global_position)
			if dd < best_d:
				best_d = dd
				best = e
		if best:
			aim_dir = (best.global_position + Vector2(0, -16) - origin).normalized()
		else:
			var mi = move_input()
			if mi.length() > 0.1:
				aim_dir = (mi * ISO).normalized()
	else:
		var to_mouse = get_global_mouse_position() - origin
		if to_mouse.length() > 4.0:
			aim_dir = to_mouse.normalized()
	facing = 1 if aim_dir.x >= 0 else -1
	gun.rotation = aim_dir.angle()
	gun.scale.y = facing


# --- dash ---
func start_dash():
	var input = move_input()
	if input.length() > 0.1:
		dash_dir = (input * ISO).normalized()
	else:
		dash_dir = aim_dir
	dash_timer = DASH_TIME
	dash_gap = DASH_TIME + DASH_GAP
	dash_charges -= 1
	dash_overclocked = inp_held("overclock")
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
	if Net.is_host():
		Net.fx_ring.rpc(player_index, radius, color)
	show_ring_local(radius, color)


func show_ring_local(radius, color):
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
		body.modulate = base_color.lerp(Color(1, 0.15, 0.1), t)    # červená podle teploty
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


# návrat do hry (co-op: mrtvý hráč se vrátí v dalším sektoru)
func revive(pos: Vector2):
	dead = false
	heat = 0.0
	crash_timer = 0.0
	dash_timer = 0.0
	oc_level = 0
	oc_hold = 0.0
	knock = Vector2.ZERO
	velocity = Vector2.ZERO
	invuln = 1.5
	global_position = pos
	smoke.emitting = false
	body.modulate = base_color
	heat_changed.emit(heat)
	Juice.burst(global_position + Vector2(0, -20), Color(0.6, 1.8, 2.2), 20)


# ============================================================
#  Síť – stav hráče (host -> klient)
# ============================================================

func net_state() -> Array:
	return [global_position, heat, dead, crash_timer, nitro_timer, in_fan_t, shield, fuse,
		invuln, aim_dir, oc_level, dash_charges, max_dashes(), vent_cd, chips,
		double_dash_timer, redline_start, upgrades, corrupts, dash_timer > 0, dash_overclocked, vent_cd_time]


# (klient) převezme stav a jen ho vykreslí
func apply_net_state(st: Array, delta: float, local_aim = null):
	_net_pos = st[0]
	if global_position.distance_to(_net_pos) > 200.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-20.0 * delta))
	heat = st[1]
	dead = st[2]
	crash_timer = st[3]
	nitro_timer = st[4]
	in_fan_t = st[5]
	shield = st[6]
	fuse = st[7]
	invuln = st[8]
	aim_dir = st[9] if local_aim == null else local_aim
	oc_level = st[10]
	dash_charges = st[11]
	_net_max_dashes = st[12]
	vent_cd = st[13]
	chips = st[14]
	double_dash_timer = st[15]
	redline_start = st[16]
	upgrades = st[17]
	corrupts = st[18]
	dash_overclocked = st[20]
	vent_cd_time = st[21]
	facing = 1 if aim_dir.x >= 0 else -1
	gun.rotation = aim_dir.angle()
	gun.scale.y = facing
	if dead:
		body.modulate = Color(0.3, 0.3, 0.3)
		smoke.emitting = true
		return
	if st[19]:                            # dash -> duchové
		ghost_timer -= delta
		if ghost_timer <= 0:
			ghost_timer = GHOST_INTERVAL
			spawn_ghost()
	if crash_timer > 0:
		body.modulate = Color(0.25, 0.35, 1.2) if int(crash_timer * 6) % 2 == 0 else Color(0.1, 0.12, 0.45)
		smoke.emitting = true
		return
	update_visual(delta)
