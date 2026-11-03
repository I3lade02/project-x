extends CharacterBody2D

signal died(pos)

const GRAVITY = 1400.0
const JUMP = -650.0
const PLATFORM_LAYER = 5        # vrstva proskočitelných plošin
const DROP_TIME = 0.25          # jak dlouho padá skrz plošinu
const SEPARATION_DIST = 34.0    # min. rozestup mezi bugy
const SEPARATION_FORCE = 0.8
const COLOR = Color(0.3, 0.9, 0.4)

var speed := 120.0
var hp := 3
var contact_heat := 20.0
var jump_cd := 0.0
var drop_timer := 0.0
var target_offset := 0.0        # každý bug míří kousek vedle hráče
var accel := 1200.0
var player

@onready var body = $Body
@onready var hitbox = $Hitbox


func _ready():
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	# trochu jiný každý bug
	speed *= randf_range(0.85, 1.15)
	target_offset = randf_range(-30.0, 30.0)
	accel = randf_range(900.0, 1500.0)


func _physics_process(delta):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	jump_cd -= delta
	drop_timer -= delta
	set_collision_mask_value(PLATFORM_LAYER, drop_timer <= 0)

	var desired_x := 0.0
	if player:
		var dx = player.global_position.x + target_offset - global_position.x
		var dy = player.global_position.y - global_position.y
		if abs(dx) > 6:
			desired_x = sign(dx) * speed

		if is_on_floor():
			# hráč je pod námi -> propadni plošinou
			if dy > 60:
				drop_timer = DROP_TIME
			# hráč je nad námi nebo narazil do zdi -> skoč
			elif jump_cd <= 0 and (dy < -80 or is_on_wall()):
				velocity.y = JUMP
				jump_cd = randf_range(0.8, 1.6)

	desired_x += separation() * speed * SEPARATION_FORCE
	velocity.x = move_toward(velocity.x, desired_x, accel * delta)

	move_and_slide()

	# dotyk s hráčem
	for b in hitbox.get_overlapping_bodies():
		if b.has_method("hit"):
			b.hit(contact_heat, global_position.x)


# odtlačování od ostatních bugů (-1 až 1)
func separation():
	var push := 0.0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var d = global_position - other.global_position
		if abs(d.x) < SEPARATION_DIST and abs(d.y) < 30:
			var side = sign(d.x)
			if side == 0:
				side = 1 if get_instance_id() > other.get_instance_id() else -1
			push += side * (1.0 - abs(d.x) / SEPARATION_DIST)
	return clamp(push, -1.0, 1.0)


func take_damage(amount):
	if hp <= 0:
		return                  # už je mrtvý (víc střel v jednom snímku)
	hp -= amount
	body.color = Color.WHITE
	create_tween().tween_property(body, "color", COLOR, 0.15)
	if hp <= 0:
		Juice.play("enemy_die", -4.0)
		Juice.burst(global_position, COLOR)
		Juice.shake(0.15)
		Juice.hitstop(0.03)
		died.emit(global_position)
		queue_free()
	else:
		Juice.play("enemy_hit", -10.0)
