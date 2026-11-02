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
const COOL_DELAY = 0.8        # za kolik s po zahřátí začne chladnout
const SHOT_HEAT = 4.0         # teplo za výstřel
const CRASH_TIME = 2.5        # délka "rebootu"
const HIT_INVULN = 0.6        # nesmrtelnost po zásahu
const KNOCKBACK = 450.0

# bonusy
const DOUBLE_JUMP_TIME = 12.0
const NITRO_TIME = 5.0
const COOLANT_AMOUNT = 50.0

var heat := 0.0
var cool_timer := 0.0         # odpočet do začátku chlazení
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

@onready var visual = $Visual
@onready var body = $Visual/Body
@onready var muzzle = $Visual/Muzzle
@onready var smoke = $Smoke


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
	var speed = SPEED * (OC_SPEED_MULT if overclock else 1.0)
	var dir = Input.get_axis("move_left", "move_right")
	velocity.x = dir * speed + knock
	knock = move_toward(knock, 0, 1800 * delta)
	if dir != 0:
		facing = sign(dir)
		visual.scale.x = facing

	max_jumps = 2 if double_jump_timer > 0 else 1
	if is_on_floor():
		jumps_left = max_jumps
	if Input.is_action_just_pressed("jump") and jumps_left > 0:
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
		heat = max(heat - COOL * delta, 0.0)
		heat_changed.emit(heat)

	update_visual()


func shoot():
	fire_cd = OC_FIRE_DELAY if overclock else FIRE_DELAY
	var b = BULLET_SCENE.instantiate()
	b.global_position = muzzle.global_position
	b.direction = Vector2(facing, 0)
	get_tree().current_scene.add_child(b)
	add_heat(SHOT_HEAT)


func add_heat(amount):
	if amount > 0 and nitro_timer > 0:
		return                                # dusík = žádné zahřívání
	heat = clamp(heat + amount, 0.0, 100.0)
	cool_timer = COOL_DELAY
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
	add_heat(amount)


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


# násobič skóre podle teploty (x1 až x4)
func multiplier():
	return 1 + int(heat / 25.0)


func crash():
	crash_timer = CRASH_TIME
	smoke.emitting = true
	crashed.emit()


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
