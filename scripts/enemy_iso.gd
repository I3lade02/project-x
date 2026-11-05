extends CharacterBody2D
## Základní nepřítel v izo pohledu (bug). Ostatní typy (dron, turret, tank, boss) z něj dědí.
## Pohyb je v "herních" souřadnicích, na obrazovce se osa Y zmenší na polovinu.

signal died(pos, value, drops)

const ISO = Vector2(1.0, 0.5)
const FLASH = Color(3, 3, 3)
const HEAT_ORB = preload("res://scenes/heat_orb.tscn")

@export var hp := 3
@export var speed_scale := 1.0        # násobí rychlost, kterou nastaví aréna
@export var contact_heat := 20.0      # kolik tepla dá dotyk
@export var score_value := 10
@export var drops := 0.25             # < 1 = šance na bonus, >= 1 = počet bonusů
@export var knock_resist := 0.0       # 0 = plné odhození, 1 = imunní
@export var separation_dist := 34.0   # min. rozestup mezi nepřáteli
@export var separation_force := 0.8
@export var burst_color := Color(0.3, 0.9, 0.4)

var speed := 120.0                    # nastavuje aréna před přidáním do scény
var max_hp := 3
var target_offset := Vector2.ZERO     # každý míří kousek vedle hráče
var accel := 1200.0
var stun := 0.0                       # po odhození chvíli nekontroluje pohyb
var wall_steer := Vector2.ZERO        # obcházení bloků
var t := 0.0
var player

@onready var body = $Visual/Body
@onready var visual = $Visual
@onready var hitbox = $Hitbox


func _ready():
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	speed *= speed_scale * randf_range(0.85, 1.15)
	target_offset = Vector2(randf_range(-30.0, 30.0), randf_range(-15.0, 15.0))
	accel = randf_range(900.0, 1500.0)
	max_hp = hp
	setup()


# --- háčky pro odvozené typy ---
func setup():
	pass

func behave(_delta):
	pass

func on_damaged():
	pass

func on_death():
	pass


func _physics_process(delta):
	t += delta
	stun -= delta
	if stun > 0 or player == null or player.dead:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	else:
		velocity = velocity.move_toward(desired_velocity(delta), accel * delta)

	move_and_slide()

	# když narazí do bloku, začne ho obcházet bokem (směrem k hráči)
	wall_steer = wall_steer.move_toward(Vector2.ZERO, 2.0 * delta)
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is StaticBody2D and player:
			var tangent = c.get_normal().orthogonal()
			if tangent.dot(player.global_position - global_position) < 0:
				tangent = -tangent
			wall_steer = tangent

	# dotyk s hráčem
	if contact_heat > 0:
		for b in hitbox.get_overlapping_bodies():
			if b.has_method("hit"):
				b.hit(contact_heat, global_position)

	behave(delta)


# výchozí chování: honit hráče
func desired_velocity(_delta) -> Vector2:
	var desired = chase_dir() * ISO * speed
	desired += separation() * speed * separation_force
	desired += wall_steer * speed
	return desired


# směr k hráči v "herních" souřadnicích (normalizovaný)
func chase_dir() -> Vector2:
	if player == null:
		return Vector2.ZERO
	var to = player.global_position + target_offset - global_position
	var w = Vector2(to.x, to.y * 2.0)
	return w.normalized() if w.length() > 8.0 else Vector2.ZERO


# vzdálenost v "herních" souřadnicích
static func iso_dist(a: Vector2, b: Vector2) -> float:
	var d = a - b
	return Vector2(d.x, d.y * 2.0).length()


# odtlačování od ostatních nepřátel
func separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var d = global_position - other.global_position
		var w = Vector2(d.x, d.y * 2.0)
		var l = w.length()
		if l < separation_dist:
			var n = w / l if l > 0.1 else Vector2.RIGHT.rotated(get_instance_id() % 628 / 100.0)
			push += n * (1.0 - l / separation_dist)
	return push.limit_length(1.0) * ISO


func world_node():
	var w = get_tree().get_first_node_in_group("world")
	return w if w else get_tree().current_scene


# vystřelí žhavou kouli (vel = rychlost na obrazovce)
func shoot_orb(vel: Vector2, heat := 12.0):
	var o = HEAT_ORB.instantiate()
	o.velocity = vel
	o.heat = heat
	o.global_position = global_position + vel.normalized() * 14.0
	world_node().add_child(o)


# odhození (vent)
func knockback(force: Vector2):
	if knock_resist >= 1.0:
		return
	velocity = force * (1.0 - knock_resist)
	stun = 0.35 * (1.0 - knock_resist)


func take_damage(amount):
	if hp <= 0:
		return                  # už je mrtvý (víc střel v jednom snímku)
	hp -= amount
	body.modulate = FLASH
	create_tween().tween_property(body, "modulate", Color.WHITE, 0.15)
	on_damaged()
	if hp <= 0:
		die()
	else:
		Juice.play("enemy_hit", -10.0)


func die():
	Juice.play("enemy_die", -4.0)
	Juice.burst(global_position + Vector2(0, -12), burst_color)
	Juice.shake(0.15)
	Juice.hitstop(0.03)
	died.emit(global_position, score_value, drops)
	on_death()
	queue_free()
