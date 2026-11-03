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
const OC_SPEED_MULT = 1.6     # násobič rychlosti při overclocku
const FIRE_DELAY = 0.3
const OC_FIRE_DELAY = 0.12
const HEAT_UP = 20.0          # teplota/s při overclocku
const COOL = 25.0             # chlazení/s
const SHOT_HEAT = 4.0         # teplo za výstřel
const HIT_INVULN = 0.6        # nesmrtelnost po zásahu
const KNOCKBACK = 450.0
const PLATFORM_LAYER = 5      # vrstva proskočitelných plošin
const DROP_TIME = 0.25        # jak dlouho padá skrz plošinu
const SPREAD = 0.15           # úhel mezi střelami ve vějíři (rad)
const BLAST_RADIUS = 180.0
const BLAST_DAMAGE = 5

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
var upgrades := {}            # id : počet

# --- stav ---
var heat := 0.0
var cool_timer := 0.0
var overclock := false
var crash_timer := 0.0
var fire_cd := 0.0
var facing := 1
var max_jumps := 1
var jumps_left := 1
var invuln := 0.0
var knock := 0.0
var dead := false
var double_jump_timer := 0.0
var nitro_timer := 0.0
var drop_timer := 0.0

@onready var visual = $Visual
@onready var body = $Visual/Body
@onready var muzzle = $Visual/Muzzle
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
	set_collision_mask_value(PLATFORM_LAYER, drop_timer <= 0)

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

	# --- pohyb ---
	overclock = Input.is_action_pressed("overclock")
	var speed = SPEED * speed_mult * (OC_SPEED_MULT if overclock else 1.0)
	var dir = Input.get_axis("move_left", "move_right")
	velocity.x = dir * speed + knock
	knock = move_toward(knock, 0, 1800 * delta)
	if dir != 0:
		facing = sign(dir)
		visual.scale.x = facing

	max_jumps = 1 + extra_jumps + (1 if double_jump_timer > 0 else 0)
	if is_on_floor():
		jumps_left = max_jumps
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() and Input.is_action_pressed("move_down"):
			drop_timer = DROP_TIME            # dolů + skok = propadnout plošinou
		elif jumps_left > 0:
			velocity.y = JUMP
			jumps_left -= 1

	move_and_slide()

	# --- střelba ---
	fire_cd -= delta
	if Input.is_action_pressed("shoot") and fire_cd <= 0:
		shoot()

	# --- teplota ---
	if overclock:
		add_heat(HEAT_UP * delta)
	elif cool_timer > 0:
		cool_timer -= delta
	else:
		heat = max(heat - COOL * cool_mult * delta, 0.0)
		heat_changed.emit(heat)

	update_visual()


func shoot():
	fire_cd = (OC_FIRE_DELAY if overclock else FIRE_DELAY) * fire_rate_mult
	var count = 1 + multishot
	var dmg = damage + (1 if heat_power and heat >= 50.0 else 0)
	for i in count:
		var angle = (i - (count - 1) / 2.0) * SPREAD
		var b = BULLET_SCENE.instantiate()
		b.global_position = muzzle.global_position
		b.direction = Vector2(facing, 0).rotated(angle)
		b.damage = dmg
		b.pierce = pierce
		get_tree().current_scene.add_child(b)
	add_heat(SHOT_HEAT * shot_heat_mult)


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
	add_heat(amount * contact_heat_mult)


# volá pickup při sebrání
func apply_powerup(type):
	if dead:
		return
	match type:
		Pickup.Type.DOUBLE_JUMP:
			double_jump_timer = DOUBLE_JUMP_TIME
			if not is_on_floor():
				jumps_left += 1               # hned můžeš skočit i ve vzduchu
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


# násobič skóre podle teploty (x1 až x4)
func multiplier():
	return 1 + int(heat / 25.0)


func crash():
	crash_timer = crash_time
	smoke.emitting = true
	crashed.emit()
	if thermal_blast:
		do_thermal_blast()


func do_thermal_blast():
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(global_position) < BLAST_RADIUS:
			e.take_damage(BLAST_DAMAGE)
	blast_ring.visible = true
	blast_ring.scale = Vector2(0.2, 0.2)
	blast_ring.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(blast_ring, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(blast_ring, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): blast_ring.visible = false)


func die():
	dead = true
	body.color = Color(0.3, 0.3, 0.3)
	smoke.emitting = true
	died.emit()


func update_visual():
	var t = heat / 100.0
	if nitro_timer > 0:
		body.color = Color(0.7, 0.9, 1.0)                    # zmrzlý od dusíku
	else:
		body.color = Color.WHITE.lerp(Color(1, 0.15, 0.1), t)   # červená podle teploty
	smoke.emitting = heat > 60.0                            # kouř od 60 %
	if heat > 85.0:                                         # třes těsně před crashem
		visual.position = Vector2(randf_range(-2, 2), randf_range(-2, 2))
	else:
		visual.position = Vector2.ZERO
	# blikání při nesmrtelnosti
	visual.modulate.a = 0.4 if invuln > 0 and int(invuln * 20) % 2 == 0 else 1.0
