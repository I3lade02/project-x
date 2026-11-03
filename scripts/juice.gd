extends Node

const SOUNDS = {
	"shoot": preload("res://sounds/shoot.wav"),
	"jam": preload("res://sounds/jam.wav"),
	"jump": preload("res://sounds/jump.wav"),
	"hurt": preload("res://sounds/hurt.wav"),
	"crash": preload("res://sounds/crash.wav"),
	"reboot": preload("res://sounds/reboot.wav"),
	"blast": preload("res://sounds/blast.wav"),
	"enemy_hit": preload("res://sounds/enemy_hit.wav"),
	"enemy_die": preload("res://sounds/enemy_die.wav"),
	"pickup": preload("res://sounds/pickup.wav"),
	"wave_clear": preload("res://sounds/wave_clear.wav"),
	"upgrade": preload("res://sounds/upgrade.wav"),
	"click": preload("res://sounds/click.wav"),
	"warn": preload("res://sounds/warn.wav"),
	"game_over": preload("res://sounds/game_over.wav"),
}
const POOL_SIZE = 16

var players := []
var next := 0
var hitstop_count := 0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	# každé tlačítko ve hře dostane zvuk kliknutí
	get_tree().node_added.connect(_on_node_added)


# přehraje zvuk (s lehce náhodnou výškou, ať to neotravuje)
func play(sound_name, volume_db := 0.0, pitch_var := 0.1):
	if not SOUNDS.has(sound_name):
		return
	var p = players[next]
	next = (next + 1) % POOL_SIZE
	p.stream = SOUNDS[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


# třes kamery (0.0 až 1.0)
func shake(amount):
	get_tree().call_group("camera", "shake", amount)


# krátké "zamrznutí" hry pro pocit síly zásahu
func hitstop(duration):
	hitstop_count += 1
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	hitstop_count -= 1
	if hitstop_count <= 0:
		hitstop_count = 0
		Engine.time_scale = 1.0


# výbuch částic na pozici
func burst(pos, color, amount := 14):
	var scene = get_tree().current_scene
	if scene == null:
		return
	var p = CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = color
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	scene.add_child.call_deferred(p)


func _on_node_added(node):
	if node is BaseButton:
		node.pressed.connect(func(): play("click", -6.0, 0.05))
