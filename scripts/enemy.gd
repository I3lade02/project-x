extends CharacterBody2D

signal died(pos)

const GRAVITY = 1400.0
const JUMP = -650.0

var speed := 120.0
var hp := 3
var contact_heat := 20.0
var jump_cd := 0.0
var player

@onready var body = $Body
@onready var hitbox = $Hitbox


func _ready():
	player = get_tree().get_first_node_in_group("player")


func _physics_process(delta):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if player:
		var dx = player.global_position.x - global_position.x
		velocity.x = sign(dx) * speed if abs(dx) > 4 else 0.0

		# skok, když je hráč výš nebo narazí do zdi
		jump_cd -= delta
		var player_above = player.global_position.y < global_position.y - 80
		if is_on_floor() and jump_cd <= 0 and (player_above or is_on_wall()):
			velocity.y = JUMP
			jump_cd = randf_range(0.8, 1.6)

	move_and_slide()

	# dotyk s hráčem
	for b in hitbox.get_overlapping_bodies():
		if b.has_method("hit"):
			b.hit(contact_heat, global_position.x)


func take_damage(amount):
	hp -= amount
	body.color = Color.WHITE
	create_tween().tween_property(body, "color", Color(0.3, 0.9, 0.4), 0.15)
	if hp <= 0:
		died.emit(global_position)
		queue_free()
